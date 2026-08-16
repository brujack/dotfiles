# ADR-0019: Shebang-derived shell lint scope

**Status:** Accepted
**Date:** 2026-08-15

## Context

`make lint`'s `SHELL_FILES` was derived by filename pathspec:

```make
SHELL_FILES := $(shell env -u GIT_DIR ... git ls-files '*.sh' '*.bash' 'scripts/pre-push' 'scripts/commit-msg')
```

A pathspec is extension-keyed. Every tracked shell script with no `.sh`/`.bash` suffix is
invisible to it, and the two extensionless hooks were reachable only by naming them
individually — a hand-maintained list, silently stale the moment a third one is added. That
list gated **35 of 101** tracked shell files; the missing 66 were the 64 extensionless mocks
under `tests/mocks/` and `config/local.sh.example`.

The omission is invisible in the gate's own output: an unlinted file is absent from scope and
report alike, so `make lint` prints the same clean result whether the set is complete or short
by sixty-five files. This is `tdd.md`'s Coverage Denominators failure, and the third instance
of it in this repo, after the bash coverage tracer's 13-entry `INCLUDE_FILES` array (ADR-0008)
and the Makefile-partition scanner's hardcoded two-file domain.

## Decision

Derive `SHELL_FILES` from each tracked file's first line via a new script,
`scripts/list-shell-files.sh`, rather than from a pathspec. The script reads the first line of
every file `git ls-files` reports (with the standard four-variable `env -u GIT_DIR
-u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE` strip, since a leaked `GIT_DIR` from a
worktree push resolves against the wrong repository without erroring) and keeps the ones whose
shebang names `bash`/`sh` — following `/` or `env `, so `#!/usr/bin/env zsh` and `#!/usr/bin/env
fish` are not mistaken for `sh` by a naive suffix match. `SHELL_FILES` now holds 100 files (99
plus the script itself, which is self-consistently linted by the gate it defines), and the two
named-hook entries are no longer special-cased.

## Consequences

**Positive.** `make lint` now gates 101 tracked shell files (100 via the script, plus itself)
instead of 35, with zero files lost — verified a strict superset of the prior scope by `comm
-23` in both directions. The five findings the widening surfaces (four `SC2086` in
`tests/mocks/brew`, needed for intentional word-splitting and suppressed at the site with the
mechanism named; one real `SC2034` in `tests/mocks/gpg`, fixed by renaming an unread loop
variable) are fixed in the same change. The `bash -n` arm's per-file `OK` line is collapsed
into a deferred one-line summary so `make lint`'s own output drops from 47 lines to 13, rather
than growing to 112. The empty-list guard's message now names the remedy
(`chmod +x scripts/list-shell-files.sh`) instead of only the possible cause, since a broken or
non-executable derivation script is now the dominant failure mode and
`scripts/pre-commit-hook.sh` runs `make lint` — a guard that locks the operator out of
committing the fix that would clear it is fail-locked, not fail-closed (ADR-0017).

**Negative.** A parse-time `git ls-files` walk plus a per-file `read` of the first line adds
+43 to +58ms to every `make` invocation, including `make help` — measured against a bare
pathspec's ~14ms over the same 406-file tree. The scope is now a script rather than a Makefile
one-liner, carrying its own bats suite (`tests/scripts/makefile_lint_scope.bats`, eleven
oracle cases plus mutation rows) instead of adding no test surface at all. `$(shell ...)`
discards the script's exit status, so a script that dies partway through yields a truncated but
non-empty list that the empty-guard cannot see — there is no runtime defence against this
(make offers `.SHELLSTATUS` only for `!=` assignments); the oracle's structural floor case is
what catches it, in the test suite rather than at runtime, and it is recorded here rather than
solved. Separately, no case pins that `SHELL_FILES` is _derived_ rather than _enumerated_ — a
hardcoded list of today's correct 100 files would pass every case now. It fails loudly rather
than silently, since the next file addition reddens the membership and floor cases, so it is
carried rather than closed.

### Rejected alternatives — both measured, not argued

**Inline `$(shell ...)` in the Makefile** — the same loop written directly into the
`SHELL_FILES` assignment — fails two independent ways, both only visible by running it.
`#` starts a comment in make, so the shebang literal needs escaping, and the escape is
version-divergent: GNU make 4.x passes `'\#!'` through to the shell verbatim, while 3.81
correctly emits `'#!'`. Since agent shells and git hooks on macOS resolve `/usr/bin/make` 3.81
while an interactive zsh resolves Homebrew 4.4.1 (ADR-0018), the identical recipe would behave
differently for a developer at a prompt than for the hook that actually gates — `shell.md`
pitfall G reproduced inside the fix for a different instance of pitfall G. Separately, escaped
spaces do not survive make's line-continuation processing; the observed expansion dropped the
loop body's argument entirely.

