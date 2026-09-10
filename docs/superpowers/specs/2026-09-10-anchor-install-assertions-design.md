# Anchor the pyenv install assertion

**Date:** 2026-09-10
**Backlog row:** "`grep -q` in `tests/setup_env/linux_ubuntu.bats` lets a real deletion pass"
**Scope:** one assertion in one test file; no production code changes.

## Problem

Bats tests confirm an install happened by searching the mock call log with a
substring match. Every mock appends one line per call (`printf "brew %s\n" "$*"`), so a
substring also matches a longer sibling's line.

`tests/setup_env/linux_ubuntu.bats:127` asserts:

```bash
grep -q "brew install pyenv" "${MOCK_CALLS_FILE}"
```

`_install_ubuntu_brew_packages` also installs `pyenv-virtualenv`
(`lib/linux_ubuntu.sh:353`), so the assertion matches that line and cannot fail for the
formula it names.

**Measured 2026-09-10** in `git archive` copies (Mac Studio, bats 1.14.0), by this
session and independently by all three round-1 review lenses:

| production                                              | assertion  | result                          |
| ------------------------------------------------------- | ---------- | ------------------------------- |
| `brew_install_formula pyenv` (`:352`) deleted           | `grep -q`  | `ok`                            |
| `brew_install_formula pyenv` (`:352`) deleted           | `grep -qx` | `not ok`                        |
| unchanged                                               | `grep -qx` | `ok`                            |
| `:352` deleted, whole of `linux_ubuntu.bats`, `grep -q` | —          | 80 ok, 0 not ok (goal-fit lens) |

No other test can catch the deletion. `linux_ubuntu.bats` is the only test file that names
`_install_ubuntu_brew_packages`; production also reaches it through
`install_ubuntu_packages` (`lib/linux_ubuntu.sh:12`). Searching `tests/` for `pyenv`
finds one other assertion that could involve this install, `workflows.bats:659`
(`grep -q "pyenv"`). It cannot fail when only the `pyenv` install is deleted: if its
test reaches this function, the substring still matches `pyenv-virtualenv`; if it does
not, the deletion never touches its log.

## Why one site, not the class

The backlog row asked for an audit of prefix collisions across the install assertions.
That audit is done and its result sets the scope.

- **Population:** `git grep -nE 'grep -qx? "(brew|apt-get|sudo apt-get|snap|pip) install' -- tests`
  at `8e2a7d50` returns 36 sites in 7 files: 23 positive assertions naming one package,
  7 absence checks (`! grep -q`), 2 absence checks written as `if grep -q … return 1`
  (`developer.bats:691`, `:711`), 2 checks that match any install, 1 regex, and the
  already-anchored `uv` site (`linux_ubuntu.bats:139`).
- **Collisions:** for each of the 23, the goal-fit and risk lenses each counted how many
  lines of that test's own mock log the substring matches against the exact line.
  **Only `:127` (`pyenv`) matches a line from a different call.** The two
  `apt-get install -y bats` sites and helm also show a second match, but it is the
  `sudo` mock's own log line for the same call, so a deletion removes both. `bat`, `git`
  and `zsh` never share a log with `bats-core`, `git-lfs` or `zsh-autosuggestions`.
- **Absence checks** keep the substring form: there it is the stricter form, since
  `! grep -q "brew install git"` also fails on `brew install git-lfs`.

Converting the other 22 would change no test's ability to fail. The class-wide question
(397 unanchored mock-log greps across 16 files, and whether an exact-match helper should
replace them) is recorded as a backlog row and designed separately.

## Design

Change `tests/setup_env/linux_ubuntu.bats:127` to:

```bash
grep -qxF "brew install pyenv" "${MOCK_CALLS_FILE}"
```

- `-x` matches the whole line, so `brew install pyenv-virtualenv` no longer satisfies it.
- `-F` makes the pattern literal, so no future edit of the package name can introduce a
  regex metacharacter by accident.
