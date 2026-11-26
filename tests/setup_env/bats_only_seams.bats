#!/usr/bin/env bats
# Seams that choose a path read or written as root, or the binary that extracts
# what lands in a root-owned directory, are honoured only under bats
# (BATS_TEST_TMPDIR non-empty). Outside bats the production value is used even
# when the variable is exported (_bats_seam, lib/helpers.sh).
#
# SAFETY. tests/mocks/sudo EXECS real commands, and `install`, `ln` and `mv`
# pass through to the real binary, so every outside-bats test shadows sudo (and
# any other step that could write or fetch) with a recorder FUNCTION. Nothing
# here reads or writes the host's /etc, /usr/local or /usr/share; host files are
# never required to exist. Assertions are on recorded
# calls: a production path must appear (a path the function builds regardless of
# what the host holds) and the exported seam path must never appear.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  : > "${MOCK_CALLS_FILE}"
  export HOME="${BATS_TEST_TMPDIR}/home"
  # _SEAM holds every exported seam value; _WORK holds temp roots and fixtures,
  # so a recorded path under _SEAM can only come from a seam being honoured.
  export _SEAM="${BATS_TEST_TMPDIR}/seam"
  export _WORK="${BATS_TEST_TMPDIR}/work"
  mkdir -p "${HOME}" "${_SEAM}" "${_WORK}"

  export _DL_STAMP_DIR="${_WORK}/stamps"
  export _DL_TMP_ROOT="${_WORK}/dl-tmp"
  export _APT_KEY_TMP_ROOT="${_WORK}/key-tmp"
  export _RELEASE_TMP_ROOT="${_WORK}/rel-tmp"
  mkdir -p "${_DL_STAMP_DIR}" "${_DL_TMP_ROOT}" "${_APT_KEY_TMP_ROOT}" "${_RELEASE_TMP_ROOT}"

  # The seams under test, all pointed at _SEAM.
  export _GO_INSTALL_ROOT="${_SEAM}/go-root"
  export _DL_BIN_DIR="${_SEAM}/dl-bin"
  export _RELEASE_BIN_DIR="${_SEAM}/release-bin"
  export _TFENV_LINK_DIR="${_SEAM}/tfenv-links"
  export _OVERRIDE_NVIDIA_KEYRING="${_SEAM}/nvidia.gpg"
  export _OVERRIDE_NVIDIA_LIST="${_SEAM}/nvidia.list"
  export _APT_SOURCES_DIR="${_SEAM}/apt-sources"
  export _APT_KEYRINGS_DIR="${_SEAM}/apt-keyrings"
  export _APT_TRUSTED_DIR="${_SEAM}/apt-trusted"
  export _CF_SOURCES_LIST="${_SEAM}/cloudflare.list"
  export _EDGE_SOURCES_DIR="${_SEAM}/edge-sources"
  export _EDGE_BOOTSTRAP_KEYRING="${_SEAM}/edge.gpg"
  export _GH_CLI_KEYRING="${_SEAM}/gh.gpg"
  export _GH_CLI_SOURCES_LIST="${_SEAM}/gh.list"
  export _DL_TAR_BIN="${_SEAM}/tar-seam"
  printf '#!/usr/bin/env bash\nprintf "SEAM-TAR %%s\\n" "$*" >> "${MOCK_CALLS_FILE}"\nexit 1\n' > "${_DL_TAR_BIN}"
  /bin/chmod +x "${_DL_TAR_BIN}"
  : > "${MOCK_CALLS_FILE}"

  _LINUX_ARCH=amd64

  # Recorders. Functions beat both PATH mocks and real binaries.
  sudo() { _rec "sudo $*"; return 0; }
  _install_apt_keyring() { _rec "keyring $*"; return 0; }
  _write_apt_source_list() { _rec "srclist $*"; return 0; }
}

_rec() { printf '%s\n' "$*" >> "${MOCK_CALLS_FILE}"; }

# No recorded call and no output line may name a path under the seam directory.
_assert_seam_unused() {
  run ! grep -qF -- "${_SEAM}" "${MOCK_CALLS_FILE}"
  [[ "${output}" != *"${_SEAM}"* ]]
}

# ── _bats_seam ────────────────────────────────────────────────────────────────

@test "_bats_seam: prints the seam value under bats" {
  run _bats_seam "/seam/dir" "/prod/dir"
  [ "$status" -eq 0 ]
  [ "$output" = "/seam/dir" ]
}

