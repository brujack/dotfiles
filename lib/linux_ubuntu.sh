#!/usr/bin/env bash
# lib/linux_ubuntu.sh — Ubuntu-specific install functions

install_ubuntu_packages() {
  local _brew_rc
  _install_ubuntu_base_packages  || return 1
  _install_ubuntu_powershell     || return 1
  _install_ubuntu_go             || return 1
  _install_ubuntu_docker         || return 1
  # After docker: the container toolkit configures the docker runtime.
  _install_ubuntu_nvidia         || return 1
  _install_ubuntu_k8s_tools      || return 1
  _install_ubuntu_hashicorp      || return 1
  _install_ubuntu_cloud_tools    || return 1
  # Tri-state, mirroring install_git_hooks_all_repos: 0 clean, 1 hard failure,
  # 2 partial success with the failed packages named. A bare `|| return 1` here
  # would abort a whole fresh-machine bootstrap because one upstream formula was
  # briefly unavailable, which is the opposite of what a bootstrap should do.
  _install_ubuntu_brew_packages
  _brew_rc=$?
  if [[ ${_brew_rc} -eq 1 ]]; then
    return 1
  fi
  _install_ubuntu_rust           || return 1
  _install_ubuntu_gui_tools      || return 1
  _install_ubuntu_misc           || return 1
}

_install_ubuntu_base_packages() {
  sudo -H apt update
  if [[ -n ${NOBLE} ]]; then
    printf "Installing hwe, common, and 24.04 packages\\n"
    sudo -H DEBIAN_FRONTEND=noninteractive apt install --install-recommends linux-generic-hwe-24.04 -y
    check_and_install_nala
    # Strip comments/blank lines: xargs -a feeds every line to nala, and a
    # comment token like '--user' aborts the whole install ("No such option").
    grep -vE '^[[:space:]]*(#|$)' ./ubuntu_common_packages.txt | xargs -r sudo DEBIAN_FRONTEND=noninteractive nala install -y
    grep -vE '^[[:space:]]*(#|$)' ./ubuntu_2404_packages.txt | xargs -r sudo DEBIAN_FRONTEND=noninteractive nala install -y
  elif [[ -n ${RESOLUTE} ]]; then
    printf "Installing hwe, common, and 26.04 packages\\n"
    sudo -H DEBIAN_FRONTEND=noninteractive apt install --install-recommends linux-generic-hwe-26.04 -y
    check_and_install_nala
    grep -vE '^[[:space:]]*(#|$)' ./ubuntu_common_packages.txt | xargs -r sudo DEBIAN_FRONTEND=noninteractive nala install -y
    grep -vE '^[[:space:]]*(#|$)' ./ubuntu_2604_packages.txt | xargs -r sudo DEBIAN_FRONTEND=noninteractive nala install -y
  else
    log_error "Unsupported Ubuntu version: ${UBUNTU_VERSION:-unknown}"
    return 1
  fi

  if [[ -n ${HAS_SNAP} ]]; then
    printf "Installing workstation packages\\n"
    grep -vE '^[[:space:]]*(#|$)' ./ubuntu_workstation_packages.txt | xargs -r sudo DEBIAN_FRONTEND=noninteractive nala install -y

    printf "Installing workstation snap packages\\n"
    grep -vE '^[[:space:]]*(#|$)' ./ubuntu_workstation_snap_packages.txt | xargs -r sudo snap install

  fi
}

_install_ubuntu_powershell() {
  printf "Installing powershell Ubuntu\\n"
  # Microsoft publishes a 26.04 config (HTTP 200) whose `resolute` dist carries
  # ZERO powershell packages -- measured 2026-09-12, against 54 in 24.04/noble.
  # So `apt install powershell` fails with "Unable to locate package" even
  # though every step before it succeeded. Unlike the azure-cli and WARP cases
  # the fallback belongs on the CONFIG url, not on a dist codename.
  local _ms_rel="${_MS_CONFIG_REL:-$(lsb_release -rs)}"
  [[ -n "${RESOLUTE:-}" ]] && _ms_rel="24.04"
  if [[ ! -f ${HOME}/software_downloads/packages-microsoft-prod.deb ]]; then
    wget -O "${HOME}"/software_downloads/packages-microsoft-prod.deb \
      "https://packages.microsoft.com/config/ubuntu/${_ms_rel}/packages-microsoft-prod.deb"
    sudo -H dpkg -i "${HOME}"/software_downloads/packages-microsoft-prod.deb
    sudo apt update
    sudo -H add-apt-repository universe
    sudo -H DEBIAN_FRONTEND=noninteractive apt install powershell -y
    if [[ -x $(command -v pwsh) ]]; then
      printf "pwsh is installed\\n"
    fi
  fi
}

