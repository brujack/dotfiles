# GNU Make 4.x on macOS — design

**Date:** 2026-08-12
**Status:** Spec — revised after round-2 Multi-Lens Review
**Backlog origin:** dotfiles#210

> **Revision note.** The round-1 design carried a fifth component: a `require-gnu-make`
> Makefile target that hard-failed `test` and `bash-coverage` under GNU Make < 4.0. It was
> **dropped**, not repaired — the review reproduced an undocumented bypass, a false-green
> remedy, a `git push` lockout, an Intel lockout, and an inability to run in CI. The full
> reasoning and both reproductions are preserved under "Rejected alternatives" and in the
> Multi-Lens Review section at the end. The primary fix is now a one-line `MAKEFLAGS`
> directive that the round-1 spec never considered.
>
> **Round 2 then found defects in that revision.** The `MAKEFLAGS` directive is an exported
> environment variable, not a file-local setting, which made the fix's own tests
> unfalsifiable; the doctor check had no consumer and has been rewired to the `-t update`
> state-ledger entry; and a second make-invoking test file (`tests/makefile_scope.bats`,
> four unflagged stdout parses) was absent from the design entirely. Round 2 found more
> than round 1 did — do not read review rounds as decaying in yield.

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
- **Fan-out is not a non-goal — it is already happening, and it was measured.** Calling it
  a non-goal was wrong in round 1. §3 is a machine-global `PATH` change, so every repo on a
  provisioned mac gets GNU Make 4.x; and §1's `MAKEFLAGS` export reaches any make descended
  from a dotfiles recipe, including one invoking another repo. Coverage was extended from 2
  repos to **9 of 9** and is clean: `ai-config` has ~30 `make -C` sites and no directive, yet
  its five make-touching suites run rc=0 / 0 not-ok under a 4.4.1 shim;
  `terraform_ansible/ansible/scripts/ci_matrix.py:20` shells `["make", …]` with `cwd=` and no
  `-C`, emitting 32 lines under both versions; `math/tests/scripts/makefile.bats` already
  passes `--no-print-directory`; and `ai-devops`, `etch-cli`, `etch-config`, `state-ledger`
  and `brucejacksonconsulting-site` have **zero** make invocations in tests or scripts. What
  *is* deferred is adding §1's directive to the other repos' own Makefiles.

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

**`MAKEFLAGS` is an exported environment variable, not a file-local directive — and that
is the most important sentence in this spec.** Measured:

```
inner Makefile alone, no directive:            3 lines
inner spawned from outer make WITH directive:  1 line      <- leaked via environment
$MAKEFLAGS inside the recipe:                  [ --no-print-directory]
inner via `env -u MAKEFLAGS`:                  3 lines     <- falsifiability restored
```

`make test` is the invocation route for both `scripts/pre-push:71` and `ci.yml:33`, so once
§1 lands **every `make` the bats suite spawns inherits `--no-print-directory` from the
environment, whichever Makefile it targets** — including a fixture built deliberately
without the directive to prove the hazard still exists. Left unaddressed, no test in this
suite could ever observe directory-line pollution again, on any platform. That is
`behavior.md`'s "a check derived from the same decision as the thing it checks" in a fresh
instance, created by the fix itself.

**Binding harness rule, stated as a partition so it can be checked mechanically.** Every
stdout-capturing `make` invocation in a test file falls in exactly one of two sets:

| set | carries | why |
| --- | ------- | --- |
| **guarded** | a per-call `--no-print-directory` | correct regardless of §1 and regardless of what the environment leaks in |
| **measuring** | `env -u MAKEFLAGS`, and nothing else | these are the only tests permitted to observe directory lines, because observing them is the point |

An earlier draft stated this as "any test that measures print-directory behaviour must use
`env -u MAKEFLAGS`" and pinned it with case 5 alone. That was prose, not enforcement: case 5
proves the environment still leaks, which is a fact about make, not about whether future
tests follow the rule. Someone adding a sixth case that measures directory output and forgets
`env -u` would pass for the wrong reason — the same defect shape §1 introduced, one layer
out.

