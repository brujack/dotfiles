#!/usr/bin/env bash
# lib/workflows.sh — top-level workflow functions dispatched by setup_env.sh

run_setup_user() {
  # need to make sure that some base packages are installed
  if [[ ${REDHAT} || ${FEDORA} ]]; then
    if ! [ -x "$(command -v dnf)" ]; then
      printf "Installing dnf\\n"
      sudo -H yum update -y
      sudo -H yum install dnf -y
      if ! [ -x "$(command -v dnf)" ]; then
        printf "Failed to install dnf\\n"
        exit 1
      fi
      printf "Installed dnf\\n"
    fi
  fi

  if [[ -n ${MACOS} ]]; then
    printf "Installing Rosetta if necessary\\n"
    install_rosetta
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${FEDORA} ]] || [[ -n ${CENTOS} ]]; then
    install_git
  fi

  mkdir -p ${HOME}/software_downloads

  if [[ ${MACOS} || ${UBUNTU} || ${FEDORA} || ${CENTOS} ]]; then
    install_zsh
  fi

  if [[ -n ${LINUX} ]]; then
    install_bats
  fi

  printf "Creating %s/bin\\n" "${HOME}"
  mkdir -p ${HOME}/bin

  printf "Creating %s\\n" "${PERSONAL_GITREPOS}"
  mkdir -p ${PERSONAL_GITREPOS}

  clone_or_update_dotfiles

  setup_dotfile_symlinks

  setup_zsh_as_default_shell

  printf "Setting up cheat.sh\\n"
  if [[ -d ${HOME}/bin ]]; then
    if [[ -n ${UBUNTU} ]]; then
      sudo -H apt update
      sudo -H apt install curl -y
    fi
    if [[ -n ${CENTOS} ]]; then
      sudo -H dnf update -y
      sudo -H dnf install curl -y
    fi
    if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then
      sudo -H yum update
      sudo -H yum install curl -y
    fi
    curl https://cht.sh/:cht.sh > ~/bin/cht.sh
    chmod 750 ${HOME}/bin/cht.sh
  fi
  if [[ -x $(command -v cht.sh) ]]; then
    printf "cht.sh is installed\\n"
  fi

  printf "Creating %s/.zsh.d\\n" "${HOME}"
  mkdir -p ${HOME}/.zsh.d
  if [[ ! -f ${HOME}/.zsh.d/_cht ]]; then
    curl https://cheat.sh/:zsh > ${HOME}/.zsh.d/_cht
  fi

  printf "Creating %s/go-work\\n" "${HOME}"
  mkdir -p ${HOME}/go-work
  if [[ -d ${HOME}/go-work ]]; then
    printf "Created %s/go-work\\n" "${HOME}"
  fi
}

