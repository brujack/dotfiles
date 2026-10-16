#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# _install_fetched_binary <name> <bin|zip|tar> <member> [<dest-name>]: fetch into a
# throwaway dir, verify against the pin, install last, stamp only on success. A
# failure at any stage must leave the destination untouched, no stamp, and no
# throwaway directory behind.
# The chmod-based tests (read-only dirs) assume a non-root runner; root ignores
# those permission bits.

# Pinned-form seams: the real sha256 of the file the wget mock will serve.
# Recompute after every switch of MOCK_WGET_FILE; sha256sum is never mocked.
_seam_for() {
  export _FETCHED_URL="${URL}"
  _FETCHED_SHA256="$(sha256sum "$1")"
  export _FETCHED_SHA256="${_FETCHED_SHA256%% *}"
}

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
  _seam_for "${FIXTURE}"
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
  _seam_for "${MOCK_WGET_FILE}"
}

_make_tar() {
  local _src="${BATS_TEST_TMPDIR}/tsrc"
  mkdir -p "${_src}/pkg/bin"
  printf 'tarred' > "${_src}/pkg/bin/tool"
  "${_DL_TAR_BIN}" -czf "${BATS_TEST_TMPDIR}/fixture.tgz" -C "${_src}" pkg
  export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/fixture.tgz"
  _seam_for "${MOCK_WGET_FILE}"
}

@test "_install_fetched_binary: download failure leaves dest, no stamp, no workdir, then retry succeeds" {
  export MOCK_WGET_FAIL_URL="example.invalid"
  run _install_fetched_binary tool bin ""
  [ "$status" -eq 1 ]
  [[ "${output}" == *"tool: download failed"* ]]
  [ "$(_wget_count)" -eq 1 ]
  _assert_tmp_was_used
  [ ! -e "${STAMP}" ]
  _assert_root_empty
  [ "$(cat "${DEST}")" = "old" ]
  unset MOCK_WGET_FAIL_URL
  run _install_fetched_binary tool bin ""
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 2 ]
  [ "$(cat "${DEST}")" = "new" ]
  [ "$(cat "${STAMP}")" = "${URL} ${_FETCHED_SHA256}" ]
}

@test "_install_fetched_binary: extract failure leaves dest, no stamp, no workdir, then retry succeeds" {
  # FIXTURE is plain text, not a zip, so the real unzip rejects it.
  run _install_fetched_binary tool zip tool
  [ "$status" -eq 1 ]
  [[ "${output}" == *"tool: extract failed"* ]]
  [ "$(_wget_count)" -eq 1 ]
  _assert_tmp_was_used
  [ ! -e "${STAMP}" ]
  _assert_root_empty
  [ "$(cat "${DEST}")" = "old" ]
  _make_zip
  run _install_fetched_binary tool zip tool
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 2 ]
  [ "$(cat "${DEST}")" = "zipped" ]
  [ "$(cat "${STAMP}")" = "${URL} ${_FETCHED_SHA256}" ]
}

# The member check alone would accept these: the extractor wrote a good member
# and then reported failure, so only the exit status can refuse the install.
@test "_install_fetched_binary: an unzip that writes the member then exits non-zero fails the extract stage" {
  _make_zip
  local _stub="${BATS_TEST_TMPDIR}/unzip-then-fail"
  printf '#!/usr/bin/env bash\n"%s" "$@"\nexit 1\n' "${_DL_UNZIP_BIN}" > "${_stub}"
  chmod +x "${_stub}"
  export _DL_UNZIP_BIN="${_stub}"
  run _install_fetched_binary tool zip tool
  [ "$status" -eq 1 ]
  [[ "${output}" == *"tool: extract failed"* ]]
  _assert_tmp_was_used
  [ "$(cat "${DEST}")" = "old" ]
  [ ! -e "${STAMP}" ]
  _assert_root_empty
}

