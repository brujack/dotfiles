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
  run _run_coverage -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  run grep -q "bats" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "run-bash-coverage.sh --help prints the same usage as -h" {
  run _run_coverage --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# Regression: the instrumented set was a literal array holding 13 of 36 tracked
# .sh files, so the reported 91% and the blocking 90% CI floor were computed over
# a third of the repo. An omitted file left the percentage unchanged instead of
# lowering it, which is why nothing surfaced it. Asserting against git ls-files
# means the denominator cannot silently shrink again.
@test "run-bash-coverage.sh instruments every tracked lib/*.sh" {
  run _run_coverage --list-sources
  [ "$status" -eq 0 ]

  # load_mocks prepends tests/mocks to PATH, and tests/mocks/git logs its args
  # and prints nothing. Calling git here through the mocked PATH returns an
  # empty list, the loop below never runs, and the test passes no matter what
  # the script instruments — verified: with lib/package_capture.sh deliberately
  # absent, the mocked form still reported ok. Strip the mock dir for this one
  # command so the expectation comes from the real index.
  local _real_path="${PATH#"${REPO_ROOT}/tests/mocks:"}"
  local _tracked
  _tracked="$(cd "${REPO_ROOT}" && PATH="${_real_path}" git ls-files 'lib/*.sh')"
  [ -n "${_tracked}" ] || { printf 'git ls-files returned nothing — mock still shadowing\n' >&2; false; }

  local _missing=0 _lib
  while IFS= read -r _lib; do
    if ! printf '%s\n' "${output}" | grep -qx "${REPO_ROOT}/${_lib}"; then
      printf 'not instrumented: %s\n' "${_lib}" >&2
      _missing=1
    fi
  done <<< "${_tracked}"
  [ "${_missing}" -eq 0 ]
}

# Regression: the coverable-line count included the body of multi-line
# `python3 -c "..."` blocks. Those are Python — xtrace emits one line for the
# whole invocation — so they inflated the denominator with lines no test could
# ever cover. lib/package_capture.sh counted 107 lines of which 54 were Python,
# reporting 22% against a ceiling it could not reach.
@test "run-bash-coverage.sh does not count multi-line python3 -c bodies as bash" {
  cat > "${BATS_TEST_TMPDIR}/embedded.sh" <<'FIXTURE'
#!/usr/bin/env bash
real_bash_one=1
_out=$(python3 -c "
import json
x = 1
print(json.dumps(x))
")
real_bash_two=2
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/embedded.sh"
  [ "$status" -eq 0 ]
  # Counted: real_bash_one, the _out=$(python3 -c " opening line, real_bash_two.
  # Not counted: the shebang (a comment), the three Python lines, and the ")
  # closing delimiter.
  [ "$output" -eq 3 ]
}

@test "run-bash-coverage.sh still counts a single-line python3 -c as bash" {
  cat > "${BATS_TEST_TMPDIR}/inline.sh" <<'FIXTURE'
#!/usr/bin/env bash
id=$(python3 -c "import uuid; print(str(uuid.uuid4()))")
after=1
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/inline.sh"
  [ "$status" -eq 0 ]
  # The shebang is a comment; the two remaining lines are both real bash.
  [ "$output" -eq 2 ]
}

# Error paths, not decoration: --count-coverable used to print 0 and exit 0 for
# a missing file — a confident wrong answer from the flag whose whole job is
# auditing the coverage denominator — and a bare --count-coverable fell through
# to a multi-minute tracer run.
# run-bash-coverage.sh derives its instrumented set with `git ls-files`, and
# load_mocks shadows git with a stub that prints nothing. Invoked through the
# mocked PATH the script sees an empty tracked set and exits 1 by design (a
# silently short set is the exact defect it was fixed for). Every test that
# executes the script therefore needs the real git, using the same PATH-strip
# idiom the count_lines_git.sh tests above already use.
_run_coverage() {
  local _clean_path
  _clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  PATH="${_clean_path}" bash "${REPO_ROOT}/scripts/run-bash-coverage.sh" "$@"
}

# Regression: the opener was matched against the raw line BEFORE the comment
# skip, so a comment merely mentioning python3 -c " set the skip state and
# swallowed every following line to EOF. That inflates the percentage rather
# than lowering it — against a gate sitting at exactly 90% with no headroom,
# that is the direction which fails green instead of red.
@test "run-bash-coverage.sh ignores python3 -c mentioned inside a comment" {
  cat > "${BATS_TEST_TMPDIR}/commented.sh" <<'FIXTURE'
a=1
# example: python3 -c "import json
b=2
c=3
d=4
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/commented.sh"
  [ "$status" -eq 0 ]
  # Four assignments. The comment is skipped and must not open a skip region.
  [ "$output" -eq 4 ]
}

# Regression: the instrumented set was a filesystem glob, so an untracked
# scratch file under lib/ silently joined the denominator locally while CI,
# which has no such file, measured a different one from the same commit.
@test "run-bash-coverage.sh excludes untracked lib/*.sh from the instrumented set" {
  local _probe="${REPO_ROOT}/lib/zz_bats_probe.sh"
  # Same pre-existence guard as the test-python collision test below: this
  # writes into the real tracked tree, and make lint's recursive SHELL_FILES
  # walk would pick up a leaked probe.
  [ -e "${_probe}" ] && skip "lib/zz_bats_probe.sh already exists; refusing to clobber"
  printf '#!/usr/bin/env bash\nzz=1\n' > "${_probe}"
  run _run_coverage --list-sources
  rm -f "${_probe}"
  [ "$status" -eq 0 ]
  ! printf '%s\n' "${output}" | grep -q 'zz_bats_probe'
}

@test "make test-python runs even when a file named test-python exists" {
  # Regression: test-python was added to the Makefile without being declared in
  # .PHONY, so a colliding filename made make treat it as satisfied and skip the
  # Python suite while `make test` still exited 0.
  local _collide="${REPO_ROOT}/test-python"
  [ -e "${_collide}" ] && skip "a real test-python path exists; refusing to clobber"
  touch "${_collide}"
  local _clean_path
  _clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  run env PATH="${_clean_path}" make -C "${REPO_ROOT}" -n test-python
  rm -f "${_collide}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unittest"* ]]
}

