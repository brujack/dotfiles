# Direct-to-master guard: default-deny

**Date:** 2026-10-02
**Status:** Draft, awaiting operator review

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

Measured 2026-10-02 on `master` at `b0e4def1`, tracked code and config files this list lets
through:

| class                                             | tracked files |
| ------------------------------------------------- | ------------- |
| `tests/mocks/*` (extensionless shell)             | 68            |
| `scripts/*.py`, `tests/*.py`                      | 5             |
| `.zshrc`, `.zprofile`                             | 2             |
| `pyproject.toml`, `uv.lock`, `requirements-*.txt` | 7             |
| `.github/workflows/*.yml`                         | 2             |

The guard's own comment records that the narrow scope was chosen deliberately, and that
`tests/mocks/*` was a known gap. The operator reversed that on 2026-10-02: no code reaches
`master` except through a PR. Docs may still go direct, untested.

**The hazard has no observed instance.** Since 2026-06-01, 11 first-parent commits on
`master` have a subject without a `(#NNN)` PR suffix, and every one touched only `.md`
files. This change protects against a route
nobody has used, so it must cost nothing on the route people do use.

### Two further defects in the same hook

1. **Two lists for one question.** The hook decides "does this push need the suite?" with an
   inert set (`\.md$|^\.github/.*\.ya?ml$|^LICENSE$`, with anything under `tests/` always
   triggering) and "may this go direct to master?" with the deny list above. They already
   disagree, and nothing keeps them in step.
2. **The inert set calls workflow files inert, and they are not.** Six test files read
   `ci.yml`: `tests/setup_env/requirements_ci.bats`, `tests/setup_env/shellcheck_pin.bats`,
   `tests/scripts/pre_push.bats`, `tests/scripts/auto_merge_gate.bats`,
   `tests/scripts/makefile_lint_scope.bats` and `tests/test_phrase_check.py`. So a push that
   changes only `ci.yml` skips the local tests that read it.

No test reads the repository's real `CLAUDE.md`, `README.md` or `docs/`: a grep for those
paths under `tests/` finds only fixtures that create their own files with those names. So
`.md` files outside `tests/` are genuinely inert.

### A third defect: renames hide the old path

`git diff --name-only` detects renames and reports only the new path. Measured in a scratch
repo: after `git mv x.sh x.md`, the default form prints `x.md`; `--no-renames` prints
`x.md` and `x.sh`. So today a commit that renames a shell file to `.md` is seen as a docs
change by both the trigger and the guard, and deletes code from `master` untested.

## Design

### One predicate

`scripts/pre-push` gets one function, `_path_is_inert <path>`, returning 0 when the path
cannot change the suite's result:

- a `.md` file that is not under `tests/`
- `LICENSE` at the repository root

Everything else is not inert. Unknown file types are not inert, so a file type added in
future is covered without anyone editing the hook.

Both decisions use it:

- **Suite trigger:** run `make test` unless every changed path is inert. Unchanged in shape
  (ADR-0017); the only behavioural change is that `.github/*.yml` now triggers.
- **Direct-to-master guard:** refuse a push to `refs/heads/master` if any path in the range
  is not inert, listing the offending paths.

### Changed paths

Both decisions read `git diff --no-renames --name-only "${range}"`, so a rename reports the
old and the new path. The existing fail-closed handling of an unresolvable range stays.

### Unchanged behaviour

- The guard evaluates the whole push range, not the tip commit.
- The refusal is accumulated inside the stdin loop and read after it, before the
  `needs_test` early exit.
- The refusal message names each path and says what to do: push a branch and open a PR.
- Branch pushes are never refused; they only decide whether the suite runs.
- `--no-verify` still bypasses the hook. That is accepted, as it is today.

### What newly needs a PR

Every non-`.md` file, including `ci.yml`, `pr-title-lint.yml`, `.claude/settings.json`,
`renovate.json`, `.gitleaks.toml`, `.shellcheckrc`, `starship.toml` and `.warp/*`. None of
these has been pushed direct since 2026-06-01, so the measured cost is zero refusals out of
11 direct pushes. The ai-config `sdlc-branch-guard` hook still permits some of these direct;
the pre-push hook is now stricter, which is the safe direction.

## Verification

| check                                                                                                                | expected                     |
| -------------------------------------------------------------------------------------------------------------------- | ---------------------------- |
| Each class in the Problem table pushed to `master` in a fixture repo: a mock, a `.py`, `.zshrc`, `uv.lock`, `ci.yml` | refused, path named          |
| A file type that does not exist in the repo, e.g. `foo.unknown`, pushed to `master`                                  | refused                      |
| `git mv x.sh x.md` pushed to `master`                                                                                | refused, naming `x.sh`       |
| A `.md` under `docs/` and `LICENSE` pushed to `master`                                                               | allowed                      |
| A `.md` under `tests/` pushed to `master`                                                                            | refused                      |
| A docs commit stacked on an unpushed code commit, pushed to `master`                                                 | refused (range, not tip)     |
| `ci.yml` alone pushed to a branch                                                                                    | suite runs (was skipped)     |
| A `.md` alone pushed to a branch                                                                                     | suite skipped                |
| Mutation: restore the old deny list in a scratch copy                                                                | the new refusal tests go red |
| Mutation: drop `--no-renames` in a scratch copy                                                                      | the rename test goes red     |
| `make test` on `claude` and `test-macos` in CI                                                                       | green                        |

The existing tests "skips when only a .github/workflows file changed" and "skips a .github
workflow using the .yaml spelling" invert: they assert the old, wrong behaviour.

## Documentation

- `CLAUDE.md` Testing section: the pre-push bullets describe the inert set, the guard's
  deny list and its exemptions. Replace with the single predicate and the docs-only rule.
- New ADR: direct-to-master is default-deny over one shared inert predicate. It amends
  ADR-0017's inert set and supersedes the guard's deliberate narrow scope.
- `ai-config/docs/knowledge/dotfiles-testing-toolchain.md`, sections "Pre-push hook:
  fail-closed inert-path set" and "Pre-push hook: direct-to-master guard": update to match.
- `docs/superpowers/README.md`: index row.

## Out of scope

- **Branch protection.** Adding `test-macos` and `bash-coverage` to required checks is a
  repository setting, given to the operator to run.
- **`enforce_admins`.** Stays off: docs pushes to `master` depend on the admin bypass of
  required checks.
- **`--no-verify`.** Bypasses every hook; unchanged.
