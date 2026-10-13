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

@test "_flatpak_available: true with the mock on PATH, false when the seam hides it" {
  run _flatpak_available
  [ "$status" -eq 0 ]
  _scratch="${BATS_TEST_TMPDIR}/empty-path"
  mkdir -p "${_scratch}"
  PATH="${_scratch}" run _flatpak_available
  [ "$status" -ne 0 ]
}
