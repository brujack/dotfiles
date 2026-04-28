#!/usr/bin/env bash
# lib/linux_rhel.sh — RHEL, CentOS, and generic Linux install functions

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
  local _pyenv_script_rhel
  _pyenv_script_rhel="$(mktemp)"
  curl -fsSL https://pyenv.run -o "${_pyenv_script_rhel}" || { rm -f "${_pyenv_script_rhel}"; return 1; }
  bash "${_pyenv_script_rhel}"
  rm -f "${_pyenv_script_rhel}"
  if [[ -x $(command -v pyenv) ]]; then
    printf "pyenv is installed\\n"
  fi

  printf "Installing shellcheck RHEL\\n"
  if [[ ! -d ${HOME}/software_downloads/shellcheck-v${SHELLCHECK_VER} ]]; then
    wget -O ${HOME}/software_downloads/shellcheck-v${SHELLCHECK_VER}.linux.x86_64.tar.xz https://shellcheck.storage.googleapis.com/shellcheck-v${SHELLCHECK_VER}.linux.x86_64.tar.xz
    xz --decompress ${HOME}/software_downloads/shellcheck-v${SHELLCHECK_VER}.linux.x86_64.tar.xz
    cd ${HOME}/software_downloads || return 1
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

  if [[ -n ${HAS_DEVTOOLS} ]]; then
    printf "Installing ggshield RHEL\\n"
    if ! command -v ggshield &>/dev/null; then
      pip3 install ggshield
    fi
    if command -v ggshield &>/dev/null; then
      printf "ggshield is installed\\n"
    fi
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
  if [[ ! -f ${HOME}/software_downloads/tflint_linux_amd64.zip ]]; then
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

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