run_setup_or_developer() {
  setup_credential_directories

  if [[ -n ${MACOS} ]]; then
    printf "Creating %s\\n" "${BREWFILE_LOC}"
    mkdir -p ${BREWFILE_LOC}

    rm -f ${BREWFILE_LOC}/Brewfile
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile ${BREWFILE_LOC}/Brewfile
    if [[ -L ${BREWFILE_LOC}/Brewfile ]]; then
      printf "Brewfile is linked\\n"
    fi

    if ! [ -x "$(command -v brew)" ]; then
      install_homebrew
    elif [ -x "$(command -v brew)" ]; then
      brew_update
      printf "Installing other brew stuff...\\n"
      #https://github.com/Homebrew/homebrew-bundle
      brew_tap_if_missing homebrew/bundle
      install_macos_casks

      printf "Cleaning Homebrew up...\\n"
      brew cleanup
    fi

    printf "Updating app store apps via softwareupdate\\n"
    sudo -H softwareupdate --install --all --verbose

    printf "Setting up macOS defaults\\n"
    ${HOME}/scripts/.osx.sh

  fi

  if [[ -n ${UBUNTU} ]]; then
    sudo -H apt update
    if [[ ${FOCAL} ]]; then
      printf "Installing hwe, common, and 20.04 packages\\n"
      sudo -H apt install --install-recommends linux-generic-hwe-20.04 -y
      xargs -a ./ubuntu_common_packages.txt sudo apt install -y
      xargs -a ./ubuntu_2004_packages.txt sudo apt install -y
    elif [[ ${JAMMY} ]]; then
      printf "Installing hwe, common, and 22.04 packages\\n"
      sudo -H apt install --install-recommends linux-generic-hwe-22.04 -y
      check_and_install_nala
      xargs -a ./ubuntu_common_packages.txt sudo nala install -y
      xargs -a ./ubuntu_2204_packages.txt sudo nala install -y
    elif [[ ${NOBLE} ]]; then
      printf "Installing hwe, common, and 24.04 packages\\n"
      sudo -H apt install --install-recommends linux-generic-hwe-24.04 -y
      check_and_install_nala
      xargs -a ./ubuntu_common_packages.txt sudo nala install -y
      xargs -a ./ubuntu_2404_packages.txt sudo nala install -y
    fi

    if [[ -n ${HAS_SNAP} ]]; then
      printf "Installing workstation packages\\n"
      xargs -a ./ubuntu_workstation_packages.txt sudo apt install -y

      printf "Installing workstation snap packages\\n"
      xargs -a ./ubuntu_workstation_snap_packages.txt sudo snap install

    fi

    if [[ -n ${BIONIC} ]]; then
      printf "Installing python 3.8 Ubuntu 18.04\\n"
      sudo -H add-apt-repository ppa:deadsnakes/ppa
      sudo -H apt update
      sudo -H apt install python3.8 -y
    fi

    printf "Installing pyenv\\n"
    curl https://pyenv.run | bash
    if [[ -x $(command -v pyenv) ]]; then
      printf "pyenv is installed\\n"
    fi

    printf "Installing powershell Ubuntu\\n"
    if [[ -n ${BIONIC} ]]; then
      if [[ ! -f ${HOME}/software_downloads/packages-microsoft-prod.deb ]]; then
        # shellcheck disable=SC2046
        wget -O ${HOME}/software_downloads/packages-microsoft-prod.deb https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
        sudo -H dpkg -i ${HOME}/software_downloads/packages-microsoft-prod.deb
        sudo apt update
        sudo -H add-apt-repository universe
        sudo -H apt install powershell -y
        if [[ -x $(command -v pwsh) ]]; then
          printf "pwsh is installed Ubuntu Bionic\\n"
        fi
      fi
    fi
    if [[ -n ${FOCAL} ]]; then
      if [[ ! -f ${HOME}/software_downloads/packages-microsoft-prod.deb ]]; then
        # shellcheck disable=SC2046
        wget -O ${HOME}/software_downloads/packages-microsoft-prod.deb https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
        sudo -H dpkg -i ${HOME}/software_downloads/packages-microsoft-prod.deb
        sudo apt update
        sudo -H add-apt-repository universe
        sudo -H apt install powershell -y
        if [[ -x $(command -v pwsh) ]]; then
          printf "pwsh is installed Ubuntu Focal\\n"
        fi
      fi
    fi
    if [[ -n ${JAMMY} ]]; then
      if [[ ! -f ${HOME}/software_downloads/packages-microsoft-prod.deb ]]; then
        # shellcheck disable=SC2046
        wget -O ${HOME}/software_downloads/packages-microsoft-prod.deb https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
        sudo -H dpkg -i ${HOME}/software_downloads/packages-microsoft-prod.deb
        sudo apt update
        sudo -H add-apt-repository universe
        sudo -H apt install powershell -y
        if [[ -x $(command -v pwsh) ]]; then
          printf "pwsh is installed Ubuntu Jammy\\n"
        fi
      fi
    fi
    if [[ -n ${NOBLE} ]]; then
      if [[ ! -f ${HOME}/software_downloads/packages-microsoft-prod.deb ]]; then
        # shellcheck disable=SC2046
        wget -O ${HOME}/software_downloads/packages-microsoft-prod.deb https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
        sudo -H dpkg -i ${HOME}/software_downloads/packages-microsoft-prod.deb
        sudo apt update
        sudo -H add-apt-repository universe
        sudo -H apt install powershell -y
        if [[ -x $(command -v pwsh) ]]; then
          printf "pwsh is installed Ubuntu Noble\\n"
        fi
      fi
    fi

    printf "Installing Go Ubuntu\\n"
    sudo -H apt update
    case ${GO_VER} in
      1.16)
        pkgs_to_remove="golang-1.15-go golang-1.15-src"
        ;;
      1.17)
        pkgs_to_remove="golang-1.16-go golang-1.16-src"
        ;;
      1.18)
        pkgs_to_remove="golang-1.17-go golang-1.17-src"
        ;;
      1.19)
        pkgs_to_remove="golang-1.18-go golang-1.18-src"
        ;;
      1.20)
        pkgs_to_remove="golang-1.19-go golang-1.19-src"
        ;;
      1.21)
        pkgs_to_remove="golang-1.20-go golang-1.20-src"
        ;;
      1.22)
        pkgs_to_remove="golang-1.21-go golang-1.21-src"
        ;;
      1.23)
        pkgs_to_remove="golang-1.22-go golang-1.22-src"
        ;;
      1.24)
        pkgs_to_remove="golang-1.23-go golang-1.23-src"
        ;;
      1.25)
        pkgs_to_remove="golang-1.24-go golang-1.24-src"
        ;;
      1.26)
        pkgs_to_remove="golang-1.25-go golang-1.25-src"
        ;;
      *)
        printf "Error: Unsupported Go version %s\\n" "${GO_VER}"
        exit 1
        ;;
    esac
    if [[ -n ${pkgs_to_remove} ]]; then
      sudo -H apt remove ${pkgs_to_remove} -y
    fi
    case ${GO_VER} in
      1.16)
        sudo add-apt-repository ppa:longsleep/golang-backports -y
        sudo -H apt install "golang-${GO_VER}-go" -y
        ;;
      1.17)
        sudo add-apt-repository ppa:longsleep/golang-backports -y
        sudo -H apt install "golang-${GO_VER}-go" -y
        ;;
      1.18)
        sudo add-apt-repository ppa:longsleep/golang-backports -y
        sudo -H apt install "golang-${GO_VER}-go" -y
        ;;
      1.19)
        sudo add-apt-repository ppa:longsleep/golang-backports -y
        sudo -H apt install "golang-${GO_VER}-go" -y
        ;;
      1.20)
        sudo add-apt-repository ppa:longsleep/golang-backports -y
        sudo -H apt install "golang-${GO_VER}-go" -y
        ;;
      1.21)
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
        ;;
        1.22)
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
        ;;
        1.23)
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
        ;;
        1.24)
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
        ;;
        1.25)
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
        ;;
        1.26)
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
        ;;
      *)
        printf "Error: Unsupported Go version %s\\n" "${GO_VER}"
        exit 1
        ;;
    esac
    INSTALLED_GO_VER=$(go version | awk '{print $3}' | sed 's/go//g')
    if [[ ${INSTALLED_GO_VER} == "${GO_VER}" ]]; then
      printf "Go %s is installed\\n" "${GO_VER}"
    fi

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
      fi
    fi

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
      echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ jammy main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list
      sudo apt-get update
      sudo apt-get install cloudflare-warp -y
      if [[ -x $(command -v cloudflared) ]]; then
        printf "cloudflared is installed\\n"
      fi
    fi

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

    if [[ -n ${HAS_SNAP} ]]; then
      if [[ ${FOCAL} ]]; then
        printf "Installing Albert Ubuntu Focal\\n"
        # shellcheck disable=SC2046
        echo "deb http://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_$(lsb_release -rs)/ /" | sudo tee /etc/apt/sources.list.d/home:manuelschneid3r.list
        # shellcheck disable=SC2046
        curl -fsSL https://download.opensuse.org/repositories/home:manuelschneid3r/xUbuntu_$(lsb_release -rs)/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/home_manuelschneid3r.gpg > /dev/null
        sudo -H apt update
        sudo -H apt install albert -y
        if [[ -x $(command -v albert) ]]; then
          printf "Albert is installed Ubuntu Focal\\n"
        fi
      elif [[ ${JAMMY} ]]; then
        printf "Installing Albert Ubuntu Jammy\\n"
        # shellcheck disable=SC2046
        echo "deb http://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_$(lsb_release -rs)/ /" | sudo tee /etc/apt/sources.list.d/home:manuelschneid3r.list
        # shellcheck disable=SC2046
        curl -fsSL https://download.opensuse.org/repositories/home:manuelschneid3r/xUbuntu_$(lsb_release -rs)/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/home_manuelschneid3r.gpg > /dev/null
        sudo -H apt update
        sudo -H apt install albert -y
        if [[ -x $(command -v albert) ]]; then
          printf "Albert is installed Ubuntu Jammy\\n"
        fi
      elif [[ ${NOBLE} ]]; then
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
        brew_install_formula claude-code
        if command -v claude &>/dev/null; then
          claude plugins install superpowers
          claude plugins install code-simplifier
          claude plugins install context7
        fi
      fi
      if [[ -n ${HAS_SNAP} ]]; then
        brew_install_formula ollama
      fi
    fi

    if [[ -n ${HAS_SNAP} ]]; then
      printf "Installing microsoft edge\\n"
      sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/edge stable main" > /etc/apt/sources.list.d/microsoft-edge.list'
      sudo -H apt update
      sudo -H apt install microsoft-edge-stable -y
    fi

    if [[ -n ${HAS_DEVTOOLS} ]]; then
      printf "Installing .net8 sdk\\n"
      sudo -H apt install dotnet-sdk-8.0 -y
    fi

    python -m pip install glances
    if [[ -x $(command -v glances) ]]; then
      printf "glances is installed\\n"
    fi
    if [[ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]]; then
      sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VER}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VER}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    fi
    sudo -H apt update
    sudo -H apt install kubectl -y

    if [[ -n ${HAS_SNAP} ]]; then
      printf "snap software with classic option, the other snap packages are installed in ubuntu_workstation_snap_packages.txt\\n"
      sudo snap install atom --classic
      sudo snap install code --classic
      sudo snap install helm --classic
      sudo snap install slack --classic
      sudo snap install certbot --classic
      sudo snap set certbot trust-plugin-with-root=ok
      sudo snap install certbot-dns-route53
    fi
    # can't use snap on wsl2
    if [[ -z ${HAS_SNAP} ]]; then
      curl https://baltocdn.com/helm/signing.asc | sudo gpg --dearmor -o /etc/apt/keyrings/helm-signing.gpg
      echo "deb [signed-by=/etc/apt/keyrings/helm-signing.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
      sudo apt-get update
      sudo apt-get install helm
    fi

    printf "Installing kustomize\\n"
    cd ${HOME}/software_downloads || exit
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    if [[ -f ${HOME}/software_downloads/kustomize ]]; then
      sudo -H mv ${HOME}/software_downloads/kustomize /usr/local/bin/kustomize
      sudo chmod 755 /usr/local/bin/kustomize
      sudo chown root:root /usr/local/bin/kustomize
      if [[ -x $(command -v kustomize) ]]; then
        printf "kustomize is installed\\n"
      fi
    fi

    # fix for missing libssl1.1 on ubuntu 22.04 and it's requirement for installing python3 via pyenv
    if [[ -n ${HAS_DEVTOOLS} ]]; then
      printf "installing libssl1.1\\n"
      echo "deb http://security.ubuntu.com/ubuntu focal-security main" | sudo tee /etc/apt/sources.list.d/focal-security.list
      sudo -H apt update
      sudo -H apt install libssl1.1 -y
    fi

    if [[ ${FOCAL} ]]; then
      sudo -H apt autoremove -y
    elif [[ ${JAMMY} ]]; then
      check_and_install_nala
      sudo -H nala autoremove -y
    elif [[ ${NOBLE} ]]; then
      check_and_install_nala
      sudo -H nala autoremove -y
    fi
  fi

  if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then
    sudo -H dnf update -y
    sudo -H dnf install bzip2 -y
    sudo -H dnf install bzip2-devel -y
    sudo -H dnf install cpan -y
    sudo -H dnf install curl -y
    sudo -H dnf install fzf -y
    sudo -H dnf install gcc -y
    sudo -H dnf install htop -y
    sudo -H dnf install iotop -y
    sudo -H dnf install iperf3 -y
    sudo -H dnf install libffi-devel -y
    sudo -H dnf install make -y
    sudo -H dnf install openssl-devel -y
    sudo -H dnf install python-setuptools -y
    sudo -H dnf install python3-setuptools -y
    sudo -H dnf install python3-devel -y
    sudo -H dnf install python3-pip -y
    sudo -H dnf install readline-devel -y
    sudo -H dnf install sqlite -y
    sudo -H dnf install sqlite-devel -y
    sudo -H dnf install the_silver_searcher -y
    sudo -H dnf install tmux -y
    sudo -H dnf install unzip -y
    sudo -H dnf install wget -y
    sudo -H dnf install xz -y
    sudo -H dnf install xa-devel -y
    sudo -H dnf install zlib-devel -y

    printf "Installing pyenv\\n"
    curl https://pyenv.run | bash
    if [[ -x $(command -v pyenv) ]]; then
      printf "pyenv is installed\\n"
    fi

    printf "Installing shellcheck RHEL\\n"
    if [[ ! -d ${HOME}/software_downloads/shellcheck-v${SHELLCHECK_VER} ]]; then
      wget -O ${HOME}/software_downloads/shellcheck-v${SHELLCHECK_VER}.linux.x86_64.tar.xz https://shellcheck.storage.googleapis.com/shellcheck-v${SHELLCHECK_VER}.linux.x86_64.tar.xz
      xz --decompress ${HOME}/software_downloads/shellcheck-v${SHELLCHECK_VER}.linux.x86_64.tar.xz
      cd ${HOME}/software_downloads || exit
      tar -xf ${HOME}/software_downloads/shellcheck-v${SHELLCHECK_VER}.linux.x86_64.tar
      sudo cp -a ${HOME}/software_downloads/shellcheck-v${SHELLCHECK_VER}/shellcheck /usr/local/bin/
      sudo chmod 755 /usr/local/bin/shellcheck
      sudo chown root:root /usr/local/bin/shellcheck
      if [[ -x $(command -v shellcheck) ]]; then
        printf "shellcheck is installed\\n"
      fi
    fi

    printf "Installing keychain RHEL\\n"
    sudo -H rpm --import http://wiki.psychotic.ninja/RPM-GPG-KEY-psychotic
    sudo -H rpm -ivh http://packages.psychotic.ninja/6/base/i386/RPMS/psychotic-release-1.0.0-1.el6.psychotic.noarch.rpm
    sudo -H yum --enablerepo=psychotic install keychain -y
    if [[ -x $(command -v keychain) ]]; then
      printf "keychain is installed\\n"
    fi

    printf "Installing azure-cli RHEL\\n"
    sudo -H rpm --import http://packages.microsoft.com/keys/microsoft.asc
    sudo -H sh -c 'echo -e "[azure-cli]\nname=Azure CLI\nbaseurl=http://packages.microsoft.com/yumrepos/azure-cli\nenabled=1\ngpgcheck=1\ngpgkey=http://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/azure-cli.repo'
    sudo -H dnf update -y
    sudo -H dnf install azure-cli -y
    if [[ -x $(command -v az) ]]; then
      printf "az is installed\\n"
    fi

    printf "Installing git credential manager RHEL\\n"
    sudo -H dnf install http://github.com/Microsoft/Git-Credential-Manager-for-Mac-and-Linux/releases/download/git-credential-manager-2.0.4/git-credential-manager-2.0.4-1.noarch.rpm -y

    printf "Installing powershell RHEL\\n"
    curl http://packages.microsoft.com/config/rhel/7/prod.repo | sudo -H tee /etc/yum.repos.d/microsoft.repo
    sudo -H dnf update -y
    sudo -H dnf install powershell -y
    if [[ -x $(command -v pwsh) ]]; then
      printf "pwsh is installed\\n"
    fi

    printf "Installing npm RHEL\\n"
    curl -sL http://rpm.nodesource.com/setup_12.x | sudo -E bash -
    sudo -H dnf update -y
    sudo -H dnf install nodejs -y

    printf "Installing glances cpu monitor RHEL\\n"
    sudo -H python -m pip install glances
    if [[ -x $(command -v glances) ]]; then
      printf "glances is installed\\n"
    fi

    printf "Installing go RHEL\\n"
    if [[ ! -f ${HOME}/software_downloads/go${GO_VER}.linux-amd64.tar.gz ]]; then
      wget -O ${HOME}/software_downloads/go${GO_VER}.linux-amd64.tar.gz https://dl.google.com/go/go${GO_VER}.linux-amd64.tar.gz
      sudo tar -C /usr/local -xzf ${HOME}/software_downloads/go${GO_VER}.linux-amd64.tar.gz
      if [[ -x $(command -v go) ]]; then
        printf "go is installed\\n"
      fi
    fi

    printf "Installing google-cloud-sdk RHEL\\n"
    if [[ ! -f /etc/yum.repos.d/google-cloud-sdk.repo ]]; then
      sudo tee -a /etc/yum.repos.d/google-cloud-sdk.repo << EOM
