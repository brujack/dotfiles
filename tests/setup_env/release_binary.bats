#!/usr/bin/env bats
# Tests for _install_pinned_release_binary (lib/linux_ubuntu.sh) and its two
# wrappers, _install_ubuntu_tflint and _install_ubuntu_tfsec.
#
# sha256sum, unzip and install are deliberately NOT mocked here -- only curl
# is, via a per-test shim rather than tests/mocks/ (load_mocks), so the
# checksum and extraction steps run for real (tdd.md pitfall F/E2, mirroring
# the _install_rustup_rs precedent in linux_ubuntu.bats). _RELEASE_BIN_DIR
# always points at a BATS_TEST_TMPDIR subdirectory so nothing touches
# /usr/local/bin and the install step never needs sudo.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  export _RELEASE_BIN_DIR="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${_RELEASE_BIN_DIR}"

  # curl-only shim: tests/mocks/curl symlinked at higher PATH precedence than
  # everything else, so sha256sum/unzip/install/mktemp all stay real
  # (shell.md: a shim directory holding only the binary you need, rather than
  # a PATH-mocks directory that also shadows unrelated tools).
  _curl_shim="$(mktemp -d -p "${BATS_TEST_TMPDIR}")"
  ln -s "${REPO_ROOT}/tests/mocks/curl" "${_curl_shim}/curl"
  export PATH="${_curl_shim}:${PATH}"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# ── _install_pinned_release_binary ───────────────────────────────────────────

@test "_install_pinned_release_binary: sha256 mismatch leaves the target directory empty and returns 1" {
  export MOCK_CURL_STDOUT="not the real payload"
  run _install_pinned_release_binary footool 9.9.9 \
    "https://example.invalid/footool" \
    "0000000000000000000000000000000000000000000000000000000000000000" \
    raw '^footool version 9\.9\.9$'
  [ "$status" -eq 1 ]
  [ ! -e "${_RELEASE_BIN_DIR}/footool" ]
}

@test "_install_pinned_release_binary: raw kind installs and the binary is executable" {
  local _payload="raw-payload-9.9.9"
  local _sha
  _sha="$(printf '%s' "${_payload}" | sha256sum | awk '{print $1}')"
  export MOCK_CURL_STDOUT="${_payload}"
  run _install_pinned_release_binary footool 9.9.9 \
    "https://example.invalid/footool" \
    "${_sha}" raw '^footool version 9\.9\.9$'
  [ "$status" -eq 0 ]
  [ -x "${_RELEASE_BIN_DIR}/footool" ]
}

