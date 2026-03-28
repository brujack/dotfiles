# Makefile Lint Target Design

**Date:** 2026-03-28
**Status:** Approved

## Goal

Add bash/zsh syntax checking for all `.sh` files in the repo, runnable as both `make lint` (standalone) and automatically as part of `make test`.

## Scope

- **In scope:** `Makefile` only — no changes to any `.sh` files or test files
- **Out of scope:** shellcheck or any external linting tool; reformatting; fixing existing syntax errors (separate concern)

## Design

### New `lint` target

A `lint` target iterates over all `.sh` files found by `find . -name "*.sh" -not -path "*/node_modules/*"` and runs `bash -n` and `zsh -n` on each. Results are printed per file/interpreter. If any check fails, `lint` exits non-zero.

```makefile
lint:
	@failed=0; \
	for f in $(shell find . -name "*.sh" -not -path "*/node_modules/*"); do \
	  bash -n "$$f" && printf "bash  OK  %s\n" "$$f" || { printf "bash FAIL %s\n" "$$f"; failed=1; }; \
	  zsh  -n "$$f" && printf "zsh   OK  %s\n" "$$f" || { printf "zsh  FAIL %s\n" "$$f"; failed=1; }; \
	done; \
	exit $$failed
```

### `test` depends on `lint`

```makefile
test: lint
```

This means `make test` runs lint first. A syntax error in any `.sh` file blocks the BATS test run.

### `.PHONY` and `help` updates

- Add `lint` to `.PHONY`
- Add `make lint  Check bash/zsh syntax of all .sh files` to the `help` target output

## Behavior

| Command | What happens |
|---|---|
| `make lint` | Checks all `.sh` files with `bash -n` and `zsh -n`; exits 0 only if all pass |
| `make test` | Runs lint first, then BATS; syntax error in any `.sh` blocks test run |
| `make test-unit` | Not changed — does not depend on lint |

## Testing

Verify manually:
1. `make lint` passes on the current repo
2. Introduce a deliberate syntax error in a `.sh` file; confirm `make lint` exits non-zero and names the failing file
3. `make test` fails when `make lint` fails (before BATS runs)
4. Revert the syntax error; confirm `make test` passes