[google-cloud-sdk]
name=Google Cloud SDK
baseurl=http://packages.cloud.google.com/yum/repos/cloud-sdk-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=http://packages.cloud.google.com/yum/doc/yum-key.gpg
       http://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOM
    fi
    sudo -H dnf update -y
    sudo -H dnf install google-cloud-sdk -y
    sudo -H dnf install google-cloud-sdk-app-engine-python -y
    sudo -H dnf install google-cloud-sdk-app-engine-python-extras -y
    sudo -H dnf install google-cloud-sdk-app-engine-go -y

    printf "Installing kubectl RHEL\\n"
    if [[ ! -f /etc/yum.repos.d/kubernetes.repo ]]; then
      echo "${RHEL_KUBECTL_REPO}" | sudo tee /tmp/kubernetes.repo > /dev/null
      sudo chown root:root /tmp/kubernetes.repo
      sudo chmod 644 /tmp/kubernetes.repo
      sudo mv /tmp/kubernetes.repo /etc/yum.repos.d/kubernetes.repo
    fi
    sudo -H dnf update -y
    sudo -H dnf install kubectl -y
    if [[ -x $(command -v kubectl) ]]; then
      printf "kubectl is installed\\n"
    fi

    printf "Installing Hashicorp Packer RHEL\\n"
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

  fi

  if [[ -n ${CENTOS} ]]; then
    sudo -H yum update -y
    sudo -H yum install curl -y
    sudo -H yum install gcc -y
    sudo -H yum install git -y
    sudo -H yum install htop -y
    sudo -H yum install iotop -y
    sudo -H yum install keychain -y
    sudo -H yum install make -y
    sudo -H yum install python-setuptools -y
    sudo -H yum install python3-setuptools -y
    sudo -H yum install python3-pip -y
    sudo -H yum install the_silver_searcher -y
    sudo -H yum install unzip -y
    sudo -H yum install wget -y
    sudo -H yum install zsh -y
  fi

  if [[ -n ${LINUX} ]]; then
    printf "Installing Hashicorp Terraform Linux with tfenv on Linux\\n"
    if [[ ! -d ${HOME}/.tfenv ]]; then
      git clone --recursive https://github.com/tfutils/tfenv.git ${HOME}/.tfenv
    fi

    printf "Linking terraform to /usr/local/bin\\n"
    sudo rm -f /usr/local/bin/terraform
    sudo ln -s ${HOME}/.tfenv/bin/terraform /usr/local/bin/terraform

    printf "Linking tfenv to /usr/local/bin\\n"
    sudo rm -f /usr/local/bin/tfenv
    sudo ln -s ${HOME}/.tfenv/bin/tfenv /usr/local/bin/tfenv

    if [[ -f ${HOME}/.tfenv/bin/tfenv ]]; then
      tfenv install ${TERRAFORM_VER}
    fi

    printf "Installing tflint\\n"
    if [[ -f ${HOME}/software_downloads/tflint_linux_amd64.zip ]]; then
      rm ${HOME}/software_downloads/tflint_linux_amd64.zip
      wget -O ${HOME}/software_downloads/tflint_linux_amd64.zip ${TFLINT_URL}
      sudo -H unzip ${HOME}/software_downloads/tflint_linux_amd64.zip -d /usr/local/bin
      sudo -H chmod 755 /usr/local/bin/tflint
    else
      wget -O ${HOME}/software_downloads/tflint_linux_amd64.zip ${TFLINT_URL}
      sudo -H unzip ${HOME}/software_downloads/tflint_linux_amd64.zip -d /usr/local/bin
      sudo -H chmod 755 /usr/local/bin/tflint
    fi
    if [[ -x $(command -v tflint) ]]; then
      printf "tflint is installed\\n"
    fi

    printf "Installing tfsec\\n"
    if [[ ! -f ${HOME}/software_downloads/tfsec-linux-amd64 ]]; then
      wget -O ${HOME}/software_downloads/tfsec-linux-amd64 ${TFSEC_URL}
      sudo -H mv ${HOME}/software_downloads/tfsec-linux-amd64 /usr/local/bin/tfsec
      sudo -H chmod 755 /usr/local/bin/tfsec
    fi
    if [[ -x $(command -v tfsec) ]]; then
      printf "tfsec is installed\\n"
    fi
  fi

  if [[ -n ${HAS_AWS} ]] && [[ -n ${MACOS} ]]; then
    mkdir -p ${HOME}/software_downloads/awscli
    printf "Installing aws-cli on MacOS\\n"
    if [[ ! -f ${HOME}/software_downloads/awscli/AWSCLIV2.pkg ]]; then
      wget -O ${HOME}/software_downloads/awscli/AWSCLIV2.pkg "https://awscli.amazonaws.com/AWSCLIV2.pkg"
      sudo installer -pkg ${HOME}/software_downloads/awscli/AWSCLIV2.pkg -target /
      rm -f ${HOME}/software_downloads/awscli/AWSCLIV2.pkg
      if [[ -x $(command -v aws) ]]; then
        printf "aws-cli is installed MacOS\\n"
      fi
    fi
  fi
  if [[ -n ${HAS_AWS} ]] && [[ -n ${LINUX} ]]; then
    mkdir -p ${HOME}/software_downloads/awscli
    printf "Installing aws-cli on Linux\\n"
    if [[ ! -f ${HOME}/software_downloads/awscli/awscliv2.zip ]]; then
      wget -O ${HOME}/software_downloads/awscli/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
      unzip ${HOME}/software_downloads/awscli/awscliv2.zip -d ${HOME}/software_downloads/awscli
      sudo -H ${HOME}/software_downloads/awscli/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin
      rm -rf ${HOME}/software_downloads/awscli
      rm -f ${HOME}/software_downloads/awscli/awscliv2.zip
      if [[ -x $(command -v aws) ]]; then
        printf "aws-cli is installed Linux\\n"
      fi
    fi
  fi

  printf "vim plugins setup\\n"
  mkdir -p ${HOME}/.vim/plugged
  if [[ -d ${HOME}/.vim/plugged ]]; then
    chmod 770 ${HOME}/.vim/plugged
  fi
  mkdir -p ${HOME}/.vim/autoload
  if [[ -d ${HOME}/.vim/autoload ]]; then
    chmod 770 ${HOME}/.vim/autoload
  fi
  if [[ ! -f ${HOME}/.vim/autoload/plug.vim ]]; then
    curl -fLo ${HOME}/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  fi
}

