#!/usr/bin/env bash

# software versions to install
RUBY_INSTALL_VER="0.8.3"
CHRUBY_VER="0.3.9"
RUBY_VER="3.2.0"
PYTHON_VER="3.10.9"
CONSUL_VER="1.12.3"
VAULT_VER="1.11.2"
NOMAD_VER="1.3.2"
PACKER_VER="1.8.3"
VAGRANT_VER="2.2.19"
HASHICORP_URL="https://releases.hashicorp.com"
WORK_TERRAFORM_VER="1.0.2"
TERRAFORM_VER="1.1.7"
GIT_VER="2.38.1"
GIT_URL="https://mirrors.edge.kernel.org/pub/software/scm/git"
ZSH_VER="5.9"
GO_VER="1.19"
DOCKER_COMPOSE_VER="v2.11.2"
DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VER}/docker-compose-$(uname -s)-$(uname -m)"
SHELLCHECK_VER="0.7.0"
Z_GIT="https://github.com/rupa/z.git"
ZABBIX_VER="4.4-1+"
KIND_VER="0.14.0"
KIND_URL="https://kind.sigs.k8s.io/dl/v${KIND_VER}/kind-linux-amd64"
YQ_VER="4.27.2"
YQ_URL="https://github.com/mikefarah/yq/releases/download/v${YQ_VER}/yq_linux_amd64"
TFLINT_VER="0.39.1"
TFLINT_URL="https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VER}/tflint_linux_amd64.zip"
TFSEC_VER="1.27.1"
TFSEC_URL="https://github.com/liamg/tfsec/releases/download/v${TFSEC_VER}/tfsec-linux-amd64"
CF_TERRAFORMING_VER="0.6.3"
CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v${CF_TERRAFORMING_VER}/cf-terraforming_${CF_TERRAFORMING_VER}_linux_amd64.tar.gz"
TELEPRESENCE_URL="https://app.getambassador.io/download/tel2/linux/amd64/latest/telepresence"
RHEL_KUBECTL_REPO="[kubernetes]
name=Kubernetes
baseurl=http://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=http://packages.cloud.google.com/yum/doc/yum-key.gpg http://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
"

# locations of directories
GITREPOS="${HOME}/git-repos"
PERSONAL_GITREPOS="${GITREPOS}/personal"
DOTFILES="dotfiles"
BREWFILE_LOC="${HOME}/brew"
HOSTNAME=$(hostname -s)
WSL_HOME="/mnt/c/Users/${USER}"

# setup some functions
quiet_which() {
  which "$1" &>/dev/null
}

rhel_installed() {
  if yum list installed "$@" >/dev/null 2>&1; then
    true
  else
    false
  fi
}

install_rosetta() {
  # Determine OS version
  # Save current IFS state

  OLDIFS=$IFS

  IFS='.' read osvers_major osvers_minor osvers_dot_version <<< "$(/usr/bin/sw_vers -productVersion)"

  # restore IFS to previous state

  IFS=$OLDIFS

  # Check to see if the Mac is reporting itself as running macOS 11

  if [[ ${osvers_major} -ge 11 ]]; then

    # Check to see if the Mac needs Rosetta installed by testing the processor

    processor=$(/usr/sbin/sysctl -n machdep.cpu.brand_string | grep -o "Intel")

    if [[ -n "$processor" ]]; then
      echo "$processor processor installed. No need to install Rosetta."
    else

      # Check for Rosetta "oahd" process. If not found,
      # perform a non-interactive install of Rosetta.

      if /usr/bin/pgrep oahd >/dev/null 2>&1; then
          echo "Rosetta is already installed and running. Nothing to do."
      else
          /usr/sbin/softwareupdate --install-rosetta --agree-to-license

          if [[ $? -eq 0 ]]; then
            echo "Rosetta has been successfully installed."
          else
            echo "Rosetta installation failed!"
            exitcode=1
          fi
      fi
    fi
    else
      echo "Mac is running macOS $osvers_major.$osvers_minor.$osvers_dot_version."
      echo "No need to install Rosetta on this version of macOS."
  fi
}

install_homebrew() {
  echo "Installing homebrew..."
  if [[ ${MACOS} ]]; then
    xcode-select --install
    # Accept Xcode license
    sudo xcodebuild -license accept
    sudo xcodebuild -runFirstLaunch
  fi
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

brew_update() {
  echo "Updating homebrew..."
  brew update
  brew upgrade
  brew upgrade --cask --greedy
  brew cleanup
}

usage() { echo "$0 usage:" && grep " .)\ #" $0; exit 0; }
[[ $# -eq 0 ]] && usage

## get command line options
# setup_user: just sets up a basic user environment for the current user
# setup: runs a full machine and developer setup
# developer: runs a developer setup with packages and python virtual environment for running ansible
# ansible: just runs the ansible setup using a python virtual environment. Typically used after a python update. To run, "pyenv virtualenv-delete -f ansible && ./setup_env.sh -t ansible"
# update: does a system update of packages including brew packages
while getopts ":ht:w" arg; do
  case ${arg} in
    t) # Specify t of either 'setup_user', 'setup', 'developer' 'ansible' or 'update'.
      [[ ${OPTARG} = "setup_user" ]] && export SETUP_USER=1
      [[ ${OPTARG} = "setup" ]] && export SETUP=1
      [[ ${OPTARG} = "developer" ]] && export DEVELOPER=1
      [[ ${OPTARG} = "ansible" ]] && export ANSIBLE=1
      [[ ${OPTARG} = "update" ]] && export UPDATE=1
      ;;
    w) # Optional -- Specify w for a redhat computer, sets up terraform 0.11 instead of default 0.12
      export WORK=1
      ;;
    h | *) # This script is used to setup a development env on macos/linux (ubuntu, redhat, fedora, centos, elementary os)
      usage
      exit 0
      ;;
  esac
done

# choose which env we are running on
[[ $(uname -s) = "Darwin" ]] && export MACOS=1
[[ $(uname -s) = "Linux" ]] && export LINUX=1

if [[ ${LINUX} ]]; then
  LINUX_TYPE=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
  [[ ${LINUX_TYPE} = "Ubuntu" ]] && export UBUNTU=1
  [[ ${LINUX_TYPE} = "CentOS Linux" ]] && export CENTOS=1
  [[ ${LINUX_TYPE} = "Red Hat Enterprise Linux Server" ]] && export REDHAT=1
  [[ ${LINUX_TYPE} = "Fedora" ]] && export FEDORA=1
  [[ ${LINUX_TYPE} = "elementary OS" ]] && export UBUNTU=1 && export ELEMENTARY=1
fi

if [[ ${UBUNTU} ]]; then
  UBUNTU_VERSION=$(lsb_release -rs)
  [[ ${UBUNTU_VERSION} = "18.04" ]] && export BIONIC=1
  [[ ${UBUNTU_VERSION} = "20.04" ]] && export FOCAL=1
  [[ ${UBUNTU_VERSION} = "22.04" ]] && export JAMMY=1
  [[ ${UBUNTU_VERSION} = "6" ]] && export FOCAL=1 # elementary os
fi

[[ $(uname -r) =~ microsoft ]] && export WINDOWS=1
[[ $(hostname -s) = "laptop" ]] && export LAPTOP=1
[[ $(hostname -s) = "studio" ]] && export STUDIO=1
[[ $(hostname -s) = "fg-bjackson" ]] && export BRUCEWORK=1
[[ $(hostname -s) = "workstation" ]] && export WORKSTATION=1
[[ $(hostname -s) = "cruncher" ]] && export CRUNCHER=1
[[ $(hostname -s) = "virtualmachine1c4f85d6" ]] && export WORKSTATION=1

