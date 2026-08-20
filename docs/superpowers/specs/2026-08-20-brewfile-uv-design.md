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

**The Linux line is not merely completeness — without it the change actively degrades the daily
loop.** `_update_check_brewfile_drift` is called **unconditionally** from `run_update`
(`lib/workflows.sh:640`); only its *cask* arm is macOS-gated (`lib/update_summary.sh:694`,
`:717`). And `HAS_DEVTOOLS` is set for four profiles, **two of which are not macOS**:
`personal_laptop`, `mac_workstation`, `linux_workstation`, `wsl2_workstation`. So a
Brewfile-only `uv` lands in the *active expected* set on both non-mac devtools machines, nothing
installs it, and `-t update` reports `brew-drift WARN → Missing (in Brewfile, not installed)`
**on every run, permanently, with no self-heal path** — `brew_update` runs `brew upgrade --yes`,
which upgrades installed formulae and installs nothing new. A gate that fires forever on correct
state is how a check gets ignored.

**A pre-existing asymmetry this change inherits and does not fix.**
`_install_ubuntu_brew_packages` carries no `HAS_*` gating (the guards in that file sit at
`:248`, `:260` and `:368`, around other functions), so the Linux side installs its whole list
unconditionally for any machine running the developer workflow, while the macOS side is
capability-tagged. `uv` inherits that asymmetry exactly as `pyenv` already does. Normalising it
is out of scope here — it would touch every formula in that list, not just this one.

### Why `[HAS_DEVTOOLS]` — by convention, and the tag does NOT gate installation

124 of 194 Brewfile entries carry a `[HAS_*]` guard (denominator stated because it matters:
194 = 127 `brew` + 59 `cask` + 8 `tap`; including the 15 `mas` lines gives 209 and a different
ratio). `pyenv`, `pyenv-virtualenv` and `python@3.13` all carry `[HAS_DEVTOOLS]`, and `uv` is
the same shape as `pyenv` — a Python-toolchain binary wanted on every development machine.

**An earlier draft of this spec claimed a stronger reason and it was false.** It argued the tag
ships `uv` "exactly where the thing it manages ships" and withholds it from `mac_mini`. It does
not. The tag is a trailing Ruby comment; `brew bundle` never sees it. `lib/macos.sh:193` bundles
the main `Brewfile` **unconditionally** — only the supplementary `Brewfile.gui` (`:195`) and
`Brewfile.devtools` (`:198`) sit behind capability guards. Proven:

```
$ printf 'brew "uv"   # [HAS_DEVTOOLS]\n' | ruby -e 'def brew(n,**k); puts n; end; eval(STDIN.read)'
uv
```

**What the tag actually does is decide what `brew-drift` expects**, not what installs. So
`mac_mini` will receive `uv`, exactly as it already receives `pyenv`, `python@3.13`, `azure-cli`
and `bun`. That is acceptable — a bottled binary sitting unused on a machine with no venv — and
it is the same treatment its closest analogue already gets. Real install-gating lives in
`Brewfile.devtools` (22 entries), which is genuinely guarded; using it here would trade
install-gating for drift coverage, since the drift check reads only the main `Brewfile`.

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
| `brew install` + `brew pin uv` | **Rejected**, but not for the reason an earlier draft gave. That draft argued pinning "preserves divergence" — refuted by this spec's own table, which puts both machines at 0.12.5 *today*, so pinning both now would converge. The correct reason is stronger: **a `Brewfile` cannot express a pin** (`brew bundle` has no pin directive), and pin state lives in `$(brew --prefix)/var/homebrew/pinned` — machine-local, untracked, invisible to the repo. Verified: that directory does not exist on the Studio, so there are zero pins fleet-wide. It is precisely the undeclared per-machine state the profile model exists to eliminate. |

Brew's own version-pinning mechanism — the `python@3.13` / `postgresql@15` pattern — is
**unavailable**: `brew search /^uv/` returns bare `uv` only, with no `uv@x.y` formula.

**The accepted risk, and a correction to how an earlier draft bounded it.** A newer `uv` can
change `uv.lock` format or resolution semantics, so the two machines can diverge on the *locker*
even once the *lock* is pinned.

That draft said the risk is "not live until step 4, because `uv.lock` does not exist yet."
**That is false, and the step it misses is step 3.** Step 3 rehearses `uv sync` against the real
`~/.pyenv/versions/ansible` — before any lock exists — and two harms are available there:

1. **`uv sync` prunes by default**, removing packages present in the environment but absent from
   the project. Rehearsing that against the operator's live 41-package working venv, with a tool
   whose sync semantics have moved across releases, is a live risk now rather than at step 4.

   Verified from uv's own documentation rather than taken from review: *"`uv sync` performs
   'exact' syncing by default, which means it will remove any packages that are not present in
   the lockfile"* (`docs.astral.sh/uv/concepts/projects/sync/`). **And the obvious mitigation is
   incomplete** — the CLI reference states: *"Use the `--inexact` flag to keep extraneous
   packages. Note that if an extraneous package conflicts with a project dependency, it will
   still be removed."* The ansible venv's defining problem is conflicting constraints, so
   conflicting extraneous packages are exactly the population at risk, and `--inexact` does not
   protect them. Step 3 needs a disposable copy of the venv, not the real one, or it needs to
   accept that a conflicting package can be removed from the operator's daily working
   environment.
