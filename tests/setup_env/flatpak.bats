#!/usr/bin/env bats
# Read helpers for the flatpak update section and the NVIDIA GL check.

load '../helpers/common.bash'

setup() {
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  : > "${MOCK_CALLS_FILE}"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  FIXTURE="${REPO_ROOT}/tests/fixtures/flatpak/runtime-list.tsv"
  export _NVIDIA_MODULE_VERSION_FILE="${BATS_TEST_TMPDIR}/nvidia-version"
}

@test "_nvidia_loaded_version: dotted version becomes dashed" {
  printf '615.71.09\n' > "${_NVIDIA_MODULE_VERSION_FILE}"
  run _nvidia_loaded_version
  [ "$status" -eq 0 ]
  [ "$output" = "615-71-09" ]
}

@test "_nvidia_loaded_version: no trailing newline gives the same result" {
  printf '615.71.09' > "${_NVIDIA_MODULE_VERSION_FILE}"
  run _nvidia_loaded_version
  [ "$status" -eq 0 ]
  [ "$output" = "615-71-09" ]
}

@test "_nvidia_loaded_version: absent file returns 1 with no output" {
  rm -f "${_NVIDIA_MODULE_VERSION_FILE}"
  run _nvidia_loaded_version
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_nvidia_loaded_version: empty file returns 1 with no output" {
  : > "${_NVIDIA_MODULE_VERSION_FILE}"
  run _nvidia_loaded_version
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_nvidia_loaded_version: non-numeric suffix returns 1" {
  printf '615.71.09-beta\n' > "${_NVIDIA_MODULE_VERSION_FILE}"
  run _nvidia_loaded_version
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_nvidia_loaded_version: single component returns 1" {
  printf '615\n' > "${_NVIDIA_MODULE_VERSION_FILE}"
  run _nvidia_loaded_version
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_flatpak_nvidia_gl_refs: fixture yields exactly the two nvidia GL refs" {
  export MOCK_FLATPAK_LIST_RUNTIME="${FIXTURE}"
  run _flatpak_nvidia_gl_refs
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "org.freedesktop.Platform.GL.nvidia-615-71-09/x86_64/1.4" ]
  [ "${lines[1]}" = "org.freedesktop.Platform.GL32.nvidia-615-71-09/x86_64/1.4" ]
  [[ "$output" != *VAAPI* ]]
  [[ "$output" != *default* ]]
  grep -qx 'flatpak list --system --runtime --columns=application,arch,branch' "${MOCK_CALLS_FILE}"
}

@test "_flatpak_nvidia_gl_refs: a missing runtime list file fails the mock (exit 99)" {
  export MOCK_FLATPAK_LIST_RUNTIME="${BATS_TEST_TMPDIR}/does-not-exist"
  run _flatpak_nvidia_gl_refs
  [ "$status" -eq 1 ]
}

@test "_flatpak_nvidia_gl_refs: empty list gives empty output, rc 0" {
  unset MOCK_FLATPAK_LIST_RUNTIME
  run _flatpak_nvidia_gl_refs
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_flatpak_nvidia_gl_refs: list failure returns 1" {
  export MOCK_FLATPAK_LIST_RUNTIME="${FIXTURE}"
  export MOCK_FLATPAK_FAIL_SUBCMD=list
  run _flatpak_nvidia_gl_refs
  [ "$status" -eq 1 ]
}

@test "_flatpak_has_apps: an installed app returns 0" {
  export MOCK_FLATPAK_LIST_APP="com.valvesoftware.Steam"
  run _flatpak_has_apps
  [ "$status" -eq 0 ]
  grep -qx 'flatpak list --system --app --columns=application' "${MOCK_CALLS_FILE}"
}

@test "_flatpak_has_apps: no apps returns 1" {
  unset MOCK_FLATPAK_LIST_APP
  run _flatpak_has_apps
  [ "$status" -eq 1 ]
}