_install_go_from_tarball() {
  if [[ ! -f ${HOME}/software_downloads/${GO_DOWNLOAD_FILENAME} ]]; then
    wget -O "${HOME}"/software_downloads/"${GO_DOWNLOAD_FILENAME}" "${GO_DOWNLOAD_URL}"
    tar xvf "${HOME}"/software_downloads/"${GO_DOWNLOAD_FILENAME}" -C "${HOME}"/software_downloads/
    if [[ -d /usr/local/go ]]; then
      sudo rm -rf /usr/local/go
    fi
    if [[ -d ${HOME}/software_downloads/go ]]; then
      sudo mv "${HOME}"/software_downloads/go /usr/local/go
      sudo chmod 755 /usr/local/go
      sudo chown -R root:root /usr/local/go
    fi
    if [[ -d ${HOME}/software_downloads/go ]]; then
      rm -rf "${HOME}"/software_downloads/go
    fi
  fi
}

_install_ubuntu_go() {
  printf "Installing Go Ubuntu\\n"
  sudo -H apt update
  _install_go_from_tarball
  # /usr/local/go/bin reaches PATH only via 6_path.zsh, which interactive zsh
  # alone sources -- so during a provision this probe resolved nothing and
  # printed "go: command not found" twice. Prefer the absolute install path,
  # fall back to PATH so an existing `go` (and the suite's mock) still drives it.
  local _go_bin="${_GO_BIN:-}"
  if [[ -z "${_go_bin}" ]]; then
    if [[ -x /usr/local/go/bin/go ]]; then _go_bin=/usr/local/go/bin/go; else _go_bin=go; fi
  fi
  INSTALLED_GO_VER=$("${_go_bin}" version 2>/dev/null | awk '{print $3}' | sed 's/go//g')
  if [[ ${INSTALLED_GO_VER} == "${GO_VER}" ]]; then
    printf "Go %s is installed\\n" "${GO_VER}"
  fi
}

# Installs rustup.rs into ~/.cargo when absent, from a version-pinned rustup-init
# whose sha256 is verified BEFORE it is executed (ci.md's third-party binary rule);
# `curl … | sh` satisfies neither half.
#
# --no-modify-path is mandatory, not stylistic: rustup-init edits shell rc files by
# default, and on this fleet ~/.zshrc and ~/.zprofile are symlinks into this repo,
# so an unguarded run writes into the tracked working tree.
#
# Seams exist because every test runs against a fake HOME with no ~/.cargo/bin/rustup,
# so all of them would otherwise enter this path and reach the network — tdd.md E2.
# _RUSTUP_INIT_SHA256 is exposed rather than mocking sha256sum: there is no sha256sum
# mock, and supplying the expected digest keeps the real check running so a mismatch
# is genuinely exercised instead of stubbed away.
_install_rustup_rs() {
  local _cargo_bin="${_OVERRIDE_CARGO_BIN_DIR:-${HOME}/.cargo/bin}"
  if [[ -x "${_cargo_bin}/rustup" ]]; then
    return 0
  fi

  # Match on the machine type, normalising Apple's `arm64` to the kernel name
  # rustup publishes under. macOS never reaches this in production (the caller is
  # HAS_RUST + Ubuntu gated), but the bats suite runs on the Studio, and a case
  # statement that fails closed on the developer's own arch makes the suite
  # unrunnable locally for a reason that has nothing to do with the code.
  local _sha _machine
  _machine="$(uname -m)"
  case "${_machine}" in
    x86_64 | amd64) _sha="${RUSTUP_INIT_SHA256_X86_64}" ;;
    aarch64 | arm64) _sha="${RUSTUP_INIT_SHA256_AARCH64}" ;;
    *)
      log_error "no pinned rustup-init sha256 for ${_machine} — refusing an unverified download"
      return 1
      ;;
  esac
  _sha="${_RUSTUP_INIT_SHA256:-${_sha}}"

  local _tmp
  _tmp="$(mktemp -d)" || return 1

  if ! curl -fsSL -o "${_tmp}/rustup-init" "${_RUSTUP_INIT_URL:-${RUSTUP_INIT_URL}}"; then
    log_error "rustup-init download failed"
    rm -rf "${_tmp}"
    return 1
  fi

  if ! printf '%s  %s\n' "${_sha}" "${_tmp}/rustup-init" | sha256sum -c - > /dev/null 2>&1; then
    log_error "rustup-init sha256 mismatch — refusing to execute"
    rm -rf "${_tmp}"
    return 1
  fi

  chmod +x "${_tmp}/rustup-init" || {
    rm -rf "${_tmp}"
    return 1
  }

  if ! "${_RUSTUP_INIT_BIN:-${_tmp}/rustup-init}" -y --no-modify-path; then
    log_error "rustup-init failed"
    rm -rf "${_tmp}"
    return 1
  fi

  rm -rf "${_tmp}"
}

