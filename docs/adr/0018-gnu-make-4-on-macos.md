# ADR-0018: GNU Make 4.x on macOS

**Status:** Accepted
**Date:** 2026-08-13

## Context

`shell.md`'s pitfall G (dotfiles#208) documented the class: GNU Make ≥ 4.0 prints
`Entering directory` / `Leaving directory` on stdout whenever `-C` changes directory;
3.81 does not. macOS still ships 3.81 at `/usr/bin/make`, so every mac in the fleet is
structurally incapable of failing for this class — a test that captures `make -C`
output and parses it stays green locally and can go red only on `ubuntu-latest`, where
the runner's `make` is already ≥ 4.0. Three tests in this repo shipped that shape and
passed two rounds of CI before the mismatch surfaced.

The gap is not cosmetic. A mac developer can write a test whose assertion is
structurally untestable on the machine they wrote it on, get a clean local run and a
clean `pr-review`, push, and only then discover the defect from CI — after the PR is
already open. Fixing the individual tests closes the instances found; it does not close
the class, because the next test with the same shape is exactly as blind on the next
mac.

Two things needed to be true at once: every mac's `make` had to actually resolve to
4.x (closing the class at the source, not just at the sites already found), and no
mechanism introduced to get there could be capable of blocking a machine from testing
or pushing. `USER.md`'s "fail closed on unknown" does not license a gate whose failure
mode is "the developer cannot commit the fix" — that is the inverse of fail-closed, it
is fail-locked.

## Decision

Align every mac's `make` with the version CI runs, and close the defect class at its
source, without any mechanism that can block a machine from testing or pushing.

**1. `MAKEFLAGS += --no-print-directory` at `Makefile:1`.** `MAKEFLAGS` is an exported
environment variable, so the directive is force-applied to every recipe subshell under
`make test`, `make lint`, and every other target — and an inherited `MAKEFLAGS`
suppresses the directory lines on **both** 4.3 and 4.4.1.

**Its scope is narrower than this ADR first claimed, and the correction is measured.**
The original text said it removed the variance "at every call site in the repo,
including ones not yet written." That is false on GNU Make 4.3, which is what
`ubuntu-24.04` — the `ubuntu-latest` image — ships. Measured on the Linux workstation
(Ubuntu 24.04, `/usr/bin/make` 4.3) against a fixture carrying the directive and a
control without it:

```
4.3    with directive: 3 lines    without: 3 lines    -> byte-identical, INERT
4.4.1  with directive: 1 line     without: 3 lines    -> suppressed
per-call --no-print-directory     -> suppressed on both
inherited MAKEFLAGS in env        -> suppressed on both
```

`-C` prints `Entering directory` **before** the Makefile is parsed, so a directive set
inside that Makefile arrives too late; 4.4.1 evidently changed this. The practical
consequence is bounded: under `make test` the exported variable does the work on every
version, so the repo's own invocations are covered. What is _not_ covered is a direct
`make -C … ` run outside an outer make on 4.3 — there the file directive does nothing.

