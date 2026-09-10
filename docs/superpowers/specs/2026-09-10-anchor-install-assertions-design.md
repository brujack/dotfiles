# Anchor package-named install assertions

**Date:** 2026-09-10
**Backlog row:** "`grep -q` in `tests/setup_env/linux_ubuntu.bats` lets a real deletion pass"
**Scope:** test files only; no production code changes.

## Problem

Bats tests confirm an install happened by searching the mock call log with a
substring match:

```bash
grep -q "brew install pyenv" "${MOCK_CALLS_FILE}"
```

Every mock appends one line per call (`printf "brew %s\n" "$*"`), so a substring
also matches a longer sibling's line. The pyenv test above also matches
`brew install pyenv-virtualenv`. It cannot fail for the formula it names.

**Measured 2026-09-10** in a `git archive` copy of `bc18bb54` on the Mac Studio,
bats 1.14.0, one test (`installs pyenv via brew`):

| production                           | assertion           | result     |
| ------------------------------------ | ------------------- | ---------- |
| `brew_install_formula pyenv` deleted | `grep -q` (current) | `ok 1`     |
| `brew_install_formula pyenv` deleted | `grep -qx`          | `not ok 1` |
| unchanged                            | `grep -qx`          | `ok 1`     |

The suite already uses the anchored form at `linux_ubuntu.bats:139` (`uv`), which the
backlog row records as killing the `uv`->`uvx` mutant the substring form survives.

## Population

Every site matched by this command at `8e2a7d50`:

```bash
git grep -nE 'grep -qx? "(brew|apt-get|sudo apt-get|snap|pip) install' -- tests
```

36 sites in 7 files. The population is **install-verb assertions only**; see Out of
scope for the wider class.

### Changed: 23 positive assertions naming one package

