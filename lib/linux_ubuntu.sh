#!/usr/bin/env bash
# lib/linux_ubuntu.sh — Ubuntu-specific install functions

install_ubuntu_packages() {
  _install_ubuntu_base_packages  || return 1
  _install_ubuntu_pyenv          || return 1
  _install_ubuntu_powershell     || return 1
  _install_ubuntu_go             || return 1
  _install_ubuntu_rust           || return 1
  _install_ubuntu_docker         || return 1
  _install_ubuntu_k8s_tools      || return 1
  _install_ubuntu_hashicorp      || return 1
  _install_ubuntu_cloud_tools    || return 1
  _install_ubuntu_brew_packages  || return 1
  _install_ubuntu_gui_tools      || return 1
  _install_ubuntu_misc           || return 1
}

_install_ubuntu_base_packages() {
  sudo -H apt update
  printf "Installing hwe, common, and 24.04 packages\\n"
  sudo -H apt install --install-recommends linux-generic-hwe-24.04 -y
  check_and_install_nala
  xargs -a ./ubuntu_common_packages.txt sudo nala install -y
  xargs -a ./ubuntu_2404_packages.txt sudo nala install -y

  if [[ -n ${HAS_SNAP} ]]; then
    printf "Installing workstation packages\\n"
    xargs -a ./ubuntu_workstation_packages.txt sudo apt install -y

    printf "Installing workstation snap packages\\n"
    xargs -a ./ubuntu_workstation_snap_packages.txt sudo snap install

  fi
}

_install_ubuntu_pyenv() {
  printf "Installing pyenv\\n"
  local _pyenv_script
  _pyenv_script="$(mktemp)"
  curl -fsSL https://pyenv.run -o "${_pyenv_script}" || { rm -f "${_pyenv_script}"; return 1; }
  bash "${_pyenv_script}"
  rm -f "${_pyenv_script}"
  if [[ -x $(command -v pyenv) ]]; then
    printf "pyenv is installed\\n"
  fi
}

_install_ubuntu_powershell() {
  printf "Installing powershell Ubuntu\\n"
  if [[ ! -f ${HOME}/software_downloads/packages-microsoft-prod.deb ]]; then
    # shellcheck disable=SC2046
    wget -O ${HOME}/software_downloads/packages-microsoft-prod.deb https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
    sudo -H dpkg -i ${HOME}/software_downloads/packages-microsoft-prod.deb
    sudo apt update
    sudo -H add-apt-repository universe
    sudo -H apt install powershell -y
    if [[ -x $(command -v pwsh) ]]; then
      printf "pwsh is installed\\n"
    fi
  fi
}

_install_go_from_tarball() {
  if [[ ! -f ${HOME}/software_downloads/${GO_DOWNLOAD_FILENAME} ]]; then
    wget -O ${HOME}/software_downloads/${GO_DOWNLOAD_FILENAME} ${GO_DOWNLOAD_URL}
    tar xvf ${HOME}/software_downloads/${GO_DOWNLOAD_FILENAME} -C ${HOME}/software_downloads/
    if [[ -d /usr/local/go ]]; then
      sudo rm -rf /usr/local/go
    fi
    if [[ -d ${HOME}/software_downloads/go ]]; then
      sudo mv ${HOME}/software_downloads/go /usr/local/go
      sudo chmod 755 /usr/local/go
      sudo chown -R root:root /usr/local/go
    fi
    if [[ -d ${HOME}/software_downloads/go ]]; then
      rm -rf ${HOME}/software_downloads/go
    fi
  fi
}

_install_ubuntu_go() {
  printf "Installing Go Ubuntu\\n"
  local _minor
  _minor=$(printf '%s' "${GO_VER}" | cut -d. -f2)
  if [[ ${_minor} -lt 16 ]] || [[ ${_minor} -gt 26 ]]; then
    printf "Error: Unsupported Go version %s\\n" "${GO_VER}"
    return 1
  fi
  sudo -H apt update
  local _prev_minor=$(( _minor - 1 ))
  local pkgs_to_remove="golang-1.${_prev_minor}-go golang-1.${_prev_minor}-src"
  if [[ -n ${pkgs_to_remove} ]]; then
    sudo -H apt remove ${pkgs_to_remove} -y
  fi
  if [[ ${_minor} -lt 21 ]]; then
    sudo add-apt-repository ppa:longsleep/golang-backports -y
    sudo -H apt install "golang-${GO_VER}-go" -y
  else
    _install_go_from_tarball
  fi
  INSTALLED_GO_VER=$(go version | awk '{print $3}' | sed 's/go//g')
  if [[ ${INSTALLED_GO_VER} == "${GO_VER}" ]]; then
    printf "Go %s is installed\\n" "${GO_VER}"
  fi
}

