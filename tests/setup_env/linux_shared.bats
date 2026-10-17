#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_ID_U=1000
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/software_downloads"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# Writes a differentiated `apt` stub that answers per-subcommand (`update`
# vs `install`) so update-fails/install-succeeds and the reverse can be
# tested in isolation. tests/mocks/apt applies one exit code to every
# invocation regardless of args, which cannot express that split — and it
# is out of scope for this task to edit that shared mock. Prints the stub's
# directory so the caller can prepend it to PATH.
_apt_stub_path() {
  local _update_exit="$1" _install_exit="$2"
  local _dir _bash_bin
  _dir="$(mktemp -d -p "${BATS_TEST_TMPDIR}")"
  _bash_bin="$(command -v bash)"
  cat > "${_dir}/apt" << EOF
#!${_bash_bin}
printf 'apt %s\n' "\$*" >> "\${MOCK_CALLS_FILE}"
case "\$1" in
  update) exit ${_update_exit} ;;
  install) exit ${_install_exit} ;;
esac
exit 0
EOF
  chmod +x "${_dir}/apt"
  printf '%s' "${_dir}"
}

# ── update_system_packages — Noble path ─────────────────────────────────────

@test "update_system_packages: calls nala full-upgrade" {
  export UBUNTU=1
  run update_system_packages
  [ "$status" -eq 0 ]
  grep -q "nala full-upgrade" "${MOCK_CALLS_FILE}"
}

@test "update_system_packages: skips snap when snap is unavailable" {
  export UBUNTU=1

  # Override the seam rather than editing PATH. On Ubuntu 24.04 — what
  # ubuntu-latest runs — snap is /usr/bin/snap, so stripping "the directory
  # containing snap" strips bash, grep, sed, awk and mktemp with it. That
  # passed on macOS and failed in CI.
  _snap_available() { return 1; }

  run update_system_packages
  [ "$status" -eq 0 ]
  # Pin the apt half as having run, so the snap absence is the gate firing
  # rather than the whole function short-circuiting.
  grep -q "nala full-upgrade" "${MOCK_CALLS_FILE}"
  refute_grep "snap refresh" "${MOCK_CALLS_FILE}"
}

@test "update_system_packages: runs snap even when apt fails" {
  export UBUNTU=1
  export MOCK_APT_EXIT=1
  run update_system_packages
  [ "$status" -eq 1 ]
  grep -q "snap refresh" "${MOCK_CALLS_FILE}"
}

# ── update_apt_packages ──────────────────────────────────────────────────────

@test "update_apt_packages: propagates a failing apt update" {
  export UBUNTU=1
  export MOCK_APT_EXIT=1
  run update_apt_packages
  [ "$status" -eq 1 ]
  [[ "$output" != *"Updated apt packages"* ]]
}

@test "update_apt_packages: propagates a failing nala full-upgrade" {
  export UBUNTU=1
  export MOCK_NALA_EXIT=1
  run update_apt_packages
  [ "$status" -eq 1 ]
  [[ "$output" != *"Updated apt packages"* ]]
}

@test "update_apt_packages: succeeds and does not call snap" {
  export UBUNTU=1
  run update_apt_packages
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated apt packages"* ]]
  refute_grep "snap" "${MOCK_CALLS_FILE}"
}

# With stdout piped (run_update tees it) nala switches to raw dpkg mode and
# forks apt into its own process group. If that child still holds the terminal
# as stdin, job control stops it and the upgrade hangs forever. Reproduced on
# Ubuntu 26.04 from an interactive shell, 2026-09-16.
@test "update_apt_packages: nala full-upgrade and autoremove do not inherit the caller's stdin" {
  export UBUNTU=1
  local _stub_dir _stdin="${BATS_TEST_TMPDIR}/caller_stdin"
  _stub_dir="$(stdin_probe_stub_path nala)"
  printf 'CALLER-STDIN\n%.0s' 1 2 3 > "${_stdin}"
  PATH="${_stub_dir}:${PATH}" run update_apt_packages < "${_stdin}"
  [ "$status" -eq 0 ]
  grep -qE '^nala full-upgrade( .*)? -y( .*)? stdin=\[\]$' "${MOCK_CALLS_FILE}"
  grep -qF "nala autoremove -y stdin=[]" "${MOCK_CALLS_FILE}"
}