@test "_install_fetched_binary: a tar that writes the member then exits non-zero fails the extract stage" {
  _make_tar
  local _stub="${BATS_TEST_TMPDIR}/tar-then-fail"
  printf '#!/usr/bin/env bash\n"%s" "$@"\nexit 1\n' "${_DL_TAR_BIN}" > "${_stub}"
  chmod +x "${_stub}"
  export _DL_TAR_BIN="${_stub}"
  run _install_fetched_binary tool tar pkg/bin/tool
  [ "$status" -eq 1 ]
  [[ "${output}" == *"tool: extract failed"* ]]
  _assert_tmp_was_used
  [ "$(cat "${DEST}")" = "old" ]
  [ ! -e "${STAMP}" ]
  _assert_root_empty
}

@test "_install_fetched_binary: install failure leaves dest, no stamp, no workdir, then retry succeeds" {
  chmod 0555 "${_DL_BIN_DIR}"
  run _install_fetched_binary tool bin ""
  [ "$status" -eq 1 ]
  [[ "${output}" == *"tool: install failed"* ]]
  [ "$(_wget_count)" -eq 1 ]
  _assert_tmp_was_used
  [ ! -e "${STAMP}" ]
  _assert_root_empty
  [ "$(cat "${DEST}")" = "old" ]
  chmod 0755 "${_DL_BIN_DIR}"
  run _install_fetched_binary tool bin ""
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 2 ]
  [ "$(cat "${DEST}")" = "new" ]
  [ "$(cat "${STAMP}")" = "${URL} ${_FETCHED_SHA256}" ]
}

@test "_install_fetched_binary: a failing rename leaves dest, no .new, no stamp, and fails" {
  # tests/mocks/mv is the failure knob; the staged copy is made by the real install.
  export MOCK_MV_FAIL_ARGS=".new"
  run _install_fetched_binary tool bin ""
  [ "$status" -eq 1 ]
  [[ "${output}" == *"tool: install failed"* ]]
  # Positive control: the rename was attempted, so the absences below are a
  # failed rename cleaned up, not a rename never reached.
  grep -q "^mv -f ${DEST}.new ${DEST}\$" "${MOCK_CALLS_FILE}"
  [ "$(cat "${DEST}")" = "old" ]
  [ ! -e "${DEST}.new" ]
  [ ! -e "${STAMP}" ]
  _assert_root_empty
}

@test "_install_fetched_binary: an unwritable stamp dir warns naming the path but still succeeds" {
  mkdir -p "${BATS_TEST_TMPDIR}/ro"
  chmod 0555 "${BATS_TEST_TMPDIR}/ro"
  export _DL_STAMP_DIR="${BATS_TEST_TMPDIR}/ro/stamps"
  run _install_fetched_binary tool bin ""
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 1 ]
  [ "$(cat "${DEST}")" = "new" ]
  [ ! -e "${_DL_STAMP_DIR}/tool" ]
  [[ "${output}" == *"could not write stamp ${_DL_STAMP_DIR}/tool"* ]]
  _assert_root_empty
}

@test "_install_fetched_binary: matching stamp and executable dest skips with the skip line and no fetch" {
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s\n' "${URL} ${_FETCHED_SHA256}" > "${STAMP}"
  run _install_fetched_binary tool bin ""
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 0 ]
  [[ "${output}" == *"tool: up to date (stamp ${STAMP}); rm it to force a re-install"* ]]
  [ "$(cat "${DEST}")" = "old" ]
}

@test "_install_fetched_binary: the same fixture without a stamp fetches exactly once" {
  run _install_fetched_binary tool bin ""
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 1 ]
  [[ "${output}" != *"up to date"* ]]
  [ "$(cat "${DEST}")" = "new" ]
}

@test "_install_fetched_binary: a stamp for a different URL fetches" {
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s\n' "https://example.invalid/other" > "${STAMP}"
  run _install_fetched_binary tool bin ""
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 1 ]
  [ "$(cat "${STAMP}")" = "${URL} ${_FETCHED_SHA256}" ]
}

@test "_install_fetched_binary: matching stamp but missing dest fetches" {
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s\n' "${URL} ${_FETCHED_SHA256}" > "${STAMP}"
  rm -f "${DEST}"
  run _install_fetched_binary tool bin ""
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 1 ]
  [ "$(cat "${DEST}")" = "new" ]
}