_install_ubuntu_rust() {
  if [[ -n ${HAS_RUST} ]]; then
    printf "Installing Rust Ubuntu\\n"
    if [[ ! -x $(command -v rustc) ]] || [[ ! -x $(command -v cargo) ]]; then
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    fi
    if [[ -f ${HOME}/.cargo/env ]]; then
      # shellcheck disable=SC1090
      . ${HOME}/.cargo/env
    fi
    if [[ -x $(command -v rustc) ]] && [[ -x $(command -v cargo) ]]; then
      printf "Rust is installed\\n"
      if ! command -v cargo-nextest &>/dev/null; then
        printf "Installing cargo-nextest\\n"
        curl -LsSf https://get.nexte.st/latest/linux | tar zxf - -C "${HOME}/.cargo/bin"
      fi
    fi
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
    sudo -H apt install docker-ce -y
    sudo -H apt install docker-ce-cli -y
    sudo -H apt install containerd.io -y
    sudo -H apt install docker-buildx-plugin -y
    sudo -H apt install docker-compose-plugin -y
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
      wget -O ${HOME}/software_downloads/kind_${KIND_VER} ${KIND_URL}
      sudo cp -a ${HOME}/software_downloads/kind_${KIND_VER} /usr/local/bin/
      sudo mv /usr/local/bin/kind_${KIND_VER} /usr/local/bin/kind
      sudo chmod 755 /usr/local/bin/kind
      sudo chown root:root /usr/local/bin/kind
      if [[ -x $(command -v kind) ]]; then
        printf "kind is installed\\n"
      fi
    fi
  fi

  if [[ -n ${HAS_K8S} ]]; then
    printf "Installing telepresence\\n"
    wget -O ${HOME}/software_downloads/telepresence ${TELEPRESENCE_URL}
    sudo cp -a ${HOME}/software_downloads/telepresence /usr/local/bin/
    sudo chmod 755 /usr/local/bin/telepresence
    sudo chown root:root /usr/local/bin/telepresence
    if [[ -x $(command -v telepresence) ]]; then
      printf "telepresence is installed\\n"
    fi
  fi

  if [[ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]]; then
    sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VER}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VER}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
  fi
  sudo -H apt update
  sudo -H apt install kubectl -y

  if [[ -n ${HAS_SNAP} ]]; then
    sudo snap install helm --classic
  fi
  # can't use snap on wsl2
  if [[ -z ${HAS_SNAP} ]]; then
    curl https://baltocdn.com/helm/signing.asc | sudo gpg --dearmor -o /etc/apt/keyrings/helm-signing.gpg
    echo "deb [signed-by=/etc/apt/keyrings/helm-signing.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
    sudo apt-get update
    sudo apt-get install helm
  fi

  printf "Installing kustomize\\n"
  cd ${HOME}/software_downloads || return 1
  local _kustomize_script
  _kustomize_script="$(mktemp)"
  curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" -o "${_kustomize_script}" || { rm -f "${_kustomize_script}"; return 1; }
  bash "${_kustomize_script}"
  rm -f "${_kustomize_script}"
  if [[ -f ${HOME}/software_downloads/kustomize ]]; then
    sudo -H mv ${HOME}/software_downloads/kustomize /usr/local/bin/kustomize
    sudo chmod 755 /usr/local/bin/kustomize
    sudo chown root:root /usr/local/bin/kustomize
    if [[ -x $(command -v kustomize) ]]; then
      printf "kustomize is installed\\n"
    fi
  fi
}