_install_ubuntu_rust() {
  if [[ -n ${HAS_RUST} ]]; then
    printf "Configuring Rust Ubuntu\\n"
    _install_rustup_rs || return 1
    if [[ -f ${HOME}/.cargo/env ]]; then
      . "${HOME}"/.cargo/env
    fi
    # Resolve explicitly rather than calling bare `rustup`: Homebrew also ships a
    # rustup on this fleet and it shadows ~/.cargo/bin on PATH, but brew builds it
    # with self-update compiled out, so `rustup self update` exits 1 there. Bare
    # calls would install the right binary and then not use it.
    local _rustup
    if [[ -x ${HOME}/.cargo/bin/rustup ]]; then
      _rustup="${HOME}/.cargo/bin/rustup"
    elif command -v rustup > /dev/null 2>&1; then
      _rustup="rustup"
    else
      log_warn "rustup not found; skipping Rust configuration"
      return 0
    fi
    "${_rustup}" self update || return 1
    "${_rustup}" update || return 1
    "${_rustup}" component add rust-analyzer || return 1
  fi
}

# Gated on HARDWARE, not on a profile capability. `claude` and `workstation` both
# map to linux_workstation, so a HAS_* flag would fire the driver install on any
# future GPU-less box with that profile, and on WSL2 where the driver lives on the
# Windows side. 10de is NVIDIA's PCI vendor ID.
_nvidia_gpu_present() {
  if [[ -n ${_OVERRIDE_NVIDIA_GPU_PRESENT+x} ]]; then
    return "${_OVERRIDE_NVIDIA_GPU_PRESENT}"
  fi
  lspci -nn 2> /dev/null | grep -qi '\[10de:'
}

# Driver comes from Ubuntu's own repo (610.57.04-0ubuntu0.26.04.3 on resolute), so
# it needs no third-party source. The container toolkit does, and that repo's GPG
# key is NOT checksum-pinned the way rustup-init is -- NVIDIA publishes no digest
# for it. The mitigation is `signed-by=`, which scopes the key to this one repo so
# it cannot vouch for anything else. Weaker than the rustup path, and recorded as a
# known limitation rather than left to look deliberate.
#
# Installing the driver does NOT bind it: nouveau holds the card until a reboot, so
# this warns rather than pretending success. Measured on claude 2026-09-12.
_install_ubuntu_nvidia() {
  if ! _nvidia_gpu_present; then
    return 0
  fi
  printf "Installing NVIDIA driver and container toolkit\\n"

  if ! dpkg -l "nvidia-driver-${NVIDIA_DRIVER_VER}" 2> /dev/null | grep -q '^ii'; then
    sudo -H DEBIAN_FRONTEND=noninteractive apt install -y "nvidia-driver-${NVIDIA_DRIVER_VER}" || return 1
    log_warn "NVIDIA driver installed — reboot required before the nvidia module replaces nouveau"
  fi

  local _keyring="${_OVERRIDE_NVIDIA_KEYRING:-${NVIDIA_CONTAINER_KEYRING}}"
  local _list="${_OVERRIDE_NVIDIA_LIST:-/etc/apt/sources.list.d/nvidia-container-toolkit.list}"

  if [[ ! -f ${_keyring} ]]; then
    curl -fsSL "${NVIDIA_CONTAINER_GPGKEY_URL}" | sudo -H gpg --dearmor -o "${_keyring}" || return 1
  fi

  if [[ ! -f ${_list} ]]; then
    # NVIDIA serves no per-release list -- ubuntu26.04 and ubuntu24.04 both 404 while
    # stable/deb returns 200 and is distro-agnostic. Measured 2026-09-12.
    curl -fsSL "${NVIDIA_CONTAINER_LIST_URL}" \
      | sed "s#deb https://#deb [signed-by=${_keyring}] https://#g" \
      | sudo -H tee "${_list}" > /dev/null || return 1
    sudo -H apt update || return 1
  fi

  if ! dpkg -l nvidia-container-toolkit 2> /dev/null | grep -q '^ii'; then
    sudo -H DEBIAN_FRONTEND=noninteractive apt install -y nvidia-container-toolkit || return 1
  fi
}

