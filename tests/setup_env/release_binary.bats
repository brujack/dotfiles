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

@test "_install_pinned_release_binary: tarxz kind installs from a nested directory" {
  # NOTE: shellcheck and friends ship .tar.xz with the binary one level down
  # (shellcheck-v0.11.0/shellcheck), unlike the zip wrappers above whose
  # member sits at the archive root. Build a real archive with that shape so
  # the extraction runs for real -- tar and xz are not mocked here, same
  # reasoning as the zip test.
  local _payload_dir="${BATS_TEST_TMPDIR}/tarxz-payload/footool-v9.9.9"
  local _fixture_tar="${BATS_TEST_TMPDIR}/footool.tar.xz"
  mkdir -p "${_payload_dir}"
  printf '#!/usr/bin/env bash\nprintf "footool version 9.9.9\\n"\n' > "${_payload_dir}/footool"
  chmod +x "${_payload_dir}/footool"
  printf 'not the binary\n' > "${_payload_dir}/README.txt"
  (cd "${BATS_TEST_TMPDIR}/tarxz-payload" && tar -cJf "${_fixture_tar}" footool-v9.9.9)
  local _sha
  _sha="$(sha256sum "${_fixture_tar}" | awk '{print $1}')"

  local _shim="${BATS_TEST_TMPDIR}/tarxz-curl-shim"
  mkdir -p "${_shim}"
  cat > "${_shim}/curl" << EOF
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
cp "${_fixture_tar}" "\${out}"
exit 0
EOF
  chmod +x "${_shim}/curl"

  PATH="${_shim}:${PATH}" run _install_pinned_release_binary footool 9.9.9 \
    "https://example.invalid/footool.tar.xz" \
    "${_sha}" tarxz '^footool version 9\.9\.9$'
  [ "$status" -eq 0 ]
  [ -x "${_RELEASE_BIN_DIR}/footool" ]
  # The sibling file must NOT be installed -- a naive "extract everything and
  # take the first file" would pick README.txt on some tar orderings.
  [ ! -e "${_RELEASE_BIN_DIR}/README.txt" ]
  run "${_RELEASE_BIN_DIR}/footool"
  [[ "$output" == *"footool version 9.9.9"* ]]
}

