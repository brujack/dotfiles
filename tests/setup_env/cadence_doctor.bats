#!/usr/bin/env bats
#
# `run !` needs bats >= 1.5.0 (CI 1.10.0, this box 1.14.0). Declared so an
# older bats fails loudly rather than mis-parsing the negation.
bats_require_minimum_version 1.5.0

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/lib/helpers.sh" 2>/dev/null || true
  source "${REPO_ROOT}/lib/launch_agents.sh"
  # the check is Studio-only by design; pin the host so these test the LOGIC
  export HOSTNAME_SHORT="studio"
  export _RHN_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  mkdir -p "${_RHN_STATE_DIR}/renovate-held" "${_RHN_STATE_DIR}/ledger-drift"
  _DOCTOR_FAILED=0
}

_beat() {  # $1 = age in days, $2 = result
  local _ts
  _ts=$(date -u -v-"${1}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -d "${1} days ago" +%Y-%m-%dT%H:%M:%SZ)
  printf '{"ts": "%s", "result": "%s", "exit_code": 0, "findings": 0}\n' \
    "${_ts}" "${2:-clean}" > "${_RHN_STATE_DIR}/renovate-held/last-run.json"
}

@test "a fresh heartbeat passes" {
  _beat 1
  run _doctor_check_renovate_cadence
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "a heartbeat older than 8 days fails" {
  _beat 9
  run _doctor_check_renovate_cadence
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"9"* || "$output" == *"stale"* ]]
}

@test "exactly 8 days is still within the window" {
  _beat 8
  run _doctor_check_renovate_cadence
  [ "$status" -eq 0 ]
}

@test "a missing heartbeat fails and names the remedy" {
  rm -f "${_RHN_STATE_DIR}/renovate-held/last-run.json"
  run _doctor_check_renovate_cadence
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"never run"* || "$output" == *"missing"* ]]
}

@test "an unparsable heartbeat fails rather than passing on a default" {
  printf 'not json at all\n' > "${_RHN_STATE_DIR}/renovate-held/last-run.json"
  run _doctor_check_renovate_cadence
  [ "$status" -ne 0 ]
  # Assert the SPECIFIC guard. Without this the date-parse guard downstream
  # also produces a FAIL, so the test goes red for a reason other than the one
  # it names and the unparsable guard can be deleted with the suite still green.
  [[ "$output" == *"unparsable"* ]]
}

@test "a heartbeat with a valid ts but no result field is unparsable, not healthy" {
  # Reaches ONLY the unparsable guard: the timestamp parses fine, so no
  # downstream guard can absorb this case.
  printf '{"ts": "%s", "exit_code": 0}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    > "${_RHN_STATE_DIR}/renovate-held/last-run.json"
  run _doctor_check_renovate_cadence
  [ "$status" -ne 0 ]
  [[ "$output" == *"unparsable"* ]]
}

@test "a fresh heartbeat recording an incomplete run does not read as healthy" {
  _beat 1 incomplete
  run _doctor_check_renovate_cadence
  [ "$status" -ne 0 ]
  [[ "$output" == *"incomplete"* ]]
}

@test "a fresh heartbeat recording held PRs passes — held is a finding, not a fault" {
  _beat 1 held
  run _doctor_check_renovate_cadence
  [ "$status" -eq 0 ]
}

@test "on a non-cadence host the check is silent, not a pass and not a fail" {
  export HOSTNAME_SHORT="laptop"
  rm -f "${_RHN_STATE_DIR}/renovate-held/last-run.json"
  run _doctor_check_renovate_cadence
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the two cadences are judged independently" {
  local _fresh _stale
  _fresh=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  _stale=$(date -u -v-20d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "20 days ago" +%Y-%m-%dT%H:%M:%SZ)
  printf '{"ts": "%s", "result": "clean", "exit_code": 0, "findings": 0}\n' "${_fresh}" \
    > "${_RHN_STATE_DIR}/renovate-held/last-run.json"
  printf '{"ts": "%s", "result": "clean", "exit_code": 0, "findings": 0}\n' "${_stale}" \
    > "${_RHN_STATE_DIR}/ledger-drift/last-run.json"
  run _doctor_check_renovate_cadence
  [ "$status" -eq 0 ]
  run _doctor_check_ledger_drift_cadence
  [ "$status" -ne 0 ]
  [[ "$output" == *"ledger-drift"* ]]
}

@test "the missing-field and bad-date failures are lexically distinct" {
  # Guard against re-convergence: if both messages ever share the asserted
  # word again, the tests above stop discriminating and go green when their
  # guard is deleted. That has happened twice on this check.
  printf 'not json at all\n' > "${_RHN_STATE_DIR}/renovate-held/last-run.json"
  run _doctor_check_renovate_cadence
  [[ "$output" == *"unparsable"* ]]
  run ! command grep -q 'not a valid date' <<<"$output"

  printf '{"ts": "garbage-not-a-date", "result": "clean"}\n' \
    > "${_RHN_STATE_DIR}/renovate-held/last-run.json"
  run _doctor_check_renovate_cadence
  [[ "$output" == *"not a valid date"* ]]
  run ! command grep -q 'heartbeat is unparsable' <<<"$output"
}

@test "a future-dated heartbeat fails rather than passing forever" {
  # `-N -gt 8` is false for every negative N, so without an explicit guard the
  # staleness check can never fire again once a heartbeat is future-dated.
  local _fut
  _fut=$(date -u -v+400d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "+400 days" +%Y-%m-%dT%H:%M:%SZ)
  printf '{"ts": "%s", "result": "clean", "exit_code": 0, "findings": 0}\n' "${_fut}" \
    > "${_RHN_STATE_DIR}/renovate-held/last-run.json"
  run _doctor_check_renovate_cadence
  [ "$status" -ne 0 ]
  [[ "$output" == *"future"* ]]
  run ! command grep -q 'PASS' <<<"$output"
}
