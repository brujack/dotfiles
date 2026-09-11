# Add the `claude` Linux workstation to the identity table — Design

## Problem

A new Linux box, hostname `claude`, is joining the fleet as the Claude development machine.
It has no entry in `config/profiles.sh`, so every identity derivation resolves it to the
unmapped case: `PROFILE=unknown`, zero `HAS_*` variables, no legacy identity variable, and
`setup_env.sh -t doctor` fails naming the hostname (`lib/helpers.sh:400`). That is the
designed behaviour for an unknown host, not a bug — it is what this change closes.

Measured on the box by the ansible session over ssh, 2026-09-11:

| property                      | value                                                                             |
| ----------------------------- | --------------------------------------------------------------------------------- |
| `hostname -s` / `hostname -f` | `claude` — no domain suffix                                                       |
| OS                            | Ubuntu 26.04, `VERSION_CODENAME=resolute`, kernel 7.0.0-31-generic, x86_64        |
| live network                  | `bond0` over `enp74s0f0` + `enp74s0f1`                                            |
| wireless                      | `wlo2` exists with `phy80211`, is DOWN, and neither `iw` nor `nmcli` is installed |
| snap                          | present, snapd 2.76.3+ubuntu26.04                                                 |
| flatpak                       | absent                                                                            |
| provisioning state            | nothing yet: no docker, no ledger, no make, no `~/.config/dotfiles/machine-id`    |

The box is intended to become the machine every session runs on, taking that role from the
Mac Studio and the `workstation` 7950X. `workstation` stays in the fleet and keeps its
entries: it becomes an additional GitHub runner, so the fleet ends with two runner servers,
`workstation` and `claude`. Both are `linux_workstation`, which already carries `docker`, so
running a runner needs nothing from this change.

## Scope

In: the dotfiles identity table, the tests that derive from it, the dotfiles `CLAUDE.md`
statements this change makes false, and the ai-config `USER.md` machine list.

**The ownership boundary, stated because it decides every "out" below.** All development
setup on `claude` comes from dotfiles — shells, symlinks, toolchains, the pyenv `ansible`
venv, git hooks. Ansible provisions exactly one thing there, the GitHub runner. So a
prerequisite that only the runner role needs belongs to that role, and this change is the
prerequisite for running `setup_env.sh` on the box at all: until `claude` is in
`PROFILE_MAP`, every workflow there resolves `PROFILE=unknown` with zero `HAS_*`.

Out, each with its owner:

- **`acl` and `python3-venv` in `ubuntu_common_packages.txt`** — requested by the ansible
  session for its runner role. Their own change, by the operator's decision.
  `python3-venv` is additionally not a dotfiles need: `setup_ansible`
  (`lib/developer.sh:464`) creates the venv with
  `pyenv virtualenv "${PYTHON_VER}" ansible` (`:523`, `:549`) and installs with
  `uv sync --frozen`; `git grep python3-venv` returns nothing in this repo.
- **The GitHub runner on `claude`** — provisioned by terraform_ansible's `github_runner`
  role, which is already adding the host on that side. dotfiles supplies what the role
  expects to find (docker, ledger) through ordinary development setup, not for the runner's
  sake.
- **Session-placement claims in `USER.md`** — deferred until the box actually hosts
  sessions. It is unprovisioned today, so a file saying sessions run there would be false.
- **`lib/legacy_rsync.sh` targets** — studio pushes to `workstation`, `laptop-1` and `ratna`
  and keeps doing so. `claude` gets repos through the git-native arm like any dev machine.

## Design

### 1. Identity entries

Two lines in `config/profiles.sh`:

```bash
[claude]="linux_workstation"   # PROFILE_MAP
[claude]="WORKSTATION"         # PROFILE_LEGACY
```

No `PROFILE_CAPS` change: `linux_workstation` already carries
`gui devtools aws k8s docker rust snap flatpak`, which is the "exact same profile as
workstation" requirement in full.

