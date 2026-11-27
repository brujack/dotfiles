#!/usr/bin/env bats
# Seams that choose a path read or written as root, or the binary that extracts
# what lands in a root-owned directory, are honoured only under bats
# (BATS_TEST_TMPDIR non-empty). Outside bats the production value is used even
# when the variable is exported (_bats_seam, lib/helpers.sh).
#
# SAFETY. tests/mocks/sudo EXECS real commands, and `install`, `ln` and `mv`
# pass through to the real binary, so every outside-bats test shadows sudo (and
# any other step that could write or fetch) with a recorder FUNCTION; the suite
# hook (tests/helpers/suite_isolation.bash) also puts a refusing sudo stub first
# on PATH. Nothing here WRITES to the host's /etc, /usr/local or /usr/share, and
# no test needs a host file to exist. The functions under test still make
# read-only existence probes of production paths (`[[ -f ]]`, `[[ -L ]]`, a
# glob), so a host file can steer which branch runs; assertions are therefore
# on recorded calls that every branch makes: a production path must appear and
# the exported seam path must never appear. Production DEFAULTS are pinned by
# recording each _bats_seam call (_spy_bats_seam), which needs no host file.

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
  export _DL_UNZIP_BIN="${_SEAM}/unzip-seam"
  export _APT_SOURCES_LIST="${_WORK}/no-sources.list"
  printf '#!/usr/bin/env bash\nprintf "SEAM-UNZIP %%s\\n" "$*" >> "${MOCK_CALLS_FILE}"\nexit 1\n' > "${_DL_UNZIP_BIN}"
  /bin/chmod +x "${_DL_UNZIP_BIN}"
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
  local _out="${output}"
  ! command grep -qF -- "${_SEAM}" "${MOCK_CALLS_FILE}" || {
    printf 'seam path recorded in calls:\n%s\n' "$(< "${MOCK_CALLS_FILE}")" >&2
    return 1
  }
  [[ "${_out}" != *"${_SEAM}"* ]]
}