@test "run-bash-coverage.sh --count-coverable exits 2 on a nonexistent file" {
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/does-not-exist.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no such file"* ]]
  # Must not report a count for a file it never read. Assert the output is not a
  # bare integer rather than `!= *"0"` — that glob only means "does not end with
  # 0", which a message like "count: 0 lines" would satisfy.
  ! [[ "$output" =~ ^[0-9]+$ ]]
}

@test "run-bash-coverage.sh --count-coverable exits 2 with no file argument" {
  run _run_coverage --count-coverable
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires a file argument"* ]]
  # Must not fall through into the tracer run.
  [[ "$output" != *"Running"* ]]
  [[ "$output" != *"Overall bash coverage"* ]]
}

@test "run-bash-coverage.sh --count-coverable exits 2 on an unreadable file" {
  local _f="${BATS_TEST_TMPDIR}/unreadable.sh"
  printf '#!/usr/bin/env bash\nx=1\n' > "${_f}"
  chmod 000 "${_f}"
  run _run_coverage --count-coverable "${_f}"
  chmod 644 "${_f}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not readable"* ]]
}

@test "run-bash-coverage.sh -h documents both inspection flags" {
  run _run_coverage -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"--list-sources"* ]]
  [[ "$output" == *"--count-coverable"* ]]
}

# The empty-set guard is the fail-loud mechanism for this script's headline
# defect and shipped unpinned — deleting it produced zero test failures.
# Invoked WITHOUT the mock strip, git is the stub that prints nothing, so the
# tracked set comes back empty: exactly the condition the guard exists for.
@test "run-bash-coverage.sh exits 1 rather than measuring an empty tracked set" {
  run bash "${REPO_ROOT}/scripts/run-bash-coverage.sh" --list-sources
  [ "$status" -eq 1 ]
  [[ "$output" == *"is this a git checkout?"* ]]
}

# git -C only chdirs; an exported GIT_DIR still wins and would make ls-files
# read another repo's index while paths get prefixed with this repo's root — a
# new lib file absent from numerator and denominator, exit 0, plausible count.
@test "run-bash-coverage.sh ignores a leaked GIT_DIR when deriving the set" {
  local _decoy="${BATS_TEST_TMPDIR}/decoy"
  local _clean_path
  _clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  PATH="${_clean_path}" bash -c "
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    mkdir -p '${_decoy}/lib' && cd '${_decoy}'
    git init -q .
    printf 'x=1\n' > lib/only_one.sh
    git add -A && git -c user.email=t@t -c user.name=T commit -qm init
  "
  local _expected _leaked
  _expected="$(_run_coverage --list-sources | wc -l | tr -d ' ')"
  _leaked="$(GIT_DIR="${_decoy}/.git" _run_coverage --list-sources | wc -l | tr -d ' ')"
  [ "${_leaked}" -eq "${_expected}" ]
  ! GIT_DIR="${_decoy}/.git" _run_coverage --list-sources | grep -q 'only_one'
}

@test "run-bash-coverage.sh counts a final line with no trailing newline" {
  printf 'a=1\nb=2\nc=3' > "${BATS_TEST_TMPDIR}/nonewline.sh"
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/nonewline.sh"
  [ "$status" -eq 0 ]
  [ "$output" -eq 3 ]
}

@test "run-bash-coverage.sh ignores python3 -c in a TRAILING comment" {
  printf 'a=1\nb=2  # see python3 -c "import json\nc=3\nd=4\n' > "${BATS_TEST_TMPDIR}/trailing.sh"
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/trailing.sh"
  [ "$status" -eq 0 ]
  [ "$output" -eq 4 ]
}

@test "run-bash-coverage.sh instruments the config files that lib sources" {
  run _run_coverage --list-sources
  [ "$status" -eq 0 ]
  # lib/detect_env.sh sources config/profiles.sh; lib/git_hooks.sh sources
  # config/hook_repos.sh. Both are reached by the suite, so both belong in the
  # denominator — the predicate is "reached by the suite", not "lives in lib/".
  printf '%s\n' "${output}" | grep -qx "${REPO_ROOT}/config/profiles.sh"
  printf '%s\n' "${output}" | grep -qx "${REPO_ROOT}/config/hook_repos.sh"
}

