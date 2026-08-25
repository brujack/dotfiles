#!/usr/bin/env bats
#
# `run !` (negated run) needs bats >= 1.5.0. Declared rather than assumed:
# without it bats only warns, and on an older bats the negation would be
# mis-parsed silently -- tdd.md pitfall G, where the local toolchain cannot
# express the failure. CI installs 1.10.0 via apt; this box has 1.14.0.
bats_require_minimum_version 1.5.0

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/cadence-notify.sh"
  export _RHN_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  NAME="renovate-held"
  export _RHN_NTFY_LOG="${BATS_TEST_TMPDIR}/ntfy.log"
  export NTFY_URL="https://ntfy.invalid/test"
  # every ntfy send is captured, never sent
  export _RHN_CURL_BIN="${BATS_TEST_TMPDIR}/fake-curl"
  cat > "${_RHN_CURL_BIN}" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${_RHN_NTFY_LOG}"
EOF
  chmod +x "${_RHN_CURL_BIN}"
}

_detector() {  # $1 = exit code, $2... = stdout lines
  local _rc="$1"; shift
  local _d="${BATS_TEST_TMPDIR}/detector"
  { printf '#!/usr/bin/env bash\n'
    for _l in "$@"; do printf 'printf "%%s\\n" %q\n' "${_l}"; done
    printf 'exit %s\n' "${_rc}"; } > "${_d}"
  chmod +x "${_d}"
  export _RHN_DETECTOR="${_d}"
}

@test "exit 0 with nothing held sends no notification and still writes the heartbeat" {
  _detector 0
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 0 ]
  [ ! -s "${_RHN_NTFY_LOG}" ]
  [ -f "${_RHN_STATE_DIR}/${NAME}/last-run.json" ]
  command grep -q '"result": *"clean"' "${_RHN_STATE_DIR}/${NAME}/last-run.json"
}

@test "exit 1 with held PRs notifies and names each finding" {
  _detector 1 'math#118  6d  major  update actions/checkout to v7' \
               'dotfiles#241  6d  major  update actions/checkout to v7'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 1 ]
  [ -s "${_RHN_NTFY_LOG}" ]
  command grep -q 'math#118' "${_RHN_NTFY_LOG}"
  command grep -q 'dotfiles#241' "${_RHN_NTFY_LOG}"
  command grep -q '"result": *"held"' "${_RHN_STATE_DIR}/${NAME}/last-run.json"
}

@test "exit 2 is reported as incomplete, never as clean" {
  _detector 2
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 2 ]
  [ -s "${_RHN_NTFY_LOG}" ]
  command grep -qi 'incomplete\|cannot determine' "${_RHN_NTFY_LOG}"
  command grep -q '"result": *"incomplete"' "${_RHN_STATE_DIR}/${NAME}/last-run.json"
  run ! command grep -q '"result": *"clean"' "${_RHN_STATE_DIR}/${NAME}/last-run.json"
}

@test "exit 2 with findings still surfaces them — incomplete dominates held" {
  _detector 2 'math#118  6d  major  update actions/checkout to v7'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 2 ]
  command grep -q 'math#118' "${_RHN_NTFY_LOG}"
  command grep -qi 'incomplete\|cannot determine' "${_RHN_NTFY_LOG}"
}

@test "a missing detector is incomplete, not clean" {
  export _RHN_DETECTOR="${BATS_TEST_TMPDIR}/does-not-exist"
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 2 ]
  command grep -q '"result": *"incomplete"' "${_RHN_STATE_DIR}/${NAME}/last-run.json"
}

@test "an unset NTFY_URL degrades delivery but never the exit code" {
  unset NTFY_URL
  _detector 1 'math#118  6d  major  x'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"NTFY_URL"* ]]
  command grep -q '"result": *"held"' "${_RHN_STATE_DIR}/${NAME}/last-run.json"
}

