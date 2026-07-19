#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# ── count_lines.sh ───────────────────────────────────────────────────────────

@test "count_lines.sh exits 1 and prints usage when no argument given" {
  run bash "${REPO_ROOT}/scripts/count_lines.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "count_lines.sh reports correct total line count" {
  local tmpdir="${BATS_TEST_TMPDIR}/testfiles"
  mkdir -p "${tmpdir}"
  printf "line1\nline2\nline3\n" > "${tmpdir}/file1.txt"
  printf "line1\nline2\n" > "${tmpdir}/file2.txt"
  run bash "${REPO_ROOT}/scripts/count_lines.sh" "${tmpdir}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total lines: 5"* ]]
}

@test "count_lines.sh excludes files in the ignore directory" {
  local tmpdir="${BATS_TEST_TMPDIR}/testfiles2"
  mkdir -p "${tmpdir}/keep" "${tmpdir}/ignore"
  printf "line1\nline2\n" > "${tmpdir}/keep/file.txt"
  printf "line1\nline2\nline3\n" > "${tmpdir}/ignore/file.txt"
  run bash "${REPO_ROOT}/scripts/count_lines.sh" "${tmpdir}" "${tmpdir}/ignore"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total lines: 2"* ]]
}

@test "count_lines.sh -h prints usage and exits 0" {
  run bash "${REPO_ROOT}/scripts/count_lines.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "count_lines.sh --help prints the same usage as -h" {
  run bash "${REPO_ROOT}/scripts/count_lines.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# ── count_lines_git.sh ───────────────────────────────────────────────────────

@test "count_lines_git.sh exits 1 and prints usage when no argument given" {
  run bash "${REPO_ROOT}/scripts/count_lines_git.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "count_lines_git.sh reports correct total line count for tracked files" {
  local tmpdir="${BATS_TEST_TMPDIR}/gitrepo"
  mkdir -p "${tmpdir}"
  # Use real git (exclude git mock from PATH so git ls-files works)
  local clean_path
  clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  bash -c "
    export PATH='${clean_path}'
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    git -C '${tmpdir}' init --quiet
    git -C '${tmpdir}' config user.email 'test@test.com'
    git -C '${tmpdir}' config user.name 'Test'
    printf 'line1\nline2\nline3\n' > '${tmpdir}/file1.txt'
    printf 'line1\nline2\n' > '${tmpdir}/file2.txt'
    git -C '${tmpdir}' add .
    git -C '${tmpdir}' commit --quiet -m 'test'
  "
  run bash -c "unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE; export PATH='${clean_path}'; bash '${REPO_ROOT}/scripts/count_lines_git.sh' '${tmpdir}'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total lines: 5"* ]]
}

@test "count_lines_git.sh excludes files matching the ignore prefix" {
  local tmpdir="${BATS_TEST_TMPDIR}/gitrepo2"
  mkdir -p "${tmpdir}/keep" "${tmpdir}/vendor"
  local clean_path
  clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  bash -c "
    export PATH='${clean_path}'
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    git -C '${tmpdir}' init --quiet
    git -C '${tmpdir}' config user.email 'test@test.com'
    git -C '${tmpdir}' config user.name 'Test'
    printf 'line1\nline2\n' > '${tmpdir}/keep/file.txt'
    printf 'line1\nline2\nline3\n' > '${tmpdir}/vendor/file.txt'
    git -C '${tmpdir}' add .
    git -C '${tmpdir}' commit --quiet -m 'test'
  "
  run bash -c "unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE; export PATH='${clean_path}'; bash '${REPO_ROOT}/scripts/count_lines_git.sh' '${tmpdir}' 'vendor'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total lines: 2"* ]]
}

@test "count_lines_git.sh -h prints usage and exits 0" {
  run bash "${REPO_ROOT}/scripts/count_lines_git.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "count_lines_git.sh --help prints the same usage as -h" {
  run bash "${REPO_ROOT}/scripts/count_lines_git.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# ── html2ascii.sh ─────────────────────────────────────────────────────────────

@test "html2ascii.sh removes HTML tags from input" {
  run bash -c "printf '<p>hello</p>\n' | bash '${REPO_ROOT}/scripts/html2ascii.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
  [[ "$output" != *"<p>"* ]]
}

@test "html2ascii.sh tokenizes on spaces (one token per line)" {
  run bash -c "printf 'hello world\n' | bash '${REPO_ROOT}/scripts/html2ascii.sh'"
  [ "$status" -eq 0 ]
  local line_count
  line_count=$(printf "%s\n" "$output" | grep -c ".")
  [ "$line_count" -ge 2 ]
}

@test "html2ascii.sh reads from a file argument" {
  local tmpfile="${BATS_TEST_TMPDIR}/test.html"
  printf "<b>bold</b> text\n" > "${tmpfile}"
  run bash "${REPO_ROOT}/scripts/html2ascii.sh" "${tmpfile}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bold"* ]]
  [[ "$output" != *"<b>"* ]]
}

