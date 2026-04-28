#!/usr/bin/env bash
# lib/linux_shared.sh — cross-distro Linux install functions (git, zsh, bats, updates)

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
      cd ${HOME}/software_downloads/git-${GIT_VER} || return 1
      make configure
      ./configure --prefix=/usr
      make -j "$(nproc)" all doc info
      sudo -H make install install-doc install-info
      if ! [[ -x "$(command -v git)" ]]; then
        log_error "Git is not installed Redhat"
        return 1
      fi
      INSTALLED_GIT_VERSION=$(git --version | awk '{print $3}')
      if [[ "${INSTALLED_GIT_VERSION}" == "${GIT_VER}" ]]; then
        log_info "Git ${GIT_VER} is installed Redhat"
      else
        log_error "Git ${GIT_VER} is not installed Redhat"
        return 1
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
      cd ${HOME}/software_downloads/zsh-${ZSH_VER} || return 1
      ./configure --prefix=/usr/local --bindir=/usr/local/bin --sysconfdir=/etc/zsh --enable-etcdir=/etc/zsh
      make
      sudo -H make install
      if ! grep -Fxq "/usr/local/bin/zsh" /etc/shells; then
        sudo -H sh -c 'echo /usr/local/bin/zsh >> /etc/shells'
      fi
      if ! grep -Fxq "/bin/zsh" /etc/shells; then
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
      return 1
    fi
    INSTALLED_ZSH_VERSION=$(zsh --version | awk '{print $2}')
    if [[ "${INSTALLED_ZSH_VERSION}" == "${ZSH_VER}" ]]; then
      log_info "zsh ${ZSH_VER} is installed Redhat"
    else
      log_error "zsh ${ZSH_VER} is not installed Redhat"
      return 1
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

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
