#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# _install_fetched_binary <name> <url> <bin|zip|tar> <member> [<dest-name>] [--resolve]:
# fetch into a throwaway dir, install last, stamp the URL only on success. A
# failure at any stage must leave the destination untouched, no stamp, and no
# throwaway directory behind.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  : > "${MOCK_CALLS_FILE}"
  # Setup scope: every directory the helper touches lives under the test tmpdir,
  # so a regression cannot reach the real /usr/local/bin or ~/software_downloads.
  export _DL_STAMP_DIR="${BATS_TEST_TMPDIR}/stamps"
  export _DL_TMP_ROOT="${BATS_TEST_TMPDIR}/dl-tmp"
  export _DL_BIN_DIR="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${_DL_TMP_ROOT}" "${_DL_BIN_DIR}"
  # tests/mocks/unzip and tar only record; extraction needs the real tools.
  _clean_path="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | tr '\n' ':' | sed 's/:$//')"
  _DL_UNZIP_BIN="$(PATH="${_clean_path}" command -v unzip)"
  _DL_TAR_BIN="$(PATH="${_clean_path}" command -v tar)"
  export _DL_UNZIP_BIN="${_DL_UNZIP_BIN:-/nonexistent/unzip}"
  export _DL_TAR_BIN="${_DL_TAR_BIN:-/nonexistent/tar}"
  _ZIP_BIN="$(PATH="${_clean_path}" command -v zip)"
  _ZIP_BIN="${_ZIP_BIN:-/nonexistent/zip}"
  DEST="${_DL_BIN_DIR}/tool"
  STAMP="${_DL_STAMP_DIR}/tool"
  URL="https://example.invalid/tool"
  printf 'old' > "${DEST}"
  chmod 0755 "${DEST}"
  # Default download: a plain file whose content is the new binary.
  FIXTURE="${BATS_TEST_TMPDIR}/fixture"
  printf 'new' > "${FIXTURE}"
  export MOCK_WGET_FILE="${FIXTURE}"
}

teardown() {
  # Restore anything a test made read-only so bats can clean the tmpdir.
  chmod -R u+rwx "${BATS_TEST_TMPDIR}" 2> /dev/null || :
}

_wget_count() {
  grep -c '^wget ' "${MOCK_CALLS_FILE}" || :
}

# Positive control for the "root is empty" assertions: the fetch really wrote
# under the throwaway root, so empty afterwards means cleaned, not never used.
_assert_tmp_was_used() {
  local _o
  _o="$(grep '^wget ' "${MOCK_CALLS_FILE}" | head -1 | sed -E 's/.* -O ([^ ]+) .*/\1/')"
  [[ "${_o}" == "${_DL_TMP_ROOT}/.dl."* ]]
}

_assert_root_empty() {
  [ -z "$(ls -A "${_DL_TMP_ROOT}")" ]
}

_make_zip() {
  local _src="${BATS_TEST_TMPDIR}/zsrc"
  mkdir -p "${_src}"
  printf 'zipped' > "${_src}/tool"
  (cd "${_src}" && "${_ZIP_BIN}" -q "${BATS_TEST_TMPDIR}/fixture.zip" tool)
  export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/fixture.zip"
}

_make_tar() {
  local _src="${BATS_TEST_TMPDIR}/tsrc"
  mkdir -p "${_src}/pkg/bin"
  printf 'tarred' > "${_src}/pkg/bin/tool"
  "${_DL_TAR_BIN}" -czf "${BATS_TEST_TMPDIR}/fixture.tgz" -C "${_src}" pkg
  export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/fixture.tgz"
}

@test "_install_fetched_binary: download failure leaves dest, no stamp, no workdir, then retry succeeds" {
  export MOCK_WGET_FAIL_URL="example.invalid"
  run _install_fetched_binary tool "${URL}" bin ""
  [ "$status" -eq 1 ]
  [[ "${output}" == *"tool: download failed"* ]]
  [ "$(_wget_count)" -eq 1 ]
  _assert_tmp_was_used
  [ ! -e "${STAMP}" ]
  _assert_root_empty
  [ "$(cat "${DEST}")" = "old" ]
  unset MOCK_WGET_FAIL_URL
  run _install_fetched_binary tool "${URL}" bin ""
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 2 ]
  [ "$(cat "${DEST}")" = "new" ]
  [ "$(cat "${STAMP}")" = "${URL}" ]
}

