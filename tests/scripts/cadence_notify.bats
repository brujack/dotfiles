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
  export NTFY_TOPIC="t" NTFY_USER="u" NTFY_PASSWORD="p"
  # every ntfy send is captured, never sent
  export _RHN_CURL_BIN="${BATS_TEST_TMPDIR}/fake-curl"
  export _RHN_NTFY_STDIN="${BATS_TEST_TMPDIR}/ntfy.stdin"
  cat > "${_RHN_CURL_BIN}" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${_RHN_NTFY_LOG}"
# Credentials must arrive on STDIN, never argv. Capturing both is what lets the
# pair of assertions discriminate: absent-from-argv alone passes on a build that
# sends no credential at all.
# Read stdin only when something is piped. A bare `cat` here blocks forever
# when production does not pipe -- the deadlock this repo documents for any
# process inheriting a live pipe.
if [ ! -t 0 ] && read -t 1 -r _l 2>/dev/null; then
  { printf '%s\n' "$_l"; cat; } >> "${_RHN_NTFY_STDIN}" 2>/dev/null || true
fi
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

@test "a detector that exists but is not executable is incomplete, not clean" {
  local _d="${BATS_TEST_TMPDIR}/noexec-detector"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${_d}"
  chmod 000 "${_d}"
  export _RHN_DETECTOR="${_d}"
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 2 ]
  command grep -q '"result": *"incomplete"' "${_RHN_STATE_DIR}/${NAME}/last-run.json"
  chmod 644 "${_d}"
}

@test "a heartbeat directory that cannot be created fails rather than reporting clean" {
  _detector 0
  local _blocked="${BATS_TEST_TMPDIR}/blocked"
  printf 'not a directory\n' > "${_blocked}"
  export _RHN_STATE_DIR="${_blocked}"
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -ne 0 ]
}

@test "the credential never appears in curl's argv" {
  # `curl -u user:pass` puts the password in the process argv, readable by any
  # `ps` on the box. Credentials go in via a config on stdin instead.
  export NTFY_USER="u" NTFY_PASSWORD="p" NTFY_TOPIC="topic"
  _detector 1 'x#1  1d  major  y'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 1 ]
  # POSITIVE: the credential is genuinely transmitted...
  command grep -q 'u:p' "${_RHN_NTFY_STDIN}"
  # ...and NEGATIVE: it is not on the command line, where any `ps` would see it.
  run ! command grep -q 'u:p' "${_RHN_NTFY_LOG}"
  run ! command grep -qE '(^| )-u( |$)' "${_RHN_NTFY_LOG}"
}

@test "the POST targets host/topic, never the bare host" {
  export NTFY_URL="https://ntfy.invalid" NTFY_TOPIC="mytopic"
  _detector 1 'x#1  1d  major  y'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 1 ]
  command grep -q 'https://ntfy.invalid/mytopic' "${_RHN_NTFY_LOG}"
}

@test "a trailing slash on NTFY_URL does not double up" {
  export NTFY_URL="https://ntfy.invalid/" NTFY_TOPIC="mytopic"
  _detector 1 'x#1  1d  major  y'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  command grep -q 'https://ntfy.invalid/mytopic' "${_RHN_NTFY_LOG}"
  run ! command grep -q 'invalid//mytopic' "${_RHN_NTFY_LOG}"
}

@test "an NTFY_URL that already carries a path is used verbatim" {
  export NTFY_URL="https://ntfy.invalid/preset" NTFY_TOPIC="mytopic"
  _detector 1 'x#1  1d  major  y'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  command grep -q 'https://ntfy.invalid/preset' "${_RHN_NTFY_LOG}"
  run ! command grep -q 'preset/mytopic' "${_RHN_NTFY_LOG}"
}

@test "missing credentials are reported distinctly from a missing channel" {
  # The endpoint requires auth (measured: anonymous POST -> 403), so no
  # credentials means no delivery -- a different fault from no URL, and it must
  # not render as the same message.
  export NTFY_URL="https://ntfy.invalid" NTFY_TOPIC="t"
  unset NTFY_USER NTFY_PASSWORD
  _detector 1 'x#1  1d  major  y'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"credential"* ]]
  run ! command grep -q 'no channel to deliver on' <<<"$output"
}

@test "config is sourced only when NTFY_URL is absent, so the env still wins" {
  local _cfg="${BATS_TEST_TMPDIR}/local.sh"
  printf 'export NTFY_URL="https://from-config.invalid"\nexport NTFY_TOPIC="cfgtopic"\nexport NTFY_USER="u"\nexport NTFY_PASSWORD="p"\n' > "${_cfg}"
  export _RHN_LOCAL_CFG="${_cfg}"
  export NTFY_URL="https://from-env.invalid" NTFY_TOPIC="envtopic" NTFY_USER="u" NTFY_PASSWORD="p"
  _detector 1 'x#1  1d  major  y'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  command grep -q 'from-env.invalid/envtopic' "${_RHN_NTFY_LOG}"
  run ! command grep -q 'from-config' "${_RHN_NTFY_LOG}"
}

@test "config supplies the channel when the env does not" {
  local _cfg="${BATS_TEST_TMPDIR}/local.sh"
  printf 'export NTFY_URL="https://from-config.invalid"\nexport NTFY_TOPIC="cfgtopic"\nexport NTFY_USER="u"\nexport NTFY_PASSWORD="p"\n' > "${_cfg}"
  export _RHN_LOCAL_CFG="${_cfg}"
  unset NTFY_URL NTFY_TOPIC NTFY_USER NTFY_PASSWORD
  _detector 1 'x#1  1d  major  y'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 1 ]
  command grep -q 'from-config.invalid/cfgtopic' "${_RHN_NTFY_LOG}"
}

@test "an absent config file is not an error — the no-channel path still reports" {
  export _RHN_LOCAL_CFG="${BATS_TEST_TMPDIR}/does-not-exist.sh"
  unset NTFY_URL NTFY_TOPIC NTFY_USER NTFY_PASSWORD
  _detector 1 'x#1  1d  major  y'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no channel"* ]]
}
