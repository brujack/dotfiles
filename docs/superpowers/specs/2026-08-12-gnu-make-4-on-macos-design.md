# GNU Make 4.x on macOS — design

**Date:** 2026-08-12
**Status:** Spec — revised after round-1 Multi-Lens Review
**Backlog origin:** dotfiles#210

> **Revision note.** The round-1 design carried a fifth component: a `require-gnu-make`
> Makefile target that hard-failed `test` and `bash-coverage` under GNU Make < 4.0. It was
> **dropped**, not repaired — the review reproduced an undocumented bypass, a false-green
> remedy, a `git push` lockout, an Intel lockout, and an inability to run in CI. The full
> reasoning and both reproductions are preserved under "Rejected alternatives" and in the
> Multi-Lens Review section at the end. The primary fix is now a one-line `MAKEFLAGS`
> directive that the round-1 spec never considered.

## Problem

macOS ships GNU Make **3.81** at `/usr/bin/make`. Apple froze it at the last GPLv2
release, so it is two decades old and will never advance. Every mac in this fleet is
therefore structurally incapable of failing for any behavioural difference introduced in
GNU Make 4.0 or later.

That is the `tdd.md` pitfall **G** class — "a test that shells out to a versioned tool
inherits that tool's version skew, and the local version may be unable to fail" — and it
is not hypothetical here. `scripts/pre-push:71` runs `make -C "${REPO_ROOT}" test`, so the
local gate on every mac blesses defects that `ubuntu-latest` rejects.

### The measurement

dotfiles#208 paid for this once. Three tests in `tests/scripts/makefile_lint_scope.bats`
captured `make print-VAR` output and parsed it as a file list. GNU Make 4.0+ prints
`Entering directory` / `Leaving directory` to stdout whenever `-C` changes directory;
3.81 does not. The two extra lines parsed as filenames and polluted every result
_identically_, so a superset assertion stayed green while a disjointness assertion went
red. Green on every mac in the fleet, red in CI, across two rounds.

Re-measured on the Mac Studio, 2026-08-12:

```
make   -C . print-ZSH_FILES               ->  1 line   (GNU Make 3.81, /usr/bin/make)
gmake  -C . print-ZSH_FILES               ->  3 lines  (GNU Make 4.4.1)
gmake --no-print-directory -C . print-…   ->  1 line
```

Mutation-checked in both directions — `--no-print-directory` stripped from the bats file,
suite run under each version, working tree restored afterwards:

```
MUTATED under gmake 4.4.1: rc=1  not-ok=3   (tests 1, 3, 5)
MUTATED under make 3.81  : rc=0  not-ok=0   <- the finding
FIXED   under gmake 4.4.1: rc=0  not-ok=0
```

The second line is the finding. The fix is correct and the local gate cannot see whether
it is present.

### The version surface is exactly one behaviour, today

The `Makefile` was grepped for constructs that exist only in GNU Make 4.x — `$(file`, `!=`,
`::=`, `.ONESHELL`, `.RECIPEPREFIX`, `--output-sync`, `.EXTRA_PREREQS`. **None are
present.** Print-directory is therefore the entire measured version surface at this commit.
That bounds the problem and is why §1 below can close it in one line — but it is a
statement about today, not a guarantee, which is why §2–§4 still align the versions rather
than relying on the surface staying this small.

### A premise from the backlog row that did not survive checking

dotfiles#210's row asserted that a `6_path.zsh` change reaches interactive shells only,
and would therefore miss agent-driven and hook-driven invocations. **That is wrong**, and
it was the load-bearing claim in the row.

Measured: an agent tool's shell on the Studio carries `~/bin`, `~/scripts`, and
`~/.cargo/bin` on `PATH`. All three are added by `.config/.zshrc.d/6_path.zsh` and by no
other file in the tree (`grep -rn 'HOME}/bin' ~/.config/.zshrc.d/ ~/.zprofile ~/.zshrc`
returns exactly one hit, at `6_path.zsh:11`). So those shells do source `.zshrc`, and a
`PATH` change there reaches them — and reaches any git hook they invoke, since a hook
inherits its invoker's environment. Confirmed by the operator: all machines run the same
`.zshrc`, so any command-line push is covered.