# With stdin closed, dpkg cannot answer a conffile prompt: it fails with "end of
# file on stdin at conffile prompt" and leaves the package unpacked but
# unconfigured. confdef+confold keeps the local edit and installs the package's
# copy beside it. Measured on claude 2026-09-16 through apt's install path.
@test "update_apt_packages: nala full-upgrade answers conffile prompts non-interactively" {
  export UBUNTU=1
  local _stub_dir
  _stub_dir="$(argv_probe_stub_path nala)"
  PATH="${_stub_dir}:${PATH}" run update_apt_packages
  [ "$status" -eq 0 ]
  grep -qxF 'argv: nala [full-upgrade][-o][Dpkg::Options::=--force-confdef][-o][Dpkg::Options::=--force-confold][-y]' "${MOCK_CALLS_FILE}"
}

# needrestart's apt Post-Invoke hook raises a debconf dialog when stdout is not a
# tty, and run_update tees stdout. sudo drops the caller's DEBIAN_FRONTEND, so the
# value has to be on the sudo command line for the hook's process to see it.
@test "update_apt_packages: nala full-upgrade sees DEBIAN_FRONTEND=noninteractive when the caller has none" {
  export UBUNTU=1
  unset DEBIAN_FRONTEND
  local _stub_dir
  _stub_dir="$(frontend_probe_stub_path nala)"
  PATH="${_stub_dir}:${PATH}" run update_apt_packages
  [ "$status" -eq 0 ]
  grep -qE '^frontend: nala full-upgrade .* DEBIAN_FRONTEND=noninteractive$' "${MOCK_CALLS_FILE}"
}

@test "update_apt_packages: nala autoremove sees DEBIAN_FRONTEND=noninteractive when the caller has none" {
  export UBUNTU=1
  unset DEBIAN_FRONTEND
  local _stub_dir
  _stub_dir="$(frontend_probe_stub_path nala)"
  PATH="${_stub_dir}:${PATH}" run update_apt_packages
  [ "$status" -eq 0 ]
  grep -qE '^frontend: nala autoremove .* DEBIAN_FRONTEND=noninteractive$' "${MOCK_CALLS_FILE}"
}

@test "update_apt_packages: the command-line value wins over a caller's DEBIAN_FRONTEND" {
  export UBUNTU=1
  export DEBIAN_FRONTEND=dialog
  local _stub_dir
  _stub_dir="$(frontend_probe_stub_path nala)"
  PATH="${_stub_dir}:${PATH}" run update_apt_packages
  [ "$status" -eq 0 ]
  grep -qE '^frontend: nala full-upgrade .* DEBIAN_FRONTEND=noninteractive$' "${MOCK_CALLS_FILE}"
  grep -qE '^frontend: nala autoremove .* DEBIAN_FRONTEND=noninteractive$' "${MOCK_CALLS_FILE}"
}

# ── update_snap_packages ─────────────────────────────────────────────────────

@test "update_snap_packages: propagates a failing snap refresh" {
  export UBUNTU=1
  export MOCK_SNAP_EXIT=1
  run update_snap_packages
  [ "$status" -eq 1 ]
  [[ "$output" != *"Updated snap packages"* ]]
}

@test "update_snap_packages: succeeds and does not call apt" {
  export UBUNTU=1
  run update_snap_packages
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated snap packages"* ]]
  refute_grep "apt " "${MOCK_CALLS_FILE}"
}

# ── install_zsh_linux ────────────────────────────────────────────────────────

@test "install_zsh_linux: skips when zsh and zsh-doc are both installed" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  export MOCK_DPKG_STATUS_zsh=ii
  export MOCK_DPKG_STATUS_zsh_doc=ii
  run install_zsh_linux
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  refute_grep "apt install" "${MOCK_CALLS_FILE}"
}

@test "install_zsh_linux: installs when zsh-doc is absent" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  export MOCK_DPKG_STATUS_zsh=ii
  unset MOCK_DPKG_STATUS_zsh_doc
  run install_zsh_linux
  [ "$status" -eq 0 ]
  grep -q "apt install zsh zsh-doc" "${MOCK_CALLS_FILE}"
}

