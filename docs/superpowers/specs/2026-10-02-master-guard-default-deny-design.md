# Direct-to-master guard: default-deny

**Date:** 2026-10-02
**Status:** Draft, revised after round 1, awaiting operator review

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

**Two scripts push to `master` every week**, and an `.md`-only rule would break both.
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
the path cannot change the suite's result. A path is inert when it is one of:

1. a `.md` file, anywhere except under the repository-root `tests/` directory
2. `LICENSE` at the repository root
3. a file under `docs/` whose blob at `<local_sha>` does not start with `#!`, and whose name
   does not end in `.sh`, `.bash`, `.bats`, `.zsh` or `.py`

Everything else is not inert, including any file type added in future. Rule 3 exists for the
weekly digest state files. The shebang check is there because `make lint` walks every tracked
file and lints any that starts with a bash or sh shebang, wherever it lives. A path whose
blob is absent at `<local_sha>` (a deletion) is judged by rules 1 to 3 on its name alone,
with rule 3's shebang test skipped.

The function is only ever called in a conditional context (`if`, `&&`, `||`), because the
hook runs under `set -e` and a bare call returning 1 would kill the hook with no message.

Both decisions use it:

- **Suite trigger:** run `make test` unless every changed path is inert (ADR-0017's shape).
  Behavioural change: `.github/*.yml` now triggers; non-shell files under `docs/` no longer do.
- **Direct-to-master guard:** refuse a push to `refs/heads/master` when any path in the range
  is not inert, **or when the range cannot be resolved**.

### Changed paths

Both decisions read `git -c core.quotePath=false diff --no-renames --name-only "${range}"`,
one path per line, so a rename reports both paths and a non-ASCII name arrives as written. A
path containing a newline splits into pieces that match nothing, so it is refused; that is
the safe direction and is accepted.

### The refusal message

It names every refused path, says that only docs may go direct, and gives the recovery for
a commit that is already on local `master`:

```
git switch -c <name>             # the commits come with you
git push -u origin <name> && gh pr create
git switch master && git reset --keep origin/master
```

`--keep` rather than `--hard`, so uncommitted work in the tree is refused rather than lost.
It no longer says "executable files", which is false for a `.toml` or `.txt`.

### Unchanged behaviour

- The guard evaluates the whole push range, not the tip commit.
- The refusal is accumulated inside the stdin loop and read after it, before the
  `needs_test` early exit.
- Branch pushes are never refused; they only decide whether the suite runs.
- A deletion-only ref line (`local_sha` all zeros) is skipped, as today.
- `--no-verify` still bypasses the hook. Accepted, as today.

### What newly needs a PR, and what that costs

`.warp/settings.toml`, `renovate.json`, `.gitleaks.toml`, `.gitignore`, `starship.toml`,
`ubuntu_*_packages.txt`, `.claude/settings.json`, workflow files, and every code file. The
measured cost is the 10 commits listed above over four months.

Two consequences to know in advance:

- **ai-config's `sdlc-branch-guard` hook permits some of these direct to master** (`*.txt`, `renovate.json`, `.gitleaks.toml`, `.gitignore`, some `settings.json`
  keys). A session can commit one to `master` with that hook's blessing and then be refused
  at push. The refusal message's recovery covers it. Aligning the two is out of scope.
- **The emergency route changes.** `rollback-cycle --reason ci-red` delivers a revert direct
  to `master`, and the likeliest reason every PR goes red is a `ci.yml` defect. A `ci.yml`
  revert can no longer go direct. It goes through a PR merged by an admin past failing
  checks (`gh pr merge --admin`; `enforce_admins` is off). The ADR states this.

### The hook can block every push, including its own fix

`.git/hooks/pre-push` is a symlink to the main checkout's `scripts/pre-push`, on every
development machine (measured on `claude`, Studio and workstation). The hook that judges a
push is the main checkout's copy, not the branch being pushed. So:

- While this change is developed, the old hook judges its pushes; the new logic is exercised
  only by bats.
- Once merged, a defect that makes the hook exit non-zero blocks branch pushes too, so the
  "branch + PR" remedy is unavailable. The recovery is a fix branch pushed with
  `--no-verify`, which then goes through PR and CI. `CLAUDE.md` states this.
- The tests below run the real hook end to end under `set -e`, so a silent death fails a
  test rather than every push.

## Verification