@test "_install_fetched_binary: extract failure leaves dest, no stamp, no workdir, then retry succeeds" {
  # FIXTURE is plain text, not a zip, so the real unzip rejects it.
  run _install_fetched_binary tool "${URL}" zip tool
  [ "$status" -eq 1 ]
  [[ "${output}" == *"tool: extract failed"* ]]
  [ "$(_wget_count)" -eq 1 ]
  _assert_tmp_was_used
  [ ! -e "${STAMP}" ]
  _assert_root_empty
  [ "$(cat "${DEST}")" = "old" ]
  _make_zip
  run _install_fetched_binary tool "${URL}" zip tool
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 2 ]
  [ "$(cat "${DEST}")" = "zipped" ]
  [ "$(cat "${STAMP}")" = "${URL}" ]
}

@test "_install_fetched_binary: install failure leaves dest, no stamp, no workdir, then retry succeeds" {
  chmod 0555 "${_DL_BIN_DIR}"
  run _install_fetched_binary tool "${URL}" bin ""
  [ "$status" -eq 1 ]
  [[ "${output}" == *"tool: install failed"* ]]
  [ "$(_wget_count)" -eq 1 ]
  _assert_tmp_was_used
  [ ! -e "${STAMP}" ]
  _assert_root_empty
  [ "$(cat "${DEST}")" = "old" ]
  chmod 0755 "${_DL_BIN_DIR}"
  run _install_fetched_binary tool "${URL}" bin ""
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 2 ]
  [ "$(cat "${DEST}")" = "new" ]
  [ "$(cat "${STAMP}")" = "${URL}" ]
}

@test "_install_fetched_binary: an unwritable stamp dir warns naming the path but still succeeds" {
  mkdir -p "${BATS_TEST_TMPDIR}/ro"
  chmod 0555 "${BATS_TEST_TMPDIR}/ro"
  export _DL_STAMP_DIR="${BATS_TEST_TMPDIR}/ro/stamps"
  run _install_fetched_binary tool "${URL}" bin ""
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 1 ]
  [ "$(cat "${DEST}")" = "new" ]
  [ ! -e "${_DL_STAMP_DIR}/tool" ]
  [[ "${output}" == *"could not write stamp ${_DL_STAMP_DIR}/tool"* ]]
  _assert_root_empty
}

@test "_install_fetched_binary: matching stamp and executable dest skips with the skip line and no fetch" {
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s\n' "${URL}" > "${STAMP}"
  run _install_fetched_binary tool "${URL}" bin ""
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 0 ]
  [[ "${output}" == *"tool: up to date (stamp ${STAMP}); rm it to force a re-install"* ]]
  [ "$(cat "${DEST}")" = "old" ]
}

@test "_install_fetched_binary: the same fixture without a stamp fetches exactly once" {
  run _install_fetched_binary tool "${URL}" bin ""
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 1 ]
  [[ "${output}" != *"up to date"* ]]
  [ "$(cat "${DEST}")" = "new" ]
}

@test "_install_fetched_binary: a stamp for a different URL fetches" {
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s\n' "https://example.invalid/other" > "${STAMP}"
  run _install_fetched_binary tool "${URL}" bin ""
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 1 ]
  [ "$(cat "${STAMP}")" = "${URL}" ]
}

@test "_install_fetched_binary: matching stamp but missing dest fetches" {
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s\n' "${URL}" > "${STAMP}"
  rm -f "${DEST}"
  run _install_fetched_binary tool "${URL}" bin ""
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 1 ]
  [ "$(cat "${DEST}")" = "new" ]
}

@test "_install_fetched_binary: zip success installs the member" {
  _make_zip
  run _install_fetched_binary tool "${URL}" zip tool
  [ "$status" -eq 0 ]
  [ "$(cat "${DEST}")" = "zipped" ]
  [ "$(cat "${STAMP}")" = "${URL}" ]
  _assert_tmp_was_used
  _assert_root_empty
}

@test "_install_fetched_binary: tar success installs a member in a subpath under a different dest name" {
  _make_tar
  run _install_fetched_binary tool "${URL}" tar pkg/bin/tool renamed
  [ "$status" -eq 0 ]
  [ "$(cat "${_DL_BIN_DIR}/renamed")" = "tarred" ]
  [ "$(cat "${_DL_STAMP_DIR}/tool")" = "${URL}" ]
  _assert_tmp_was_used
  _assert_root_empty
}

