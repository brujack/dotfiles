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

# ── _install_ubuntu_base_packages ────────────────────────────────────────────

@test "_install_ubuntu_base_packages: installs hwe-24.04" {
  export NOBLE=1
  unset RESOLUTE HAS_SNAP
  run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
  grep -q "apt install.*linux-generic-hwe-24.04" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_base_packages: HAS_SNAP installs workstation snap packages" {
  export NOBLE=1
  unset RESOLUTE
  export HAS_SNAP=1
  run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
  grep -q "snap install" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_base_packages: no HAS_SNAP skips snap install" {
  export NOBLE=1
  unset RESOLUTE HAS_SNAP
  run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
  ! grep -q "snap install" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_base_packages: RESOLUTE installs hwe-26.04" {
  export RESOLUTE=1
  unset NOBLE HAS_SNAP
  run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
  grep -q "apt install.*linux-generic-hwe-26.04" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_base_packages: unsupported Ubuntu version returns 1" {
  unset NOBLE RESOLUTE HAS_SNAP
  run _install_ubuntu_base_packages
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsupported Ubuntu version"* ]]
}

# ── _install_ubuntu_pyenv ────────────────────────────────────────────────────

@test "_install_ubuntu_pyenv: calls curl to download installer" {
  run _install_ubuntu_pyenv
  [ "$status" -eq 0 ]
  grep -q "curl.*pyenv.run" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_pyenv: returns 1 when curl fails" {
  export MOCK_CURL_EXIT=1
  local _rc=0
  _install_ubuntu_pyenv || _rc=$?
  [ "${_rc}" -ne 0 ]
}

# ── _install_ubuntu_powershell ───────────────────────────────────────────────

