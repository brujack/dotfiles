#!/usr/bin/env bash

# software versions to install
CF_TERRAFORMING_VER="0.16.1"
CHRUBY_VER="0.3.9"
CONSUL_VER="1.16.0"
DOCKER_COMPOSE_VER="v2.20.2"
GIT_VER="2.43.0"
GO_VER="1.22"
KIND_VER="0.20.0"
NOMAD_VER="1.6.1"
PACKER_VER="1.9.2"
PYTHON_VER="3.12.4"
RUBY_INSTALL_VER="0.9.1"
RUBY_VER="3.3.3"
SHELLCHECK_VER="0.9.0"
TERRAFORM_VER="1.3.5"
TFLINT_VER="0.49.0"
TFSEC_VER="1.28.4"
VAGRANT_VER="2.3.7"
VAULT_VER="1.14.1"
VIRTUALBOX_VER="virtualbox-7.0"
YQ_VER="4.40.3"
ZSH_VER="5.9"
KUBERNETES_VER="v1.30"

CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v${CF_TERRAFORMING_VER}/cf-terraforming_${CF_TERRAFORMING_VER}_linux_amd64.tar.gz"
GIT_URL="https://mirrors.edge.kernel.org/pub/software/scm/git"
DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VER}/docker-compose-$(uname -s)-$(uname -m)"
HASHICORP_URL="https://releases.hashicorp.com"
KIND_URL="https://kind.sigs.k8s.io/dl/v${KIND_VER}/kind-linux-amd64"
TELEPRESENCE_URL="https://app.getambassador.io/download/tel2/linux/amd64/latest/telepresence"
TFLINT_URL="https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VER}/tflint_linux_amd64.zip"
TFSEC_URL="https://github.com/liamg/tfsec/releases/download/v${TFSEC_VER}/tfsec-linux-amd64"
YQ_URL="https://github.com/mikefarah/yq/releases/download/v${YQ_VER}/yq_linux_amd64"

# following go vars are for linux where go version is >= 1.21
GO_DOWNLOAD_FILENAME="go1.21.1.linux-amd64.tar.gz"
GO_DOWNLOAD_URL="https://go.dev/dl/${GO_DOWNLOAD_FILENAME}"

RHEL_KUBECTL_REPO="cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VER}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VER}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF"

# locations of directories
BREWFILE_LOC="${HOME}/brew"
DOTFILES="dotfiles"
GITREPOS="${HOME}/git-repos"
PERSONAL_GITREPOS="${GITREPOS}/personal"
WSL_HOME="/mnt/c/Users/${USER}"

HOSTNAME=$(hostname -s)

# setup some functions
quiet_which() {
  which "$1" &>/dev/null
}

rhel_installed_package() {
  if ! command -v yum &>/dev/null; then
    printf "yum command not found! Please install yum or run on a supported system.\\n"
    return 1
  fi
  yum list installed "$@" >/dev/null 2>&1
}

install_rosetta() {
  # Determine OS version
  # Save current IFS state
  OLDIFS=$IFS
  IFS='.' read osvers_major osvers_minor osvers_dot_version <<< "$(/usr/bin/sw_vers -productVersion)"

  # Restore IFS to previous state
  IFS=$OLDIFS
  exitcode=0

  # Check to see if the Mac is reporting itself as running macOS 11 or higher
  if [[ ${osvers_major} -ge 11 ]]; then

    # Check to see if the Mac needs Rosetta installed by testing the processor
    processor=$(/usr/sbin/sysctl -n machdep.cpu.brand_string)

    if [[ "$processor" == *"Intel"* ]]; then
      printf "%s processor installed. No need to install Rosetta.\\n" "${processor}"
    else

      # Check for Rosetta "oahd" process. If not found, perform a non-interactive install of Rosetta.
      if /usr/bin/pgrep oahd >/dev/null 2>&1; then
          printf "Rosetta is already installed and running. Nothing to do.\\n"
      else
          /usr/sbin/softwareupdate --install-rosetta --agree-to-license

          if [[ $? -eq 0 ]]; then
            printf "Rosetta has been successfully installed.\\n"
          else
            printf "Rosetta installation failed!\\n"
            exitcode=1
          fi
      fi
    fi
  else
    printf "Mac is running macOS %s\\n" "$osvers_major.$osvers_minor.$osvers_dot_version."
    printf "No need to install Rosetta on this version of macOS.\\n"
  fi

  return $exitcode
}


install_homebrew() {
  if [[ "$(uname -s)" == "Darwin" ]]; then

    printf "Installing Xcode Command Line Tools...\\n"
    if ! xcode-select --print-path &>/dev/null; then
      printf "Installing Xcode Command Line Tools...\\n"
      xcode-select --install

      # Check if the installation was successful
      if [[ $? -ne 0 ]]; then
        printf "Failed to install Xcode Command Line Tools. Aborting.\\n"
        return 1
      fi

      # Accept Xcode license
      printf "Accepting Xcode license...\\n"
      sudo xcodebuild -license accept
      sudo xcodebuild -runFirstLaunch

      # Check if the license acceptance was successful
      if [[ $? -ne 0 ]]; then
        printf "Failed to accept Xcode license. Aborting.\\n"
        return 1
      fi
    fi
  fi

  printf "Installing Homebrew...\\n"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Check if the installation was successful
  if [[ $? -ne 0 ]]; then
    printf "Failed to install Homebrew. Aborting.\\n"
    return 1
  fi

  printf "Homebrew has been successfully installed.\\n"
  return 0
}


brew_update() {
  if ! command -v brew &>/dev/null; then
    printf "Homebrew not found, installing Homebrew...\\n"
    install_homebrew
  fi

  printf "Updating Homebrew...\\n"
  if ! brew update; then
    printf "Failed to update Homebrew. Aborting.\\n"
    return 1
  fi

  printf "Upgrading installed formulae...\\n"
  if ! brew upgrade; then
    printf "Failed to upgrade formulae. Aborting.\\n"
    return 1
  fi

  printf "Upgrading installed casks...\\n"
  if ! brew upgrade --cask --greedy; then
    printf "Failed to upgrade casks. Aborting.\\n"
    return 1
  fi

  printf "Cleaning Homebrew up...\\n"
  if ! brew cleanup; then
    printf "Failed to clean up. Aborting.\\n"
    return 1
  fi

  printf "Homebrew update process completed successfully.\\n"
  return 0
}