_install_ubuntu_docker() {
  if [[ -n ${HAS_DOCKER} ]]; then
    printf "Installing docker\\n"
    sudo mkdir -p /etc/apt/keyrings
    if [[ -f /etc/apt/keyrings/docker.gpg ]]; then
      sudo rm -f /etc/apt/keyrings/docker.gpg
    fi
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo -H apt update
    sudo -H DEBIAN_FRONTEND=noninteractive apt install docker-ce -y
    sudo -H DEBIAN_FRONTEND=noninteractive apt install docker-ce-cli -y
    sudo -H DEBIAN_FRONTEND=noninteractive apt install containerd.io -y
    sudo -H DEBIAN_FRONTEND=noninteractive apt install docker-buildx-plugin -y
    sudo -H DEBIAN_FRONTEND=noninteractive apt install docker-compose-plugin -y
    local _daemon_json="${_DOCKER_DAEMON_JSON:-/etc/docker/daemon.json}"
    if [[ ! -f ${_daemon_json} ]]; then
      printf "Configuring Docker for cgroup v2\\n"
      # SINGLE-quoted, so the escape is \n and not \\n. Every other printf in
      # this file is double-quoted -- `printf "Docker is installed\\n"` -- where
      # the shell collapses \\ to \ and printf then sees \n and emits a newline.
      # Inside single quotes nothing collapses: printf receives \\n, turns \\
      # into a literal backslash, and the n stays an n. The correct idiom
      # inverts when copied across the quoting boundary, and the result is
      # 46 bytes of valid JSON followed by two bytes of garbage.
      #
      # Measured on claude 2026-09-12: 48 bytes, `dockerd --validate` refusing
      # it with "invalid character '\\' after top-level value". It was latent
      # rather than visible -- dockerd had started before the file was written
      # and never re-read it -- so docker info, systemctl is-active and every
      # functional check passed, and only a cold start would have exposed it.
      # It surfaced when a second daemon (docker-ci) parsed the file on its own
      # cold start and restart-looped.
      printf '{"exec-opts": ["native.cgroupdriver=systemd"]}\n' | \
        sudo tee "${_daemon_json}" > /dev/null
      # Write, then prove the artifact is loadable. The escaping bug above was
      # only half the defect: the write had no post-condition, so a file dockerd
      # could not parse looked identical to a good one. dockerd holds whatever
      # config it read at start, so `docker info`, `systemctl is-active` and
      # every functional check keep passing over a broken file -- the only
      # observable is a cold start, which may be days away and will land on
      # whoever reboots rather than on whoever provisioned.
      #
      # dockerd --validate is the authoritative reader and exits non-zero with
      # the parse error. _DOCKER_VALIDATE_BIN seams it for the suite, which runs
      # on macs where dockerd does not exist -- same absolute-binary problem
      # _OVERRIDE_KEYCHAIN_BIN and _AWS_GPG_BIN carry.
      local _docker_validate="${_DOCKER_VALIDATE_BIN:-dockerd}"
      if command -v "${_docker_validate}" > /dev/null 2>&1; then
        if ! sudo "${_docker_validate}" --validate --config-file "${_daemon_json}" > /dev/null 2>&1; then
          log_error "${_daemon_json} did not validate — refusing to leave a config dockerd cannot parse"
          return 1
        fi
      else
        # Absent validator is not evidence the file is good. Say so rather than
        # passing silently, which is the shape that let the original bug ship.
        log_warn "dockerd not resolvable — ${_daemon_json} written but NOT validated"
      fi
    fi
    sudo usermod -a -G docker bruce
    if [[ -x $(command -v docker) ]]; then
      printf "Docker is installed\\n"
    fi
  fi
}

_install_ubuntu_k8s_tools() {
  if [[ -n ${HAS_K8S} ]]; then
    if [[ ! -f ${HOME}/software_downloads/kind_${KIND_VER} ]]; then
      printf "Installing kind\\n"
      wget -O "${HOME}"/software_downloads/kind_"${KIND_VER}" "${KIND_URL}"
      sudo cp -a "${HOME}"/software_downloads/kind_"${KIND_VER}" /usr/local/bin/
      sudo mv /usr/local/bin/kind_"${KIND_VER}" /usr/local/bin/kind
      sudo chmod 755 /usr/local/bin/kind
      sudo chown root:root /usr/local/bin/kind
      if [[ -x $(command -v kind) ]]; then
        printf "kind is installed\\n"
      fi
    fi
  fi

  if [[ -n ${HAS_K8S} ]]; then
    printf "Installing telepresence\\n"
    wget -O "${HOME}"/software_downloads/telepresence "${TELEPRESENCE_URL}"
    sudo cp -a "${HOME}"/software_downloads/telepresence /usr/local/bin/
    sudo chmod 755 /usr/local/bin/telepresence
    sudo chown root:root /usr/local/bin/telepresence
    if [[ -x $(command -v telepresence) ]]; then
      printf "telepresence is installed\\n"
    fi
  fi

  # Purge stale baltocdn helm APT source left by pre-PR#155 runs — the repo
  # serves unsigned/NOSPLIT data and has no resolute suite, causing apt update
  # to fail on every subsequent setup run even after the code was fixed.
  sudo rm -f /etc/apt/sources.list.d/helm-stable-debian.list 2>/dev/null || true

  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VER}/deb/Release.key" \
    | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  printf 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/%s/deb/ /\n' "${KUBERNETES_VER}" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list
  sudo -H apt update
  sudo -H DEBIAN_FRONTEND=noninteractive apt install kubectl -y

  if [[ -n ${HAS_SNAP} ]]; then
    sudo snap install helm --classic
  fi
  # helm and kustomize on non-snap systems are installed via brew in
  # _install_ubuntu_brew_packages(); no curl installer needed here.
}