@test "_install_fetched_binary: --resolve with a matching stamp and executable dest skips without wget" {
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s\n' "https://example.invalid/v1" > "${STAMP}"
  export MOCK_CURL_STDOUT="https://example.invalid/v1"
  run _install_fetched_binary tool "${URL}" bin "" --resolve
  [ "$status" -eq 0 ]
  grep -q '^curl ' "${MOCK_CALLS_FILE}"
  [ "$(_wget_count)" -eq 0 ]
  [[ "${output}" == *"tool: up to date"* ]]
}

@test "_install_fetched_binary: --resolve to a new URL installs and stamps the resolved URL" {
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s\n' "https://example.invalid/v1" > "${STAMP}"
  export MOCK_CURL_STDOUT="https://example.invalid/v2"
  run _install_fetched_binary tool "${URL}" bin "" --resolve
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 1 ]
  grep -q '^wget .*https://example.invalid/v2' "${MOCK_CALLS_FILE}"
  [ "$(cat "${DEST}")" = "new" ]
  [ "$(cat "${STAMP}")" = "https://example.invalid/v2" ]
}

@test "_install_fetched_binary: dest-name followed by --resolve are both honoured" {
  export MOCK_CURL_STDOUT="https://example.invalid/v2"
  run _install_fetched_binary tool "${URL}" bin "" renamed --resolve
  [ "$status" -eq 0 ]
  [ "$(cat "${_DL_BIN_DIR}/renamed")" = "new" ]
}

@test "_install_fetched_binary: failed resolution with stamp and non-empty executable dest keeps the copy" {
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s\n' "https://example.invalid/v1" > "${STAMP}"
  export MOCK_CURL_EXIT=22
  run _install_fetched_binary tool "${URL}" bin "" --resolve
  [ "$status" -eq 0 ]
  grep -q '^curl ' "${MOCK_CALLS_FILE}"
  [ "$(_wget_count)" -eq 0 ]
  [[ "${output}" == *"tool: could not resolve ${URL}; keeping installed copy"* ]]
  [ "$(cat "${DEST}")" = "old" ]
}

@test "_install_fetched_binary: failed resolution with no stamp fails" {
  export MOCK_CURL_EXIT=22
  run _install_fetched_binary tool "${URL}" bin "" --resolve
  [ "$status" -eq 1 ]
  grep -q '^curl ' "${MOCK_CALLS_FILE}"
  [ "$(_wget_count)" -eq 0 ]
  [[ "${output}" == *"tool: resolve failed"* ]]
  [ "$(cat "${DEST}")" = "old" ]
}

@test "_install_fetched_binary: failed resolution with a stamp but a 0-byte dest fails" {
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s\n' "https://example.invalid/v1" > "${STAMP}"
  : > "${DEST}"
  export MOCK_CURL_EXIT=22
  run _install_fetched_binary tool "${URL}" bin "" --resolve
  [ "$status" -eq 1 ]
  grep -q '^curl ' "${MOCK_CALLS_FILE}"
  [ "$(_wget_count)" -eq 0 ]
  [[ "${output}" == *"tool: resolve failed"* ]]
}

@test "_install_fetched_binary: a resolved URL equal to the input counts as a failed resolution" {
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s\n' "https://example.invalid/v1" > "${STAMP}"
  export MOCK_CURL_STDOUT="${URL}"
  run _install_fetched_binary tool "${URL}" bin "" --resolve
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 0 ]
  [[ "${output}" == *"keeping installed copy"* ]]
  rm -f "${STAMP}"
  run _install_fetched_binary tool "${URL}" bin "" --resolve
  [ "$status" -eq 1 ]
  [ "$(_wget_count)" -eq 0 ]
}

@test "_install_fetched_binary: unknown kind and missing arguments are rejected before any fetch" {
  run _install_fetched_binary tool "${URL}" bogus ""
  [ "$status" -eq 1 ]
  run _install_fetched_binary "" "${URL}" bin ""
  [ "$status" -eq 1 ]
  run _install_fetched_binary tool "" bin ""
  [ "$status" -eq 1 ]
  [ "$(_wget_count)" -eq 0 ]
  [ "$(cat "${DEST}")" = "old" ]
}
