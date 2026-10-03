# Direct-to-master guard: default-deny

**Date:** 2026-10-02
**Status:** Approved 2026-10-02

## Problem

`ci.yml` runs on `pull_request` only, so a commit pushed straight to `master` is tested by
nothing except the local pre-push hook, which runs the suite on the pushing machine. Since
2026-09-19 that machine is the Linux `claude` box, so a direct push is never tested on macOS.
dotfiles#306 made every PR run the suite on macOS; this closes the other route.

`scripts/pre-push` already refuses a push to `refs/heads/master` whose range carries an
"executable-class" path. The class is a deny list:

```
\.(sh|bash|bats|zsh)$|(^|/)Makefile$|^scripts/(pre-push|commit-msg)$
```

Tracked code and config files this list lets through, measured 2026-10-02 at `b0e4def1`:
68 `tests/mocks/*` (extensionless shell), 5 `*.py`, `.zshrc`, `.zprofile`, `pyproject.toml`,
`uv.lock`, five `requirements-*.txt` and two workflow files. The guard's own comment records
that the narrow scope was chosen deliberately and that `tests/mocks/*` was a known gap. The
operator reversed that on 2026-10-02: no code reaches `master` except through a PR; docs may
still go direct, untested.

### How `master` is actually written

Measured 2026-10-02 on a clone with history back to 2026-05-25, first-parent commits on
`master` since 2026-06-01. **The first version of this spec measured on the main checkout,
which is a shallow clone holding 19 commits, and reported 11 non-PR commits, all `.md`. Both
figures described four days, not four months.**

|                                                                                        | commits |
| -------------------------------------------------------------------------------------- | ------- |
| first-parent commits                                                                   | 750     |
| subject without a `(#NNN)` PR suffix                                                   | 561     |
| of those, authored by `github-actions[bot]` (pushed by CI, not through any local hook) | 12      |
| refused by today's deny list, applied retroactively                                    | 18      |
| refused if only `.md` (outside `tests/`) and `LICENSE` were allowed                    | 42      |
| refused under this design (below)                                                      | 28      |

The 10 commits this design refuses that today's list would not: `.warp/settings.toml` (4),
`renovate.json` (3), `ubuntu_common_packages.txt` (1), `scripts/phrase_check.py` with its
test (1), `.github/workflows/ci.yml` (1). About three a month.

**Two scripts push to `master` every week.** One of them writes a non-`.md` state file.
`scripts/whats-new-anthropic.sh` and `scripts/whats-new-claude-code.sh` commit a digest
under `docs/` together with a state file (`docs/anthropic-new-features/.platform-state.txt`
and similar) and push it; a refused push leaves the commit on local `master`, unpushed, and
every later docs push from that checkout is then refused for a file the session never
touched. Last runs: 2026-09-28.

### Defects in the current hook that this design must not carry over

1. **The guard fails open when the range cannot be resolved.** A failed `git diff` sets
   `needs_test=1` and leaves `changed` empty, and the guard only runs when `changed` is
   non-empty (`scripts/pre-push:74`). Reproduced by the round-1 risk lens in a scratch repo:
   a push to `refs/heads/master` carrying `x.sh`, with a `remote_sha` the repository does not
   have (a force-push over an unfetched remote), ran the suite and exited 0.
2. **Two lists for one question.** "Does this push need the suite?" uses an inert set
   (`\.md$|^\.github/.*\.ya?ml$|^LICENSE$`, anything under `tests/` always triggering);
   "may this go direct?" uses the deny list. They already disagree.
3. **The inert set calls workflow files inert.** Six test files read `ci.yml`
   (`requirements_ci.bats`, `shellcheck_pin.bats`, `pre_push.bats`, `auto_merge_gate.bats`,
   `makefile_lint_scope.bats`, `test_phrase_check.py`), so a `ci.yml`-only push skips them.
4. **Renames hide the old path.** `git diff --name-only` reports only the new name of a
   rename. Measured in a scratch repo: after `git mv x.sh x.md` the default form prints
   `x.md`, and `--no-renames` prints `x.md` and `x.sh`.