@test "html2ascii.sh exits 0" {
  run bash -c "printf 'hello\n' | bash '${REPO_ROOT}/scripts/html2ascii.sh'"
  [ "$status" -eq 0 ]
}

@test "html2ascii.sh -h prints usage and exits 0 without reading stdin" {
  run bash "${REPO_ROOT}/scripts/html2ascii.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "html2ascii.sh --help prints the same usage as -h" {
  run bash "${REPO_ROOT}/scripts/html2ascii.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "html2ascii.sh replaces html entities with correct UTF-8 characters" {
  run bash -c "printf 'a&auml;A&Auml;o&ouml;O&Ouml;a&aring;A&Aring;\n' | bash '${REPO_ROOT}/scripts/html2ascii.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"aäAÄoöOÖaåAÅ"* ]]
  [[ "$output" != *$'\xef\xbf\xbd'* ]]
}

@test "html2ascii.sh on a nonexistent file exits 0, surfacing cat's error (no crash, no hang)" {
  run bash "${REPO_ROOT}/scripts/html2ascii.sh" "${BATS_TEST_TMPDIR}/does-not-exist"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No such file or directory"* ]]
}

# ── kill_zombie.sh ─────────────────────────────────────────────────────────────

@test "kill_zombie.sh calls pgrep with defunct pattern" {
  run bash "${REPO_ROOT}/scripts/kill_zombie.sh"
  grep -q "pgrep <defunct>" "${MOCK_CALLS_FILE}"
}

@test "kill_zombie.sh proceeds without error when pgrep returns no PIDs" {
  export MOCK_PGREP_EXIT=1
  run bash "${REPO_ROOT}/scripts/kill_zombie.sh"
  [ "$status" -eq 0 ]
  grep -q "pgrep <defunct>" "${MOCK_CALLS_FILE}"
}

@test "kill_zombie.sh kills a single matching PID" {
  # kill is a bash builtin, invisible to PATH mocks — shadow it with an
  # exported shell function instead (bash functions take precedence over
  # regular, non-special builtins, and export -f propagates into the child
  # `bash script.sh` subprocess this test spawns via `run`).
  kill() { printf "kill %s\n" "$*" >> "${MOCK_CALLS_FILE}"; }
  export -f kill
  export MOCK_PGREP_EXIT=0
  export MOCK_PGREP_OUTPUT="1234"
  run bash "${REPO_ROOT}/scripts/kill_zombie.sh"
  [ "$status" -eq 0 ]
  grep -q "kill -9 1234" "${MOCK_CALLS_FILE}"
}

@test "kill_zombie.sh kills each PID individually when multiple defunct processes exist" {
  # Regression test: the original implementation quoted the whole multi-line
  # pgrep output as a single argument to kill (`kill -9 "${processes}"`),
  # which silently failed to kill any of them once there was more than one
  # match. This must invoke kill once per PID.
  kill() { printf "kill %s\n" "$*" >> "${MOCK_CALLS_FILE}"; }
  export -f kill
  export MOCK_PGREP_EXIT=0
  export MOCK_PGREP_OUTPUT="1234
5678"
  run bash "${REPO_ROOT}/scripts/kill_zombie.sh"
  [ "$status" -eq 0 ]
  grep -q "kill -9 1234" "${MOCK_CALLS_FILE}"
  grep -q "kill -9 5678" "${MOCK_CALLS_FILE}"
  # exactly 2 kill invocations, not 1 combined bad call
  [ "$(grep -c '^kill -9' "${MOCK_CALLS_FILE}")" -eq 2 ]
}

