#!/usr/bin/env bats
# _doctor_check_gitguardian_config: does a .gitguardian config sit where ggshield
# would read it (HOME or a listed repo's working tree) and silence the scan?

load '../helpers/common.bash'

setup() {
  load_setup_env
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/personal"
  mkdir -p "${PERSONAL_GITREPOS}/alpha" "${PERSONAL_GITREPOS}/beta"
  # shellcheck disable=SC2034 # read by _doctor_check_gitguardian_config in lib/helpers.sh
  HOOK_EXPECTED_REPOS=(alpha beta)
  OUT="${BATS_TEST_TMPDIR}/arm_out"
}

# run_arm -- NOT `run`: a subshell would lose the counters.
run_arm() {
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_WARN=0; _DOCTOR_FAILED=0
  _doctor_check_gitguardian_config > "${OUT}" 2>&1
}

@test "doctor gitguardian config: none found is one PASS" {
  run_arm
  grep -qF "no .gitguardian config in ${HOME} or the listed repos" "${OUT}"
  [ "${_DOCTOR_PASS}" -eq 1 ]
  [ "${_DOCTOR_WARN}" -eq 0 ]
}

@test "doctor gitguardian config: home .gitguardian.yaml is a WARN naming its path" {
  : > "${HOME}/.gitguardian.yaml"
  run_arm
  grep -qF "${HOME}/.gitguardian.yaml" "${OUT}"
  grep -qF "[WARN]" "${OUT}"
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
}

@test "doctor gitguardian config: untracked .gitguardian.yml in a repo is a WARN" {
  git init -q "${PERSONAL_GITREPOS}/alpha"
  : > "${PERSONAL_GITREPOS}/alpha/.gitguardian.yml"
  run_arm
  grep -qF "${PERSONAL_GITREPOS}/alpha/.gitguardian.yml" "${OUT}"
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
}

@test "doctor gitguardian config: tracked .gitguardian in a repo is a WARN" {
  git init -q "${PERSONAL_GITREPOS}/alpha"
  : > "${PERSONAL_GITREPOS}/alpha/.gitguardian"
  git -C "${PERSONAL_GITREPOS}/alpha" add .gitguardian
  run_arm
  grep -qF "${PERSONAL_GITREPOS}/alpha/.gitguardian " "${OUT}"
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
}

@test "doctor gitguardian config: dangling symlink is a WARN" {
  ln -s "${BATS_TEST_TMPDIR}/nowhere" "${HOME}/.gitguardian.yaml"
  run_arm
  grep -qF "${HOME}/.gitguardian.yaml" "${OUT}"
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
}

@test "doctor gitguardian config: two files are two WARNs and no PASS" {
  : > "${HOME}/.gitguardian"
  : > "${PERSONAL_GITREPOS}/beta/.gitguardian.yaml"
  run_arm
  [ "$(grep -c '\[WARN\]' "${OUT}")" -eq 2 ]
  [ "${_DOCTOR_WARN}" -eq 2 ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
}

@test "doctor gitguardian config: an absent repo dir is skipped silently" {
  # shellcheck disable=SC2034 # read by _doctor_check_gitguardian_config in lib/helpers.sh
  HOOK_EXPECTED_REPOS=(alpha missing)
  run_arm
  run grep -qF "missing" "${OUT}"
  [ "${status}" -ne 0 ]
  [ "${_DOCTOR_PASS}" -eq 1 ]
  [ "${_DOCTOR_FAIL}" -eq 0 ]
}

@test "doctor gitguardian config: empty HOOK_EXPECTED_REPOS still checks HOME" {
  # shellcheck disable=SC2034 # read by _doctor_check_gitguardian_config in lib/helpers.sh
  HOOK_EXPECTED_REPOS=()
  : > "${HOME}/.gitguardian.yml"
  run_arm
  grep -qF "${HOME}/.gitguardian.yml" "${OUT}"
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ "${_DOCTOR_FAIL}" -eq 0 ]
}

@test "doctor gitguardian config: unset HOOK_EXPECTED_REPOS passes without failing" {
  unset HOOK_EXPECTED_REPOS
  run_arm
  [ "${_DOCTOR_PASS}" -eq 1 ]
  [ "${_DOCTOR_FAIL}" -eq 0 ]
}