# Record every _bats_seam call as "SEAM <seam value> | <default>", then run the
# real helper, so a test can pin the default a call site passes.
_spy_bats_seam() {
  eval "$(declare -f _bats_seam | sed '1s/_bats_seam/_real_bats_seam/')"
  _bats_seam() { _rec "SEAM $1 | $2"; _real_bats_seam "$@"; }
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
  # The live-source probe reads the production .sources file; shadowing grep
  # fixes the branch (no live source) and records which file it would read.
  grep() { _rec "grep $*"; return 1; }
  BATS_TEST_TMPDIR='' run _install_ubuntu_edge_source
  command grep -qF "grep -q ^URIs: /etc/apt/sources.list.d/microsoft-edge.sources" "${MOCK_CALLS_FILE}"
  command grep -qF "/usr/share/keyrings/microsoft-edge-bootstrap.gpg" "${MOCK_CALLS_FILE}"
  command grep -qF "sudo rm -f /etc/apt/sources.list.d/microsoft-edge.list /usr/share/keyrings/microsoft-edge-bootstrap.gpg" "${MOCK_CALLS_FILE}"
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

# ── production defaults, pinned at the call site ─────────────────────────────

@test "_install_ubuntu_go: the version probe's default root is /usr/local" {
  _spy_bats_seam
  unset _GO_BIN
  _install_go_from_tarball() { return 0; }
  go() { return 0; }
  BATS_TEST_TMPDIR='' run _install_ubuntu_go
  command grep -qxF "SEAM ${_GO_INSTALL_ROOT} | /usr/local" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_nvidia: the keyring and list defaults are the production paths" {
  _spy_bats_seam
  export _OVERRIDE_NVIDIA_GPU_PRESENT=0
  curl() { return 1; }
  dpkg() { return 1; }
  BATS_TEST_TMPDIR='' run _install_ubuntu_nvidia
  command grep -qxF "SEAM ${_OVERRIDE_NVIDIA_KEYRING} | ${NVIDIA_CONTAINER_KEYRING}" "${MOCK_CALLS_FILE}"
  command grep -qxF "SEAM ${_OVERRIDE_NVIDIA_LIST} | /etc/apt/sources.list.d/nvidia-container-toolkit.list" "${MOCK_CALLS_FILE}"
}

@test "_hashicorp_warn_handwritten_source: the default sources dir is /etc/apt/sources.list.d" {
  _spy_bats_seam
  BATS_TEST_TMPDIR='' run _hashicorp_warn_handwritten_source
  [ "$(command grep -cxF "SEAM ${_APT_SOURCES_DIR} | /etc/apt/sources.list.d" "${MOCK_CALLS_FILE}")" -eq 2 ]
}

@test "_hashicorp_warn_handwritten_source: a HashiCorp source in the seam dir is named under bats" {
  mkdir -p "${_APT_SOURCES_DIR}"
  printf 'deb https://apt.releases.hashicorp.com noble main\n' > "${_APT_SOURCES_DIR}/hand.list"
  run _hashicorp_warn_handwritten_source
  [[ "${output}" == *"${_APT_SOURCES_DIR}/hand.list also configures apt.releases.hashicorp.com"* ]]
}

@test "_install_fetched_binary: _DL_UNZIP_BIN is ignored outside bats, real unzip extracts" {
  wget() { _rec "wget $*"; : > "$2"; }
  unzip() {
    local _d
    while (($#)); do
      if [[ $1 == -d ]]; then _d="$2"; shift; fi
      shift
    done
    _rec "unzip -d ${_d}"
    printf 'payload' > "${_d}/kind"
  }
  _sha256_check() { return 0; }
  BATS_TEST_TMPDIR='' run _install_fetched_binary kind zip kind
  command grep -q "^unzip -d " "${MOCK_CALLS_FILE}"
  command grep -qF " /usr/local/bin/kind.new" "${MOCK_CALLS_FILE}"
  run ! command grep -q "SEAM-UNZIP" "${MOCK_CALLS_FILE}"
  _assert_seam_unused
}

# ── signature verifiers and trust anchors ────────────────────────────────────
# _MS_GPG_BIN, _MS_AR_BIN, _MS_KEY_PATH and _APT_KEY_GPG_BIN choose the verifier
# or the key ahead of a root `dpkg -i` / `sudo install`. An exported variable
# must not swap in a verifier that says "good" or a key the caller controls.
# Each outside-bats test points the seam at something that would CHANGE the
# verdict or record a call, then asserts the real tool decided. The real gpg and
# ar are read-only here (throwaway --homedir, HOME is a bats temp dir).

_ms_fixture_deb() { printf '%s' "${REPO_ROOT}/tests/fixtures/packages-microsoft-prod.deb"; }

# tests/mocks/gpg shadows the real gpg on PATH, so a bare `gpg` default would
# resolve to the mock; put the real gpg and gpgconf first instead.
_need_real_gpg() {
  local _t _p _sys="/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"
  mkdir -p "${_WORK}/real-bin"
  for _t in gpg gpgconf; do
    _p="$(PATH="${_sys}" command -v "${_t}")" || skip "${_t} not installed"
    ln -sf "${_p}" "${_WORK}/real-bin/${_t}"
  done
  export PATH="${_WORK}/real-bin:${PATH}"
}

# As above, plus GNU ar. Microsoft's .deb stores GNU-format member names that
# Apple's /usr/bin/ar cannot extract (it exits 0 having extracted nothing), so
# the same probe as linux_ubuntu.bats applies: skip on a Mac without GNU ar
# (Homebrew binutils' gar), fail elsewhere so a runner image without binutils
# cannot silently drop the verifier tests.
_need_real_gpg_ar() {
  _need_real_gpg
  local _c _p _gnu=""
  for _c in ar gar; do
    _p="$(PATH="/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin" command -v "${_c}")" || continue
    if "${_p}" --version 2> /dev/null | command grep -q 'GNU ar'; then
      _gnu="${_p}"
      break
    fi
  done
  if [[ -z ${_gnu} ]]; then
    [[ "$(uname -s)" == "Darwin" ]] && skip "no GNU ar: Apple's ar cannot read the GNU member names in Microsoft's .deb"
    printf 'GNU ar (binutils) is required to test _ms_verify_deb off macOS\n' >&2
    return 1
  fi
  ln -sf "${_gnu}" "${_WORK}/real-bin/ar"
}

# A gpg stand-in that records every call. --show-keys lists a primary key whose
# fingerprint is STUB_FPR; --dearmor copies stdin to -o <file> or stdout; every
# other call fails.
_make_gpg_stub() {
  cat > "${_SEAM}/gpg-stub" << 'STUB'
#!/usr/bin/env bash
printf 'SEAM-GPG %s\n' "$*" >> "${MOCK_CALLS_FILE}"
_out=""
_prev=""
for _a in "$@"; do
  [[ ${_prev} == -o ]] && _out="${_a}"
  _prev="${_a}"
done
case " $* " in
  *" --show-keys "*) printf 'pub:u:255:22:AAAA:1:::::\nfpr:::::::::%s:\n' "${STUB_FPR:-0}" ;;
  *" --dearmor "*) if [[ -n ${_out} ]]; then cat > "${_out}"; else cat; fi ;;
  *) exit 1 ;;
esac
STUB
  /bin/chmod +x "${_SEAM}/gpg-stub"
}