# Regression guard for the predicate widening to scripts/*.sh: every tracked
# script except bash-tracer.sh (excluded below — see the next test) must stay
# instrumented, so a future narrowing of the scripts/*.sh glob is caught here
# rather than silently shrinking the denominator again.
@test "run-bash-coverage.sh instruments every tracked scripts/*.sh except bash-tracer.sh" {
  run _run_coverage --list-sources
  [ "$status" -eq 0 ]

  # Same PATH-strip rationale as the lib/*.sh instrumentation test above: the
  # mocked git prints nothing, which would make this loop vacuously pass.
  local _real_path="${PATH#"${REPO_ROOT}/tests/mocks:"}"
  local _tracked
  _tracked="$(cd "${REPO_ROOT}" && PATH="${_real_path}" git ls-files 'scripts/*.sh')"
  [ -n "${_tracked}" ] || { printf 'git ls-files returned nothing — mock still shadowing\n' >&2; false; }

  local _missing=0 _s
  while IFS= read -r _s; do
    [[ "${_s}" == "scripts/bash-tracer.sh" ]] && continue
    if ! printf '%s\n' "${output}" | grep -qx "${REPO_ROOT}/${_s}"; then
      printf 'not instrumented: %s\n' "${_s}" >&2
      _missing=1
    fi
  done <<< "${_tracked}"
  [ "${_missing}" -eq 0 ]
}

# An extension-keyed pathspec ('scripts/*.sh') cannot match either hook — both
# are extensionless. Widening the predicate to scripts/*.sh must not silently
# drop the two files that gate every commit and push in the repo; they are
# named explicitly in the git ls-files call, not reached by the glob.
@test "run-bash-coverage.sh --list-sources includes both extensionless hooks" {
  run _run_coverage --list-sources
  [ "$status" -eq 0 ]
  printf '%s\n' "${output}" | grep -qx "${REPO_ROOT}/scripts/pre-push"
  printf '%s\n' "${output}" | grep -qx "${REPO_ROOT}/scripts/commit-msg"
}

# bash-tracer.sh is the file BASH_ENV points every traced subprocess at, and
# `set -x` is its own LAST command — its five preceding lines run before
# tracing turns on, and nothing follows it, so zero trace lines are ever
# attributed to it. Verified:
#   _COV_TRACE_FILE=$PWD/tr.txt BASH_ENV=scripts/bash-tracer.sh bash -c 'x=1; y=2'
#   grep -c 'bash-tracer.sh' tr.txt   -> 0
#   wc -l < tr.txt                    -> 2   (the traced subprocess's own
#                                              commands DO appear)
# It is uncoverable by construction, not untested. A future reader must not
# "fix" this back into the instrumented set without re-deriving that.
@test "run-bash-coverage.sh excludes bash-tracer.sh from the instrumented set" {
  run _run_coverage --list-sources
  [ "$status" -eq 0 ]
  ! printf '%s\n' "${output}" | grep -qx "${REPO_ROOT}/scripts/bash-tracer.sh"
}

# bash xtrace emits a multi-line array assignment as ONE line, so its element
# lines can never be covered individually. Counting them inflates the
# denominator the same way the embedded-Python bodies did — 13 of
# config/profiles.sh's 15 counted lines were array elements.
@test "run-bash-coverage.sh does not count multi-line array elements as bash" {
  cat > "${BATS_TEST_TMPDIR}/arr.sh" <<'FIXTURE'
declare -A M=(
  [a]="one"
  [b]="two"
  [c]="three"
)
x=1
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/arr.sh"
  [ "$status" -eq 0 ]
  # The opening declare line is a real command; the three elements and the
  # closing paren are not.
  [ "$output" -eq 2 ]
}