**What a `PATH`-only fix does not reach was then measured rather than reasoned about.** A
`BatchMode` ssh to ratna reports `brew` and `gmake` both absent, because a non-interactive
ssh session does not source `.zshrc` — while `/usr/local/opt/make/libexec/gnubin` exists on
that same box. That is the reach gap demonstrated on a real machine: the tool is installed,
and the shell cannot see it. `cron`/`launchd` and non-zsh shells have the same shape.

This is why §1 is the primary fix and the `PATH` layer is support, not the reverse.

## Goals

1. The measured defect class cannot recur, at every call site including ones not yet
   written.
2. `make` resolves to GNU Make 4.x on every mac in the fleet, so the local gate and CI run
   the same program.
3. A machine where goal 2 has not been achieved is **visible**, not silently divergent.
4. No mechanism introduced here can prevent a machine from running its tests or pushing.

Goal 4 is new in this revision and is what retired the guard.

## Non-goals

- **Linux is untouched.** Ubuntu's `make` is already GNU 4.x.
- **CI is untouched.** `ubuntu-latest` already runs 4.x; that is the version being aligned
  _to_.
- **`coreutils` / `findutils` stay as they are.** Both installed, neither on `PATH` under
  its GNU name. Same shape of gap, but only `make` has a measured defect behind it, and a
  GNU-first policy is a materially larger blast radius. Named so the omission reads as a
  decision.
- **No fan-out to other repos.** The `PATH` half is inherently fleet-wide — it is the
  machine's `PATH`, so all nine repos get GNU Make 4.x once a mac is provisioned. §1 is
  per-repo and stays in dotfiles for now. Two other repos were spot-checked and are already
  safe: `terraform_ansible/ansible/scripts/ci_matrix.py:20` shells `["make", …]` with `cwd=`
  and no `-C` (so no directory lines), and `math/tests/scripts/makefile.bats` already passes
  `--no-print-directory`.

## Design

Four components. §1 closes the defect; §2–§3 align the versions; §4 makes divergence
visible.

### 1. Remove the variance at the source — `Makefile`

```make
MAKEFLAGS += --no-print-directory
```

One line. Verified on this machine with a fixture Makefile carrying that directive:
`print-VAR` emits **1 line under 3.81 and 1 line under 4.4.1**, and 3.81 accepts the
directive with **rc=0** — it is not a 4.x-only construct.

This is `tdd.md` pitfall G's own **first** preference ("remove the variance at the call
site"), and it is strictly better than fixing call sites individually, because it covers
invocations that do not exist yet. That matters specifically here: #208's fix landed on the
`_make_print` helper and two hand-built invocations stayed broken, which is pitfall G's
step 2 verbatim. A file-level directive has no step 2.

Existing per-call-site `--no-print-directory` flags in
`tests/scripts/makefile_lint_scope.bats` (lines 40, 146, 158) **stay**. They are correct,
they document the hazard at the point a reader meets it, and they protect any invocation
that does not go through this `Makefile`.

### 2. Provisioning — `lib/macos.sh`, `lib/workflows.sh`

Add `install_make_macos()`, mirroring the existing `install_git_macos` /
`install_zsh_macos` / `install_bats_macos` shape exactly:

```bash
install_make_macos() {
  if quiet_which gmake; then
    log_info "GNU make already installed"
    return 0
  fi

  log_info "Installing GNU make via Homebrew"
  if ! command -v brew &> /dev/null; then
    install_homebrew
  fi
  if command -v brew &> /dev/null; then
    brew_install_formula make || return 1
  else
    log_error "Failed to install Homebrew. Cannot install GNU make."
    return 1
  fi
  log_info "Installed GNU make"
}
```

Called from `run_setup_user` in `lib/workflows.sh`, inside the existing
`if [[ -n ${MACOS} ]]` branch alongside `install_git`.