So the load-bearing protection is the **per-call flag** and the partition that enforces
it, not this line. That is what `tdd.md` pitfall G prescribes first ("remove the
variance at the call site"), and reaching for a single-line file-level answer instead is
the shortcut this ADR is now the record of. The directive stays because it is correct
where it applies and costs nothing; it is no longer described as the fix.

This was found by CI, not locally: with only 3.81 and 4.4.1 on the authoring machine,
the 4.3 behaviour was structurally unobservable — pitfall G landing on the change that
exists to close pitfall G.

**2. `install_make_macos()` in `lib/macos.sh`, called from `run_setup_user`'s macOS
branch (`lib/workflows.sh:127`).** Probes `gmake`, never `make` — macOS always has
`/usr/bin/make` at 3.81, so probing `make` would report success on exactly the
machines that need the install. Installs via `brew_install_formula make` when `gmake`
is absent.

**3. A dual-prefix gnubin prepend in `.config/.zshrc.d/6_path.zsh`.** Homebrew's
`make` formula is keg-only; its `gnubin` directory symlinks `make` to `gmake`.
Prepending it ahead of everything else on `PATH` makes plain `make` resolve to GNU
4.x instead of the bundled `/usr/bin/make`. Both Apple Silicon
(`/opt/homebrew/opt/make/libexec/gnubin`) and Intel
(`/usr/local/opt/make/libexec/gnubin`) prefixes are checked, in that order, and the
loop takes the first that exists — a single Homebrew prefix assumption would have
silently no-op'd on ratna (`x86_64`, Homebrew at `/usr/local`).

**Its scope is narrower than "every mac resolves GNU make", and this is the second
scope correction in this ADR.** `6_path.zsh` is sourced by **interactive** zsh only, so
the prepend reaches a human at a terminal and nothing else. Measured on the Studio,
2026-08-13, on a fully provisioned machine:

```
interactive zsh      /opt/homebrew/opt/make/libexec/gnubin/make   GNU Make 4.4.1
non-interactive zsh  /usr/bin/make                                GNU Make 3.81
agent session shell  /usr/bin/make                                GNU Make 3.81
```

So every agent-invoked `make test`, every script, and the `pre-push` hook still resolve
3.81 — the actor that runs the gate most often is the one the fix does not reach. Both
numbers are correct; they describe different actors, and "the Studio's make version" has
no single answer.

The failure this creates is worse than the uniform blindness it replaced. Previously
every route on a mac returned 3.81, so nothing could confirm a ≥4.0 behaviour was
covered. Now a developer verifying by hand at a prompt gets 4.4.1 and concludes the class
is handled, while the run that actually gates gets 3.81 — the check answers for an actor
other than the one being checked. `tdd.md`'s privilege-fidelity rule (E3) is the same
shape one attribute over: a test running as root cannot validate an unprivileged guard,
and an interactive shell cannot validate what a hook resolves.

Whether to widen the prepend is deliberately **not** decided here. Putting gnubin on a
non-interactive `PATH` changes the toolchain underneath every hook and script on the
machine, which is its own hazard and a larger change than this ADR's; it is filed as a
backlog row instead. What is decided is that the claim now matches the measurement.

**4. A `make_version` field in the state-ledger base JSON (`lib/update_summary.sh`).**
macOS-only, populated from `make --version` (not `gmake --version`) specifically
because the field exists to catch the case where GNU make 4.x is installed but the
gnubin PATH prepend isn't in effect and `make` still silently resolves to the bundled
3.81. Probing `gmake` would hide exactly the drift the field exists to surface. The
value is validated with a regex (`^[0-9]+$`) before any numeric comparison — an
unvalidated `-ge`/`-lt` on a raw `grep` match would treat a non-numeric,
identifier-shaped operand as bash arithmetic's silent 0 rather than falling through to
`"unknown"`.

**Plus a repo-wide test invariant.** Every stdout-capturing `make -C` invocation in a
`.bats` file must be in exactly one of two states: **guarded** (a per-call
`--no-print-directory`) or **measuring** (`env -u MAKEFLAGS`, verifying the version
behavior itself). A scanner in `tests/scripts/makefile_lint_scope.bats` enforces this
over the tracked `.bats` set and asserts both sets are non-empty, so the invariant
cannot pass vacuously by having zero of either kind.

## Consequences

**Positive.** Every mac in the fleet now resolves `make` to 4.x **at an interactive
prompt** through the same mechanism CI uses to provision `ubuntu-latest`'s runner,
closing the version-skew class for the human rather than patching the three tests that
had already tripped on it. Agent shells, scripts, and git hooks still get 3.81 — see the
scope note under decision 3; this sentence originally omitted the qualifier and claimed
the fleet outright. A future `-C` call
site is covered **when it runs under an outer make** — `MAKEFLAGS` is exported and an
inherited value suppresses on both 4.3 and 4.4.1 — but not when it runs standalone on
4.3, which is why the partition scanner rather than the directive is what makes the
invariant hold. The `make_version` ledger field makes a machine whose
gnubin prepend silently isn't in effect queryable across the fleet, rather than visible
only at that machine's own terminal the next time someone happens to run `make -n`
there.

**Negative.** The scanner is a structural, not semantic, check — see the accepted gap
below. The `Makefile` directive is version-dependent for `-C` (inert on 4.3, effective
on 4.4.1), so it must not be cited as the reason a call site is safe; only the per-call
flag and the exported-variable path hold on every version. The ledger schema addition is a shared-schema change (see below), and the
gnubin dual-prefix path list is now something that has to be kept in sync if Homebrew
ever changes its keg-only layout.

### The rejected enforcement guard

The original design's centerpiece was a `require-gnu-make` Makefile target: a guard
that would hard-fail `test` and `bash-coverage` under GNU Make < 4.0, on the theory
that a version mismatch should block the gate outright rather than rely on every
individual test guarding itself. It was **dropped, not repaired**, on five grounds —
four reproduced by measurement during this branch's review rounds (commits `c974e4b`,
`79c0a1f`, `4aa286e`, `3cfad7f`, `562ffca`, `e42bd94`; full transcripts in
`docs/superpowers/specs/2026-08-12-gnu-make-4-on-macos-design.md`):

- **Bypassable.** `MAKE_VERSION` is an ordinary make variable, settable from the
  command line like any other. `/usr/bin/make guard MAKE_VERSION=4.9` printed `PASSED`
  under real GNU Make 3.81 and exited 0. The design had claimed "no escape hatch"; the
  hatch was undocumented and traceless.
