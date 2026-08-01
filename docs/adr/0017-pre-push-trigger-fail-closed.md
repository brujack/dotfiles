# ADR-0017: The pre-push trigger fails closed

**Status:** Accepted
**Date:** 2026-08-01

## Context

`scripts/pre-push` decides whether `make test` runs before a push reaches GitHub. It
decided by **allowlist**: a `grep -qE` alternation of patterns that should trigger the
suite. Anything not matching was skipped silently.

That shape failed four times in a single session, each instance found by a different
gate, each a real file class that `make test` genuinely depends on:

| #   | Missed class                             | How `make test` depends on it                                                                                  | Found by                  |
| --- | ---------------------------------------- | -------------------------------------------------------------------------------------------------------------- | ------------------------- |
| 1   | `scripts/pre-push`, `scripts/commit-msg` | Executed against the real file by `tests/scripts/*.bats`; extensionless, so no extension rule matched          | dotfiles#191 bug-scan     |
| 2   | `.config/.zshrc.d/*.zsh` (7 files)       | `tests/zshrc.d/unit.bats` runs `zsh -n` on each                                                                | `bug-scan`, this session  |
| 3   | `.shellcheckrc`, `.gitignore`            | `make lint` reads the former (`test: lint`); `tests/setup_env/unit.bats:676` greps the real latter             | `bug-scan`, this session  |
| 4   | `ubuntu_*_packages.txt` (5 files)        | `lib/linux_ubuntu.sh` reads them by relative path; `tests/setup_env/linux_ubuntu.bats` asserts on real content | `pr-review`, this session |

Instance 4 is the decisive one. It was found _after_ a `bug-scan` pass had enumerated
all 392 tracked files and declared the dependency set closed. A careful, explicit
enumeration still missed a class — which is the strongest available evidence that the
problem is not insufficient care.

**The failure directions are asymmetric.** Under-triggering fails **open**: a push that
breaks `make test` sails past the local gate, reaches CI, and burns exactly the
GitHub Actions minutes the hook exists to conserve. Over-triggering costs local
wall-clock and nothing else. An allowlist defaults to the expensive direction for
every file class nobody thought to enumerate, and the set of such classes is not
knowable in advance — it grows whenever a test starts reading a new real file.

This is the case `USER.md` already covers: _fail closed on unknown; unknown ≠ safe_.
The allowlist inverted that default.

## Decision

**The trigger fails closed.** `make test` runs unless _every_ changed path is provably
inert:

```bash
changed="$(git diff --name-only "${range}" 2>/dev/null)"
diff_rc=$?
if [[ ${diff_rc} -ne 0 ]]; then
    # Cannot determine what changed — fail closed.
    needs_test=1
elif printf '%s' "${changed}" | grep -qvE '\.md$|^\.github/.*\.ya?ml$|^LICENSE$'; then
    needs_test=1
fi
```

The `diff_rc` branch matters and was added after review. Piping `git diff` straight
into `grep` discards git's own exit status — the pipeline reports grep's. A `remote_sha`
naming an object the local repo lacks makes `git diff` fail with empty stdout, `grep -qv`
returns 1, and the gate is skipped with no claim of irrelevance at all. `set -e` cannot
catch it either: the status is grep's, and the pipeline sits inside an `if`, where
`set -e` is disabled. On a seven-machine fleet where branches move between boxes, that
is reachable.

`grep -qv` succeeds when any changed path does **not** match the inert set, so a single
unrecognized path is enough to run the suite. Skipping now requires an affirmative
claim that every changed file is irrelevant, rather than an omission from a list.

The inert set is deliberately small and each member is justified:

- `\.md$` — no `.md` file is read by `make test`. The two that tests reference
  (`CLAUDE.md`, the Cursor `.mdc` mirror) are reached only through
  `_OVERRIDE_CLAUDE_MD_PATH` / `_OVERRIDE_TARGET_PATH` fixture seams, and
  `make check-agent-guidance` is not part of `make test`.
- `^docs/.*\.md$` — ADRs, specs, plans, knowledge. Scoped to `.md` deliberately; see
  the correction below.
- `^\.github/.*\.ya?ml$` — CI workflow definitions. They configure the _remote_ gate.
  Also scoped by file type, same reason.
- `^LICENSE$` — inert by construction, anchored at both ends.

Anything else — including any file class introduced in future — runs the suite until
someone makes a deliberate, reviewed decision to add it to the inert set.

### Correction: the first draft of this inert set reproduced the very bug it fixes

This ADR originally listed `^docs/` and `^\.github/` unscoped, justified as "nothing
under `make test` reads them," plus a `^CHANGELOG` member. The Phase 3 gate chain
found all three wrong before merge:

- **`^docs/` and `^\.github/` were false.** `make test` depends on `lint`, and
  `SHELL_FILES := $(shell find . -name "*.sh" ...)` globs **recursively** with only
  `node_modules`/`coverage` excluded. A `docs/gen.sh` or `.github/scripts/foo.sh` is
  therefore shellchecked by `make test` while being invisible to the trigger —
  confirmed empirically. That is instance-class #3 from the table above
  (`.shellcheckrc` → `make lint` → `test: lint`) reproduced inside the fix for it.
- **`^CHANGELOG` was unanchored and redundant.** It absorbed `CHANGELOG_gen.sh` and
  `CHANGELOGS/build.sh`, while the only tracked file it was meant to cover
  (`CHANGELOG.md`) was already inert via `\.md$`. Deleted rather than anchored.

The fix scopes the two directory members to their real file types rather than
narrowing `SHELL_FILES` — shrinking what gets linted to make this ADR's excuse true
would trade a real gate for bookkeeping.

**The lesson is the one this ADR is about.** Inverting to fail-closed does not
eliminate the failure mode; it relocates it from "forgot a trigger" to "wrongly
declared something inert," which is what the Consequences section predicted. The
relocation is still worth it — the new failure mode requires an explicit edit to a
short list, every member is now pinned by a test, and the mistake was caught by a
gate before merge rather than by a silently-skipped push afterwards. But "fail-closed"
is not self-enforcing, and this correction is the evidence.

## Consequences

**Positive.** The four historical misses are closed by construction, not by
enumeration, and so is every class not yet thought of. The next equivalent mistake
costs a few minutes of local test time instead of a silently-skipped gate. Adding to
the inert set is now a visible, reviewable act.

**Negative.** More pushes run the suite. Concretely: 192 of 392 tracked files trigger
under the new rule versus a smaller set before, and a push touching only, say,
`starship.toml` or `.vimrc` now runs ~1100 tests where it previously did not. That is
the cost being deliberately bought, and it is bounded — the suite is local, the
alternative failure is a red CI run plus a round trip.

**Test semantics change.** Two negative tests written under the allowlist assert that
`.zshrc` and `.gitignore_global` do _not_ trigger. Under fail-closed they correctly
_do_ trigger, because neither is inert. Those assertions are inverted rather than
deleted — the change in their expected value is precisely what this ADR decides.

**The inert set is now the thing to guard.** The failure mode moves from "forgot to add
a trigger" to "wrongly added something inert." The latter is far easier to catch: it
requires an explicit edit to a short, commented list, and every member is pinned by a
test.

## Related

- `USER.md` — "Fail closed on unknown. Unknown ≠ safe." and "Allow-paths must be as
  tight as deny-paths."
- `docs/superpowers/specs/2026-07-31-git-hook-detection-gaps-design.md` — the spec this
  supersedes the trigger design of; records all four instances and the review trail.
- ADR-0016 — auto-install git hooks; the mechanism that puts this hook on all seven
  machines.
