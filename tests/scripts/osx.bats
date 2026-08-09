#!/usr/bin/env bats
# Coverage backfill for scripts/.osx.sh — a one-shot macOS preference dump.
# It is a straight-line script: past the -h/--help guard every line runs
# unconditionally, so there is no branching surface beyond "was -h/--help
# passed". There is no pure/testable function in it either (tdd.md's
# property-test section: "if the audit finds no pure, testable operations
# ... note it explicitly and skip" — every observable behavior here is a
# side effect through defaults/chflags/killall/sudo).
#
# defaults, chflags, and killall have no PATH mock in tests/mocks/, and the
# real tests/mocks/sudo execs whatever absolute-path binary it's given when
# one exists on the filesystem — which /System/Library/.../kickstart
# genuinely does on a real Mac. Shadowing all four as exported bash
# functions (the same technique tests/scripts/unit.bats already uses to
# shadow the `kill` builtin for kill_zombie.sh) makes them win bash's
# command lookup ahead of both the real binaries and the PATH mock, so
# nothing in this file can touch real system state. See CLAUDE.md's Mock
# Pattern section and tests/scripts/unit.bats:187-199 for the precedent.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"

  # shellcheck disable=SC2317 # not dead: exported for the `bash .osx.sh`
  # child process spawned by `run` in every test below.
  defaults() { printf 'defaults %s\n' "$*" >>"${MOCK_CALLS_FILE}"; return "${MOCK_DEFAULTS_EXIT:-0}"; }
  # shellcheck disable=SC2317
  chflags() { printf 'chflags %s\n' "$*" >>"${MOCK_CALLS_FILE}"; return "${MOCK_CHFLAGS_EXIT:-0}"; }
  # shellcheck disable=SC2317
  killall() { printf 'killall %s\n' "$*" >>"${MOCK_CALLS_FILE}"; return "${MOCK_KILLALL_EXIT:-0}"; }
  # shellcheck disable=SC2317
  sudo() { printf 'sudo %s\n' "$*" >>"${MOCK_CALLS_FILE}"; return "${MOCK_SUDO_EXIT:-0}"; }
  export -f defaults chflags killall sudo
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
  unset MOCK_DEFAULTS_EXIT MOCK_CHFLAGS_EXIT MOCK_KILLALL_EXIT MOCK_SUDO_EXIT
}

# Full expected call list, in the order scripts/.osx.sh issues them. Used by
# multiple tests below rather than duplicated per-test.
_assert_full_run_calls() {
  local -a expected_defaults=(
    "write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true"
    "write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true"
    "write com.apple.screencapture type -string png"
    "write com.apple.screencapture disable-shadow -bool true"
    "write com.apple.finder NewWindowTargetPath -string file://${HOME}"
    "write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true"
    "write com.apple.finder ShowHardDrivesOnDesktop -bool true"
    "write com.apple.finder ShowMountedServersOnDesktop -bool true"
    "write com.apple.finder ShowRemovableMediaOnDesktop -bool true"
    "write com.apple.finder AppleShowAllFiles -bool true"
    "write NSGlobalDomain AppleShowAllExtensions -bool true"
    "write com.apple.finder ShowStatusBar -bool true"
    "write com.apple.finder _FXShowPosixPathInTitle -bool true"
    "write com.apple.finder FXEnableExtensionChangeWarning -bool false"
    "write com.apple.desktopservices DSDontWriteNetworkStores -bool true"
    "write com.apple.finder FXPreferredViewStyle -string Flwv"
    "write com.apple.ActivityMonitor OpenMainWindow -bool true"
    "write com.apple.ActivityMonitor ShowCategory -int 0"
    "write com.apple.systemuiserver menuExtras -array-add /System/Library/CoreServices/Menu Extras/Volume.menu"
    "write com.apple.systemuiserver menuExtras -array-add /System/Library/CoreServices/Menu Extras/Bluetooth.menu"
    "write NSGlobalDomain com.apple.swipescrolldirection -bool false"
    "write com.apple.dock autohide -bool true"
    "write com.apple.dock largesize -int 60"
  )
  local _line
  for _line in "${expected_defaults[@]}"; do
    grep -F -q -- "defaults ${_line}" "${MOCK_CALLS_FILE}"
  done
  grep -F -q -- "chflags nohidden ${HOME}/Library" "${MOCK_CALLS_FILE}"
  grep -F -q -- "killall SystemUIServer" "${MOCK_CALLS_FILE}"
  grep -F -q -- "sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -activate -configure -access -on -users bruce -privs -all -restart -agent -menu" "${MOCK_CALLS_FILE}"
  grep -F -q -- "sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -restart -agent" "${MOCK_CALLS_FILE}"
  grep -F -q -- "sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist" "${MOCK_CALLS_FILE}"
}

# ── main flow: no args ───────────────────────────────────────────────────────

@test ".osx.sh with no args writes every expected Finder, screenshot, and print-panel default" {
  run bash "${REPO_ROOT}/scripts/.osx.sh"
  [ "$status" -eq 0 ]
  _assert_full_run_calls
}