_install_ubuntu_hashicorp() {
  printf "Installing Hashicorp Consul Ubuntu\\n"
  if [[ ! -d ${HOME}/software_downloads/consul_${CONSUL_VER} ]]; then
    wget -O ${HOME}/software_downloads/consul_${CONSUL_VER}_linux_amd64.zip ${HASHICORP_URL}/consul/${CONSUL_VER}/consul_${CONSUL_VER}_linux_amd64.zip
    unzip ${HOME}/software_downloads/consul_${CONSUL_VER}_linux_amd64.zip -d ${HOME}/software_downloads/consul_${CONSUL_VER}
    sudo cp -a ${HOME}/software_downloads/consul_${CONSUL_VER}/consul /usr/local/bin/
    sudo chmod 755 /usr/local/bin/consul
    sudo chown root:root /usr/local/bin/consul
    if [[ -x $(command -v consul) ]]; then
      printf "consul is installed\\n"
    fi
  fi

  printf "Installing Hashicorp Vault Ubuntu\\n"
  if [[ ! -d ${HOME}/software_downloads/vault_${VAULT_VER} ]]; then
    wget -O ${HOME}/software_downloads/vault_${VAULT_VER}_linux_amd64.zip ${HASHICORP_URL}/vault/${VAULT_VER}/vault_${VAULT_VER}_linux_amd64.zip
    unzip ${HOME}/software_downloads/vault_${VAULT_VER}_linux_amd64.zip -d ${HOME}/software_downloads/vault_${VAULT_VER}
    sudo cp -a ${HOME}/software_downloads/vault_${VAULT_VER}/vault /usr/local/bin/
    sudo chmod 755 /usr/local/bin/vault
    sudo chown root:root /usr/local/bin/vault
    if [[ -x $(command -v vault) ]]; then
      printf "vault is installed\\n"
    fi
  fi

  printf "Installing Hashicorp Nomad Ubuntu\\n"
  if [[ ! -d ${HOME}/software_downloads/nomad_${NOMAD_VER} ]]; then
    wget -O ${HOME}/software_downloads/nomad_${NOMAD_VER}_linux_amd64.zip ${HASHICORP_URL}/nomad/${NOMAD_VER}/nomad_${NOMAD_VER}_linux_amd64.zip
    unzip ${HOME}/software_downloads/nomad_${NOMAD_VER}_linux_amd64.zip -d ${HOME}/software_downloads/nomad_${NOMAD_VER}
    sudo cp -a ${HOME}/software_downloads/nomad_${NOMAD_VER}/nomad /usr/local/bin/
    sudo chmod 755 /usr/local/bin/nomad
    sudo chown root:root /usr/local/bin/nomad
    if [[ -x $(command -v nomad) ]]; then
      printf "nomad is installed\\n"
    fi
  fi

  printf "Installing Hashicorp Packer Ubuntu\\n"
  if [[ ! -d ${HOME}/software_downloads/packer_${PACKER_VER} ]]; then
    wget -O ${HOME}/software_downloads/packer_${PACKER_VER}_linux_amd64.zip ${HASHICORP_URL}/packer/${PACKER_VER}/packer_${PACKER_VER}_linux_amd64.zip
    unzip ${HOME}/software_downloads/packer_${PACKER_VER}_linux_amd64.zip -d ${HOME}/software_downloads/packer_${PACKER_VER}
    sudo cp -a ${HOME}/software_downloads/packer_${PACKER_VER}/packer /usr/local/bin/
    sudo chmod 755 /usr/local/bin/packer
    sudo chown root:root /usr/local/bin/packer
    if [[ -x $(command -v packer) ]]; then
      printf "packer is installed\\n"
    fi
  fi

  printf "Installing Hashicorp Vagrant Ubuntu\\n"
  if [[ ! -d ${HOME}/software_downloads/vagrant_${VAGRANT_VER} ]]; then
    wget -O ${HOME}/software_downloads/vagrant_${VAGRANT_VER}_linux_amd64.zip ${HASHICORP_URL}/vagrant/${VAGRANT_VER}/vagrant_${VAGRANT_VER}_linux_amd64.zip
    unzip ${HOME}/software_downloads/vagrant_${VAGRANT_VER}_linux_amd64.zip -d ${HOME}/software_downloads/vagrant_${VAGRANT_VER}
    sudo cp -a ${HOME}/software_downloads/vagrant_${VAGRANT_VER}/vagrant /usr/local/bin/
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
    wget -O- https://deb.releases.teleport.dev/teleport-pubkey.asc | sudo gpg --dearmor --yes --output /usr/share/keyrings/telport-pubkey.gpg
    sudo add-apt-repository "deb https://deb.releases.teleport.dev/ stable main"
    sudo -H apt update
    sudo -H apt install teleport -y
    if [[ -x $(command -v tsh) ]]; then
      printf "Teleport is installed\\n"
    fi
  fi

  if [[ -n ${HAS_DEVTOOLS} ]]; then
    printf "Installing cloudflared\\n"
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list
    sudo apt-get update
    sudo apt-get install cloudflare-warp -y
    if [[ -x $(command -v cloudflared) ]]; then
      printf "cloudflared is installed\\n"
    fi
  fi

  printf "Installing azure-cli\\n"
  curl -sL http://packages.microsoft.com/keys/microsoft.asc | \
  gpg --dearmor | \
  sudo tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg > /dev/null
  AZ_REPO=$(lsb_release -cs)
  sudo -H add-apt-repository \
  "deb [arch=amd64] http://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main"
  sudo -H apt update
  sudo -H apt install azure-cli -y
  if [[ -x $(command -v az) ]]; then
    printf "az is installed\\n"
  fi

  printf "Installing gcloud-sdk\\n"
  if [[ ! -f /etc/apt/sources.list.d/google-cloud-sdk.list ]]; then
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
  fi
  sudo apt update
  sudo -H apt install google-cloud-sdk -y
  sudo -H apt install google-cloud-sdk-app-engine-go -y
  sudo -H apt install google-cloud-cli -y

  printf "Installing cf-terraforming Ubuntu\\n"
  if [[ ! -f ${HOME}/software_downloads/cf-terraforming_${CF_TERRAFORMING_VER}_linux_amd64.tar.gz ]]; then
    wget -O ${HOME}/software_downloads/cf-terraforming_${CF_TERRAFORMING_VER}_linux_amd64.tar.gz ${CF_TERRAFORMING_URL}
    tar xvf ${HOME}/software_downloads/cf-terraforming_${CF_TERRAFORMING_VER}_linux_amd64.tar.gz -C ${HOME}/software_downloads
    if [[ -f ${HOME}/software_downloads/CHANGELOG.md ]]; then
      rm ${HOME}/software_downloads/CHANGELOG.md
    fi
    if [[ -f ${HOME}/software_downloads/LICENSE ]]; then
      rm ${HOME}/software_downloads/LICENSE
    fi
    if [[ -f ${HOME}/software_downloads/README.md ]]; then
      rm ${HOME}/software_downloads/README.md
    fi
    sudo cp -a ${HOME}/software_downloads/cf-terraforming /usr/local/bin/
    sudo chmod 755 /usr/local/bin/cf-terraforming
    sudo chown root:root /usr/local/bin/cf-terraforming
    if [[ -x $(command -v cf-terraforming) ]]; then
      printf "cf-terraforming is installed\\n"
    fi
  fi
}