install_git() {
  printf "Installing git\\n"
  if [[ "$(uname -s)" != "Darwin" ]]; then
    if brew list | grep '^git$' &> /dev/null; then
      printf "Git (from Homebrew) is already installed.\\n"
      return 0
    fi
    printf "Installing git via Homebrew.\\n"
    if [[ -n ${MACOS} ]]; then
      if ! command -v brew &> /dev/null; then
        install_homebrew
      fi
      if command -v brew &> /dev/null; then
        brew install git
      else
        printf "Failed to install Homebrew. Cannot install Git.\\n"
        return 1
      fi
    fi
  elif [[ "$(uname -s)" == "Linux" ]]; then
    if [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "Ubuntu" ]]; then
      printf "Installing git via apt\\n"
      sudo -H add-apt-repository ppa:git-core/ppa -y
      sudo -H apt update
      sudo -H apt dist-upgrade -y
      sudo -H apt install git -y
    elif [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "CentOS Linux" ]]; then
      printf "Installing git via yum\\n"
      sudo -H yum update -y
      sudo -H yum install git -y
    elif [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "Fedora" ]]; then
      printf "Installing git via dnf\\n"
      sudo -H dnf update -y
      sudo -H dnf install git -y
    fi
  fi
  printf "Installed git\\n"
}

install_zsh() {
  printf "Installing zsh\\n"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if brew list | grep '^zsh$' &> /dev/null; then
      printf "zsh (from Homebrew) is already installed.\\n"
      return 0
    fi
    printf "Installing zsh via Homebrew.\\n"
    if [[ -n ${MACOS} ]]; then
      if ! command -v brew &> /dev/null; then
        install_homebrew
      fi
      if command -v brew &> /dev/null; then
        brew install zsh
      else
        printf "Failed to install Homebrew. Cannot install zsh.\\n"
        return 1
      fi
    fi
  elif [[ "$(uname -s)" == "Linux" ]]; then
    if [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "Ubuntu" ]]; then
      printf "Installing zsh via apt\\n"
      sudo -H apt update
      sudo -H apt dist-upgrade -y
      sudo -H apt install zsh zsh-doc -y
    elif [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "CentOS Linux" ]]; then
      printf "Installing zsh via yum\\n"
      sudo -H yum update -y
      sudo -H yum install zsh -y
    elif [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "Fedora" ]]; then
      printf "Installing zsh via dnf\\n"
      sudo -H dnf update -y
      sudo -H dnf install zsh -y
    fi
  fi
  printf "Installed zsh\\n"
}

check_and_install_nala() {
  printf "Installing nala\\n"
  if [[ "$(uname -s)" = "Linux" ]]; then
    if [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') = "Ubuntu" ]]; then
      if ! [ -x "$(command -v nala)" ]; then
        printf "Installing nala via apt\\n"
        wget -O ${HOME}/software_downloads/volian-archive-keyring_0.2.0_all.deb https://gitlab.com/-/project/39215670/uploads/d9473098bc12525687dc9aca43d50159/volian-archive-keyring_0.2.0_all.deb
        sudo -H dpkg --install ${HOME}/software_downloads/volian-archive-keyring_0.2.0_all.deb
        wget -O ${HOME}/software_downloads/volian-archive-nala_0.2.0_all.deb https://gitlab.com/-/project/39215670/uploads/d00e44faaf2cc8aad526ca520165a0af/volian-archive-nala_0.2.0_all.deb
        sudo -H dpkg --install ${HOME}/software_downloads/volian-archive-nala_0.2.0_all.deb
        sudo -H apt update
        sudo -H apt install nala -y
      fi
    fi
  fi
}

usage() {
  cat << EOF
Usage: $0 -t <type> [-w]
Types:
  setup_user : Sets up a basic user environment for the current user
  setup      : Runs a full machine and developer setup
  developer  : Runs a developer setup with packages and python virtual environment for running ansible
  ansible    : Just runs the ansible setup using a python virtual environment. Typically used after a python update
  update     : Does a system update of packages including brew packages
Options:
  -w : Optional -- Specify w for a redhat computer, sets up terraform 0.11 instead of default 0.12
EOF
  exit 0
}

process_args() {
  local arg OPTARG
  while getopts ":ht:w" arg; do
    case ${arg} in
      t)
        case ${OPTARG} in
          setup_user) readonly SETUP_USER=1 ;;
          setup) readonly SETUP=1 ;;
          developer) readonly DEVELOPER=1 ;;
          ansible) readonly ANSIBLE=1 ;;
          update) readonly UPDATE=1 ;;
          *) echo "Invalid option for -t"; usage; exit 1 ;;
        esac
        ;;
      w) readonly WORK=1 ;;
      h | *) usage; exit 0 ;;
    esac
  done
}

