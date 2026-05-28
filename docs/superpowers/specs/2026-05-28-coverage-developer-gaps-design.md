> **Status: DONE**

# Coverage: developer.sh Gaps

## Context

`developer.sh` has 21 uncovered lines. The 3 existing tests in `developer.bats` cover
only `setup_vim_plugins`. `update_rust` and `clone_personal_repos` have zero test
coverage.

## Uncovered Lines

| Lines   | Function               | Code                                               | Reason untested                  |
| ------- | ---------------------- | -------------------------------------------------- | -------------------------------- |
| 38–57   | `update_rust`          | Entire function body (3 rustup branches + nextest) | No tests exist for this function |
| 236–262 | `clone_personal_repos` | git clone calls (dirs-missing path)                | No tests exist for this function |

## Design

### `update_rust` — four branches

The function has three rustup-detection branches and a nextest-update gate:

```
if [[ -n UBUNTU ]] && [[ -n HAS_RUST ]]:
  if [[ -x ~/.cargo/bin/rustup ]]     → Branch A: cargo-home rustup
  elif command -v rustup               → Branch B: PATH rustup
  else                                 → Branch C: warn, skip
  if _rustup_found==1 && command -v cargo-nextest → Branch D: nextest update
```

**Branch A** — controllable: fake `HOME` is `BATS_TEST_TMPDIR`, so creating
`${HOME}/.cargo/bin/rustup` as an executable file puts it where the guard checks.

**Branch B** — controllable: `load_mocks` prepends `tests/mocks/` to PATH;
`tests/mocks/rustup` already exists. Since `HOME` is fake, `~/.cargo/bin/rustup` does
not exist → first check fails → `elif command -v rustup` finds the mock.

**Branch C** — requires rustup absent from PATH entirely. Do not call `load_mocks`;
set PATH to `/usr/bin:/bin:/usr/sbin:/sbin`. Fake HOME already lacks
`~/.cargo/bin/rustup`. `log_warn` is a sourced function — no mock needed.

**Branch D (nextest update)** — requires `_rustup_found=1` AND `command -v cargo-nextest`.
Add a new `tests/mocks/cargo-nextest` mock script (identical pattern to other mocks).
Test: Branch A setup + cargo-nextest mock in PATH → assert `curl get.nexte.st` call.
Negative test: Branch C setup (no rustup) → assert curl NOT called.

### `clone_personal_repos` — two paths

**Skip path** — create `${BATS_TEST_TMPDIR}/home/git-repos/personal/dotfiles` before
calling the function; assert `git clone` NOT called.

**Clone path** — don't create the dir; assert `git clone` called with the dotfiles
repo URL.

Covering dotfiles (the first repo) is sufficient — remaining 7 repos follow identical
structure and hit the same tracer lines.

### New mock needed

`tests/mocks/cargo-nextest` — standard pattern:

```bash
#!/usr/bin/env bash
printf "cargo-nextest %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_CARGO_NEXTEST_EXIT:-0}"
```

Add `MOCK_CARGO_NEXTEST_EXIT` to the Mock Pattern table in `CLAUDE.md`.

## Tests to Write

All tests go in `tests/setup_env/developer.bats`.

### update_rust — skips when UBUNTU not set

```
@test "update_rust: skips when UBUNTU not set" {
  export HAS_RUST=1
  unset UBUNTU
  run update_rust
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ] || ! grep -q "rustup" "${MOCK_CALLS_FILE}"
}
```

### update_rust — uses ~/.cargo/bin/rustup when it exists

```
@test "update_rust: calls ~/.cargo/bin/rustup when it exists" {
  load_mocks
  export UBUNTU=1; export HAS_RUST=1
  mkdir -p "${HOME}/.cargo/bin"
  cp "${BATS_TEST_DIRNAME}/../../tests/mocks/rustup" "${HOME}/.cargo/bin/rustup"
  chmod +x "${HOME}/.cargo/bin/rustup"
  run update_rust
  [ "$status" -eq 0 ]
  grep -q "self update" "${MOCK_CALLS_FILE}"
  grep -q "component add" "${MOCK_CALLS_FILE}"
}
```

### update_rust — uses PATH rustup when cargo/bin/rustup missing

```
@test "update_rust: uses PATH rustup when ~/.cargo/bin/rustup is missing" {
  load_mocks
  export UBUNTU=1; export HAS_RUST=1
  # No ~/.cargo/bin/rustup in fake HOME; tests/mocks/rustup is in PATH
  run update_rust
  [ "$status" -eq 0 ]
  grep -q "self update" "${MOCK_CALLS_FILE}"
}
```

### update_rust — warns when rustup not found anywhere

```
@test "update_rust: logs warning when rustup not found" {
  export UBUNTU=1; export HAS_RUST=1
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  run update_rust
  [ "$status" -eq 0 ]
  [[ "$output" == *"rustup not found"* ]]
}
```

### update_rust — updates nextest when rustup found and cargo-nextest available

```
@test "update_rust: updates nextest when rustup found and cargo-nextest available" {
  load_mocks
  export UBUNTU=1; export HAS_RUST=1
  mkdir -p "${HOME}/.cargo/bin"
  cp "${BATS_TEST_DIRNAME}/../../tests/mocks/rustup" "${HOME}/.cargo/bin/rustup"
  chmod +x "${HOME}/.cargo/bin/rustup"
  run update_rust
  [ "$status" -eq 0 ]
  grep -q "get.nexte.st" "${MOCK_CALLS_FILE}"
}
```

### update_rust — skips nextest when rustup not found

```
@test "update_rust: skips nextest update when rustup not found" {
  export UBUNTU=1; export HAS_RUST=1
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  run update_rust
  [ "$status" -eq 0 ]
  ! grep -q "get.nexte.st" "${MOCK_CALLS_FILE:-/dev/null}"
}
```

### clone_personal_repos — skips when dir exists

```
@test "clone_personal_repos: skips git clone when dotfiles dir exists" {
  load_mocks
  mkdir -p "${PERSONAL_GITREPOS}/dotfiles"
  run clone_personal_repos
  [ "$status" -eq 0 ]
  ! grep -q "git clone.*dotfiles" "${MOCK_CALLS_FILE}"
}
```

### clone_personal_repos — clones when dir missing

```
@test "clone_personal_repos: calls git clone for dotfiles when dir missing" {
  load_mocks
  run clone_personal_repos
  [ "$status" -eq 0 ]
  grep -q "git clone.*dotfiles" "${MOCK_CALLS_FILE}"
}
```

## Files Changed

| File                             | Change                                              |
| -------------------------------- | --------------------------------------------------- |
| `tests/mocks/cargo-nextest`      | New mock script                                     |
| `tests/setup_env/developer.bats` | 8 new tests                                         |
| `CLAUDE.md`                      | Add `MOCK_CARGO_NEXTEST_EXIT` to Mock Pattern table |

## Expected Outcome

`developer.sh` coverage: ~30% (only setup_vim_plugins tested) → ~75–80%.
Adds 8 new BATS tests; total rises from 619 → 627.