The partition is checkable without any semantic judgment about what a test "measures", which
is what made the original rule unenforceable. Case 4 asserts it: every capturing invocation
is in exactly one set, and **both sets are non-empty**. An invocation in neither set fails.

Residual gap, stated rather than papered over: a test that captures make stdout for reasons
unrelated to directory lines is pushed into the guarded set and carries a flag it does not
strictly need. That is a small tax and arguably correct anyway. What the partition does not
do is verify that a test placed in the *measuring* set genuinely needs to be there — a test
could carry `env -u MAKEFLAGS` without measuring anything. Nothing catches that, and nothing
cheaply could.

It also means the fan-out is real and already happening — see Non-goals.

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

### 4. Detection — a make-version field on the `-t update` ledger entry

`lib/update_summary.sh:377` defines `_ledger_write_run_entry RUN_TYPE EXIT_CODE`, called at
`:491` for `update` and from five `run_*` workflows in `lib/workflows.sh`. §4 adds the
machine's `make` major version as a **field on the entry `-t update` already writes**.

**A field, not a new section — deliberately.** A new section would require a matching entry
in `_UPDATE_SECTION_ORDER` (`lib/update_summary.sh:5`), and CLAUDE.md records that coupling
as a two-place edit whose omission tracks a section internally while never printing it. A
field on an existing entry needs neither edit.

**Why this and not `-t doctor`.** Round 1 put the check in `run_doctor`, which fails the
reads-it test in both directions: it could not change a decision (it was report-only by
design), and its output persisted nowhere — `_ledger_write_run_entry` is called for
`setup_user`, `setup`, `developer`, `recreate_venv` and `recreate_ruby`, and **never for
`run_doctor`**, while `~/.dotfiles-update.log` is `-t update` only. Its entire product was
one line in a terminal summary from an on-demand command. Goal 3 was stated and undelivered.

Attaching to `-t update` fixes both halves: it is the command every machine actually runs
on a cadence, and the ledger is an immutable append-then-derive record, so "which macs are
still on 3.81" becomes a query rather than something you learn by sitting at each machine.

A `doctor_warn` line in `-t doctor` may ride along, since the version probe exists either
way — but the ledger field is the consumer that justifies the component, and the doctor line
is not a substitute for it.

**Nothing here fails a run.** The field is recorded; no exit code changes. §1 already closes
the defect, so a machine on 3.81 is divergent-and-recorded, not broken.

**The probe must not reuse `_doctor_check_one_version`.** That helper asserts a **pin** —
`[[ "${_installed}" == "${_pinned}"* ]]` against a `lib/constants.sh` constant. What is
wanted is a **floor**: any GNU Make ≥ 4.0 is correct, so 4.3 must pass. Reaching for the
existing helper, or adding a `MAKE_VER` constant to feed it, would encode the wrong relation
while looking like it followed the established pattern. There is deliberately no `MAKE_VER`
constant. `shell.md`'s semver pitfall applies — extract the major component and compare with
`-ge`, never lexicographically.

**An unparseable or absent `make --version` must be recorded as `unknown`, not as a
version.** Empty output yields an empty major, and `[[ "" -ge 4 ]]` is false — which would
be recorded identically to a real 3.81, making a broken probe indistinguishable from a
correctly-detected old make. Case 18 pins this.

## Testing

Every component gets tests in the same commit as its code, per `tdd.md`.

Two facts the earlier drafts got wrong, both now pinned by cases below. `Makefile:81` is
`test: lint test-python` — any edit must preserve `test-python`. And there are **two**
make-invoking bats files, not one: `tests/scripts/makefile_lint_scope.bats` (5 flagged
invocations) and `tests/makefile_scope.bats` (**4 unflagged** `make -C "${REPO_ROOT}" -n
lint` stdout parses at lines 36, 45, 68, 79, and zero `--no-print-directory`). The second
was absent from round 1 and round 2's design entirely.

### `MAKEFLAGS` — `tests/scripts/makefile_lint_scope.bats`