run_developer_or_ansible() {
  printf "Installing json2yaml via npm\\n"
  npm install json2yaml

  printf "Installing ruby-install on linux\\n"
  if [[ -n ${LINUX} ]]; then
    if [[ ! -d ${HOME}/software_downloads/ruby-install-${RUBY_INSTALL_VER} ]]; then
      wget -O ${HOME}/software_downloads/ruby-install-${RUBY_INSTALL_VER}.tar.gz https://github.com/postmodern/ruby-install/archive/v${RUBY_INSTALL_VER}.tar.gz
      tar -xzvf ${HOME}/software_downloads/ruby-install-${RUBY_INSTALL_VER}.tar.gz -C ${HOME}/software_downloads/
      cd ${HOME}/software_downloads/ruby-install-${RUBY_INSTALL_VER}/ || exit
      sudo make install
    fi
  fi

  printf "Installing chruby on linux\\n"
  if [[ -n ${LINUX} ]]; then
    if [[ -n ${FOCAL} ]] || [[ -n ${JAMMY} ]]; then
      if [[ ! -d ${HOME}/software_downloads/chruby-${CHRUBY_VER} ]]; then
        wget -O ${HOME}/software_downloads/chruby-${CHRUBY_VER}.tar.gz https://github.com/postmodern/chruby/archive/v${CHRUBY_VER}.tar.gz
        tar -xzvf ${HOME}/software_downloads/chruby-${CHRUBY_VER}.tar.gz -C ${HOME}/software_downloads/
        cd ${HOME}/software_downloads/chruby-${CHRUBY_VER}/ || exit
        sudo make install
      fi
    fi
  fi

  if [[ ! -d ${HOME}/.rubies/ruby-${RUBY_VER}/bin ]]; then
    printf "Install ruby %s\\n" "${RUBY_VER}"
    if [[ -n ${MACOS} ]]; then
      # shellcheck disable=SC2046
      ruby-install ${RUBY_VER} -- --with-openssl-dir=$(brew --prefix openssl@3)
    fi
    if [[ -n ${LINUX} ]]; then
      if [[ -n ${FOCAL} ]]; then
        ruby-install ${RUBY_VER}
      elif [[ -n ${JAMMY} ]]; then
        # Ruby 4.0 requires OpenSSL 3; Jammy ships OpenSSL 3 at /usr by default
        OPENSSL_DIR="$(pkg-config --variable=prefix openssl 2>/dev/null)"
        ruby-install ${RUBY_VER} -- --with-openssl-dir="${OPENSSL_DIR:-/usr}"
      elif [[ -n ${NOBLE} ]]; then
        if ! [[ -d ${HOME}/.rbenv/versions/${RUBY_VER} ]]; then
          # Optional but often helpful: point Ruby at Ubuntu's OpenSSL
          OPENSSL_DIR="$(pkg-config --variable=libdir openssl 2>/dev/null | sed 's#/lib$##')"
          RUBY_CONFIGURE_OPTS="--with-openssl-dir=${OPENSSL_DIR:-/usr}" rbenv install ${RUBY_VER}
          rbenv global ${RUBY_VER}
          rbenv rehash
        fi
      fi
    fi
    INSTALLED_RUBY_VERSION=$(ruby --version | awk '{print $2}')
    if [[ ${INSTALLED_RUBY_VERSION} == "${RUBY_VER}" ]]; then
      printf "ruby %s is installed\\n" "${RUBY_VER}"
    fi
  fi

  if [[ -n ${LINUX} ]]; then
    printf "installing github cli on linux\\n"
    if [[ -n ${UBUNTU} ]]; then
      wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
      sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
      sudo -H apt update
      sudo -H apt install gh
      if [[ -x $(command -v gh) ]]; then
        printf "gh is installed Ubuntu\\n"
      fi
    elif [[ -n ${REDHAT} ]] || [[ -n ${CENTOS} ]] || [[ -n ${FEDORA} ]]; then
      sudo -H dnf install 'dnf-command(config-manager)'
      sudo -H dnf config-manager --add-repo http://cli.github.com/packages/rpm/gh-cli.repo
      sudo dnf install gh --repo gh-cli
      if [[ -x $(command -v gh) ]]; then
        printf "gh is installed RHEL\\n"
      fi
    fi
  fi

  printf "Setup kitchen\\n"
  if [[ -n ${MACOS} ]]; then
    source ${CHRUBY_LOC}/chruby/chruby.sh
    source ${CHRUBY_LOC}/chruby/auto.sh
    chruby ruby-${RUBY_VER}
  elif [[ -n ${LINUX} ]]; then
    if [[ -n ${FOCAL} ]] || [[ -n ${JAMMY} ]]; then
      source ${CHRUBY_LOC}/chruby/chruby.sh
      source ${CHRUBY_LOC}/chruby/auto.sh
      chruby ruby-${RUBY_VER}
    elif [[ -n ${NOBLE} ]]; then
      if ! [[ -d ${HOME}/.rbenv/versions/${RUBY_VER} ]]; then
        rbenv install ${RUBY_VER}
      fi
    fi
  fi

  if [[ -n ${MACOS} ]]; then
    gem install test-kitchen
    gem install kitchen-ansible
    gem install kitchen-docker
    gem install kitchen-inspec
    gem install kitchen-terraform
    gem install kitchen-verifier-serverspec
    gem install bundle
    gem install bundler
  elif [[ -n ${LINUX} ]]; then
    if [[ -n ${FOCAL} ]] || [[ -n ${JAMMY} ]]; then
      gem install test-kitchen
      gem install kitchen-ansible
      gem install kitchen-docker
      gem install kitchen-inspec
      gem install kitchen-terraform
      gem install kitchen-verifier-serverspec
      gem install bundle
      gem install bundler
    elif [[ -n ${NOBLE} ]]; then
      rbenv shell ${RUBY_VER}
      gem install test-kitchen
      gem install kitchen-ansible
      gem install kitchen-docker
      gem install kitchen-inspec
      gem install kitchen-terraform
      gem install kitchen-verifier-serverspec
      gem install bundle
      gem install bundler
    fi
  fi

  printf "Install terraspace\\n"
  gem install terraspace
  if [[ -x $(command -v terraspace) ]]; then
    printf "terraspace is installed\\n"
  fi

  printf "ANSIBLE setup\\n"
  if ! [[ -d ${HOME}/.pyenv/versions/${PYTHON_VER} ]]; then
    if [[ -n "${LINUX:-}" ]]; then
      # Keep pyenv's build definitions current (optional but useful)
      pyenv update

      # zsh-safe cleanup (avoids: zsh: no matches found)
      rm -rf "/tmp/python-build.*" 2>/dev/null || true

      # Force bundled libmpdec + keep Homebrew out of the build environment
      # shellcheck disable=SC2016 # vars expand inside bash -lc at runtime, not here
      env -i \
        HOME="$HOME" USER="$USER" SHELL="${SHELL:-/bin/bash}" TERM="$TERM" \
        PYTHON_VER="${PYTHON_VER}" \
        PYENV_ROOT="$HOME/.pyenv" \
        PYENV_VIRTUALENV_DISABLE_PROMPT=1 \
        PYTHON_CONFIGURE_OPTS="--with-system-libmpdec=no" \
        PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
        bash -lc '
          set -euo pipefail
          export PATH="$PYENV_ROOT/bin:$PATH"
          eval "$(pyenv init -)"
          pyenv install -s -v "${PYTHON_VER}"
        '

    elif [[ -n "${MACOS:-}" ]]; then
      # macOS: normal pyenv install, use system/brew deps as you already have them
      pyenv install -s "${PYTHON_VER}"
    fi
  fi

  if ! [[ $(readlink "${HOME}/.pyenv/versions/ansible") == "${HOME}/.pyenv/versions/${PYTHON_VER}/envs/ansible" ]]; then
    if [[ -n ${HAS_DEVTOOLS} ]]; then
      export PYENV_ROOT="$HOME/.pyenv"
      export PYENV_VIRTUALENV_DISABLE_PROMPT=1
      if quiet_which pyenv; then
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init -)"
      fi
      pyenv virtualenv-delete -f ansible
      pyenv virtualenv "${PYTHON_VER}" ansible
      pyenv activate ansible
      printf "Installing Ansible dependencies...\\n"
      python -m pip install ansible ansible-lint certbot certbot-dns-cloudflare boto3 docker gmpy2 jmespath mpmath netaddr pylint psutil bpytop HttpPy j2cli wheel shell-gpt
    fi
  fi

  printf "personal git repos cloning\\n"
  if ! [[ -d ${PERSONAL_GITREPOS}/dotfiles ]]; then
    git clone git@github.com:brujack/dotfiles.git ${PERSONAL_GITREPOS}/dotfiles
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/docker_container_terraform ]]; then
    git clone git@github.com:brujack/docker_container_terraform.git ${PERSONAL_GITREPOS}/docker_container_terraform
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/docker_container_terraform_packer_ansible ]]; then
    git clone git@github.com:brujack/docker_container_terraform_packer_ansible.git ${PERSONAL_GITREPOS}/docker_container_terraform_packer_ansible
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/kubernetes ]]; then
    git clone git@github.com:brujack/kubernetes.git ${PERSONAL_GITREPOS}/kubernetes
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/pfsense_config ]]; then
    git clone git@github.com:brujack/pfsense_config.git ${PERSONAL_GITREPOS}/pfsense_config
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/python-learning ]]; then
    git clone git@github.com:brujack/python-learning.git ${PERSONAL_GITREPOS}/python-learning
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/terraform_ansible ]]; then
    git clone git@github.com:brujack/terraform_ansible.git ${PERSONAL_GITREPOS}/terraform_ansible
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/terraspace_env ]]; then
    git clone git@github.com:brujack/terraspace_env.git ${PERSONAL_GITREPOS}/terraspace_env
  fi

}