@test "install_zsh_linux: installs when zsh is in rc state" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  export MOCK_DPKG_STATUS_zsh=rc
  # zsh-doc must read as installed here — otherwise its absence alone would
  # explain the guard failing, and the test would say nothing about `rc`.
  export MOCK_DPKG_STATUS_zsh_doc=ii
  run install_zsh_linux
  [ "$status" -eq 0 ]
  grep -q "apt install zsh zsh-doc" "${MOCK_CALLS_FILE}"
}

@test "install_zsh_linux: propagates a failing apt install" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  unset MOCK_DPKG_STATUS_zsh MOCK_DPKG_STATUS_zsh_doc
  export MOCK_APT_EXIT=1
  run install_zsh_linux
  [ "$status" -eq 1 ]
  [[ "$output" != *"Installed zsh"* ]]
}

@test "install_zsh_linux: warns but continues when apt update fails" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  unset MOCK_DPKG_STATUS_zsh MOCK_DPKG_STATUS_zsh_doc
  local _stub_dir _old_path
  _stub_dir="$(_apt_stub_path 1 0)"
  _old_path="${PATH}"
  export PATH="${_stub_dir}:${PATH}"
  run install_zsh_linux
  export PATH="${_old_path}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"apt update failed"* ]]
  [[ "$output" == *"Installed zsh"* ]]
}

@test "install_zsh_linux: apt install zsh sees DEBIAN_FRONTEND=noninteractive" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  unset MOCK_DPKG_STATUS_zsh MOCK_DPKG_STATUS_zsh_doc DEBIAN_FRONTEND
  local _stub_dir
  _stub_dir="$(frontend_probe_stub_path apt)"
  PATH="${_stub_dir}:${PATH}" run install_zsh_linux
  [ "$status" -eq 0 ]
  grep -qE '^frontend: apt install zsh zsh-doc .*DEBIAN_FRONTEND=noninteractive$' "${MOCK_CALLS_FILE}"
}

@test "install_zsh_linux: does not run dist-upgrade" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  unset MOCK_DPKG_STATUS_zsh MOCK_DPKG_STATUS_zsh_doc
  run install_zsh_linux
  [ "$status" -eq 0 ]
  # Pin the install path as the reason dist-upgrade is absent. Without this,
  # the guard short-circuiting produces the same absence and the assertion
  # passes while proving nothing -- confirmed by mutation.
  grep -q "apt install zsh zsh-doc" "${MOCK_CALLS_FILE}"
  refute_grep "dist-upgrade" "${MOCK_CALLS_FILE}"
}

# ── install_git_linux ────────────────────────────────────────────────────────

@test "install_git_linux: skips when git is already installed" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  export MOCK_DPKG_STATUS_git=ii
  run install_git_linux
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  refute_grep "apt install" "${MOCK_CALLS_FILE}"
}

@test "install_git_linux: apt install git sees DEBIAN_FRONTEND=noninteractive" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  unset MOCK_DPKG_STATUS_git DEBIAN_FRONTEND
  local _stub_dir
  _stub_dir="$(frontend_probe_stub_path apt)"
  PATH="${_stub_dir}:${PATH}" run install_git_linux
  [ "$status" -eq 0 ]
  grep -qE '^frontend: apt install git .*DEBIAN_FRONTEND=noninteractive$' "${MOCK_CALLS_FILE}"
}

@test "install_git_linux: installs when git is absent" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  unset MOCK_DPKG_STATUS_git
  run install_git_linux
  [ "$status" -eq 0 ]
  grep -q "apt install git" "${MOCK_CALLS_FILE}"
}

@test "install_git_linux: installs when git is in rc state" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  export MOCK_DPKG_STATUS_git=rc
  run install_git_linux
  [ "$status" -eq 0 ]
  grep -q "apt install git" "${MOCK_CALLS_FILE}"
}

@test "install_git_linux: propagates a failing apt install" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  unset MOCK_DPKG_STATUS_git
  export MOCK_APT_EXIT=1
  run install_git_linux
  [ "$status" -eq 1 ]
  [[ "$output" != *"Installed git"* ]]
}

@test "install_git_linux: warns but continues when PPA add fails" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  unset MOCK_DPKG_STATUS_git
  export MOCK_ADD_APT_REPO_EXIT=1
  run install_git_linux
  [ "$status" -eq 0 ]
  [[ "$output" == *"PPA add failed"* ]]
  [[ "$output" == *"Installed git"* ]]
}

