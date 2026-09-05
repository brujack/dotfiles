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
  # At setup scope, not per-test. _rhn_load_channel falls back to
  # REPO_ROOT/config/local.sh when this is unset, and that file exists untracked
  # on any provisioned machine with a live NTFY_URL -- so any case that unsets
  # NTFY_URL silently reads the operator's real channel. Setting it per-test
  # would leave the trap armed for the next case someone adds; three already set
  # it, and the fourth did not.
  export _RHN_LOCAL_CFG="${BATS_TEST_TMPDIR}/no-local-cfg.sh"
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

@test "setup points _RHN_LOCAL_CFG away from the real config/local.sh" {
  # Asserts the FIXTURE, not behaviour, and deliberately. The behavioural form
  # would have to write to the real config/local.sh to prove it is not read,
  # which mutates the operator's untracked machine-local secrets file.
  #
  # Three states satisfy a bare `[ ! -e "${_RHN_LOCAL_CFG}" ]` -- correctly
  # pointed at an absent fixture, unset, and empty -- and only the first is the
  # one meant, so each is excluded by its own assertion.
  [ -n "${_RHN_LOCAL_CFG:-}" ]
  [[ "${_RHN_LOCAL_CFG}" == "${BATS_TEST_TMPDIR}/"* ]]
  [ "${_RHN_LOCAL_CFG}" != "${REPO_ROOT}/config/local.sh" ]
  [ ! -e "${_RHN_LOCAL_CFG}" ]
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

@test "a quote in the credential is escaped, not silently truncated" {
  # curl's -K value is quote-delimited: an unescaped `"` terminates it early and
  # the rest is dropped. Measured via --libcurl: user = "has"quote:pw" emits
  # USERPWD "has:" -- truncated username, no password -- which surfaces as a 403
  # and reports as "delivery failed", identical to the server being down.
  export NTFY_USER='ha"s' NTFY_PASSWORD='p\w' NTFY_TOPIC="t"
  _detector 1 'x#1  1d  major  y'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 1 ]
  command grep -q 'ha\\"s' "${_RHN_NTFY_STDIN}"
  command grep -q 'p\\\\w'  "${_RHN_NTFY_STDIN}"
}

@test "a newline in the credential is refused, not escaped" {
  # curl's config format is line-oriented: a quoted value cannot contain a line
  # break, so everything after one is parsed as further DIRECTIVES. Measured on
  # curl 8.7.1 -- a password of $'p\noutput = /tmp/x' made curl obey the smuggled
  # `output` and write the response body there; user-agent/url/upload-file are
  # reachable identically. Escaping cannot close this; refusal can.
  export NTFY_USER="u" NTFY_PASSWORD=$'p\noutput = /tmp/pwned' NTFY_TOPIC="t"
  _detector 1 'x#1  1d  major  y'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"newline"* ]]
  run ! command grep -q 'output = ' "${_RHN_NTFY_STDIN}"
  run ! command grep -q 'output = ' "${_RHN_NTFY_LOG}"
}

@test "a carriage return is refused too" {
  export NTFY_USER="u" NTFY_PASSWORD=$'p\rurl = https://evil.invalid' NTFY_TOPIC="t"
  _detector 1 'x#1  1d  major  y'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [[ "$output" == *"newline"* ]]
  run ! command grep -q 'evil.invalid' "${_RHN_NTFY_STDIN}"
}

# A detector's stderr is its DIAGNOSIS channel: it says why a run could not
# determine an answer. Discarding it leaves the operator a notification naming
# no cause at all -- measured on the first real ledger-drift run, where
# `ERROR: ledger binary not found` never reached the push.
_detector_stderr() {  # $1 = exit code, $2 = stderr line, $3... = stdout lines
  local _rc="$1" _errline="$2"; shift 2
  local _d="${BATS_TEST_TMPDIR}/detector"
  { printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" %q >&2\n' "${_errline}"
    for _l in "$@"; do printf 'printf "%%s\\n" %q\n' "${_l}"; done
    printf 'exit %s\n' "${_rc}"; } > "${_d}"
  chmod +x "${_d}"
  export _RHN_DETECTOR="${_d}"
}

@test "the detector's stderr names the cause on the incomplete path" {
  _detector_stderr 2 'ERROR: ledger binary not found'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 2 ]
  command grep -q 'ledger binary not found' "${_RHN_NTFY_LOG}"
}

@test "the detector's stderr is surfaced on the held path too, not only incomplete" {
  _detector_stderr 1 'WARN: 2 of 9 repos unreachable' 'repo-a  6d  major' 'repo-b  6d  major'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 1 ]
  command grep -q '2 of 9 repos unreachable' "${_RHN_NTFY_LOG}"
  command grep -q 'repo-a' "${_RHN_NTFY_LOG}"
}

# stdout is the findings channel, stderr is not. Merging the two would inflate
# the count by the length of the diagnosis. This can only go red under mutation
# -- verified by rewriting the capture as `2>&1`, which takes it to 3 -- so it
# is a guard against a plausible future edit, not a repro of a past failure.
@test "the detector's stderr never inflates the finding count" {
  _detector_stderr 1 'WARN: 2 of 9 repos unreachable' 'repo-a  6d  major' 'repo-b  6d  major'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 1 ]
  command grep -q '"findings": 2' "${_RHN_STATE_DIR}/${NAME}/last-run.json"
}

# The cannot-determine path prints a diagnosis and no findings. Rendering that
# diagnosis under "Found so far:" would present a cause as a finding and count
# it as one -- the same collapse as the exit code, one layer up.
@test "a diagnosis with no findings is not labelled or counted as a finding" {
  _detector_stderr 2 'ERROR: ledger binary not found'
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 2 ]
  command grep -q '"findings": 0' "${_RHN_STATE_DIR}/${NAME}/last-run.json"
  run ! command grep -q 'Found so far' "${_RHN_NTFY_LOG}"
}

# The heartbeat must be written on EVERY outcome, including this script's own
# failures — a run that errored and a run that never happened must not look
# alike, because that distinction is the only thing doctor reads this file for.
@test "a temp-file failure is incomplete with a heartbeat, not a bare early return" {
  _detector 0
  printf '#!/usr/bin/env bash\nexit 1\n' > "${BATS_TEST_TMPDIR}/false-mktemp"
  chmod +x "${BATS_TEST_TMPDIR}/false-mktemp"
  export _RHN_MKTEMP="${BATS_TEST_TMPDIR}/false-mktemp"
  run bash "${SCRIPT}" "${NAME}" "${_RHN_DETECTOR}"
  [ "$status" -eq 2 ]
  command grep -q '"result": *"incomplete"' "${_RHN_STATE_DIR}/${NAME}/last-run.json"
}

# The captured stderr is POSTed off-box, so its size is a security property and
# not a formatting preference. Only-red-under-mutation, like the count guard:
# verified by removing the `tail -n 20`, which lets line 1 through.
@test "the published stderr is capped, so a runaway detector cannot dump unbounded output off-box" {
  local _d="${BATS_TEST_TMPDIR}/detector"
  { printf '#!/usr/bin/env bash\n'
    printf 'for i in $(seq 1 100); do printf "errline-%%s\\n" "$i" >&2; done\n'
    printf 'exit 2\n'; } > "${_d}"
  chmod +x "${_d}"
  run bash "${SCRIPT}" "${NAME}" "${_d}"
  [ "$status" -eq 2 ]
  command grep -q 'errline-100' "${_RHN_NTFY_LOG}"
  run ! command grep -q 'errline-1$' "${_RHN_NTFY_LOG}"
}