run_update() {
  local _run_all=0
  _any_update_flag || _run_all=1

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_BREW:-} ]]; then
    if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
      brew_update
      printf "Updating app store apps softwareupdate\\n"
      sudo -H softwareupdate --install --all --verbose
    fi
  fi

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_CLAUDE:-} ]]; then
    if command -v claude &>/dev/null; then
      printf "Updating Claude plugins\\n"
      claude plugins update superpowers && claude plugins update code-simplifier && claude plugins update context7
      printf "Updated Claude plugins\\n"
    fi
  fi

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_MAS:-} ]]; then
    update_system_packages
  fi

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_PIP:-} ]]; then
    printf "Updating pip3 packages\n"
    if [[ -n ${HAS_DEVTOOLS} ]]; then
      export PYENV_ROOT="$HOME/.pyenv"
      export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"

      if command -v pyenv >/dev/null 2>&1; then
        eval "$(pyenv init -)"
        eval "$(pyenv virtualenv-init -)" 2>/dev/null || true
      fi

      pyenv shell ansible 2>/dev/null || true
      PYTHON="$(pyenv which python 2>/dev/null || command -v python3)"

      "$PYTHON" -m pip install -U pip setuptools wheel

      "$PYTHON" - <<'PY'
import json, subprocess, sys