@test "_flatpak_has_apps: whitespace-only list returns 1" {
  export MOCK_FLATPAK_LIST_APP=" \n\t"
  run _flatpak_has_apps
  [ "$status" -eq 1 ]
}

@test "_flatpak_has_apps: list failure returns 2" {
  export MOCK_FLATPAK_LIST_APP="com.valvesoftware.Steam"
  export MOCK_FLATPAK_FAIL_SUBCMD=list
  run _flatpak_has_apps
  [ "$status" -eq 2 ]
}

@test "_flatpak_available: true with the mock on PATH, false with PATH set to an empty dir" {
  run _flatpak_available
  [ "$status" -eq 0 ]
  _scratch="${BATS_TEST_TMPDIR}/empty-path"
  mkdir -p "${_scratch}"
  PATH="${_scratch}" run _flatpak_available
  [ "$status" -ne 0 ]
}

@test "_flatpak_nvidia_gl_refs: real read-only flatpak list yields only nvidia GL refs" {
  _clean_path="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | tr '\n' ':' | sed 's/:$//')"
  PATH="${_clean_path}" command -v flatpak > /dev/null 2>&1 || skip "flatpak not installed"
  unset _NVIDIA_MODULE_VERSION_FILE
  PATH="${_clean_path}" run _flatpak_nvidia_gl_refs
  [ "$status" -eq 0 ]
  [[ "$output" != *VAAPI* ]]
  local _line
  while IFS= read -r _line; do
    [[ -z "${_line}" ]] && continue
    [[ "${_line}" =~ ^org\.freedesktop\.Platform\.GL(32)?\.nvidia-[0-9-]+/[^/]+/[^/]+$ ]]
  done <<<"${output}"
  # Count against the raw list by a second mechanism (grep on the id column),
  # not against the loaded driver: a host whose extension is missing is the
  # state this feature reports, and must not turn the suite red.
  local _raw _got
  _raw="$(PATH="${_clean_path}" flatpak list --system --runtime --columns=application \
    | grep -cE '^org\.freedesktop\.Platform\.GL(32)?\.nvidia-')" || true
  _got="$(grep -c . <<<"${output}")" || true
  [ "${_got}" -eq "${_raw}" ]
}

# ── update_flatpak_packages ──────────────────────────────────────────────────

_gl_missing_fixture() {
  grep -v 'GL\.nvidia-615-71-09' "${FIXTURE}" > "${BATS_TEST_TMPDIR}/runtime-missing.tsv"
  printf '%s' "${BATS_TEST_TMPDIR}/runtime-missing.tsv"
}

_with_driver() {
  printf '615.71.09\n' > "${_NVIDIA_MODULE_VERSION_FILE}"
}

@test "update_flatpak_packages: update failure returns 1 and never uninstalls" {
  export MOCK_FLATPAK_FAIL_SUBCMD=update
  run update_flatpak_packages
  [ "$status" -eq 1 ]
  ! grep -q '^flatpak uninstall' "${MOCK_CALLS_FILE}"
}

@test "update_flatpak_packages: uninstall --unused failure returns 1, update ran first, no list after" {
  _with_driver
  export MOCK_FLATPAK_LIST_RUNTIME="${FIXTURE}"
  export MOCK_FLATPAK_LIST_APP="com.valvesoftware.Steam"
  export MOCK_FLATPAK_FAIL_ARGS=--unused
  run update_flatpak_packages
  [ "$status" -eq 1 ]
  local _u _x
  _u="$(grep -n '^flatpak update' "${MOCK_CALLS_FILE}" | head -1 | cut -d: -f1)"
  _x="$(grep -n '^flatpak uninstall' "${MOCK_CALLS_FILE}" | head -1 | cut -d: -f1)"
  [ -n "${_u}" ]
  [ -n "${_x}" ]
  [ "${_u}" -lt "${_x}" ]
  ! grep -q '^flatpak list' "${MOCK_CALLS_FILE}"
}