@test "run-bash-coverage.sh still counts an array that closes on one line" {
  printf 'A=()\nb=1\n' > "${BATS_TEST_TMPDIR}/inline_arr.sh"
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/inline_arr.sh"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

# An unterminated region silently swallowed every line after it, RAISING the
# percentage — the fail-green direction against a gate with one point of
# headroom, and nothing would have reported it because the count still looked
# plausible. The two ways to reach it are documented limits of the heuristic.
@test "run-bash-coverage.sh fails loudly on an unterminated python3 -c block" {
  printf '#!/usr/bin/env bash\n_x=$(python3 -c "\nimport json\n' > "${BATS_TEST_TMPDIR}/unterm.sh"
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/unterm.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unterminated python3 -c block"* ]]
  ! [[ "$output" =~ ^[0-9]+$ ]]
}

# Regression: the python3 -c detector had no quote-parity check, unlike the
# heredoc opener detector right above it in the source, which already rejects
# a match whose prefix leaves it inside an odd (still-open) quote. A line
# that merely MENTIONS the pattern `python3 -c "` as a quoted string literal
# — not an actual invocation — matched anyway, opening a false embedded
# region that swallowed every line after it until a line coincidentally
# starting with a bare `"` closed it again. Found by real reproduction, not
# reasoning: this is the exact shape of scripts/run-bash-coverage.sh's own
# `if [[ "${_code}" == *'python3 -c "'* ]]; then` line scanning itself,
# which swallowed 24 of its own real, traced source lines (300-323) as a
# false "unterminated python3 -c block" region — verified with a hand-built
# fixture using the identical construct, isolated from the real file.
@test "run-bash-coverage.sh does not open an embedded python3-c region for a quoted pattern-match string" {
  cat > "${BATS_TEST_TMPDIR}/selfref.sh" <<'FIXTURE'
#!/usr/bin/env bash
a=1
if [[ "${a}" == *'python3 -c "'* ]]; then
  b=2
fi
c=3
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/selfref.sh"
  [ "$status" -eq 0 ]
  # Counted: a=1, the if line itself, b=2, c=3. Not counted: the shebang and
  # the structural fi. Before the fix, the false-open at the if line swallowed
  # b=2, fi, and c=3 to end of file (well past the real closing `"` of the
  # pattern), reporting only 2.
  [ "$output" -eq 4 ]
}

@test "run-bash-coverage.sh fails loudly on an unterminated array literal" {
  printf '#!/usr/bin/env bash\ndeclare -A M=(\n  [a]="one"\n' > "${BATS_TEST_TMPDIR}/untermarr.sh"
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/untermarr.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unterminated array literal"* ]]
}

@test "run-bash-coverage.sh --list-sources includes the setup_env.sh entry point" {
  run _run_coverage --list-sources
  [ "$status" -eq 0 ]
  printf '%s\n' "${output}" | grep -qx "${REPO_ROOT}/setup_env.sh"
}

# Regression: heredoc bodies and their terminator line were counted as coverable,
# but xtrace never emits either — only the opener line, verified with
# PS4='T:${LINENO}: '. scripts/sync-agent-guidance.sh has 64 of its 99 "coverable"
# lines inside a single heredoc, capping its true coverage at 38%.
@test "run-bash-coverage.sh does not count a heredoc body or its terminator" {
  cat > "${BATS_TEST_TMPDIR}/heredoc.sh" <<'FIXTURE'
#!/usr/bin/env bash
a=1
cat <<'EOF2'
body line one
body line two
EOF2
b=2
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/heredoc.sh"
  [ "$status" -eq 0 ]
  # Counted: a=1, the cat <<'EOF2' opener, b=2. Not counted: the shebang comment,
  # the two body lines, and the EOF2 terminator.
  [ "$output" -eq 3 ]
}

@test "run-bash-coverage.sh still counts an unquoted <<DELIM heredoc opener" {
  cat > "${BATS_TEST_TMPDIR}/unquoted.sh" <<'FIXTURE'
#!/usr/bin/env bash
cat <<DELIM
body
DELIM
x=1
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/unquoted.sh"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

# Boundary: a here-string (<<<) is a single-line redirect with no body or
# terminator — not a heredoc. Its trailing < would otherwise be misread as the
# tail of a truncated << match (delimiter "foo"), which would treat every
# following line as an unterminated heredoc body.
@test "run-bash-coverage.sh does not treat a here-string (<<<) as a heredoc opener" {
  cat > "${BATS_TEST_TMPDIR}/herestring.sh" <<'FIXTURE'
#!/usr/bin/env bash
read -r x <<< foo
after=1
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/herestring.sh"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

# Boundary: a << appearing inside an already-open quoted string is not a real
# heredoc operator — bash parses it as literal text, so the line traces normally
# and no body/terminator search should ever start.
@test "run-bash-coverage.sh does not treat << inside a quoted string as a heredoc opener" {
  cat > "${BATS_TEST_TMPDIR}/quotedstring.sh" <<'FIXTURE'
#!/usr/bin/env bash
msg='See <<EOF for docs'
after=1
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/quotedstring.sh"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

# Boundary: zero body lines between opener and terminator.
@test "run-bash-coverage.sh handles an empty heredoc body" {
  cat > "${BATS_TEST_TMPDIR}/empty.sh" <<'FIXTURE'
#!/usr/bin/env bash
cat <<'EMPTY'
EMPTY
after=1
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/empty.sh"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

# Boundary: heredoc opened as the last real content of the file, no terminator
# ever appears. Silently swallowing the rest (there is no rest) must still be
# reported as a loud failure, matching the python3-c/array-literal error paths.
@test "run-bash-coverage.sh fails loudly on an unterminated heredoc" {
  printf '#!/usr/bin/env bash\ncat <<'"'"'EOF'"'"'\nfoo\n' > "${BATS_TEST_TMPDIR}/untermhd.sh"
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/untermhd.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unterminated heredoc"* ]]
  ! [[ "$output" =~ ^[0-9]+$ ]]
}

# Regression: a synthetic single-process fixture (bash -x -c 'source f; f')
# suggested a function-declaration header line is never traced, and the
# heuristic excluded it on that basis. A real tracer pass over the bats
# suite contradicted that at scale — 150 of 189 measured heuristic
# disagreements were function-declaration lines the trace actually emitted
# (e.g. lib/detect_env.sh:4 `detect_env() {`, traced twice). Under BASH_ENV
# with xtrace already active — how the real tracer runs, not how the
# synthetic fixture ran it — defining a function IS a traced command. The
# exclusion is removed entirely rather than narrowed: trust the measured
# fleet data over one fixture. Header lines now count same as any other code.
@test "run-bash-coverage.sh counts function-declaration header lines" {
  cat > "${BATS_TEST_TMPDIR}/funcdecl.sh" <<'FIXTURE'
#!/usr/bin/env bash
f()
{
  x=1
}
g ()  {
  y=2
}
f
g
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/funcdecl.sh"
  [ "$status" -eq 0 ]
  # Counted: f()'s own header line, x=1, g ()  {'s header line, y=2, the call
  # to f, the call to g. Not counted: the shebang and the bare structural
  # lines ({ on its own line, both closing }).
  [ "$output" -eq 6 ]
}

# A single-line function (body on the same physical line as the header) DOES get
# traced when called, attributed to that line — must still count.
@test "run-bash-coverage.sh still counts a single-line function body" {
  cat > "${BATS_TEST_TMPDIR}/singleline.sh" <<'FIXTURE'
#!/usr/bin/env bash
greet() { echo "hi"; }
greet
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/singleline.sh"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

# Regression: the existing _case_label_re only matched a single token with no
# spaces and no leading hyphen, so a hyphen-leading or multi-token-with-spaces
# label like `-h | --help)` fell through and was counted, even though xtrace
# never emits a case-arm label line.
@test "run-bash-coverage.sh does not count a hyphen-leading multi-token case label" {
  cat > "${BATS_TEST_TMPDIR}/hyphenlabel.sh" <<'FIXTURE'
#!/usr/bin/env bash
case "$1" in
  -h | --help)
    echo "help"
    ;;
esac
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/hyphenlabel.sh"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

# An empty-body case arm (label immediately followed by ;; on the SAME line, no
# real command) is never traced either — verified with PS4='T:${LINENO}: '.
@test "run-bash-coverage.sh does not count an empty-body case arm with trailing ;;" {
  cat > "${BATS_TEST_TMPDIR}/emptyarm.sh" <<'FIXTURE'
#!/usr/bin/env bash
case "$1" in
  sync | check) ;;
  *)
    run_default
    ;;
esac
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/emptyarm.sh"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

# Regression guard: a case-arm label followed by a REAL command before the
# trailing ;;, all on one line, DOES get traced (attributed to that line) — the
# empty-body exclusion above must not swallow this shape.
@test "run-bash-coverage.sh still counts a case arm with a same-line command" {
  cat > "${BATS_TEST_TMPDIR}/samelinecmd.sh" <<'FIXTURE'
#!/usr/bin/env bash
case "$1" in
  -h | --help) echo "help" ;;
  *) echo "default" ;;
esac
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/samelinecmd.sh"
  [ "$status" -eq 0 ]
  [ "$output" -eq 3 ]
}

# The motivating regression, combining a function declaration with a heredoc
# body inside it — the exact shape that made scripts/sync-agent-guidance.sh's
# true coverage unreachable at its published percentage.
@test "run-bash-coverage.sh correctly counts a heredoc nested inside a function" {
  cat > "${BATS_TEST_TMPDIR}/nested.sh" <<'FIXTURE'
#!/usr/bin/env bash
f() {
  cat <<'USAGE'
a
b
c
USAGE
}
f
x=1
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/nested.sh"
  [ "$status" -eq 0 ]
  # Counted: f() {'s own header line (function declarations count — see the
  # test above), the cat <<'USAGE' opener, the call to f, x=1.
  [ "$output" -eq 4 ]
}

# ── line continuation ────────────────────────────────────────────────────────
# Regression: a backslash-newline splices the next physical line onto the same
# logical command — xtrace only ever emits the FIRST physical line, verified
# with PS4='T:${LINENO}: '. Counting the continuation lines as separate
# coverable bash inflates the denominator the same way multi-line arrays and
# python3 -c bodies do. This exact fixture counted 11 before the fix; real
# xtrace over it emits only 8 distinct line numbers (2 3 4 8 9 11 14 15) — 9
# coverable lines once you count the untaken `else` branch (line 6, genuinely
# coverable, just not hit by this one run).
@test "run-bash-coverage.sh does not count backslash line-continuation lines as bash" {
  cat > "${BATS_TEST_TMPDIR}/cont.sh" <<'FIXTURE'
#!/usr/bin/env bash
x=1
if [[ -n "${x}" ]]; then
  y=2
else
  y=3
fi
for i in 1 2; do
  z="${i}"
done
printf '%s\n' \
  "a" \
  "b"
case "${x}" in
  1) w=1 ;;
esac
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/cont.sh"
  [ "$status" -eq 0 ]
  [ "$output" -eq 9 ]
}

# Boundary: the continuation opener itself is real code and must still count;
# only the SWALLOWED lines ("a" and "b") are excluded.
@test "run-bash-coverage.sh still counts the opener line of a continuation" {
  cat > "${BATS_TEST_TMPDIR}/opener.sh" <<'FIXTURE'
#!/usr/bin/env bash
printf '%s\n' \
  "a" \
  "b"
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/opener.sh"
  [ "$status" -eq 0 ]
  # Only the printf opener is real bash; "a" and "b" are spliced onto it.
  [ "$output" -eq 1 ]
}

# Boundary: a backslash as the true last character of the FILE, with no
# following physical line to splice onto. Nothing is silently swallowed (there
# is nothing left to swallow) so this must not crash, hang, or report an
# unterminated-region error — unlike heredoc/array/python3, a continuation can
# only ever consume ONE further line at a time, never "to EOF".
@test "run-bash-coverage.sh handles a trailing backslash at end of file with no following line" {
  printf '#!/usr/bin/env bash\na=1\nb=2 \\\n' > "${BATS_TEST_TMPDIR}/eofcont.sh"
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/eofcont.sh"
  [ "$status" -eq 0 ]
  # a=1 and the b=2 \ line itself (the opener, nothing follows to swallow).
  [ "$output" -eq 2 ]
}

# Boundary: a continuation inside an ALREADY-excluded heredoc body must not be
# double-processed by the continuation logic — the heredoc-body skip runs
# first and swallows the whole body regardless of what it contains, verified
# against real bash (the body line's trailing backslash has no effect at all;
# the heredoc terminator ends the region normally).
@test "run-bash-coverage.sh does not apply continuation logic inside a heredoc body" {
  cat > "${BATS_TEST_TMPDIR}/hdcont.sh" <<'FIXTURE'
#!/usr/bin/env bash
a=1
cat <<'EOF2'
some text \
more text
EOF2
b=2
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/hdcont.sh"
  [ "$status" -eq 0 ]
  # a=1, the cat <<'EOF2' opener, b=2. The heredoc body's embedded backslash
  # must not exclude anything past the real EOF2 terminator.
  [ "$output" -eq 3 ]
}

# Boundary: a line ending in TWO backslashes is an escaped (literal) backslash
# character, not a continuation — the pair cancels out and the real newline
# terminates the statement normally. Verified against real bash: `echo "foo" \\`
# traces on its own line, and the following line traces separately too.
@test "run-bash-coverage.sh does not treat a trailing escaped backslash (\\\\\\\\) as a continuation" {
  cat > "${BATS_TEST_TMPDIR}/twobs.sh" <<'FIXTURE'
#!/usr/bin/env bash
a=1
echo "foo" \\
b=2
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/twobs.sh"
  [ "$status" -eq 0 ]
  # All three are real, independent bash lines — nothing is spliced.
  [ "$output" -eq 3 ]
}

# Boundary: a continuation whose next physical line is blank ends the
# continuation there (nothing left to splice) rather than chaining further —
# verified against real bash, which traces the statement AFTER the blank line
# separately, not as part of the continued one.
@test "run-bash-coverage.sh ends a continuation at a blank next line" {
  printf '#!/usr/bin/env bash\na=1 \\\n\nb=2\n' > "${BATS_TEST_TMPDIR}/blankcont.sh"
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/blankcont.sh"
  [ "$status" -eq 0 ]
  # a=1 (the opener) and b=2 (a fresh statement after the blank line).
  [ "$output" -eq 2 ]
}

# Boundary: a continuation whose next physical line is a comment. Real bash
# splices the comment onto the same logical line, where the `#` starts a
# comment that consumes the rest of that (still single) statement — so the
# comment's own trailing content is inert and does NOT chain the continuation
# further, verified against real bash tracing only the opener.
@test "run-bash-coverage.sh ends a continuation at a comment next line" {
  printf '#!/usr/bin/env bash\na=1 \\\n# comment\nb=2\n' > "${BATS_TEST_TMPDIR}/commentcont.sh"
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/commentcont.sh"
  [ "$status" -eq 0 ]
  # a=1 (the opener) and b=2 (a fresh statement after the comment).
  [ "$output" -eq 2 ]
}

# Regression: a continuation-swallowed line is not always inert. A line that
# merely continues an ARGUMENT LIST (more words in the same one command) is
# never separately traced — but a swallowed line that itself begins or
# contains a new top-level command (a `||`/`&&`/`|`/`;` compound-list
# operator) IS traced, on its own line number. The original fix excluded
# every swallowed line unconditionally, which silently dropped this case
# below what the tracer actually emits — the exact failure mode the
# covered-vs-coverable invariant exists to catch, verified here directly
# since --count-coverable never runs the real tracer to trigger it. Real
# xtrace over this fixture emits 5 distinct line numbers (2 3 5 8 9), verified
# with PS4='T:${LINENO}: '.
@test "run-bash-coverage.sh still counts a continuation line that starts a new command with ||" {
  cat > "${BATS_TEST_TMPDIR}/cmdcont.sh" <<'FIXTURE'
#!/usr/bin/env bash
x=1
[[ -n "${x}" ]] || \
  [[ -z "${x}" ]]
printf '%s\n' \
  "a" \
  "b"
curl -s "http://example" \
  -H "X: y" || true
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/cmdcont.sh"
  [ "$status" -eq 0 ]
  # x=1, the [[ ... ]] || \ opener, the swallowed [[ -z ]] line (has ||, kept),
  # the printf opener ("a"/"b" are pure arguments, excluded), the curl opener
  # ("-H ... || true" has ||, kept).
  [ "$output" -eq 5 ]
}

# Sibling boundary case: a swallowed line with NO command separator at all —
# purely more words in the same one command — must still be excluded. Without
# this counter-test, a fix for the case above that over-corrects into keeping
# every swallowed line would pass silently.
@test "run-bash-coverage.sh still excludes a pure-argument continuation line with no separator" {
  cat > "${BATS_TEST_TMPDIR}/pureargcont.sh" <<'FIXTURE'
#!/usr/bin/env bash
curl --max-time 5 --silent --fail \
  -H "Authorization: Bearer ${TOKEN}" \
  https://api.example.com/user > /dev/null 2>&1 || rc=$?
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/pureargcont.sh"
  [ "$status" -eq 0 ]
  # The curl opener, and the final line (has ||, kept). The -H flag line is a
  # pure argument continuation with no separator — excluded.
  [ "$output" -eq 2 ]
}

# Regression, found by real reproduction against the production tracer (not
# reasoning): for a `var=$(cmd ...)` assignment whose command substitution
# spans a backslash continuation, bash attributes the WHOLE assignment's
# xtrace line to wherever the substitution's closing `)` lands — the LAST
# physical line — not the opener. Verified with
# BASH_ENV=scripts/bash-tracer.sh against `_x=$(comm -13 "a" \` + `  "b")`:
# the trace names only the closing line, never the opener. The exact shape
# was lib/update_summary.sh:655-656 (`_untracked_formulae=$(comm -13 ... \` /
# `    "...")`) — misdiagnosed as a case-label over-match in the original
# report; the real mechanism is this continuation-closing-paren attribution,
# and _case_label_re does not even match a line starting with `"`. A
# continuation line with no `||`/`&&`/`|`/`;` that ends in a bare `)` now
# falls through and counts, same as a `_cmd_sep_re` match does. This is
# deliberately over-inclusive for a plain (non-assignment) command whose
# continuation closes with `$(...)` — real xtrace still attributes those to
# the opener, so the closing line is counted despite no test ever reaching
# it — the same accepted, conservative direction as every other heuristic
# edge case here: it only ever lowers the reported percentage.
@test "run-bash-coverage.sh still counts a continuation line that closes a command substitution" {
  cat > "${BATS_TEST_TMPDIR}/assigncont.sh" <<'FIXTURE'
#!/usr/bin/env bash
a=1
result=$(comm -13 "a" \
    "b")
echo "${result}"
FIXTURE
  run _run_coverage --count-coverable "${BATS_TEST_TMPDIR}/assigncont.sh"
  [ "$status" -eq 0 ]
  # a=1, the result=$(comm -13 "a" \ opener, the "b") closing line (real
  # xtrace attributes the whole assignment here), the echo call.
  [ "$output" -eq 4 ]
}

# ── --file-coverage: union the trace into the denominator ──────────────────
#
# The static heuristic in _count_coverable_lines can be wrong in the
# under-inclusive direction: a body line of a multi-line array literal is
# excluded because xtrace emits the whole array assignment as one line at
# the opener — but a hand-built trace naming that body line anyway must
# still be unioned into the denominator rather than silently dropped, and
# reported as a disagreement so a systematically wrong exclusion stays
# visible instead of being quietly absorbed into a higher denominator. This
# used a function-declaration header line as the excluded-but-traced example
# until that exclusion rule was removed (see the function-declaration tests
# above) — an array-literal body line demonstrates the same union mechanism
# and remains genuinely excluded.
@test "run-bash-coverage.sh --file-coverage unions a traced line the heuristic excluded, and reports it as a disagreement" {
  cat > "${BATS_TEST_TMPDIR}/arrbug.sh" <<'FIXTURE'
#!/usr/bin/env bash
arr=(
  a
)
echo "${arr[@]}"
FIXTURE
  # Heuristic-coverable for this fixture is lines 2 and 5 (the arr=( opener,
  # the echo call) — line 3 ("  a") and line 4 (")") are excluded as array
  # body/close. Hand-write a trace that (wrongly, from the heuristic's view)
  # also names line 3.
  {
    printf '%s:2\n' "${BATS_TEST_TMPDIR}/arrbug.sh"
    printf '%s:3\n' "${BATS_TEST_TMPDIR}/arrbug.sh"
    printf '%s:5\n' "${BATS_TEST_TMPDIR}/arrbug.sh"
  } > "${BATS_TEST_TMPDIR}/arrbug_trace.txt"

  run _run_coverage --file-coverage "${BATS_TEST_TMPDIR}/arrbug.sh" "${BATS_TEST_TMPDIR}/arrbug_trace.txt"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  # covered: 3 distinct traced lines (2, 3, 5).
  [ "${lines[0]}" = "3" ]
  # coverable: union of heuristic [2, 5] and traced [2, 3, 5] is [2, 3, 5] = 3
  # — NOT the heuristic's own 2, which is what would still fail the
  # covered-can-never-exceed-coverable invariant.
  [ "${lines[1]}" = "3" ]
  # disagreement: the only line the heuristic excluded but the trace emitted.
  [ "${lines[2]}" = "3" ]
}

# Sibling boundary case: when the trace agrees with the heuristic exactly,
# the union adds nothing and there are zero disagreements — without this
# counter-test, a union that always pads the denominator (e.g. adding the
# traced count unconditionally) would pass the test above just as well.
@test "run-bash-coverage.sh --file-coverage reports no disagreement when the trace matches the heuristic" {
  cat > "${BATS_TEST_TMPDIR}/clean.sh" <<'FIXTURE'
#!/usr/bin/env bash
a=1
b=2
FIXTURE
  {
    printf '%s:2\n' "${BATS_TEST_TMPDIR}/clean.sh"
    printf '%s:3\n' "${BATS_TEST_TMPDIR}/clean.sh"
  } > "${BATS_TEST_TMPDIR}/clean_trace.txt"

  run _run_coverage --file-coverage "${BATS_TEST_TMPDIR}/clean.sh" "${BATS_TEST_TMPDIR}/clean_trace.txt"
  [ "$status" -eq 0 ]
  # Exactly covered + coverable — no third (disagreement) line at all.
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "2" ]
  [ "${lines[1]}" = "2" ]
}

# Boundary: a trace file with zero lines for this source (e.g. an
# instrumented file no test happens to exercise). covered must be 0, not
# blow up on an empty traced-lines set, and coverable must fall back to
# exactly the heuristic's own count — the union of a set and the empty set
# is the set itself.
@test "run-bash-coverage.sh --file-coverage handles a trace file with no lines for this source" {
  cat > "${BATS_TEST_TMPDIR}/untraced.sh" <<'FIXTURE'
#!/usr/bin/env bash
a=1
b=2
FIXTURE
  printf '%s/other.sh:1\n' "${BATS_TEST_TMPDIR}" > "${BATS_TEST_TMPDIR}/other_trace.txt"

  run _run_coverage --file-coverage "${BATS_TEST_TMPDIR}/untraced.sh" "${BATS_TEST_TMPDIR}/other_trace.txt"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "0" ]
  [ "${lines[1]}" = "2" ]
}