# setup variables based off of environment
if [[ ${MACOS} ]]; then
  if [[ ${RATNA} ]]; then
    CHRUBY_LOC="/usr/local/opt/chruby/share"
  elif [[ ${LAPTOP} ]] || [[ ${STUDIO} ]] || [[ ${BRUCEWORK} ]]; then
    CHRUBY_LOC="/opt/homebrew/opt/chruby/share"
  fi
elif [[ ${LINUX} ]]; then
  CHRUBY_LOC="/usr/local/share"
fi

# Setup is run rarely as it should be run when setting up a new device or when doing a controlled change after changing items in setup
# The following code is used to setup the base system with some base packages and the basic layout of the users home directory
if [[ ${SETUP} || ${SETUP_USER} ]]; then
  # need to make sure that some base packages are installed
  if [[ ${REDHAT} || ${FEDORA} ]]; then
    if ! [ -x "$(command -v dnf)" ]; then
      echo "Installing dnf"
      sudo -H yum update -y
      sudo -H yum install dnf -y
    fi
  fi

  if [[ ${MACOS} ]]; then
    echo "Installing Rosetta if necessary"
    install_rosetta
  fi

  if ! [[ -d ${HOME}/software_downloads ]]; then
    mkdir ${HOME}/software_downloads
  fi

  echo "Installing git"
  if [[ ${MACOS} ]]; then
    if ! [ -x "$(command -v brew)" ]; then
      install_homebrew
    elif [ -x "$(command -v brew)" ]; then
      brew install git
    fi
  fi

  if [[ ${UBUNTU} ]]; then
    sudo -H add-apt-repository ppa:git-core/ppa -y
    sudo -H apt update
    sudo -H apt dist-upgrade -y
    sudo -H apt install git -y
  fi
  if [[ ${FEDORA} ]]; then
    sudo -H dnf update -y
    sudo -H dnf install git -y
  fi
  if [[ ${CENTOS} ]]; then
    sudo -H yum update -y
    sudo -H yum install git -y
  fi
  if [[ ${REDHAT} ]]; then
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
      echo "Installing Redhat git"
      wget -O ${HOME}/software_downloads/git-${GIT_VER}.tar.gz ${GIT_URL}/git-${GIT_VER}.tar.gz
      tar -zxvf ${HOME}/software_downloads/git-${GIT_VER}.tar.gz -C ${HOME}/software_downloads
      cd ${HOME}/software_downloads/git-${GIT_VER} || exit
      make configure
      ./configure --prefix=/usr
      make -j $(nproc) all doc info
      sudo -H make install install-doc install-info
    fi
  fi

  echo "Installing zsh"
  if [[ ${MACOS} ]]; then
    if ! [ -x "$(command -v brew)" ]; then
      install_homebrew
    elif [ -x "$(command -v brew)" ]; then
      brew install zsh
    fi
  fi
  if [[ ${UBUNTU} ]]; then
    sudo -H apt update
    sudo -H apt install zsh -y
    sudo -H apt install zsh-doc -y
  fi
  if [[ ${FEDORA} ]]; then
    sudo -H dnf update -y
    sudo -H dnf install zsh -y
  fi
  if [[ ${CENTOS} ]]; then
    sudo -H yum update -y
    sudo -H yum install zsh -y
  fi
  # for REDHAT need to download/build/install a much newer version of zsh
  if [[ ${REDHAT} ]]; then
    if rhel_installed zsh; then
      sudo -H yum remove zsh -y
    fi
    sudo -H yum update
    sudo -H yum install gcc -y
    sudo -H yum install make -y
    sudo -H yum install ncurses-devel -y
    if [[ ! -f ${HOME}/software_downloads/zsh-${ZSH_VER}.tar.xz ]]; then
      echo "Installing Redhat zsh"
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
  fi

  echo "Creating home bin"
  if [[ ! -d ${HOME}/bin ]]; then
    mkdir ${HOME}/bin
  fi

  echo "Creating ${PERSONAL_GITREPOS}"
  if [[ ! -d ${PERSONAL_GITREPOS} ]]; then
    mkdir ${PERSONAL_GITREPOS}
  fi

  echo "Copying ${DOTFILES} from Github"
  if [[ ! -d ${PERSONAL_GITREPOS}/${DOTFILES} ]]; then
    cd ${HOME} || return
    git clone --recursive git@github.com:brujack/${DOTFILES}.git ${PERSONAL_GITREPOS}/${DOTFILES}
    # for regular https github used on machines that will not push changes
    # git clone --recursive https://github.com/brujack/${DOTFILES}.git ${PERSONAL_GITREPOS}/${DOTFILES}
  else
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    git pull
  fi

  echo "Linking ${DOTFILES} to their home"

  if [[ ${MACOS} ]]; then
    if [[ -f ${HOME}/.gitconfig ]]; then
      rm ${HOME}/.gitconfig
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_mac ${HOME}/.gitconfig
    elif [[ ! -L ${HOME}/.gitconfig ]]; then
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_mac ${HOME}/.gitconfig
    fi
    if [[ -d ${HOME}/git-repos/fortis ]]; then
      if [[ ! -L ${HOME}/git-repos/fortis/.gitconfig ]]; then
        ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_mac_fortis ${HOME}/git-repos/fortis/.gitconfig
      fi
    fi
    if [[ -d ${HOME}/git-repos/gitlab ]]; then
      if [[ ! -L ${HOME}/git-repos/gitlab/.gitconfig ]]; then
        ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_mac_gitlab ${HOME}/git-repos/gitlab/.gitconfig
      fi
    fi
  fi
  if [[ ${LINUX} ]]; then
    if [[ -f ${HOME}/.gitconfig ]]; then
      rm ${HOME}/.gitconfig
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_linux ${HOME}/.gitconfig
    elif [[ ! -L ${HOME}/.gitconfig ]]; then
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_linux ${HOME}/.gitconfig
    fi
    if [[ ${WORKSTATION} ]] || [[ ${CRUNCHER} ]]; then
      if [[ -d ${HOME}/git-repos/fortis ]]; then
        if [[ ! -L ${HOME}/git-repos/fortis/.gitconfig ]]; then
          ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_linux_fortis ${HOME}/git-repos/fortis/.gitconfig
        fi
      fi
      if [[ -d ${HOME}/git-repos/gitlab ]]; then
        if [[ ! -L ${HOME}/git-repos/gitlab/.gitconfig ]]; then
          ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_linux_gitlab ${HOME}/git-repos/gitlab/.gitconfig
        fi
      fi
    fi
  fi

  if [[ -f ${HOME}/.vimrc ]]; then
    rm ${HOME}/.vimrc
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.vimrc ${HOME}/.vimrc
  elif [[ ! -L ${HOME}/.vimrc ]]; then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.vimrc ${HOME}/.vimrc
  fi

  if [[ -f ${HOME}/.p10k.zsh ]]; then
    rm ${HOME}/.p10k.zsh
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.p10k.zsh ${HOME}/.p10k.zsh
  elif [[ ! -L ${HOME}/.p10k.zsh ]]; then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.p10k.zsh ${HOME}/.p10k.zsh
  fi

  if [[ -f ${HOME}/.tmux.conf ]]; then
    rm ${HOME}/.tmux.conf
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.tmux.conf ${HOME}/.tmux.conf
  elif [[ ! -L ${HOME}/.tmux.conf ]]; then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.tmux.conf ${HOME}/.tmux.conf
  fi

  if [[ -d ${HOME}/scripts ]]; then
    rm -rf ${HOME}/scripts
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/scripts ${HOME}/scripts
  elif [[ ! -L ${HOME}/scripts ]]; then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/scripts ${HOME}/scripts
  fi

  if [[ ${MACOS} || ${LINUX} ]]; then
    if [[ ! -d ${HOME}/.config ]]; then
      mkdir -p ${HOME}/.config
    fi
  fi

  if [[ ${MACOS} || ${LINUX} ]]; then
    if [[ ! -d ${HOME}/.tf_creds ]]; then
      mkdir -p ${HOME}/.tf_creds
    fi
    if [[ -d ${HOME}/.tf_creds ]]; then
      chmod 700 ${HOME}/.tf_creds
    fi
  fi

  if [[ ${MACOS} || ${LINUX} ]]; then
    echo "powershell profile and custom oh-my-posh theme"
    if [[ ! -d ${HOME}/.config/powershell ]]; then
      mkdir -p ${HOME}/.config/powershell
    fi
    if [[ -f ${HOME}/.config/powershell/profile.ps1 ]]; then
      rm ${HOME}/.config/powershell/profile.ps1
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/profile.ps1 ${HOME}/.config/powershell/profile.ps1
    elif [[ ! -L ${HOME}/.config/powershell/profile.ps1 ]]; then
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/profile.ps1 ${HOME}/.config/powershell/profile.ps1
    fi
    if [[ -f ${HOME}/.config/powershell/bruce.omp.json ]]; then
      rm ${HOME}/.config/powershell/bruce.omp.json
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/bruce.omp.json ${HOME}/.config/powershell/bruce.omp.json
    elif [[ ! -L ${HOME}/.config/powershell/bruce.omp.json ]]; then
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/bruce.omp.json ${HOME}/.config/powershell/bruce.omp.json
    fi
  fi

  if [[ ${MACOS} || ${LINUX} ]]; then
    echo "starship profile"
    if [[ -f ${HOME}/.config/starship.toml ]]; then
      rm ${HOME}/.config/starship.toml
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/starship.toml ${HOME}/.config/starship.toml
    elif [[ ! -L ${HOME}/.config/starship.toml ]]; then
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/starship.toml ${HOME}/.config/starship.toml
    fi
  fi

  echo "Installing Oh My ZSH..."
  if [[ ! -d ${HOME}/.oh-my-zsh ]]; then
    sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
  fi

  echo "Installing p10k"
  if [[ ! -d ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k ]]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k
  fi

  if [[ -f ${HOME}/.zshrc ]]; then
    rm ${HOME}/.zshrc
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.zshrc ${HOME}/.zshrc
  elif [[ ! -L ${HOME}/.zshrc ]]; then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.zshrc ${HOME}/.zshrc
  fi

  if [[ ! -L ${HOME}/.config/.zshrc.d && -f ${HOME}/.config/.zshrc.d ]]; then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.config/.zshrc.d ${HOME}/.config/.zshrc.d
  else
    rm ${HOME}/.config/.zshrc.d
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.config/.zshrc.d ${HOME}/.config/.zshrc.d
  fi

  if [[ -f ${HOME}/.zprofile ]]; then
    rm ${HOME}/.zprofile
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.zprofile ${HOME}/.zprofile
  elif [[ ! -L ${HOME}/.zprofile ]]; then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.zprofile ${HOME}/.zprofile
  fi

  echo "Linking custom bruce.zsh-theme"
  if [[ ! -L ${HOME}/.oh-my-zsh/custom/themes/bruce.zsh-theme && -d ${HOME}/.oh-my-zsh/custom/themes ]]; then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/bruce.zsh-theme ${HOME}/.oh-my-zsh/custom/themes/bruce.zsh-theme
  else
    rm ${HOME}/.oh-my-zsh/custom/themes/bruce.zsh-theme
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/bruce.zsh-theme ${HOME}/.oh-my-zsh/custom/themes/bruce.zsh-theme
  fi

  if [[ ! -d ${HOME}/.tmux ]]; then
    mkdir ${HOME}/.tmux
  fi

  if [[ ! -d ${HOME}/.tmux/plugins/tpm ]]; then
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
  fi

  if [[ ! -d ${HOME}/.warp ]]; then
    mkdir ${HOME}/.warp
    chmod 700 ${HOME}/.warp
  fi
  if [[ ! -L ${HOME}/.ssh/themes && -f ${HOME}/.warp/themes ]]; then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.warp/themes ${HOME}/.warp/themes
  else
    rm ${HOME}/.warp/themes
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.warp/themes ${HOME}/.warp/themes
  fi
  if [[ ! -L ${HOME}/.ssh/launch_configurations && -f ${HOME}/.warp/launch_configurations ]]; then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.warp/launch_configurations ${HOME}/.warp/launch_configurations
  else
    rm ${HOME}/.warp/launch_configurations
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.warp/launch_configurations ${HOME}/.warp/launch_configurations
  fi

  if [[ ! -d ${HOME}/.ssh ]]; then
    mkdir ${HOME}/.ssh
    chmod 700 ${HOME}/.ssh
  fi
  if [[ ! -L ${HOME}/.ssh/config && -f ${HOME}/.ssh/config ]]; then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.ssh/config ${HOME}/.ssh/config
  else
    rm ${HOME}/.ssh/config
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.ssh/config ${HOME}/.ssh/config
  fi
  if [[ ! -L ${HOME}/.ssh/config && -f ${HOME}/.ssh/teleport.cfg ]]; then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.ssh/teleport.cfg ${HOME}/.ssh/teleport.cfg
  else
    rm ${HOME}/.ssh/teleport.cfg
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.ssh/teleport.cfg ${HOME}/.ssh/teleport.cfg
  fi

  if [[ ! -d ${HOME}/.tsh ]]; then
    mkdir ${HOME}/.tsh
    chmod 700 ${HOME}/.tsh
  fi

  echo "Setting ZSH as shell..."
  if [[ ! ${REDHAT} ]]; then
    if [[ ! ${SHELL} = "/bin/zsh" ]]; then
      chsh -s /bin/zsh
    fi
  elif [[ ${REDHAT} ]]; then
    if [[ ! ${SHELL} = "/usr/local/bin/zsh" ]]; then
      chsh -s /usr/local/bin/zsh
    fi
  fi

  echo "Setting up cheat.sh"
  if [[ -d ${HOME}/bin ]]; then
    if [[ ${UBUNTU} ]]; then
      sudo -H apt update
      sudo -H apt install curl -y
    fi
    if [[ ${CENTOS} ]]; then
      sudo -H dnf update -y
      sudo -H dnf install curl -y
    fi
    if [[ ${REDHAT} ]] || [[ ${FEDORA} ]]; then
      sudo -H yum update
      sudo -H yum install curl -y
    fi
    curl https://cht.sh/:cht.sh > ~/bin/cht.sh
    chmod 750 ${HOME}/bin/cht.sh
  fi
  if [[ ! -d ${HOME}/.zsh.d ]]; then
    mkdir ${HOME}/.zsh.d
  fi
  if [[ ! -f ${HOME}/.zsh.d/_cht ]]; then
    curl https://cheat.sh/:zsh > ${HOME}/.zsh.d/_cht
  fi
