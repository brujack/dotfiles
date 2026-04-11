#!/usr/bin/env bash
# lib/linux.sh — Linux-specific install and update functions

install_git_linux() {
  log_info "Installing git"
  if [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "Ubuntu" ]]; then
    log_info "Installing git via apt"
    sudo -H add-apt-repository ppa:git-core/ppa -y
    sudo -H apt update
    sudo -H apt dist-upgrade -y
    sudo -H apt install git -y
  elif [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "CentOS Linux" ]]; then
    log_info "Installing git via yum"
    sudo -H yum update -y
    sudo -H yum install git -y
  elif [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "Fedora" ]]; then
    log_info "Installing git via dnf"
    sudo -H dnf update -y
    sudo -H dnf install git -y
  fi
  # because the version of git is so old on redhat, we need to install a newer version by compiling it
  if [[ -n ${REDHAT} ]]; then
    sudo -H dnf update -y
    sudo -H dnf install asciidoc -y
    sudo -H dnf install autoconf -y
    sudo -H dnf install cpan -y
    sudo -H dnf install docbook2X -y
    sudo -H dnf install make -y
    sudo -H dnf install perl-App-cpanminus -y
    sudo -H dnf install perl-ExtUtils-MakeMaker -y
    sudo -H dnf install perl-IO-Socket-SSL -y
    sudo -H dnf install wget -y
    sudo -H dnf install xmlto -y
    #cpan to properly compile git on redhat
    cpan App::cpanminus
    cpanm Test::Simple
    cpanm Fatal
    cpanm XML::SAX
    if [[ ! -f ${HOME}/software_downloads/git-${GIT_VER}.tar.gz ]]; then
      log_info "Installing Redhat git"
      wget -O ${HOME}/software_downloads/git-${GIT_VER}.tar.gz ${GIT_URL}/git-${GIT_VER}.tar.gz
      tar -zxvf ${HOME}/software_downloads/git-${GIT_VER}.tar.gz -C ${HOME}/software_downloads
      cd ${HOME}/software_downloads/git-${GIT_VER} || exit
      make configure
      ./configure --prefix=/usr
      make -j "$(nproc)" all doc info
      sudo -H make install install-doc install-info
      if ! [[ -x "$(command -v git)" ]]; then
        log_error "Git is not installed Redhat"
        exit 1
      fi
      INSTALLED_GIT_VERSION=$(git --version | awk '{print $3}')
      if [[ "${INSTALLED_GIT_VERSION}" == "${GIT_VER}" ]]; then
        log_info "Git ${GIT_VER} is installed Redhat"
      else
        log_error "Git ${GIT_VER} is not installed Redhat"
        exit 1
      fi
    fi
  fi
  log_info "Installed git"
}

install_zsh_linux() {
  log_info "Installing zsh"
  if [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "Ubuntu" ]]; then
    log_info "Installing zsh via apt"
    sudo -H apt update
    sudo -H apt dist-upgrade -y
    sudo -H apt install zsh zsh-doc -y
  elif [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "CentOS Linux" ]]; then
    log_info "Installing zsh via yum"
    sudo -H yum update -y
    sudo -H yum install zsh -y
  elif [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "Fedora" ]]; then
    log_info "Installing zsh via dnf"
    sudo -H dnf update -y
    sudo -H dnf install zsh -y
  fi
  # because the version of zsh is so old on redhat, we need to install a newer version by compiling it
  if [[ -n ${REDHAT} ]]; then
    if rhel_installed_package zsh; then
      sudo -H yum remove zsh -y
    fi
    sudo -H yum update
    sudo -H yum install gcc -y
    sudo -H yum install make -y
    sudo -H yum install ncurses-devel -y
    if [[ ! -f ${HOME}/software_downloads/zsh-${ZSH_VER}.tar.xz ]]; then
      log_info "Installing Redhat zsh"
      wget -O ${HOME}/software_downloads/zsh-${ZSH_VER}.tar.xz http://www.zsh.org/pub/zsh-${ZSH_VER}.tar.xz
      tar -xvf ${HOME}/software_downloads/zsh-${ZSH_VER}.tar.xz -C ${HOME}/software_downloads
      cd ${HOME}/software_downloads/zsh-${ZSH_VER} || exit
      ./configure --prefix=/usr/local --bindir=/usr/local/bin --sysconfdir=/etc/zsh --enable-etcdir=/etc/zsh
      make
      sudo -H make install
      # shellcheck disable=SC2143 # grep -Fxq has no output; checking if line absent
      if [[ ! $(grep -Fxq "/usr/local/bin/zsh" /etc/shells) ]]; then
        sudo -H sh -c 'echo /usr/local/bin/zsh >> /etc/shells'
      fi
      # shellcheck disable=SC2143 # grep -Fxq has no output; checking if line absent
      if [[ ! $(grep -Fxq "/bin/zsh" /etc/shells) ]]; then
        sudo -H sh -c 'echo /bin/zsh >> /etc/shells'
      fi
    fi
    if [[ -f /bin/zsh ]]; then
      sudo -H rm -f /bin/zsh
    fi
    if [[ ! -L /bin/zsh ]]; then
      if [[ -f /usr/local/bin/zsh ]]; then
        sudo -H ln -s /usr/local/bin/zsh /bin/zsh
      fi
    fi
    if ! [[ -x "$(command -v zsh)" ]]; then
      log_error "zsh is not installed Redhat"
      exit 1
    fi
    INSTALLED_ZSH_VERSION=$(zsh --version | awk '{print $2}')
    if [[ "${INSTALLED_ZSH_VERSION}" == "${ZSH_VER}" ]]; then
      log_info "zsh ${ZSH_VER} is installed Redhat"
    else
      log_error "zsh ${ZSH_VER} is not installed Redhat"
      exit 1
    fi
  fi
  log_info "Installed zsh"
}

install_bats() {
  if quiet_which bats; then
    log_info "bats already installed"
    return 0
  fi

  log_info "Installing bats"

  if [[ -n ${UBUNTU} ]]; then
    sudo -H apt-get install -y bats
  elif [[ -n ${REDHAT} ]] || [[ -n ${CENTOS} ]] || [[ -n ${FEDORA} ]]; then
    curl -fsSL "https://github.com/bats-core/bats-core/archive/refs/tags/v${BATS_VER}.tar.gz" \
      -o /tmp/bats.tar.gz
    tar -xzf /tmp/bats.tar.gz -C /tmp
    sudo -H /tmp/bats-core-${BATS_VER}/install.sh /usr/local
    rm -rf /tmp/bats.tar.gz /tmp/bats-core-${BATS_VER}
  else
    log_warn "Unsupported platform for bats install"
    return 1
  fi
}

update_system_packages() {
  if [[ -n ${UBUNTU} ]]; then
    sudo -H apt update
    if [[ -n ${FOCAL} ]]; then
      sudo -H apt autoremove -y
    elif [[ -n ${JAMMY} ]]; then
      check_and_install_nala
      sudo -H nala full-upgrade -y
      sudo -H nala autoremove -y
    elif [[ -n ${NOBLE} ]]; then
      check_and_install_nala
      sudo -H nala full-upgrade -y
      sudo -H nala autoremove -y
    fi
    sudo snap refresh
    log_info "Updated snap packages"
  fi
  if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then
    sudo -H dnf update -y
    log_info "Updated dnf packages"
  fi
  if [[ -n ${CENTOS} ]]; then
    sudo -H yum update -y
    log_info "Updated yum packages"
  fi
}

install_ubuntu_packages() {
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
}

install_rhel_packages() {
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
}

install_centos_packages() {
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
}

install_linux_packages() {
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
}