@test "kill_zombie.sh -h prints usage and exits 0 without calling pgrep" {
  run bash "${REPO_ROOT}/scripts/kill_zombie.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  run grep -q pgrep "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "kill_zombie.sh --help prints the same usage as -h" {
  run bash "${REPO_ROOT}/scripts/kill_zombie.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# ── mkill.sh ──────────────────────────────────────────────────────────────────

@test "mkill.sh calls pgrep with the provided pattern" {
  run bash "${REPO_ROOT}/scripts/mkill.sh" myprocess
  grep -q "pgrep myprocess" "${MOCK_CALLS_FILE}"
}

@test "mkill.sh calls sudo kill -9 for each returned pid" {
  export MOCK_PGREP_EXIT=0
  export MOCK_PGREP_OUTPUT="1234
5678"
  run bash "${REPO_ROOT}/scripts/mkill.sh" myprocess
  [ "$status" -eq 0 ]
  grep -q "sudo kill -9 1234" "${MOCK_CALLS_FILE}"
  grep -q "sudo kill -9 5678" "${MOCK_CALLS_FILE}"
}

@test "mkill.sh exits 0 and calls no kill when pgrep finds no matches" {
  export MOCK_PGREP_EXIT=1
  run bash "${REPO_ROOT}/scripts/mkill.sh" myprocess
  [ "$status" -eq 0 ]
  run grep -q "sudo kill" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "mkill.sh exits non-zero with usage message when no pattern given" {
  run bash "${REPO_ROOT}/scripts/mkill.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
  run grep -q pgrep "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "mkill.sh -h prints usage and exits 0 without calling pgrep" {
  run bash "${REPO_ROOT}/scripts/mkill.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  run grep -q pgrep "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "mkill.sh --help prints the same usage as -h" {
  run bash "${REPO_ROOT}/scripts/mkill.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# ── restart_fah.sh ─────────────────────────────────────────────────────────────

@test "restart_fah.sh calls FAHClient stop" {
  run bash "${REPO_ROOT}/scripts/restart_fah.sh"
  grep -q "sudo systemctl stop FAHClient" "${MOCK_CALLS_FILE}"
}

@test "restart_fah.sh calls FAHClient start" {
  run bash "${REPO_ROOT}/scripts/restart_fah.sh"
  grep -q "sudo systemctl start FAHClient" "${MOCK_CALLS_FILE}"
}

@test "restart_fah.sh calls pgrep fah between stop and start" {
  export MOCK_PGREP_EXIT=0
  export MOCK_PGREP_OUTPUT="4321"
  run bash "${REPO_ROOT}/scripts/restart_fah.sh"
  grep -q "pgrep fah" "${MOCK_CALLS_FILE}"
  grep -q "sudo kill -9 4321" "${MOCK_CALLS_FILE}"
}

@test "restart_fah.sh -h prints usage and exits 0 without touching FAHClient" {
  run bash "${REPO_ROOT}/scripts/restart_fah.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  run grep -q FAHClient "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "restart_fah.sh --help prints the same usage as -h" {
  run bash "${REPO_ROOT}/scripts/restart_fah.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# ── sync_git_repos.sh ─────────────────────────────────────────────────────────

@test "sync_git_repos.sh with no arguments runs both legs (default mode)" {
  export MOCK_HOSTNAME_OUTPUT=studio
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export HOME="${BATS_TEST_TMPDIR}"
  mkdir -p "${HOME}/git-repos/personal/fake-repo/.git"
  run bash "${REPO_ROOT}/scripts/sync_git_repos.sh"
  [ "$status" -eq 0 ]
  grep -q "^git " "${MOCK_CALLS_FILE}"
  grep -q rsync "${MOCK_CALLS_FILE}"
}

@test "sync_git_repos.sh -h prints usage mentioning both sync modes" {
  run bash "${REPO_ROOT}/scripts/sync_git_repos.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"git sync"* ]]
  [[ "$output" == *"legacy sync"* ]]
}

@test "sync_git_repos.sh --help prints the same usage as -h" {
  run bash "${REPO_ROOT}/scripts/sync_git_repos.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--git-only"* ]]
  [[ "$output" == *"--legacy-only"* ]]
}

@test "sync_git_repos.sh --git-only runs the git leg and skips the legacy rsync leg" {
  export MOCK_HOSTNAME_OUTPUT=studio
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export HOME="${BATS_TEST_TMPDIR}"
  # Seed a fake repo so the git-sync leg has something to act on — an empty
  # personal/ tree would make "git leg ran and did nothing" and "script
  # crashed before mode dispatch" indistinguishable to this test.
  mkdir -p "${HOME}/git-repos/personal/fake-repo/.git"
  run bash "${REPO_ROOT}/scripts/sync_git_repos.sh" --git-only
  [ "$status" -eq 0 ]
  grep -q "^git " "${MOCK_CALLS_FILE}"
  run grep -q rsync "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "sync_git_repos.sh rejects an unrecognized flag without running either leg" {
  export MOCK_HOSTNAME_OUTPUT=studio
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export HOME="${BATS_TEST_TMPDIR}"
  mkdir -p "${HOME}/git-repos/personal/fake-repo/.git"
  run bash "${REPO_ROOT}/scripts/sync_git_repos.sh" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unrecognized option"* ]]
  run grep -q rsync "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
  run grep -q "^git " "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "sync_git_repos.sh --legacy-only skips the git sync leg" {
  export MOCK_HOSTNAME_OUTPUT=studio
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export HOME="${BATS_TEST_TMPDIR}"
  mkdir -p "${HOME}/git-repos/personal"
  run bash "${REPO_ROOT}/scripts/sync_git_repos.sh" --legacy-only
  [ "$status" -eq 0 ]
  grep -q rsync "${MOCK_CALLS_FILE}"
}

# ── pre-commit-hook.sh ────────────────────────────────────────────────────────

@test "pre-commit-hook.sh is executable" {
  [ -x "${REPO_ROOT}/scripts/pre-commit-hook.sh" ]
}

@test "pre-commit-hook.sh exits 0 when make lint passes" {
  local tmpdir="${BATS_TEST_TMPDIR}/fakerepo"
  mkdir -p "${tmpdir}"
  printf '#!/usr/bin/env bash\nprintf "%%s\n" "${MOCK_GIT_TOPLEVEL:-/tmp}"\n' > "${tmpdir}/git"
  printf '#!/usr/bin/env bash\nexit "${MOCK_MAKE_EXIT:-0}"\n' > "${tmpdir}/make"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${tmpdir}/ggshield"
  chmod +x "${tmpdir}/git" "${tmpdir}/make" "${tmpdir}/ggshield"
  run bash -c "MOCK_GIT_TOPLEVEL='${tmpdir}' PATH='${tmpdir}:${PATH}' bash '${REPO_ROOT}/scripts/pre-commit-hook.sh'"
  [ "$status" -eq 0 ]
}

@test "pre-commit-hook.sh exits 1 when make lint fails" {
  local tmpdir="${BATS_TEST_TMPDIR}/fakerepo2"
  mkdir -p "${tmpdir}"
  printf '#!/usr/bin/env bash\nprintf "%%s\n" "${MOCK_GIT_TOPLEVEL:-/tmp}"\n' > "${tmpdir}/git"
  printf '#!/usr/bin/env bash\nexit "${MOCK_MAKE_EXIT:-0}"\n' > "${tmpdir}/make"
  chmod +x "${tmpdir}/git" "${tmpdir}/make"
  run bash -c "MOCK_GIT_TOPLEVEL='${tmpdir}' MOCK_MAKE_EXIT=1 PATH='${tmpdir}:${PATH}' bash '${REPO_ROOT}/scripts/pre-commit-hook.sh'"
  [ "$status" -eq 1 ]
}

@test "pre-commit-hook.sh exits 1 when ggshield fails" {
  local tmpdir="${BATS_TEST_TMPDIR}/fakerepo3"
  mkdir -p "${tmpdir}"
  printf '#!/usr/bin/env bash\nprintf "%%s\n" "${MOCK_GIT_TOPLEVEL:-/tmp}"\n' > "${tmpdir}/git"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${tmpdir}/make"
  printf '#!/usr/bin/env bash\nexit 1\n' > "${tmpdir}/ggshield"
  chmod +x "${tmpdir}/git" "${tmpdir}/make" "${tmpdir}/ggshield"
  run bash -c "MOCK_GIT_TOPLEVEL='${tmpdir}' PATH='${tmpdir}:${PATH}' bash '${REPO_ROOT}/scripts/pre-commit-hook.sh'"
  [ "$status" -eq 1 ]
}

@test "pre-commit-hook.sh succeeds when ggshield is not installed" {
  local tmpdir="${BATS_TEST_TMPDIR}/fakerepo4"
  mkdir -p "${tmpdir}"
  printf '#!/usr/bin/env bash\nprintf "%%s\n" "${MOCK_GIT_TOPLEVEL:-/tmp}"\n' > "${tmpdir}/git"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${tmpdir}/make"
  # No ggshield in PATH — hook should still pass
  chmod +x "${tmpdir}/git" "${tmpdir}/make"
  run bash -c "MOCK_GIT_TOPLEVEL='${tmpdir}' PATH='${tmpdir}:/usr/bin:/bin' bash '${REPO_ROOT}/scripts/pre-commit-hook.sh'"
  [ "$status" -eq 0 ]
}

# ── bootstrap_mac.sh ─────────────────────────────────────────────────────────

@test "_bootstrap_check_macos passes on Darwin" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  export MOCK_UNAME_S=Darwin
  run _bootstrap_check_macos
  [ "$status" -eq 0 ]
}

@test "_bootstrap_check_macos fails on Linux" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  export MOCK_UNAME_S=Linux
  run _bootstrap_check_macos
  [ "$status" -eq 1 ]
  [[ "$output" == *"macOS only"* ]]
}

@test "_bootstrap_mac_install_homebrew skips when brew already installed" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  run _bootstrap_mac_install_homebrew
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  ! grep -q "curl" "${MOCK_CALLS_FILE}"
}

@test "_bootstrap_mac_install_homebrew calls curl when brew missing" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  export MOCK_WHICH_MISSING=brew
  run _bootstrap_mac_install_homebrew
  [ "$status" -eq 0 ]
  grep -q "curl" "${MOCK_CALLS_FILE}"
}

@test "_bootstrap_mac_install_homebrew returns error when curl fails" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  export MOCK_WHICH_MISSING=brew
  export MOCK_CURL_EXIT=1
  run _bootstrap_mac_install_homebrew
  [ "$status" -ne 0 ]
}

