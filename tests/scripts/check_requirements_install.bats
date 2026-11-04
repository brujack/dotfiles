#!/usr/bin/env bats
# scripts/check-requirements-install.sh installs the requirements-ci renderings
# that ai-config and state-ledger CI pull live from dotfiles master, in each
# consumer's install shape, under the interpreter pyproject.toml requires.
#
# Every test drives a stub interpreter through RENDERINGS_INSTALL_PYTHON: the
# real check needs the network and minutes of pip, so the suite proves the
# script's control flow and the CI job proves the install.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/check-requirements-install.sh"
  WF="${REPO_ROOT}/.github/workflows/ci.yml"

  # Fixture root: a pyproject.toml carrying requires-python and the three
  # consumed renderings, so no test reads or mutates the tracked files.
  ROOT="${BATS_TEST_TMPDIR}/root"
  mkdir -p "${ROOT}"
  printf '[project]\nrequires-python = "==3.14.*"\n' > "${ROOT}/pyproject.toml"
  for _f in requirements-ci-test.txt requirements-ci-audit.txt requirements-ci-mutation.txt; do
    printf 'pkg==1.0 --hash=sha256:00\n' > "${ROOT}/${_f}"
  done
  export RENDERINGS_INSTALL_ROOT="${ROOT}"

  TMP_ROOT="${BATS_TEST_TMPDIR}/tmp"
  mkdir -p "${TMP_ROOT}"
  export RENDERINGS_INSTALL_TMP_ROOT="${TMP_ROOT}"

  CALLS="${BATS_TEST_TMPDIR}/calls"
  : > "${CALLS}"
  export STUB_CALLS="${CALLS}"
  export STUB_PY_MINOR="3.14"
  unset STUB_PIP_FAIL_MATCH STUB_VENV_FAIL

  # Stub interpreter: answers the version probe and `-m venv DIR`, creating a
  # DIR/bin/pip that logs its argv and fails when an argument matches
  # STUB_PIP_FAIL_MATCH.
  STUB="${BATS_TEST_TMPDIR}/bin/python"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${STUB}" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-c" ]]; then
  printf '%s\n' "${STUB_PY_MINOR}"
  exit 0
fi
if [[ "$1" == "-m" && "$2" == "venv" ]]; then
  [[ -n "${STUB_VENV_FAIL:-}" ]] && exit 1
  mkdir -p "$3/bin"
  printf 'venv %s\n' "$3" >> "${STUB_CALLS}"
  cat > "$3/bin/pip" <<'PIP'
#!/usr/bin/env bash
printf 'pip %s\n' "$*" >> "${STUB_CALLS}"
if [[ -n "${STUB_PIP_FAIL_MATCH:-}" && "$*" == *"${STUB_PIP_FAIL_MATCH}"* ]]; then
  exit 1
fi
exit 0
PIP
  chmod +x "$3/bin/pip"
  exit 0
fi
exit 99
EOF
  chmod +x "${STUB}"
  export RENDERINGS_INSTALL_PYTHON="${STUB}"
}

# _job_block <job>: print a top-level job's lines from ci.yml.
_job_block() {
  awk -v want="$1" '
    /^  [a-z-]+:$/ { job=$1; sub(/:$/,"",job); next }
    job == want { print }
  ' "${WF}"
}

@test "installs every consumer shape, each in its own venv, with --require-hashes" {
  run "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(grep -c '^venv ' "${CALLS}")" -eq 3 ]
  [ "$(grep -c '^pip ' "${CALLS}")" -eq 5 ]
  [ "$(grep '^pip ' "${CALLS}" | grep -vc -- '--require-hashes')" -eq 0 ]
  # Order mirrors the consumers: test then audit, mutation alone, test then mutation.
  run grep -o 'requirements-ci-[a-z]*\.txt' "${CALLS}"
  [ "${output}" = "requirements-ci-test.txt
requirements-ci-audit.txt
requirements-ci-mutation.txt
requirements-ci-test.txt
requirements-ci-mutation.txt" ]
}