@test "run-bash-coverage.sh --file-coverage exits 2 with fewer than two arguments" {
  run _run_coverage --file-coverage "${BATS_TEST_TMPDIR}/clean.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--file-coverage"* ]]
}

@test "run-bash-coverage.sh --file-coverage exits 2 on a nonexistent source file" {
  printf '%s:1\n' "${BATS_TEST_TMPDIR}/nope.sh" > "${BATS_TEST_TMPDIR}/some_trace.txt"
  run _run_coverage --file-coverage "${BATS_TEST_TMPDIR}/nope.sh" "${BATS_TEST_TMPDIR}/some_trace.txt"
  [ "$status" -eq 2 ]
}

@test "run-bash-coverage.sh --file-coverage exits 2 on a nonexistent trace file" {
  cat > "${BATS_TEST_TMPDIR}/onlysrc.sh" <<'FIXTURE'
#!/usr/bin/env bash
a=1
FIXTURE
  run _run_coverage --file-coverage "${BATS_TEST_TMPDIR}/onlysrc.sh" "${BATS_TEST_TMPDIR}/no_such_trace.txt"
  [ "$status" -eq 2 ]
}

# _file_coverage_report calls _count_coverable_lines first and returns 1
# without ever reading the trace file when the heuristic itself can't compute
# a denominator (same unterminated python3 -c fixture --count-coverable is
# tested against above). --file-coverage's own error path for that failure
# had no test even though its --count-coverable twin does.
@test "run-bash-coverage.sh --file-coverage exits 1 when the heuristic cannot compute a denominator" {
  printf '#!/usr/bin/env bash\n_x=$(python3 -c "\nimport json\n' > "${BATS_TEST_TMPDIR}/unterm.sh"
  : > "${BATS_TEST_TMPDIR}/empty_trace.txt"

  run _run_coverage --file-coverage "${BATS_TEST_TMPDIR}/unterm.sh" "${BATS_TEST_TMPDIR}/empty_trace.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot compute a trustworthy denominator"* ]]
}