[[ $# -eq 0 ]] && usage
process_args "$@"

# choose which env we are running on
[[ $(uname -s) = "Darwin" ]] && readonly MACOS=1
[[ $(uname -s) = "Linux" ]] && readonly LINUX=1

if [[ -n ${LINUX} ]]; then
  LINUX_TYPE=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
  [[ ${LINUX_TYPE} = "Ubuntu" ]] && readonly UBUNTU=1
  [[ ${LINUX_TYPE} = "CentOS Linux" ]] && readonly CENTOS=1
  [[ ${LINUX_TYPE} = "Red Hat Enterprise Linux Server" ]] && readonly REDHAT=1
  [[ ${LINUX_TYPE} = "Fedora" ]] && readonly FEDORA=1
  [[ ${LINUX_TYPE} = "elementary OS" ]] && readonly UBUNTU=1 && readonly ELEMENTARY=1
fi

if [[ -n ${UBUNTU} ]]; then
  UBUNTU_VERSION=$(lsb_release -rs)
  [[ ${UBUNTU_VERSION} = "18.04" ]] && readonly BIONIC=1
  [[ ${UBUNTU_VERSION} = "20.04" ]] && readonly FOCAL=1
  [[ ${UBUNTU_VERSION} = "22.04" ]] && readonly JAMMY=1
  [[ ${UBUNTU_VERSION} = "24.04" ]] && readonly NOBLE=1
  [[ ${UBUNTU_VERSION} = "6" ]] && readonly FOCAL=1 # elementary os
fi

[[ $(uname -r) =~ microsoft ]] && readonly WINDOWS=1
[[ $(hostname -s) = "laptop" ]] && readonly LAPTOP=1
[[ $(hostname -s) = "studio" ]] && readonly STUDIO=1
[[ $(hostname -s) = "reception" ]] && readonly RECEPTION=1
[[ $(hostname -s) = "office" ]] && readonly OFFICE=1
[[ $(hostname -s) = "home-1" ]] && readonly HOMES=1
[[ $(hostname -s) = "virtualmachine1c4f85d6" ]] && readonly WORKSTATION=1
[[ $(hostname -s) = "workstation" ]] && readonly WORKSTATION=1
[[ $(hostname -s) = "cruncher" ]] && readonly CRUNCHER=1
[[ $(hostname -s) = "virtualmachine1c4f85d6" ]] && readonly WORKSTATION=1

# setup variables based off of environment
if [[ -n ${MACOS} ]]; then
  if [[ -n ${RATNA} ]]; then
    CHRUBY_LOC="/usr/local/opt/chruby/share"
  elif [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]]; then
    CHRUBY_LOC="/opt/homebrew/opt/chruby/share"
  fi
elif [[ -n ${LINUX} ]]; then
  CHRUBY_LOC="/usr/local/share"
fi

# Setup is run rarely as it should be run when setting up a new device or when doing a controlled change after changing items in setup
# The following code is used to setup the base system with some base packages and the basic layout of the users home directory
if [[ ${SETUP} || ${SETUP_USER} ]]; then
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
      printf "Installing Redhat git\\n"
      wget -O ${HOME}/software_downloads/git-${GIT_VER}.tar.gz ${GIT_URL}/git-${GIT_VER}.tar.gz
      tar -zxvf ${HOME}/software_downloads/git-${GIT_VER}.tar.gz -C ${HOME}/software_downloads
      cd ${HOME}/software_downloads/git-${GIT_VER} || exit
      make configure
      ./configure --prefix=/usr
      make -j $(nproc) all doc info
      sudo -H make install install-doc install-info
      if ! [[ -x "$(command -v git)" ]]; then
        printf "Git is not installed Redhat\\n"
        exit 1
      fi
      INSTALLED_GIT_VERSION=$(git --version | awk '{print $3}')
      if [[ "${INSTALLED_GIT_VERSION}" == "${GIT_VER}" ]]; then
        printf "Git %s is installed Redhat\\n" ${GIT_VER}
      else
        printf "Git %s is not installed Redhat\\n" ${GIT_VER}
        exit 1
      fi
    fi
  fi

  if [[ ${MACOS} || ${UBUNTU} || ${FEDORA} || ${CENTOS} ]]; then
    install_zsh
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
      printf "Installing Redhat zsh\\n"
      wget -O ${HOME}/software_downloads/zsh-${ZSH_VER}.tar.xz http://www.zsh.org/pub/zsh-${ZSH_VER}.tar.xz
      tar -xvf ${HOME}/software_downloads/zsh-${ZSH_VER}.tar.xz -C ${HOME}/software_downloads
      cd ${HOME}/software_downloads/zsh-${ZSH_VER} || exit
      ./configure --prefix=/usr/local --bindir=/usr/local/bin --sysconfdir=/etc/zsh --enable-etcdir=/etc/zsh
      make
      sudo -H make install
      if [[ ! $(grep -Fxq "/usr/local/bin/zsh" /etc/shells) ]]; then
        sudo -H sh -c 'echo /usr/local/bin/zsh >> /etc/shells'
      fi
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
        printf "zsh is not installed Redhat\\n"
        exit 1
      fi
      INSTALLED_ZSH_VERSION=$(zsh --version | awk '{print $2}')
      if [[ "${INSTALLED_ZSH_VERSION}" == "${ZSH_VER}" ]]; then
        printf "zsh %s is installed Redhat\\n" ${ZSH_VER}
      else
        printf "zsh %s is not installed Redhat\\n" ${ZSH_VER}
        exit 1
      fi
  fi

  printf "Creating %s/bin\\n" "${HOME}"
  mkdir -p ${HOME}/bin

  printf "Creating %s\\n" "${PERSONAL_GITREPOS}"
  mkdir -p ${PERSONAL_GITREPOS}

  printf "Copying %s from Github\\n" "${DOTFILES}"
  if [[ ! -d ${PERSONAL_GITREPOS}/${DOTFILES} ]]; then
    cd ${HOME} || return
    git clone --recursive git@github.com:brujack/${DOTFILES}.git ${PERSONAL_GITREPOS}/${DOTFILES}
    # for regular https github used on machines that will not push changes
    # git clone --recursive https://github.com/brujack/${DOTFILES}.git ${PERSONAL_GITREPOS}/${DOTFILES}
  else
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    git pull
  fi

  printf "Linking %s to their home\\n" "${DOTFILES}"

  if [[ -n ${MACOS} ]]; then
    rm -f ${HOME}/.gitconfig
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_mac ${HOME}/.gitconfig
    if [[ -d ${HOME}/git-repos/gitlab ]]; then
      rm -f ${HOME}/git-repos/gitlab/.gitconfig
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_mac_gitlab ${HOME}/git-repos/gitlab/.gitconfig
    fi
    if [[ -L ${HOME}/git-repos/gitlab/.gitconfig ]]; then
      printf "gitlab/.gitconfig is linked\\n"
    fi
  fi
  if [[ -n ${LINUX} ]]; then
    rm -f ${HOME}/.gitconfig
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_linux ${HOME}/.gitconfig
    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
      if [[ -d ${HOME}/git-repos/gitlab ]]; then
        rm -f ${HOME}/git-repos/gitlab/.gitconfig
        ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_linux_gitlab ${HOME}/git-repos/gitlab/.gitconfig
      fi
      if [[ -L ${HOME}/git-repos/gitlab/.gitconfig ]]; then
        printf "gitlab/.gitconfig is linked Linux\\n"
      fi
    fi
  fi

  rm -f ${HOME}/.vimrc
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.vimrc ${HOME}/.vimrc
  if [[ -L ${HOME}/.vimrc ]]; then
    printf ".vimrc is linked\\n"
  fi

  rm -f ${HOME}/.p10k.zsh
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.p10k.zsh ${HOME}/.p10k.zsh
  if [[ -L ${HOME}/.p10k.zsh ]]; then
    printf ".p10k.zsh is linked\\n"
  fi

  rm -f ${HOME}/.tmux.conf
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.tmux.conf ${HOME}/.tmux.conf
  if [[ -L ${HOME}/.tmux.conf ]]; then
    printf ".tmux.conf is linked\\n"
  fi

  if [[ -d ${HOME}/scripts ]]; then
    rm -rf ${HOME}/scripts
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/scripts ${HOME}/scripts
  elif [[ ! -L ${HOME}/scripts ]]; then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/scripts ${HOME}/scripts
  fi
  if [[ -L ${HOME}/scripts ]]; then
    printf "scripts is linked\\n"
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
    printf "Creating %s/.config\\n" "${HOME}"
    mkdir -p ${HOME}/.config
  fi
  if [[ -d ${HOME}/.config ]]; then
    printf "Created %s/.config\\n" "${HOME}"
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
    printf "Creating %s/.tf_creds\\n" "${HOME}"
    mkdir -p ${HOME}/.tf_creds
    if [[ -d ${HOME}/.tf_creds ]]; then
      chmod 700 ${HOME}/.tf_creds
    fi
    if [[ -d ${HOME}/.tf_creds ]]; then
      printf "Created %s/.tf_creds\\n" "${HOME}"
    fi
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
    printf "powershell profile and custom oh-my-posh theme\\n"
    mkdir -p ${HOME}/.config/powershell
    rm -f ${HOME}/.config/powershell/profile.ps1
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/profile.ps1 ${HOME}/.config/powershell/profile.ps1
    rm -f ${HOME}/.config/powershell/bruce.omp.json
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/bruce.omp.json ${HOME}/.config/powershell/bruce.omp.json
    if [[ -L ${HOME}/.config/powershell/profile.ps1 ]]; then
      printf "powershell profile is linked\\n"
    fi
    if [[ -L ${HOME}/.config/powershell/bruce.omp.json ]]; then
      printf "bruce.omp.json is linked\\n"
    fi
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
    printf "starship profile\\n"
    rm -f ${HOME}/.config/starship.toml
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/starship.toml ${HOME}/.config/starship.toml
    if [[ -L ${HOME}/.config/starship.toml ]]; then
      printf "starship.toml is linked\\n"
    fi
  fi

  printf "Installing Oh My ZSH...\\n"
  if [[ ! -d ${HOME}/.oh-my-zsh ]]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    if [[ -d ${HOME}/.oh-my-zsh ]]; then
      printf "Installed Oh My ZSH\\n"
    fi
  fi

  printf "Installing p10k\\n"
  if [[ ! -d ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k ]]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k
    if [[ -d ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k ]]; then
      printf "Installed p10k\\n"
    fi
  fi

  printf "linking .zshrc\\n"
  rm -f ${HOME}/.zshrc
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.zshrc ${HOME}/.zshrc
  if [[ -L ${HOME}/.zshrc ]]; then
    printf ".zshrc is linked\\n"
  fi

  printf "linking .zshrc.d\\n"
  rm -f ${HOME}/.config/.zshrc.d
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.config/.zshrc.d ${HOME}/.config/.zshrc.d
  if [[ -L ${HOME}/.config/.zshrc.d ]]; then
    printf ".zshrc.d is linked\\n"
  fi

  printf "linking .zprofile\\n"
  rm -f ${HOME}/.zprofile
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.zprofile ${HOME}/.zprofile
  if [[ -L ${HOME}/.zprofile ]]; then
    printf ".zprofile is linked\\n"
  fi

  printf "Linking custom bruce.zsh-theme\\n"
  rm -f ${HOME}/.oh-my-zsh/custom/themes/bruce.zsh-theme
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/bruce.zsh-theme ${HOME}/.oh-my-zsh/custom/themes/bruce.zsh-theme
  if [[ -L ${HOME}/.oh-my-zsh/custom/themes/bruce.zsh-theme ]]; then
    printf "bruce.zsh-theme is linked\\n"
  fi

  printf "Creating %s/.tmux\\n" "${HOME}"
  mkdir -p ${HOME}/.tmux
  if [[ -d ${HOME}/.tmux ]]; then
    printf "Created %s/.tmux\\n" "${HOME}"
  fi

  if [[ ! -d ${HOME}/.tmux/plugins/tpm ]]; then
    printf "Installing TPM\\n"
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
    if [[ -d ${HOME}/.tmux/plugins/tpm ]]; then
      printf "Installed TPM\\n"
    fi
  fi

  printf "Creating %s/.warp\\n" "${HOME}"
  mkdir -p ${HOME}/.warp
  if [[ -d ${HOME}/.warp ]]; then
    chmod 700 ${HOME}/.warp
    if [[ -d ${HOME}/.warp ]]; then
      printf "Created %s/.warp\\n" "${HOME}"
    fi
  fi
  printf "Linking %s/.warp/themes\\n" "${HOME}"
  rm -f ${HOME}/.warp/themes
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.warp/themes ${HOME}/.warp/themes
  if [[ -L ${HOME}/.warp/themes ]]; then
    printf ".warp/themes is linked\\n"
  fi

  printf "Linking %s/.warp/launch_configurations\\n" "${HOME}"
  rm -f ${HOME}/.warp/launch_configurations
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.warp/launch_configurations ${HOME}/.warp/launch_configurations
  if [[ -L ${HOME}/.warp/launch_configurations ]]; then
    printf ".warp/launch_configurations is linked\\n"
  fi

  printf "Creating %s/.ssh\\n" "${HOME}"
  mkdir -p ${HOME}/.ssh
  if [[ -d ${HOME}/.ssh ]]; then
    chmod 700 ${HOME}/.ssh
    if [[ -d ${HOME}/.ssh ]]; then
      printf "Created %s/.ssh\\n" "${HOME}"
    fi
  fi

  printf "Linking %s/.ssh/config\\n" "${HOME}"
  rm -f ${HOME}/.ssh/config
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.ssh/config ${HOME}/.ssh/config
  if [[ -L ${HOME}/.ssh/config ]]; then
    printf ".ssh/config is linked\\n"
  fi

  printf "Linking %s/.ssh/teleport.cfg\\n" "${HOME}"
  rm -f ${HOME}/.ssh/teleport.cfg
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.ssh/teleport.cfg ${HOME}/.ssh/teleport.cfg
  if [[ -L ${HOME}/.ssh/teleport.cfg ]]; then
    printf ".ssh/teleport.cfg is linked\\n"
  fi

  printf "Creating %s/.tsh\\n" "${HOME}"
  mkdir -p ${HOME}/.tsh
  if [[ -d ${HOME}/.tsh ]]; then
    chmod 700 ${HOME}/.tsh
    if [[ -d ${HOME}/.tsh ]]; then
      printf "Created %s/.tsh\\n" "${HOME}"
    fi
  fi

  printf "Setting ZSH as shell...\\n"

  # Set the ZSH path based on the value of REDHAT
  ZSH_PATH=${REDHAT:+"/usr/local/bin/zsh"}
  ZSH_PATH=${ZSH_PATH:-"/bin/zsh"}

  if [[ ${SHELL} != "${ZSH_PATH}" ]]; then
    if which "${ZSH_PATH}" >/dev/null 2>&1; then
      chsh -s "${ZSH_PATH}"
      printf "Changed default shell to %s\\n" "${ZSH_PATH}"
    else
      printf "Error: %s does not exist\\n" "${ZSH_PATH}"
    fi
  fi

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
fi

# full setup and installation of all packages for a development environment
if [[ -n ${SETUP} ]] || [[ -n ${DEVELOPER} ]]; then
  printf "Creating %s/.aws\\n" "${HOME}"
  mkdir -p ${HOME}/.aws
  if [[ -d ${HOME}/.aws ]]; then
    chmod 700 ${HOME}/.aws
    printf "Created %s/.aws\\n" "${HOME}"
  fi

  printf "Creating %s/.gcloud_creds\\n" "${HOME}"
  mkdir -p ${HOME}/.gcloud_creds
  if [[ -d ${HOME}/.gcloud_creds ]]; then
    chmod 700 ${HOME}/.gcloud_creds
    printf "Created %s/.gcloud_creds\\n" "${HOME}"
  fi

  printf "Creating %s/.azure_creds\\n" "${HOME}"
  mkdir -p ${HOME}/.azure_creds
  if [[ -d ${HOME}/.azure_creds ]]; then
    chmod 700 ${HOME}/.azure_creds
    printf "Created %s/.azure_creds\\n" "${HOME}"
  fi

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
      brew tap homebrew/bundle
      brew tap homebrew/cask
      cd ${BREWFILE_LOC} && brew bundle
      brew install --cask chef/chef/inspec
      brew tap cloudflare/cloudflare
      brew install --cask cloudflare/cloudflare/cf-terraforming
      brew install --cask dotnet
      brew install go-task/tap/go-task
      brew install --cask miro
      brew tap snyk/tap
      brew install snyk
      brew tap teamookla/speedtest
      brew install speedtest
      brew install redpanda-data/tap/redpanda
      if [[ -n ${STUDIO} ]] || [[ -n ${LAPTOP} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]] || [[ -n ${RATNA} ]]; then
        brew install datawire/blackbird/telepresence-arm64
        brew install cloudflared
      fi

      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit

      # the below casks and mas are not in a brewfile since they will "fail" if already installed
      if [[ ! -d "/Applications/1Password.app" ]]; then
        brew install --cask 1password
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]]; then
        if [[ ! -d "/Applications/Adobe\ Creative\ Cloud" ]]; then
          brew install --cask adobe-creative-cloud
        fi
      fi
      if [[ ! -d "/Applications/Adobe\ Acrobat\ Reader\ DC.app" ]]; then
        brew install --cask adobe-acrobat-reader
      fi
      if [[ ! -d "/Applications/Alfred\ 5.app" ]]; then
        brew install --cask alfred
      fi
      if [[ ! -d "/Applications/AppCleaner.app" ]]; then
        brew install --cask appcleaner
      fi
      if [[ ! -d "/Applications/Atom.app" ]]; then
        brew install --cask atom
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]]; then
        if [[ ! -d "/Applications/balenaEtcher.app" ]]; then
          brew install --cask balenaetcher
        fi
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]]; then
        if [[ ! -d "/Applications/BambuStudio.app" ]]; then
          brew install --cask bambu-studio
        fi
      fi
      if [[ ! -d "/Applications/Beyond\ Compare.app" ]]; then
        brew install --cask beyond-compare
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]]; then
        if [[ ! -d "/Applications/Carbon\ Copy\ Cloner.app" ]]; then
          brew install --cask carbon-copy-cloner
        fi
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]]; then
        if [[ ! -d "/Applications/ChatGPT.app" ]]; then
          brew install --cask chatgpt
        fi
      fi
      if [[ ! -d "/Applications/DaisyDisk.app" ]]; then
        brew install --cask daisydisk
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]]; then
        if [[ ! -d "/Applications/DBeaver.app" ]]; then
          brew install --cask dbeaver-community
        fi
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]]; then
        if [[ ! -d "/Applications/Discord.app" ]]; then
          brew install --cask discord
        fi
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]]; then
        if [[ ! -d "/Applications/Docker.app" ]]; then
          brew install --cask docker
        fi
      fi
      if [[ ! -d "/Applications/Dropbox.app" ]]; then
        brew install --cask dropbox
      fi
      if [[ ! -d "/Applications/ExpressVPN.app" ]]; then
        brew install --cask expressvpn
      fi
      if [[ ! -d "/Applications/Firefox.app" ]]; then
        brew install --cask firefox
      fi
      if [[ ! -d "/Applications/Flycut.app" ]]; then
        brew install --cask flycut
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]]; then
        if [[ ! -d "/Applications/Fork.app" ]]; then
          brew install --cask fork
        fi
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]]; then
        if [[ ! -d "/Applications/Funter.app" ]]; then
          brew install --cask funter
        fi
      fi
      if [[ ! -d "/Applications/Google\ Chrome.app" ]]; then
        brew install --cask google-chrome
      fi
      if [[ ! -d "/Applications/GitHub\ Desktop.app" ]]; then
        brew install --cask github
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]]; then
        if [[ ! -d "/Applications/Google\ Cloud\ SDK.app" ]]; then
          brew install --cask google-cloud-sdk
        fi
      fi
      if [[ ! -d "/Applications/iStat\ Menus.app" ]]; then
        brew install --cask istat-menus
      fi
      if [[ ! -d "/Applications/iTerm.app" ]]; then
        brew install --cask iterm2
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]]; then
        if [[ ! -d "/Applications/Lens.app" ]]; then
          brew install --cask lens
        fi
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]]; then
        if [[ ! -d "/Applications/logioptionsplus.app" ]]; then
          brew install --cask logi-options-plus
        fi
      fi
      if [[ ! -d "/Applications/MacDown.app" ]]; then
        brew install --cask macdown
      fi
      if [[ ! -d "/Applications/Malwarebytes.app" ]]; then
        brew install --cask malwarebytes
      fi
      if [[ -n ${RATNA} ]] || [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]]; then
        if [[ ! -d "/Applications/Microsoft\ Word.app" ]]; then
          brew install --cask microsoft-office
        fi
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]]; then
        if [[ ! -d "/Applications/MySQLWorkbench.app" ]]; then
          brew install --cask mysqlworkbench
        fi
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]]; then
        if [[ ! -d "/Applications/OBS.app" ]]; then
          brew install --cask obs
        fi
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]]; then
        if [[ ! -d "/usr/local/Caskroom/oracle-jdk" ]]; then
          brew install --cask oracle-jdk
        fi
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]]; then
        if [[ ! -d "/Applications/Postman.app" ]]; then
          brew install --cask postman
        fi
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]]; then
        if [[ ! -d "/usr/local/sessionmanagerplugin" ]]; then
          brew install --cask session-manager-plugin
        fi
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]]; then
        if [[ ! -d "/Applications/SourceTree.app" ]]; then
          brew install --cask sourcetree
        fi
      fi
      if [[ ! -d "/Applications/Spotify.app" ]]; then
        brew install --cask spotify
      fi
      if [[ ! -d "/Applications/PowerShell.app" ]]; then
        brew install --cask powershell
      fi
      if [[ ! -d "/Applications/Slack.app" ]]; then
        brew install --cask slack
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]]; then
        if [[ ! -d "/Applications/Steam.app" ]]; then
          brew install --cask steam
        fi
      fi
      if [[ ! -d "/Applications/TeamViewer.app" ]]; then
        brew install --cask teamviewer
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]]; then
        if [[ ! -d "/Applications/VirtualBox.app" ]]; then
          brew install --cask virtualbox
        fi
      fi
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]]; then
        if [[ ! -d "/Applications/Vagrant.app" ]]; then
          brew install --cask vagrant
        fi
      fi
      if [[ ! -d "/Applications/Visual\ Studio\ Code.app" ]]; then
        brew install --cask visual-studio-code
      fi
      if [[ ! -d "/Applications/VLC.app" ]]; then
        brew install --cask vlc
      fi
      if [[ ! -d "/Applications/Warp.app" ]]; then
        brew install --cask warp
      fi
      if [[ ! -d "/Applications/zoom.us.app" ]]; then
        brew install --cask zoom
      fi

      printf "Cleaning Homebrew up...\\n"
      brew cleanup
    fi

    printf "Updating app store apps via softwareupdate\\n"
    sudo -H softwareupdate --install --all --verbose

    printf "Installing common apps via mas\\n"
    if [[ ! -d "/Applications/Better\ Rename\ 9.app" ]]; then
      mas install 414209656
    fi
    if [[ ! -d "/Applications/Brother\ iPrint\&Scan.app" ]]; then
      mas install 1193539993
    fi
    if [[ ! -d "/Applications/Blackmagic\ Disk\ Speed\ Test.app" ]]; then
      mas install 425264550
    fi
    if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]]; then
      if [[ ! -d "/Applications/Evernote.app" ]]; then
        mas install 406056744
      fi
    fi
    if [[ ! -d "/Applications/Flycut.app" ]]; then
      mas install 442160987
    fi
    if [[ ! -d "/Applications/iNet\ Network\ Scanner.app" ]]; then
      mas install 403304796
    fi
    if [[ ! -d "/Applications/Mactracker.app" ]]; then
      mas install 430255202
    fi
    if [[ ! -d "/Applications/Magnet.app" ]]; then
      mas install 441258766
    fi
    if [[ ! -d "/Applications/Markoff.app" ]]; then
      mas install 1084713122
    fi
    if [[ ! -d "/Applications/Microsoft\ Remote\ Desktop.app" ]]; then
      mas install 715768417
    fi
    if [[ ! -d "/Applications/Remote\ Desktop.app" ]]; then
      mas install 409907375
    fi
    if [[ ! -d "/Applications/Simplenote.app" ]]; then
      mas install 692867256
    fi
    if [[ ! -d "/Applications/Slack.app" ]]; then
      mas install 803453959
    fi
    if [[ ! -d "/Applications/Speedtest.app" ]]; then
      mas install 1153157709
    fi
    if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]]; then
      if [[ ! -d "/Applications/SQLPro\ for\ Postgres.app" ]]; then
        mas install 1025345625
      fi
    fi
    if [[ ! -d "/Applications/Sync\ Folders\ Pro.app" ]]; then
      mas install 522706442
    fi
    if [[ ! -d "/Applications/The\ Unarchiver.app" ]]; then
      mas install 425424353
    fi
    if [[ ! -d "/Applications/Transmit.app" ]]; then
      mas install 403388562
    fi
    if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]]; then
      if [[ ! -d "/Applications/Valentina\ Studio.app" ]]; then
        mas install 604825918
      fi
    fi

    if [[ -n ${RATNA} ]] || [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]]; then
      printf "Installing extra apps via mas\\n"
      if [[ ! -d "/Applications/Keynote.app" ]]; then
        mas install 409183694
      fi
      if [[ ! -d "/Applications/iMovie.app" ]]; then
        mas install 408981434
      fi
      if [[ ! -d "/Applications/Magnet.app" ]]; then
        mas install 441258766
      fi
      if [[ ! -d "/Applications/Numbers.app" ]]; then
        mas install 409203825
      fi
      if [[ ! -d "/Applications/Pages.app" ]]; then
        mas install 409201541
      fi
      if [[ ! -d "/Applications/Pixelmator\ Pro.app" ]]; then
        mas install 1289583905
      fi
      if [[ ! -d "/Applications/Read CHM.app" ]]; then
        mas install 594432954
      fi
      if [[ ! -d "/Applications/Telegram.app" ]]; then
        mas install 747648890
      fi
      printf "Installing xcode-stuff\\n"
      if [[ ! -d "/Applications/Xcode.app" ]]; then
        mas install 497799835
      fi
    fi

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

    if [[ -n ${WORKSTATION} ]]; then
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
        wget -O ${HOME}/software_downloads/packages-microsoft-prod.deb http://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
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
        wget -O ${HOME}/software_downloads/packages-microsoft-prod.deb http://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
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
        wget -O ${HOME}/software_downloads/packages-microsoft-prod.deb http://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
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
        wget -O ${HOME}/software_downloads/packages-microsoft-prod.deb http://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
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
      *)
        printf "Error: Unsupported Go version %s\\n" "${GO_VER}"
        exit 1
        ;;
    esac
    INSTALLED_GO_VER=$(go version | awk '{print $3}' | sed 's/go//g')
    if [[ ${INSTALLED_GO_VER} == ${GO_VER} ]]; then
      printf "Go %s is installed\\n" "${GO_VER}"
    fi

    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
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

    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
      printf "Installing Virtualbox\\n"
      wget -q http://www.virtualbox.org/download/oracle_vbox_2016.asc -O- | sudo apt-key add -
      wget -q http://www.virtualbox.org/download/oracle_vbox.asc -O- | sudo apt-key add -
      sudo add-apt-repository "deb http://download.virtualbox.org/virtualbox/debian $(lsb_release -cs) contrib"
      sudo -H apt update
      sudo -H apt install ${VIRTUALBOX_VER} -y
      if [[ -x $(command -v vboxmanage) ]]; then
        printf "Virtualbox is installed\\n"
      fi
    fi

    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
      printf "Installing teleport\\n"
      wget -q https://deb.releases.teleport.dev/teleport-pubkey.asc -O- | sudo apt-key add -
      sudo add-apt-repository "deb https://deb.releases.teleport.dev/ stable main"
      sudo -H apt update
      sudo -H apt install teleport -y
      if [[ -x $(command -v tsh) ]]; then
        printf "Teleport is installed\\n"
      fi
    fi

    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
      printf "Installing cloudflared\\n"
      curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
      echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ jammy main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list
      sudo apt-get update
      sudo apt-get install cloudflare-warp -y
      if [[ -x $(command -v cloudflared) ]]; then
        printf "cloudflared is installed\\n"
      fi
    fi

    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
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

    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
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

    if [[ -n ${WORKSTATION} ]]; then
      if [[ ${FOCAL} ]]; then
        printf "Installing Albert Ubuntu Focal\\n"
        curl https://build.opensuse.org/projects/home:manuelschneid3r/public_key | sudo apt-key add -
        echo "deb http://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_$(lsb_release -rs)/ /" | sudo tee /etc/apt/sources.list.d/home:manuelschneid3r.list
        sudo wget -nv https://download.opensuse.org/repositories/home:manuelschneid3r/xUbuntu_$(lsb_release -rs)/Release.key -O "/etc/apt/trusted.gpg.d/home:manuelschneid3r.asc"
        sudo -H apt update
        sudo -H apt install albert -y
        if [[ -x $(command -v albert) ]]; then
          printf "Albert is installed Ubuntu Focal\\n"
        fi
      elif [[ ${JAMMY} ]]; then
        printf "Installing Albert Ubuntu Jammy\\n"
        curl https://build.opensuse.org/projects/home:manuelschneid3r/public_key | sudo apt-key add -
        echo "deb http://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_$(lsb_release -rs)/ /" | sudo tee /etc/apt/sources.list.d/home:manuelschneid3r.list
        sudo wget -nv https://download.opensuse.org/repositories/home:manuelschneid3r/xUbuntu_$(lsb_release -rs)/Release.key -O "/etc/apt/trusted.gpg.d/home:manuelschneid3r.asc"
        sudo -H apt update
        sudo -H apt install albert -y
        if [[ -x $(command -v albert) ]]; then
          printf "Albert is installed Ubuntu Jammy\\n"
        fi
      elif [[ ${NOBLE} ]]; then
        printf "Installing Albert Ubuntu Noble\\n"
        curl https://build.opensuse.org/projects/home:manuelschneid3r/public_key | sudo apt-key add -
        echo "deb http://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_$(lsb_release -rs)/ /" | sudo tee /etc/apt/sources.list.d/home:manuelschneid3r.list
        sudo wget -nv https://download.opensuse.org/repositories/home:manuelschneid3r/xUbuntu_$(lsb_release -rs)/Release.key -O "/etc/apt/trusted.gpg.d/home:manuelschneid3r.asc"
        sudo -H apt update
        sudo -H apt install albert -y
        if [[ -x $(command -v albert) ]]; then
          printf "Albert is installed Ubuntu Noble\\n"
        fi
      fi
    fi

    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
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
      echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
      curl http://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
    fi
    sudo apt update
    sudo -H apt install google-cloud-sdk -y
    sudo -H apt install google-cloud-sdk-app-engine-python -y
    sudo -H apt install google-cloud-sdk-app-engine-python-extras -y
    sudo -H apt install google-cloud-sdk-app-engine-go -y

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
      brew install argocd
      brew install bat
      brew install exa
      brew install git-lfs
      brew install fzf
      brew install gh
      brew install hadolint
      brew install k9s
      brew install lazydocker
      brew install linkerd
      brew install mongosh
      brew install mongodb-atlas
      brew install neovim
      brew install ripgrep
      brew install rustup
      brew install starship
      brew install tgenv
      brew install zoxide
      brew install go-task/tap/go-task
      brew install redpanda-data/tap/redpanda
      brew tap snyk/tap
      brew install snyk
    fi

    if [[ -n ${WORKSTATION} ]]; then
      printf "Installing microsoft edge\\n"
      sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/edge stable main" > /etc/apt/sources.list.d/microsoft-edge.list'
      sudo -H apt update
      sudo -H apt install microsoft-edge-stable -y
    fi

    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
      printf "Installing .net7 sdk\\n"
      sudo -H apt install dotnet-sdk-8.0 -y
    fi

    python3 -m pip install glances
    if [[ -x $(command -v glances) ]]; then
      printf "glances is installed\\n"
    fi
    if [[ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]]; then
      sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VER}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VER}/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    fi
    sudo -H apt update
    sudo -H apt install kubectl -y

    if [[ -n ${WORKSTATION} ]]; then
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
    if [[ -n ${CRUNCHER} ]]; then
      curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
      echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
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
    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
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
    if [[ ! -d ${HOME}/software_downloads/shellcheck-v${SHELLCHEK_VER} ]]; then
      wget -O ${HOME}/software_downloads/shellcheck-v${SHELLCHEK_VER}.linux.x86_64.tar.xz https://shellcheck.storage.googleapis.com/shellcheck-v${SHELLCHEK_VER}.linux.x86_64.tar.xz
      xz --decompress ${HOME}/software_downloads/shellcheck-v${SHELLCHEK_VER}.linux.x86_64.tar.xz
      cd ${HOME}/software_downloads || exit
      tar -xf ${HOME}/software_downloads/shellcheck-v${SHELLCHEK_VER}.linux.x86_64.tar
      sudo cp -a ${HOME}/software_downloads/shellcheck-v${SHELLCHEK_VER}/shellcheck /usr/local/bin/
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
    sudo -H python3 -m pip install glances
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
      sudo echo "${RHEL_KUBECTL_REPO}" > /tmp/kubernetes.repo
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

  if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]] || [[ -n ${RATNA} ]]; then
    mkdir -p ${HOME}/software_downloads/awscli
    if [[ -n ${MACOS} ]]; then
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
  fi
  if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
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
fi

