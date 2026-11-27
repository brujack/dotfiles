#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Suite-level HOME isolation: tests/helpers/suite_isolation.bash via the
# setup_suite.bash hook in each test directory. Every nested bats run below
# targets a fixture directory under BATS_TEST_TMPDIR.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  HELPER="${REPO_ROOT}/tests/helpers/suite_isolation.bash"
  FX="${BATS_TEST_TMPDIR}/fx"
  OUT="${BATS_TEST_TMPDIR}/out.env"
  REC="${BATS_TEST_TMPDIR}/rec"
}

# mkfx <fixture-test-body> [helper-path]: fixture dir with a hook and a.bats.
mkfx() {
  local _body="${1}" _helper="${2:-${HELPER}}"
  mkdir -p "${FX}"
  printf 'source "%s"\n' "${_helper}" > "${FX}/setup_suite.bash"
  printf '#!/usr/bin/env bats\n@test "probe" {\n%s\n}\n' "${_body}" > "${FX}/a.bats"
}

_uv_ver() {
  local _v
  _v="$(sed -n 's/^UV_VER="\(.*\)"$/\1/p' "${REPO_ROOT}/lib/constants.sh")"
  # A pattern broken the same way here and in the helper must not pass silently.
  [[ "${_v}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  printf '%s\n' "${_v}"
}

@test "every test directory has a setup_suite.bash that sources the helper" {
  local _dir
  while IFS= read -r _dir; do
    [[ -f "${REPO_ROOT}/${_dir}/setup_suite.bash" && ! -L "${REPO_ROOT}/${_dir}/setup_suite.bash" ]] \
      || { printf 'missing hook: %s\n' "${_dir}" >&2; return 1; }
    command grep -q 'suite_isolation.bash' "${REPO_ROOT}/${_dir}/setup_suite.bash" \
      || { printf 'missing hook: %s\n' "${_dir}" >&2; return 1; }
  done < <(while IFS= read -r _f; do dirname "${_f}"; done < "${REPO_ROOT}/tests/bats-files.txt" | LC_ALL=C sort -u)
}

@test "HOME of this test lies under a bats-sentinel directory" {
  [[ "${HOME}" == */bats-sentinel.*/home ]]
}

@test "setup_suite exports the R2 values" {
  mkfx 'env > "${OUT}"; for _d in HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME PARALLEL_HOME; do [ -d "${!_d}" ] && printf "dir-ok:%s\n" "${_d}" >> "${OUT}"; done'
  run env -u MOCK_CALLS_FILE OUT="${OUT}" bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 0 ]
  local _h _s
  _h="$(sed -n 's/^HOME=//p' "${OUT}")"
  [[ "${_h}" == */bats-sentinel.*/home ]]
  _s="${_h%/home}"
  command grep -qx "HOME=${_s}/home" "${OUT}"
  command grep -qx "ZDOTDIR=${_s}/home" "${OUT}"
  command grep -qx "TMPPREFIX=${_s}/zsh" "${OUT}"
  command grep -qx "PARALLEL_HOME=${_s}/parallel" "${OUT}"
  command grep -qx "XDG_CONFIG_HOME=${_s}/xdg/config" "${OUT}"
  command grep -qx "XDG_CACHE_HOME=${_s}/xdg/cache" "${OUT}"
  command grep -qx "XDG_DATA_HOME=${_s}/xdg/data" "${OUT}"
  command grep -qx "XDG_STATE_HOME=${_s}/xdg/state" "${OUT}"
  command grep -qx "GIT_CONFIG_GLOBAL=/dev/null" "${OUT}"
  command grep -qx "GIT_CONFIG_SYSTEM=/dev/null" "${OUT}"
  command grep -qx "MOCK_CALLS_FILE=${_s}/mock_calls" "${OUT}"
  if command grep -q '^_BATS_SENTINEL=' "${OUT}"; then return 1; fi
  local _n
  for _n in HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME PARALLEL_HOME; do
    command grep -qx "dir-ok:${_n}" "${OUT}"
  done
}

@test "a caller's MOCK_CALLS_FILE survives" {
  mkfx 'env > "${OUT}"'
  run env MOCK_CALLS_FILE=/caller/calls OUT="${OUT}" bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 0 ]
  command grep -qx 'MOCK_CALLS_FILE=/caller/calls' "${OUT}"
}

@test "PINNED_UV_BIN comes from the pre-swap HOME" {
  local _fake="${BATS_TEST_TMPDIR}/fakehome" _v _uv
  _v="$(_uv_ver)"
  _uv="${_fake}/.local/share/dotfiles/pinned/uv-${_v}/uv"
  mkdir -p "${_uv%/*}"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${_uv}"
  chmod +x "${_uv}"
  mkfx 'env > "${OUT}"'
  run env -u PINNED_UV_BIN HOME="${_fake}" OUT="${OUT}" bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 0 ]
  command grep -qx "PINNED_UV_BIN=${_uv}" "${OUT}"
  run env PINNED_UV_BIN=/caller/uv HOME="${_fake}" OUT="${OUT}" bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 0 ]
  command grep -qx 'PINNED_UV_BIN=/caller/uv' "${OUT}"
}

@test "PINNED_UV_BIN stays unset when the real HOME has no pinned uv" {
  local _fake="${BATS_TEST_TMPDIR}/emptyhome"
  mkdir -p "${_fake}"
  mkfx 'env > "${OUT}"'
  run env -u PINNED_UV_BIN HOME="${_fake}" OUT="${OUT}" bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 0 ]
  if command grep -q '^PINNED_UV_BIN=' "${OUT}"; then return 1; fi
}