@test "_bootstrap_mac_install_bash5 skips when bash >= 5" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  local _mockbash="${BATS_TEST_TMPDIR}/bash5mock"
  printf '#!/bin/bash\nprintf "GNU bash, version 5.2.0(1)-release\\n"\n' > "${_mockbash}"
  chmod +x "${_mockbash}"
  export BASH="${_mockbash}"
  run _bootstrap_mac_install_bash5
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  ! grep -q "brew install bash" "${MOCK_CALLS_FILE}"
}

@test "_bootstrap_mac_install_bash5 installs when bash < 5" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  local _mockbash="${BATS_TEST_TMPDIR}/bash3mock"
  printf '#!/bin/bash\nprintf "GNU bash, version 3.2.57(1)-release\\n"\n' > "${_mockbash}"
  chmod +x "${_mockbash}"
  export BASH="${_mockbash}"
  run _bootstrap_mac_install_bash5
  [ "$status" -eq 0 ]
  grep -q "brew install bash" "${MOCK_CALLS_FILE}"
}

@test "_bootstrap_mac_install_bash5 returns error when brew install fails" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  local _mockbash="${BATS_TEST_TMPDIR}/bash3mock2"
  printf '#!/bin/bash\nprintf "GNU bash, version 3.2.57(1)-release\\n"\n' > "${_mockbash}"
  chmod +x "${_mockbash}"
  export BASH="${_mockbash}"
  export MOCK_BREW_INSTALL_EXIT=1
  run _bootstrap_mac_install_bash5
  [ "$status" -ne 0 ]
}