@test "install_git_linux: does not run dist-upgrade" {
  unset MACOS
  export LINUX=1 UBUNTU=1
  unset MOCK_DPKG_STATUS_git
  run install_git_linux
  [ "$status" -eq 0 ]
  # See the zsh sibling: the install path must be pinned, or a short-circuiting
  # guard satisfies the absence assertion on its own.
  grep -q "apt install git" "${MOCK_CALLS_FILE}"
  refute_grep "dist-upgrade" "${MOCK_CALLS_FILE}"
}

# --- _apt_stale_signer_hosts ---

@test "_apt_stale_signer_hosts: resolute stale fixture yields docker host and NO_PUBKEY" {
  run _apt_stale_signer_hosts < "${REPO_ROOT}/tests/fixtures/apt/update-stale-rotated-resolute.txt"
  [ "$status" -eq 0 ]
  [ "$output" == "$(printf 'download.docker.com\tNO_PUBKEY')" ]
}

@test "_apt_stale_signer_hosts: clean fixture yields no output" {
  run _apt_stale_signer_hosts < "${REPO_ROOT}/tests/fixtures/apt/update-clean-resolute.txt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_apt_stale_signer_hosts: two stale hosts print in first-appearance order" {
  local _in="${BATS_TEST_TMPDIR}/two.txt"
  cat "${REPO_ROOT}/tests/fixtures/apt/update-stale-rotated-noble.txt" \
    "${REPO_ROOT}/tests/fixtures/apt/update-hashicorp-stale-rotated.txt" > "${_in}"
  run _apt_stale_signer_hosts < "${_in}"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == "download.docker.com"$'\t'* ]]
  [[ "${lines[1]}" == "apt.releases.hashicorp.com"$'\t'* ]]
}

@test "_apt_stale_signer_hosts: every URL on a considered line contributes a host" {
  local _line _in="${BATS_TEST_TMPDIR}/line.txt"
  _line="$(command grep -m1 -E '^(W|E|Warning|Error):.*NO_PUBKEY' "${REPO_ROOT}/tests/fixtures/apt/update-stale-rotated-resolute.txt")"
  [ -n "${_line}" ]
  printf '%s\n' "${_line}" | sed -E 's#(https?://[^ ]+)#\1 https://second.example/x#' > "${_in}"
  run _apt_stale_signer_hosts < "${_in}"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "$output" == *"download.docker.com"* ]]
  [[ "$output" == *"second.example"* ]]
}

@test "_apt_signer_awk_list: joined value has no newline (BWK awk rejects one in -v)" {
  run _apt_signer_awk_list "${APT_SIGNER_PREFIXES[@]}"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\n'* ]]
  [ "$output" == "W:|E:|Warning:|Error:" ]
  run _apt_signer_awk_list "${APT_SIGNER_TOKENS[@]}"
  [[ "$output" != *$'\n'* ]]
  [[ "$output" == "NO_PUBKEY|"*"|is no longer signed" ]]
}

# Real considered line from the stale fixture; the cases below derive from it with sed.
_stale_fixture_line() {
  command grep -m1 -E '^(W|E|Warning|Error):.*NO_PUBKEY' "${REPO_ROOT}/tests/fixtures/apt/update-stale-rotated-resolute.txt"
}