**Reusing `WORKSTATION` rather than minting a `CLAUDE` variable is the load-bearing
choice.** Two live consumers branch on the legacy variable rather than on a capability:
`.zprofile:10` (`WORKSTATION || CRUNCHER`, rbenv init) and
`.config/.zshrc.d/7_final.zsh:60` (the eight-name list that activates the `ansible` pyenv
venv). Reuse means both work on `claude` with no edit. A new variable would need those two
lines plus every test isolation line that enumerates the legacy names by hand — 42 lines
across 4 bats files, measured with `git grep -cI 'WORKSTATION' -- tests`
(`tests/setup_env/profiles.bats` 8, `tests/zshrc.d/unit.bats` 23,
`tests/zshrc.d/profiles.bats` 7, `tests/zshrc.d/cross_shell.bats` 4) — or the new variable
leaks between tests and those two branches silently skip on the new machine.

The cost, stated rather than discovered later: no consumer can distinguish `claude` from
`workstation` by legacy variable. Only `hostname -s` separates them. Nothing in the repo
needs that distinction today — the only host-keyed literals left in `lib/` are `studio` and
`studio-1` (`lib/legacy_rsync.sh:5`, `lib/launch_agents.sh:149`), measured by grepping `lib`, `scripts`, `config`, `.config` and `.zprofile` for quoted
hostname literals — `tests/` and `docs/` were outside that population and do contain
more.

**Ubuntu 26.04 needs nothing.** `detect_env` sets `RESOLUTE` from `lsb_release -rs`, and
`lib/linux_ubuntu.sh` already has the 26.04 arm installing `ubuntu_common_packages.txt` plus
`ubuntu_2604_packages.txt`.

**flatpak being absent is an unprovisioned box, not a profile difference.** `flatpak` is a
line in `ubuntu_workstation_packages.txt`, which installs under `HAS_SNAP`
(`lib/linux_ubuntu.sh:39-46`); `HAS_FLATPAK` gates only the Steam flathub install at `:431`.
snap is present, so the package install path works.

### 2. Wired-only, and the exemption it requires

`claude` gets one entry per table, with no `claude-1` twin — matching `workstation` and
`cruncher`, which `config/profiles.sh:19` records as wired-only by design. The box has
wireless hardware but nothing manages it, and it can only report `claude` today.

This is the step the repo's own documentation gets wrong.
`tests/setup_env/profiles.bats:292` asserts every wired `PROFILE_MAP` key has a `-1` twin on
the same profile, and exempts hosts through a hand-typed set at `:296`:

```bash
local -A wired_only=([workstation]=1 [cruncher]=1)
```

A wired-only host added without joining that set fails the suite. So a wired-only machine
costs **4 edits across 3 files**, not the 3 across 2 that `CLAUDE.md`'s "Adding a New
Machine" claims.

**The risk this accepts:** if anything ever brings `wlo2` up and the box reports `claude-1`,
that hostname is unmapped and the machine loses `PROFILE` and every `HAS_*` at once. The
twin rule exists for exactly that failure. It is accepted because no software on the box
manages the interface, and the ansible session has been asked to say if that changes.

### 3. Tests

- `tests/helpers/legacy_oracle.bash` gains a `claude)` arm returning `WORKSTATION`. The
  oracle is hand-typed on purpose (ADR-0021) and its `*)` arm fails loudly, so a host added
  to `PROFILE_MAP` without an arm here turns the suite red rather than going untested.
- `tests/setup_env/profiles.bats:296` gains `[claude]=1` in `wired_only`.
- **A new test asserting `claude` and `workstation` resolve identically** — same `PROFILE`,
  same full `HAS_*` set, same legacy variable, via the existing `_profile_snapshot` helper
  that the `studio`/`studio-1` case at `:315` already uses. Nothing in the suite currently
  asserts that two hosts are equivalent, and "the exact same profile as workstation" is the
  requirement this change exists to satisfy. Written RED first, against the table with no
  `claude` entry.