@test "bootstrap_mac_main calls functions in order on Darwin" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  export MOCK_UNAME_S=Darwin
  local _mockbash="${BATS_TEST_TMPDIR}/bash5main"
  printf '#!/bin/bash\nprintf "GNU bash, version 5.2.0(1)-release\\n"\n' > "${_mockbash}"
  chmod +x "${_mockbash}"
  export BASH="${_mockbash}"
  run bootstrap_mac_main
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bootstrap complete"* ]]
}

@test "bootstrap_mac_main fails on non-macOS" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  export MOCK_UNAME_S=Linux
  run bootstrap_mac_main
  [ "$status" -eq 1 ]
}

@test "bootstrap_mac_main -h prints usage and exits 0 without checking macOS" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  export MOCK_UNAME_S=Linux
  run bootstrap_mac_main -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "bootstrap_mac_main --help prints the same usage as -h" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  run bootstrap_mac_main --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "bootstrap_mac.sh forwards -h to bootstrap_mac_main when run directly" {
  run bash "${REPO_ROOT}/scripts/bootstrap_mac.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# ── bootstrap_linux.sh ────────────────────────────────────────────────────────

@test "_bootstrap_check_linux passes on Linux" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  export MOCK_UNAME_S=Linux
  run _bootstrap_check_linux
  [ "$status" -eq 0 ]
}

@test "_bootstrap_check_linux fails on Darwin" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  export MOCK_UNAME_S=Darwin
  run _bootstrap_check_linux
  [ "$status" -eq 1 ]
  [[ "$output" == *"Linux only"* ]]
}

