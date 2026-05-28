# Coverage: setup_env.sh Preamble Branches

> **Status: DONE** — implemented in PR #100 (2026-05-28)

## Context

`setup_env.sh` has 14 uncovered lines (75% coverage vs 90% floor). All gaps are in
the preamble block (lines 4–40) that runs only when the script is executed directly.
The block contains two early-exit checks — bash version and Homebrew presence — each
with a macOS and a Linux hint path that are never exercised by existing tests.

Current tests only verify the _bypass_ conditions (doctor/check-versions/--brew-install
skip the brew check); they do not invoke the error paths themselves.

## Uncovered Lines

| Lines | Code                                                 | Reason untested                                                    |
| ----- | ---------------------------------------------------- | ------------------------------------------------------------------ |
| 21–27 | bash version `< 5` error + OS-specific hint + exit 1 | `BASH_VERSINFO[0]` is read-only; can't lower it from outside       |
| 31–37 | Homebrew not found error + OS-specific hint + exit 1 | Bypass tests skip this block entirely; error paths never triggered |
| 55    | `[[ $# -eq 0 ]] && usage`                            | All current tests pass at least one argument                       |

## Design

### Test seam for bash version

`BASH_VERSINFO` is a read-only bash built-in — tests cannot override it. Add a
one-character test seam to the preamble:

```bash
# Before (setup_env.sh line 6):
_BASH_MAJOR="${BASH_VERSINFO[0]:-0}"

# After:
_BASH_MAJOR="${_OVERRIDE_BASH_MAJOR:-${BASH_VERSINFO[0]:-0}}"
```

This allows tests to inject a low version number without changing production
behaviour (env var is unset in production; bash 5+ always wins the real path).

Document `_OVERRIDE_BASH_MAJOR` in the Test Seams table in CLAUDE.md.

### Brew prereq error paths

Already testable via:

- `MOCK_WHICH_MISSING=brew` — makes `env which brew` fail
- `MOCK_UNAME_S=Darwin|Linux` — controls the OS-hint branch

Pass a non-bypass argument (e.g. `--update`) so `_REQUIRES_BREW_PREREQ` stays 1.

### No-args path

`bash setup_env.sh` with zero arguments hits line 55 (`usage`) before any flag
processing. On the test machine brew is installed, so the preamble passes cleanly.
No mocks required; just assert status 0 and output contains "Usage:".

## Tests to Write

All tests go in `tests/setup_env/unit.bats` near the existing preamble tests
(around line 192).

### Bash version error — macOS

```
@test "setup_env.sh exits 1 with bash version error on macOS" {
  load_mocks
  export _OVERRIDE_BASH_MAJOR=4
  export MOCK_UNAME_S=Darwin
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh" --update
  [ "$status" -eq 1 ]
  [[ "$output" == *"bash 5+ required"* ]]
  [[ "$output" == *"bootstrap_mac.sh"* ]]
}
```

### Bash version error — Linux

```
@test "setup_env.sh exits 1 with bash version error on Linux" {
  load_mocks
  export _OVERRIDE_BASH_MAJOR=4
  export MOCK_UNAME_S=Linux
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh" --update
  [ "$status" -eq 1 ]
  [[ "$output" == *"bash 5+ required"* ]]
  [[ "$output" == *"bootstrap_linux.sh"* ]]
}
```

### Homebrew error — macOS

```
@test "setup_env.sh exits 1 with Homebrew error on macOS" {
  load_mocks
  export MOCK_WHICH_MISSING=brew
  export MOCK_UNAME_S=Darwin
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh" --update
  [ "$status" -eq 1 ]
  [[ "$output" == *"Homebrew not found"* ]]
  [[ "$output" == *"bootstrap_mac.sh"* ]]
}
```

### Homebrew error — Linux

```
@test "setup_env.sh exits 1 with Homebrew error on Linux" {
  load_mocks
  export MOCK_WHICH_MISSING=brew
  export MOCK_UNAME_S=Linux
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh" --update
  [ "$status" -eq 1 ]
  [[ "$output" == *"Homebrew not found"* ]]
  [[ "$output" == *"bootstrap_linux.sh"* ]]
}
```

### No-args → usage

```
@test "setup_env.sh calls usage when invoked with no arguments" {
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}
```

## Files Changed

| File                        | Change                                         |
| --------------------------- | ---------------------------------------------- |
| `setup_env.sh`              | Add `_OVERRIDE_BASH_MAJOR` seam (1 line)       |
| `tests/setup_env/unit.bats` | 5 new tests                                    |
| `CLAUDE.md`                 | Add `_OVERRIDE_BASH_MAJOR` to Test Seams table |

## Expected Outcome

setup_env.sh coverage: 75% → ~96% (covers 12 of 14 uncovered lines).
The remaining 2 may be unreachable structural lines (elif/fi keywords) excluded
by the tracer — acceptable.