@test "_install_fetched_binary: zip success installs the member" {
  _make_zip
  run _install_fetched_binary tool zip tool
  [ "$status" -eq 0 ]
  [ "$(cat "${DEST}")" = "zipped" ]
  [ "$(cat "${STAMP}")" = "${URL} ${_FETCHED_SHA256}" ]
  _assert_tmp_was_used
  _assert_root_empty
}

@test "_install_fetched_binary: tar success installs a member in a subpath under a different dest name" {
  _make_tar
  run _install_fetched_binary tool tar pkg/bin/tool renamed
  [ "$status" -eq 0 ]
  [ "$(cat "${_DL_BIN_DIR}/renamed")" = "tarred" ]
  [ "$(cat "${_DL_STAMP_DIR}/tool")" = "${URL} ${_FETCHED_SHA256}" ]
  _assert_tmp_was_used
  _assert_root_empty
}

@test "_install_fetched_binary: unknown kind and missing or surplus arguments are rejected before any fetch, naming the call" {
  run _install_fetched_binary tool bogus ""
  [ "$status" -eq 1 ]
  [[ "${output}" == *"_install_fetched_binary: bad arguments: tool bogus "* ]]
  run _install_fetched_binary "" bin ""
  [ "$status" -eq 1 ]
  [[ "${output}" == *"_install_fetched_binary: bad arguments:  bin "* ]]
  run _install_fetched_binary tool "" bin ""
  [ "$status" -eq 1 ]
  [[ "${output}" == *"_install_fetched_binary: bad arguments: tool  bin "* ]]
  run _install_fetched_binary tool bin
  [ "$status" -eq 1 ]
  [[ "${output}" == *"_install_fetched_binary: bad arguments: tool bin"* ]]
  run _install_fetched_binary tool
  [ "$status" -eq 1 ]
  [[ "${output}" == *"_install_fetched_binary: bad arguments: tool"* ]]
  run _install_fetched_binary tool bin "" one two
  [ "$status" -eq 1 ]
  [[ "${output}" == *"_install_fetched_binary: bad arguments: tool bin  one two"* ]]
  [ "$(_wget_count)" -eq 0 ]
  [ ! -e "${_DL_BIN_DIR}/bin" ]
  [ "$(cat "${DEST}")" = "old" ]
}

_assert_extract_failed_clean() {
  [ "$status" -eq 1 ]
  [[ "${output}" == *"tool: extract failed"* ]]
  [ "$(_wget_count)" -eq 1 ]
  _assert_tmp_was_used
  [ ! -e "${STAMP}" ]
  _assert_root_empty
  [ "$(cat "${DEST}")" = "old" ]
}

@test "_install_fetched_binary: a tar member that is a symlink is refused" {
  local _src="${BATS_TEST_TMPDIR}/lsrc"
  mkdir -p "${_src}/pkg/bin"
  printf 'secret' > "${_src}/real"
  chmod 0600 "${_src}/real"
  ln -s "${_src}/real" "${_src}/pkg/bin/tool"
  "${_DL_TAR_BIN}" -czf "${BATS_TEST_TMPDIR}/link.tgz" -C "${_src}" pkg
  export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/link.tgz"
  _seam_for "${MOCK_WGET_FILE}"
  run _install_fetched_binary tool tar pkg/bin/tool
  _assert_extract_failed_clean
}

@test "_install_fetched_binary: a tar member that is a directory is refused" {
  local _src="${BATS_TEST_TMPDIR}/dsrc"
  mkdir -p "${_src}/pkg/bin/tool"
  printf 'x' > "${_src}/pkg/bin/tool/inner"
  "${_DL_TAR_BIN}" -czf "${BATS_TEST_TMPDIR}/dir.tgz" -C "${_src}" pkg
  export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/dir.tgz"
  _seam_for "${MOCK_WGET_FILE}"
  run _install_fetched_binary tool tar pkg/bin/tool
  _assert_extract_failed_clean
}