- The adjacent `uv` site (`:139`) uses `-qx` without `-F`. Its pattern has no
  metacharacters, so the two behave identically; it is left alone.

### Accepted trade-off

`-x` fails a correct implementation that adds an argument (for example
`brew install --quiet pyenv`), and the failure output shows only the grep command, not the
recorded line. For one site that is acceptable: `brew_install_formula` has always run
`brew install "$formula"`, and a changed argv is behaviour the test should notice. Better
failure output belongs to the class-wide helper, not to this line.

## Verification

1. **Mutation, against the edited file:** in a scratch copy of the branch, delete
   `brew_install_formula pyenv` from `lib/linux_ubuntu.sh`. The edited test must go red.
   Run the same mutant against the original assertion: it must stay green, or the mutant
   is not exercising the defect.
2. **Control:** unmutated, the edited test is green.
3. **Suite:** `make test` exits 0 with the test count unchanged.
4. **CI:** the PR's `test` and `bash-coverage` jobs pass on `ubuntu-latest`.

An empty mock log turns step 2 red, so the positive assertion cannot pass on nothing.

## Documentation

`docs/superpowers/README.md`, in the implementation PR:

- Retire the backlog row this closes.
- Add one row for the class, pointing at this spec for its measurements: 397 unanchored
  mock-log greps, 1 collision in the 23-site install subset, and an exact-match helper
  that prints the log on failure as the candidate fix (`refute_grep` precedent: 39
  calls added since it landed, against 1 bare `! grep -q`).
- Reword the inherited-variables row added in `8e2a7d50` from `MACOS`/`LINUX`/`HAS_*` to
  "the variables `detect_env` sets", since the listed names omit `UBUNTU`, `PROFILE` and
  the legacy identity variables.

No `CLAUDE.md` change: a one-line assertion fix sets no convention, and a rule beside
~370 counter-examples with no check behind it would not be followed.

## Out of scope

- The other 22 positive install assertions (no collision; consistency only).
- The wider class and the `assert_called` helper (backlog row above).
- Replacing bare `! grep -q` with `refute_grep` (all install-verb absence checks are live).

## Multi-Lens Review

Reviewed at commit: `007590cd` (Step 7 self-review commit, before Step 8 dispatch). That
round reviewed the earlier 23-site design; the body above is the revision it produced.
References below to "steps 2–4", "the bullet" and "the 23 sites" are to that earlier text.

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
log with `bats-core`, `git-lfs` or `zsh-autosuggestions`. Verification steps 2–3 plan 23
production mutations to answer what one counting run answers; step 2 cannot fail on its
own (an unwritten log also turns every site red) and is only meaningful beside step 1.
Reads-it test: the CLAUDE.md bullet persists but is advice with no check, beside ~370
remaining substring examples; step 4 has no consumer after the session.
Assumption: the 23 recorded lines on `ubuntu-latest` match macOS. Settled by running the
converted files on the workstation, or by the PR's CI run.
Disposition: Addressed. Owner chose the "Pyenv only" scope (2026-09-10). Scope cut from 23
sites to `:127`; verification reduced to the pyenv deletion mutant, a control, `make test`
and CI; the CLAUDE.md bullet and the population-closure step removed. The assumption is
moot for the dropped sites and was measured true on the workstation by the risk lens.

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
Disposition: Addressed in part: owner chose the "Pyenv only" scope (2026-09-10); the
bullet is dropped and `-F` is added so the match is literal. Accepted in part, reason: the
missing failure output and the `assert_called` helper are deferred to the class-wide
backlog row, to be designed against all 397 checks rather than this slice. The assumption
no longer applies, since no rule is written.

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
Disposition: Addressed. Owner chose the "Pyenv only" scope (2026-09-10): none of the three
sudo-passthrough sites is converted, so the dependency is not introduced. The
`developer.bats` wording is corrected in "Why one site".

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