**Called directly, with no `install_make()` dispatcher.** `install_zsh` and `install_bats`
are dispatchers because both platforms need work; here Linux needs none, so a dispatcher
would exist only to have an empty arm. This also sidesteps a contract hazard already on the
backlog: `install_bats`'s `if`/`elif` has no `else`, so it returns **0** when neither
`MACOS` nor `LINUX` is set.

The probe is `quiet_which gmake`, not `make` — `make` is always present on macOS at 3.81,
so probing it would report success on precisely the machine that needs the install.

`brew "make"` already exists at `Brewfile:70`, so `brew bundle` parity is unchanged. This
function exists because `setup_user` does not run `brew bundle`.

### 3. `PATH` — `.config/.zshrc.d/6_path.zsh`

Inside the existing `if [[ ${MACOS} ]]` block:

```zsh
for _gnubin in /opt/homebrew/opt/make/libexec/gnubin \
               /usr/local/opt/make/libexec/gnubin; do
  [[ -d ${_gnubin} ]] && { path=(${_gnubin} $path); break }
done
unset _gnubin
```

Three properties, each load-bearing and each measured.

**Prepend, not `path+=`.** The file's existing idiom is append, which leaves `/usr/bin`
ahead of anything it adds — verified directly: `path+=` yields `first=/usr/bin` while
`path=(dir $path)` yields `first=…/gnubin`. An append here would be completely inert and
would look correct.

**Both Homebrew prefixes, tested for existence — not `brew --prefix`, and not a hostname
branch.** ratna is `x86_64` (macOS 13.7.8) with Homebrew at `/usr/local`, and
`/usr/local/opt/make/libexec/gnubin` **already exists there**. A hardcoded `/opt/homebrew`
would silently no-op on a machine that already has the fix on disk. `brew --prefix make`
was considered and rejected: this same file is what puts `/opt/homebrew/bin` on `PATH`
(lines 18–25), so `brew` is not guaranteed resolvable at this point — measured absent over
non-interactive ssh to ratna — and it would spend a subprocess on every shell start. A
`${RATNA}` branch was also available (`1_init.zsh:17` sets it, before this file runs) and
was rejected as weaker: testing the directory stays correct when the next Intel machine
appears, while testing the hostname does not.

**Idempotent for free.** `typeset -U path` at the top of the file dedupes — verified with
three consecutive prepends producing three total entries and no duplicates. Re-sourcing
`.zshrc` is safe.

`break` after the first hit means an (impossible today) machine with both prefixes gets one
entry, deterministically the ARM one.

### 4. Detection — new `_doctor_check_make_version` in `lib/helpers.sh`

A **new** check function, called from `run_doctor` alongside the existing
`_doctor_check_tools` / `_doctor_check_versions` / `_doctor_check_hooks_path` list.
macOS-only; returns without counting a check on Linux.

**Report-only — `doctor_warn`, never `doctor_fail`.** It must not touch `_DOCTOR_FAILED`
and must not change `-t doctor`'s exit code. A mac on 3.81 is _divergent from CI_, which is
worth surfacing, but §1 already closes the defect, so failing the machine's health check
over it would be a verdict out of proportion to the condition — and `-t doctor` exiting
non-zero on six machines the day this merges is the same rollout problem the guard had,
wearing a smaller hat.

**It must not reuse `_doctor_check_one_version`, and this is the trap.** That helper
asserts a **pin** — its comparison is `[[ "${_installed}" == "${_pinned}"* ]]` against a
constant from `lib/constants.sh`. What is wanted here is a **floor**: any GNU Make ≥ 4.0 is
correct, so a machine on 4.3 must pass. Reaching for the existing helper, or adding a
`MAKE_VER` constant to feed it, would encode the wrong relation while looking like it
followed the established pattern. There is deliberately no `MAKE_VER` constant.

Version parsing must not use string comparison — `shell.md`'s semver pitfall applies
(`[[ "4.4.1" < "3.81" ]]` is true under lexicographic `[[`). Extract the major component
and compare with `-ge`.

## Testing

Every component gets tests in the same commit as its code, per `tdd.md`.