@test ".osx.sh with no args issues exactly 23 defaults writes, 1 chflags, 1 killall, and 3 sudo calls (no unintended extra side effects)" {
  run bash "${REPO_ROOT}/scripts/.osx.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^defaults ' "${MOCK_CALLS_FILE}")" -eq 23 ]
  [ "$(grep -c '^chflags ' "${MOCK_CALLS_FILE}")" -eq 1 ]
  [ "$(grep -c '^killall ' "${MOCK_CALLS_FILE}")" -eq 1 ]
  [ "$(grep -c '^sudo ' "${MOCK_CALLS_FILE}")" -eq 3 ]
  # 23 + 1 + 1 + 3 == 28, and nothing else was logged.
  [ "$(wc -l <"${MOCK_CALLS_FILE}")" -eq 28 ]
}

@test ".osx.sh restarts SystemUIServer after the defaults writes and before the sudo calls" {
  run bash "${REPO_ROOT}/scripts/.osx.sh"
  [ "$status" -eq 0 ]
  local _killall_line _first_sudo_line
  _killall_line="$(grep -n '^killall SystemUIServer$' "${MOCK_CALLS_FILE}" | cut -d: -f1)"
  _first_sudo_line="$(grep -n '^sudo ' "${MOCK_CALLS_FILE}" | head -1 | cut -d: -f1)"
  [ -n "${_killall_line}" ]
  [ -n "${_first_sudo_line}" ]
  [ "${_killall_line}" -lt "${_first_sudo_line}" ]
}

# ── boundary values: argument handling past the usage guard ─────────────────

@test ".osx.sh with an unrecognized flag still runs the main body (only -h/--help short-circuit)" {
  run bash "${REPO_ROOT}/scripts/.osx.sh" --not-a-real-flag
  [ "$status" -eq 0 ]
  [[ "$output" != *"Usage:"* ]]
  _assert_full_run_calls
}

@test ".osx.sh with an empty-string argument still runs the main body" {
  run bash "${REPO_ROOT}/scripts/.osx.sh" ""
  [ "$status" -eq 0 ]
  [[ "$output" != *"Usage:"* ]]
  _assert_full_run_calls
}

@test ".osx.sh with multiple positional arguments still runs the main body (only \$1 is inspected)" {
  run bash "${REPO_ROOT}/scripts/.osx.sh" foo bar baz
  [ "$status" -eq 0 ]
  [[ "$output" != *"Usage:"* ]]
  _assert_full_run_calls
}

# ── error paths: script has no `set -e` — verify the actual fail-open behavior ──

@test ".osx.sh continues issuing later commands even when every defaults write fails" {
  export MOCK_DEFAULTS_EXIT=1
  run bash "${REPO_ROOT}/scripts/.osx.sh"
  # No set -e in the script: a failing defaults call does not abort the run,
  # so status reflects only the LAST command executed (sudo launchctl, which
  # still returns 0 here) — not the earlier defaults failures.
  [ "$status" -eq 0 ]
  [ "$(grep -c '^defaults ' "${MOCK_CALLS_FILE}")" -eq 23 ]
  grep -F -q -- "killall SystemUIServer" "${MOCK_CALLS_FILE}"
  grep -F -q -- "sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist" "${MOCK_CALLS_FILE}"
}

@test ".osx.sh continues to the sudo calls even when chflags fails" {
  export MOCK_CHFLAGS_EXIT=1
  run bash "${REPO_ROOT}/scripts/.osx.sh"
  [ "$status" -eq 0 ]
  grep -F -q -- "chflags nohidden ${HOME}/Library" "${MOCK_CALLS_FILE}"
  [ "$(grep -c '^sudo ' "${MOCK_CALLS_FILE}")" -eq 3 ]
}

@test ".osx.sh continues to the sudo calls even when killall fails" {
  export MOCK_KILLALL_EXIT=1
  run bash "${REPO_ROOT}/scripts/.osx.sh"
  [ "$status" -eq 0 ]
  grep -F -q -- "killall SystemUIServer" "${MOCK_CALLS_FILE}"
  [ "$(grep -c '^sudo ' "${MOCK_CALLS_FILE}")" -eq 3 ]
}

@test ".osx.sh's own exit status is the final sudo call's status (last command, no set -e, no explicit exit)" {
  export MOCK_SUDO_EXIT=1
  run bash "${REPO_ROOT}/scripts/.osx.sh"
  [ "$status" -eq 1 ]
  # All three sudo calls still ran despite each failing.
  [ "$(grep -c '^sudo ' "${MOCK_CALLS_FILE}")" -eq 3 ]
}

# ── state transition / idempotency ───────────────────────────────────────────

@test ".osx.sh run twice produces the same set of calls both times (idempotent — no accumulating extra state)" {
  bash "${REPO_ROOT}/scripts/.osx.sh"
  local _first_count
  _first_count="$(wc -l <"${MOCK_CALLS_FILE}")"
  [ "${_first_count}" -eq 28 ]

  # NB: `cp` itself is PATH-mocked and would log its own invocation into
  # MOCK_CALLS_FILE (tests/mocks/cp is a logging pass-through). `cat` has no
  # mock, so it's used here to snapshot the file without corrupting it.
  local _run1_calls="${BATS_TEST_TMPDIR}/run1_calls"
  cat "${MOCK_CALLS_FILE}" >"${_run1_calls}"
  : >"${MOCK_CALLS_FILE}"

  bash "${REPO_ROOT}/scripts/.osx.sh"
  local _second_count
  _second_count="$(wc -l <"${MOCK_CALLS_FILE}")"
  [ "${_second_count}" -eq "${_first_count}" ]
  diff "${_run1_calls}" "${MOCK_CALLS_FILE}"
}