5. **Non-ASCII paths are quoted.** `git diff` prints `"docs/caf\303\251.md"`, which matches
   no pattern. That fails safe, but it would refuse a legitimate docs push.

No test reads the repository's real `.md` files outside `tests/`: a grep of `tests/`,
`scripts/*.py` and the `Makefile` finds only fixtures, `test_relocation_check.py` reads
`CLAUDE.md` only at the pinned revision `2e38f5e4`, and `check-agent-guidance` is not a
prerequisite of `make test`. That premise holds today and nothing enforces it.

## Design

### One predicate

`scripts/pre-push` gets one function, `_path_is_inert <path> <local_sha>`, returning 0 when
the path cannot change the suite's result. A path is inert only when both hold:

1. **By name:** it is a `.md` file anywhere except under the repository-root `tests/`
   directory, or it is `LICENSE` at the repository root.
2. **By content:** its blob at `<local_sha>` does not start with `#!`. `make lint` selects
   shell files by their first line, whatever their name (`scripts/list-shell-files.sh`), so
   a `.md` that starts with a bash shebang is linted and is not inert. Measured in round 2:
   a `docs/evil.md` and a root `LICENSE` starting `#!/usr/bin/env bash` both joined
   `SHELL_FILES`.

How the content is read matters, and round 3 found the obvious way wrong. `git cat-file -p
<sha>:<path> | head -c 2` returns 141 under `pipefail` for any blob larger than the pipe
buffer (measured: a 300 KB blob gave 141), and `CLAUDE.md` and `docs/superpowers/README.md`
are both larger than that. Without `pipefail` a failed read is invisible instead. So:

- `git cat-file -e <local_sha>:<path>` fails: the path was deleted; judge it by name alone.
- `git cat-file -t <local_sha>:<path>` is not `blob` (a gitlink, say): not inert.
- Otherwise read the first two bytes with `head -c 2 < <(git cat-file blob <local_sha>:<path>)`,
  a process substitution, so no pipeline status is involved.

The check refuses any `#!`, while `make lint` selects only bash and sh shebangs. That is
stricter than needed and costs nothing: no tracked `.md` or `LICENSE` starts with `#!`.

Everything else is not inert, including any file type added in future. There is no rule
for other files under `docs/`. The one non-`.md` file the weekly digest writes,
`docs/anthropic-new-features/.platform-state.txt`, is renamed to `.platform-state.md` in
this change with `git mv`, so its content carries over, together with the one line in
`scripts/whats-new-anthropic.sh` that names it, `docs/anthropic-new-features/README.md:8`,
and the six lines of `tests/scripts/whats-new-anthropic.bats` that use the name. Without the
content, the first digest after the rename finds no state and reports the whole platform
release-notes page as new.

The function is only ever called in a conditional context (`if`, `&&`, `||`), because the
hook runs under `set -e` and a bare call returning 1 would kill the hook with no message.

Both decisions use it:

- **Suite trigger:** run `make test` unless every changed path is inert (ADR-0017's shape).
  Behavioural change: `.github/*.yml` now triggers.
- **Direct-to-master guard:** refuse a push to `refs/heads/master` when any path in the range
  is not inert, or when the range cannot be resolved.

### Changed paths

Both decisions read `git -c core.quotePath=false diff --no-renames --name-only "${range}"`,
one path per line, so a rename reports both paths and a non-ASCII name arrives as written.
Git still C-quotes a path containing a newline, tab, `"` or `\` (measured: `"docs/nl\nx.md"`
arrives as one quoted line). A quoted path matches no inert name, so it is refused. That is
the safe direction and is accepted.

### The refusal messages

**When paths are refused**, the message names every one, says that only `.md` files and
`LICENSE` may go to `master` directly, and gives the recovery for what was pushed. The choice
is made from the ref line's `local_ref`, not from the current branch, because a session on
`feat` can still run a push of local `master`:

- `local_ref` is `refs/heads/master`: create a branch from local `master` (the refused
  commits come with it), push that branch and run `gh pr create --fill`, then
  `git switch master && git reset --keep origin/master`. If `reset --keep` refuses because an
  uncommitted change touches a file in those commits, commit or set aside that change first;
  nothing has been lost. In a worktree, where `master` is checked out elsewhere, run the
  reset in the main checkout.
- `local_ref` is another branch, `refs/heads/<b>`: push `<b>` itself
  (`git push -u origin <b>`) and run `gh pr create --fill`.
- `local_ref` is `HEAD` (a detached HEAD): create a branch first (`git switch -c <name>`),
  then as above.
- In an emergency (`hotfix-cycle`, `rollback-cycle --reason ci-red`): open the PR the same
  way and merge it with `gh pr merge --admin`, which bypasses failing required checks because
  `enforce_admins` is off. Do not use `--no-verify`; `hotfix-cycle` forbids it.

**When the range cannot be resolved**, a separate message says so, names the ref, and says
to `git fetch` and retry. Measured in round 2: a shallow, stale checkout whose remote had
moved on reaches the hook with a `remote_sha` it does not have, for a push git is about to
reject as "fetch first" anyway. A fetch clears it.

Because the hook decides for the whole push, a single push carrying both a branch and a
refused `master` refuses the branch too. The message says to push the branch on its own.

### Unchanged behaviour

- The guard evaluates the whole push range, not the tip commit. Only the tip's content lands
  on `master`, so the content check reads the blob at `<local_sha>`.
- The refusal is accumulated inside the stdin loop and read after it, before the
  `needs_test` early exit.
- Branch pushes are never refused; they only decide whether the suite runs.
- A deletion-only ref line (`local_sha` all zeros) is skipped, as today.
- `--no-verify` still bypasses the hook.

### What newly needs a PR, and what that costs

Every file that is not an inert `.md` or `LICENSE`: `.warp/settings.toml`, `renovate.json`,
`.gitleaks.toml`, `.gitignore`, `starship.toml`, `ubuntu_*_packages.txt`,
`.claude/settings.json`, workflow files, `docs/cursor/plans/.gitkeep`, and all code. The
measured cost is the 10 commits listed in the Problem section over four months.

**Other layers still say some of these may go direct**, and a session reads them before it
reaches this hook: the global `git-workflow.md` standard (`renovate.json`, `.gitleaks.toml`,
some `.claude/settings.json` keys) and ai-config's `sdlc-branch-guard` (`*.txt`,
`renovate.json`, `.gitleaks.toml`, `.editorconfig`, `.gitignore`); `hotfix-cycle` and
`rollback-cycle` authorize direct pushes in general. In dotfiles the hook is the stricter
rule and wins. The refusal message is where a session learns that, so it carries the
recovery and the emergency route. `CLAUDE.md` states the rule too. Aligning the global
standard and the ai-config guard is an ai-config backlog row, not part of this change.

### The docs-are-inert premise is pinned by a test

Direct `.md` pushes are untested, which is safe only while nothing `make test` runs reads a
tracked `.md` outside `tests/`. That holds today and three review lenses named it as the
design's remaining assumption, so a new bats file, `tests/scripts/docs_inert_premise.bats`,
pins it in two parts:

1. **The prerequisite chain is an allowlist.** The test reads `make`'s own database
   (`make -pn test`) for the prerequisites of `test` and compares them, recursively, with a
   recorded list: today `lint check-lock check-requirements-ci test-python`. A new
   prerequisite fails the test with a message saying to check whether it reads a tracked
   `.md` and, if not, add it to the list. `check-agent-guidance`, which reads `CLAUDE.md`,
   is named in the message as the known reader.
2. **No test reads a real `.md` by path.** It scans `tests/**/*.bats`, `tests/**/*.py` and
   `tests/helpers/*` for a path built from the repository root that ends in `.md` outside
   `tests/` (shell forms such as `"${REPO_ROOT}/CLAUDE.md"`, Python forms such as
   `REPO_ROOT / "CLAUDE.md"`). Today there are none. An entry on a recorded allowlist, with
   its reason, exempts a file; `tests/test_relocation_check.py` needs none, because it reads
   `CLAUDE.md` only through `git show 2e38f5e4:CLAUDE.md` at a pinned revision.

Both parts are heuristics over text, so each carries a positive control: a scratch copy
with `check-agent-guidance` added to `test:` must fail part 1, and a fixture test file
reading `"${REPO_ROOT}/README.md"` must fail part 2.

### The hook can block every push, including its own fix

`.git/hooks/pre-push` is a symlink to the main checkout's `scripts/pre-push`, on every
development machine (measured on `claude`, Studio and workstation). The hook that judges a
push is the main checkout's copy, not the branch being pushed. So:

- While this change is developed, the old hook judges its pushes; the new logic is exercised
  only by bats.
- Once merged, a defect that makes the hook exit non-zero blocks branch pushes too. The
  recovery is a fix branch pushed with `--no-verify`, which then goes through PR and CI.
  `CLAUDE.md` states this as the one sanctioned use.
- The tests below run the real hook end to end under `set -e`, so a silent death fails a
  test rather than every push.

## Verification

All rows run the real hook against fixture repositories in `tests/scripts/pre_push.bats`.

| check                                                                                                                                                                              | expected                                                                                                |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Push to `master` carrying, one per case: a `tests/mocks/` file, a `.py`, `.zshrc`, `uv.lock`, `ci.yml`, `.warp/settings.toml`, `renovate.json`, `docs/x/.state.txt`, `foo.unknown` | refused; message names the path                                                                         |
| `docs/a.md`, `README.md`, root `LICENSE`, a non-ASCII `docs/café.md` pushed to `master`                                                                                            | allowed                                                                                                 |
| `docs/evil.md` and root `LICENSE` each starting `#!/usr/bin/env bash`, pushed to `master`                                                                                          | refused                                                                                                 |
| `tests/a.md`, `x/LICENSE`, `a.md.sh`, a path containing a newline, pushed to `master`                                                                                              | refused                                                                                                 |
| `foo/tests/a.md` pushed to `master`                                                                                                                                                | allowed (only the root `tests/` is test-owned)                                                          |
| `git mv x.sh x.md`, pushed to `master`                                                                                                                                             | refused, naming `x.sh`                                                                                  |
| A commit deleting a tracked `.sh`, pushed to `master`                                                                                                                              | refused                                                                                                 |
| A commit deleting a tracked `docs/old.md`, pushed to `master`                                                                                                                      | allowed                                                                                                 |
| Push to `master` whose `remote_sha` the fixture repo does not have                                                                                                                 | refused with the fetch-and-retry message, not the PR recipe                                             |
| Refused push with `local_ref` `refs/heads/master`, run while the current branch is `feat`                                                                                          | message contains `gh pr create --fill` and `reset --keep`, and does not tell the session to push `feat` |
| Refused push with `local_ref` `refs/heads/feat`                                                                                                                                    | message names `feat` in its push command and does not contain `reset --keep`                            |
| Refused push from a detached HEAD                                                                                                                                                  | message contains `git switch -c`                                                                        |
| Any refused push                                                                                                                                                                   | message contains `gh pr merge --admin` and does not contain `--no-verify`                               |
| A `.md` larger than the pipe buffer (300 KB) pushed to `master`                                                                                                                    | allowed                                                                                                 |
| A docs commit stacked on an unpushed code commit, pushed to `master`                                                                                                               | refused (range, not tip)                                                                                |
| `ci.yml` alone pushed to a branch                                                                                                                                                  | suite runs (was skipped)                                                                                |
| `docs/a.md` alone pushed to a branch                                                                                                                                               | suite skipped                                                                                           |
| A non-inert path pushed to a branch                                                                                                                                                | suite runs, push not refused                                                                            |
| `scripts/whats-new-anthropic.sh` reads and writes `.platform-state.md` (existing digest tests, updated)                                                                            | passes                                                                                                  |
| After the rename, `.platform-state.md` holds the content `.platform-state.txt` held                                                                                                | identical                                                                                               |
| Mutation: restore the old deny list in a scratch copy                                                                                                                              | the refusal rows go red                                                                                 |
| Mutation: drop the content check                                                                                                                                                   | the shebang row goes red                                                                                |
| Mutation: drop `--no-renames`                                                                                                                                                      | the rename row goes red                                                                                 |
| Mutation: drop the unresolvable-range refusal                                                                                                                                      | that row goes red                                                                                       |
| Mutation: call `_path_is_inert` bare, outside a conditional                                                                                                                        | a row goes red with the hook exiting before its message                                                 |
| `tests/scripts/docs_inert_premise.bats` on the real repo                                                                                                                           | passes                                                                                                  |
| Mutation: add `check-agent-guidance` to `test:` in a scratch copy                                                                                                                  | the prerequisite part goes red, naming it                                                               |
| Mutation: a fixture test reading `"${REPO_ROOT}/README.md"`                                                                                                                        | the reader part goes red, naming the file                                                               |
| `make test` on `claude`, and `test-macos` in CI                                                                                                                                    | green                                                                                                   |

Both directions of the predicate are covered: always-inert fails the refusal rows;
never-inert fails the allowed rows and the "suite skipped" row.

The existing tests "skips when only a .github/workflows file changed" and "skips a .github
workflow using the .yaml spelling" invert.

## Documentation

- `CLAUDE.md` Testing section: replace the pre-push bullets on the inert set and the guard
  with the single predicate, the `.md`-and-`LICENSE` rule, the recoveries, the emergency
  route, and the hook-defect recovery.
- New ADR: direct-to-master is default-deny over one shared inert predicate. It amends
  ADR-0017's inert set, supersedes the guard's deliberately narrow scope, and records the
  emergency route.
- `ai-config/docs/knowledge/dotfiles-testing-toolchain.md`: update the two pre-push sections.
- `docs/superpowers/README.md`: index row.

## Out of scope

- **Branch protection.** Adding `test-macos` and `bash-coverage` to required checks is a
  repository setting, given to the operator to run. It does not affect `gh pr merge --admin`.
- **`enforce_admins`.** Stays off: docs pushes and the emergency admin merge depend on it.
- **Aligning the global `git-workflow.md` and ai-config's `sdlc-branch-guard`** with this
  rule. ai-config backlog row.
- **Commits authored `Test <test@test.com>`.** Workstation's dotfiles checkout carries a
  repo-local `user.name = Test`; 264 of the non-PR commits since 2026-06-01 carry it. P1
  backlog row in this repo.

## Multi-Lens Review

### Round 1

Reviewed at commit: `f9196251`. Every reference in this subsection is to the spec as it stood
at that commit; the body above was revised in response.

#### Goal-Fit

Finding: Worth building; default-deny is no larger than widening the deny list and removes
the drift. Real flaw: the guard fails open when the range cannot be resolved, and the spec
carried that over. Missing rows: unresolvable range, a pure code deletion, a nested
`*/tests/*.md`.
Assumption: The hook is live in every checkout that pushes `master`, and no commit reaches
`master` another way. Checked after the review: the hook resolves to `scripts/pre-push` on
`claude`, Studio and workstation; no non-PR commit since 2026-06-01 has a `GitHub` committer.
CI-authored commits (`github-actions[bot]`, 12) reach `master` without any local hook.
Disposition: Addressed — guard refuses an unresolvable range; rows added for it, a code deletion and a nested tests/*.md. Operator, 2026-10-02.

#### Ergonomics

Finding: The cost premise was measured on a shallow clone; the real cost is not zero. The
weekly digest scripts push non-`.md` state files to `master` and would break every week. The
two guards disagree and the spec gave no recovery recipe; the refusal message says
"executable files". Verification lacks negative anchoring cases and a message check.
Assumption: The scripted weekly digest push should keep going direct. Settled by the operator.
Disposition: Addressed — cost re-measured on a deep clone; the digest state file renamed; recovery recipes added. Operator, 2026-10-02.

#### Risk

Finding: Guard fails open on an unresolvable range (reproduced). A defective hook blocks
every push including branch pushes, because the hook is a shared symlink; a bare predicate
call under `set -e` dies silently. The design closes the `rollback-cycle --reason ci-red`
route for a `ci.yml` revert. Non-ASCII paths are quoted. Deletion-only pushes unmentioned.
Assumption: Every route that legitimately writes `master` is an interactive human docs push.
Refuted by measurement: two scheduled scripts write `master` weekly.
Disposition: Addressed — unresolvable range refused, emergency route stated, non-ASCII paths handled, deletion-only pushes stated. Operator, 2026-10-02.

#### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2

Reviewed at commit: `b4be2dd5`. References are to the spec as it stood at that commit; the
body above was revised in response. All three lenses re-ran, because round 1 changed the
design's substance.

#### Goal-Fit

Finding: Rule 3 (non-shell files under `docs/` inert) served one file,
`.platform-state.txt`; renaming it gives the same 28 refusals with less mechanism. The
shebang reasoning was applied to rule 3 only, though `make lint` selects by content
everywhere. Cost table re-derived on the deep clone: 28 refused, the 10 newly refused match.
Assumption: No test or lint target reads tracked `.md` content; one `test:` prerequisite
change would break it. Checked: no such reader today; nothing enforces it.
Disposition: Addressed — the docs/ rule dropped and the state file renamed; the content check applies to every path. Operator, 2026-10-02.

#### Ergonomics

Finding: The recovery recipe failed in two of three cases (`reset --keep` refuses when the
dirty file is in the refused commit; `git switch master` fails in a worktree) and
`gh pr create` needs `--fill` non-interactively. The global standard and ai-config's guard
tell sessions some non-`.md` files may go direct, so the refusal is the first they hear.
`hotfix-cycle` and `rollback-cycle` authorize direct pushes and forbid `--no-verify`, with no
stated route here. Admin merge past red required checks verified to work.
Assumption: No workflow that authorizes a direct push runs in dotfiles without reading this
repo's rule. Addressed by putting the emergency route in the refusal message itself.
Disposition: Addressed — recovery recipes per case, emergency route in the refusal message; aligning the global standard and ai-config's guard is an ai-config backlog row. Operator, 2026-10-02.

#### Risk

Finding: Design: rules 1 and 2 lacked the content check (measured: shebang `.md` and
`LICENSE` join `SHELL_FILES`); rule 3's extension list missed `.zsh-theme`; the
unresolvable-range refusal fires on an ordinary stale push with the wrong recovery, and a
single push of a branch plus a refused `master` now refuses the branch too. Apparatus:
newline paths arrive C-quoted, not split; a failed blob read looked like "no shebang".
Assumption: The digest scripts push from an up-to-date `master`. If not, they hit the
fetch-and-retry message weekly; a fetch clears it.
Disposition: Addressed — content check on every path, no extension list, a separate fetch-and-retry message. Operator, 2026-10-02.

### Round 3 (scoped: Risk, Design and Verification only)

Reviewed at commit: `98d89ef8`. Round 2's rewrite removed mechanism, so one scoped lens
re-read only the rewritten sections.

Finding: Design: reading the first bytes through a pipe returns 141 under `pipefail` for a
blob larger than the pipe buffer, which would refuse `CLAUDE.md` and the plan index; the
recovery was keyed on the current branch rather than `local_ref`, and failed for a detached
HEAD; the rename must carry the state file's content. Apparatus: no large-`.md` row; the
recovery rows could pass with a message printing every recipe; no row for the emergency text.
Harmless: refusing any `#!` is stricter than `make lint`; no tracked `.md` starts with one.
Assumption: No `make test` prerequisite reads a tracked `.md`. True today
(`test: lint check-lock check-requirements-ci test-python`; `check-agent-guidance` reads
`CLAUDE.md` and is not a prerequisite); nothing enforces it.
Disposition: Addressed — blob read without a pipe, recovery keyed on local_ref, rename with git mv; the open assumption is now pinned by tests/scripts/docs_inert_premise.bats. Operator, 2026-10-02.

Review stops here. Round 3's findings are about how the hook reads a blob and what the
message prints, which the first red tests in Phase 2 exercise directly, and the design got
smaller in round 2 and did not grow in round 3.