@test "_bats_seam: prints the production default outside bats even when the seam is set" {
  BATS_TEST_TMPDIR='' run _bats_seam "/seam/dir" "/prod/dir"
  [ "$status" -eq 0 ]
  [ "$output" = "/prod/dir" ]
}

@test "_bats_seam: an empty seam value falls back to the default under bats" {
  run _bats_seam "" "/prod/dir"
  [ "$status" -eq 0 ]
  [ "$output" = "/prod/dir" ]
}

@test "_bats_seam: an empty seam value falls back to the default outside bats" {
  BATS_TEST_TMPDIR='' run _bats_seam "" "/prod/dir"
  [ "$status" -eq 0 ]
  [ "$output" = "/prod/dir" ]
}

# ── Go: _GO_INSTALL_ROOT, _DL_TAR_BIN ────────────────────────────────────────

@test "_install_go_from_tarball: _GO_INSTALL_ROOT and _DL_TAR_BIN are ignored outside bats" {
  local _src="${_WORK}/gosrc"
  mkdir -p "${_src}/go/bin"
  printf 'new' > "${_src}/go/bin/go"
  chmod +x "${_src}/go/bin/go"
  /usr/bin/tar -czf "${_WORK}/go.tgz" -C "${_src}" go
  wget() { _rec "wget $*"; /bin/cp "${_WORK}/go.tgz" "$2"; }
  tar() { _rec "tar $*"; /usr/bin/tar "$@"; }
  _go_verify() { return 0; }
  BATS_TEST_TMPDIR='' run _install_go_from_tarball
  # Production root: the swap steps name /usr/local/go whatever the host holds.
  grep -q "/usr/local/go" "${MOCK_CALLS_FILE}"
  grep -q "^tar -xzf" "${MOCK_CALLS_FILE}"
  run ! grep -q "SEAM-TAR" "${MOCK_CALLS_FILE}"
  _assert_seam_unused
}

@test "_install_ubuntu_go: the version probe ignores _GO_INSTALL_ROOT outside bats" {
  mkdir -p "${_GO_INSTALL_ROOT}/go/bin"
  printf '#!/usr/bin/env bash\nprintf "go version go0.0.7-seam linux/amd64\\n"\n' > "${_GO_INSTALL_ROOT}/go/bin/go"
  chmod +x "${_GO_INSTALL_ROOT}/go/bin/go"
  unset _GO_BIN
  _install_go_from_tarball() { return 0; }
  BATS_TEST_TMPDIR='' run _install_ubuntu_go
  [[ "${output}" != *"0.0.7-seam"* ]]
}

# ── _DL_BIN_DIR, _DL_TAR_BIN: stamped removal and fetched binaries ───────────

@test "_hashicorp_retire_stamped: removes under /usr/local/bin, never _DL_BIN_DIR, outside bats" {
  printf 'stamp\n' > "${_DL_STAMP_DIR}/consul"
  BATS_TEST_TMPDIR='' run _hashicorp_retire_stamped consul
  grep -qF "sudo rm -f /usr/local/bin/consul" "${MOCK_CALLS_FILE}"
  _assert_seam_unused
}

@test "_install_fetched_binary: installs to /usr/local/bin and extracts with real tar outside bats" {
  local _src="${_WORK}/kind-src"
  mkdir -p "${_src}"
  printf 'payload' > "${_src}/kind"
  /usr/bin/tar -czf "${_WORK}/kind.tgz" -C "${_src}" kind
  wget() { _rec "wget $*"; /bin/cp "${_WORK}/kind.tgz" "$2"; }
  tar() { _rec "tar $*"; /usr/bin/tar "$@"; }
  _sha256_check() { return 0; }
  BATS_TEST_TMPDIR='' run _install_fetched_binary kind tar kind
  grep -qF "sudo install -m 0755" "${MOCK_CALLS_FILE}"
  grep -qF " /usr/local/bin/kind.new" "${MOCK_CALLS_FILE}"
  grep -q "^tar -xzf" "${MOCK_CALLS_FILE}"
  run ! grep -q "SEAM-TAR" "${MOCK_CALLS_FILE}"
  _assert_seam_unused
}

# ── _RELEASE_BIN_DIR ─────────────────────────────────────────────────────────