@test "_install_pinned_release_binary: zip kind installs" {
  local _payload_dir="${BATS_TEST_TMPDIR}/zip-payload"
  local _fixture_zip="${BATS_TEST_TMPDIR}/footool.zip"
  mkdir -p "${_payload_dir}"
  printf '#!/usr/bin/env bash\nprintf "footool version 9.9.9\\n"\n' > "${_payload_dir}/footool"
  chmod +x "${_payload_dir}/footool"
  (cd "${_payload_dir}" && zip -q "${_fixture_zip}" footool)
  local _sha
  _sha="$(sha256sum "${_fixture_zip}" | awk '{print $1}')"

  # A local, test-only curl shim: copies the real fixture zip's bytes to the
  # -o target rather than the shared mock's MOCK_CURL_STDOUT string, which
  # cannot safely carry zip binary content through a shell variable. Does not
  # touch tests/mocks/curl.
  local _zip_curl_shim="${BATS_TEST_TMPDIR}/zip-curl-shim"
  mkdir -p "${_zip_curl_shim}"
  cat > "${_zip_curl_shim}/curl" << EOF
#!/usr/bin/env bash
out=""
while [[ \$# -gt 0 ]]; do
  if [[ "\$1" == "-o" ]]; then
    out="\$2"
    shift 2
    continue
  fi
  shift
done
cp "${_fixture_zip}" "\${out}"
exit 0
EOF
  chmod +x "${_zip_curl_shim}/curl"

  PATH="${_zip_curl_shim}:${PATH}" run _install_pinned_release_binary footool 9.9.9 \
    "https://example.invalid/footool.zip" \
    "${_sha}" zip '^footool version 9\.9\.9$'
  [ "$status" -eq 0 ]
  [ -x "${_RELEASE_BIN_DIR}/footool" ]
}

@test "_install_pinned_release_binary: skips when the installed binary already prints the pinned version line" {
  printf '#!/usr/bin/env bash\nprintf "footool version 9.9.9\\n"\n' > "${_RELEASE_BIN_DIR}/footool"
  chmod +x "${_RELEASE_BIN_DIR}/footool"
  run _install_pinned_release_binary footool 9.9.9 \
    "https://example.invalid/footool" \
    "0000000000000000000000000000000000000000000000000000000000000000" \
    raw '^footool version 9\.9\.9$'
  [ "$status" -eq 0 ]
  refute_grep 'curl' "${MOCK_CALLS_FILE}"
}

@test "_install_pinned_release_binary: no skip when only an out-of-date notice line contains the version (whole-line anchor)" {
  # Installed binary is an OLDER version whose second line happens to mention
  # the pinned target as a substring -- e.g. tflint's real "Your version is
  # out of date! The latest version is X" notice. A substring match would
  # wrongly treat this as already-installed-at-pin; the anchored regex must not.
  cat > "${_RELEASE_BIN_DIR}/footool" << 'EOF'
#!/usr/bin/env bash
printf "footool version 8.8.8\n"
printf "Your version is out of date! The latest version is footool version 9.9.9 (upgrade recommended)\n"
EOF
  chmod +x "${_RELEASE_BIN_DIR}/footool"
  local _payload="raw-payload-9.9.9"
  local _sha
  _sha="$(printf '%s' "${_payload}" | sha256sum | awk '{print $1}')"
  export MOCK_CURL_STDOUT="${_payload}"
  run _install_pinned_release_binary footool 9.9.9 \
    "https://example.invalid/footool" \
    "${_sha}" raw '^footool version 9\.9\.9$'
  [ "$status" -eq 0 ]
  grep -q 'curl' "${MOCK_CALLS_FILE}"
  [ -x "${_RELEASE_BIN_DIR}/footool" ]
}

@test "_install_pinned_release_binary: no skip when a PATH stub prints the pinned line but _RELEASE_BIN_DIR is empty" {
  # A stub on PATH (not in _RELEASE_BIN_DIR) prints the exact pinned version
  # line. The skip check must read _RELEASE_BIN_DIR/<name>, never the PATH
  # copy -- shell.md's absolute-path-default rule, applied to the read side.
  local _path_stub_dir="${BATS_TEST_TMPDIR}/path-stub"
  mkdir -p "${_path_stub_dir}"
  printf '#!/usr/bin/env bash\nprintf "footool version 9.9.9\\n"\n' > "${_path_stub_dir}/footool"
  chmod +x "${_path_stub_dir}/footool"

  local _payload="raw-payload-9.9.9"
  local _sha
  _sha="$(printf '%s' "${_payload}" | sha256sum | awk '{print $1}')"
  export MOCK_CURL_STDOUT="${_payload}"

  PATH="${_path_stub_dir}:${PATH}" run _install_pinned_release_binary footool 9.9.9 \
    "https://example.invalid/footool" \
    "${_sha}" raw '^footool version 9\.9\.9$'
  [ "$status" -eq 0 ]
  grep -q 'curl' "${MOCK_CALLS_FILE}"
  [ -x "${_RELEASE_BIN_DIR}/footool" ]
}

@test "_install_pinned_release_binary: download failure returns 1 and installs nothing" {
  export MOCK_CURL_EXIT=1
  run _install_pinned_release_binary footool 9.9.9 \
    "https://example.invalid/footool" \
    "0000000000000000000000000000000000000000000000000000000000000000" \
    raw '^footool version 9\.9\.9$'
  [ "$status" -eq 1 ]
  [ ! -e "${_RELEASE_BIN_DIR}/footool" ]
}

# ── _install_ubuntu_tflint / _install_ubuntu_tfsec: HAS_DEVTOOLS gate ───────

@test "_install_ubuntu_tflint: no-op and no network reached when HAS_DEVTOOLS is unset" {
  unset HAS_DEVTOOLS
  run _install_ubuntu_tflint
  [ "$status" -eq 0 ]
  [ ! -e "${_RELEASE_BIN_DIR}/tflint" ]
  refute_grep 'curl' "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_tflint: HAS_DEVTOOLS set reaches the download path" {
  export HAS_DEVTOOLS=1
  run _install_ubuntu_tflint
  # No matching real artifact behind the mock curl, so this fails the
  # checksum and returns 1 -- the point is that it TRIED, proving the gate
  # let it through rather than staying a no-op.
  grep -q 'curl' "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_tfsec: no-op and no network reached when HAS_DEVTOOLS is unset" {
  unset HAS_DEVTOOLS
  run _install_ubuntu_tfsec
  [ "$status" -eq 0 ]
  [ ! -e "${_RELEASE_BIN_DIR}/tfsec" ]
  refute_grep 'curl' "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_tfsec: HAS_DEVTOOLS set reaches the download path" {
  export HAS_DEVTOOLS=1
  run _install_ubuntu_tfsec
  grep -q 'curl' "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_tflint / _install_ubuntu_tfsec: wiring to the helper ────

@test "_install_ubuntu_tflint: passes the pinned amd64 URL, sha, kind and version regex" {
  export HAS_DEVTOOLS=1
  _LINUX_ARCH=amd64
  _install_pinned_release_binary() { printf '%s\n' "$*" >> "${MOCK_CALLS_FILE}"; }
  run _install_ubuntu_tflint
  [ "$status" -eq 0 ]
  grep -qF 'tflint 0.61.0 https://github.com/terraform-linters/tflint/releases/download/v0.61.0/tflint_linux_amd64.zip ca4e4e8cb7cc3436f2b6979e9c4fd4e2623a66fcca1ad1fe12f8669967636ae2 zip ^TFLint version 0\.61\.0$' "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_tflint: passes the pinned arm64 sha and URL" {
  export HAS_DEVTOOLS=1
  _LINUX_ARCH=arm64
  _install_pinned_release_binary() { printf '%s\n' "$*" >> "${MOCK_CALLS_FILE}"; }
  run _install_ubuntu_tflint
  [ "$status" -eq 0 ]
  grep -qF "tflint_linux_arm64.zip 999c25cfdb5208fe1133dec6b219e666a39fc2a7a0786a781dc9924ea5945ebf" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_tfsec: passes the pinned amd64 raw URL, sha, kind and version regex" {
  export HAS_DEVTOOLS=1
  _LINUX_ARCH=amd64
  _install_pinned_release_binary() { printf '%s\n' "$*" >> "${MOCK_CALLS_FILE}"; }
  run _install_ubuntu_tfsec
  [ "$status" -eq 0 ]
  grep -qF 'tfsec 1.28.14 https://github.com/aquasecurity/tfsec/releases/download/v1.28.14/tfsec-linux-amd64 a32d0799bbefababaa4fcd814da9f4d251cd932789590b99d1d5fcb89ace6f68 raw ^v1\.28\.14$' "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_tflint: unknown arch skips without attempting a download" {
  export HAS_DEVTOOLS=1
  _LINUX_ARCH=riscv64
  run _install_ubuntu_tflint
  [ "$status" -eq 0 ]
  refute_grep 'curl' "${MOCK_CALLS_FILE}"
}