_install_ubuntu_hashicorp() {
  printf "Installing Hashicorp Consul Ubuntu\\n"
  if [[ ! -d ${HOME}/software_downloads/consul_${CONSUL_VER} ]]; then
    wget -O "${HOME}"/software_downloads/consul_"${CONSUL_VER}"_linux_"${_LINUX_ARCH}".zip "${HASHICORP_URL}"/consul/"${CONSUL_VER}"/consul_"${CONSUL_VER}"_linux_"${_LINUX_ARCH}".zip
    unzip "${HOME}"/software_downloads/consul_"${CONSUL_VER}"_linux_"${_LINUX_ARCH}".zip -d "${HOME}"/software_downloads/consul_"${CONSUL_VER}"
    sudo cp -a "${HOME}"/software_downloads/consul_"${CONSUL_VER}"/consul /usr/local/bin/
    sudo chmod 755 /usr/local/bin/consul
    sudo chown root:root /usr/local/bin/consul
    if [[ -x $(command -v consul) ]]; then
      printf "consul is installed\\n"
    fi
  fi

  printf "Installing Hashicorp Vault Ubuntu\\n"
  if [[ ! -d ${HOME}/software_downloads/vault_${VAULT_VER} ]]; then
    wget -O "${HOME}"/software_downloads/vault_"${VAULT_VER}"_linux_"${_LINUX_ARCH}".zip "${HASHICORP_URL}"/vault/"${VAULT_VER}"/vault_"${VAULT_VER}"_linux_"${_LINUX_ARCH}".zip
    unzip "${HOME}"/software_downloads/vault_"${VAULT_VER}"_linux_"${_LINUX_ARCH}".zip -d "${HOME}"/software_downloads/vault_"${VAULT_VER}"
    sudo cp -a "${HOME}"/software_downloads/vault_"${VAULT_VER}"/vault /usr/local/bin/
    sudo chmod 755 /usr/local/bin/vault
    sudo chown root:root /usr/local/bin/vault
    if [[ -x $(command -v vault) ]]; then
      printf "vault is installed\\n"
    fi
  fi

  printf "Installing Hashicorp Nomad Ubuntu\\n"
  if [[ ! -d ${HOME}/software_downloads/nomad_${NOMAD_VER} ]]; then
    wget -O "${HOME}"/software_downloads/nomad_"${NOMAD_VER}"_linux_"${_LINUX_ARCH}".zip "${HASHICORP_URL}"/nomad/"${NOMAD_VER}"/nomad_"${NOMAD_VER}"_linux_"${_LINUX_ARCH}".zip
    unzip "${HOME}"/software_downloads/nomad_"${NOMAD_VER}"_linux_"${_LINUX_ARCH}".zip -d "${HOME}"/software_downloads/nomad_"${NOMAD_VER}"
    sudo cp -a "${HOME}"/software_downloads/nomad_"${NOMAD_VER}"/nomad /usr/local/bin/
    sudo chmod 755 /usr/local/bin/nomad
    sudo chown root:root /usr/local/bin/nomad
    if [[ -x $(command -v nomad) ]]; then
      printf "nomad is installed\\n"
    fi
  fi

  printf "Installing Hashicorp Packer Ubuntu\\n"
  if [[ ! -d ${HOME}/software_downloads/packer_${PACKER_VER} ]]; then
    wget -O "${HOME}"/software_downloads/packer_"${PACKER_VER}"_linux_"${_LINUX_ARCH}".zip "${HASHICORP_URL}"/packer/"${PACKER_VER}"/packer_"${PACKER_VER}"_linux_"${_LINUX_ARCH}".zip
    unzip "${HOME}"/software_downloads/packer_"${PACKER_VER}"_linux_"${_LINUX_ARCH}".zip -d "${HOME}"/software_downloads/packer_"${PACKER_VER}"
    sudo cp -a "${HOME}"/software_downloads/packer_"${PACKER_VER}"/packer /usr/local/bin/
    sudo chmod 755 /usr/local/bin/packer
    sudo chown root:root /usr/local/bin/packer
    if [[ -x $(command -v packer) ]]; then
      printf "packer is installed\\n"
    fi
  fi

  printf "Installing Hashicorp Vagrant Ubuntu\\n"
  if [[ ! -d ${HOME}/software_downloads/vagrant_${VAGRANT_VER} ]]; then
    # vagrant has no ARM64 Linux build — amd64 only
    wget -O "${HOME}"/software_downloads/vagrant_"${VAGRANT_VER}"_linux_amd64.zip "${HASHICORP_URL}"/vagrant/"${VAGRANT_VER}"/vagrant_"${VAGRANT_VER}"_linux_amd64.zip
    unzip "${HOME}"/software_downloads/vagrant_"${VAGRANT_VER}"_linux_amd64.zip -d "${HOME}"/software_downloads/vagrant_"${VAGRANT_VER}"
    sudo cp -a "${HOME}"/software_downloads/vagrant_"${VAGRANT_VER}"/vagrant /usr/local/bin/
    sudo chmod 755 /usr/local/bin/vagrant
    sudo chown root:root /usr/local/bin/vagrant
    if [[ -x $(command -v vagrant) ]]; then
      printf "vagrant is installed\\n"
    fi
  fi
}