@test "_install_fetched_binary: a tar lacking the member is refused" {
  _make_tar
  run _install_fetched_binary tool tar pkg/bin/missing
  _assert_extract_failed_clean
}

@test "_install_fetched_binary: a successful but empty download is refused" {
  : > "${BATS_TEST_TMPDIR}/empty"
  export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/empty"
  _seam_for "${MOCK_WGET_FILE}"
  run _install_fetched_binary tool bin ""
  _assert_extract_failed_clean
}

@test "_install_fetched_binary: an uncreatable workdir fails before any fetch" {
  mkdir -p "${BATS_TEST_TMPDIR}/ro2"
  chmod 0555 "${BATS_TEST_TMPDIR}/ro2"
  export _DL_TMP_ROOT="${BATS_TEST_TMPDIR}/ro2/tmp"
  run _install_fetched_binary tool bin ""
  [ "$status" -eq 1 ]
  [[ "${output}" == *"tool: workdir failed"* ]]
  [ "$(_wget_count)" -eq 0 ]
  [ "$(cat "${DEST}")" = "old" ]
  [ ! -e "${STAMP}" ]
}

# ── pinned form: refusals before any download ────────────────────────────────

# Real kind constants pointed at the fixture's own digest, seams off, so the
# builder -> pin -> verify path runs exactly as a caller's does.
_kind_real_pins() {
  unset _FETCHED_URL _FETCHED_SHA256
  local _s
  _s="$(sha256sum "${MOCK_WGET_FILE}")"
  _s="${_s%% *}"
  export _LINUX_ARCH=amd64
  export KIND_SHA256_AMD64="${_s}" KIND_SHA256_ARM64="${_s}"
  export KIND_SHA256_FOR_VER="${KIND_VER}"
  KIND_FIXTURE_SHA="${_s}"
  KIND_URL_EXPECTED="$(_release_asset_url kind "${_LINUX_ARCH}")"
}

_assert_refused_before_download() {
  [ "$status" -eq 1 ]
  [ "$(_wget_count)" -eq 0 ]
  [ ! -e "${_DL_STAMP_DIR}/${1}" ]
  [ -z "$(ls -A "${_DL_TMP_ROOT}")" ]
}

@test "_install_fetched_binary: an unknown tool is refused with no download" {
  unset _FETCHED_URL _FETCHED_SHA256
  export _LINUX_ARCH=amd64
  run _install_fetched_binary bogus bin bogus
  _assert_refused_before_download bogus
  [[ "${output}" == *"bogus: unknown tool"* ]]
}

@test "_install_fetched_binary: an unknown arch is refused with no download" {
  _kind_real_pins
  export _LINUX_ARCH=riscv64
  run _install_fetched_binary kind bin kind
  _assert_refused_before_download kind
  [[ "${output}" == *"kind: no pin for arch 'riscv64'"* ]]
}

@test "_install_fetched_binary: an unknown tool is refused at the pin lookup when only the URL is seamed" {
  # _FETCHED_URL bypasses the URL lookup, so the pin lookup is the only stage
  # left that can name the tool as unknown.
  unset _FETCHED_SHA256
  export _FETCHED_URL="${URL}" _LINUX_ARCH=amd64
  run _install_fetched_binary bogus bin bogus
  _assert_refused_before_download bogus
  [[ "${output}" == *"bogus: unknown tool"* ]]
}

@test "_install_fetched_binary: an unknown arch is refused at the pin lookup when only the URL is seamed" {
  unset _FETCHED_SHA256
  export _FETCHED_URL="${URL}" _LINUX_ARCH=riscv64
  run _install_fetched_binary kind bin kind
  _assert_refused_before_download kind
  [[ "${output}" == *"kind: no pin for arch 'riscv64'"* ]]
}