- **Its printed remedy was a false green.** Make does not propagate itself to a bare
  `make` invoked from within a recipe. An outer `gmake` whose recipe ran
  `make --version` reported `GNU Make 3.81` — so the guard's own suggested remedy
  (`gmake test`) would have run the outer make at 4.4.1 while every bats test inside
  still resolved `make` through `PATH` to 3.81, the exact drift the guard exists to
  catch.
- **It blocked `git push`.** `scripts/pre-push` runs `make -C "${REPO_ROOT}" test`, so
  the guard fired there too. The design's stated mitigation — "lint is unguarded, so a
  machine can commit its way out" — was true and useless: an unpushable commit is not a
  recovery path.
- **It could not run in CI.** `ubuntu-latest` has neither a 3.81 `make` nor a `gmake`,
  so the guard's own negative-case tests would skip in the one environment that gates
  merge.
- **Intel lockout.** With a hardcoded `/opt/homebrew` PATH assumption, the guard's own
  remediation path would silently no-op on ratna (`x86_64`, Homebrew at `/usr/local`)
  while the guard itself still fired.

The replacement is the four components above plus the scanner: no target anywhere in
this repo can refuse to run because of the local `make` version. The version skew is
closed by making the correct `make` the one that's actually on `PATH`, not by refusing
to proceed when it isn't.

### The `MAKEFLAGS` export and the measuring-test partition

`MAKEFLAGS` is an environment variable, not a file-local directive, so every `make` a
test spawns inherits it once the Makefile sets it — including a test that means to
_measure_ the print-directory behavior itself. A test asserting "GNU Make 4.x prints
directory lines" that doesn't strip `MAKEFLAGS` first will observe no directory lines
regardless of the real make version, and pass for the wrong reason. This is why the
partition is enforced per-invocation by the `tests/scripts/makefile_lint_scope.bats`
scanner rather than by a single canary test: a canary only proves the leak is absent in
the one case it names; when a guard is dropped from a _different_ call site and a leak
is present there, that case goes blind, it does not go red.

### The ledger schema addition

`make_version` was added to the base JSON in `lib/update_summary.sh`, which all six run
types share and which declares `"schema_version": "1.0"`. Additive, macOS-only fields
are safe for any consumer that ignores unknown keys, but it is a change to a shared
schema and is recorded here as a decision rather than left as an implementation detail
a future reader has to reconstruct from the diff.

### A system binary is now shadowed by a user-writable one

Prepending `gnubin` changes which `make` a shell resolves, and with it who owns that
file. Measured on the Mac Studio:

```
/usr/bin/make                           root wheel    (root-owned)
/opt/homebrew/opt/make/libexec/gnubin   bruce admin   (user-writable)
```

This is the first place in `6_path.zsh` where a root-owned system binary is
deliberately shadowed by a user-writable one, and it is unavoidable given the goal —
Homebrew installs under a user-owned prefix on Apple Silicon, so there is no way to
put GNU Make 4.x ahead of `/usr/bin/make` without it.

It grants no capability an attacker did not already have. `~/bin`, `~/scripts` and
`~/.cargo/bin` are already on `PATH` from this same file, `/opt/homebrew/bin` was
already appended before this change, and `.zshrc` itself is user-writable — anyone who
can write to `gnubin` can write to all of those. What changed is narrower: previously
`/usr/bin` won for any name present in both, so `make` specifically resolved
root-owned; now it does not.

Recorded because the reasoning that makes it acceptable is worth writing down once
rather than re-deriving. A future change that widens the prepend beyond this single
directory — `coreutils`' `gnubin` holds ~100 binaries against this one's single
`make` — is a materially different trade and should be argued on its own terms, not
inherited from this decision.

### A named, accepted gap

The scanner is a line-level pattern match, not a make-semantics parser. It cannot see a
recursive sub-make (`$(MAKE)` invoked from within a recipe) or `make -w`, both of which
print directory lines with no `-C` on the line the scanner reads. A static scanner
cannot determine whether a target recurses without evaluating the Makefile itself. This
is not reachable today — the root `Makefile` has no `$(MAKE)` recipes — and is recorded
as an accepted gap rather than closed, per the same reasoning that dropped the
`require-gnu-make` guard: a mechanism that would need to grow into a real Makefile
parser to close a gap that isn't currently exploitable is not worth the complexity it
would add to a test scanner.

## Related

- `~/.claude/standards/shell.md` pitfall G — the version-skew class this ADR closes at
  the source, including the reproduction of `--no-print-directory`/`--porcelain`-style
  fixes as the preferred remedy over parsing around the variance.
- `docs/superpowers/specs/2026-08-12-gnu-make-4-on-macos-design.md` — full design,
  measurement transcripts for all five rejected-guard grounds, and the scanner's bypass
  enumeration.
- `docs/adr/0017-pre-push-trigger-fail-closed.md` — the "fail closed on unknown, but
  never fail-locked" distinction this ADR's rejected-guard section turns on: a gate that
  blocks the fix from being pushed is not fail-closed, it is fail-locked.