fi

# full setup and installation of all packages for a development environment
if [[ ${SETUP} || ${DEVELOPER} ]]; then
  echo "Creating home aws"
  if [[ ! -d ${HOME}/.aws ]]; then
    mkdir ${HOME}/.aws
    chmod 700 ${HOME}/.aws
  fi

  echo "Creating home gcloud_creds"
  if [[ ! -d ${HOME}/.gcloud_creds ]]; then
    mkdir ${HOME}/.gcloud_creds
    chmod 700 ${HOME}/.gcloud_creds
  fi

  echo "Creating home azure_creds"
  if [[ ! -d ${HOME}/.azure_creds ]]; then
    mkdir ${HOME}/.azure_creds
    chmod 700 ${HOME}/.azure_creds
  fi

  if [[ ${MACOS} ]]; then
    echo "Creating $BREWFILE_LOC"
    if [[ ! -d ${BREWFILE_LOC} ]]; then
      mkdir ${BREWFILE_LOC}
    fi

    if [[ ! -L ${BREWFILE_LOC}/Brewfile ]]; then
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile $BREWFILE_LOC/Brewfile
    else
      rm $BREWFILE_LOC/Brewfile
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile $BREWFILE_LOC/Brewfile
    fi

    if ! [ -x "$(command -v brew)" ]; then
      install_homebrew
    elif [ -x "$(command -v brew)" ]; then
      brew_update
      echo "Installing other brew stuff..."
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
      if [[ ${STUDIO} ]] || [[ ${LAPTOP} ]] || [[ ${BRUCEWORK} ]]; then
        brew install datawire/blackbird/telepresence-arm64
        brew install -cloudflare
      fi
      if [[ ${RATNA} ]]; then
        brew install datawire/blackbird/telepresence
      fi

      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit

      # the below casks and mas are not in a brewfile since they will "fail" if already installed
      if [[ ! -d "/Applications/1Password.app" ]]; then
        brew install --cask 1password
      fi
      if [[ ${LAPTOP} ]] || [[ ${STUDIO} ]]; then
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
      if [[ ! -d "/Applications/balenaEtcher.app" ]]; then
        brew install --cask balenaetcher
      fi
      if [[ ! -d "/Applications/Beyond\ Compare.app" ]]; then
        brew install --cask beyond-compare
      fi
      if [[ ! -d "/Applications/Carbon\ Copy Cloner.app" ]]; then
        brew install --cask carbon-copy-cloner
      fi
      if [[ ! -d "/Applications/DaisyDisk.app" ]]; then
        brew install --cask daisydisk
      fi
      if [[ ! -d "/Applications/DBeaver.app" ]]; then
        brew install --cask dbeaver-community
      fi
      if [[ ! -d "/Applications/Discord.app" ]]; then
        brew install --cask discord
      fi
      if [[ ! -d "/Applications/Docker.app" ]]; then
        brew install --cask docker
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
      if [[ ! -d "/Applications/Fork.app" ]]; then
        brew install --cask fork
      fi
      if [[ ! -d "/Applications/Funter.app" ]]; then
        brew install --cask funter
      fi
      if [[ ! -d "/Applications/Google\ Chrome.app" ]]; then
        brew install --cask google-chrome
      fi
      if [[ ! -d "/Applications/GitHub\ Desktop.app" ]]; then
        brew install --cask github
      fi
      if [[ ! -d "/usr/local/Caskroom/google-cloud-sdk" ]]; then
        brew install --cask google-cloud-sdk
      fi
      if [[ ! -d "/Applications/iStat\ Menus.app" ]]; then
        brew install --cask istat-menus
      fi
      if [[ ! -d "/Applications/iTerm.app" ]]; then
        brew install --cask iterm2
      fi
      if [[ ! -d "/Applications/Lens.app" ]]; then
        brew install --cask lens
      fi
      if [[ ! -d "/Applications/MacDown.app" ]]; then
        brew install --cask macdown
      fi
      if [[ ! -d "/Applications/Malwarebytes.app" ]]; then
        brew install --cask malwarebytes
      fi
      if [[ ${RATNA} ]] || [[ ${LAPTOP} ]] || [[ ${STUDIO} ]] || [[ ${BRUCEWORK} ]]; then
        if [[ ! -d "/Applications/Microsoft\ Word.app" ]]; then
          brew install --cask microsoft-office
        fi
      fi
      if [[ ! -d "/Applications/MySQLWorkbench.app" ]]; then
        brew install --cask mysqlworkbench
      fi
      if [[ ! -d "/Applications/OBS.app" ]]; then
        brew install --cask obs
      fi
      if [[ ! -d "/usr/local/Caskroom/oracle-jdk" ]]; then
        brew install --cask oracle-jdk
      fi
      if [[ ! -d "/Applications/Postman.app" ]]; then
        brew install --cask postman
      fi
      if [[ ! -d "/usr/local/sessionmanagerplugin" ]]; then
        brew install --cask session-manager-plugin
      fi
      if [[ ! -d "/Applications/SourceTree.app" ]]; then
        brew install --cask sourcetree
      fi
      if [[ ! -d "/Applications/PowerShell.app" ]]; then
        brew install --cask powershell
      fi
      if [[ ! -d "/Applications/Slack.app" ]]; then
        brew install --cask slack
      fi
      if [[ ! -d "/Applications/Steam.app" ]]; then
        brew install --cask steam
      fi
      if [[ ! -d "/Applications/TeamViewer.app" ]]; then
        brew install --cask teamviewer
      fi
      if [[ ! -d "/Applications/VirtualBox.app" ]]; then
        brew install --cask virtualbox
      fi
      if [[ ! -d "/Applications/Vagrant.app" ]]; then
        brew install --cask vagrant
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

      echo "Cleaning up brew"
      brew cleanup
    fi

    echo "Updating app store apps via softwareupdate"
    sudo -H softwareupdate --install --all --verbose

    echo "Installing common apps via mas"
    if [[ ! -d "/Applications/Better\ Rename\ 9.app" ]]; then
      mas install 414209656
    fi
    if [[ ${LAPTOP} ]] || [[ ${STUDIO} ]] || [[ ${BRUCEWORK} ]]; then
      if [[ ! -d "/Applications/Bitwarden.app" ]]; then
        mas install 1352778147
      fi
    fi
    if [[ ! -d "/Applications/Brother\ iPrint\&Scan.app" ]]; then
      mas install 1193539993
    fi
    if [[ ! -d "/Applications/Blackmagic\ Disk\ Speed\ Test.app" ]]; then
      mas install 425264550
    fi
    if [[ ! -d "/Applications/Evernote.app" ]]; then
      mas install 406056744
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
    if [[ ! -d "/Applications/SQLPro\ for\ Postgres.app" ]]; then
      mas install 1025345625
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
    if [[ ! -d "/Applications/Valentina\ Studio.app" ]]; then
      mas install 604825918
    fi

    if [[ ${RATNA} ]] || [[ ${LAPTOP} ]] || [[ ${STUDIO} ]] || [[ ${BRUCEWORK} ]]; then
      echo "Installing extra apps via mas"
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
      if [[ ! -d "/Applications/Pixelmator.app" ]]; then
        mas install 407963104
      fi
      if [[ ! -d "/Applications/Read CHM.app" ]]; then
        mas install 594432954
      fi
      if [[ ! -d "/Applications/Telegram.app" ]]; then
        mas install 747648890
      fi
      echo "Installing xcode-stuff"
      if [[ ! -d "/Applications/Xcode.app" ]]; then
        mas install 497799835
      fi
    fi

    echo "Setting up macOS defaults"
    ~/scripts/.osx.sh

  fi

  if [[ ${UBUNTU} ]]; then
    sudo -H apt update
    if [[ ${FOCAL} ]]; then
      sudo -H apt install --install-recommends linux-generic-hwe-20.04 -y
    elif [[ ${JAMMY} ]]; then
      sudo -H apt install --install-recommends linux-generic-hwe-22.04 -y
    fi
    xargs -a ./ubuntu_common_packages.txt sudo apt install -y
    if [[ ${FOCAL} ]]; then
      xargs -a ./ubuntu_2004_packages.txt sudo apt install -y
    elif [[ ${JAMMY} ]]; then
      xargs -a ./ubuntu_2204_packages.txt sudo apt install -y
    fi

    if [[ ${WORKSTATION} ]]; then
      # apt package installation
      xargs -a ./ubuntu_workstation_packages.txt sudo apt install -y

      # snap package installation
      xargs -a ./ubuntu_workstation_snap_packages.txt sudo snap install

    fi

    if [[ ${BIONIC} ]]; then
      echo "Installing python 3.8 Ubuntu 18.04"
      sudo -H add-apt-repository ppa:deadsnakes/ppa
      sudo -H apt update
      sudo -H apt install python3.8 -y
    fi

    echo "Installing pyenv"
    curl https://pyenv.run | bash

    echo "Installing powershell Ubuntu"
    if [[ ${BIONIC} ]]; then
      if [[ ! -f ${HOME}/software_downloads/packages-microsoft-prod.deb ]]; then
        wget -O ${HOME}/software_downloads/packages-microsoft-prod.deb http://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
        sudo -H dpkg -i ${HOME}/software_downloads/packages-microsoft-prod.deb
        sudo apt update
        sudo -H add-apt-repository universe
        sudo -H apt install powershell -y
      fi
    fi
    if [[ ${FOCAL} ]]; then
      if [[ ! -f ${HOME}/software_downloads/packages-microsoft-prod.deb ]]; then
        wget -O ${HOME}/software_downloads/packages-microsoft-prod.deb http://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
        sudo -H dpkg -i ${HOME}/software_downloads/packages-microsoft-prod.deb
        sudo apt update
        sudo -H add-apt-repository universe
        sudo -H apt install powershell -y
      fi
    fi
    if [[ ${JAMMY} ]]; then
      if [[ ! -f ${HOME}/software_downloads/packages-microsoft-prod.deb ]]; then
        wget -O ${HOME}/software_downloads/packages-microsoft-prod.deb http://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
        sudo -H dpkg -i ${HOME}/software_downloads/packages-microsoft-prod.deb
        sudo apt update
        sudo -H add-apt-repository universe
        sudo -H apt install powershell -y
      fi
    fi

    echo "Installing go Ubuntu"
    sudo add-apt-repository ppa:longsleep/golang-backports -y
    sudo -H apt update
    if [[ ${GO_VER} == "1.16" ]]; then
      if [[ $(dpkg-query -W -f='${Status}' golang-1.15-go 2>/dev/null | grep -c "ok installed") -eq 1 ]]; then
        sudo -H apt remove golang-1.15-go -y
      fi
      if [[ $(dpkg-query -W -f='${Status}' golang-1.15-src 2>/dev/null | grep -c "ok installed") -eq 1 ]]; then
        sudo -H apt remove golang-1.15-src -y
      fi
    elif [[ ${GO_VER} == "1.17" ]]; then
      if [[ $(dpkg-query -W -f='${Status}' golang-1.16-go 2>/dev/null | grep -c "ok installed") -eq 1 ]]; then
        sudo -H apt remove golang-1.16-go -y
      fi
      if [[ $(dpkg-query -W -f='${Status}' golang-1.16-src 2>/dev/null | grep -c "ok installed") -eq 1 ]]; then
        sudo -H apt remove golang-1.16-src -y
      fi
    elif [[ ${GO_VER} == "1.18" ]]; then
      if [[ $(dpkg-query -W -f='${Status}' golang-1.17-go 2>/dev/null | grep -c "ok installed") -eq 1 ]]; then
        sudo -H apt remove golang-1.17-go -y
      fi
      if [[ $(dpkg-query -W -f='${Status}' golang-1.17-src 2>/dev/null | grep -c "ok installed") -eq 1 ]]; then
        sudo -H apt remove golang-1.17-src -y
      fi
    elif [[ ${GO_VER} == "1.19" ]]; then
      if [[ $(dpkg-query -W -f='${Status}' golang-1.18-go 2>/dev/null | grep -c "ok installed") -eq 1 ]]; then
        sudo -H apt remove golang-1.18-go -y
      fi
      if [[ $(dpkg-query -W -f='${Status}' golang-1.18-src 2>/dev/null | grep -c "ok installed") -eq 1 ]]; then
        sudo -H apt remove golang-1.18-src -y
      fi
      sudo -H apt install golang-${GO_VER}-go -y
    fi

    if [[ ! ${WORKSTATION} ]]; then
      echo "Installing docker"
      curl -fsSL http://download.docker.com/linux/ubuntu/gpg | sudo -H apt-key add -
      sudo -H add-apt-repository \
      "deb [arch=amd64] http://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) \
      stable"
      sudo -H apt update
      sudo -H apt install docker-ce -y
      sudo -H apt install docker-ce-cli -y
      sudo -H apt install containerd.io -y
    fi

    if [[ ! ${CRUNCHER} ]] || [[ ! ${WORKSTATION} ]]; then
      echo "Installing Virtualbox"
      wget -q http://www.virtualbox.org/download/oracle_vbox_2016.asc -O- | sudo apt-key add -
      wget -q http://www.virtualbox.org/download/oracle_vbox.asc -O- | sudo apt-key add -
      sudo add-apt-repository "deb http://download.virtualbox.org/virtualbox/debian $(lsb_release -cs) contrib"
      sudo -H apt update
      sudo -H apt install virtualbox-6.1 -y
    fi

    if [[ ${WORKSTATION} ]] || [[ ${CRUNCHER} ]]; then
      echo "Installing teleport"
      wget -q https://deb.releases.teleport.dev/teleport-pubkey.asc -O- | sudo apt-key add -
      sudo add-apt-repository "deb https://deb.releases.teleport.dev/ stable main"
      sudo -H apt update
      sudo -H apt install teleport -y
    fi

    if [[ ${WORKSTATION} ]] || [[ ${CRUNCHER} ]]; then
      echo "Installing cloudflared"
      wget -q https://pkg.cloudflare.com/cloudflare-main.gpg -O- | sudo apt-key add -
      sudo add-apt-repository "deb https://pkg.cloudflare.com/ $(lsb_release -cs) main"
      sudo -H apt update
      sudo -H apt install cloudflared -y
    fi

    if [[ ${WORKSTATION} ]] || [[ ${CRUNCHER} ]]; then
      if [[ ! -f ${HOME}/software_downloads/kind_${KIND_VER} ]]; then
        echo "Installing kind"
        wget -O ${HOME}/software_downloads/kind_${KIND_VER} ${KIND_URL}
        sudo cp -a ${HOME}/software_downloads/kind_${KIND_VER} /usr/local/bin/
        sudo mv /usr/local/bin/kind_${KIND_VER} /usr/local/bin/kind
        sudo chmod 755 /usr/local/bin/kind
        sudo chown root:root /usr/local/bin/kind
      fi
    fi

    if [[ ${WORKSTATION} ]] || [[ ${CRUNCHER} ]]; then
      if [[ ! -f ${HOME}/software_downloads/yq_${YQ_VER} ]]; then
        echo "Installing yq"
        wget -O ${HOME}/software_downloads/yq_${YQ_VER} ${YQ_URL}
        sudo cp -a ${HOME}/software_downloads/yq_${YQ_VER} /usr/local/bin/
        sudo mv /usr/local/bin/yq_${YQ_VER} /usr/local/bin/yq
        sudo chmod 755 /usr/local/bin/yq
        sudo chown root:root /usr/local/bin/yq
      fi
    fi

    if [[ ${WORKSTATION} ]]; then
      if [[ ${FOCAL} ]]; then
        echo "Installing Albert"
        curl https://build.opensuse.org/projects/home:manuelschneid3r/public_key | sudo apt-key add -
        echo "deb http://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_$(lsb_release -rs)/ /" | sudo tee /etc/apt/sources.list.d/home:manuelschneid3r.list
        sudo wget -nv https://download.opensuse.org/repositories/home:manuelschneid3r/xUbuntu_$(lsb_release -rs)/Release.key -O "/etc/apt/trusted.gpg.d/home:manuelschneid3r.asc"
        sudo -H apt update
        sudo -H apt install albert -y
      elif [[ ${JAMMY} ]]; then
        echo "Installing Albert"
        curl https://build.opensuse.org/projects/home:manuelschneid3r/public_key | sudo apt-key add -
        echo "deb http://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_$(lsb_release -rs)/ /" | sudo tee /etc/apt/sources.list.d/home:manuelschneid3r.list
        sudo wget -nv https://download.opensuse.org/repositories/home:manuelschneid3r/xUbuntu_$(lsb_release -rs)/Release.key -O "/etc/apt/trusted.gpg.d/home:manuelschneid3r.asc"
        sudo -H apt update
        sudo -H apt install albert -y
      fi
    fi

    if [[ ${WORKSTATION} ]] || [[ ${CRUNCHER} ]]; then
      echo "Installing telepresence"
      wget -O ${HOME}/software_downloads/telepresence ${TELEPRESENCE_URL}
      sudo cp -a ${HOME}/software_downloads/telepresence /usr/local/bin/
      sudo chmod 755 /usr/local/bin/telepresence
      sudo chown root:root /usr/local/bin/telepresence
    fi

    echo "Installing azure-cli"
    curl -sL http://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor | \
    sudo tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg > /dev/null
    AZ_REPO=$(lsb_release -cs)
    sudo -H add-apt-repository \
    "deb [arch=amd64] http://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main"
    sudo -H apt update
    sudo -H apt install azure-cli -y

    echo "Installing gcloud-sdk"
    if [[ ! -f /etc/apt/sources.list.d/google-cloud-sdk.list ]]; then
      echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
      curl http://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
    fi
    sudo apt update
    sudo -H apt install google-cloud-sdk -y
    sudo -H apt install google-cloud-sdk-app-engine-python -y
    sudo -H apt install google-cloud-sdk-app-engine-python-extras -y
    sudo -H apt install google-cloud-sdk-app-engine-go -y

    echo "Installing Hashicorp Consul Ubuntu"
    if [[ ! -d ${HOME}/software_downloads/consul_${CONSUL_VER} ]]; then
      wget -O ${HOME}/software_downloads/consul_${CONSUL_VER}_linux_amd64.zip ${HASHICORP_URL}/consul/${CONSUL_VER}/consul_${CONSUL_VER}_linux_amd64.zip
      unzip ${HOME}/software_downloads/consul_${CONSUL_VER}_linux_amd64.zip -d ${HOME}/software_downloads/consul_${CONSUL_VER}
      sudo cp -a ${HOME}/software_downloads/consul_${CONSUL_VER}/consul /usr/local/bin/
      sudo chmod 755 /usr/local/bin/consul
      sudo chown root:root /usr/local/bin/consul
    fi

    echo "Installing Hashicorp Vault Ubuntu"
    if [[ ! -d ${HOME}/software_downloads/vault_${VAULT_VER} ]]; then
      wget -O ${HOME}/software_downloads/vault_${VAULT_VER}_linux_amd64.zip ${HASHICORP_URL}/vault/${VAULT_VER}/vault_${VAULT_VER}_linux_amd64.zip
      unzip ${HOME}/software_downloads/vault_${VAULT_VER}_linux_amd64.zip -d ${HOME}/software_downloads/vault_${VAULT_VER}
      sudo cp -a ${HOME}/software_downloads/vault_${VAULT_VER}/vault /usr/local/bin/
      sudo chmod 755 /usr/local/bin/vault
      sudo chown root:root /usr/local/bin/vault
    fi

    echo "Installing Hashicorp Nomad Ubuntu"
    if [[ ! -d ${HOME}/software_downloads/nomad_${NOMAD_VER} ]]; then
      wget -O ${HOME}/software_downloads/nomad_${NOMAD_VER}_linux_amd64.zip ${HASHICORP_URL}/nomad/${NOMAD_VER}/nomad_${NOMAD_VER}_linux_amd64.zip
      unzip ${HOME}/software_downloads/nomad_${NOMAD_VER}_linux_amd64.zip -d ${HOME}/software_downloads/nomad_${NOMAD_VER}
      sudo cp -a ${HOME}/software_downloads/nomad_${NOMAD_VER}/nomad /usr/local/bin/
      sudo chmod 755 /usr/local/bin/nomad
      sudo chown root:root /usr/local/bin/nomad
    fi

    echo "Installing Hashicorp Packer Ubuntu"
    if [[ ! -d ${HOME}/software_downloads/packer_${PACKER_VER} ]]; then
      wget -O ${HOME}/software_downloads/packer_${PACKER_VER}_linux_amd64.zip ${HASHICORP_URL}/packer/${PACKER_VER}/packer_${PACKER_VER}_linux_amd64.zip
      unzip ${HOME}/software_downloads/packer_${PACKER_VER}_linux_amd64.zip -d ${HOME}/software_downloads/packer_${PACKER_VER}
      sudo cp -a ${HOME}/software_downloads/packer_${PACKER_VER}/packer /usr/local/bin/
      sudo chmod 755 /usr/local/bin/packer
      sudo chown root:root /usr/local/bin/packer
    fi

    echo "Installing Hashicorp Vagrant Ubuntu"
    if [[ ! -d ${HOME}/software_downloads/vagrant_${VAGRANT_VER} ]]; then
      wget -O ${HOME}/software_downloads/vagrant_${VAGRANT_VER}_linux_amd64.zip ${HASHICORP_URL}/vagrant/${VAGRANT_VER}/vagrant_${VAGRANT_VER}_linux_amd64.zip
      unzip ${HOME}/software_downloads/vagrant_${VAGRANT_VER}_linux_amd64.zip -d ${HOME}/software_downloads/vagrant_${VAGRANT_VER}
      sudo cp -a ${HOME}/software_downloads/vagrant_${VAGRANT_VER}/vagrant /usr/local/bin/
      sudo chmod 755 /usr/local/bin/vagrant
      sudo chown root:root /usr/local/bin/vagrant
    fi

    echo "Installing docker-compose Ubuntu"
    if [[ ! -f ${HOME}/software_downloads/docker-compose_${DOCKER_COMPOSE_VER} ]]; then
      wget -O ${HOME}/software_downloads/docker-compose_${DOCKER_COMPOSE_VER} ${DOCKER_COMPOSE_URL}
      sudo cp -a ${HOME}/software_downloads/docker-compose_${DOCKER_COMPOSE_VER} /usr/local/bin/
      sudo mv /usr/local/bin/docker-compose_${DOCKER_COMPOSE_VER} /usr/local/bin/docker-compose
      sudo chmod 755 /usr/local/bin/docker-compose
      sudo chown root:root /usr/local/bin/docker-compose
    fi

    echo "Installing cf-terraforming Ubuntu"
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
    fi

    if ! [ -x "$(command -v brew)" ]; then
      install_homebrew
    elif [ -x "$(command -v brew)" ]; then
      echo "Installing brew packages in Ubuntu"
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
      brew install neovim
      brew install ripgrep
      brew install starship
      brew install tgenv
      brew install zoxide
      brew install go-task/tap/go-task
      brew tap snyk/tap
      brew install snyk
    fi

    if [[ ${WORKSTATION} ]]; then
      echo "Installing microsoft teams"
      sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/ms-teams stable main" > /etc/apt/sources.list.d/teams.list'
      sudo -H apt update
      sudo -H apt install teams -y
    fi

    if [[ ${WORKSTATION} ]]; then
      echo "Installing microsoft edge"
      sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/edge stable main" > /etc/apt/sources.list.d/microsoft-edge.list'
      sudo -H apt update
      sudo -H apt install microsoft-edge-stable -y
    fi

    if [[ ${WORKSTATION} ]] || [[ ${CRUNCHER} ]]; then
      echo "Installing .net6 sdk"
      sudo -H apt install dotnet-sdk-6.0 -y
    fi

    python3 -m pip install glances
    if [[ ! -f /usr/share/keyrings/kubernetes-archive-keyring.gpg ]]; then
      sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
      echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    fi
    sudo -H apt update
    sudo -H apt install kubectl -y

    if [[ ${WORKSTATION} ]]; then
      echo "snap software with classic option, the other snap packages are installed in ubuntu_workstation_snap_packages.txt"
      sudo snap install atom --classic
      sudo snap install code --classic
      sudo snap install helm --classic
      sudo snap install slack --classic
      sudo snap install certbot --classic
      sudo snap set certbot trust-plugin-with-root=ok
      sudo snap install certbot-dns-route53
    fi
    # can't use snap on wsl2
    if [[ ${CRUNCHER} ]]; then
      curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
      echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
      sudo apt-get update
      sudo apt-get install helm
    fi

    echo "Installing kustomize"
    cd ${HOME}/software_downloads || exit
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    if [[ -f ${HOME}/software_downloads/kustomize ]]; then
      sudo -H mv ${HOME}/software_downloads/kustomize /usr/local/bin/kustomize
      sudo chmod 755 /usr/local/bin/kustomize
      sudo chown root:root /usr/local/bin/kustomize
    fi

    sudo -H apt autoremove -y
  fi

  if [[ ${REDHAT} || ${FEDORA} ]]; then
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

    echo "Installing pyenv"
    curl https://pyenv.run | bash

    echo "Installing shellcheck RHEL"
    if [[ ! -d ${HOME}/software_downloads/shellcheck-v${SHELLCHEK_VER} ]]; then
      wget -O ${HOME}/software_downloads/shellcheck-v${SHELLCHEK_VER}.linux.x86_64.tar.xz https://shellcheck.storage.googleapis.com/shellcheck-v${SHELLCHEK_VER}.linux.x86_64.tar.xz
      xz --decompress ${HOME}/software_downloads/shellcheck-v${SHELLCHEK_VER}.linux.x86_64.tar.xz
      cd ${HOME}/software_downloads || exit
      tar -xf ${HOME}/software_downloads/shellcheck-v${SHELLCHEK_VER}.linux.x86_64.tar
      sudo cp -a ${HOME}/software_downloads/shellcheck-v${SHELLCHEK_VER}/shellcheck /usr/local/bin/
      sudo chmod 755 /usr/local/bin/shellcheck
      sudo chown root:root /usr/local/bin/shellcheck
    fi

    echo "Installing keychain RHEL"
    sudo -H rpm --import http://wiki.psychotic.ninja/RPM-GPG-KEY-psychotic
    sudo -H rpm -ivh http://packages.psychotic.ninja/6/base/i386/RPMS/psychotic-release-1.0.0-1.el6.psychotic.noarch.rpm
    sudo -H yum --enablerepo=psychotic install keychain -y

    echo "Installing azure-cli RHEL"
    sudo -H rpm --import http://packages.microsoft.com/keys/microsoft.asc
    sudo -H sh -c 'echo -e "[azure-cli]\nname=Azure CLI\nbaseurl=http://packages.microsoft.com/yumrepos/azure-cli\nenabled=1\ngpgcheck=1\ngpgkey=http://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/azure-cli.repo'
    sudo -H dnf update -y
    sudo -H dnf install azure-cli -y

    echo "Installing git credential manager RHEL"
    sudo -H dnf install http://github.com/Microsoft/Git-Credential-Manager-for-Mac-and-Linux/releases/download/git-credential-manager-2.0.4/git-credential-manager-2.0.4-1.noarch.rpm -y

    echo "Installing powershell RHEL"
    curl http://packages.microsoft.com/config/rhel/7/prod.repo | sudo -H tee /etc/yum.repos.d/microsoft.repo
    sudo -H dnf update -y
    sudo -H dnf install powershell -y

    echo "Installing npm RHEL"
    curl -sL http://rpm.nodesource.com/setup_12.x | sudo -E bash -
    sudo -H dnf update -y
    sudo -H dnf install nodejs -y

    echo "Installing glances cpu monitor RHEL"
    sudo -H python3 -m pip install glances

    echo "Installing go RHEL"
    if [[ ! -f ${HOME}/software_downloads/go${GO_VER}.linux-amd64.tar.gz ]]; then
      wget -O ${HOME}/software_downloads/go${GO_VER}.linux-amd64.tar.gz https://dl.google.com/go/go${GO_VER}.linux-amd64.tar.gz
      sudo tar -C /usr/local -xzf ${HOME}/software_downloads/go${GO_VER}.linux-amd64.tar.gz
    fi

    echo "Installing google-cloud-sdk RHEL"
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

    echo "Installing kubectl RHEL"
    if [[ ! -f /etc/yum.repos.d/kubernetes.repo ]]; then
      sudo echo "${RHEL_KUBECTL_REPO}" > /tmp/kubernetes.repo
      sudo chown root:root /tmp/kubernetes.repo
      sudo chmod 644 /tmp/kubernetes.repo
      sudo mv /tmp/kubernetes.repo /etc/yum.repos.d/kubernetes.repo
    fi
    sudo -H dnf update -y
    sudo -H dnf install kubectl -y

    echo "Installing Hashicorp Packer RHEL"
    if [[ ! -d ${HOME}/software_downloads/packer_${PACKER_VER} ]]; then
      wget -O ${HOME}/software_downloads/packer_${PACKER_VER}_linux_amd64.zip ${HASHICORP_URL}/packer/${PACKER_VER}/packer_${PACKER_VER}_linux_amd64.zip
      unzip ${HOME}/software_downloads/packer_${PACKER_VER}_linux_amd64.zip -d ${HOME}/software_downloads/packer_${PACKER_VER}
      sudo cp -a ${HOME}/software_downloads/packer_${PACKER_VER}/packer /usr/local/bin/
      sudo chmod 755 /usr/local/bin/packer
      sudo chown root:root /usr/local/bin/packer
    fi

  fi

  if [[ ${CENTOS} ]]; then
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

  if [[ ${LINUX} ]]; then
    echo "Installing Hashicorp Terraform Linux with tfenv on Linux"
    if [[ ! -d ${HOME}/.tfenv ]]; then
      git clone --recursive https://github.com/tfutils/tfenv.git ${HOME}/.tfenv
    fi
    if [[ -f /usr/local/bin/terraform ]]; then
      sudo rm /usr/local/bin/terraform
    fi
    if [[ ! -L /usr/local/bin/tfenv ]]; then
      sudo ln -s ${HOME}/.tfenv/bin/tfenv /usr/local/bin/tfenv
    fi
    if [[ ! -L /usr/local/bin/terraform ]]; then
      sudo ln -s ${HOME}/.tfenv/bin/terraform /usr/local/bin/terraform
    fi
    if [[ -f ${HOME}/.tfenv/bin/tfenv ]]; then
      tfenv install ${TERRAFORM_VER}
    fi
    echo "Installing tflint"
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
    echo "Installing tfsec"
    if [[ ! -f ${HOME}/software_downloads/tfsec-linux-amd64 ]]; then
      wget -O ${HOME}/software_downloads/tfsec-linux-amd64 ${TFSEC_URL}
      sudo -H mv ${HOME}/software_downloads/tfsec-linux-amd64 /usr/local/bin/tfsec
      sudo -H chmod 755 /usr/local/bin/tfsec
    fi
  fi

  echo "Installing aws-cli"
  if [[ ${LINUX} ]]; then
    if [[ ! -d ${HOME}/software_downloads/awscli ]]; then
      mkdir ${HOME}/software_downloads/awscli
    fi
    if [[ ! -f ${HOME}/software_downloads/awscli/awscliv2.zip ]]; then
      wget -O ${HOME}/software_downloads/awscli/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
      unzip ${HOME}/software_downloads/awscli/awscliv2.zip -d ${HOME}/software_downloads/awscli
      sudo -H ${HOME}/software_downloads/awscli/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin
    fi
  fi

  echo "vim plugins"
  if [[ ! -d ${HOME}/.vim ]]; then
    mkdir ${HOME}/.vim
    chmod 770 ${HOME}/.vim
    if [[ ! -d ${HOME}/.vim/plugged ]]; then
      mkdir ${HOME}/.vim/plugged
      chmod 770 ${HOME}/.vim/plugged
    fi
    if [[ ! -d ${HOME}/.vim/autoload ]]; then
      mkdir ${HOME}/.vim/autoload
      chmod 770 ${HOME}/.vim/autoload
      if [[ ! -f ${HOME}/.vim/autoload/plug.vim ]]; then
        curl -fLo ${HOME}/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
      fi
    fi
  fi