_install_ubuntu_brew_packages() {
  if ! [ -x "$(command -v brew)" ]; then
    install_homebrew
  elif [ -x "$(command -v brew)" ]; then
    printf "Installing brew packages in Ubuntu\\n"
    brew_update
    brew_install_formula argocd
    brew_install_formula bat
    brew_install_formula git-lfs
    brew_install_formula fzf
    brew_install_formula gh
    brew_install_formula hadolint
    brew_install_formula k9s
    brew_install_formula lazydocker
    brew_install_formula linkerd
    brew_install_formula mongosh
    brew_install_formula mongodb-atlas
    brew_install_formula neovim
    brew_install_formula rbenv
    brew_install_formula ripgrep
    brew_install_formula rustup
    brew_install_formula starship
    brew_install_formula tgenv
    brew_install_formula zoxide
    brew_install_formula go-task/tap/go-task
    brew_install_formula redpanda-data/tap/redpanda
    brew_tap_if_missing snyk/tap
    brew_install_formula snyk
    if [[ -n ${HAS_DEVTOOLS} ]]; then
      brew_tap_if_missing gitguardian/tap
      brew_install_formula ggshield
      brew_install_formula claude-code
      if command -v claude &>/dev/null; then
        claude plugins install superpowers
        claude plugins install code-simplifier
        claude plugins install code-review
        claude plugins install context7
      fi
    fi
    if [[ -n ${HAS_SNAP} ]]; then
      brew_install_formula ollama
    fi
    # Trust third-party taps for Homebrew 6.0 (idempotent — no-op if already trusted or tap absent)
    brew trust cloudflare/cloudflare datawire/blackbird gitguardian/tap go-task/tap redpanda-data/tap snyk/tap 2>/dev/null || true
  fi
}