| file                                     | lines                                                                                                                                                                                                                       |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tests/scripts/unit.bats`                | 499 (`bash`)                                                                                                                                                                                                                |
| `tests/setup_env/install_functions.bats` | 36 (`git`), 69 (`zsh`)                                                                                                                                                                                                      |
| `tests/setup_env/install_guards.bats`    | 54 (`git`), 120 (`apt-get -y bats`), 244, 251, 297 (`make`)                                                                                                                                                                 |
| `tests/setup_env/linux_ubuntu.bats`      | 127 (`pyenv`), 133 (`pyenv-virtualenv`), 247 (`cargo-nextest`), 253 (`cargo-cyclonedx`), 259 (`cyclonedx-python`), 268 (`shfmt`), 393 (`snap install helm`), 428 (`helm`), 434 (`kustomize`), 582 (`bat`), 589 (`ggshield`) |
| `tests/setup_env/macos.bats`             | 133 (`git`), 157 (`zsh`), 198 (`bats-core`)                                                                                                                                                                                 |
| `tests/setup_env/workflows.bats`         | 248 (`apt-get -y bats`)                                                                                                                                                                                                     |

### Not changed: 13 sites, each for a stated reason

- **7 absence checks** — `unit.bats:488`, `install_functions.bats:27`, `:60`,
  `install_guards.bats:68`, `linux_ubuntu.bats:42`, `:596`, `workflows.bats:405`.
  For an absence check the substring is the **stricter** form:
  `! grep -q "brew install git"` also fails on `brew install git-lfs`, while
  `! grep -qx` passes whenever the recorded line differs by one argument. Anchoring
  them would weaken them. All 7 are the last command of their `@test` body, so none
  is inert under shellcheck `SC2314` (checked by scanning each site's next non-blank,
  non-comment line).
- **2 bare-manager checks** — `unit.bats:600` (`apt-get install`),
  `linux_ubuntu.bats:34` (`snap install`). They assert that _some_ install ran. No
  single line exists to anchor to.
- **2 conditions** — `developer.bats:691`, `:711` (`if grep -q "pip install"`). Not
  assertions.
- **1 regex** — `install_functions.bats:534` (`apt-get install.*zlib1g-dev`). A
  pattern over a multi-package line, deliberately unanchored.
- **1 already anchored** — `linux_ubuntu.bats:139` (`uv`).

## Design

Convert each of the 23 sites from `grep -q "<line>"` to `grep -qx "<line>"`.

One site needs its expected line widened, not just anchored. `linux_ubuntu.bats:393`
asserts `snap install helm`, while production runs `sudo snap install helm --classic`
(`lib/linux_ubuntu.sh:178`). It asserts the full line `snap install helm --classic`.
The flag is behaviour, not noise: snap refuses a classic-confinement snap without it.

**The recorded helm line is inferred, not observed.** The probe below shows only that
`-qx "snap install helm"` fails. The first implementation step reads the actual line
from a run before editing the assertion.

### Alternatives rejected

- **A shared `assert_called` helper matching at word boundaries.** Tolerates trailing
  arguments, but needs regex escaping for names such as `python@3.13`, and adds a
  helper for a one-token change per site.
- **Inline word-boundary regex** (`grep -qE "brew install pyenv( |$)"`). Correct, but
  leaves two idioms side by side where one already exists.

### Accepted trade-off

`-qx` fails a correct implementation that adds an argument (for example
`brew install --quiet git`). That is intended: the recorded argv is the behaviour
under test, and the one such case in the population (helm) is handled above.

## Probe

**Measured 2026-09-10** in a `git archive` copy of `8e2a7d50` (no `.git`), Mac Studio,
bats 1.14.0. All 23 sites converted to plain `-qx` (helm not yet widened); the six
files containing them were run.

| file                      | ok  | not ok | cause of failures       |
| ------------------------- | --- | ------ | ----------------------- |
| `install_functions.bats`  | 52  | 0      | —                       |
| `install_guards.bats`     | 92  | 0      | —                       |
| `linux_ubuntu.bats`       | 79  | 1      | helm, as expected above |
| `macos.bats`              | 30  | 0      | —                       |
| `workflows.bats`          | 214 | 0      | —                       |
| `tests/scripts/unit.bats` | 83  | 63     | unrelated — see below   |

All 63 `unit.bats` failures are `run-bash-coverage.sh` tests, which derive their file
set from `git ls-files` and so fail in a copy with no `.git`. Control: the first of
them, `run-bash-coverage.sh instruments every tracked lib/*.sh`, passes when run in
the real worktree. The converted `unit.bats:499` test
(`_bootstrap_mac_install_bash5 installs when bash < 5`) passed in the probe.

The probe is **macOS only**. The Linux-arm tests run on macOS under mocks, so this
covers the assertion form, not platform behaviour. CI (`ubuntu-latest`) is the second
environment.

## Verification

1. **Suite:** `make test` exits 0, and the test count is unchanged (no test is added
   or removed).
2. **Each converted assertion is live:** for each of the 23 sites, delete the
   production install call it names in a scratch copy and run that one test. The
   anchored test must go red at **all 23**. A site that stays green is a finding, not a
   pass.
3. **The change discriminates somewhere:** for the same mutants, record whether the
   _original_ substring form stayed green. At least `linux_ubuntu.bats:127` (`pyenv`)
   must, or the mutation is not exercising the defect. Candidate sibling collisions to
   check: `bat`/`bats-core`, `git`/`git-lfs`, `zsh`/`zsh-autosuggestions`. Record
   the list of sites where the substring form survived; do not predict it.
4. **Population is closed:** after the change, the population command above still
   returns 36 sites. Exactly 24 use `grep -qx` (the 23 plus `uv`), and the 12 that
   still use `grep -q` are the ones listed under Not changed, excluding `uv`, by
   file and line.

At sites with no live sibling collision, both forms go red under deletion. For those
sites the change buys consistency, not new detection. The PR description says so.

## Documentation

- `CLAUDE.md` Testing Rules: one bullet. Assert a recorded mock call with `grep -qx`,
  because a substring matches a longer sibling. Keep absence checks as substring,
  where the substring is the stricter form.
- `docs/superpowers/README.md`: retire the backlog row this closes; add the Out of
  scope row below; reword the inherited-variables row added in `8e2a7d50` from
  `MACOS`/`LINUX`/`HAS_*` to "the variables `detect_env` sets", since the listed names
  omit `UBUNTU`, `PROFILE` and the legacy identity variables.

## Out of scope

- **The wider class.** `git grep -hE 'grep -q[^x]*"[^"]*" "\$\{?MOCK_CALLS_FILE' -- tests`
  returns 397 lines across 16 files at `8e2a7d50`. That count includes the 36 sites
  here, absence checks, and non-install verbs. Same weakness, different commands.
  Recorded as one backlog row, not converted here.
- **Replacing bare `! grep -q` with `refute_grep`.** All install-verb absence checks are
  live today; converting them is a style change with no detection gain.

## Multi-Lens Review

Reviewed at commit: `007590cd` (Step 7 self-review commit, before Step 8 dispatch)

All three lenses independently reproduced the premise: with `brew_install_formula pyenv`
deleted from `lib/linux_ubuntu.sh:352`, the substring test stays green and `-qx` goes
red. Goal-fit extended it to the whole of `linux_ubuntu.bats` (80 ok, 0 not ok with the
install deleted).

### Goal-Fit

Finding: Worth building, but mostly as consistency. By counting substring matches against
exact matches in each converted test's own mock log, **only `linux_ubuntu.bats:127`
(`pyenv`) has a sibling collision**. 19 sites match one line either way. The two
`apt-get -y bats` sites and helm show a second line, but it is the `sudo` mock's own log
entry from the same call, so a deletion removes both. `bat`, `git` and `zsh` never share a
log with `bats-core`, `git-lfs` or `zsh-autosuggestions`. Verification steps 2–3 plan 23 production
mutations to answer what one counting run answers; step 2 cannot fail on its own (an
unwritten log also turns every site red) and is only meaningful beside step 1. Reads-it
test: the CLAUDE.md bullet persists but is advice with no check, beside ~370 remaining
substring examples; step 4 has no consumer after the session.
Assumption: the 23 recorded lines on `ubuntu-latest` match macOS. Settled by running the
converted files on the workstation, or by the PR's CI run.
Disposition:

### Ergonomics

Finding: A failing `-qx` does not show the recorded line. With `--quiet` added to
`brew_install_formula` in a scratch copy, the pyenv test failed with only
`` `grep -qx "brew install pyenv" ...' failed ``, the same message as a deleted install.
`refute_grep` (`tests/helpers/common.bash:27`) exists partly to name what was found, and
since it landed tests added 39 `refute_grep` calls against 1 bare `! grep -q`; no
install assertion has been added since the `uv` `-qx` precedent. An exact-match helper
that prints the log on failure was not considered. The proposed bullet ("assert a
recorded mock call with `grep -qx`") reads wider than the change: 397 − 23 substring
sites remain, 59 of them in `install_functions.bats` beside its 2 converted ones. The
escaping argument for rejecting a helper is weak: `@` is not a regex metacharacter, and
`-qx` without `-F` is a regex match too.
Assumption: that a CLAUDE.md bullet, rather than the nearest existing example, decides
what the next install test uses. Untested; check at the next PR adding an install
assertion.
Disposition:

### Risk

Finding: No blocking issue; one unstated new dependency. Three sites
(`install_guards.bats:120`, `workflows.bats:248`, `linux_ubuntu.bats:393`) pass under
`-qx` only because `tests/mocks/sudo` passes through to the `apt-get`/`snap` mocks; the
substring form also matched the `sudo -H apt-get ...` line. Breaking that passthrough
leaves the old form green and turns the new form red — better fidelity, but the spec
should say so. Real detection gain is 1 of 23 (pyenv). Platform skew does not bite:
`brew_install_formula` always runs `brew install "$formula"`, mocks write one line per call
with no trailing space or CRLF, and `MOCK_CALLS_FILE` is per-test under
`BATS_TEST_TMPDIR`. An empty log turns step 1 red (brew mock writing nothing failed the
converted `bat` test). Minor: `developer.bats:691`/`:711` are absence checks written as
`if … return 1`, not "not assertions"; leaving them is still right. Measured on macOS with
identity variables removed (all six files green) and on the workstation (24 ok, 0 not ok
for the 23 converted plus `uv`).
Assumption: no uncertain assumption found. The runner's PATH order for the sudo
passthrough is confirmed by the PR's first CI run.
Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