A note the round-1 spec got wrong: `Makefile:81` is `test: lint test-python`. Any change to
that line must preserve `test-python`, and case 5 below exists so nothing can drop it
silently again.

### `MAKEFLAGS` — `tests/scripts/makefile_lint_scope.bats`

| #   | Case                                                                                                         | Expect            |
| --- | ------------------------------------------------------------------------------------------------------------ | ----------------- |
| 1   | `print-ZSH_FILES` emits the same line count under 3.81 and under a 4.x shim                                  | equal, and **>0** |
| 2   | A `print-`-style probe returns a specific derived value, not a verdict                                       | exact value       |
| 3   | `MAKEFLAGS += --no-print-directory` is present in the `Makefile`                                             | match             |
| 4   | No `make` invocation under `tests/` parses stdout without either the file-level directive or a per-call flag | structural        |
| 5   | `test` still has `test-python` as a prerequisite                                                             | present           |

Case 1 asserts **equality plus non-emptiness**. Equality alone passes if both sides emit
zero lines, which is exactly the "measurement produced nothing" state the review flagged as
indistinguishable from a pass. Case 2 pins a derived value rather than a branch outcome,
for the same reason.

Case 4 is the durable channel for what round 1 left as PR-body prose. It replaces a
"verification before merge" step that changed no verdict and left no record.

The 4.x shim resolves to **any make ≥ 4**, not to `gmake` by name — `ubuntu-latest` has no
`gmake`, and a shim keyed on that name would make these cases skip in the one environment
that is the merge gate. On a machine where no make ≥ 4 can be found, cases 1 and 2 `skip`
with a stated reason rather than passing vacuously.

### `PATH` — `tests/zshrc.d/unit.bats`

| #   | Case                                                                 | Expect                            |
| --- | -------------------------------------------------------------------- | --------------------------------- |
| 6   | With an ARM-prefix gnubin dir present, it is `path[1]`               | first element, not merely present |
| 7   | With only a `/usr/local` gnubin dir present, it is `path[1]`         | first element                     |
| 8   | Sourcing three times yields one entry                                | count unchanged                   |
| 9   | With neither dir present, no entry added and `PATH` otherwise intact | absent, rest unchanged            |
| 10  | Under `LINUX`, no gnubin entry is added                              | absent                            |
| 11  | `_gnubin` does not leak into the environment after sourcing          | unset                             |

Case 6 asserts **position**, not membership: a membership check (`grep -q gnubin`) would
pass for the append idiom, which is inert. Case 7 is the ratna case and is the one that
would have failed the round-1 design.

### Provisioning — `tests/setup_env/install_guards.bats`

| #   | Case                                                                     | Expect             |
| --- | ------------------------------------------------------------------------ | ------------------ |
| 12  | `gmake` present → no `brew install` call                                 | idempotent skip    |
| 13  | `gmake` absent, brew present → `brew_install_formula make` called        | called once        |
| 14  | `gmake` absent, brew absent and uninstallable → returns 1, logs error    | rc=1               |
| 15  | Probe is `gmake`, not `make` (a stubbed 3.81 `make` must not satisfy it) | install still runs |

Case 15 is the mirror of case 6: it pins the one substitution that would make the component
inert on exactly the machines it targets.

### Doctor — `tests/setup_env/unit.bats`

| #   | Case                                     | Expect                     |
| --- | ---------------------------------------- | -------------------------- |
| 16  | macOS, `make` reports 3.81 → warns       | warn counted               |
| 17  | macOS, 3.81 → does **not** fail the run  | `_DOCTOR_FAILED` unchanged |
| 18  | macOS, `make` reports 4.4.1 → passes     | pass counted               |
| 19  | Linux → check does not run               | not counted                |
| 20  | Comparison is numeric, not lexicographic | 4.4.1 ≥ 3.81               |

Case 17 is the negative structural assertion that keeps this check report-only. Without it,
someone promoting `doctor_warn` to `doctor_fail` later would reintroduce a fleet-wide
failure and nothing would catch it.

## Rollout risk

