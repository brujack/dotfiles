# Design: CI Safety and Clarity Pass

**Date:** 2026-04-08
**Status:** Approved

## Summary

Fix the ambiguous `auto-merge` job condition in `.github/workflows/ci.yml` and add a macOS syntax-check job to catch platform-specific shell drift.

## Motivation

### Auto-merge condition

The current `auto-merge` condition:

```yaml
if: github.event_name == 'pull_request' && github.actor == 'dependabot[bot]' || github.event_name == 'push'
```

Due to operator precedence, this evaluates as:

```
(pull_request AND dependabot) OR push
```

It fires on **every push** to any non-master branch, not only when a PR exists. The `gh pr list` check inside the step means it only merges when a PR is found — so there's no functional harm. But the condition is misleading and makes intent unclear. The correct expression for "run auto-merge when tests pass, on any push or PR event" is:

```yaml
if: github.event_name == 'pull_request' || github.event_name == 'push'
```

### macOS syntax check

The CI `test` job runs on `ubuntu-latest` only. Shell scripts that use macOS-specific syntax (`/bin/bash` quirks, BSD vs GNU flag differences in brace expansion, etc.) won't be caught until someone runs on a Mac. A lightweight macOS lint job that runs `bash -n` and `zsh -n` on all `.sh` files catches these early.

## Changes

### Modified: `.github/workflows/ci.yml`

**1. Fix auto-merge condition:**

```yaml
auto-merge:
  needs: [test]
  if: github.event_name == 'pull_request' || github.event_name == 'push'
```

**2. Add `lint-macos` job:**

```yaml
lint-macos:
  runs-on: macos-latest
  steps:
    - uses: actions/checkout@v5

    - name: Syntax check all shell scripts (bash)
      run: |
        find . -name '*.sh' -not -path './.worktrees/*' -not -path './tests/mocks/*' \
          | xargs -I{} bash -n {}

    - name: Syntax check all shell scripts (zsh)
      run: |
        find . -name '*.sh' -not -path './.worktrees/*' -not -path './tests/mocks/*' \
          | xargs -I{} zsh -n {}
```

The `lint-macos` job runs in parallel with the existing `test` job. It does not depend on `test`, so it does not block auto-merge if it fails (macOS lint is advisory). If future sessions decide to enforce it, add it to `needs: [test, lint-macos]` in the `auto-merge` job.

## Constraints

- No behavior change to when CI runs (triggers remain the same).
- The macOS lint job must not require any additional tool installs (only `bash` and `zsh` which ship with macOS).
- Auto-merge logic inside the step (`gh pr list`) is unchanged.
