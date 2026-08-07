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
