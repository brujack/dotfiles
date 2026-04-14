# Doctor Mode Enhancement Design

**Status:** Draft
**Date:** 2026-04-08

## Goal

Upgrade `run_doctor()` from a var-dump into a real diagnostic tool that actively verifies system state and exits non-zero when checks fail.

## Architecture

`run_doctor()` in `lib/helpers.sh` gains a check framework built around two primitives:

- `doctor_pass(label)` — prints `[PASS] label` in green, increments pass counter
- `doctor_fail(label, detail)` — prints `[FAIL] label: detail` in red, increments fail counter, sets `_DOCTOR_FAILED=1`

After all checks run, a summary line prints (`N checks passed, M failed`) and `run_doctor()` returns 1 if `_DOCTOR_FAILED=1`, else 0. The `setup_env.sh` dispatch already does `{ run_doctor; exit 0; }` — this changes to `{ run_doctor; exit $?; }`.

## Check Categories

### 1. Environment vars (existing — keep as-is)

Current var-dump section retained for context. Reformatted as a header block, not pass/fail.

### 2. Symlink checks

For each expected dotfile symlink, verify it exists (`-L`) and its target exists (`-e`). If the symlink is missing or broken, fail.

Symlinks checked:

- `~/.zshrc` → repo `.zshrc`
- `~/.zprofile` → repo `.zprofile`
- `~/.vimrc` → repo `.vimrc`
- `~/.tmux.conf` → repo `.tmux.conf`
- `~/.p10k.zsh` → repo `.p10k.zsh`
- `~/.ssh/config` → repo `.ssh/config`
- `~/.config/starship.toml` → repo `starship.toml`
- `~/.config/.zshrc.d` → repo `.config/.zshrc.d`
- `~/.gitconfig` → repo `.gitconfig_mac` (macOS) or `.gitconfig_linux` (Linux)

### 3. Tool presence checks

Verify each tool is reachable via `command -v`. Fail if missing.

Tools checked: `git`, `zsh`, `curl`, `tmux`, `bats`

macOS-only: `brew`

Linux-only: `apt-get` or `yum`/`dnf` (whichever matches the distro)

### 4. Credential directory checks

Verify each directory exists and has mode `700`. Fail if missing or wrong permissions.

Directories: `~/.aws`, `~/.tf_creds`, `~/.ssh`, `~/.tsh`

Permission check: `stat -c '%a'` (Linux) / `stat -f '%OLp'` (macOS).

### 5. Version checks

For each pinned tool, compare the pinned constant against the installed version.

| Tool   | Pinned constant | Version command                    |
| ------ | --------------- | ---------------------------------- |
| Go     | `GO_VER`        | `go version` → parse semver        |
| Python | `PYTHON_VER`    | `python3 --version` → parse semver |
| Ruby   | `RUBY_VER`      | `ruby --version` → parse semver    |
| zsh    | `ZSH_VER`       | `zsh --version` → parse semver     |

If the tool is not installed, skip with a warn (not a fail — presence is covered by category 3). If installed version doesn't match pinned, fail.

Version comparison: string equality on the major.minor.patch portion (e.g. `3.14.3` must equal `PYTHON_VER`). Patch-level drift is a fail.

## Output Format

```
=== Doctor Report ===

OS Detection:
  MACOS=1  LINUX=<unset>
  ...

Profile:
  PROFILE=personal_laptop

Capabilities:
  HAS_GUI=1  HAS_DEVTOOLS=1  ...

Key Paths:
  HOME=/Users/bruce  ...

=== Checks ===

Symlinks:
  [PASS] ~/.zshrc
  [FAIL] ~/.tmux.conf: symlink missing

Tools:
  [PASS] git
  [PASS] brew

Credential directories:
  [PASS] ~/.aws (700)
  [FAIL] ~/.tf_creds: missing

Versions:
  [PASS] go (1.26)
  [FAIL] python3: installed 3.13.1, pinned 3.14.3

=== Summary ===
14 checks passed, 2 failed
```

## Error Handling

- `stat` command differs between macOS and Linux — use `[[ -n ${MACOS} ]]` to branch
- Missing tools in version checks → `log_warn` and skip (not counted as fail)
- Any `command -v` failure in tool presence → counted as fail

## Testing

New tests in `tests/setup_env/unit.bats`:

- `doctor_pass` increments pass count and prints `[PASS]`
- `doctor_fail` sets `_DOCTOR_FAILED` and prints `[FAIL]`
- `run_doctor` exits 0 when no failures
- `run_doctor` exits 1 when at least one failure
- Symlink check passes when symlink exists, fails when missing
- Tool check passes when tool present (`command -v` succeeds), fails when absent
- Credential dir check passes with correct permissions, fails when missing
- Version check passes when versions match, fails when mismatch

## Files Modified

| Action | File                                                                        |
| ------ | --------------------------------------------------------------------------- |
| Modify | `lib/helpers.sh` — add `doctor_pass`, `doctor_fail`, rewrite `run_doctor()` |
| Modify | `setup_env.sh` — change `exit 0` to `exit $?` in doctor dispatch            |
| Modify | `tests/setup_env/unit.bats` — add check framework tests                     |
| Modify | `CLAUDE.md` — note non-zero exit behavior                                   |
