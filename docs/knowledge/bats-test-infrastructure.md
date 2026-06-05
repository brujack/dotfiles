# BATS Test Infrastructure Reference

Stable reference for the dotfiles BATS test harness. Covers test seams (override env vars) and the PATH-mock system (MOCK_* env vars). See `CLAUDE.md` Testing section for behavioral rules and pitfalls.

---

## Test Seams

Functions that operate on specific file paths use override env vars to redirect to temp files in tests:

| Seam                         | Used by                                                              | Effect                                                                                    |
| ---------------------------- | -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `_OVERRIDE_BASH_MAJOR`       | `setup_env.sh` preamble                                              | Overrides `BASH_VERSINFO[0]` (read-only built-in) to test the bash version < 5 error path |
| `_OVERRIDE_BREWFILE_PATH`    | `_update_check_brewfile_drift`                                       | Path to Brewfile; defaults to `${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile`                 |
| `_OVERRIDE_CONSTANTS_PATH`   | `_update_version_pin()`                                              | Redirects to a temp copy of `lib/constants.sh`; defaults to real path when unset          |
| `UPDATE_LOG_PATH`            | `_update_summary()`                                                  | Redirects log writes to a temp file in tests; defaults to `~/.dotfiles-update.log`        |
| `_UPDATE_TMPDIR`             | all summary functions                                                | Set to `${BATS_TEST_TMPDIR}` in tests to isolate snapshot files                           |
| `_BOOTSTRAP_OS_RELEASE`      | `_bootstrap_linux_detect_distro`                                     | Path to os-release file; defaults to `/etc/os-release`                                    |
| `_REBOOT_REQUIRED_PATH`      | `_update_record_end` apt case                                        | Path to reboot-required flag file; defaults to `/var/run/reboot-required`                 |
| `_REBOOT_REQUIRED_PKGS_PATH` | `_update_record_end` apt case                                        | Path to reboot-required.pkgs file; defaults to `/var/run/reboot-required.pkgs`            |
| `_OVERRIDE_FEATURES_DIR`     | `scripts/whats-new-claude-code.sh`, `scripts/whats-new-anthropic.sh` | Redirects output and state files to a temp dir                                            |
| `_OVERRIDE_DOTFILES_ROOT`    | `scripts/whats-new-claude-code.sh`, `scripts/whats-new-anthropic.sh` | Redirects the repo root used for `cd` before git operations                               |
| `_OVERRIDE_AI_CONFIG_DIR`    | `setup_ai_config`, `setup_dotfile_symlinks`                          | Overrides `AI_CONFIG_DIR` (readonly) for test isolation                                   |

Pattern: `local _file="${_OVERRIDE_VAR:-$(dirname "${BASH_SOURCE[0]}")/real/path}"`. Tests set the var and pass a writable temp copy; production code leaves it unset.

---

## Mock Pattern

```bash
# In setup():
load_mocks           # prepends tests/mocks/ to PATH
export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
export MOCK_BREW_LIST_FORMULA="git wget"  # controls mock brew list output
export MOCK_WHICH_MISSING=bats            # makes which return 1 for 'bats'

# Assert what was called:
grep -q "brew install git" "${MOCK_CALLS_FILE}"
```

Available mock env vars:

| Variable | Effect |
|---|---|
| `MOCK_CALLS_FILE` | File where all mock invocations are logged |
| `MOCK_BREW_LIST_FORMULA` | Space-separated formulas returned by `brew list --formula --full-name` (use tap-qualified names, e.g. `teamookla/speedtest/speedtest`) |
| `MOCK_BREW_LIST_CASK` | Space-separated casks returned by `brew list --cask` |
| `MOCK_BREW_LEAVES` | Space-separated formulae returned by `brew leaves` (top-level installs only; default: empty) |
| `MOCK_BREW_TAPS` | Space-separated taps returned by `brew tap` |
| `MOCK_BREW_INSTALL_EXIT` | Exit code for `brew install` (default: 0) |
| `MOCK_BREW_TAP_EXIT` | Exit code for `brew tap <name>` (default: 0) |
| `MOCK_APT_EXIT` | Exit code for `apt-get` (default: 0) |
| `MOCK_WHICH_MISSING` | Command name for which `which` returns 1 |
| `MOCK_CURL_EXIT` | Exit code for `curl` (default: 0); use 22 for HTTP auth failure (FAIL), 28 for timeout (WARN), 6 for DNS failure (WARN) in `_doctor_check_github_mcp` tests |
| `MOCK_UNAME_S` | Value returned by `uname -s` |
| `MOCK_BATS_VER` | BATS_VER used by mock tar to create stub directory |
| `MOCK_ID_U` | Value returned by `id -u` (default: 1000) |
| `MOCK_AWK_OS_NAME` | Distro name returned when `awk` parses `os-release` |
| `MOCK_SW_VERS_PRODUCTVERSION` | OS version returned by `sw_vers -productVersion` (default: 12.0.0) |
| `MOCK_SYSCTL_CPU` | CPU brand string returned by `sysctl -n machdep.cpu.brand_string` (default: Apple M1) |
| `MOCK_PGREP_EXIT` | Exit code for `pgrep` (default: 1 = process not found) |
| `MOCK_SOFTWAREUPDATE_EXIT` | Exit code for `softwareupdate` (default: 0) |
| `MOCK_WGET_EXIT` | Exit code for `wget` (default: 0); `-O` target file is created |
| `MOCK_DPKG_EXIT` | Exit code for `dpkg` (default: 0) |
| `MOCK_DPKG_QUERY_EXIT` | Exit code for `dpkg-query` (default: 0) |
| `MOCK_DPKG_OUTPUT` | Lines printed to stdout by `dpkg-query -W` mock (default: empty) |
| `MOCK_CHSH_EXIT` | Exit code for `chsh` (default: 0) |
| `MOCK_APT_ONLY_EXIT` | Exit code for `apt` only (overrides MOCK_APT_EXIT for apt; default: MOCK_APT_EXIT) |
| `MOCK_ADD_APT_REPO_EXIT` | Exit code for `add-apt-repository` (default: 0) |
| `MOCK_INSTALLER_EXIT` | Exit code for `installer` (default: 0) |
| `MOCK_UNZIP_EXIT` | Exit code for `unzip` (default: 0) |
| `MOCK_GIT_CLONE_EXIT` | Exit code for `git clone` (default: 0); target directory is created |
| `MOCK_GIT_EXIT` | Exit code for all other `git` commands (default: 0) |
| `MOCK_MAS_EXIT` | Exit code for `mas` (default: 0) |
| `MOCK_MAS_UPGRADE_OUTPUT` | Lines printed to stdout by `mas upgrade` mock (default: empty); use `==> Updated AppName (version)` lines to simulate updated apps |
| `MOCK_TEE_EXIT` | Exit code for `tee` (default: 0); real `/usr/bin/tee` is called unless exit ≠ 0 |
| `MOCK_GEM_EXIT` | Exit code for `gem` (default: 0) |
| `MOCK_NPM_EXIT` | Exit code for `npm` (default: 0) |
| `MOCK_SNAP_EXIT` | Exit code for `snap` (default: 0) |
| `MOCK_SNAP_LIST_OUTPUT` | Lines printed to stdout by `snap list` mock (default: empty); include a header line as first line since awk skips `NR>1` |
| `MOCK_NALA_EXIT` | Exit code for `nala` (default: 0) |
| `MOCK_RUSTUP_EXIT` | Exit code for `rustup` (default: 0) |
| `MOCK_BREW_UPDATE_EXIT` | Exit code for `brew update` (default: 0) |
| `MOCK_BREW_UPGRADE_EXIT` | Exit code for `brew upgrade` and `brew upgrade --cask --greedy` (default: 0) |
| `MOCK_BREW_CLEANUP_EXIT` | Exit code for `brew cleanup` (default: 0) |
| `MOCK_CURL_STDOUT` | Content printed to stdout by `curl` mock (used for `$(curl ...)` substitution; default: empty) |
| `MOCK_CURL_PLATFORM_STDOUT` | Content returned by `curl` mock when URL contains `platform.claude.com`; used by `whats-new-anthropic.sh` (default: falls back to `MOCK_CURL_STDOUT`) |
| `MOCK_CURL_SDK_STDOUT` | Content returned by `curl` mock when URL contains `githubusercontent.com`; used by `whats-new-anthropic.sh` (default: falls back to `MOCK_CURL_STDOUT`) |
| `MOCK_XCODE_SELECT_PRINT_PATH_EXIT` | Exit code for `xcode-select --print-path` (default: 0 = already installed) |
| `MOCK_XCODE_SELECT_EXIT` | Exit code for `xcode-select --install` (default: 0) |
| `MOCK_XCODEBUILD_EXIT` | Exit code for `xcodebuild` (default: 0) |
| `MOCK_KILL_EXIT` | Exit code for `kill` (default: 0) |
| `MOCK_TMUX_EXIT` | Exit code for `tmux` (default: 0) |
| `MOCK_RSYNC_EXIT` | Exit code for `rsync` (default: 0) |
| `MOCK_HOSTNAME_OUTPUT` | Value returned by `hostname -s` (default: `testhost`) |
| `MOCK_SLEEP_EXIT` | Exit code for `sleep` (default: 0) |
| `MOCK_PGREP_OUTPUT` | PIDs printed to stdout by `pgrep` mock (default: empty; used to simulate found processes) |
| `MOCK_LN_EXIT` | Exit code for `ln` (default: 0); real `/bin/ln` is called unless exit ≠ 0 |
| `MOCK_CHMOD_EXIT` | Exit code for `chmod` (default: 0); real `/bin/chmod` is called unless exit ≠ 0 |
| `MOCK_MV_EXIT` | Exit code for `mv` (default: 0); real `/bin/mv` is called unless exit ≠ 0 |
| `MOCK_CP_EXIT` | Exit code for `cp` (default: 0); real `/bin/cp` is called unless exit ≠ 0 |
| `MOCK_TAR_EXIT` | Exit code for `tar` (default: 0); when non-zero, suppresses stub directory creation so tests can simulate extraction failure and trigger `cd` failure |
| `MOCK_CLAUDE_EXIT` | Exit code for `claude` (default: 0); applies to all `claude` calls including `-p` |
| `MOCK_CLAUDE_STDOUT` | Content printed to stdout by `claude -p` mock (default: `## New Features\n- Mock feature added`); used by scripts that call `claude -p "prompt"` to summarize content |
| `MOCK_CLAUDE_PLUGINS_LIST_OUTPUT` | Lines printed to stdout by `claude plugins list` mock (default: empty) |

**Pass-through mocks:** `ln`, `chmod`, `mv`, `cp`, and `tee` call the real binary (`/bin/cmd "$@" 2>/dev/null || true`) so tests that assert actual filesystem state (permissions, file existence, symlinks, captured output files) work correctly. Set the corresponding exit var to a non-zero value to simulate failure instead. Any mock that needs to support tests checking real filesystem state must use this pattern — a log-only mock will cause silent assertion failures.