if [[ -n ${DEVELOPER} ]] || [[ -n ${ANSIBLE} ]]; then
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
    if [[ ! -d ${HOME}/software_downloads/chruby-${CHRUBY_VER} ]]; then
      wget -O ${HOME}/software_downloads/chruby-${CHRUBY_VER}.tar.gz https://github.com/postmodern/chruby/archive/v${CHRUBY_VER}.tar.gz
      tar -xzvf ${HOME}/software_downloads/chruby-${CHRUBY_VER}.tar.gz -C ${HOME}/software_downloads/
      cd ${HOME}/software_downloads/chruby-${CHRUBY_VER}/ || exit
      sudo make install
    fi
  fi

  printf "install ruby %s\\n" "${RUBY_VER}"
  if [[ ! -d ${HOME}/.rubies/ruby-${RUBY_VER}/bin ]]; then
    if [[ -n ${MACOS} ]]; then
      ruby-install ${RUBY_VER} -- --with-openssl-dir=$(brew --prefix openssl@3)
    fi
    if [[ -n ${LINUX} ]]; then
      ruby-install ${RUBY_VER}
    fi
    INSTALLED_RUBY_VERSION=$(ruby --version) | awk '{print $2}'
    if [[ ${INSTALLED_RUBY_VERSION} == ${RUBY_VER} ]]; then
      printf "ruby %s is installed\\n" "${RUBY_VER}"
    fi
  fi

  if [[ -n ${LINUX} ]]; then
    printf "installing github cli on linux\\n"
    if [[ -n ${UBUNTU} ]]; then
      sudo -H apt-key adv --keyserver keyserver.ubuntu.com --recv-key C99B11DEB97541F0
      sudo -H apt-add-repository https://cli.github.com/packages
      sudo -H apt update
      sudo -H apt install gh
      if [[ -x $(command -v gh) ]]; then
        printf "gh is installed Ubuntu\\n"
      fi
    elif [[ -n ${REDHAT} ]] || [[ -n ${CENTOS} ]] || [[ -n ${FEDORA} ]]; then
      sudo -H dnf config-manager --add-repo http://cli.github.com/packages/rpm/gh-cli.repo
      sudo dnf install gh
      if [[ -x $(command -v gh) ]]; then
        printf "gh is installed RHEL\\n"
      fi
    fi
  fi

  printf "Setup kitchen\\n"
  source ${CHRUBY_LOC}/chruby/chruby.sh
  source ${CHRUBY_LOC}/chruby/auto.sh
  chruby ruby-${RUBY_VER}
  gem install test-kitchen
  gem install kitchen-ansible
  gem install kitchen-docker
  gem install kitchen-inspec
  gem install kitchen-terraform
  gem install kitchen-verifier-serverspec
  gem install bundle
  gem install bundler

  printf "Install terraspace\\n"
  gem install terraspace
  if [[ -x $(command -v terraspace) ]]; then
    printf "terraspace is installed\\n"
  fi

  printf "ANSIBLE setup\\n"
  if [[ -n ${LINUX} ]]; then
    pyenv update
  fi
  if ! [[ -d ${HOME}/.pyenv/versions/${PYTHON_VER} ]]; then
    pyenv install ${PYTHON_VER}
  fi

  if ! [[ $(readlink "${HOME}/.pyenv/versions/ansible") == "${HOME}/.pyenv/versions/${PYTHON_VER}/envs/ansible" ]]; then
    if [[ -n ${STUDIO} ]] || [[ -n ${LAPTOP} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]] || [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]] || [[ -n ${RATNA} ]]; then
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
      python3 -m pip install ansible ansible-lint certbot certbot-dns-cloudflare boto3 docker jmespath netaddr pylint psutil bpytop HttpPy j2cli wheel shell-gpt
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