**No lockout path exists in this design.** §1 is inert on both versions. §3 no-ops when the
directory is absent. §4 warns. §2 runs only under `setup_user`. Nothing can prevent a
machine from running `make test`, committing, or pushing — which is the difference between
this revision and round 1, where the guard blocked `scripts/pre-push:71` on six
unprovisioned macs.

**The full suite passes under GNU Make 4.x.** Measured on the Studio with a 4.4.1 shim
ahead of `PATH`: `rc=0`, **1294 ok, 0 not ok, 2 skipped** — matching the CI-measured test
count exactly. So §3 flipping the version that runs `make test` breaks nothing. This
settles the round-1 Goal-fit assumption, which asked whether the rollout risk was "six
machines need provisioning" or "the suite is red on every mac at merge". It is the former,
and mild.

**ratna is Intel and is managed by this repo.** `x86_64`, macOS 13.7.8, Homebrew at
`/usr/local`, `gnubin` already present, `PROFILE` resolves to `unknown` because the
hostname is absent from `PROFILE_MAP` — but `6_path.zsh`'s branch is gated on `MACOS`, not
on `PROFILE`, so §3 executes there. It is a server-room terminal and does no development,
so it never runs the gate; §3 is correct there for tidiness rather than for lockout
avoidance, and §4 will report it.

## Rejected alternatives

**A `require-gnu-make` Makefile target that hard-fails `test` and `bash-coverage` under
< 4.0.** This was round 1's §3. Dropped on five independent grounds, four of them
reproduced:

- **The bypass.** `MAKE_VERSION` is an ordinary make variable, so a command-line assignment
  overrides it. Reproduced: `/usr/bin/make guard MAKE_VERSION=4.9` prints
  `PASSED under real GNU Make 3.81`, **rc=0**. The spec claimed "no escape hatch"; the hatch
  was undocumented and traceless — strictly worse than the named `ALLOW_OLD_MAKE=1` it had
  rejected on allow-path grounds.
- **The remedy was a false green.** Make does not propagate itself to a bare `make` in a
  recipe or subprocess. Reproduced: an outer `gmake` whose recipe runs `make --version`
  reports **`GNU Make 3.81`**. So the printed escape `gmake test` would run the outer make
  at 4.4.1 while every make-invoking bats test resolved bare `make` through `PATH` to 3.81
  — green, having exercised precisely the version the guard existed to distrust.
- **It blocked `git push`.** `scripts/pre-push:71` calls `make -C "${REPO_ROOT}" test`. The
  mitigation "lint is unguarded, so a machine can always commit its way out" was true and
  useless; unpushable commits are not a recovery path, and the only escape was
  `git push --no-verify` — the all-or-nothing bypass `git-workflow.md` records as having
  already cost this fleet a repo-wide breakage.
- **It could not run in CI.** `ubuntu-latest` has neither a 3.81 `make` nor a `gmake`, so
  the guard's core cases would skip in the environment that is the merge gate. CI would go
  green over a deleted `require-gnu-make`.
- **Intel lockout.** With `/opt/homebrew` hardcoded, round 1's `PATH` component would
  silently no-op on ratna while the guard still fired — unrunnable and unpushable, with a
  printed remedy that did not fix it. Silent-then-permanent.

**`PATH` prepend alone, with no `MAKEFLAGS` line.** Reaches more than round 1 credited
(agent shells and hooks included), but the ratna ssh measurement shows the gap is real, and
it leaves future call sites exposed on any shell that did not source `.zshrc`.

**Makefile re-execs itself under `gmake` when it detects 3.81.** Rejected on
`code-standards.md` grounds — clever is not a compliment, and it would make the version that
actually ran a target invisible in the output.

**Warn-only guard now, fatal later.** Nothing schedules "later". A warn-only gate is a gate
that does not exist.

**Fan out to all nine repos immediately.** Deferred until §1 has run here for a while.

## Files touched