@test "an unreadable constants file prints the message and still isolates" {
  local _t="${BATS_TEST_TMPDIR}/t"
  mkdir -p "${_t}/tests/helpers"
  cp "${HELPER}" "${_t}/tests/helpers/suite_isolation.bash"
  mkfx '[[ "${HOME}" == */bats-sentinel.*/home ]]' "${_t}/tests/helpers/suite_isolation.bash"
  run bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"cannot read UV_VER from"* ]]
}

@test "the sentinel exists during the run and is gone after" {
  mkfx '[ -d "${HOME%/home}" ]; printf "%s" "${HOME%/home}" > "${REC}"'
  run env REC="${REC}" bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 0 ]
  [ -n "$(cat "${REC}")" ]
  [ ! -e "$(cat "${REC}")" ]
}

@test "mktemp failure stops the suite" {
  local _mark="${BATS_TEST_TMPDIR}/ran"
  mkfx 'touch "${MARK}"'
  run env MARK="${_mark}" _BATS_SENTINEL_TMP_ROOT="${BATS_TEST_TMPDIR}/missing" bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 1 ]
  # setup_suite must stop the run: the fixture test never executes.
  [ ! -e "${_mark}" ]
  [[ "${output}" == *"not ok 1 setup_suite"* ]]
  [[ "${output}" == *"bats isolation: cannot create sentinel under"* ]]
}

@test "guard refuses an empty sentinel" {
  # shellcheck disable=SC1090 # HELPER is derived from BATS_TEST_DIRNAME in setup(); path is tests/helpers/suite_isolation.bash
  source "${HELPER}"
  _BATS_SENTINEL=""
  run teardown_suite
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"bats isolation: no sentinel to check"* ]]
}

@test "guard refuses a non-sentinel directory" {
  # shellcheck disable=SC1090 # HELPER is derived from BATS_TEST_DIRNAME in setup(); path is tests/helpers/suite_isolation.bash
  source "${HELPER}"
  mkdir -p "${BATS_TEST_TMPDIR}/canary"
  printf 'x' > "${BATS_TEST_TMPDIR}/canary/file"
  _BATS_SENTINEL="${BATS_TEST_TMPDIR}/canary"
  run teardown_suite
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"bats isolation: no sentinel to check"* ]]
  [ -f "${BATS_TEST_TMPDIR}/canary/file" ]
}

@test "a nested failing setup never deletes an inherited sentinel" {
  # Pins the outcome: a failed $(mktemp) assignment empties the variable anyway,
  # so the inherited value must be neither used nor deleted. The plant is a
  # valid sentinel path (basename bats-sentinel.*), so only the unset protects it.
  local _plant="${BATS_TEST_TMPDIR}/bats-sentinel.keep"
  mkdir -p "${_plant}/home"
  mkfx ':'
  run env _BATS_SENTINEL="${_plant}" _BATS_SENTINEL_TMP_ROOT="${BATS_TEST_TMPDIR}/missing" \
    bats "${FX}/a.bats" < /dev/null
  [ -d "${_plant}" ]
  [[ "${output}" == *"cannot create sentinel under"* ]]
  [[ "${output}" == *"no sentinel to check"* ]]
}

@test "an inherited exported _BATS_SENTINEL does not leak into tests" {
  local _plant="${BATS_TEST_TMPDIR}/bats-sentinel.inherit"
  mkdir -p "${_plant}/home"
  mkfx 'env > "${OUT}"'
  run env _BATS_SENTINEL="${_plant}" OUT="${OUT}" bats "${FX}/a.bats" < /dev/null
  [ "${status}" -eq 0 ]
  # `!` does not trip errexit mid-test, so branch explicitly.
  if command grep -q '^_BATS_SENTINEL=' "${OUT}"; then return 1; fi
  [ -d "${_plant}" ]
}

@test "guard refuses a sentinel-named path that does not exist" {
  # shellcheck disable=SC1090 # HELPER is derived from BATS_TEST_DIRNAME in setup(); path is tests/helpers/suite_isolation.bash
  source "${HELPER}"
  _BATS_SENTINEL="${BATS_TEST_TMPDIR}/bats-sentinel.gone"
  run teardown_suite
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"bats isolation: no sentinel to check"* ]]
}

@test "a failed removal is reported even when rm exits 0" {
  local _s="${BATS_TEST_TMPDIR}/bats-sentinel.rmfail" _shim="${BATS_TEST_TMPDIR}/shim"
  mkdir -p "${_s}/home/x" "${_shim}"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${_shim}/rm"
  chmod +x "${_shim}/rm"
  # shellcheck disable=SC1090 # HELPER is derived from BATS_TEST_DIRNAME in setup(); path is tests/helpers/suite_isolation.bash
  source "${HELPER}"
  _BATS_SENTINEL="${_s}"
  PATH="${_shim}:${PATH}" run teardown_suite
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"bats isolation: cannot remove"* ]]
  [[ "${output}" == *"chmod -R u+w"* ]]
  /bin/rm -rf "${_s}"
}

@test "sudo resolves to the refusing stub when a test loads no mocks" {
  # No load_mocks here, so this is the path release_binary.bats and
  # pinned_uv.bats take: the real /usr/bin/sudo must be unreachable.
  [[ "$(command -v sudo)" == */bats-sentinel.*/nosudo/sudo ]]
  run sudo touch "${BATS_TEST_TMPDIR}/must-not-exist"
  [ "${status}" -eq 97 ]
  [[ "${output}" == *"REAL SUDO BLOCKED"* ]]
  [ ! -e "${BATS_TEST_TMPDIR}/must-not-exist" ]
}