| #   | Case                                                                                          | Expect                     |
| --- | --------------------------------------------------------------------------------------------- | -------------------------- |
| 1   | Under `env -u MAKEFLAGS`, `print-ZSH_FILES` line count is equal across 3.81 and a 4.x make     | equal, and **>0**          |
| 2   | Under `env -u MAKEFLAGS`, a `print-` probe returns a specific derived value                    | exact value                |
| 3   | `MAKEFLAGS += --no-print-directory` is present in the `Makefile`                               | match                      |
| 4   | Every stdout-capturing make invocation in a test file is in exactly one of the guarded/measuring sets | partition holds, both sets **>0** |
| 5   | With `MAKEFLAGS` inherited (no `env -u`), a directive-free fixture emits directory lines under 4.x | leak is observable     |
| 6   | `test` still has `test-python` as a prerequisite                                               | present                    |

**Case 1's skip rule is explicit and names CI.** The comparison needs a `<4` arm and a `≥4`
arm. `ubuntu-latest` has neither a 3.81 `make` nor a `gmake`, so on CI the case would
otherwise compare 4.x against 4.x — equal by construction, passing with the `MAKEFLAGS` line
deleted. The rule: resolve the `<4` arm from `/usr/bin/make` and the `≥4` arm from the first
make ≥ 4 on `PATH`; if either arm is missing, `skip` with a reason that names which arm and
why. A skip on `ubuntu-latest` is expected and correct; a silent same-binary comparison is
not.

**Case 4 replaces a version of itself that could not fail.** The round-2 wording was "no
invocation parses stdout without *either* the file-level directive or a per-call flag" —
and §1 makes the file-level directive a global fact, so the OR-arm was satisfied for every
invocation in the repo the instant §1 existed. It gave zero protection to the per-call flags
§1 says must stay, and zero coverage of the four unflagged parses in
`tests/makefile_scope.bats`. Worse, §1's directive lives in the repo `Makefile` and does not
reach **fixture** Makefiles at all — `tests/setup_env/git_hooks.bats` writes 24 of them,
invoked via `make -C <repo> install-hooks`, plus one at `tests/scripts/pre_commit_hook.bats:25`.
So the old case passed precisely for the call sites §1 cannot protect. The replacement
asserts the guarded/measuring partition above over **every** stdout-capturing invocation —
fixture-Makefile and repo-Makefile alike — and **asserts both sets are non-empty**, so a
scanner matching nothing cannot read as a pass.

Widening it from fixtures-only to every capturing invocation is deliberate and closes a hole
an earlier draft left. Fixture Makefiles are the ones §1's directive cannot reach, so they
were the obvious case; but the four repo-Makefile parses in `tests/makefile_scope.bats` are
green today *because of the environment leak*, not because they are correct. Run them outside
a `make test` context, or in a future where §1's line moves, and they parse directory lines
again. §1's own text argues that per-call flags "protect any invocation that does not go
through this `Makefile`" — leaving those four dependent on a global fact contradicts that in
the same document.

**Case 5 is the falsifiability guard.** It is the only case that would fail if the
`env -u MAKEFLAGS` discipline were dropped — it asserts the leak is still observable, which
is what proves cases 1 and 2 are measuring the Makefile rather than the environment.

### `PATH` — `tests/zshrc.d/unit.bats`

| #   | Case                                                                 | Expect                            |
| --- | -------------------------------------------------------------------- | --------------------------------- |
| 7   | With an ARM-prefix gnubin dir present, it is `path[1]`               | first element, not merely present |
| 8   | With only a `/usr/local` gnubin dir present, it is `path[1]`         | first element                     |
| 9   | Sourcing three times yields one entry                                | count unchanged                   |
| 10  | With neither dir present, no entry added and `PATH` otherwise intact | absent, rest unchanged            |
| 11  | Under `LINUX`, no gnubin entry is added **and** a known Linux path is | absent + **positive mirror**      |
| 12  | `_gnubin` does not leak into the environment after sourcing          | unset                             |