_make_ar_stub() {
  printf '#!/usr/bin/env bash\nprintf "SEAM-AR %%s\\n" "$*" >> "${MOCK_CALLS_FILE}"\nexit 1\n' > "${_SEAM}/ar-stub"
  /bin/chmod +x "${_SEAM}/ar-stub"
}

@test "_ms_verify_deb: _MS_GPG_BIN is honoured under bats" {
  _need_real_gpg_ar
  _make_gpg_stub
  _MS_GPG_BIN="${_SEAM}/gpg-stub" run _ms_verify_deb "$(_ms_fixture_deb)"
  [ "${status}" -ne 0 ]
  command grep -q '^SEAM-GPG ' "${MOCK_CALLS_FILE}"
}

@test "_ms_verify_deb: _MS_GPG_BIN is ignored outside bats, real gpg verifies" {
  _need_real_gpg_ar
  _make_gpg_stub
  _MS_GPG_BIN="${_SEAM}/gpg-stub" BATS_TEST_TMPDIR='' run _ms_verify_deb "$(_ms_fixture_deb)"
  [ "${status}" -eq 0 ]
  run ! command grep -q '^SEAM-GPG ' "${MOCK_CALLS_FILE}"
}

@test "_ms_verify_deb: _MS_AR_BIN is honoured under bats" {
  _need_real_gpg_ar
  _make_ar_stub
  _MS_AR_BIN="${_SEAM}/ar-stub" run _ms_verify_deb "$(_ms_fixture_deb)"
  [ "${status}" -ne 0 ]
  command grep -q '^SEAM-AR ' "${MOCK_CALLS_FILE}"
}

@test "_ms_verify_deb: _MS_AR_BIN is ignored outside bats, real ar extracts" {
  _need_real_gpg_ar
  _make_ar_stub
  _MS_AR_BIN="${_SEAM}/ar-stub" BATS_TEST_TMPDIR='' run _ms_verify_deb "$(_ms_fixture_deb)"
  [ "${status}" -eq 0 ]
  run ! command grep -q '^SEAM-AR ' "${MOCK_CALLS_FILE}"
}

@test "_ms_verify_deb: _MS_KEY_PATH is honoured under bats" {
  _need_real_gpg_ar
  printf 'not a key\n' > "${_SEAM}/bad.asc"
  _MS_KEY_PATH="${_SEAM}/bad.asc" run _ms_verify_deb "$(_ms_fixture_deb)"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"could not import ${_SEAM}/bad.asc"* ]]
}

@test "_ms_verify_deb: _MS_KEY_PATH is ignored outside bats, the vendored key verifies" {
  _need_real_gpg_ar
  printf 'not a key\n' > "${_SEAM}/bad.asc"
  _MS_KEY_PATH="${_SEAM}/bad.asc" BATS_TEST_TMPDIR='' run _ms_verify_deb "$(_ms_fixture_deb)"
  [ "${status}" -eq 0 ]
  _assert_seam_unused
}

@test "_keyring_has_pinned_fpr: _MS_GPG_BIN is honoured under bats" {
  _make_gpg_stub
  printf 'junk\n' > "${_WORK}/ring"
  mkdir -p "${_WORK}/home"
  STUB_FPR=PINNED _MS_GPG_BIN="${_SEAM}/gpg-stub" run _keyring_has_pinned_fpr "${_WORK}/ring" PINNED "${_WORK}/home"
  [ "${status}" -eq 0 ]
  command grep -q '^SEAM-GPG ' "${MOCK_CALLS_FILE}"
}