**An `awk 'FNR==1 && ...'` one-liner with a `HASH := \#` variable** to sidestep the comment
character does work correctly on both make versions. It is rejected on testability: it can
only be exercised through make itself, where a script is directly testable with bats — this
repo's idiom for every other Makefile-invoked check. The `HASH := \#` indirection is also the
kind of cleverness `code-standards.md` rejects on its own terms.

**A wider pathspec** — `git ls-files '*.sh' '*.bash' <hooks> 'tests/mocks/*'
'config/local.sh.example'` — produces a **byte-identical 100-file set today**, verified by
diff. So the script buys zero net files and zero net findings over a one-line pathspec
widening; any justification resting on scope size is false. What separates the two is
bidirectional correctness, not coverage, and it is measurable rather than asserted: a directory
glob cannot express "only the shell ones" in the other direction. Reproduced in a scratch
repo — after `touch tests/mocks/README.md`, the widened pathspec returns rc=1
(`SC2148: "Tips depend on target shell and yours is unknown"`) while the shebang-derived script
returns rc=0. The pathspec route turns `make lint` red, and therefore blocks `git commit`
(`scripts/pre-commit-hook.sh` runs it), for a Markdown file that was never meant to be linted.
The content-derived set self-corrects in both directions: a file enters scope when it starts
being shell, and leaves when it stops. That correctness property, not the file count, is what
+43ms and eleven test cases are paying for.

### Deferred repos, and the open reference-class question

math, ai-config, terraform_ansible, and etch-cli are unchanged. Net new lintable files if the
same derivation were applied: 4, 0, 0, and 0 respectively — ai-config's entire delta is 10
deliberately-defective pitfall fixtures (3 of which fail shellcheck at default severity by
design) and terraform_ansible's is 8 Jinja/Terraform templates, both of which would need an
exclusion predicate invented solely to gain nothing. Where a predicate is eventually wanted, it
belongs in `shell.md` as a stated rule — _a template extension (`.j2`, `.tpl`), or a
deliberately-defective pitfall fixture_ — never as a per-repo filename list, which is the exact
defect class this ADR removes.

Whether the underlying hazard generalizes beyond dotfiles is **left open, not settled**. A
fleet-wide sweep of every directory a pathspec would have to glob (not just `tests/mocks/`,
which reads 0 of 68 arrivals and looked like insurance against nothing until the question was
rescoped) found 20 non-shell arrivals across 136 total arrivals into such directories,
fleet-wide. 18 of those 20 are Python files landing beside hooks in repos that already carry
Python test suites in that same directory by design (math and terraform_ansible account for
15 of the 18), which is a narrower and more specific reference class than "any repo's
`scripts/` directory accumulates non-shell files at random." dotfiles itself has had exactly
one such collision ever — `scripts/dropbox.py`, present 2020-04-06 to 2023-11-24 — and it never
overlapped with the extensionless hooks, which arrived in 2026. Whether the Python-beside-hooks
pattern transfers to a shell-only repo like this one is not established by the sweep; it is
recorded as unresolved so a later reader does not treat the 20 figure as proof the hazard
applies here.

## Related

- `~/.claude/standards/tdd.md` — Coverage Denominators; the failure class this ADR is the
  third instance of.
- `~/.claude/standards/shell.md` — the `git ls-files` pathspec-cannot-express-"every-tracked-
  shell-script" pitfall, and pitfall G (version-divergent make behavior), reproduced here
  inside the rejected inline-`$(shell ...)` alternative.
- `docs/adr/0017-pre-push-trigger-fail-closed.md` — the fail-closed-vs-fail-locked distinction
  behind the empty-guard's remedy message.
- `docs/adr/0018-gnu-make-4-on-macos.md` — the make-version split (3.81 in agent/hook shells,
  4.4.1 in interactive zsh) that makes the inline-`$(shell ...)` escape divergence live rather
  than theoretical.
- `docs/superpowers/specs/2026-08-15-shell-lint-shebang-scope-design.md` — full design,
  measurement transcripts, the base-rate sweep, and the test oracle's four review rounds.