Case 7 asserts **position**, not membership: a membership check would pass for the append
idiom, which is inert. Case 8 is the ratna case.

Case 11 carries a positive assertion in the same harness on purpose. A pure absence
assertion under `LINUX` passes for a `6_path.zsh` that died on its first line — `shell.md`'s
own rule that a suite of negative assertions needs at least one positive assertion sharing
the harness. The same applies to case 19 below.

### Provisioning — `tests/setup_env/install_guards.bats`

| #   | Case                                                                    | Expect             |
| --- | ----------------------------------------------------------------------- | ------------------ |
| 13  | `gmake` present → no `brew install` call                                | idempotent skip    |
| 14  | `gmake` absent, brew present → `brew_install_formula make` called       | called once        |
| 15  | `gmake` absent, brew absent and uninstallable → returns 1, logs error   | rc=1               |
| 16  | Probe is `gmake`, not `make` (a stubbed 3.81 `make` must not satisfy it) | install still runs |

Case 16 is the mirror of case 7: it pins the one substitution that would make the component
inert on exactly the machines it targets.

### Ledger field — `tests/setup_env/update_summary.bats`

| #   | Case                                                            | Expect                    |
| --- | ----------------------------------------------------------------- | ------------------------- |
| 17  | `-t update` on macOS writes a make-version field on the entry    | field present, value `4`  |
| 18  | Unparseable/absent `make --version` records `unknown`, not a version | `unknown`, not `3`/empty |
| 19  | Linux: no make-version field **and** the entry is still written   | absent + **positive mirror** |
| 20  | Comparison is numeric, not lexicographic                          | 4.4.1 ≥ 3.81              |
| 21  | The field never changes the run's exit code                       | rc unchanged              |

Case 18 is the one that distinguishes a broken probe from a correctly-detected old make —
without it, an empty version string records identically to a real 3.81. Case 21 keeps the
component non-blocking, so a later change promoting it to a failure has to break a test
rather than slip through.

## Rollout risk

**No lockout path exists in this design.** §1 is inert on both versions. §3 no-ops when the
directory is absent. §4 warns. §2 runs only under `setup_user`. Nothing can prevent a
machine from running `make test`, committing, or pushing — which is the difference between
this revision and round 1, where the guard blocked `scripts/pre-push:71` on six
unprovisioned macs.

**The full suite passes under GNU Make 4.x — and, separately, with the directive actually
in place.** These are two different claims and round 2 caught them being conflated.

| measurement                                              | result                    |
| -------------------------------------------------------- | ------------------------- |
| 4.4.1 shim on `PATH`, **no** directive in the `Makefile` | `rc=0`, 1294 ok, 0 not ok |
| directive **in** the `Makefile`, `/usr/bin/make` 3.81    | `rc=0`, 1294 ok, 0 not ok |
| directive **in** the `Makefile`, 4.4.1 shim              | `rc=0`, 1294 ok, 0 not ok |

The first settles round 1's Goal-fit assumption: the rollout risk is "six machines need
provisioning", not "the suite is red on every mac at merge". The second and third settle
round 2's Ergonomics assumption, which correctly pointed out that the first measurement says
nothing about exporting a new variable into all 1294 tests' environments and silently
reflagging every descendant make. All three are `rc=0`.

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

**A report-only `_doctor_check_make_version` in `-t doctor`.** Round 2's §4. Dropped
because nothing reads it: `run_doctor` never writes a ledger entry, `~/.dotfiles-update.log`
is `-t update` only, and `-t doctor` is on-demand — so "divergence is visible" reduced to
"visible if a human happens to run doctor," while §1 removes the red-CI symptom that would
otherwise surface it. Replaced by the ledger field above rather than deleted, because the
divergence signal is worth having once it has a consumer.

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
| `lib/update_summary.sh`                  | make-version field on the ledger entry       |
| `.config/.zshrc.d/6_path.zsh`            | dual-prefix gnubin prepend                   |
| `tests/scripts/makefile_lint_scope.bats` | cases 1–6                                    |
| `tests/makefile_scope.bats`              | add `--no-print-directory` to lines 36/45/68/79 |
| `tests/zshrc.d/unit.bats`                | cases 7–12                                   |
| `tests/setup_env/install_guards.bats`    | cases 13–16                                  |
| `tests/setup_env/update_summary.bats`    | cases 17–21                                  |
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