@test "_install_fetched_binary: a workdir that mkdir accepts but mktemp cannot create fails before any fetch" {
  if [ "$(id -u)" -eq 0 ]; then skip "running as root: a read-only directory does not stop mktemp"; fi
  mkdir -p "${BATS_TEST_TMPDIR}/ro3"
  chmod 0555 "${BATS_TEST_TMPDIR}/ro3"
  export _DL_TMP_ROOT="${BATS_TEST_TMPDIR}/ro3"
  run _install_fetched_binary tool bin ""
  [ "$status" -eq 1 ]
  [[ "${output}" == *"tool: workdir failed"* ]]
  [ "$(_wget_count)" -eq 0 ]
  [ "$(cat "${DEST}")" = "old" ]
  [ ! -e "${STAMP}" ]
  [ -z "$(ls -A "${_DL_TMP_ROOT}")" ]
}

@test "_install_fetched_binary: pins recorded for another version are refused" {
  _kind_real_pins
  export KIND_SHA256_FOR_VER="0.0.1"
  run _install_fetched_binary kind bin kind
  _assert_refused_before_download kind
  [[ "${output}" == *"kind: repo constants are inconsistent: pins are for 0.0.1, KIND_VER is ${KIND_VER}; fix lib/constants.sh in the repo (scripts/refresh-sha256-pins.sh kind)"* ]]
}

@test "_install_fetched_binary: a malformed pin is refused naming its variable" {
  _kind_real_pins
  export KIND_SHA256_AMD64="not-a-sha"
  run _install_fetched_binary kind bin kind
  _assert_refused_before_download kind
  [[ "${output}" == *"kind: KIND_SHA256_AMD64 is not a 64-hex sha256; refusing to download"* ]]
}

@test "_install_fetched_binary: a missing pin is refused" {
  _kind_real_pins
  export KIND_SHA256_AMD64=""
  run _install_fetched_binary kind bin kind
  _assert_refused_before_download kind
  [[ "${output}" == *"kind: KIND_SHA256_AMD64 is not a 64-hex sha256; refusing to download"* ]]
}

@test "_install_fetched_binary: the bats seam pin is checked for shape too" {
  export _FETCHED_SHA256="xyz"
  run _install_fetched_binary tool bin ""
  _assert_refused_before_download tool
  [[ "${output}" == *"tool: _FETCHED_SHA256 is not a 64-hex sha256; refusing to download"* ]]
}

# ── pinned form: verify stage ────────────────────────────────────────────────

@test "_install_fetched_binary: success prints sha256 verified and writes the two-field stamp" {
  run _install_fetched_binary tool bin ""
  [ "$status" -eq 0 ]
  [[ "${output}" == *"tool: sha256 verified"* ]]
  [ "$(cat "${STAMP}")" = "${URL} ${_FETCHED_SHA256}" ]
  [ "$(cat "${DEST}")" = "new" ]
}

@test "_install_fetched_binary: a wrong pin installs nothing and reports the real digest and URL" {
  local _real="${_FETCHED_SHA256}"
  export _FETCHED_SHA256
  _FETCHED_SHA256="$(printf 'x%.0s' {1..64} | tr 'x' 'a')"
  run _install_fetched_binary tool bin ""
  [ "$status" -eq 1 ]
  [[ "${output}" == *"tool: sha256 mismatch: _FETCHED_SHA256 expects ${_FETCHED_SHA256}, download is ${_real} from ${URL}; nothing installed, existing binary kept. Re-run; if it repeats at an unchanged version, upstream changed the asset: investigate before scripts/refresh-sha256-pins.sh --accept-changed tool"* ]]
  [ "$(_wget_count)" -eq 1 ]
  _assert_tmp_was_used
  [ "$(cat "${DEST}")" = "old" ]
  [ ! -e "${STAMP}" ]
  _assert_root_empty
  [[ "${output}" != *"sha256 verified"* ]]
}

@test "_install_fetched_binary: verify rc 3 says could-not-read, not mismatch" {
  _verify_sha256() { return 3; }
  run _install_fetched_binary tool bin ""
  [ "$status" -eq 1 ]
  [[ "${output}" == *"tool: could not read the download to verify it"* ]]
  [[ "${output}" != *"mismatch"* ]]
  [ "$(cat "${DEST}")" = "old" ]
  [ ! -e "${STAMP}" ]
  _assert_root_empty
}