@test "_keyring_has_pinned_fpr: a forging _MS_GPG_BIN is ignored outside bats" {
  _need_real_gpg
  _make_gpg_stub
  printf 'junk\n' > "${_WORK}/ring"
  mkdir -p "${_WORK}/home"
  STUB_FPR=PINNED _MS_GPG_BIN="${_SEAM}/gpg-stub" BATS_TEST_TMPDIR='' run _keyring_has_pinned_fpr "${_WORK}/ring" PINNED "${_WORK}/home"
  [ "${status}" -ne 0 ]
  run ! command grep -q '^SEAM-GPG ' "${MOCK_CALLS_FILE}"
}

@test "_build_pinned_keyring: a forging _MS_GPG_BIN installs nothing outside bats" {
  _need_real_gpg
  _make_gpg_stub
  printf 'junk\n' > "${_WORK}/key"
  STUB_FPR=PINNED _MS_GPG_BIN="${_SEAM}/gpg-stub" run _build_pinned_keyring "${_WORK}/key" "${_WORK}/ring" PINNED
  [ "${status}" -eq 0 ]
  command grep -q '^sudo install ' "${MOCK_CALLS_FILE}"
  : > "${MOCK_CALLS_FILE}"
  STUB_FPR=PINNED _MS_GPG_BIN="${_SEAM}/gpg-stub" BATS_TEST_TMPDIR='' run _build_pinned_keyring "${_WORK}/key" "${_WORK}/ring" PINNED
  [ "${status}" -ne 0 ]
  run ! command grep -q '^SEAM-GPG ' "${MOCK_CALLS_FILE}"
  run ! command grep -q '^sudo install ' "${MOCK_CALLS_FILE}"
}