@test "_install_pinned_release_binary: tarxz kind fails when the archive holds no matching binary" {
  local _payload_dir="${BATS_TEST_TMPDIR}/tarxz-bad/other-v1"
  local _fixture_tar="${BATS_TEST_TMPDIR}/bad.tar.xz"
  mkdir -p "${_payload_dir}"
  printf 'nothing useful\n' > "${_payload_dir}/NOTES.txt"
  (cd "${BATS_TEST_TMPDIR}/tarxz-bad" && tar -cJf "${_fixture_tar}" other-v1)
  local _sha
  _sha="$(sha256sum "${_fixture_tar}" | awk '{print $1}')"

  local _shim="${BATS_TEST_TMPDIR}/tarxz-bad-shim"
  mkdir -p "${_shim}"
  cat > "${_shim}/curl" << EOF
#!/usr/bin/env bash
out=""
while [[ \$# -gt 0 ]]; do
  if [[ "\$1" == "-o" ]]; then out="\$2"; shift 2; continue; fi
  shift
done
cp "${_fixture_tar}" "\${out}"
exit 0
EOF
  chmod +x "${_shim}/curl"

  PATH="${_shim}:${PATH}" run _install_pinned_release_binary footool 9.9.9 \
    "https://example.invalid/bad.tar.xz" \
    "${_sha}" tarxz '^footool version 9\.9\.9$'
  [ "$status" -eq 1 ]
  [ ! -e "${_RELEASE_BIN_DIR}/footool" ]
  # Name the branch, not just the rc. Deleting the not-found guard ALSO returns
  # 1 -- an empty _extracted makes the install step fail instead -- so
  # `status -eq 1` alone is satisfied by either cause and pins neither.
  # Mutation-confirmed: without this line, removing the guard leaves the test
  # green.
  [[ "$output" == *"not found in the extracted archive"* ]]
  [[ "$output" != *"install into"* ]]
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

@test "_install_pinned_release_binary: an HTTP failure is reported as a download failure, not a checksum mismatch" {
  # MOCK_CURL_EXIT above fails regardless of whether -f is on the command
  # line, so it cannot prove the invocation actually asked curl to fail on
  # HTTP error. MOCK_CURL_HTTP_STATUS only fails for an f-bearing form
  # (tests/setup_env/mocks_curl.bats) -- dropping -fsSL's f would silently
  # turn this into a "successful" empty download that fails at the checksum
  # step instead, with the wrong diagnostic.
  export MOCK_CURL_HTTP_STATUS=404
  run _install_pinned_release_binary footool 9.9.9 \
    "https://example.invalid/footool" \
    "0000000000000000000000000000000000000000000000000000000000000000" \
    raw '^footool version 9\.9\.9$'
  [ "$status" -eq 1 ]
  [ ! -e "${_RELEASE_BIN_DIR}/footool" ]
  [[ "$output" == *"download failed"* ]]
  [[ "$output" != *"sha256 mismatch"* ]]
}

@test "_install_pinned_release_binary: a malformed pinned sha256 fails closed before any download" {
  # Boundary: the pin itself must be a plausible 64-hex-char digest before
  # anything is trusted to verify against it. macOS /sbin/sha256sum exits 0
  # on a malformed checksum LINE (only warns on stderr, discarded by the
  # redirect), so without this guard an empty or typo'd pin would sail
  # through sha256sum -c on this platform specifically.
  export MOCK_CURL_STDOUT="whatever"
  run _install_pinned_release_binary footool 9.9.9 \
    "https://example.invalid/footool" \
    "not-a-valid-sha256" \
    raw '^footool version 9\.9\.9$'
  [ "$status" -eq 1 ]
  [ ! -e "${_RELEASE_BIN_DIR}/footool" ]
  [[ "$output" == *"pinned sha256"* ]]
  refute_grep 'curl' "${MOCK_CALLS_FILE}"
}

@test "_install_pinned_release_binary: failure path leaves no residue under _RELEASE_TMP_ROOT" {
  # _RELEASE_TMP_ROOT is the seam that makes this assertable at all: BSD
  # mktemp -d with no template ignores TMPDIR, so a TMPDIR-based version of
  # this test would be inert on the Studio, where this suite runs.
  local _tmp_root="${BATS_TEST_TMPDIR}/release-tmp-root"
  mkdir -p "${_tmp_root}"
  export _RELEASE_TMP_ROOT="${_tmp_root}"
  export MOCK_CURL_STDOUT="not the real payload"
  run _install_pinned_release_binary footool 9.9.9 \
    "https://example.invalid/footool" \
    "0000000000000000000000000000000000000000000000000000000000000000" \
    raw '^footool version 9\.9\.9$'
  [ "$status" -eq 1 ]
  [ -z "$(ls -A "${_tmp_root}")" ]
}

@test "_install_pinned_release_binary: defaults to /usr/local/bin when _RELEASE_BIN_DIR is unset" {
  unset _RELEASE_BIN_DIR
  # Recording (non-executing) install/sudo stubs: the point is only to
  # observe the destination path the helper resolves, never to touch the
  # real /usr/local/bin regardless of whether it happens to be writable on
  # this machine.
  local _shim="${BATS_TEST_TMPDIR}/default-dir-shim"
  mkdir -p "${_shim}"
  cat > "${_shim}/install" << EOF
#!/usr/bin/env bash
printf "install %s\n" "\$*" >> "${MOCK_CALLS_FILE}"
exit 0
EOF
  cp "${_shim}/install" "${_shim}/sudo"
  chmod +x "${_shim}/install" "${_shim}/sudo"

  local _payload="raw-payload-9.9.9"
  local _sha
  _sha="$(printf '%s' "${_payload}" | sha256sum | awk '{print $1}')"
  export MOCK_CURL_STDOUT="${_payload}"

  PATH="${_shim}:${PATH}" run _install_pinned_release_binary footool 9.9.9 \
    "https://example.invalid/footool" \
    "${_sha}" raw '^footool version 9\.9\.9$'
  [ "$status" -eq 0 ]
  grep -qF '/usr/local/bin/footool' "${MOCK_CALLS_FILE}"
}

@test "_install_pinned_release_binary: a non-writable destination routes install through sudo" {
  local _dest="${BATS_TEST_TMPDIR}/readonly-bin"
  mkdir -p "${_dest}"
  chmod 0555 "${_dest}"
  export _RELEASE_BIN_DIR="${_dest}"

  # A recording sudo stub, deliberately NOT tests/mocks/sudo -- that mock
  # execs the real command when it resolves on PATH, which would be a
  # genuine write here (tdd.md E2, the test's failing/passing path must be
  # inert regardless).
  local _sudo_shim="${BATS_TEST_TMPDIR}/sudo-shim"
  mkdir -p "${_sudo_shim}"
  cat > "${_sudo_shim}/sudo" << EOF
#!/usr/bin/env bash
printf "sudo %s\n" "\$*" >> "${MOCK_CALLS_FILE}"
exit 0
EOF
  chmod +x "${_sudo_shim}/sudo"

  local _payload="raw-payload-9.9.9"
  local _sha
  _sha="$(printf '%s' "${_payload}" | sha256sum | awk '{print $1}')"
  export MOCK_CURL_STDOUT="${_payload}"

  PATH="${_sudo_shim}:${PATH}" run _install_pinned_release_binary footool 9.9.9 \
    "https://example.invalid/footool" \
    "${_sha}" raw '^footool version 9\.9\.9$'
  [ "$status" -eq 0 ]
  grep -qF "sudo install -m 0755" "${MOCK_CALLS_FILE}"
  grep -qF "${_dest}/footool" "${MOCK_CALLS_FILE}"
}

@test "_install_pinned_release_binary: a failing sudo install returns 1 and installs nothing" {
  local _dest="${BATS_TEST_TMPDIR}/readonly-bin"
  mkdir -p "${_dest}"
  chmod 0555 "${_dest}"
  export _RELEASE_BIN_DIR="${_dest}"

  local _sudo_shim="${BATS_TEST_TMPDIR}/sudo-shim"
  mkdir -p "${_sudo_shim}"
  cat > "${_sudo_shim}/sudo" << EOF
#!/usr/bin/env bash
printf "sudo %s\n" "\$*" >> "${MOCK_CALLS_FILE}"
exit 1
EOF
  chmod +x "${_sudo_shim}/sudo"

  local _payload="raw-payload-9.9.9"
  local _sha
  _sha="$(printf '%s' "${_payload}" | sha256sum | awk '{print $1}')"
  export MOCK_CURL_STDOUT="${_payload}"

  PATH="${_sudo_shim}:${PATH}" run _install_pinned_release_binary footool 9.9.9 \
    "https://example.invalid/footool" \
    "${_sha}" raw '^footool version 9\.9\.9$'
  [ "$status" -eq 1 ]
  [ ! -e "${_dest}/footool" ]
}

@test "_install_pinned_release_binary: a failing non-sudo install returns 1 and installs nothing" {
  # Sibling of the sudo-failure test above, but for the writable-destination
  # branch (line 812's `[[ -w "${_dir}" ]]` true arm). This is the damaging
  # half: on a box where the operator owns _RELEASE_BIN_DIR (both claude and
  # workstation have /usr/local/bin as root:root, so this branch is
  # unreachable there today, but is kept deliberately -- see the comment at
  # the -w guard), a swallowed failure here reports success with nothing on
  # disk, and _install_ubuntu_misc's `|| log_warn` never fires.
  local _dest="${BATS_TEST_TMPDIR}/writable-bin"
  mkdir -p "${_dest}"
  export _RELEASE_BIN_DIR="${_dest}"

  # A recording install stub, deliberately not tests/mocks -- it must fail
  # every time rather than exec a real install (tdd.md E2).
  local _install_shim="${BATS_TEST_TMPDIR}/install-shim"
  mkdir -p "${_install_shim}"
  cat > "${_install_shim}/install" << EOF
#!/usr/bin/env bash
printf "install %s\n" "\$*" >> "${MOCK_CALLS_FILE}"
exit 1
EOF
  chmod +x "${_install_shim}/install"

  local _payload="raw-payload-9.9.9"
  local _sha
  _sha="$(printf '%s' "${_payload}" | sha256sum | awk '{print $1}')"
  export MOCK_CURL_STDOUT="${_payload}"

  PATH="${_install_shim}:${PATH}" run _install_pinned_release_binary footool 9.9.9 \
    "https://example.invalid/footool" \
    "${_sha}" raw '^footool version 9\.9\.9$'
  [ "$status" -eq 1 ]
  [[ "$output" == *"install into"* ]]
  [ ! -e "${_dest}/footool" ]
}

@test "_install_pinned_release_binary: unzip failure returns 1 before reaching install" {
  # The archive genuinely lacks the expected member -- unzip -o -q "${_artifact}"
  # "${_name}" -d "${_tmp}" has nothing to extract. The "!= *install into*"
  # half is what discriminates this arm from the install-failure test above:
  # without it, the install guard failing later on an empty _extracted would
  # satisfy the same bare "status -eq 1" assertion.
  local _payload_dir="${BATS_TEST_TMPDIR}/zip-payload-bad"
  local _fixture_zip="${BATS_TEST_TMPDIR}/footool-bad.zip"
  mkdir -p "${_payload_dir}"
  printf '#!/usr/bin/env bash\nprintf "footool version 9.9.9\\n"\n' > "${_payload_dir}/wrongname"
  chmod +x "${_payload_dir}/wrongname"
  (cd "${_payload_dir}" && zip -q "${_fixture_zip}" wrongname)
  local _sha
  _sha="$(sha256sum "${_fixture_zip}" | awk '{print $1}')"

  local _zip_curl_shim="${BATS_TEST_TMPDIR}/zip-curl-shim-bad"
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
  [ "$status" -eq 1 ]
  [[ "$output" == *"unzip failed"* ]]
  [[ "$output" != *"install into"* ]]
  [ ! -e "${_RELEASE_BIN_DIR}/footool" ]
}

@test "_install_pinned_release_binary: unknown kind returns 1" {
  local _payload="raw-payload-9.9.9"
  local _sha
  _sha="$(printf '%s' "${_payload}" | sha256sum | awk '{print $1}')"
  export MOCK_CURL_STDOUT="${_payload}"
  run _install_pinned_release_binary footool 9.9.9 \
    "https://example.invalid/footool" \
    "${_sha}" tarball '^footool version 9\.9\.9$'
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

@test "_install_ubuntu_shellcheck: no-op and no network reached when HAS_DEVTOOLS is unset" {
  unset HAS_DEVTOOLS
  run _install_ubuntu_shellcheck
  [ "$status" -eq 0 ]
  refute_grep 'curl' "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_shellcheck: passes the pinned amd64 URL, sha, kind and version regex" {
  export HAS_DEVTOOLS=1
  _LINUX_ARCH=amd64
  _install_pinned_release_binary() { printf '%s\n' "$*" >> "${MOCK_CALLS_FILE}"; }
  run _install_ubuntu_shellcheck
  [ "$status" -eq 0 ]
  # The whole argv, not a substring: the arch SPELLING is the part most likely
  # to be wrong, since shellcheck publishes x86_64 while _LINUX_ARCH says amd64.
  grep -qF 'shellcheck 0.11.0 https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.xz 8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198 tarxz ^version: 0\.11\.0$' "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_shellcheck: passes the pinned arm64 sha and the aarch64 URL" {
  export HAS_DEVTOOLS=1
  _LINUX_ARCH=arm64
  _install_pinned_release_binary() { printf '%s\n' "$*" >> "${MOCK_CALLS_FILE}"; }
  run _install_ubuntu_shellcheck
  [ "$status" -eq 0 ]
  grep -qF "shellcheck-v0.11.0.linux.aarch64.tar.xz 12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588" "${MOCK_CALLS_FILE}"
  # arm64 must NOT reuse the amd64 spelling or digest
  refute_grep 'x86_64' "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_shellcheck: unknown arch skips without attempting a download" {
  export HAS_DEVTOOLS=1
  _LINUX_ARCH=riscv64
  run _install_ubuntu_shellcheck
  [ "$status" -eq 0 ]
  refute_grep 'curl' "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_shellcheck: the version regex matches shellcheck's real --version output" {
  # NOTE: shellcheck prints a multi-line banner whose version line is `version: X.Y.Z`,
  # unlike tflint's `TFLint version X.Y.Z`. A regex copied from the tflint
  # wrapper would never match, so the skip-check would reinstall on every run.
  # Assert against the real binary's real output rather than a remembered shape.
  local _real
  _real="$(command -v shellcheck || true)"
  [ -n "${_real}" ] || skip "shellcheck not installed on this machine"
  local _ver_line
  _ver_line="$("${_real}" --version | grep '^version:')"
  [[ "${_ver_line}" =~ ^version:\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "_install_ubuntu_tflint: unknown arch skips without attempting a download" {
  export HAS_DEVTOOLS=1
  _LINUX_ARCH=riscv64
  run _install_ubuntu_tflint
  [ "$status" -eq 0 ]
  refute_grep 'curl' "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_tflint: honours _TFLINT_URL and _TFLINT_SHA256 overrides" {
  export HAS_DEVTOOLS=1
  export _TFLINT_URL="https://example.invalid/tflint-override.zip"
  export _TFLINT_SHA256="override-sha-tflint"
  _install_pinned_release_binary() { printf '%s\n' "$*" >> "${MOCK_CALLS_FILE}"; }
  run _install_ubuntu_tflint
  [ "$status" -eq 0 ]
  grep -qF "https://example.invalid/tflint-override.zip override-sha-tflint" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_tfsec: honours _TFSEC_URL and _TFSEC_SHA256 overrides" {
  export HAS_DEVTOOLS=1
  export _TFSEC_URL="https://example.invalid/tfsec-override"
  export _TFSEC_SHA256="override-sha-tfsec"
  _install_pinned_release_binary() { printf '%s\n' "$*" >> "${MOCK_CALLS_FILE}"; }
  run _install_ubuntu_tfsec
  [ "$status" -eq 0 ]
  grep -qF "https://example.invalid/tfsec-override override-sha-tfsec" "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_misc call sites are advisory ────────────────────────────

@test "linux_ubuntu.sh: _install_ubuntu_tflint and _install_ubuntu_tfsec call sites are each followed by || log_warn" {
  # Statically pin the call site against the source, not via a mocked run --
  # both wrappers are stubbed in linux_ubuntu.bats's own _install_ubuntu_misc
  # dispatcher tests, so a run-based assertion there would never see a
  # swapped `|| return 1`. Line numbers are derived with grep -n at test
  # time, never hardcoded (Task 4's precedent, tests/setup_env/developer.bats
  # "install_pyenv_rehash_hook is the line immediately before pyenv rehash").
  local _src="${BATS_TEST_DIRNAME}/../../lib/linux_ubuntu.sh"
  local _name
  for _name in _install_ubuntu_tflint _install_ubuntu_tfsec; do
    local _line _content
    _line="$(grep -n "^  ${_name} || " "${_src}" | cut -d: -f1)"
    if [ -z "${_line}" ]; then
      printf "no '%s || ...' call site found in %s\n" "${_name}" "${_src}" >&2
      return 1
    fi
    _content="$(sed -n "${_line}p" "${_src}")"
    if [[ "${_content}" != *"|| log_warn"* ]]; then
      printf "call site at line %s: %q does not contain || log_warn\n" "${_line}" "${_content}" >&2
      return 1
    fi
  done
}