| File                                     | Change                                       |
| ---------------------------------------- | -------------------------------------------- |
| `Makefile`                               | `MAKEFLAGS += --no-print-directory`          |
| `lib/macos.sh`                           | `install_make_macos()`                       |
| `lib/workflows.sh`                       | call it from `run_setup_user`'s macOS branch |
| `lib/helpers.sh`                         | new `_doctor_check_make_version` (warn-only) |
| `.config/.zshrc.d/6_path.zsh`            | dual-prefix gnubin prepend                   |
| `tests/scripts/makefile_lint_scope.bats` | cases 1–5                                    |
| `tests/zshrc.d/unit.bats`                | cases 6–11                                   |
| `tests/setup_env/install_guards.bats`    | cases 12–15                                  |
| `tests/setup_env/unit.bats`              | cases 16–20                                  |
| `CLAUDE.md`                              | Testing + Key Conventions notes              |

## Related

- dotfiles#208 — the incident that measured the defect
- dotfiles#210 — the backlog row this spec supersedes
- `tdd.md` pitfall G — version skew in a shelled-out tool, and its preference order
- `behavior.md` — "a check derived from the same decision as the thing it checks cannot falsify it"
- `shell.md` — semver string comparison pitfall

## Multi-Lens Review

Reviewed at commit: `0d070ae` (Step 7 self-review commit, before Step 8 dispatch)

Three lenses ran independently, with no access to the brainstorming conversation. All three
independently found the same defect in §3's snippet (the dropped `test-python`
prerequisite), and two independently found the pre-push lockout. Three further findings
were reproduced directly by the author afterwards rather than accepted on report — those
reproductions are recorded inline below.

### Goal-Fit

Finding: **The one measured defect this spec exists for is closed by a single line, in the
file that produces the output, and the spec never puts that option on the table.**
`MAKEFLAGS += --no-print-directory` in the `Makefile` covers every call site — including
ones not yet written, which is exactly the failure mode `tdd.md` pitfall G records. Author
reproduction: with that line present, `print-VAR` emits **1 line under 3.81 and 1 line
under 4.4.1**, and 3.81 accepts the directive with rc=0. `tdd.md`'s own preference order
puts *remove the variance at the call site* first and *verify under CI's version* third;
this spec skips first and builds third as permanent fleet infrastructure. A `Makefile` grep
for 4.x-only constructs (`$(file`, `!=`, `::=`, `.ONESHELL`, `.RECIPEPREFIX`,
`--output-sync`, `.EXTRA_PREREQS`) found none, so print-directory is the entire measured
version surface today.

Also: cases 2 and 3 `skip` on `ubuntu-latest`, which has no `gmake` — so the guard's
positive arm runs only on an already-provisioned mac. And "Verification before merge" fails
the reads-it test in both directions: the mutation re-run changes no verdict and its only
output is PR-body prose.

Assumption (SETTLED — CONFIRMED): that the full 1294-test suite — not just the make-scope files — passes under
GNU Make 4.x on macOS. §2 flips the version running `make test` on every mac before §1 or
§3 matter. Verified for the two make-aware files only (rc=0, 10 ok). Settle with
`PATH="$shim:$PATH" make test` over the whole suite; a non-zero rc changes the rollout
risk from "six machines need provisioning" to "the suite is red on every mac the instant
this merges".

Disposition: **Addressed.** The `MAKEFLAGS += --no-print-directory` line is now §1 and the
primary fix; the guard was dropped rather than repaired. The reads-it failure on
"Verification before merge" is closed by test case 4, a structural assertion in the suite
rather than PR-body prose. The shim now resolves to any make ≥ 4 rather than to `gmake` by
name, so the cases run on `ubuntu-latest`. Assumption settled by measurement: full suite
under a 4.4.1 shim returned `rc=0`, 1294 ok, 0 not ok, 2 skipped.

### Ergonomics

Finding: **The guard blocks `git push`, not just `make test`, and the stated mitigation
misreads that.** `scripts/pre-push:71` is `make -C "${REPO_ROOT}" test`, so on an
unprovisioned mac the guard fires there. "lint is unguarded, so a machine can always commit
its way out" is true and useless — unpushable commits are not a recovery path, and the only
escape is `git push --no-verify`, which `git-workflow.md` documents as all-or-nothing.