@test "_install_fetched_binary: verify rc 126 says could-not-run with the rc, not mismatch" {
  _verify_sha256() { return 126; }
  run _install_fetched_binary tool bin ""
  [ "$status" -eq 1 ]
  [[ "${output}" == *"tool: sha256 check could not run (rc 126)"* ]]
  [[ "${output}" != *"mismatch"* ]]
  [ "$(cat "${DEST}")" = "old" ]
  [ ! -e "${STAMP}" ]
  _assert_root_empty
}

@test "_install_fetched_binary: a stamp with the right URL and an old sha reinstalls" {
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s %s\n' "${URL}" "$(printf 'b%.0s' {1..64})" > "${STAMP}"
  run _install_fetched_binary tool bin ""
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 1 ]
  [ "$(cat "${STAMP}")" = "${URL} ${_FETCHED_SHA256}" ]
}

@test "_install_fetched_binary: a URL-only legacy stamp reinstalls" {
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s\n' "${URL}" > "${STAMP}"
  run _install_fetched_binary tool bin ""
  [ "$status" -eq 0 ]
  [ "$(_wget_count)" -eq 1 ]
}

@test "_install_fetched_binary: kind downloads the builder URL and verifies with its real pin" {
  _kind_real_pins
  run _install_fetched_binary kind bin kind
  [ "$status" -eq 0 ]
  [ -n "${KIND_URL_EXPECTED}" ]
  grep -qF -- " ${KIND_URL_EXPECTED}" "${MOCK_CALLS_FILE}"
  [[ "${output}" == *"kind: sha256 verified"* ]]
  [ "$(cat "${_DL_STAMP_DIR}/kind")" = "${KIND_URL_EXPECTED} ${KIND_FIXTURE_SHA}" ]
}

# ── seams are bats-only ──────────────────────────────────────────────────────

@test "_install_fetched_binary: the _FETCHED_* seams are ignored outside bats" {
  _kind_real_pins
  # Seams exported but pointing somewhere else entirely; real pin is wrong.
  export _FETCHED_URL="https://example.invalid/seam" _FETCHED_SHA256="${KIND_FIXTURE_SHA}"
  export KIND_SHA256_AMD64
  KIND_SHA256_AMD64="$(printf 'c%.0s' {1..64})"
  local _saved="${BATS_TEST_TMPDIR}"
  BATS_TEST_TMPDIR=""
  run _install_fetched_binary kind bin kind
  BATS_TEST_TMPDIR="${_saved}"
  [ "$status" -eq 1 ]
  [ -n "${KIND_URL_EXPECTED}" ]
  grep -qF -- " ${KIND_URL_EXPECTED}" "${MOCK_CALLS_FILE}"
  [[ "${output}" == *"kind: sha256 mismatch: KIND_SHA256_AMD64 expects $(printf 'c%.0s' {1..64}), download is ${KIND_FIXTURE_SHA} from ${KIND_URL_EXPECTED}"* ]]
  run ! grep -qF "example.invalid/seam" "${MOCK_CALLS_FILE}"
}

@test "_install_fetched_binary: --resolve is no longer an option" {
  run _install_fetched_binary tool bin "" renamed --resolve
  [ "$status" -eq 1 ]
  [ "$(_wget_count)" -eq 0 ]
}

# ── archives are not extracted before the sha256 passes ──────────────────────

# An extractor stub that records each call, then delegates to the real tool.
_recording_extractor() {
  local _real="$1" _stub="${BATS_TEST_TMPDIR}/$2"
  printf '#!/usr/bin/env bash\nprintf "called\\n" >> "%s"\nexec "%s" "$@"\n' \
    "${BATS_TEST_TMPDIR}/extract-calls" "${_real}" > "${_stub}"
  chmod +x "${_stub}"
  : > "${BATS_TEST_TMPDIR}/extract-calls"
  printf '%s' "${_stub}"
}

_wrong_pin() {
  export _FETCHED_SHA256
  _FETCHED_SHA256="$(printf 'a%.0s' {1..64})"
}

