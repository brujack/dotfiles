# GNU Make 4.x on macOS — design

**Date:** 2026-08-12
**Status:** Spec — awaiting review
**Backlog origin:** dotfiles#210

## Problem

macOS ships GNU Make **3.81** at `/usr/bin/make`. Apple froze it at the last GPLv2
release, so it is two decades old and will never advance. Every mac in this fleet is
therefore structurally incapable of failing for any behavioural difference introduced in
GNU Make 4.0 or later.

That is the `tdd.md` pitfall **G** class — "a test that shells out to a versioned tool
inherits that tool's version skew, and the local version may be unable to fail" — and it
is not hypothetical here. `scripts/pre-push` runs `make test`, so the local gate on every
mac blesses defects that `ubuntu-latest` rejects.

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

### A premise from the backlog row that did not survive checking

dotfiles#210's row asserted that a `6_path.zsh` change reaches interactive shells only,
and would therefore miss agent-driven and hook-driven invocations. **That is wrong**, and
it was the load-bearing claim in the row.

Measured: an agent tool's shell on this machine carries `~/bin`, `~/scripts`, and
`~/.cargo/bin` on `PATH`. All three are added by `.config/.zshrc.d/6_path.zsh` and by no
other file in the tree (`grep -rn 'HOME}/bin' ~/.config/.zshrc.d/ ~/.zprofile ~/.zshrc`
returns exactly one hit, at `6_path.zsh:11`). So those shells do source `.zshrc`, and a
`PATH` change there reaches them — and reaches any git hook they invoke, since a hook
inherits its invoker's environment.

What a `PATH`-only fix genuinely does not reach on macOS is narrower: `cron`/`launchd`,
and any non-zsh shell. Both are real; neither is the dominant path. The correction matters
because it changes which component is load-bearing — see "Rejected alternatives".

## Goals

1. `make` resolves to GNU Make 4.x on every mac in the fleet, for interactive shells,
   agent-driven shells, and the git hooks they invoke.
2. A machine where that provisioning has not happened **fails loudly** rather than
   reporting a false green.
3. The failure is recoverable without a chicken-and-egg lockout.

## Non-goals

- **Linux is untouched.** Ubuntu's `make` is already GNU 4.x. No Linux branch changes.
- **CI is untouched.** `ubuntu-latest` already runs 4.x; that is the version the gate is
  being aligned _to_.
- **`coreutils` / `findutils` stay as they are.** Both are installed and neither is on
  `PATH` under its GNU name. That is the same shape of gap, but only `make` has a measured
  defect behind it, and a GNU-first policy is a materially larger blast radius. Named here
  so the omission reads as a decision rather than an oversight.