2. **The artifact under protection at step 3 is the _measurement_, not the lock.** The
   rehearsal's output is what decides step 4's design. If the Studio rehearses under one `uv`
   and the workstation under another — which follows directly from `brew upgrade --yes` running
   on two different schedules — the rehearsals are not comparable and step 4 gets built on a
   comparison that was never valid.

**The deferral still stands, on the reason that survives:** reversing it costs one line plus an
install function, and the pinned-binary machinery is disproportionate before anything consumes
`uv`. But the pin decision belongs **before step 3's rehearsal**, not after it, and the cheapest
adequate form is pinning both machines to the same `uv` for the rehearsal's duration and
recording the version beside each result.

**The deferral has no mechanism, so it needs a destination rather than a sentence.** Nothing in
this repo can observe `uv` version drift: `brew-drift` compares formula *names* through `comm`
over sorted lists, so a version delta is structurally invisible to it, and `-t check-versions`
reads pinned constants in `lib/constants.sh`, which this decision deliberately leaves without a
`UV_VER`. A revisit that depends on a human recalling one sentence in a four-steps-stale spec is
a deferral that gets *discovered*, and it gets discovered as a lockfile disagreement — the worst
place to learn it. A backlog row in `docs/superpowers/README.md` carries it instead.

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

**Two implementation details, both from review and both load-bearing:**

- Case 1 must `unset "${!HAS_@}"` *before* exporting `HAS_DEVTOOLS=1` — the precedent at `:510`
  does this. Without it an ambient capability from the developer's own shell can satisfy the
  assertion, and a mis-tagged entry passes.
- Use `grep -qx 'uv'`, not a substring match. `uv` appears nowhere in the `Brewfile` as a
  substring today (`grep -n 'uv' Brewfile` → rc 1), so a substring assertion is unambiguous
  *now* and quietly stops being so the day someone adds a formula containing those two letters.

**A reviewer disagreement, resolved by mutation rather than by preference.** One lens argued the
macOS pair cannot distinguish `[HAS_DEVTOOLS]` from any other tag (case 2 unsets *all* `HAS_*`,
so `[HAS_GUI]` would satisfy it identically) and wanted a fourth case copied from `:528`.
Another walked the mutation table and found the pair already covers every degenerate direction:

| mutation | case 1 | case 2 |
| --- | --- | --- |
| capability extractor always returns empty | pass | **fail** |
| indirection always reads SET (include everything) | pass | **fail** |
| indirection always reads UNSET (drop all tagged) | **fail** | pass |

The mutation table is evidence and the tag-identity objection is a reading, so the pair stands.
The objection is not worthless though: it is correct that neither case pins the tag's *identity*,
only that *a* tag is present and honoured. That is acceptable here because the tag does not gate
installation anyway — it selects drift expectations — so a wrong-but-present tag is a
drift-reporting bug, not a delivery bug.

## Verification

- `make test` green, `make lint` rc 0.
- `uv` installed and resolvable on **both load-bearing machines** (Mac Studio, Linux 7950X), by
  the path each platform actually uses: `brew bundle` from the Brewfile on macOS,
  `_install_ubuntu_brew_packages` on Linux. Verifying only the machine you are sitting at would
  pass on the one-edit version of this change, which installs on macOS alone.

**One verification bullet is not falsifiable as written, and is replaced.** "`uv` installed and
resolvable on both machines" is satisfiable *by hand* — which is exactly how it would be
satisfied on the workstation — so it cannot falsify the proposition it appears to gate, namely
*that the repo's own install path delivers `uv`*. That is `behavior.md`'s "a check derived from
the same decision as the thing it checks." The falsifying form costs one command: **on a machine
where `uv` is not yet installed, run `-t update` and assert `brew-drift` reports clean.** A
hand-installed `uv` passes the old bullet and fails this one if the repo path is broken.
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
An earlier draft claimed `uv`'s reachability is "exactly coextensive with `setup_env.sh`'s own
precondition." **It is not, and the two propositions are different**: the precondition proves
*the brew prefix is on PATH*, not *that `uv` is installed*. Two actor classes pass the
precondition and still find no `uv`:

- **Any mac between this line landing and the next `-t setup --brew-install`** — `-t update`
  alone runs `brew upgrade --yes`, which upgrades installed formulae and installs nothing new.
- **Any Linux/WSL2 devtools machine**, until the `_install_ubuntu_brew_packages` line below
  lands — brew resolves there, but `brew bundle` never runs.

What *is* true, and is the weaker claim worth keeping: this change adds no **new** PATH hazard.
Any actor that cannot find brew was already blocked at `setup_env.sh:30` before `uv` existed. This fleet's documented case of `setup_env.sh` being unrunnable
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