cmd = [sys.executable, "-m", "pip", "list", "--outdated", "--format=json"]
out = subprocess.check_output(cmd, text=True)
pkgs = [p["name"] for p in json.loads(out)]

if pkgs:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-U", *pkgs])
PY

      "$PYTHON" -m pip check || true
      printf "Updated pip packages\n"
    fi
  fi

  if [[ ${_run_all} -eq 1 ]]; then
    update_aws_cli
    update_rust
    if [[ -d ${HOME}/.tfenv ]]; then
      printf "Updating tfenv\\n"
      cd ${HOME}/.tfenv || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    fi
    if [[ -d ${HOME}/.oh-my-zsh ]]; then
      printf "Updating oh-my-zsh\\n"
      cd ${HOME}/.oh-my-zsh || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    fi
    if [[ -d ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k ]]; then
      printf "Updating powerlevel10k\\n"
      cd ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    fi
    if [[ -d ${HOME}/.tmux/plugins/tpm ]]; then
      printf "Updating tpm\\n"
      cd ${HOME}/.tmux/plugins/tpm || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    fi
    if [[ -f ${HOME}/bin/cht.sh ]]; then
      printf "Updating cheat.sh\\n"
      curl https://cht.sh/:cht.sh > ~/bin/cht.sh
      chmod 754 ${HOME}/bin/cht.sh
    fi
    if [[ -f ${HOME}/.zsh.d/_cht ]]; then
      printf "Updating cheat.sh tab completion\\n"
      curl https://cheat.sh/:zsh > ${HOME}/.zsh.d/_cht
    fi
    if [[ -d ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then
      printf "Updating zsh-autosuggestions\\n"
      cd ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    fi
  fi

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_GEMS:-} ]]; then
    printf "updating ruby gems\\n"
    gem update
  fi
}