@test "a failed install exits 1, names the shape, and still tries the others" {
  export STUB_PIP_FAIL_MATCH="requirements-ci-audit.txt"
  run "${SCRIPT}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAILED: ci-test+ci-audit"* ]]
  [[ "${output}" == *"OK: ci-mutation"* ]]
  [[ "${output}" == *"OK: ci-test+ci-mutation"* ]]
  [ "$(grep -c '^venv ' "${CALLS}")" -eq 3 ]
}

@test "an interpreter of the wrong minor version exits 2 before any venv" {
  export STUB_PY_MINOR="3.13"
  run "${SCRIPT}"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"3.13"* && "${output}" == *"3.14"* ]]
  [ ! -s "${CALLS}" ]
}

@test "a missing interpreter exits 2" {
  export RENDERINGS_INSTALL_PYTHON="${BATS_TEST_TMPDIR}/no-such-python"
  run "${SCRIPT}"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"no-such-python"* ]]
}

@test "a requires-python not of the form ==X.Y.* exits 2" {
  printf '[project]\nrequires-python = ">=3.12"\n' > "${ROOT}/pyproject.toml"
  run "${SCRIPT}"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"requires-python"* ]]
  [ ! -s "${CALLS}" ]
}

@test "a missing rendering fails its shapes without running pip for them" {
  rm "${ROOT}/requirements-ci-audit.txt"
  run "${SCRIPT}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"MISSING: requirements-ci-audit.txt"* ]]
  [[ "${output}" == *"OK: ci-mutation"* ]]
  [ "$(grep -c 'requirements-ci-audit.txt' "${CALLS}")" -eq 0 ]
}

@test "a venv that cannot be created fails every shape" {
  export STUB_VENV_FAIL=1
  run "${SCRIPT}"
  [ "${status}" -eq 1 ]
  [ "$(grep -c 'FAILED: ' <<< "${output}")" -eq 3 ]
  [ "$(grep -c '^pip ' "${CALLS}")" -eq 0 ]
}

@test "temporary venvs are removed after success and after failure" {
  run "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ -z "$(ls -A "${TMP_ROOT}")" ]
  export STUB_PIP_FAIL_MATCH="requirements-ci-test.txt"
  run "${SCRIPT}"
  [ "${status}" -eq 1 ]
  [ -z "$(ls -A "${TMP_ROOT}")" ]
}

@test "an unwritable temp root exits 2" {
  export RENDERINGS_INSTALL_TMP_ROOT="${BATS_TEST_TMPDIR}/no-such-dir"
  run "${SCRIPT}"
  [ "${status}" -eq 2 ]
}

@test "ci.yml renderings-install job runs the check on the required python and gates auto-merge" {
  run _job_block renderings-install
  [ -n "${output}" ]
  [[ "${output}" == *"runs-on: ubuntu-latest"* ]]
  [[ "${output}" == *"timeout-minutes:"* ]]
  [[ "${output}" == *"contents: read"* ]]
  [[ "${output}" == *"make check-requirements-install"* ]]
  # The job's python must be the minor pyproject.toml requires, so a
  # requires-python bump cannot leave CI testing the old interpreter.
  _want="$(sed -nE 's/^requires-python = "==([0-9]+\.[0-9]+)\.\*"$/\1/p' "${REPO_ROOT}/pyproject.toml")"
  [ -n "${_want}" ]
  [[ "${output}" == *"python-version: \"${_want}\""* ]]
  run _job_block auto-merge
  [[ "${output}" =~ needs:\ \[[^]]*renderings-install ]]
}

@test "_job_block reads only the named job" {
  # positive control: auto-merge holds the gate script; secret-scan does not.
  run _job_block secret-scan
  [[ "${output}" == *"gitleaks"* ]]
  [[ "${output}" != *"auto-merge-gate.sh"* ]]
  run _job_block no-such-job
  [ -z "${output}" ]
}

@test "check-requirements-install is a make target outside make test" {
  run grep -E '^check-requirements-install:' "${REPO_ROOT}/Makefile"
  [ "${status}" -eq 0 ]
  # It needs the network, so it must not run on every push.
  run grep -E '^(test|test-prereqs):.*check-requirements-install' "${REPO_ROOT}/Makefile"
  [ "${status}" -ne 0 ]
}