Also: the printed remedies (`brew install make`, `setup_env.sh -t setup_user`) install
`gmake` but do not change `PATH` in the shell you are standing in, so the documented
sequence is hit-guard → run-remedy → hit-guard-again. `test-unit` and `test-python` invoke
bats and are unguarded, so the fast iteration loop keeps the exact blind behaviour this
spec exists to end. And case 1 is vacuous: `make nonexistent-target` already returns rc=2,
so "exits non-zero under 3.81" passes with `require-gnu-make` deleted entirely.

Assumption (SETTLED by the operator — confirmed): that every routine `git push` route on all seven machines runs from a shell
that sourced `.zshrc`. Verified only for zsh and one agent tool on the Studio. If false for
any route (an editor's source-control panel, a `sh -c` harness), the guard converts that
route into a *permanent* failure that `install_make_macos` cannot fix.

Disposition: **Addressed.** The guard is gone, so the push lockout, the ineffective printed
remedies, and the unguarded-`test-unit` gap all cease to exist — nothing in the revised
design can block a push. The dropped `test-python` prerequisite is fixed and pinned by test
case 5. Case 1 no longer relies on a bare non-zero exit (which `make nonexistent-target`
satisfies anyway); it asserts equality **and** non-emptiness, and case 2 pins a derived
value. Assumption confirmed by the operator: all machines run the same `.zshrc`, so every
command-line push route is covered.

### Risk

Finding: **"No escape hatch" is false, and the hatch is undocumented and traceless.**
`MAKE_VERSION` is an ordinary make variable, so a command-line assignment overrides it.
Author reproduction: `/usr/bin/make guard MAKE_VERSION=4.9` prints
`PASSED under real GNU Make 3.81`, **rc=0**. That is an allow-path looser than the
deny-path, and worse than a named `ALLOW_OLD_MAKE=1` would be.

**And the guard's own printed remedy is itself a false green.** Make does not propagate
itself to a bare `make` in a recipe or subprocess. Author reproduction: an outer `gmake`
whose recipe runs `make --version` reports **`GNU Make 3.81`**. So `gmake test` runs the
outer make at 4.4.1 while every make-invoking bats test resolves bare `make` through `PATH`
to 3.81 — the suite goes green having exercised precisely the version the spec exists to
stop trusting. §3's verification row "`gmake test` under 4.4.1 → rc=0" is evidence of the
bug, not the fix. Only §2 changes what the tests actually measure.

Also: `/opt/homebrew` is hardcoded with no Intel arm, though the repo already carries an
Intel-prefix branch at `.config/.zshrc.d/5_general.zsh:7`. On an Intel mac §2's dir-guard
silently no-ops while §3 still fires — a machine that cannot run `make test` or push, whose
printed remedy does not fix it. Silent-then-permanent, which is the lockout the design
claims to avoid.

Assumption (SETTLED — REFUTED): that every mac in the fleet is Apple Silicon. Settle with `uname -m` on each
of the seven machines. One Intel hit means §2 must resolve via `brew --prefix make` rather
than a literal path, and §3 must not fire where §2 could not apply.

Disposition: **Addressed.** Both reproductions stand and both are recorded under "Rejected
alternatives" as the reason the guard was dropped rather than fixed — the `MAKE_VERSION`
override and the `gmake test` false green. The hardcoded prefix is replaced by a
dual-prefix existence test. Assumption **refuted**: ratna is `x86_64`, macOS 13.7.8,
Homebrew at `/usr/local`, measured over ssh — and `/usr/local/opt/make/libexec/gnubin`
already exists there, so the round-1 path would have no-opped on a machine that already had
the fix installed. `brew --prefix make` was the obvious repair and is also wrong: `6_path.zsh`
is itself what puts Homebrew on `PATH`, and `brew` measured absent over non-interactive ssh.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger. Acceptance criteria are
concrete return codes and named structural assertions.
Disposition: N/A

### Round 2

The revision above changed design substance — a component was removed, not reworded — so all
three lenses re-run against it rather than only the lens that raised each finding.