_install_ubuntu_cloud_tools() {
  if [[ -n ${HAS_DEVTOOLS} ]]; then
    printf "Installing teleport\\n"
    curl -fsSL https://deb.releases.teleport.dev/teleport-pubkey.asc | sudo gpg --dearmor --yes --output /usr/share/keyrings/teleport-pubkey.gpg
    sudo rm -f /etc/apt/sources.list.d/archive_uri-https_deb_releases_teleport_dev_-noble.list
    echo "deb [signed-by=/usr/share/keyrings/teleport-pubkey.gpg] https://deb.releases.teleport.dev/ stable main" | sudo tee /etc/apt/sources.list.d/teleport.list
    sudo -H apt update
    sudo -H DEBIAN_FRONTEND=noninteractive apt install teleport -y
    if [[ -x $(command -v tsh) ]]; then
      printf "Teleport is installed\\n"
    fi
  fi

  if [[ -n ${HAS_DEVTOOLS} ]]; then
    printf "Installing cloudflared\\n"
    local _cf_codename
    _cf_codename="$(lsb_release -cs)"
    # Cloudflare WARP has no Ubuntu 26.04 packages yet; fall back to noble
    [[ -n "${RESOLUTE:-}" ]] && _cf_codename="noble"
    local _cf_sources="${_CF_SOURCES_LIST:-/etc/apt/sources.list.d/cloudflare-client.list}"
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${_cf_codename} main" | sudo tee "${_cf_sources}"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install cloudflare-warp -y
    if [[ -x $(command -v cloudflared) ]]; then
      printf "cloudflared is installed\\n"
    fi
  fi

  printf "Installing azure-cli\\n"
  curl -sL http://packages.microsoft.com/keys/microsoft.asc | \
  gpg --dearmor | \
  sudo tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg > /dev/null
  AZ_REPO=$(lsb_release -cs)
  # Azure CLI has no Ubuntu 26.04 packages yet; fall back to noble
  [[ -n "${RESOLUTE:-}" ]] && AZ_REPO="noble"
  # Purge stale azure-cli APT sources before re-adding: add-apt-repository
  # appends a new dist line rather than replacing the old one, so a prior run
  # with 'resolute' (before the noble fallback) leaves a stale entry that
  # causes apt-get update to 404 on every subsequent run.
  sudo rm -f /etc/apt/sources.list.d/packages.microsoft.com_repos_azure-cli.list 2>/dev/null || true
  sudo rm -f /etc/apt/sources.list.d/azure-cli.list 2>/dev/null || true
  sudo -H add-apt-repository \
  "deb [arch=$(dpkg --print-architecture)] http://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main"
  sudo -H apt update
  sudo -H DEBIAN_FRONTEND=noninteractive apt install azure-cli -y
  if [[ -x $(command -v az) ]]; then
    printf "az is installed\\n"
  fi

  printf "Installing gcloud-sdk\\n"
  if [[ ! -f /etc/apt/sources.list.d/google-cloud-sdk.list ]]; then
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
  fi
  sudo apt update
  sudo -H DEBIAN_FRONTEND=noninteractive apt install google-cloud-sdk -y
  sudo -H DEBIAN_FRONTEND=noninteractive apt install google-cloud-sdk-app-engine-go -y
  sudo -H DEBIAN_FRONTEND=noninteractive apt install google-cloud-cli -y

  printf "Installing cf-terraforming Ubuntu\\n"
  if [[ ! -f ${HOME}/software_downloads/cf-terraforming_${CF_TERRAFORMING_VER}_linux_${_LINUX_ARCH}.tar.gz ]]; then
    wget -O "${HOME}"/software_downloads/cf-terraforming_"${CF_TERRAFORMING_VER}"_linux_"${_LINUX_ARCH}".tar.gz "${CF_TERRAFORMING_URL}"
    tar xvf "${HOME}"/software_downloads/cf-terraforming_"${CF_TERRAFORMING_VER}"_linux_"${_LINUX_ARCH}".tar.gz -C "${HOME}"/software_downloads
    if [[ -f ${HOME}/software_downloads/CHANGELOG.md ]]; then
      rm "${HOME}"/software_downloads/CHANGELOG.md
    fi
    if [[ -f ${HOME}/software_downloads/LICENSE ]]; then
      rm "${HOME}"/software_downloads/LICENSE
    fi
    if [[ -f ${HOME}/software_downloads/README.md ]]; then
      rm "${HOME}"/software_downloads/README.md
    fi
    sudo cp -a "${HOME}"/software_downloads/cf-terraforming /usr/local/bin/
    sudo chmod 755 /usr/local/bin/cf-terraforming
    sudo chown root:root /usr/local/bin/cf-terraforming
    if [[ -x $(command -v cf-terraforming) ]]; then
      printf "cf-terraforming is installed\\n"
    fi
  fi
}

