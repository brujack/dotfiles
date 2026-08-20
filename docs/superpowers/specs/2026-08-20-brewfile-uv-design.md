# Adding `uv` to the Brewfile — Design

**Date:** 2026-08-20
**Status:** Approved
**Scope:** one `Brewfile` line, one test pair, one recorded version-policy decision.

## Context

This is **step 1 of five** in ai-config's rewritten Python dependency management design
(`ai-config/docs/superpowers/specs/2026-08-20-python-dependency-management-v2-design.md`), and
the only step unblocked today. The remaining four are named here for context and are explicitly
**not** in this spec's scope:

2. delete `wheel` from the venv package list
3. rehearse `uv sync` against the real `~/.pyenv/versions/ansible`
4. `pyproject.toml` with `[dependency-groups]` + `uv.lock`
5. `-t update` applies the lock instead of `pip install -U`

The problem the parent design addresses is measured and not restated here: an unpinned
41-package list duplicated in three places, a daily `pip install -U` loop that resolves
*backwards* to satisfy an over-constrained set, and two development machines sitting in two
different stable states.

`uv` is the locker that design selects. It is a **local-only** tool: the other repos consume an
exported hashed `requirements.txt` (`uv export --format requirements-txt`) which plain `pip`
installs, so no CI runner needs `uv`.

### What is deliberately absent, and why

Earlier iterations of the parent design proposed a **pipx "cabinet"** isolating standalone CLIs,
and **PATH work** to make that cabinet reachable. Both are dropped. The cabinet's central claim
was measured away by external adversarial review: **pipx relocates `ecdsa` rather than removing
it** — `checkov` requires `ecdsa<1.0.0,>=0.19.0`, so an isolated checkov installs it too. The
shared venv goes green because the package left the *audit*, not the *machine*. With the cabinet
gone, the PATH work it required goes with it.

## Decision

**Two edits, not one — the Brewfile alone installs on macOS only.**

The scope as originally relayed was a single `Brewfile` line. That is insufficient: **Linux does
not consume the Brewfile.** `brew bundle --file .../Brewfile` is called from `lib/macos.sh:193`
only, while Ubuntu installs from a hardcoded list of `brew_install_formula` calls in
`_install_ubuntu_brew_packages()` (`lib/linux_ubuntu.sh:329`). A Brewfile-only change would
install `uv` on the Studio and silently not on the Linux 7950X — the second of the two
load-bearing machines, and the one the parent design's `uv sync` rehearsal will eventually run
against.

1. `Brewfile`, beside the existing Python tooling:

```ruby
brew "uv"                                    # [HAS_DEVTOOLS]
```

2. `lib/linux_ubuntu.sh`, in `_install_ubuntu_brew_packages()`, alphabetically:

```bash
brew_install_formula uv
```

**This is the established both-platforms pattern, not a new one.** Measured: `pyenv`,
`pyenv-virtualenv`, `fzf`, `gh`, `neovim` and `ripgrep` each appear in *both* the `Brewfile`
and the Linux list. `uv` is the same shape as `pyenv` — a Python-toolchain binary needed on
every development machine — and follows it exactly.

**A pre-existing asymmetry this change inherits and does not fix.**
`_install_ubuntu_brew_packages` carries no `HAS_*` gating (the guards in that file sit at
`:248`, `:260` and `:368`, around other functions), so the Linux side installs its whole list
unconditionally for any machine running the developer workflow, while the macOS side is
capability-tagged. `uv` inherits that asymmetry exactly as `pyenv` already does. Normalising it
is out of scope here — it would touch every formula in that list, not just this one.

### Why `[HAS_DEVTOOLS]`, and why that is correct rather than merely conventional

124 of 194 Brewfile entries carry a `[HAS_*]` capability guard, and `pyenv`,
`pyenv-virtualenv` and `python@3.13` all carry `[HAS_DEVTOOLS]`. Following that convention is
the obvious move, but the stronger reason is that **`HAS_DEVTOOLS` is the same gate that decides
whether the ansible venv exists at all** — `run_update`'s pip section is gated on it. So `uv`
ships exactly where the thing it manages ships, and is withheld from `mac_mini`, which has no
devtools and no venv for a locker to act on.

### Version policy: unpinned, and this is a decision rather than an omission

`-t update` reaches `brew upgrade --yes`, so **drift is real, not theoretical**: both machines
track whatever brew's `uv` currently is, and they update on different days. Call chain verified
rather than inferred from a grep: `lib/workflows.sh:298` calls `brew_update`
(`lib/helpers.sh:70`), whose body runs `brew upgrade --yes` at `:89`.