All rows run the real hook against fixture repositories in `tests/scripts/pre_push.bats`.

| check                                                                                                                                                         | expected                                                           |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| Push to `master` carrying, one per case: a `tests/mocks/` file, a `.py`, `.zshrc`, `uv.lock`, `ci.yml`, `.warp/settings.toml`, `renovate.json`, `foo.unknown` | refused; message names the path and contains the recovery commands |
| `git mv x.sh x.md`, pushed to `master`                                                                                                                        | refused, naming `x.sh`                                             |
| A commit deleting a tracked `.sh`, pushed to `master`                                                                                                         | refused                                                            |
| Push to `master` whose `remote_sha` the fixture repo does not have                                                                                            | refused                                                            |
| `docs/a.md`, `README.md`, root `LICENSE`, a non-ASCII `docs/café.md`, `docs/x/.state.txt` pushed to `master`                                                  | allowed                                                            |
| `tests/a.md`, `x/LICENSE`, `a.md.sh`, `docs/run.sh`, an extensionless `docs/tool` starting with `#!/usr/bin/env bash` pushed to `master`                      | refused                                                            |
| `foo/tests/a.md` pushed to `master`                                                                                                                           | allowed (only the root `tests/` is test-owned)                     |
| A docs commit stacked on an unpushed code commit, pushed to `master`                                                                                          | refused (range, not tip)                                           |
| `ci.yml` alone pushed to a branch                                                                                                                             | suite runs (was skipped)                                           |
| `docs/x/.state.txt` alone pushed to a branch                                                                                                                  | suite skipped (was run)                                            |
| A non-inert path pushed to a branch                                                                                                                           | suite runs, push not refused                                       |
| Mutation: restore the old deny list in a scratch copy                                                                                                         | the new refusal rows go red                                        |
| Mutation: drop `--no-renames`                                                                                                                                 | the rename row goes red                                            |
| Mutation: drop the unresolvable-range refusal                                                                                                                 | that row goes red                                                  |
| Mutation: call `_path_is_inert` bare, outside a conditional                                                                                                   | a row goes red with the hook exiting before its message            |
| `make test` on `claude`, and `test-macos` in CI                                                                                                               | green                                                              |

The existing tests "skips when only a .github/workflows file changed" and "skips a .github
workflow using the .yaml spelling" invert.

## Documentation

- `CLAUDE.md` Testing section: replace the pre-push bullets on the inert set and the guard
  with the single predicate, the docs-only rule, the refusal recovery and the hook-defect
  recovery.
- New ADR: direct-to-master is default-deny over one shared inert predicate. It amends
  ADR-0017's inert set, supersedes the guard's deliberately narrow scope, and records the
  emergency route.
- `ai-config/docs/knowledge/dotfiles-testing-toolchain.md`: update the two pre-push sections.
- `docs/superpowers/README.md`: index row.

## Out of scope

- **Branch protection.** Adding `test-macos` and `bash-coverage` to required checks is a
  repository setting, given to the operator to run.
- **`enforce_admins`.** Stays off: docs pushes and the emergency admin merge depend on it.
- **Aligning ai-config's `sdlc-branch-guard`** with this predicate. Backlog row in ai-config.
- **264 of the 561 non-PR commits since 2026-06-01 are authored `Test <test@test.com>`**,
  including two today. Cause found: workstation's dotfiles checkout carries a repo-local
  `user.name = Test` in `.git/config`, overriding the global identity. The operator unsets it;
  which test wrote it is a backlog row.

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
Disposition:

#### Ergonomics

Finding: The cost premise was measured on a shallow clone; the real cost is not zero. The
weekly digest scripts push non-`.md` state files to `master` and would break every week. The
two guards disagree and the spec gave no recovery recipe; the refusal message says
"executable files". Verification lacks negative anchoring cases and a message check.
Assumption: The scripted weekly digest push should keep going direct. Settled by the operator.
Disposition:

#### Risk

Finding: Guard fails open on an unresolvable range (reproduced). A defective hook blocks
every push including branch pushes, because the hook is a shared symlink; a bare predicate
call under `set -e` dies silently. The design closes the `rollback-cycle --reason ci-red`
route for a `ci.yml` revert. Non-ASCII paths are quoted. Deletion-only pushes unmentioned.
Assumption: Every route that legitimately writes `master` is an interactive human docs push.
Refuted by measurement: two scheduled scripts write `master` weekly.
Disposition:

#### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