fi

if [[ ${DEVELOPER} || ${ANSIBLE} ]]; then
  echo "Installing json2yaml via npm"
  npm install json2yaml

  echo "Installing ruby-install on linux"
  if [[ ${LINUX} ]]; then
    if [[ ! -d ${HOME}/software_downloads/ruby-install-${RUBY_INSTALL_VER} ]]; then
      wget -O ${HOME}/software_downloads/ruby-install-${RUBY_INSTALL_VER}.tar.gz https://github.com/postmodern/ruby-install/archive/v${RUBY_INSTALL_VER}.tar.gz
      tar -xzvf ${HOME}/software_downloads/ruby-install-${RUBY_INSTALL_VER}.tar.gz -C ${HOME}/software_downloads/
      cd ${HOME}/software_downloads/ruby-install-${RUBY_INSTALL_VER}/ || exit
      sudo make install
    fi
  fi

  echo "Installing chruby on linux"
  if [[ ${LINUX} ]]; then
    if [[ ! -d ${HOME}/software_downloads/chruby-${CHRUBY_VER} ]]; then
      wget -O ${HOME}/software_downloads/chruby-${CHRUBY_VER}.tar.gz https://github.com/postmodern/chruby/archive/v${CHRUBY_VER}.tar.gz
      tar -xzvf ${HOME}/software_downloads/chruby-${CHRUBY_VER}.tar.gz -C ${HOME}/software_downloads/
      cd ${HOME}/software_downloads/chruby-${CHRUBY_VER}/ || exit
      sudo make install
    fi
  fi

  echo "install ruby ${RUBY_VER}"
  if [[ ! -d ${HOME}/.rubies/ruby-${RUBY_VER}/bin ]]; then
    ruby-install ruby ${RUBY_VER}
  fi

  if [[ ${LINUX} ]]; then
    echo "installing github cli on linux"
    if [[ ${UBUNTU} ]]; then
      sudo -H apt-key adv --keyserver keyserver.ubuntu.com --recv-key C99B11DEB97541F0
      sudo -H apt-add-repository https://cli.github.com/packages
      sudo -H apt update
      sudo -H apt install gh
    elif [[ ${REDHAT} || ${CENTOS} || ${FEDORA} ]]; then
      sudo -H dnf config-manager --add-repo http://cli.github.com/packages/rpm/gh-cli.repo
      sudo dnf install gh
    fi
  fi

  echo "Setup kitchen"
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

  echo "Install terraspace"
  gem install terraspace

  echo "ANSIBLE setup"
  if [[ ${LINUX} ]]; then
    pyenv update
  fi
  if ! [[ -d ${HOME}/.pyenv/versions/${PYTHON_VER} ]]; then
    pyenv install ${PYTHON_VER}
  fi

  if ! [[ $(readlink ${HOME}/.pyenv/versions/ansible) == "${HOME}/.pyenv/versions/${PYTHON_VER}/envs/ansible" ]]; then
    if [[ ${STUDIO} ]] || [[ ${LAPTOP} ]] || [[ ${WORKSTATION} ]] || [[ ${CRUNCHER} ]] || [[ ${RATNA} ]]; then
      pyenv virtualenv-delete -f ansible
      pyenv virtualenv ${PYTHON_VER} ansible
      pyenv activate ansible
      python3 -m pip install ansible ansible-cmdb ansible-lint certbot certbot-dns-cloudflare boto3 docker docker-compose jmespath pylint psutil bpytop HttpPy j2cli wheel
    elif [[ ${BRUCEWORK} ]]; then
      pyenv virtualenv-delete -f ansible
      pyenv virtualenv ${PYTHON_VER} ansible
      pyenv activate ansible
      python3 -m pip --cert ~/nscacerts.pem install ansible ansible-cmdb ansible-lint boto3 docker docker-compose jmespath pylint psutil bpytop HttpPy j2cli wheel
    fi
  fi

  echo "personal git repos cloning"
  if ! [[ -d ${PERSONAL_GITREPOS}/dotfiles ]]; then
    git clone git@github.com:brujack/dotfiles.git ${PERSONAL_GITREPOS}/dotfiles
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/aws_terraform_modules ]]; then
    git clone git@github.com:brujack/aws_terraform_modules.git ${PERSONAL_GITREPOS}/aws_terraform_modules
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/aws_terraform_using_modules ]]; then
    git clone git@github.com:brujack/aws_terraform_using_modules.git ${PERSONAL_GITREPOS}/aws_terraform_using_modules
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
if [[ ${UPDATE} ]]; then
  if [[ ${MACOS} || ${LINUX} ]]; then
    brew_update
    echo "Updating app store apps softwareupdate"
    sudo -H softwareupdate --install --all --verbose
  fi
  if [[ ${UBUNTU} ]]; then
    sudo -H apt update
    sudo -H apt dist-upgrade -y
    sudo -H apt autoremove -y
    sudo snap refresh
  fi
  if [[ ${REDHAT} || ${FEDORA} ]]; then
    sudo -H dnf update -y
  fi
  if [[ ${CENTOS} ]]; then
    sudo -H yum update -y
  fi
  if [[ ${MACOS} ]]; then
    echo "Updating mas packages"
    mas upgrade
  fi
  echo "Updating pip3 packages"
  if [[ ${STUDIO} ]] || [[ ${LAPTOP} ]] || [[ ${WORKSTATION} ]] || [[ ${CRUNCHER} ]] || [[ ${RATNA} ]]; then
    python3 -m pip install --upgrade pip
    python3 -m pip list --outdated --format=columns | awk '{print $1;}' | awk 'NR>2' | xargs -n1 python3 -m pip install -U
    python3 -m pip check
  elif [[ ${BRUCEWORK} ]]; then
    python3 -m pip install --upgrade pip --cert ~/nscacerts.pem
    python3 -m pip list --outdated --format=columns --cert ~/nscacerts.pem | awk '{print $1;}' | awk 'NR>2' | xargs -n1 python3 -m pip install -U --cert ~/nscacerts.pem
    python3 -m pip check --cert ~/nscacerts.pem
  fi
  if [[ ${LINUX} ]]; then
    echo "Updating Linux awscli"
    cd ${HOME}/software_downloads/awscli || exit
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -u -o awscliv2.zip
    sudo -H ${HOME}/software_downloads/awscli/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin --update
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
  fi
  if [[ -d ${HOME}/.tfenv ]]; then
    echo "Updating tfenv"
    cd ${HOME}/.tfenv || exit
    git pull
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
  fi
  if [[ -d ${HOME}/.oh-my-zsh ]]; then
    echo "Updating oh-my-zsh"
    cd ${HOME}/.oh-my-zsh || exit
    git pull
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
  fi
  if [[ -d ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k ]]; then
    echo "Updating powerlevel10k"
    cd ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k || exit
    git pull
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
  fi
  if [[ -d ${HOME}/.tmux/plugins/tpm ]]; then
    echo "Updating tpm"
    cd ${HOME}/.tmux/plugins/tpm || exit
    git pull
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
  fi
  if [[ -f ${HOME}/bin/cht.sh ]]; then
    echo "Updating cheat.sh"
    curl https://cht.sh/:cht.sh > ~/bin/cht.sh
    chmod 754 ${HOME}/bin/cht.sh
  fi
  if [[ -f ${HOME}/.zsh.d/_cht ]]; then
    echo "Updating cheat.sh tab completion"
    curl https://cheat.sh/:zsh > ${HOME}/.zsh.d/_cht
  fi
  if [[ -d ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then
    echo "Updating zsh-autosuggestions"
    cd ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions || exit
    git pull
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
  fi
  echo "updating ruby gems"
  gem update
fi

/usr/bin/env zsh ${HOME}/.zshrc

exit 0