_fetch_github_latest() {
  local _repo="$1"
  local -a _curl_args=(-sf)
  if [[ -n ${GITHUB_TOKEN:-} ]]; then
    _curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  curl "${_curl_args[@]}" \
    "https://api.github.com/repos/${_repo}/releases/latest" \
    | grep '"tag_name"' \
    | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' \
    | sed 's/^v//'
}

_check_one_version() {
  local _tool="$1" _pinned="$2" _repo="$3" _cmd="$4" _regex="$5"

  if ! command -v "${_tool}" &>/dev/null; then
    printf "  [SKIP]     %-12s not installed\n" "${_tool}"
    return 0
  fi

  local _latest
  _latest=$(_fetch_github_latest "${_repo}")
  if [[ -z "${_latest}" ]]; then
    printf "  [WARN]     %-12s could not fetch latest version\n" "${_tool}"
    return 0
  fi

  local _raw _installed
  _raw=$(${_cmd} 2>&1)
  _installed=$(printf '%s' "${_raw}" | grep -oE "${_regex}" | head -1)

  if [[ -z "${_installed}" ]]; then
    printf "  [WARN]     %-12s could not parse installed version\n" "${_tool}"
    return 0
  fi

  _installed="${_installed#v}"
  # Strip any leading non-numeric prefix (handles golang's "go1.x.y" tag format)
  _latest="${_latest#"${_latest%%[0-9]*}"}"

  if [[ "${_installed}" == "${_latest}" ]]; then
    printf "  [OK]       %-12s pinned=%-10s latest=%s\n" "${_tool}" "${_pinned}" "${_latest}"
    return 0
  else
    printf "  [OUTDATED] %-12s pinned=%-10s latest=%s  installed=%s\n" \
      "${_tool}" "${_pinned}" "${_latest}" "${_installed}"
    return 1
  fi
}