### Round 3 — external architectural review (no lens dispatch)

Two findings, both accepted and applied above. Raised against the merged `9c7c8a3` text by an
independent reviewer outside the lens harness, so there is no assumption line to record.

**1. The `env -u MAKEFLAGS` rule was unenforced, and case 5 did not enforce it.** Case 5
asserts the leak is observable — a fact about make's behaviour, not about whether future tests
follow the discipline. A sixth case measuring directory output and forgetting `env -u` would
pass for the wrong reason: the defect shape §1 introduced, one layer out. Fixed by restating
the rule as a **guarded/measuring partition** and having case 4 assert it, which needs no
semantic judgment about what a test "measures" — the property that made the original rule
unenforceable. The residual gap (nothing verifies a test in the *measuring* set needs to be
there) is now stated in §1 rather than left implied.

**2. `tests/makefile_scope.bats`'s four parses had no stated outcome.** The Files-touched row
said "flag or cover by case 4" — two different outcomes. Case 4 as written covered fixture
Makefiles only, so those four repo-Makefile invocations fell outside it and "cover by case 4"
resolved to "leave alone". They are green today because of the environment leak, not because
they are correct. Fixed by widening case 4 to every stdout-capturing invocation and naming the
concrete edit: `--no-print-directory` on lines 36, 45, 68 and 79.

Neither finding changes the four components. Both change what the suite can catch.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger. Acceptance criteria are
concrete return codes and named structural assertions.
Disposition: N/A

### Round 2

The revision above changed design substance — a component was removed, not reworded — so all
three lenses re-run against it rather than only the lens that raised each finding.

Reviewed at commit: `c459705` (round-1 revision, before round-2 dispatch)

Round 2 found more than round 1, in text round 1 never read. Three findings were reproduced
directly by the author rather than accepted on report.

### Goal-Fit (round 2)

Finding: **§4 was decoration and Goal 3 was undelivered.** `_ledger_write_run_entry` is
called for `setup_user`/`setup`/`developer`/`recreate_venv`/`recreate_ruby` and never for
`run_doctor`; `~/.dotfiles-update.log` is `-t update` only. §4's entire product was one
terminal line from an on-demand command — no decision changed, no durable output. Also: case
4's oracle accepted "the repo Makefile has the directive" as blanket satisfaction, which
passes for exactly the fixture-Makefile call sites §1 cannot reach (24 in
`tests/setup_env/git_hooks.bats`, one in `pre_commit_hook.bats:25`). Also: the fan-out
non-goal was mislabelled — §3 is the fan-out; coverage extended to 9/9 repos and is clean.

Assumption (SETTLED — CONFIRMED): that the current Homebrew `make` formula still ships
`libexec/gnubin/make`, the sole mechanism connecting §2 to §3. The evidence on this box was a
directory dated Feb 2023, which attests to the 2023 formula rather than today's. Checked
against the live tap: `brew cat make` line 20 is
`(libexec/"gnubin").install_symlink bin/"gmake" => "make"`, and its caveats block prints
`PATH="#{opt_libexec}/gnubin:$PATH"` as the recommended remedy — so §3 is the approach
Homebrew documents, not a deviation. Stable and installed are both 4.4.1.

Disposition: **Addressed.** §4 rewired to a make-version field on the `-t update` ledger
entry — a field rather than a section, so `_UPDATE_SECTION_ORDER`'s two-place coupling is not
touched. Case 4 rewritten to discriminate repo-Makefile from fixture-Makefile invocations,
assert per-file flag counts, and require a non-empty scanned set. Fan-out relabelled as
measured 9/9 coverage.

### Ergonomics (round 2)