Three options were considered and two rejected on measurement:

| option | verdict |
| --- | --- |
| **Unpinned `brew "uv"`** | **Chosen.** |
| Pinned binary via the GitHub-release pattern (`UV_VER` in `lib/constants.sh`, checksum-verified, as for `gitleaks`/`cf-terraforming`) | Rejected *for now* — real machinery, and it guarantees convergence, but it is disproportionate before the artifact it protects exists. |
| `brew install` + `brew pin uv` | **Rejected outright.** `brew pin` freezes whatever each machine already installed, so if the Studio installs 0.12.5 today and the workstation installs 0.13.0 next month, pinning both *preserves* the divergence rather than preventing it — the opposite of the intent. This repo also has **zero** existing `brew pin` usages. |

Brew's own version-pinning mechanism — the `python@3.13` / `postgresql@15` pattern — is
**unavailable**: `brew search /^uv/` returns bare `uv` only, with no `uv@x.y` formula.

**The accepted risk, stated plainly.** A newer `uv` can change `uv.lock` format or resolution
semantics, and the two machines can therefore diverge on the *locker* even once the *lock* is
pinned. That risk is **not live until step 4**, because `uv.lock` does not exist yet. Revisit at
step 4, when drift can actually bite, at which point the pinned-binary option above is the
prepared answer. Reversing this decision costs one line plus an install function.

## Testing

A **pair** of cases in `tests/setup_env/brewfile_drift.bats`, both reading the real `Brewfile`
via `${REPO_ROOT}`, following the existing precedent at line 510 (`bats-core` present,
`azure-cli` absent):

1. `_brewfile_parse_section brew` with `HAS_DEVTOOLS=1` yields `uv`
2. `_brewfile_parse_inactive brew` with all `HAS_*` unset yields `uv`

**The pair is the design, not two spellings of one test.** Case 1 alone passes whether or not
the entry carries a capability tag, so it proves presence but not gating. Case 2 fails unless
the entry is *both* present *and* tagged. Together they pin that `uv` ships on developer
machines and is withheld elsewhere.

And a third case in `tests/setup_env/linux_ubuntu.bats`, following the existing
`_install_ubuntu_brew_packages: installs pyenv via brew` precedent at `:124`:

3. `_install_ubuntu_brew_packages` calls `brew_install_formula uv`

**Without case 3 the macOS pair passes on a change that ships to one machine.** That is the
defect this spec's own first draft contained, and the test that would have caught it.

## Verification

- `make test` green, `make lint` rc 0.
- `uv` installed and resolvable on **both load-bearing machines** (Mac Studio, Linux 7950X), by
  the path each platform actually uses: `brew bundle` from the Brewfile on macOS,
  `_install_ubuntu_brew_packages` on Linux. Verifying only the machine you are sitting at would
  pass on the one-edit version of this change, which installs on macOS alone.
- Reachable by the actor that runs `-t update`.

**The actor question is already resolved and introduces no new hazard.** Measured per machine,
because the two use different prefixes and an earlier draft of this spec stated a Studio-only
measurement as a general claim:

| machine | brew prefix | on non-interactive PATH? | `uv` available |
| --- | --- | --- | --- |
| Mac Studio | `/opt/homebrew` | no (`env -i`); yes for agent shells and interactive zsh | 0.12.5 bottled |
| Linux 7950X | `/home/linuxbrew/.linuxbrew` | **no** — `ssh workstation 'command -v brew'` finds nothing | 0.12.5 bottled (Homebrew 6.0.18) |

However `setup_env.sh:30` gates every workflow on `env which brew` and exits with an error
without it.
So `uv`'s reachability is **exactly coextensive with `setup_env.sh`'s own precondition**: any
actor that can run the entry point at all can find `uv`, and any actor that cannot was already
blocked before `uv` existed. This fleet's documented case of `setup_env.sh` being unrunnable
non-interactively on the workstation is that same pre-existing precondition, not a new
consequence of this change — and the table above is its direct measurement: brew is absent from
that machine's non-interactive PATH, which is *why* the entry point refuses there.

**Consequence for installation.** Because brew is not on the workstation's non-interactive PATH,
installing `uv` there via `ssh` requires prepending the prefix explicitly
(`PATH=/home/linuxbrew/.linuxbrew/bin:$PATH`) rather than relying on `ssh workstation 'brew …'`,
which fails with command-not-found.

## Out of scope

No CI change. No `pipx`. No PATH work. No `pyproject.toml`, no `uv.lock`, no `-t update`
integration — those are steps 3–5 of the parent design and each needs its own cycle.