@test "_bootstrap_linux_detect_distro detects Ubuntu" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  local _osrel="${BATS_TEST_TMPDIR}/os-release"
  printf 'ID=ubuntu\nID_LIKE=debian\n' > "${_osrel}"
  export _BOOTSTRAP_OS_RELEASE="${_osrel}"
  _bootstrap_linux_detect_distro
  [ "${_DISTRO_FAMILY}" = "ubuntu" ]
}

@test "_bootstrap_linux_detect_distro returns unknown for unrecognized distro" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  local _osrel="${BATS_TEST_TMPDIR}/os-release"
  printf 'ID=alpine\n' > "${_osrel}"
  export _BOOTSTRAP_OS_RELEASE="${_osrel}"
  _bootstrap_linux_detect_distro
  [ "${_DISTRO_FAMILY}" = "unknown" ]
}

@test "_bootstrap_linux_detect_distro handles missing os-release" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  export _BOOTSTRAP_OS_RELEASE="${BATS_TEST_TMPDIR}/nonexistent"
  _bootstrap_linux_detect_distro
  [ "${_DISTRO_FAMILY}" = "unknown" ]
}

@test "_bootstrap_linux_install_prereqs calls apt-get for ubuntu" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  _DISTRO_FAMILY="ubuntu"
  run _bootstrap_linux_install_prereqs
  [ "$status" -eq 0 ]
  grep -q "apt-get install" "${MOCK_CALLS_FILE}"
}

@test "_bootstrap_linux_install_prereqs prints warning for unknown" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  _DISTRO_FAMILY="unknown"
  run _bootstrap_linux_install_prereqs
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unknown distro"* ]]
}

@test "_bootstrap_linux_install_prereqs returns error when apt-get fails" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  _DISTRO_FAMILY="ubuntu"
  export MOCK_APT_EXIT=1
  run _bootstrap_linux_install_prereqs
  [ "$status" -ne 0 ]
}

@test "_bootstrap_linux_install_homebrew skips when brew already installed" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  run _bootstrap_linux_install_homebrew
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  ! grep -q "curl" "${MOCK_CALLS_FILE}"
}

@test "_bootstrap_linux_install_homebrew calls curl when brew missing" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  export MOCK_WHICH_MISSING=brew
  run _bootstrap_linux_install_homebrew
  [ "$status" -eq 0 ]
  grep -q "curl" "${MOCK_CALLS_FILE}"
}

@test "bootstrap_linux_main calls functions in order on Linux" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  export MOCK_UNAME_S=Linux
  local _osrel="${BATS_TEST_TMPDIR}/os-release"
  printf 'ID=ubuntu\n' > "${_osrel}"
  export _BOOTSTRAP_OS_RELEASE="${_osrel}"
  run bootstrap_linux_main
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bootstrap complete"* ]]
}

@test "bootstrap_linux_main fails on non-Linux" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  export MOCK_UNAME_S=Darwin
  run bootstrap_linux_main
  [ "$status" -eq 1 ]
}

@test "bootstrap_linux_main -h prints usage and exits 0 without checking Linux" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  export MOCK_UNAME_S=Darwin
  run bootstrap_linux_main -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "bootstrap_linux_main --help prints the same usage as -h" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  run bootstrap_linux_main --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "bootstrap_linux.sh forwards -h to bootstrap_linux_main when run directly" {
  run bash "${REPO_ROOT}/scripts/bootstrap_linux.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "push-bash-coverage.sh -h prints usage and exits 0 without running coverage" {
  run bash "${REPO_ROOT}/scripts/push-bash-coverage.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  run grep -q "run-bash-coverage" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "push-bash-coverage.sh --help prints the same usage as -h" {
  run bash "${REPO_ROOT}/scripts/push-bash-coverage.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "run-bash-coverage.sh -h prints usage and exits 0 without running bats" {
  run bash "${REPO_ROOT}/scripts/run-bash-coverage.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  run grep -q "bats" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "run-bash-coverage.sh --help prints the same usage as -h" {
  run bash "${REPO_ROOT}/scripts/run-bash-coverage.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test ".osx.sh -h prints usage and exits 0 without writing any defaults" {
  run bash "${REPO_ROOT}/scripts/.osx.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  run grep -q "defaults\|sudo\|killall" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test ".osx.sh --help prints the same usage as -h" {
  run bash "${REPO_ROOT}/scripts/.osx.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}