_install_ubuntu_gui_tools() {
  if [[ -n ${HAS_DEVTOOLS} ]]; then
    printf "Installing Virtualbox\\n"
    wget -O- https://www.virtualbox.org/download/oracle_vbox_2016.asc | sudo gpg --dearmor --yes --output /usr/share/keyrings/oracle-virtualbox-2016.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle-virtualbox-2016.gpg] http://download.virtualbox.org/virtualbox/debian $(. /etc/os-release && echo "$VERSION_CODENAME") contrib" | sudo tee /etc/apt/sources.list.d/virtualbox.list
    sudo -H apt update
    sudo -H apt install ${VIRTUALBOX_VER} -y
    if [[ -x $(command -v vboxmanage) ]]; then
      printf "Virtualbox is installed\\n"
    fi
  fi

  if [[ -n ${HAS_SNAP} ]]; then
    printf "Installing Albert Ubuntu Noble\\n"
    # shellcheck disable=SC2046
    echo "deb http://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_$(lsb_release -rs)/ /" | sudo tee /etc/apt/sources.list.d/home:manuelschneid3r.list
    # shellcheck disable=SC2046
    curl -fsSL https://download.opensuse.org/repositories/home:manuelschneid3r/xUbuntu_$(lsb_release -rs)/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/home_manuelschneid3r.gpg > /dev/null
    sudo -H apt update
    sudo -H apt install albert -y
    if [[ -x $(command -v albert) ]]; then
      printf "Albert is installed Ubuntu Noble\\n"
    fi
  fi

  if [[ -n ${HAS_SNAP} ]]; then
    printf "Installing microsoft edge\\n"
    sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/edge stable main" > /etc/apt/sources.list.d/microsoft-edge.list'
    sudo -H apt update
    sudo -H apt install microsoft-edge-stable -y
  fi

  if [[ -n ${HAS_SNAP} ]]; then
    printf "snap software with classic option, the other snap packages are installed in ubuntu_workstation_snap_packages.txt\\n"
    sudo snap install atom --classic
    sudo snap install code --classic
    sudo snap install slack --classic
    sudo snap install certbot --classic
    sudo snap set certbot trust-plugin-with-root=ok
    sudo snap install certbot-dns-route53
  fi
}

_install_ubuntu_misc() {
  printf "Installing docker-compose Ubuntu\\n"
  if [[ ! -f ${HOME}/software_downloads/docker-compose_${DOCKER_COMPOSE_VER} ]]; then
    wget -O ${HOME}/software_downloads/docker-compose_${DOCKER_COMPOSE_VER} ${DOCKER_COMPOSE_URL}
    sudo cp -a ${HOME}/software_downloads/docker-compose_${DOCKER_COMPOSE_VER} /usr/local/bin/
    sudo mv /usr/local/bin/docker-compose_${DOCKER_COMPOSE_VER} /usr/local/bin/docker-compose
    sudo chmod 755 /usr/local/bin/docker-compose
    sudo chown root:root /usr/local/bin/docker-compose
    if [[ -x $(command -v docker-compose) ]]; then
      printf "docker-compose is installed\\n"
    fi
  fi

  if [[ -n ${HAS_DEVTOOLS} ]]; then
    if [[ ! -f ${HOME}/software_downloads/yq_${YQ_VER} ]]; then
      printf "Installing yq\\n"
      wget -O ${HOME}/software_downloads/yq_${YQ_VER} ${YQ_URL}
      sudo cp -a ${HOME}/software_downloads/yq_${YQ_VER} /usr/local/bin/
      sudo mv /usr/local/bin/yq_${YQ_VER} /usr/local/bin/yq
      sudo chmod 755 /usr/local/bin/yq
      sudo chown root:root /usr/local/bin/yq
      if [[ -x $(command -v yq) ]]; then
        printf "yq is installed\\n"
      fi
    fi
  fi

  if [[ -n ${HAS_DEVTOOLS} ]]; then
    printf "Installing .net8 sdk\\n"
    sudo -H apt install dotnet-sdk-8.0 -y
  fi

  python -m pip install glances
  if [[ -x $(command -v glances) ]]; then
    printf "glances is installed\\n"
  fi

  check_and_install_nala
  sudo -H nala autoremove -y
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