@test "update_flatpak_packages: the only uninstall is uninstall --unused" {
  _with_driver
  export MOCK_FLATPAK_LIST_RUNTIME="${FIXTURE}"
  export MOCK_FLATPAK_LIST_APP="com.valvesoftware.Steam"
  run update_flatpak_packages
  [ "$status" -eq 0 ]
  [ "$(grep -c '^flatpak uninstall' "${MOCK_CALLS_FILE}")" -eq 1 ]
  grep -qx 'flatpak uninstall -y --noninteractive --system --unused' "${MOCK_CALLS_FILE}"
  grep -qx 'flatpak update -y --noninteractive --system' "${MOCK_CALLS_FILE}"
  grep -qx 'sudo flatpak update -y --noninteractive --system' "${MOCK_CALLS_FILE}"
  grep -qx 'sudo flatpak uninstall -y --noninteractive --system --unused' "${MOCK_CALLS_FILE}"
}

@test "update_flatpak_packages: no driver version file returns 0, no flatpak: line, no list call" {
  rm -f "${_NVIDIA_MODULE_VERSION_FILE}"
  run update_flatpak_packages
  [ "$status" -eq 0 ]
  [[ "$output" != *"flatpak: no GL"* ]]
  ! grep -q '^flatpak list' "${MOCK_CALLS_FILE}"
}

@test "update_flatpak_packages: full fixture with apps returns 0" {
  _with_driver
  export MOCK_FLATPAK_LIST_RUNTIME="${FIXTURE}"
  export MOCK_FLATPAK_LIST_APP="com.valvesoftware.Steam"
  run update_flatpak_packages
  [ "$status" -eq 0 ]
  [[ "$output" != *"flatpak: no GL"* ]]
}

@test "update_flatpak_packages: GL.nvidia missing returns 2 and names the driver" {
  _with_driver
  export MOCK_FLATPAK_LIST_RUNTIME
  MOCK_FLATPAK_LIST_RUNTIME="$(_gl_missing_fixture)"
  export MOCK_FLATPAK_LIST_APP="com.valvesoftware.Steam"
  run update_flatpak_packages
  [ "$status" -eq 2 ]
  [[ "$output" == *"flatpak: no GL.nvidia-615-71-09 installed for loaded driver 615.71.09"* ]]
}

@test "update_flatpak_packages: empty runtime list with apps returns 2" {
  _with_driver
  unset MOCK_FLATPAK_LIST_RUNTIME
  export MOCK_FLATPAK_LIST_APP="com.valvesoftware.Steam"
  run update_flatpak_packages
  [ "$status" -eq 2 ]
  [[ "$output" == *"flatpak: no GL.nvidia-615-71-09"* ]]
}

@test "update_flatpak_packages: GL32 only returns 2" {
  _with_driver
  grep 'GL32\.nvidia-615-71-09' "${FIXTURE}" > "${BATS_TEST_TMPDIR}/gl32.tsv"
  export MOCK_FLATPAK_LIST_RUNTIME="${BATS_TEST_TMPDIR}/gl32.tsv"
  export MOCK_FLATPAK_LIST_APP="com.valvesoftware.Steam"
  run update_flatpak_packages
  [ "$status" -eq 2 ]
  [[ "$output" == *"flatpak: no GL.nvidia-615-71-09"* ]]
}

@test "update_flatpak_packages: a ref whose version only extends the loaded one returns 2" {
  _with_driver
  printf 'org.freedesktop.Platform.GL.nvidia-615-71-09x\tx86_64\t1.4\n' > "${BATS_TEST_TMPDIR}/prefix.tsv"
  export MOCK_FLATPAK_LIST_RUNTIME="${BATS_TEST_TMPDIR}/prefix.tsv"
  export MOCK_FLATPAK_LIST_APP="com.valvesoftware.Steam"
  run update_flatpak_packages
  [ "$status" -eq 2 ]
  [[ "$output" == *"flatpak: no GL.nvidia-615-71-09"* ]]
}

