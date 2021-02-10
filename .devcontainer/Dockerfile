# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.158.0/containers/ubuntu/.devcontainer/base.Dockerfile

# [Choice] Ubuntu version: bionic, focal
ARG VARIANT="focal"
FROM mcr.microsoft.com/vscode/devcontainers/base:0-${VARIANT}

# Options for setup script
ARG INSTALL_ZSH="true"
ARG UPGRADE_PACKAGES="true"
ARG Z_GIT="https://github.com/rupa/z.git"
ARG GO_VER="1.15"
ARG HELM_VER="3.5.2"
ARG TERRAFORM_VER="0.14.5"

ARG USER_NAME="vscode"

# upgrade all packages
RUN apt update && apt dist-upgrade -y

# Install package software-properties-common to get add-apt-repository
RUN apt update && apt install software-properties-common -y

# Install newer version of git
RUN add-apt-repository ppa:git-core/ppa && apt update && apt install git -y

# Install common packages
RUN apt update && apt install -y \
  apt-transport-https \
  autoconf \
  automake \
  bison \
  build-essential \
  ca-certificates \
  cpanminus \
  curl \
  dnstop \
  dnsutils \
  flex \
  fonts-powerline \
  fzf \
  gcc \
  git \
  gnupg \
  htop \
  iotop \
  iperf3 \
  jq \
  keychain \
  libbz2-dev \
  libffi-dev \
  liblzma-dev \
  libelf-dev \
  libncurses5-dev \
  libncursesw5-dev \
  libpython3-dev \
  libreadline-dev \
  libssl-dev \
  libsqlite3-dev \
  llvm \
  lm-sensors \
  locales \
  lsof \
  make \
  mtr-tiny \
  ncdu \
  network-manager \
  net-tools \
  nload \
  nodejs \
  npm \
  openssh-server \
  openssl \
  python-openssl \
  python-setuptools \
  python3-pip \
  python3-setuptools \
  ranger \
  rar \
  rlwrap \
  screen \
  shellcheck \
  silversearcher-ag \
  smartmontools \
  software-properties-common \
  sysstat \
  thermald \
  tk-dev \
  tmux \
  traceroute \
  unattended-upgrades \
  unrar \
  unzip \
  vim \
  wget \
  xinetd \
  xz-utils \
  zlib1g-dev \
  zip \
  zsh \
  zsh-doc

# Setup and install of oh-my-zsh
USER $USER_NAME
ENV TERM xterm
ENV ZSH_THEME powerlevel10k/powerlevel10k
RUN wget https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh || true
RUN git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /home/$USER_NAME/.oh-my-zsh/custom/themes/powerlevel10k
COPY .zshrc /home/$USER_NAME/.zshrc
COPY .p10k.zsh /home/$USER_NAME/.p10k.zsh

# Copy app rc files
COPY .vimrc /home/$USER_NAME/.vimrc
COPY .gitconfig_linux /home/$USER_NAME/.gitconfig
COPY .tmux.conf /home/$USER_NAME/.tmux.conf

# mkdir some things
RUN mkdir /home/$USER_NAME/bin
RUN mkdir /home/$USER_NAME/scripts
RUN mkdir /home/$USER_NAME/.aws
RUN chmod 700 /home/$USER_NAME/.aws
RUN mkdir /home/$USER_NAME/.ssh
RUN chmod 700 /home/$USER_NAME/.ssh
COPY .ssh/config /home/$USER_NAME/.ssh/config

# setup z
RUN git clone --recursive $Z_GIT /home/$USER_NAME/z

# setup cheat.sh
RUN curl https://cht.sh/:cht.sh > /home/$USER_NAME/bin/cht.sh
RUN chmod 750 /home/$USER_NAME/bin/cht.sh
RUN mkdir /home/$USER_NAME/.zsh.d
RUN curl https://cheat.sh/:zsh > /home/$USER_NAME/.zsh.d/_cht

# install pyenv
RUN curl https://pyenv.run | bash

# mkdir downloads directory for tools downloads
RUN mkdir /home/$USER_NAME/downloads

# install powershell
RUN wget -O /home/$USER_NAME/downloads/packages-microsoft-prod.deb http://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb
RUN sudo dpkg -i /home/$USER_NAME/downloads/packages-microsoft-prod.deb
RUN sudo apt update
RUN sudo add-apt-repository universe
RUN sudo apt install powershell -y

# install go
RUN sudo add-apt-repository ppa:longsleep/golang-backports -y
RUN sudo apt update
RUN sudo apt install golang-$GO_VER-go -y

# install awscli
RUN mkdir /home/$USER_NAME/downloads/awscli
RUN wget -O /home/$USER_NAME/downloads/awscli/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
RUN unzip /home/$USER_NAME/downloads/awscli/awscliv2.zip -d /home/$USER_NAME/downloads/awscli
RUN sudo /home/$USER_NAME/downloads/awscli/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin

# install azure-cli
RUN curl -sL http://packages.microsoft.com/keys/microsoft.asc | \
  gpg --dearmor | \
  sudo tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg > /dev/null
RUN sudo add-apt-repository "deb [arch=amd64] http://packages.microsoft.com/repos/azure-cli/ focal main"
RUN sudo apt update
RUN sudo apt install azure-cli -y

# install gcloud-sdk
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
RUN curl http://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
RUN sudo apt update
RUN sudo apt install google-cloud-sdk -y
RUN sudo apt install google-cloud-sdk-app-engine-python -y
RUN sudo apt install google-cloud-sdk-app-engine-python-extras -y
RUN sudo apt install google-cloud-sdk-app-engine-go -y

# install kubernetes tools
# helm
RUN wget -O /home/$USER_NAME/downloads/helm-v$HELM_VER-linux-amd64.tar.gz https://get.helm.sh/helm-v$HELM_VER-linux-amd64.tar.gz
RUN mkdir /home/$USER_NAME/downloads/helm-v$HELM_VER
RUN tar zxvf /home/$USER_NAME/downloads/helm-v$HELM_VER-linux-amd64.tar.gz -C /home/$USER_NAME/downloads/helm-v$HELM_VER
RUN sudo cp -a /home/$USER_NAME/downloads/helm-v$HELM_VER/linux-amd64/helm /usr/local/bin/helm
#kubectl
RUN wget -O /home/$USER_NAME/downloads/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
RUN sudo cp -a /home/$USER_NAME/downloads/kubectl /usr/local/bin/kubectl
RUN sudo chmod 755 /usr/local/bin/kubectl

# install hashicorp terraform
RUN git clone --recursive https://github.com/tfutils/tfenv.git /home/$USER_NAME/.tfenv
RUN sudo ln -s ${HOME}/.tfenv/bin/tfenv /usr/local/bin/tfenv
# RUN sudo tfenv install $TERRAFORM_VER
# RUN sudo tfenv use $TERRAFORM_VER