- **No fan-out to other repos in this change.** The `PATH` half is inherently fleet-wide
  (it is the machine's `PATH`, so all nine repos get GNU Make 4.x for free). Only the
  Makefile guard is per-repo, and it stays in dotfiles until it has run long enough to show
  it does not misfire.

## Design

Four components.

### 1. Provisioning — `lib/macos.sh`, `lib/workflows.sh`

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
would exist only to have an empty arm. This also sidesteps a known contract hazard already
on the backlog: `install_bats`'s `if`/`elif` has no `else`, so it returns **0** when
neither `MACOS` nor `LINUX` is set, and `install_make || return 1` could not distinguish
"installed" from "no arm ran".

The probe is `quiet_which gmake`, not `make` — `make` is always present on macOS at 3.81,
so probing it would report success on precisely the machine that needs the install.

`brew "make"` already exists at `Brewfile:70`, so `brew bundle` parity is unchanged. The
new function exists because `setup_user` does not run `brew bundle`, and §3's guard is
absolute — provisioning has to be guaranteed by the workflow every machine runs, or the
guard becomes a lockout.

### 2. `PATH` — `.config/.zshrc.d/6_path.zsh`

Inside the existing `if [[ ${MACOS} ]]` block:

```zsh
if [[ -d /opt/homebrew/opt/make/libexec/gnubin ]]; then
  path=('/opt/homebrew/opt/make/libexec/gnubin' $path)
fi
```

**Prepend, not `path+=`, and this is the whole point of the component.** Measured: the
file's existing idiom is append (`path+=(...)`), which leaves `/usr/bin` ahead of anything
it adds — verified directly, `path+=` yields `first=/usr/bin` while `path=(dir $path)`
yields `first=/opt/homebrew/opt/make/libexec/gnubin`. An append here would be completely
inert and would look correct.

Homebrew deliberately installs GNU make as `gmake` and does not link it as `make`;
overriding that is a considered deviation, not an accident. The blast radius is exactly one
binary: `ls /opt/homebrew/opt/make/libexec/gnubin/` returns a single entry, `make`. This is
not a coreutils-style shadowing sweep.

Idempotency is free: `typeset -U path` at the top of the file dedupes, so re-sourcing
`.zshrc` any number of times yields one entry — verified with three consecutive prepends
producing three total path entries and no duplicates.

The directory-existence guard means a mac that has not yet run §1 simply does not get the
prepend, rather than acquiring a broken `PATH` entry.

### 3. Version guard — `Makefile`

```make
MAKE_MAJOR := $(firstword $(subst ., ,$(MAKE_VERSION)))

.PHONY: require-gnu-make
require-gnu-make:
	@[ "$(MAKE_MAJOR)" -ge 4 ] || { \
	  printf 'GNU Make >= 4.0 required (have %s).\n' "$(MAKE_VERSION)"; \
	  printf '  brew install make            # already in Brewfile\n'; \
	  printf '  ./setup_env.sh -t setup_user # durable fix\n'; \
	  printf 'Or run this suite directly: gmake test\n'; \
	  exit 1; }

test: require-gnu-make lint
bash-coverage: require-gnu-make
```

Verified on this machine against both versions:

| invocation                     | result                                |
| ------------------------------ | ------------------------------------- |
| `make test` under 3.81         | guard message, `rc=2`                 |
| `gmake test` under 4.4.1       | suite runs, `rc=0`                    |
| `make help` under 3.81         | works, `rc=0`                         |
| `MAKE_VERSION` read under 3.81 | populated — reports `3.81`, major `3` |

That last row is what makes the guard viable at all: the variable the guard reads is
present in the version being guarded against, so the check is not itself blind.

**Recipe-level, never parse-time.** The Makefile already carries a comment recording
exactly this constraint for `BATS_MISSING`: "`$(error)` fires wherever it is expanded, so
folding it into a `:=` assignment would abort every make invocation (including
`make help`) at parse time regardless of target." A `require-gnu-make` prerequisite target
keeps the check DRY and explicit without inheriting that hazard.

**Guards `test` and `bash-coverage`, deliberately not `lint`.** `lint` runs `bash -n`,
`zsh -n` and `shellcheck` — none of which care what version of make invoked them — and
`lint` is the pre-commit hook. Guarding it would lock an unprovisioned machine out of
committing the very change that provisions it. The targets guarded are the ones that
actually depend on make's own behaviour.

**No escape hatch.** No environment variable, no commit trailer, no bypass. Three things
make that safe rather than brittle: `lint` stays unguarded so committing always works;
`gmake` is already declared in `Brewfile` and now installed by `setup_user`, so the remedy
is available on any machine with brew; and the failure message names the remedy inline. An
`ALLOW_OLD_MAKE=1`-style hatch would be an allow-path looser than the deny-path, and a
banner that scrolls past while `rc=0` is what gets believed.

Prerequisite ordering note: `test: require-gnu-make lint` relies on left-to-right
prerequisite evaluation, which GNU Make guarantees only for non-parallel builds. This repo
never invokes `make -j`, and the consequence of reordering under `-j` would be that `lint`
runs before the guard fires — wasted work, not a wrong verdict.

### 4. Detection — new `_doctor_check_make_version` in `lib/helpers.sh`

A **new** check function, called from `run_doctor` alongside the existing
`_doctor_check_tools` / `_doctor_check_versions` / `_doctor_check_hooks_path` list, using
the established `_DOCTOR_PASS` / `_DOCTOR_FAIL` / `_DOCTOR_FAILED` convention so
`-t doctor` exits non-zero on failure. The failure text names the same remedy as §3.
macOS-only; returns without counting a check on Linux.

**It must not reuse `_doctor_check_one_version`, and this is the trap.** That helper asserts
a **pin** — its comparison is `[[ "${_installed}" == "${_pinned}"* ]]` against a constant
from `lib/constants.sh`. What is wanted here is a **floor**: any GNU Make ≥ 4.0 is correct,
so a machine on 4.3 must pass. Reaching for the existing helper, or adding a `MAKE_VER`
constant to feed it, would encode the wrong relation while looking like it followed the
established pattern. There is deliberately no `MAKE_VER` constant in this design.

This is the component that surfaces a mis-provisioned machine _before_ someone hits §3 the
hard way, and it is the only one that reports across the fleet rather than at the moment of
use.

Version parsing must not use string comparison — `shell.md`'s semver pitfall applies
(`[[ "4.4.1" < "3.81" ]]` is true under lexicographic `[[`). Extract the major component
and compare with `-ge`, the same way §3 does.

## Testing

Every component gets tests in the same commit as its code, per `tdd.md`.

### The guard's own test has the defect it guards against

A test asserting "the guard fires under 3.81 and passes under 4.4.1" cannot be validated by
a toolchain that only has one of them. This is `behavior.md`'s "a check derived from the
same decision as the thing it checks cannot falsify it", in its most literal form.

So the shim is a first-class part of the test, not a manual verification step:

```bash
shim="$(mktemp -d)"
ln -s "$(command -v gmake)" "${shim}/make"
PATH="${shim}:${PATH}" make -C "${REPO_ROOT}" test   # must succeed
```

Cases, in `tests/scripts/makefile_lint_scope.bats` (which already owns the make-invocation
tests and already carries the `--no-print-directory` rationale comment):

| #   | Case                                                              | Expect |
| --- | ----------------------------------------------------------------- | ------ |
| 1   | `require-gnu-make` exits non-zero under a 3.81 `make`             | rc≠0   |
| 2   | `require-gnu-make` exits 0 under a 4.x `make` (shimmed `gmake`)   | rc=0   |
| 3   | Failure message names both `brew install make` and `setup_env.sh` | match  |
| 4   | `make help` succeeds under 3.81 (guard is not parse-time)         | rc=0   |
| 5   | `lint` has no `require-gnu-make` prerequisite (lockout guard)     | absent |

Case 5 is a **negative structural assertion** and is the one that keeps the design's safety
property from silently eroding — someone adding the guard to `lint` later would restore the
lockout, and nothing else would catch it.

On a machine with no `gmake`, cases 2 and 3 `skip` with a stated reason rather than passing
vacuously.

### `PATH` tests — `tests/zshrc.d/unit.bats`

| #   | Case                                                                         | Expect                            |
| --- | ---------------------------------------------------------------------------- | --------------------------------- |
| 6   | With the gnubin dir present, it is `path[1]` after sourcing `6_path.zsh`     | first element, not merely present |
| 7   | Sourcing three times yields one entry (idempotency via `typeset -U`)         | count unchanged                   |
| 8   | With the gnubin dir absent, no entry is added and `PATH` is otherwise intact | absent, rest unchanged            |
| 9   | Under `LINUX`, no gnubin entry is added                                      | absent                            |

Case 6 asserts **position**, not membership. A membership assertion (`grep -q gnubin`)
would pass for the append idiom, which is inert — the test has to be able to fail for the
bug that would actually be written.

### Provisioning tests — `tests/setup_env/install_guards.bats`

| #   | Case                                                                     | Expect             |
| --- | ------------------------------------------------------------------------ | ------------------ |
| 10  | `gmake` present → no `brew install` call                                 | idempotent skip    |
| 11  | `gmake` absent, brew present → `brew_install_formula make` called        | called once        |
| 12  | `gmake` absent, brew absent and uninstallable → returns 1, logs error    | rc=1               |
| 13  | Probe is `gmake`, not `make` (a stubbed 3.81 `make` must not satisfy it) | install still runs |

Case 13 is the mirror of case 6: it pins the one substitution that would make the whole
component inert on exactly the machines it targets.

### Doctor tests — `tests/setup_env/unit.bats`

| #   | Case                                       | Expect             |
| --- | ------------------------------------------ | ------------------ |
| 14  | macOS, `make` reports 3.81 → check fails   | `_DOCTOR_FAILED`≠0 |
| 15  | macOS, `make` reports 4.4.1 → check passes | pass counted       |
| 16  | Linux → check does not run                 | not counted        |
| 17  | Comparison is numeric, not lexicographic   | 4.4.1 ≥ 3.81       |

## Verification before merge

Beyond `make test`, the PR must show the mutation check re-run under **both** make
versions, exactly as this spec's Problem section did — reverting `--no-print-directory` and
confirming red under 4.4.1 and green under 3.81. That is the evidence that the class this
whole change exists for is still reachable by the suite.

Also required: `zsh -i -c 'exit'` after the `6_path.zsh` change, per the repo convention
for any `.zshrc.d` edit.

## Rollout risk

Between this merging and `setup_env.sh -t setup_user` running on a given mac, `make test`
on that machine fails. That is up to six other machines: the laptop, three work macs, and
the mac mini.

Mitigations, in order of what actually carries the weight:

1. `lint` is unguarded, so committing and the pre-commit hook keep working. A machine can
   always commit its way out.
2. The guard message names both the one-shot fix and the durable one, matching the existing
   `BATS_MISSING` convention.
3. `gmake` is already installed on any mac that has run `brew bundle`, so on most machines
   the recovery is the `PATH` half alone.

This is a real interruption and the PR body must say so rather than describing it as
seamless.

## Rejected alternatives

**`PATH` prepend alone.** This was the original shape, and the correction in "A premise
that did not survive checking" makes it much stronger than first assessed — it reaches
agent shells and hooks, not just interactive terminals. It is still rejected, because
nothing detects a machine where it has not run. Silence is exactly the failure mode being
fixed; a fix whose absence is undetectable reproduces the original defect one level up.

**Guard alone, no `PATH` change.** Correct and loud, but every mac would fail `make test`
until fingers, hooks, and docs were retrained to `gmake test`. It optimises for purity of
mechanism over the ergonomics of the thing being used many times a day.

**Makefile re-execs itself under `gmake` when it detects 3.81.** Rejected on
`code-standards.md` grounds — clever is not a compliment. It would make the version that
actually ran a target invisible in the output, which is a strictly worse property for a
change whose entire purpose is making the running version legible.

**Warn-only now, fatal later.** Rejected: nothing schedules "later". A warn-only gate is a
gate that does not exist, and this repo already carries report-only checks that nobody
reads.

**Fan out the guard to all nine repos immediately.** Rejected on blast radius. `make lint`
is the pre-commit hook and `test: lint` makes it pre-push; a guard that misfires would lock
the whole fleet out of committing at once, including the commit that would fix it. dotfiles
carries it first.

## Files touched

| File                                     | Change                                        |
| ---------------------------------------- | --------------------------------------------- |
| `lib/macos.sh`                           | `install_make_macos()`                        |
| `lib/workflows.sh`                       | call it from `run_setup_user`'s macOS branch  |
| `lib/helpers.sh`                         | new `_doctor_check_make_version`               |
| `.config/.zshrc.d/6_path.zsh`            | gnubin prepend, macOS, dir-guarded            |
| `Makefile`                               | `MAKE_MAJOR`, `require-gnu-make`, two prereqs |
| `tests/scripts/makefile_lint_scope.bats` | cases 1–5                                     |
| `tests/zshrc.d/unit.bats`                | cases 6–9                                     |
| `tests/setup_env/install_guards.bats`    | cases 10–13                                   |
| `tests/setup_env/unit.bats` | cases 14–17                                   |
| `CLAUDE.md`                              | Testing + Key Conventions notes               |

## Related

- dotfiles#208 — the incident that measured the defect
- dotfiles#210 — the backlog row this spec supersedes
- `tdd.md` pitfall G — version skew in a shelled-out tool
- `behavior.md` — "a check derived from the same decision as the thing it checks cannot falsify it"
- `shell.md` — semver string comparison pitfall (§4)