@test "update_flatpak_packages: GL missing but no apps returns 0, no line" {
  _with_driver
  export MOCK_FLATPAK_LIST_RUNTIME
  MOCK_FLATPAK_LIST_RUNTIME="$(_gl_missing_fixture)"
  export MOCK_FLATPAK_LIST_APP=
  run update_flatpak_packages
  [ "$status" -eq 0 ]
  [[ "$output" != *"flatpak: no GL"* ]]
}

@test "update_flatpak_packages: runtime list failure returns 1" {
  _with_driver
  export MOCK_FLATPAK_LIST_RUNTIME="${FIXTURE}"
  export MOCK_FLATPAK_LIST_APP="com.valvesoftware.Steam"
  export MOCK_FLATPAK_FAIL_ARGS=--runtime
  run update_flatpak_packages
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot list runtimes"* ]]
}

@test "update_flatpak_packages: app list failure returns 1" {
  _with_driver
  export MOCK_FLATPAK_LIST_RUNTIME="${FIXTURE}"
  export MOCK_FLATPAK_FAIL_ARGS=--app
  run update_flatpak_packages
  [ "$status" -eq 1 ]
}

# ── run_update flatpak section ───────────────────────────────────────────────

@test "run_update flatpak section: OK when update_flatpak_packages succeeds" {
  setup_run_update_linux
  update_flatpak_packages() { printf 'Updated flatpak runtimes\n'; return 0; }
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_flatpak")" = "OK" ]
}

@test "run_update flatpak section: rc 2 is WARN with reason and detail, not FAIL" {
  setup_run_update_linux
  update_flatpak_packages() {
    printf 'flatpak: no GL.nvidia-615-71-09 installed for loaded driver 615.71.09\n'
    return 2
  }
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_flatpak")" = "WARN" ]
  [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_flatpak")" == *"no NVIDIA GL extension for the loaded driver"* ]]
  grep -q 'flatpak: no GL.nvidia-' "${_DOTFILES_RUN_TMPDIR}/detail_flatpak"
  ! grep -q FAIL "${_DOTFILES_RUN_TMPDIR}/status_flatpak"
}

@test "run_update flatpak section: rc 2 does not make run_update fail" {
  setup_run_update_linux
  update_flatpak_packages() { return 2; }
  run run_update
  [ "$status" -eq 0 ]
}

@test "run_update flatpak section: rc 1 is FAIL" {
  setup_run_update_linux
  update_flatpak_packages() { return 1; }
  local _rc=0
  run_update || _rc=$?
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_flatpak")" = "FAIL" ]
  [ "${_rc}" -ne 0 ]
}

@test "run_update flatpak section: SKIP when flatpak is not installed" {
  setup_run_update_linux
  _flatpak_available() { return 1; }
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_flatpak")" = "SKIP" ]
  grep -q "flatpak not installed on this host" "${_DOTFILES_RUN_TMPDIR}/result_flatpak"
  ! grep -q '^flatpak update' "${MOCK_CALLS_FILE}"
}

@test "run_update flatpak section: SKIP not applicable off Linux" {
  setup_run_update_linux
  unset LINUX UBUNTU NOBLE
  export MACOS=1
  run_update
  grep -q "not applicable" "${_DOTFILES_RUN_TMPDIR}/result_flatpak"
}

@test "run_update flatpak section: SKIP flag not set" {
  setup_run_update_linux
  unset UPDATE_PKGS
  export UPDATE_CLAUDE=1
  run_update
  grep -q "flag not set" "${_DOTFILES_RUN_TMPDIR}/result_flatpak"
}

@test "_UPDATE_SECTION_ORDER: flatpak directly follows snap" {
  local _i _snap=-1 _fp=-1
  for _i in "${!_UPDATE_SECTION_ORDER[@]}"; do
    [[ "${_UPDATE_SECTION_ORDER[${_i}]}" == snap ]] && _snap="${_i}"
    [[ "${_UPDATE_SECTION_ORDER[${_i}]}" == flatpak ]] && _fp="${_i}"
  done
  [ "${_snap}" -ge 0 ]
  [ "${_fp}" -eq $(( _snap + 1 )) ]
}