Finding: **Case 4 could not fail** — §1 made its OR-arm a global fact, so it was case 3 in
structural clothing. **Case 1 degenerated to 4.x-vs-4.x on the merge gate**, since
`ubuntu-latest` has no 3.81 arm. **`MAKEFLAGS` exports into every recipe's environment and is
inherited arbitrarily deep**, including into other repos — so the "per-repo" non-goal was
inaccurate and any future test invoking make from inside `make test` is green for the wrong
reason. **20 of 20 cases expected PASS**, with cases 10 and 19 pure absence assertions having
no positive mirror in the same harness. Day-to-day output cost: none found — `-w` still
overrides, recipe failures still print `file:line: target`, and the Makefile has no recursive
`$(MAKE)`.

Assumption (SETTLED — CONFIRMED): that the suite stays green with
`MAKEFLAGS += --no-print-directory` actually in the `Makefile` — a different change from the
shim-only measurement, which said nothing about exporting a variable into all 1294 tests'
environments. Measured both ways with the directive in place: `/usr/bin/make` 3.81 →
`rc=0`, 1294 ok, 0 not ok; 4.4.1 shim → `rc=0`, 1294 ok, 0 not ok.

Disposition: **Addressed.** Case 1 gains an explicit two-arm skip rule naming CI. Case 4
rewritten. Cases 11 and 19 gain positive mirrors sharing their harness. New case 5 asserts
the `MAKEFLAGS` leak remains observable, which is what proves cases 1–2 measure the Makefile
rather than the environment. `tests/makefile_scope.bats` added to scope.

### Risk (round 2)

Finding: **`MAKEFLAGS` is exported to the whole process tree, making the fix's own test class
unfalsifiable.** Reproduced by the author: a directive-free inner Makefile emits 3 lines
alone, 1 line when spawned from an outer make carrying the directive, and 3 again under
`env -u MAKEFLAGS`; `$MAKEFLAGS` in the recipe reads `[ --no-print-directory]`. Also: case 1
was a tautology in CI; report-only doctor plus a manual-only trigger plus §1 suppressing the
symptom meant nothing detected divergence; and case 16 could not distinguish "3.81" from "the
probe returned nothing".

Assumption (partially settled): that `ubuntu-latest` carries no GNU Make < 4.0 at any
reachable path. Not independently re-measured here; the spec now handles both branches by
making case 1 skip explicitly with a named reason when either arm is missing, so the case is
correct whichever way the assumption falls.

Disposition: **Addressed.** The export is documented in §1 as the most important fact in the
spec, with a binding harness rule (`env -u MAKEFLAGS`) and case 5 pinning it. Case 1's skip
rule names CI. §4 rewired to `-t update`. New case 18 records an unparseable version as
`unknown` rather than as a version.

### Round 3 — external architectural review (no lens dispatch)

Two findings, both accepted and applied above. Raised against the merged `9c7c8a3` text by an
independent reviewer outside the lens harness, so there is no assumption line to record.

**1. The `env -u MAKEFLAGS` rule was unenforced, and case 5 did not enforce it.** Case 5
asserts the leak is observable — a fact about make's behaviour, not about whether future tests
follow the discipline. A sixth case measuring directory output and forgetting `env -u` would
pass for the wrong reason: the defect shape §1 introduced, one layer out. Fixed by restating
the rule as a **guarded/measuring partition** and having case 4 assert it, which needs no
semantic judgment about what a test "measures" — the property that made the original rule
unenforceable. The residual gap (nothing verifies a test in the *measuring* set needs to be
there) is now stated in §1 rather than left implied.

**2. `tests/makefile_scope.bats`'s four parses had no stated outcome.** The Files-touched row
said "flag or cover by case 4" — two different outcomes. Case 4 as written covered fixture
Makefiles only, so those four repo-Makefile invocations fell outside it and "cover by case 4"
resolved to "leave alone". They are green today because of the environment leak, not because
they are correct. Fixed by widening case 4 to every stdout-capturing invocation and naming the
concrete edit: `--no-print-directory` on lines 36, 45, 68 and 79.

Neither finding changes the four components. Both change what the suite can catch.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
Disposition: N/A