@test "_install_fetched_binary: a wrong pin never runs unzip" {
  _make_zip
  export _DL_UNZIP_BIN
  _DL_UNZIP_BIN="$(_recording_extractor "${_DL_UNZIP_BIN}" unzip-rec)"
  _wrong_pin
  run _install_fetched_binary tool zip tool
  [ "$status" -eq 1 ]
  [[ "${output}" == *"tool: sha256 mismatch"* ]]
  [ ! -s "${BATS_TEST_TMPDIR}/extract-calls" ]
  [ "$(cat "${DEST}")" = "old" ]
  [ ! -e "${STAMP}" ]
  _assert_tmp_was_used
  _assert_root_empty
}

@test "_install_fetched_binary: a wrong pin never runs tar" {
  _make_tar
  export _DL_TAR_BIN
  _DL_TAR_BIN="$(_recording_extractor "${_DL_TAR_BIN}" tar-rec)"
  _wrong_pin
  run _install_fetched_binary tool tar pkg/bin/tool
  [ "$status" -eq 1 ]
  [[ "${output}" == *"tool: sha256 mismatch"* ]]
  [ ! -s "${BATS_TEST_TMPDIR}/extract-calls" ]
  [ "$(cat "${DEST}")" = "old" ]
  [ ! -e "${STAMP}" ]
  _assert_tmp_was_used
  _assert_root_empty
}

@test "_install_fetched_binary: the recording extractors ARE called when the pin is right (positive control)" {
  _make_zip
  export _DL_UNZIP_BIN
  _DL_UNZIP_BIN="$(_recording_extractor "${_DL_UNZIP_BIN}" unzip-rec)"
  run _install_fetched_binary tool zip tool
  [ "$status" -eq 0 ]
  [ -s "${BATS_TEST_TMPDIR}/extract-calls" ]
  _make_tar
  export _DL_TAR_BIN
  _DL_TAR_BIN="$(_recording_extractor "${_DL_TAR_BIN}" tar-rec)"
  rm -f "${STAMP}"
  run _install_fetched_binary tool tar pkg/bin/tool
  [ "$status" -eq 0 ]
  [ -s "${BATS_TEST_TMPDIR}/extract-calls" ]
}

# ── _sha256_check ────────────────────────────────────────────────────────────

@test "_sha256_check: a match is silent and returns 0" {
  run _sha256_check n "${FIXTURE}" VAR "${_FETCHED_SHA256}" "${URL}" "tail"
  [ "$status" -eq 0 ]
  [ -z "${output}" ]
}

@test "_sha256_check: a mismatch returns 1 and names variable, pin, actual, URL and tail" {
  local _bad
  _bad="$(printf 'a%.0s' {1..64})"
  run _sha256_check n "${FIXTURE}" VAR "${_bad}" "${URL}" "the-tail"
  [ "$status" -eq 1 ]
  [[ "${output}" == *"n: sha256 mismatch: VAR expects ${_bad}, download is ${_FETCHED_SHA256} from ${URL}; the-tail"* ]]
}

@test "_sha256_check: a mismatch whose actual-hash read fails says unreadable" {
  local _bad
  _bad="$(printf 'a%.0s' {1..64})"
  sha256sum() { return 1; }
  run _sha256_check n "${FIXTURE}" VAR "${_bad}" "${URL}" "the-tail"
  [ "$status" -eq 1 ]
  [[ "${output}" == *"download is unreadable from ${URL}"* ]]
}

@test "_sha256_check: rc 3 passes through with its own message" {
  run _sha256_check n "${BATS_TEST_TMPDIR}/absent" VAR "${_FETCHED_SHA256}" "${URL}" "t"
  [ "$status" -eq 3 ]
  [[ "${output}" == *"n: could not read the download to verify it"* ]]
  [[ "${output}" != *"mismatch"* ]]
}

@test "_sha256_check: rc 126 passes through with its own message" {
  _verify_sha256() { return 126; }
  run _sha256_check n "${FIXTURE}" VAR "${_FETCHED_SHA256}" "${URL}" "t"
  [ "$status" -eq 126 ]
  [[ "${output}" == *"n: sha256 check could not run (rc 126)"* ]]
  [[ "${output}" != *"mismatch"* ]]
}