# Regression: the disagreement computation fed comm -23 two `sort -un`
# (numeric-sorted) streams, but comm requires its inputs sorted in the
# shell's own collating order — what plain `sort -u` produces — not numeric
# order. For multi-digit line numbers the two diverge: "9" sorts before "10"
# numerically but after it lexicographically ('9' > '1'). comm does not
# error on the mismatch; it silently desyncs partway through its merge walk
# and reports a line as "excluded but traced" even when that line is present
# in both streams. A fixture confined to single-digit line numbers can never
# expose this — the traced set here deliberately spans the 9/10 boundary.
@test "run-bash-coverage.sh --file-coverage does not report a false disagreement across a digit-length boundary" {
  cat > "${BATS_TEST_TMPDIR}/digitcross.sh" <<'FIXTURE'
#!/usr/bin/env bash
a=1
b=2
c=3
d=4
e=5
f=6
g=7
h=8
i=9
j=10
k=11
FIXTURE
  # Lines 2-12 are all heuristic-coverable (every assignment counts). The
  # traced subset (2, 3, 10, 11) is entirely within that set, so a correct
  # disagreement report is empty.
  {
    printf '%s:2\n' "${BATS_TEST_TMPDIR}/digitcross.sh"
    printf '%s:3\n' "${BATS_TEST_TMPDIR}/digitcross.sh"
    printf '%s:10\n' "${BATS_TEST_TMPDIR}/digitcross.sh"
    printf '%s:11\n' "${BATS_TEST_TMPDIR}/digitcross.sh"
  } > "${BATS_TEST_TMPDIR}/digitcross_trace.txt"

  run _run_coverage --file-coverage "${BATS_TEST_TMPDIR}/digitcross.sh" "${BATS_TEST_TMPDIR}/digitcross_trace.txt"
  [ "$status" -eq 0 ]
  # covered=4, coverable=11 (union adds nothing — traced is a subset of the
  # heuristic) — and no third (disagreement) line at all.
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "4" ]
  [ "${lines[1]}" = "11" ]
}