# Returns 0 clean, 1 hard failure, 2 partial success with the failed packages named.
# The tri-state mirrors install_git_hooks_all_repos: a bootstrap must not abort
# because one upstream formula was briefly unavailable, but it must not report
# success over a package that never landed either. Before this, every call was
# unchecked and brew_install_formula swallowed its own status -- which is how
# `go-task/tap/go-task` failed with exit 127 on every Linux run since it was added,
# silently, leaving claude without it. Measured 2026-09-12.
_install_ubuntu_brew_packages() {
  local _failed=()
  # Was `install_homebrew` unchecked inside an if/elif, so a fresh box installed brew
  # and then skipped the entire package list for that run. Install, then fall through.
  if ! [ -x "$(command -v brew)" ]; then
    install_homebrew || return 1
  fi
  if ! [ -x "$(command -v brew)" ]; then
    log_error "brew still unavailable after install_homebrew"
    return 1
  fi

  printf "Installing brew packages in Ubuntu\\n"
  brew_update

  local _f
  for _f in \
    argocd bat cargo-nextest cargo-cyclonedx cyclonedx-python git-lfs fzf gh \
    hadolint helm k9s kustomize lazydocker linkerd mongosh mongodb-atlas neovim \
    pyenv pyenv-virtualenv rbenv ripgrep rustup \
    starship tgenv uv zoxide redpanda-data/tap/redpanda \
    git-cliff kcov mdbook bun getagentseal/codeburn/codeburn \
    go-task; do
    # go-task is `go-task`, NOT `go-task/tap/go-task`: the tap-qualified name resolves
    # to a macOS Cask that shells out to /usr/bin/xattr and exits 127 on Linux. Core
    # ships the formula now. Same for `bun` over `oven-sh/bun/bun`, and `codeburn` is
    # only ever the tap-qualified name -- bare `codeburn` resolves to nothing.
    brew_install_formula "${_f}" || _failed+=("${_f}")
  done

  # Homebrew rather than apt deliberately: apt ships shfmt 3.8.0 on noble and
  # 3.12.0 on resolute, against 3.13.1 from brew. A formatter's output is the
  # gate, so version skew across machines would flag files nobody touched.
  brew_install_formula shfmt || _failed+=(shfmt)

  brew_tap_if_missing snyk/tap
  brew_install_formula snyk || _failed+=(snyk)

  # codex is a Cask on Linux as well as macOS, so it needs the cask-aware guard:
  # brew_formula_installed greps `brew list --formula` and would never see it,
  # reinstalling on every run.
  brew_install_cask codex || _failed+=(codex)

  if [[ -n ${HAS_DEVTOOLS} ]]; then
    brew_tap_if_missing gitguardian/tap
    brew_install_formula ggshield || _failed+=(ggshield)
    brew_install_formula claude-code@latest || _failed+=(claude-code@latest)
    if command -v claude &> /dev/null; then
      # `-s user`, and plugin@marketplace, and the SINGULAR verb. The old form
      # (`claude plugins install <bare-name>`) registered at PROJECT scope against
      # whatever cwd the run happened to have, so `claude plugins update` later
      # reported "not installed at scope user" for 12 plugins and failed the update's
      # claude section. Measured on claude 2026-09-12.
      local _p
      for _p in superpowers@claude-plugins-official code-simplifier@claude-plugins-official \
        code-review@claude-plugins-official context7@claude-plugins-official; do
        claude plugin install -s user "${_p}" < /dev/null || _failed+=("${_p}")
      done
    fi
  fi

  if [[ -n ${HAS_SNAP} ]]; then
    brew_install_formula ollama || _failed+=(ollama)
  fi

  # Trust third-party taps for Homebrew 6.0 (idempotent — no-op if already trusted or tap absent)
  brew trust cloudflare/cloudflare datawire/blackbird getagentseal/codeburn gitguardian/tap go-task/tap oven-sh/bun redpanda-data/tap snyk/tap 2> /dev/null || true

  if [[ ${#_failed[@]} -gt 0 ]]; then
    log_warn "brew: ${#_failed[@]} package(s) failed: ${_failed[*]}"
    return 2
  fi
}

_install_ubuntu_gui_tools() {
  if [[ -n ${HAS_DEVTOOLS} ]]; then
    printf "Installing Virtualbox\\n"
    wget -O- https://www.virtualbox.org/download/oracle_vbox_2016.asc | sudo gpg --dearmor --yes --output /usr/share/keyrings/oracle-virtualbox-2016.gpg
    # VirtualBox has no ARM64 Linux build — amd64 only
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle-virtualbox-2016.gpg] http://download.virtualbox.org/virtualbox/debian $(. /etc/os-release && echo "$VERSION_CODENAME") contrib" | sudo tee /etc/apt/sources.list.d/virtualbox.list
    sudo -H apt update
    # shellcheck disable=SC2086 # package-name slot: apt install takes a list, and VIRTUALBOX_VER may hold more than one package
    sudo -H DEBIAN_FRONTEND=noninteractive apt install ${VIRTUALBOX_VER} -y
    if [[ -x $(command -v vboxmanage) ]]; then
      printf "Virtualbox is installed\\n"
    fi
  fi

  if [[ -n ${HAS_SNAP} ]]; then
    printf "Installing Albert Ubuntu Noble\\n"
    echo "deb http://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_$(lsb_release -rs)/ /" | sudo tee /etc/apt/sources.list.d/home:manuelschneid3r.list
    # shellcheck disable=SC2046 # `lsb_release -rs` emits one token (e.g. 24.04) inside a URL path; there is nothing to split
    curl -fsSL https://download.opensuse.org/repositories/home:manuelschneid3r/xUbuntu_$(lsb_release -rs)/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/home_manuelschneid3r.gpg > /dev/null
    sudo -H apt update
    sudo -H DEBIAN_FRONTEND=noninteractive apt install albert -y
    if [[ -x $(command -v albert) ]]; then
      printf "Albert is installed Ubuntu Noble\\n"
    fi
  fi

  if [[ -n ${HAS_SNAP} ]]; then
    printf "Installing microsoft edge\\n"
    # Microsoft Edge has no ARM64 Linux build — amd64 only
    sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/edge stable main" > /etc/apt/sources.list.d/microsoft-edge.list'
    sudo -H apt update
    sudo -H DEBIAN_FRONTEND=noninteractive apt install microsoft-edge-stable -y
  fi

  if [[ -n ${HAS_SNAP} ]]; then
    printf "snap software with classic option, the other snap packages are installed in ubuntu_workstation_snap_packages.txt\\n"
    sudo snap install code --classic
    sudo snap install slack --classic
    sudo snap install certbot --classic
    sudo snap set certbot trust-plugin-with-root=ok
    sudo snap install certbot-dns-route53
  fi

  if [[ -n ${HAS_FLATPAK} ]]; then
    printf "Installing Steam via Flatpak\\n"
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    sudo flatpak install flathub com.valvesoftware.Steam -y
    if sudo flatpak list | grep -q com.valvesoftware.Steam; then
      printf "Steam is installed\\n"
    fi
  fi
}

_install_ubuntu_misc() {
  printf "Installing docker-compose Ubuntu\\n"
  if [[ ! -f ${HOME}/software_downloads/docker-compose_${DOCKER_COMPOSE_VER} ]]; then
    wget -O "${HOME}"/software_downloads/docker-compose_"${DOCKER_COMPOSE_VER}" "${DOCKER_COMPOSE_URL}"
    sudo cp -a "${HOME}"/software_downloads/docker-compose_"${DOCKER_COMPOSE_VER}" /usr/local/bin/
    sudo mv /usr/local/bin/docker-compose_"${DOCKER_COMPOSE_VER}" /usr/local/bin/docker-compose
    sudo chmod 755 /usr/local/bin/docker-compose
    sudo chown root:root /usr/local/bin/docker-compose
    if [[ -x $(command -v docker-compose) ]]; then
      printf "docker-compose is installed\\n"
    fi
  fi

  if [[ -n ${HAS_DEVTOOLS} ]]; then
    if [[ ! -f ${HOME}/software_downloads/yq_${YQ_VER} ]]; then
      printf "Installing yq\\n"
      wget -O "${HOME}"/software_downloads/yq_"${YQ_VER}" "${YQ_URL}"
      sudo cp -a "${HOME}"/software_downloads/yq_"${YQ_VER}" /usr/local/bin/
      sudo mv /usr/local/bin/yq_"${YQ_VER}" /usr/local/bin/yq
      sudo chmod 755 /usr/local/bin/yq
      sudo chown root:root /usr/local/bin/yq
      if [[ -x $(command -v yq) ]]; then
        printf "yq is installed\\n"
      fi
    fi
  fi

  if [[ -n ${HAS_DEVTOOLS} ]]; then
    printf "Installing .net8 sdk\\n"
    # dotnet-sdk-8.0 is absent from some Ubuntu releases (e.g. 26.04 resolute);
    # don't abort the rest of setup if the package can't be located.
    sudo -H DEBIAN_FRONTEND=noninteractive apt install dotnet-sdk-8.0 -y || log_warn "dotnet-sdk-8.0 not available on this Ubuntu release; skipping"
  fi

  if [[ -n ${HAS_DEVTOOLS} ]]; then
    # _FORCE_OPENTOFU_INSTALL is a test seam: forces the install path even when
    # tofu is already on PATH, so tests don't depend on host tofu presence.
    # Unset in normal operation — identical to `! command -v tofu`.
    if [[ -n ${_FORCE_OPENTOFU_INSTALL:-} ]] || ! command -v tofu &>/dev/null; then
      printf "Installing opentofu\\n"
      sudo mkdir -p /etc/apt/keyrings
      curl -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey \
        | sudo gpg --dearmor -o /etc/apt/keyrings/opentofu-archive-keyring.gpg
      printf "deb [signed-by=/etc/apt/keyrings/opentofu-archive-keyring.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main\n" \
        | sudo DEBIAN_FRONTEND=noninteractive tee /etc/apt/sources.list.d/opentofu.list > /dev/null
      sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
      # The package in packages.opentofu.org/opentofu/tofu/any is named `tofu`,
      # not `opentofu` -- its amd64 index carries exactly that one package.
      # Installing `opentofu` failed with "Unable to locate package" on every
      # Ubuntu release, silently, because the `command -v tofu` check below
      # simply never fired. Measured on claude 2026-09-12.
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y tofu
      if command -v tofu &>/dev/null; then
        printf "opentofu is installed\\n"
      fi
    else
      printf "opentofu already installed\\n"
    fi
  fi

  check_and_install_nala
  sudo -H nala autoremove -y
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
