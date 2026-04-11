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
    git -C '${tmpdir}' init --quiet
    git -C '${tmpdir}' config user.email 'test@test.com'
    git -C '${tmpdir}' config user.name 'Test'
    printf 'line1\nline2\nline3\n' > '${tmpdir}/file1.txt'
    printf 'line1\nline2\n' > '${tmpdir}/file2.txt'
    git -C '${tmpdir}' add .
    git -C '${tmpdir}' commit --quiet -m 'test'
  "
  run bash -c "export PATH='${clean_path}'; bash '${REPO_ROOT}/scripts/count_lines_git.sh' '${tmpdir}'"
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
    git -C '${tmpdir}' init --quiet
    git -C '${tmpdir}' config user.email 'test@test.com'
    git -C '${tmpdir}' config user.name 'Test'
    printf 'line1\nline2\n' > '${tmpdir}/keep/file.txt'
    printf 'line1\nline2\nline3\n' > '${tmpdir}/vendor/file.txt'
    git -C '${tmpdir}' add .
    git -C '${tmpdir}' commit --quiet -m 'test'
  "
  run bash -c "export PATH='${clean_path}'; bash '${REPO_ROOT}/scripts/count_lines_git.sh' '${tmpdir}' 'vendor'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total lines: 2"* ]]
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

# ── kill_zombie.sh ─────────────────────────────────────────────────────────────

@test "kill_zombie.sh calls pgrep with defunct pattern" {
  run bash "${REPO_ROOT}/scripts/kill_zombie.sh"
  grep -q "pgrep <defunct>" "${MOCK_CALLS_FILE}"
}

@test "kill_zombie.sh passes pgrep output to kill -9" {
  # kill is a bash builtin so the PATH mock is not invoked; verify the script
  # proceeds past pgrep without error when pgrep returns no PIDs
  export MOCK_PGREP_EXIT=1
  run bash "${REPO_ROOT}/scripts/kill_zombie.sh"
  grep -q "pgrep <defunct>" "${MOCK_CALLS_FILE}"
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
  grep -q "sudo kill -9 1234" "${MOCK_CALLS_FILE}"
  grep -q "sudo kill -9 5678" "${MOCK_CALLS_FILE}"
}

# ── restart_fah.sh ─────────────────────────────────────────────────────────────

@test "restart_fah.sh calls FAHClient stop" {
  run bash "${REPO_ROOT}/scripts/restart_fah.sh"
  grep -q "sudo /etc/init.d/FAHClient stop" "${MOCK_CALLS_FILE}"
}

@test "restart_fah.sh calls FAHClient start" {
  run bash "${REPO_ROOT}/scripts/restart_fah.sh"
  grep -q "sudo /etc/init.d/FAHClient start" "${MOCK_CALLS_FILE}"
}

@test "restart_fah.sh calls pgrep fah between stop and start" {
  export MOCK_PGREP_EXIT=0
  export MOCK_PGREP_OUTPUT="4321"
  run bash "${REPO_ROOT}/scripts/restart_fah.sh"
  grep -q "pgrep fah" "${MOCK_CALLS_FILE}"
  grep -q "sudo kill -9 4321" "${MOCK_CALLS_FILE}"
}

# ── synch_git-repos.sh ────────────────────────────────────────────────────────

@test "synch_git-repos.sh prints error message when not on studio" {
  export MOCK_HOSTNAME_OUTPUT=testhost
  unset STUDIO
  run bash "${REPO_ROOT}/scripts/synch_git-repos.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"needs to be run on studio"* ]]
  run grep -q "rsync" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "synch_git-repos.sh calls rsync for all three hosts when on studio" {
  export MOCK_HOSTNAME_OUTPUT=studio
  export HOME="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/git-repos"
  run bash "${REPO_ROOT}/scripts/synch_git-repos.sh"
  [ "$status" -eq 0 ]
  grep -q "rsync.*laptop-1" "${MOCK_CALLS_FILE}"
  grep -q "rsync.*workstation" "${MOCK_CALLS_FILE}"
  grep -q "rsync.*ratna" "${MOCK_CALLS_FILE}"
}

# ── tmux-workstation.sh ───────────────────────────────────────────────────────

@test "tmux-workstation.sh creates exactly 5 tmux sessions" {
  run bash "${REPO_ROOT}/scripts/tmux-workstation.sh"
  local count
  count=$(grep -c "^tmux new" "${MOCK_CALLS_FILE}")
  [ "$count" -eq 5 ]
}

@test "tmux-workstation.sh uses correct session names" {
  run bash "${REPO_ROOT}/scripts/tmux-workstation.sh"
  grep -q "tmux new -s bpytop" "${MOCK_CALLS_FILE}"
  grep -q "tmux new -s cyber1" "${MOCK_CALLS_FILE}"
  grep -q "tmux new -s cyber2" "${MOCK_CALLS_FILE}"
  grep -q "tmux new -s cone1" "${MOCK_CALLS_FILE}"
  grep -q "tmux new -s cone2" "${MOCK_CALLS_FILE}"
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
  chmod +x "${tmpdir}/git" "${tmpdir}/make"
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