fi

# update is run more often to keep the device up to date with patches
if [[ -n ${UPDATE} ]]; then
  if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
    brew_update
    printf "Updating app store apps softwareupdate\\n"
    sudo -H softwareupdate --install --all --verbose
  fi
  if [[ -n ${UBUNTU} ]]; then
    sudo -H apt update
    if [[ ${FOCAL} ]]; then
      sudo -H apt autoremove -y
    elif [[ ${JAMMY} ]]; then
      check_and_install_nala
      sudo -H nala full-upgrade -y
      sudo -H nala autoremove -y
    elif [[ ${NOBLE} ]]; then
      check_and_install_nala
      sudo -H nala full-upgrade -y
      sudo -H nala autoremove -y
    fi
    sudo snap refresh
    printf "Updated snap packages\\n"
  fi
  if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then
    sudo -H dnf update -y
    printf "Updated dnf packages\\n"
  fi
  if [[ -n ${CENTOS} ]]; then
    sudo -H yum update -y
    printf "Updated yum packages\\n"
  fi
  if [[ -n ${MACOS} ]]; then
    printf "Updating mas packages\\n"
    mas upgrade
  fi
  printf "Updating pip3 packages\\n"
  if [[ -n ${STUDIO} ]] || [[ -n ${LAPTOP} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]] || [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]] || [[ -n ${RATNA} ]]; then
    python3 -m pip install --upgrade pip
    python3 -m pip list --outdated --format=columns | awk '{print $1;}' | awk 'NR>2' | xargs -n1 python3 -m pip install -U
    python3 -m pip check
    printf "Updated pip packages\\n"
  fi
  if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]] || [[ -n ${RATNA} ]]; then
    if [[ -n ${MACOS} ]]; then
      printf "Updating MACOS awscli\\n"
      cd ${HOME}/software_downloads/awscli || exit
      curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
      sudo -H installer -pkg AWSCLIV2.pkg -target /
      rm AWSCLIV2.pkg
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    fi
  fi
  if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
    printf "Updating Linux awscli\\n"
    cd ${HOME}/software_downloads/awscli || exit
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -u -o awscliv2.zip
    sudo -H ${HOME}/software_downloads/awscli/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin --update
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
  fi
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
  printf "updating ruby gems\\n"
  gem update
fi

/usr/bin/env zsh ${HOME}/.zshrc

exit 0