- `tests/zshrc.d/profiles.bats` carries two comments reading "all 13 PROFILE_MAP keys" and
  "today's 13 hosts". A 14th key makes both stale. The numbers go; the derivation they
  describe stays.

Everything else is already derived from `"${!PROFILE_MAP[@]}"` and covers the new host with
no edit: the bash and zsh per-host loops, the key↔legacy parity tests at `:432` and `:469`,
and the cross-shell equivalence test. The `no_legacy` exception set in
`tests/zshrc.d/profiles.bats:120` stays empty, because `claude` does have a legacy variable.

The set-equality test at `tests/setup_env/profiles.bats:485` ("PROFILE_LEGACY values are
exactly the eight legacy identity variable names") stays green by construction: reusing
`WORKSTATION` adds a key, not a value.

### 4. dotfiles `CLAUDE.md` corrections

- **The Key Conventions bullet (line 849 at `cf259c28`) is false, and this change makes it
  more misleading.** It says `WORKSTATION` and
  `CRUNCHER` "have been removed; use `HAS_*` vars instead". Both are live in
  `PROFILE_LEGACY` (`config/profiles.sh:62-63`) and read by `.zprofile:10`. Corrected to
  describe the table as it is.
- **The Profile Model paragraph** (line 1051 at `cf259c28`) names `workstation` and `cruncher` as the wired-only hosts; `claude` joins
  that list.
- **"Adding a New Machine"** says 3 edits across 2 files. That holds for a host with a twin
  and is wrong for a wired-only one, which also needs the `wired_only` exemption. The
  section gains that step.

### 5. ai-config `USER.md`

The machine list grows to eight, with `claude` as a development machine carrying all repos.
"Harness development happens on exactly two" becomes three, and "six of the seven carry
every repo" becomes seven of the eight. That two-machine line was deliberately narrowed on
2026-08-11, so it is changed knowingly rather than as a typo fix.

The "Session placement" paragraph and `workstation`'s role are left alone until the box
hosts sessions.

## Verification

| check                          | command                                                               | expected                                      |
| ------------------------------ | --------------------------------------------------------------------- | --------------------------------------------- |
| RED before the entries         | the new equivalence test, run on the unmodified table                 | fails: `claude` resolves `PROFILE=unknown`    |
| identity resolves              | `MOCK_HOSTNAME_OUTPUT=claude` through `_profile_snapshot`             | identical to `workstation`'s snapshot         |
| full suite                     | `make test`                                                           | rc 0, run by the pre-push hook                |
| oracle is load-bearing         | delete the `claude)` arm, re-run `bats tests/setup_env/profiles.bats` | red; restores green when replaced             |
| twin exemption is load-bearing | remove `[claude]=1` from `wired_only`, re-run the same file           | red on the twin assertion                     |
| docs                           | `grep -n 'have been removed' CLAUDE.md`                               | no hit for the `WORKSTATION`/`CRUNCHER` claim |

The two mutation checks are the point of the verification table: both edits are one-line
data changes whose absence a green suite would otherwise hide.

## Rejected alternatives

- **Mint a `CLAUDE` legacy variable** — distinguishes the box in legacy terms, costs the two
  startup-file branches plus 42 hand-typed isolation lines, and buys a distinction nothing
  needs.
- **No legacy variable, `HAS_*` only** — the cleanest end state, but `.zprofile`'s rbenv init
  and `7_final.zsh`'s venv activation both branch on legacy variables today, so the new
  machine would silently skip both. Converting those two sites to capability tests is a
  separate change with its own risk.
- **Add the `claude-1` twin defensively** — two extra lines and no exemption edit, and it
  would remove the unmapped-hostname risk entirely. Rejected by the operator on the
  `workstation`/`cruncher` precedent and the measured fact that nothing manages `wlo2`.
- **Fold `acl`/`python3-venv` in** — they apply to every Ubuntu machine, not just this one,
  and belong in a change that says so.