_release_shadows() {
  printf 'payload' > "${_WORK}/footool.bin"
  curl() {
    local _a
    while (($#)); do
      if [[ $1 == -o ]]; then _a="$2"; shift; fi
      shift
    done
    /bin/cp "${_WORK}/footool.bin" "${_a}"
  }
  _sha256_check() { return 0; }
  install() { _rec "install $*"; return 0; }
  mv() { _rec "mv $*"; return 0; }
}

@test "_install_pinned_release_binary: _RELEASE_BIN_DIR is ignored outside bats" {
  _release_shadows
  BATS_TEST_TMPDIR='' run _install_pinned_release_binary footool 1.0 https://example.invalid/footool \
    "$(printf 'a%.0s' {1..64})" raw '^footool 1\.0$'
  grep -qF " /usr/local/bin/footool.new" "${MOCK_CALLS_FILE}"
  _assert_seam_unused
}

@test "_install_uv_pinned_for: still installs under HOME outside bats, whatever _RELEASE_BIN_DIR holds" {
  local _src="${_WORK}/uv-src/uv-x86_64-unknown-linux-gnu"
  mkdir -p "${_src}"
  printf 'payload' > "${_src}/uv"
  /usr/bin/tar -czf "${_WORK}/uv.tgz" -C "${_WORK}/uv-src" uv-x86_64-unknown-linux-gnu
  curl() {
    local _a
    while (($#)); do
      if [[ $1 == -o ]]; then _a="$2"; shift; fi
      shift
    done
    /bin/cp "${_WORK}/uv.tgz" "${_a}"
  }
  tar() { /usr/bin/tar "$@"; }
  _sha256_check() { return 0; }
  install() { _rec "install $*"; return 0; }
  mv() { _rec "mv $*"; return 0; }
  export _UNAME_M=x86_64
  BATS_TEST_TMPDIR='' run _install_uv_pinned_for Linux
  grep -qF "${HOME}/.local/share/dotfiles/pinned/uv-" "${MOCK_CALLS_FILE}"
  run ! grep -qF "/usr/local/bin" "${MOCK_CALLS_FILE}"
  _assert_seam_unused
}

# ── _TFENV_LINK_DIR ──────────────────────────────────────────────────────────

@test "_install_ubuntu_tfenv: links under /usr/local/bin, never _TFENV_LINK_DIR, outside bats" {
  export HAS_DEVTOOLS=1
  export _TFENV_ROOT="${_WORK}/tfenv-root"
  mkdir -p "${_TFENV_ROOT}/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${_TFENV_ROOT}/bin/tfenv"
  chmod +x "${_TFENV_ROOT}/bin/tfenv"
  printf '1.0.0\n' > "${_TFENV_ROOT}/version"
  ln() { _rec "ln $*"; return 0; }
  BATS_TEST_TMPDIR='' run _install_ubuntu_tfenv
  # A host that already links /usr/local/bin/tfenv gets a warning naming it
  # instead of an ln call; either way the production path is the one named.
  { cat "${MOCK_CALLS_FILE}"; printf '%s\n' "${output}"; } | grep -qF "/usr/local/bin/tfenv"
  _assert_seam_unused
}

# ── NVIDIA keyring and list ──────────────────────────────────────────────────

@test "_install_ubuntu_nvidia: _OVERRIDE_NVIDIA_KEYRING and _OVERRIDE_NVIDIA_LIST are ignored outside bats" {
  export _OVERRIDE_NVIDIA_GPU_PRESENT=0
  curl() {
    local _a
    while (($#)); do
      if [[ $1 == -o ]]; then _a="$2"; shift; fi
      shift
    done
    printf 'deb https://example.invalid/ stable main\n' > "${_a}"
  }
  dpkg() { return 1; }
  BATS_TEST_TMPDIR='' run _install_ubuntu_nvidia
  # daemon.json resolver is a positive control that the function ran to its end.
  grep -qF "sudo -H cat /etc/docker/daemon.json" "${MOCK_CALLS_FILE}"
  _assert_seam_unused
}

# ── apt dirs ─────────────────────────────────────────────────────────────────

@test "_install_ubuntu_k8s_tools: apt dirs are the production ones outside bats" {
  BATS_TEST_TMPDIR='' run _install_ubuntu_k8s_tools
  grep -qF "sudo rm -f /etc/apt/sources.list.d/helm-stable-debian.list" "${MOCK_CALLS_FILE}"
  grep -qF "/etc/apt/keyrings/kubernetes-apt-keyring.gpg" "${MOCK_CALLS_FILE}"
  grep -qF "/etc/apt/sources.list.d/kubernetes.list" "${MOCK_CALLS_FILE}"
  _assert_seam_unused
}

@test "_install_ubuntu_cloud_tools: apt dirs and _CF_SOURCES_LIST are the production ones outside bats" {
  export HAS_DEVTOOLS=1
  BATS_TEST_TMPDIR='' run _install_ubuntu_cloud_tools
  grep -qF "/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg" "${MOCK_CALLS_FILE}"
  grep -qF "/etc/apt/sources.list.d/cloudflare-client.list" "${MOCK_CALLS_FILE}"
  grep -qF "/usr/share/keyrings/teleport-pubkey.gpg" "${MOCK_CALLS_FILE}"
  grep -qF "/etc/apt/trusted.gpg.d/microsoft.asc.gpg" "${MOCK_CALLS_FILE}"
  _assert_seam_unused
}

@test "_install_ubuntu_albert: legacy cleanup uses the production apt dirs outside bats" {
  curl() { return 1; }
  BATS_TEST_TMPDIR='' run _install_ubuntu_albert
  grep -qF "sudo rm -f /etc/apt/trusted.gpg.d/home_manuelschneid3r.gpg /etc/apt/sources.list.d/home:manuelschneid3r.list" "${MOCK_CALLS_FILE}"
  _assert_seam_unused
}

@test "_install_ubuntu_gui_tools: virtualbox keyring and source use the production apt dirs outside bats" {
  export HAS_DEVTOOLS=1
  BATS_TEST_TMPDIR='' run _install_ubuntu_gui_tools
  grep -qF "/usr/share/keyrings/oracle-virtualbox-2016.gpg" "${MOCK_CALLS_FILE}"
  grep -qF "/etc/apt/sources.list.d/virtualbox.list" "${MOCK_CALLS_FILE}"
  _assert_seam_unused
}

@test "_install_ubuntu_misc: opentofu keyring and source use the production apt dirs outside bats" {
  export HAS_DEVTOOLS=1 _FORCE_OPENTOFU_INSTALL=1
  _install_fetched_binary() { return 0; }
  _install_ubuntu_shellcheck() { return 0; }
  _install_ubuntu_uv_pinned() { return 0; }
  _install_ubuntu_tflint() { return 0; }
  _install_ubuntu_tfsec() { return 0; }
  _install_ubuntu_tfenv() { return 0; }
  check_and_install_nala() { return 0; }
  BATS_TEST_TMPDIR='' run _install_ubuntu_misc
  grep -qF "sudo mkdir -p /etc/apt/keyrings" "${MOCK_CALLS_FILE}"
  grep -qF "/etc/apt/keyrings/opentofu-archive-keyring.gpg" "${MOCK_CALLS_FILE}"
  grep -qF "/etc/apt/sources.list.d/opentofu.list" "${MOCK_CALLS_FILE}"
  _assert_seam_unused
}

# ── edge ─────────────────────────────────────────────────────────────────────

@test "_install_ubuntu_edge_source: sources dir and bootstrap keyring are the production ones outside bats" {
  _build_pinned_keyring() { _rec "bpk $*"; return 1; }
  BATS_TEST_TMPDIR='' run _install_ubuntu_edge_source
  # Whichever branch the host's real edge .sources file selects, the keyring
  # named is the production one.
  grep -qF "/usr/share/keyrings/microsoft-edge-bootstrap.gpg" "${MOCK_CALLS_FILE}"
  _assert_seam_unused
}

# ── gh cli ───────────────────────────────────────────────────────────────────

@test "install_github_cli_linux: keyring and source list are the production ones outside bats" {
  export UBUNTU=1
  BATS_TEST_TMPDIR='' run install_github_cli_linux
  grep -qF "sudo mkdir -p /etc/apt/keyrings" "${MOCK_CALLS_FILE}"
  grep -qF "/etc/apt/keyrings/githubcli-archive-keyring.gpg" "${MOCK_CALLS_FILE}"
  grep -qF "/etc/apt/sources.list.d/github-cli.list" "${MOCK_CALLS_FILE}"
  _assert_seam_unused
}

# ── under bats the seams still work ──────────────────────────────────────────

@test "_install_ubuntu_k8s_tools: apt dir seams are honoured under bats" {
  run _install_ubuntu_k8s_tools
  grep -qF "${_SEAM}/apt-keyrings/kubernetes-apt-keyring.gpg" "${MOCK_CALLS_FILE}"
  grep -qF "${_SEAM}/apt-sources/kubernetes.list" "${MOCK_CALLS_FILE}"
}

@test "install_github_cli_linux: path seams are honoured under bats" {
  export UBUNTU=1
  run install_github_cli_linux
  grep -qF "${_SEAM}/gh.gpg" "${MOCK_CALLS_FILE}"
  grep -qF "${_SEAM}/gh.list" "${MOCK_CALLS_FILE}"
}