@test "_apt_stale_signer_hosts: line without a considered prefix yields nothing" {
  local _line
  _line="$(_stale_fixture_line | sed 's/^[A-Za-z]*: *//')"
  [[ "${_line}" == *"https://"* && "${_line}" == *NO_PUBKEY* ]]
  run _apt_stale_signer_hosts <<< "${_line}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_apt_stale_signer_hosts: prefix match is case-sensitive" {
  local _line
  _line="$(_stale_fixture_line | sed 's/^Warning:/WARNING:/')"
  [[ "${_line}" == "WARNING:"* && "${_line}" == *"https://"* ]]
  run _apt_stale_signer_hosts <<< "${_line}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_apt_stale_signer_hosts: considered line without a token yields nothing" {
  local _line
  _line="$(_stale_fixture_line | sed 's/NO_PUBKEY [0-9A-F]*//')"
  [[ "${_line}" == "Warning:"* && "${_line}" == *"https://"* && "${_line}" != *NO_PUBKEY* ]]
  run _apt_stale_signer_hosts <<< "${_line}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_apt_stale_signer_hosts: host is lowercased with userinfo and port removed" {
  local _line
  _line="$(_stale_fixture_line | sed 's#https://download.docker.com#https://user@DOWNLOAD.Docker.com:443#')"
  [[ "${_line}" == *"user@DOWNLOAD.Docker.com:443"* ]]
  run _apt_stale_signer_hosts <<< "${_line}"
  [ "$status" -eq 0 ]
  [ "$output" == "$(printf 'download.docker.com\tNO_PUBKEY')" ]
}

@test "_apt_stale_signer_hosts: CRLF line leaves no CR in a line-final host" {
  local _in="${BATS_TEST_TMPDIR}/crlf.txt"
  # The appended URL ends the line, so an unstripped CR would land in its host.
  printf '%s https://second.example\r\n' "$(_stale_fixture_line)" > "${_in}"
  run _apt_stale_signer_hosts < "${_in}"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[1]}" == "$(printf 'second.example\tNO_PUBKEY')" ]
}

@test "_apt_stale_signer_hosts: fails closed when the signer lists are undefined" {
  # Sources only linux_shared.sh, so lib/constants.sh's arrays are absent.
  run bash -c 'log_error() { printf "%s\n" "$*" >&2; }; source "$1/lib/linux_shared.sh"; _apt_stale_signer_hosts < "$1/tests/fixtures/apt/update-stale-rotated-resolute.txt"' _ "${REPO_ROOT}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"constants.sh"* ]]
}

# --- _apt_signer_remedy ---

# Asserts the remedy for $1 is exactly one line, rc 0, and leaves it in ${output}.
_remedy_one_line() {
  run _apt_signer_remedy "$1"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "_apt_signer_remedy: download.docker.com says re-run -t developer and blames the publisher on persistence" {
  _remedy_one_line download.docker.com
  [[ "$output" == *"-t developer"* ]]
  [[ "$output" == *"publisher's own key"* ]]
}

@test "_apt_signer_remedy: both k8s hosts share the docker re-fetch remedy" {
  local _h _docker
  _remedy_one_line download.docker.com
  _docker="${output}"
  for _h in pkgs.k8s.io prod-cdn.packages.k8s.io deb.releases.teleport.dev pkg.cloudflareclient.com download.virtualbox.org cli.github.com; do
    _remedy_one_line "${_h}"
    [[ "$output" == *"-t developer"* ]]
    [ "$output" == "${_docker}" ]
  done
}

@test "_apt_signer_remedy: nvidia.github.io names the keyring file to remove" {
  _remedy_one_line nvidia.github.io
  [[ "$output" == *"/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"* ]]
  [[ "$output" == *"-t developer"* ]]
}

@test "_apt_signer_remedy: packages.cloud.google.com names the source list to remove" {
  _remedy_one_line packages.cloud.google.com
  [[ "$output" == *"/etc/apt/sources.list.d/google-cloud-sdk.list"* ]]
  [[ "$output" == *"-t developer"* ]]
}

@test "_apt_signer_remedy: packages.opentofu.org stages, shows the fingerprint, then moves into place" {
  _remedy_one_line packages.opentofu.org
  [[ "$output" == *"mktemp -d"* ]]
  [[ "$output" == *"gpg --show-keys"* ]]
  [[ "$output" == *".gpg.new"* ]]
  [[ "$output" == *"/etc/apt/keyrings/opentofu-archive-keyring.gpg"* ]]
}

@test "_apt_signer_remedy: packages.microsoft.com points at MS_GPG_FPR" {
  _remedy_one_line packages.microsoft.com
  [[ "$output" == *"MS_GPG_FPR"* ]]
  [[ "$output" == *"keys/microsoft.asc"* ]]
}

@test "_apt_signer_remedy: download.opensuse.org points at ALBERT_GPG_FPR" {
  _remedy_one_line download.opensuse.org
  [[ "$output" == *"ALBERT_GPG_FPR"* ]]
}

@test "_apt_signer_remedy: an unknown host gets the no-remedy text" {
  _remedy_one_line example.invalid
  [[ "$output" == *"no remedy for this host"* ]]
}

@test "_apt_signer_remedy: apt.releases.hashicorp.com has no arm and falls to the unknown text" {
  local _unknown
  _remedy_one_line example.invalid
  _unknown="${output}"
  _remedy_one_line apt.releases.hashicorp.com
  [ "$output" == "${_unknown}" ]
}
