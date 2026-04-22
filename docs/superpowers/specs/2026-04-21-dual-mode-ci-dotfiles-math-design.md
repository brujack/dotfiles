# Dual-Mode CI: Pre-push Local Gate + GitHub Actions Final Gate

**Date:** 2026-04-21
**Repos:** dotfiles, math
**Status:** Approved

## Context

The ansible repo established a dual-mode CI strategy: a permanent pre-push hook runs tests locally before every push, and GitHub Actions is the final merge gate on PRs only. This design applies that same strategy to the dotfiles and math repos, and codifies it as the standard for all personal repos in `~/.claude/CLAUDE.md`.

Currently:

- **dotfiles:** has a pre-commit hook (lint + ggshield), no pre-push hook. CI runs on bare `push:` (every branch) + PRs.
- **math:** has a pre-commit hook (lint per staged sub-project + ggshield), no pre-push hook. CI runs on `branches-ignore: [master]` (every non-master branch push) + PRs.

Both consume GitHub Actions minutes on every branch push even though CI failing at that point provides no gate — branches can be pushed without review.

## Decision

**Two-layer CI for every personal repo:**

1. **Pre-push hook (local, permanent):** runs the test suite before the push reaches GitHub. Catches failures fast without consuming GitHub Actions minutes. Installed via `make install-hooks` alongside the pre-commit hook. Never removed.

2. **GitHub Actions (PR-only, final gate):** removes branch-push triggers. CI runs only on PRs, where it is the authoritative merge gate with auto-merge on pass.

## Dotfiles Changes

### `scripts/pre-push` (new)

Runs `make test` (lint + bats) on every push. Skips branch deletions.

```bash
#!/usr/bin/env bash
# Pre-push hook: runs full test suite locally before push reaches GitHub.
# Permanent: provides fast local feedback and conserves GitHub Actions minutes.
# GitHub Actions is the final merge gate on PRs.
set -e

while read -r local_ref local_sha remote_ref remote_sha; do
    [ "${local_sha}" = "0000000000000000000000000000000000000000" ] && exit 0
done

printf "Running tests locally (pre-push)...\n"
make -C "$(git rev-parse --show-toplevel)" test
```

### `Makefile` — `install-hooks` target

Update to install both hooks:

```makefile
install-hooks:
	ln -sf "$(shell pwd)/scripts/pre-commit-hook.sh" .git/hooks/pre-commit
	ln -sf "$(shell pwd)/scripts/pre-push" .git/hooks/pre-push
	@printf "Pre-commit and pre-push hooks installed\n"
```

### `.github/workflows/ci.yml` — remove push trigger

Remove the bare `push:` trigger. Keep only `pull_request: branches: [master]`.

```yaml
on:
  pull_request:
    branches:
      - master
```

## Math Changes

### `scripts/pre-push` (new)

Detects which sub-projects have commits in the current push range and runs `make test` for each. Skips branch deletions. For new branches (no remote SHA), falls back to comparing against the merge-base with `origin/master`.

Sub-projects checked: `pi`, `pi/pi-rs`, `prime/prime-rs`, `fib`, `fib/fib-rs`, `sq`, `sq/sq-rs`, `twin-primes/twin-primes-rs`

```bash
#!/usr/bin/env bash
# Pre-push hook: runs tests for changed sub-projects before push reaches GitHub.
# Permanent: provides fast local feedback and conserves GitHub Actions minutes.
# GitHub Actions is the final merge gate on PRs.
set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
DIRS_TO_TEST=()

while read -r local_ref local_sha remote_ref remote_sha; do
    [ "${local_sha}" = "0000000000000000000000000000000000000000" ] && continue

    if [ "${remote_sha}" = "0000000000000000000000000000000000000000" ]; then
        base="$(git merge-base "${local_sha}" origin/master 2>/dev/null \
            || git rev-list --max-parents=0 "${local_sha}")"
        range="${base}..${local_sha}"
    else
        range="${remote_sha}..${local_sha}"
    fi

    for dir in pi pi/pi-rs prime/prime-rs fib fib/fib-rs sq sq/sq-rs twin-primes/twin-primes-rs; do
        if git diff --name-only "${range}" | grep -q "^${dir}/"; then
            DIRS_TO_TEST+=("${dir}")
        fi
    done
done

for dir in $(printf '%s\n' "${DIRS_TO_TEST[@]+"${DIRS_TO_TEST[@]}"}" | sort -u); do
    printf "test: %s\n" "${dir}"
    make -C "${REPO_ROOT}/${dir}" test
done
```

### Root `Makefile` — `install-hooks` target

Update to install both hooks:

```makefile
install-hooks:
	ln -sf "$(shell pwd)/scripts/pre-commit" "$$(git rev-parse --git-path hooks)/pre-commit"
	ln -sf "$(shell pwd)/scripts/pre-push" "$$(git rev-parse --git-path hooks)/pre-push"
	@printf "Pre-commit and pre-push hooks installed\n"
```

### GitHub Actions workflows — remove push triggers

All per-sub-project workflows (`fib-rs.yml`, `pi-rs.yml`, `prime-rs.yml`, `sq-rs.yml`, `twin-primes-rs.yml`, `pi-py.yml`, `fib-py.yml`, `sq-py.yml`) currently have:

```yaml
on:
  push:
    branches-ignore:
      - master
  pull_request:
    branches:
      - master
```

Change all to:

```yaml
on:
  pull_request:
    branches:
      - master
```

## Global `~/.claude/CLAUDE.md` Changes

Add two new bullets to the existing "Personal Repos" subsection (after the pre-commit hook bullet):

> - **Pre-push hook (permanent):** every personal repo must have a `scripts/pre-push` that runs the test suite locally before the push reaches GitHub. This is permanent — not a temporary workaround. `make install-hooks` must install it alongside the pre-commit hook. For multi-project repos, run only sub-projects with changed commits in the push range.
> - **GitHub Actions CI triggers:** workflows must trigger on `pull_request` only — never on bare `push:` or `branches-ignore:` push triggers. The pre-push hook is the branch-push gate; GitHub Actions is the PR merge gate.

## What Does Not Change

- Pre-commit hooks in both repos — no changes
- Test suite content in both repos — no changes
- `auto-merge.yml` in math — no changes
- `secret-scan` and `snyk-scan` in math auto-merge — no changes
- dotfiles `lint-macos` and `secret-scan` jobs — no changes (these stay in ci.yml, just remove the push trigger)