@test "_install_ubuntu_powershell: calls wget for packages-microsoft-prod.deb" {
  run _install_ubuntu_powershell
  [ "$status" -eq 0 ]
  grep -q "wget.*packages-microsoft-prod.deb" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_powershell: skips wget when deb already downloaded" {
  touch "${HOME}/software_downloads/packages-microsoft-prod.deb"
  run _install_ubuntu_powershell
  [ "$status" -eq 0 ]
  ! grep -q "wget.*packages-microsoft-prod.deb" "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_go ───────────────────────────────────────────────────────

@test "_install_ubuntu_go: version <=1.20 calls add-apt-repository" {
  export GO_VER="1.20"
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  grep -q "add-apt-repository.*golang-backports" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_go: version >=1.21 calls wget for tarball" {
  export GO_VER="1.26"
  export GO_DOWNLOAD_FILENAME="go1.26.linux-amd64.tar.gz"
  export GO_DOWNLOAD_URL="https://dl.google.com/go/go1.26.linux-amd64.tar.gz"
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  grep -q "wget.*${GO_DOWNLOAD_FILENAME}" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_go: version >=1.21 skips wget when tarball already exists" {
  export GO_VER="1.26"
  export GO_DOWNLOAD_FILENAME="go1.26.linux-amd64.tar.gz"
  touch "${HOME}/software_downloads/${GO_DOWNLOAD_FILENAME}"
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  ! grep -q "wget.*${GO_DOWNLOAD_FILENAME}" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_go: prints success when go version matches after install" {
  export GO_VER="1.26"
  export GO_DOWNLOAD_FILENAME="go1.26.linux-amd64.tar.gz"
  export GO_DOWNLOAD_URL="https://dl.google.com/go/go1.26.linux-amd64.tar.gz"
  # Pre-create tarball so wget/tar are skipped
  touch "${HOME}/software_downloads/${GO_DOWNLOAD_FILENAME}"
  # Fake go binary that reports matching version
  local _bin_dir="${BATS_TEST_TMPDIR}/gobin"
  mkdir -p "${_bin_dir}"
  printf '#!/usr/bin/env bash\nprintf "go version go1.26 linux/amd64\\n"\n' > "${_bin_dir}/go"
  chmod +x "${_bin_dir}/go"
  export PATH="${_bin_dir}:${PATH}"
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  [[ "$output" == *"Go 1.26 is installed"* ]]
}

@test "_install_ubuntu_go: unsupported version returns 1" {
  export GO_VER="1.99"
  local _rc=0
  _install_ubuntu_go || _rc=$?
  [ "${_rc}" -ne 0 ]
}

# ── _install_ubuntu_rust ─────────────────────────────────────────────────────

@test "_install_ubuntu_rust: HAS_RUST unset does nothing" {
  unset HAS_RUST
  run _install_ubuntu_rust
  [ "$status" -eq 0 ]
  ! grep -q "rustup" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_rust: HAS_RUST set calls curl for rustup installer" {
  export HAS_RUST=1
  # Override PATH to a minimal set that excludes cargo bin dirs, so
  # command -v rustc/cargo returns empty and the install guard runs curl.
  local _orig_path="${PATH}"
  # Build a PATH that only contains the mocks dir and essential system dirs,
  # explicitly excluding any path component containing "cargo" or ".cargo".
  local _clean_path=""
  IFS=: read -ra _parts <<< "${PATH}"
  for _p in "${_parts[@]}"; do
    [[ "${_p}" == *cargo* ]] && continue
    [[ -z "${_clean_path}" ]] && _clean_path="${_p}" || _clean_path="${_clean_path}:${_p}"
  done
  export PATH="${_clean_path}"
  run _install_ubuntu_rust
  export PATH="${_orig_path}"
  [ "$status" -eq 0 ]
  grep -q "curl.*rustup.rs" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_rust: installs cargo-nextest when rust installed but nextest absent" {
  export HAS_RUST=1
  local _bin_dir="${BATS_TEST_TMPDIR}/fakebin"
  mkdir -p "${_bin_dir}"
  printf '#!/usr/bin/env bash\n' > "${_bin_dir}/rustc" && chmod +x "${_bin_dir}/rustc"
  printf '#!/usr/bin/env bash\n' > "${_bin_dir}/cargo" && chmod +x "${_bin_dir}/cargo"
  mkdir -p "${HOME}/.cargo/bin"
  # Strip any dir containing cargo-nextest from PATH so the absence guard runs
  local _clean_path=""
  IFS=: read -ra _parts <<< "${PATH}"
  for _p in "${_parts[@]}"; do
    [[ -x "${_p}/cargo-nextest" ]] && continue
    [[ -z "${_clean_path}" ]] && _clean_path="${_p}" || _clean_path="${_clean_path}:${_p}"
  done
  export PATH="${_bin_dir}:${_clean_path}"
  _install_ubuntu_rust
  grep -q "curl.*nexte.st" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_rust: skips cargo-nextest install when already present" {
  export HAS_RUST=1
  local _bin_dir="${BATS_TEST_TMPDIR}/fakebin"
  mkdir -p "${_bin_dir}"
  printf '#!/usr/bin/env bash\n' > "${_bin_dir}/rustc"        && chmod +x "${_bin_dir}/rustc"
  printf '#!/usr/bin/env bash\n' > "${_bin_dir}/cargo"        && chmod +x "${_bin_dir}/cargo"
  printf '#!/usr/bin/env bash\n' > "${_bin_dir}/cargo-nextest" && chmod +x "${_bin_dir}/cargo-nextest"
  mkdir -p "${HOME}/.cargo/bin"
  export PATH="${_bin_dir}:${PATH}"
  _install_ubuntu_rust
  ! grep -q "curl.*nexte.st" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_rust: sources .cargo/env when file exists" {
  export HAS_RUST=1
  local _bin_dir="${BATS_TEST_TMPDIR}/fakebin"
  mkdir -p "${_bin_dir}"
  printf '#!/usr/bin/env bash\n' > "${_bin_dir}/rustc"         && chmod +x "${_bin_dir}/rustc"
  printf '#!/usr/bin/env bash\n' > "${_bin_dir}/cargo"         && chmod +x "${_bin_dir}/cargo"
  printf '#!/usr/bin/env bash\n' > "${_bin_dir}/cargo-nextest" && chmod +x "${_bin_dir}/cargo-nextest"
  mkdir -p "${HOME}/.cargo/bin"
  printf '# cargo env stub\n' > "${HOME}/.cargo/env"
  export PATH="${_bin_dir}:${PATH}"
  run _install_ubuntu_rust
  [ "$status" -eq 0 ]
}

# ── _install_go_from_tarball ──────────────────────────────────────────────────

@test "_install_go_from_tarball: moves software_downloads/go to /usr/local/go when present" {
  export GO_VER="1.26"
  export GO_DOWNLOAD_FILENAME="go1.26.linux-amd64.tar.gz"
  export GO_DOWNLOAD_URL="https://dl.google.com/go/go1.26.linux-amd64.tar.gz"
  mkdir -p "${HOME}/software_downloads/go"
  export MOCK_SUDO_EXIT=1
  run _install_go_from_tarball
  [ "$status" -eq 0 ]
  grep -q "sudo mv.*software_downloads/go" "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_docker ───────────────────────────────────────────────────

@test "_install_ubuntu_docker: HAS_DOCKER unset does nothing" {
  unset HAS_DOCKER
  run _install_ubuntu_docker
  [ "$status" -eq 0 ]
  ! grep -q "apt install docker-ce" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_docker: HAS_DOCKER set installs docker-ce" {
  export HAS_DOCKER=1
  run _install_ubuntu_docker
  [ "$status" -eq 0 ]
  grep -q "apt install docker-ce" "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_k8s_tools ────────────────────────────────────────────────

@test "_install_ubuntu_k8s_tools: HAS_K8S calls wget for kind" {
  export HAS_K8S=1
  export KIND_VER="0.22.0"
  export KIND_URL="https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64"
  export KUBERNETES_VER="v1.29"
  export TELEPRESENCE_URL="https://app.getambassador.io/download/tel2/linux/amd64/latest/telepresence"
  unset HAS_SNAP
  run _install_ubuntu_k8s_tools
  [ "$status" -eq 0 ]
  grep -q "wget.*kind" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_k8s_tools: HAS_K8S skips kind wget when already downloaded" {
  export HAS_K8S=1
  export KIND_VER="0.22.0"
  export KIND_URL="https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64"
  export KUBERNETES_VER="v1.29"
  export TELEPRESENCE_URL="https://app.getambassador.io/download/tel2/linux/amd64/latest/telepresence"
  touch "${HOME}/software_downloads/kind_0.22.0"
  unset HAS_SNAP
  run _install_ubuntu_k8s_tools
  [ "$status" -eq 0 ]
  ! grep -q "wget.*kind_0.22.0" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_k8s_tools: no HAS_K8S skips kind and telepresence" {
  unset HAS_K8S HAS_SNAP
  export KUBERNETES_VER="v1.29"
  run _install_ubuntu_k8s_tools
  [ "$status" -eq 0 ]
  ! grep -q "wget.*kind" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_k8s_tools: HAS_SNAP installs helm via snap" {
  export HAS_SNAP=1
  export HAS_K8S=1
  export KIND_VER="0.22.0"
  export KIND_URL="https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64"
  export KUBERNETES_VER="v1.29"
  export TELEPRESENCE_URL="https://app.getambassador.io/download/tel2/linux/amd64/latest/telepresence"
  run _install_ubuntu_k8s_tools
  [ "$status" -eq 0 ]
  grep -q "snap install helm" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_k8s_tools: no HAS_SNAP installs helm via apt" {
  unset HAS_SNAP
  export HAS_K8S=1
  export KIND_VER="0.22.0"
  export KIND_URL="https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64"
  export KUBERNETES_VER="v1.29"
  export TELEPRESENCE_URL="https://app.getambassador.io/download/tel2/linux/amd64/latest/telepresence"
  run _install_ubuntu_k8s_tools
  [ "$status" -eq 0 ]
  grep -q "apt-get install helm" "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_hashicorp ────────────────────────────────────────────────

@test "_install_ubuntu_hashicorp: calls wget for consul when dir does not exist" {
  export CONSUL_VER="1.17.0"
  export VAULT_VER="1.15.0"
  export NOMAD_VER="1.7.0"
  export PACKER_VER="1.10.0"
  export VAGRANT_VER="2.4.0"
  export HASHICORP_URL="https://releases.hashicorp.com"
  run _install_ubuntu_hashicorp
  [ "$status" -eq 0 ]
  grep -q "wget.*consul" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_hashicorp: skips consul wget when dir already exists" {
  export CONSUL_VER="1.17.0"
  export VAULT_VER="1.15.0"
  export NOMAD_VER="1.7.0"
  export PACKER_VER="1.10.0"
  export VAGRANT_VER="2.4.0"
  export HASHICORP_URL="https://releases.hashicorp.com"
  mkdir -p "${HOME}/software_downloads/consul_1.17.0"
  run _install_ubuntu_hashicorp
  [ "$status" -eq 0 ]
  ! grep -q "wget.*consul_1.17.0" "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_cloud_tools ──────────────────────────────────────────────

@test "_install_ubuntu_cloud_tools: always calls apt install azure-cli" {
  export CF_TERRAFORMING_VER="0.13.0"
  export CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v0.13.0/cf-terraforming_0.13.0_linux_amd64.tar.gz"
  unset HAS_DEVTOOLS
  run _install_ubuntu_cloud_tools
  [ "$status" -eq 0 ]
  grep -q "apt install azure-cli" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_cloud_tools: HAS_DEVTOOLS installs teleport" {
  export HAS_DEVTOOLS=1
  export CF_TERRAFORMING_VER="0.13.0"
  export CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v0.13.0/cf-terraforming_0.13.0_linux_amd64.tar.gz"
  run _install_ubuntu_cloud_tools
  [ "$status" -eq 0 ]
  grep -q "apt install teleport" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_cloud_tools: no HAS_DEVTOOLS skips teleport" {
  unset HAS_DEVTOOLS
  export CF_TERRAFORMING_VER="0.13.0"
  export CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v0.13.0/cf-terraforming_0.13.0_linux_amd64.tar.gz"
  run _install_ubuntu_cloud_tools
  [ "$status" -eq 0 ]
  ! grep -q "apt install teleport" "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_brew_packages ────────────────────────────────────────────

@test "_install_ubuntu_brew_packages: calls brew_install_formula for core packages" {
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew install bat" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: HAS_DEVTOOLS installs ggshield" {
  export HAS_DEVTOOLS=1
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew install ggshield" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: no HAS_DEVTOOLS skips ggshield" {
  unset HAS_DEVTOOLS
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  ! grep -q "brew install ggshield" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: calls install_homebrew when brew is absent" {
  install_homebrew() { printf "install_homebrew_called\n"; }
  local _saved_path="${PATH}"
  export PATH="/usr/bin:/bin"
  run _install_ubuntu_brew_packages
  export PATH="${_saved_path}"
  [[ "$output" == *"install_homebrew_called"* ]]
}

@test "_install_ubuntu_brew_packages: calls brew trust for third-party taps including getagentseal and bun" {
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew trust.*getagentseal/codeburn" "${MOCK_CALLS_FILE}"
  grep -q "brew trust.*oven-sh/bun" "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_gui_tools ────────────────────────────────────────────────

@test "_install_ubuntu_gui_tools: HAS_DEVTOOLS installs virtualbox" {
  export HAS_DEVTOOLS=1
  export VIRTUALBOX_VER="virtualbox-7.0"
  unset HAS_SNAP
  run _install_ubuntu_gui_tools
  [ "$status" -eq 0 ]
  grep -q "apt install ${VIRTUALBOX_VER}" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: no HAS_DEVTOOLS skips virtualbox" {
  unset HAS_DEVTOOLS HAS_SNAP
  run _install_ubuntu_gui_tools
  [ "$status" -eq 0 ]
  ! grep -q "apt install virtualbox" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: HAS_SNAP installs albert" {
  export HAS_SNAP=1
  unset HAS_DEVTOOLS
  run _install_ubuntu_gui_tools
  [ "$status" -eq 0 ]
  grep -q "apt install albert" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: no HAS_SNAP skips albert and edge" {
  unset HAS_SNAP HAS_DEVTOOLS
  run _install_ubuntu_gui_tools
  [ "$status" -eq 0 ]
  ! grep -q "apt install albert" "${MOCK_CALLS_FILE}"
  ! grep -q "apt install microsoft-edge-stable" "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_misc ─────────────────────────────────────────────────────

@test "_install_ubuntu_misc: calls wget for docker-compose when file does not exist" {
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  unset HAS_DEVTOOLS
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  grep -q "wget.*docker-compose" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_misc: skips docker-compose wget when file already exists" {
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  touch "${HOME}/software_downloads/docker-compose_2.24.0"
  unset HAS_DEVTOOLS
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  ! grep -q "wget.*docker-compose_2.24.0" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_misc: HAS_DEVTOOLS installs yq" {
  export HAS_DEVTOOLS=1
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  grep -q "wget.*yq" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_misc: no HAS_DEVTOOLS skips yq" {
  unset HAS_DEVTOOLS
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  ! grep -q "wget.*yq" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_misc: calls nala autoremove" {
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  unset HAS_DEVTOOLS
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  grep -q "nala autoremove" "${MOCK_CALLS_FILE}"
}