# The suite's setup() replaces _install_apt_keyring with a recorder; re-source the
# real one here (the recorders for sudo and the others stay).
_load_real_apt_keyring() {
  source "${REPO_ROOT}/lib/linux_ubuntu.sh"
  curl() {
    local _o
    while (($#)); do
      [[ $1 == -o ]] && _o="$2"
      shift
    done
    printf 'key' > "${_o}"
  }
}

@test "_install_apt_keyring: _APT_KEY_GPG_BIN is honoured under bats" {
  _make_gpg_stub
  _load_real_apt_keyring
  _APT_KEY_GPG_BIN="${_SEAM}/gpg-stub" run _install_apt_keyring https://example.invalid/k "${_WORK}/ring" armored
  [ "${status}" -eq 0 ]
  command grep -q '^SEAM-GPG ' "${MOCK_CALLS_FILE}"
}

@test "_install_apt_keyring: _APT_KEY_GPG_BIN is ignored outside bats, real gpg converts" {
  _need_real_gpg
  _make_gpg_stub
  _load_real_apt_keyring
  _APT_KEY_GPG_BIN="${_SEAM}/gpg-stub" BATS_TEST_TMPDIR='' run _install_apt_keyring https://example.invalid/k "${_WORK}/ring" armored
  [ "${status}" -ne 0 ]
  run ! command grep -q '^SEAM-GPG ' "${MOCK_CALLS_FILE}"
  run ! command grep -q '^sudo install ' "${MOCK_CALLS_FILE}"
}

# Edge and albert read the same seams. Both functions probe host files
# read-only (the live Edge .sources), so each test forces the branch it needs.

@test "_install_ubuntu_edge_source: _MS_KEY_PATH is ignored outside bats, the vendored key is used" {
  printf 'not a key\n' > "${_SEAM}/edge-key.asc"
  grep() { return 1; } # no live .sources: reach the bootstrap branch whatever the host holds
  _build_pinned_keyring() { _rec "KEY $1"; return 1; }
  _MS_KEY_PATH="${_SEAM}/edge-key.asc" BATS_TEST_TMPDIR='' run _install_ubuntu_edge_source
  command grep -qxF "KEY ${DOTFILES_REPO_ROOT}/keys/microsoft.asc" "${MOCK_CALLS_FILE}"
  _assert_seam_unused
}

@test "_install_ubuntu_edge_source: _MS_KEY_PATH is honoured under bats" {
  printf 'not a key\n' > "${_SEAM}/edge-key.asc"
  grep() { return 1; } # as above
  _build_pinned_keyring() { _rec "KEY $1"; return 1; }
  _MS_KEY_PATH="${_SEAM}/edge-key.asc" run _install_ubuntu_edge_source
  command grep -qxF "KEY ${_SEAM}/edge-key.asc" "${MOCK_CALLS_FILE}"
}

# Reaches the fingerprint-mismatch report, the only albert path that runs gpg.
_albert_mismatch_setup() {
  _make_gpg_stub
  lsb_release() { printf '24.04\n'; }
  curl() {
    local _o
    while (($#)); do
      [[ $1 == -o ]] && _o="$2"
      shift
    done
    printf 'junk' > "${_o}"
  }
  _build_pinned_keyring() { return 1; }
}

@test "_install_ubuntu_albert: _MS_GPG_BIN is ignored outside bats, real gpg lists the key" {
  _need_real_gpg
  _albert_mismatch_setup
  _MS_GPG_BIN="${_SEAM}/gpg-stub" BATS_TEST_TMPDIR='' run _install_ubuntu_albert
  [ "${status}" -eq 2 ]
  run ! command grep -q '^SEAM-GPG ' "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_albert: _MS_GPG_BIN is honoured under bats" {
  _need_real_gpg
  _albert_mismatch_setup
  _MS_GPG_BIN="${_SEAM}/gpg-stub" run _install_ubuntu_albert
  [ "${status}" -eq 2 ]
  command grep -q '^SEAM-GPG ' "${MOCK_CALLS_FILE}"
}

# ── AWS installer verifiers and trust anchor ─────────────────────────────────
# _AWS_GPG_BIN, _AWS_KEY_PATH and _AWS_PKGUTIL_BIN choose the verifier or the key
# ahead of `sudo ./aws/install` / `sudo installer`. Same contract as above: the
# real tool and the vendored key decide outside bats. The _make_gpg_stub stand-in
# records every call; _make_forging_gpg_stub also reports a good signature on --verify.

# A pkgutil stand-in that vouches for AWS's team ID and records the call.
_make_pkgutil_stub() {
  printf '#!/usr/bin/env bash\nprintf "SEAM-PKGUTIL %%s\\n" "$*" >> "${MOCK_CALLS_FILE}"\nprintf "Developer ID Installer: AMZN Mobile LLC (%s)\\n" "%s"\n' \
    "%s" "${AWSCLI_APPLE_TEAM_ID}" > "${_SEAM}/pkgutil-stub"
  /bin/chmod +x "${_SEAM}/pkgutil-stub"
}

# A gpg that accepts any import and reports VALIDSIG for the pinned fingerprint.
_make_forging_gpg_stub() {
  cat > "${_SEAM}/gpg-forge" << STUB
#!/usr/bin/env bash
printf 'SEAM-GPG %s\n' "\$*" >> "\${MOCK_CALLS_FILE}"
case " \$* " in
  *" --verify "*) printf '[GNUPG:] VALIDSIG ${AWSCLI_GPG_FPR} x\n' ;;
esac
exit 0
STUB
  /bin/chmod +x "${_SEAM}/gpg-forge"
}

_aws_payload() {
  printf 'payload\n' > "${_WORK}/awscli.zip"
  printf 'not a signature\n' > "${_WORK}/awscli.zip.sig"
}

@test "_aws_verify_zip: _AWS_GPG_BIN is honoured under bats" {
  _make_forging_gpg_stub
  _aws_payload
  _AWS_GPG_BIN="${_SEAM}/gpg-forge" run _aws_verify_zip "${_WORK}/awscli.zip" "${_WORK}/awscli.zip.sig"
  [ "${status}" -eq 0 ]
  command grep -q '^SEAM-GPG ' "${MOCK_CALLS_FILE}"
}

@test "_aws_verify_zip: a forging _AWS_GPG_BIN is ignored outside bats, real gpg rejects" {
  _need_real_gpg
  _make_forging_gpg_stub
  _aws_payload
  _AWS_GPG_BIN="${_SEAM}/gpg-forge" BATS_TEST_TMPDIR='' run _aws_verify_zip "${_WORK}/awscli.zip" "${_WORK}/awscli.zip.sig"
  [ "${status}" -ne 0 ]
  run ! command grep -q '^SEAM-GPG ' "${MOCK_CALLS_FILE}"
}

@test "_aws_verify_zip: _AWS_KEY_PATH is honoured under bats" {
  _need_real_gpg
  _aws_payload
  printf 'not a key\n' > "${_SEAM}/bad.asc"
  _AWS_KEY_PATH="${_SEAM}/bad.asc" run _aws_verify_zip "${_WORK}/awscli.zip" "${_WORK}/awscli.zip.sig"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"could not import the vendored key"* ]]
}

@test "_aws_verify_zip: _AWS_KEY_PATH is ignored outside bats, the vendored key is imported" {
  _need_real_gpg
  _aws_payload
  printf 'not a key\n' > "${_SEAM}/bad.asc"
  _AWS_KEY_PATH="${_SEAM}/bad.asc" BATS_TEST_TMPDIR='' run _aws_verify_zip "${_WORK}/awscli.zip" "${_WORK}/awscli.zip.sig"
  [ "${status}" -ne 0 ]
  [[ "${output}" != *"could not import the vendored key"* ]]
  [[ "${output}" == *"did not verify"* ]]
  _assert_seam_unused
}

@test "_aws_verify_pkg: _AWS_PKGUTIL_BIN is honoured under bats" {
  _make_pkgutil_stub
  _AWS_PKGUTIL_BIN="${_SEAM}/pkgutil-stub" run _aws_verify_pkg "${_WORK}/AWSCLIV2.pkg"
  [ "${status}" -eq 0 ]
  command grep -q '^SEAM-PKGUTIL ' "${MOCK_CALLS_FILE}"
}

# A recording pkgutil first on PATH stands for the default `pkgutil` on any OS
# (Linux has none; the suite's tests/mocks/pkgutil would otherwise decide).
@test "_aws_verify_pkg: a forging _AWS_PKGUTIL_BIN is ignored outside bats, PATH pkgutil decides" {
  _make_pkgutil_stub
  mkdir -p "${_WORK}/pk-bin"
  printf '#!/usr/bin/env bash\nprintf "PATH-PKGUTIL %%s\\n" "$*" >> "${MOCK_CALLS_FILE}"\nexit 1\n' > "${_WORK}/pk-bin/pkgutil"
  /bin/chmod +x "${_WORK}/pk-bin/pkgutil"
  PATH="${_WORK}/pk-bin:${PATH}" _AWS_PKGUTIL_BIN="${_SEAM}/pkgutil-stub" BATS_TEST_TMPDIR='' run _aws_verify_pkg "${_WORK}/AWSCLIV2.pkg"
  [ "${status}" -ne 0 ]
  command grep -q '^PATH-PKGUTIL ' "${MOCK_CALLS_FILE}"
  run ! command grep -q '^SEAM-PKGUTIL ' "${MOCK_CALLS_FILE}"
}

@test "_doctor_check_aws_key_expiry: _AWS_KEY_PATH is honoured under bats" {
  export HAS_AWS=1
  _AWS_KEY_PATH="${_SEAM}/absent.asc" run _doctor_check_aws_key_expiry
  [[ "${output}" == *"vendored key not found at ${_SEAM}/absent.asc"* ]]
}

@test "_doctor_check_aws_key_expiry: _AWS_KEY_PATH is ignored outside bats, the vendored key is read" {
  export HAS_AWS=1
  _need_real_gpg
  _AWS_KEY_PATH="${_SEAM}/absent.asc" BATS_TEST_TMPDIR='' run _doctor_check_aws_key_expiry
  [[ "${output}" != *"vendored key not found"* ]]
  [[ "${output}" == *"expires in"* ]]
  _assert_seam_unused
}

@test "_doctor_check_aws_key_expiry: _AWS_GPG_BIN is honoured under bats" {
  export HAS_AWS=1
  _make_gpg_stub
  _AWS_GPG_BIN="${_SEAM}/gpg-stub" run _doctor_check_aws_key_expiry
  command grep -q '^SEAM-GPG ' "${MOCK_CALLS_FILE}"
}

@test "_doctor_check_aws_key_expiry: _AWS_GPG_BIN is ignored outside bats, real gpg reads the key" {
  export HAS_AWS=1
  _need_real_gpg
  _make_gpg_stub
  _AWS_GPG_BIN="${_SEAM}/gpg-stub" BATS_TEST_TMPDIR='' run _doctor_check_aws_key_expiry
  # Positive control: only a gpg that read the key reaches either expiry branch
  # (a past expiry prints a negative count), so a missing default cannot pass.
  [[ "${output}" == *"expires in"* ]]
  run ! command grep -q '^SEAM-GPG ' "${MOCK_CALLS_FILE}"
}