@test "an unexpected detector exit code is incomplete, not clean" {
  _detector 7
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 2 ]
  command grep -q '"result": *"incomplete"' "${_RHN_STATE_DIR}/${NAME}/last-run.json"
}

@test "running twice leaves one heartbeat, refreshed" {
  _detector 0
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"; [ "$status" -eq 0 ]
  local _first; _first=$(command grep -o '"ts": *"[^"]*"' "${_RHN_STATE_DIR}/${NAME}/last-run.json")
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"; [ "$status" -eq 0 ]
  [ "$(find "${_RHN_STATE_DIR}" -name 'last-run.json' | wc -l | tr -d ' ')" -eq 1 ]
  [ -n "${_first}" ]
}

@test "a failing ntfy delivery is reported but never changes the exit code" {
  cat > "${_RHN_CURL_BIN}" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
  chmod +x "${_RHN_CURL_BIN}"
  _detector 1 'math#118  6d  major  x'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"delivery failed"* ]]
  command grep -q '"result": *"held"' "${_RHN_STATE_DIR}/${NAME}/last-run.json"
}

@test "a failing ntfy delivery on the incomplete path still exits 2" {
  cat > "${_RHN_CURL_BIN}" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
  chmod +x "${_RHN_CURL_BIN}"
  _detector 2
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 2 ]
  command grep -q '"result": *"incomplete"' "${_RHN_STATE_DIR}/${NAME}/last-run.json"
}

@test "the detector runs with NTFY_URL scrubbed so it cannot deliver its own alert" {
  # ledger_drift_check.sh makes its own ntfy call. If the wrapper let NTFY_URL
  # through, that push would duplicate the wrapper's AND keep the failure mode
  # where detection and delivery fail together.
  local _d="${BATS_TEST_TMPDIR}/leaky-detector"
  cat > "${_d}" <<'EOF'
#!/usr/bin/env bash
printf 'NTFY_URL_SEEN=[%s]\n' "${NTFY_URL:-}"
exit 1
EOF
  chmod +x "${_d}"
  export _RHN_DETECTOR="${_d}"
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 1 ]
  command grep -q 'NTFY_URL_SEEN=\[\]' "${_RHN_NTFY_LOG}"
  run ! command grep -q 'NTFY_URL_SEEN=\[https' "${_RHN_NTFY_LOG}"
}

@test "two cadences keep separate heartbeats" {
  _detector 0
  run bash "${SCRIPT}" renovate-held "${_RHN_DETECTOR}"; [ "$status" -eq 0 ]
  _detector 1 'state-ledger drift: 3 stale'
  run bash "${SCRIPT}" ledger-drift "${_RHN_DETECTOR}"; [ "$status" -eq 1 ]
  command grep -q '"result": *"clean"' "${_RHN_STATE_DIR}/renovate-held/last-run.json"
  command grep -q '"result": *"held"'  "${_RHN_STATE_DIR}/ledger-drift/last-run.json"
}

@test "the ntfy call uses --data-raw, never -d" {
  # curl's -d OPENS A FILE when the argument starts with '@', so -d on an
  # unvalidated string is a latent local-file-read that POSTs the contents.
  # Verified against curl's parser: -d @/nonexistent errors "encountered when
  # reading a file"; --data-raw does not.
  _detector 1 'x#1  1d  major  y'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 1 ]
  command grep -q -- '--data-raw' "${_RHN_NTFY_LOG}"
  run ! command grep -qE -- '(^| )-d( |$)' "${_RHN_NTFY_LOG}"
}

@test "a name that could break out of the state path is refused" {
  _detector 0
  for _bad in '../escape' 'a/b' 'has|pipe' 'Has-Caps' ''; do
    run bash "${SCRIPT}" "${_bad}" "${_RHN_DETECTOR}"
    [ "$status" -ne 0 ]
    [ ! -d "${_RHN_STATE_DIR}/${_bad}" ]
  done
}