# The reconciliation invariant `_count_coverable_lines`'s two modes must
# hold: "lines" mode emits exactly the set "count" mode counts. There is no
# direct CLI hook onto lines-mode's raw output, so this derives the emission
# count indirectly via --file-coverage against a trace with zero lines for
# the source: the union of the heuristic and an empty traced set is the
# heuristic itself, so --file-coverage's reported "coverable" (its 2nd
# output line) is then exactly the count "lines" mode emitted — which must
# equal --count-coverable's own total for the same file.
@test "run-bash-coverage.sh lines-mode emission count reconciles with count-mode's total, per file" {
  : > "${BATS_TEST_TMPDIR}/empty_trace.txt"
  for _f in lib/git_sync.sh lib/package_capture.sh scripts/bootstrap_mac.sh scripts/pre-push lib/helpers.sh; do
    run _run_coverage --count-coverable "${REPO_ROOT}/${_f}"
    [ "$status" -eq 0 ]
    _count_total="$output"

    run _run_coverage --file-coverage "${REPO_ROOT}/${_f}" "${BATS_TEST_TMPDIR}/empty_trace.txt"
    [ "$status" -eq 0 ]
    _coverable_via_lines="${lines[1]}"

    [ "${_count_total}" = "${_coverable_via_lines}" ]
  done
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