run_check_versions() {
  local _outdated=0 _skipped=0 _warned=0 _ok=0

  printf "=== Version Check ===\n\n"

  _run_cv_check() {
    local _tool="$1" _pinned="$2" _repo="$3" _cmd="$4" _regex="$5"
    local _out
    _out=$(_check_one_version "${_tool}" "${_pinned}" "${_repo}" "${_cmd}" "${_regex}" 2>&1)
    printf '%s\n' "${_out}"
    if [[ "${_out}" == *"[SKIP]"* ]];       then _skipped=$(( _skipped + 1 ))
    elif [[ "${_out}" == *"[WARN]"* ]];     then _warned=$(( _warned + 1 ))
    elif [[ "${_out}" == *"[OK]"* ]];       then _ok=$(( _ok + 1 ))
    elif [[ "${_out}" == *"[OUTDATED]"* ]]; then _outdated=$(( _outdated + 1 )); fi
  }

  _run_cv_check "go"         "${GO_VER}"         "golang/go"           "go version"           "[0-9]+\.[0-9]+(\.[0-9]+)?"
  _run_cv_check "python3"    "${PYTHON_VER}"      "python/cpython"      "python3 --version"    "[0-9]+\.[0-9]+\.[0-9]+"
  _run_cv_check "ruby"       "${RUBY_VER}"        "ruby/ruby"           "ruby --version"       "[0-9]+\.[0-9]+\.[0-9]+"
  _run_cv_check "zsh"        "${ZSH_VER}"         "zsh-users/zsh"       "zsh --version"        "[0-9]+\.[0-9]+(\.[0-9]+)?"
  _run_cv_check "yq"         "${YQ_VER}"          "mikefarah/yq"        "yq --version"         "[0-9]+\.[0-9]+\.[0-9]+"
  _run_cv_check "shellcheck" "${SHELLCHECK_VER}"  "koalaman/shellcheck" "shellcheck --version" "[0-9]+\.[0-9]+\.[0-9]+"
  _run_cv_check "vagrant"    "${VAGRANT_VER}"     "hashicorp/vagrant"   "vagrant --version"    "[0-9]+\.[0-9]+\.[0-9]+"

  printf "\n%d outdated, %d skipped, %d warnings, %d OK\n" \
    "${_outdated}" "${_skipped}" "${_warned}" "${_ok}"

  [[ ${_outdated} -eq 0 ]]
}
