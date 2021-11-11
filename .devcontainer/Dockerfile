# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.158.0/containers/ubuntu/.devcontainer/base.Dockerfile

# [Choice] Ubuntu version: bionic, focal
ARG VARIANT="focal"
# hadolint ignore=DL3008,DL3013,DL3016,DL3028
FROM mcr.microsoft.com/vscode/devcontainers/base:0-${VARIANT}

# Options for setup script
ARG INSTALL_ZSH="true"
ARG UPGRADE_PACKAGES="true"
ARG Z_GIT="https://github.com/rupa/z.git"
ARG GO_VER="1.17"
ARG HELM_VER="3.7.0"
ARG HASHICORP_URL="https://releases.hashicorp.com"
ARG TERRAFORM_VER="1.0.9"
ARG YQ_VER="4.12.2"
ARG YQ_URL="https://github.com/mikefarah/yq/releases/download/v${YQ_VER}/yq_linux_amd64"

ARG USER_NAME="vscode"

# upgrade all packages
RUN apt-get update && apt-get upgrade -y \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Install package software-properties-common to get add-apt-repository
RUN apt-get update && apt-get install --no-install-recommends software-properties-common -y \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Install newer version of git
RUN add-apt-repository ppa:git-core/ppa && apt-get update && apt-get install --no-install-recommends git -y \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Install common packages
RUN apt-get update && apt-get install --no-install-recommends -y \
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
  libarchive-tools \
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
  mc \
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
  ruby-full \
  screen \
  shellcheck \
  silversearcher-ag \
  smartmontools \
  snapd \
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
  zsh-doc \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Setup and install of oh-my-zsh
USER ${USER_NAME}
ENV TERM xterm
ENV ZSH_THEME powerlevel10k/powerlevel10k
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN wget -q https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh || true \
  && git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /home/${USER_NAME}/.oh-my-zsh/custom/themes/powerlevel10k
COPY .zshrc /home/${USER_NAME}/.zshrc
COPY .p10k.zsh /home/${USER_NAME}/.p10k.zsh

# Copy app rc files
COPY .vimrc /home/${USER_NAME}/.vimrc
COPY .gitconfig_linux /home/${USER_NAME}/.gitconfig
COPY .tmux.conf /home/${USER_NAME}/.tmux.conf

# mkdir some things
RUN mkdir /home/${USER_NAME}/bin \
  && mkdir /home/${USER_NAME}/scripts \
  && mkdir /home/${USER_NAME}/.aws \
  && chmod 700 /home/${USER_NAME}/.aws \
  && mkdir /home/${USER_NAME}/.ssh \
  && chmod 700 /home/${USER_NAME}/.ssh
COPY .ssh/config /home/${USER_NAME}/.ssh/config

# install homebrew
RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"

# setup z
RUN git clone --recursive ${Z_GIT} /home/${USER_NAME}/z

# setup cheat.sh
RUN curl https://cht.sh/:cht.sh > /home/${USER_NAME}/bin/cht.sh \
  && chmod 750 /home/${USER_NAME}/bin/cht.sh \
  && mkdir /home/${USER_NAME}/.zsh.d \
  && curl https://cheat.sh/:zsh > /home/${USER_NAME}/.zsh.d/_cht

# install pyenv
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl https://pyenv.run | bash

# mkdir downloads directory for tools downloads
RUN mkdir /home/${USER_NAME}/downloads

# install powershell
RUN wget -q -O /home/${USER_NAME}/downloads/packages-microsoft-prod.deb http://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb \
  && sudo dpkg -i /home/${USER_NAME}/downloads/packages-microsoft-prod.deb \
  && sudo apt-get update \
  && sudo add-apt-repository universe \
  && sudo apt-get install --no-install-recommends powershell -y \
  && sudo apt-get clean \
  && sudo rm -rf /var/lib/apt/lists/*

# install go
RUN sudo add-apt-repository ppa:longsleep/golang-backports -y \
  && sudo apt-get update \
  && sudo apt-get install --no-install-recommends golang-${GO_VER}-go -y \
  && sudo apt-get clean \
  && sudo rm -rf /var/lib/apt/lists/*

# install awscli
RUN mkdir /home/${USER_NAME}/downloads/awscli \
  && wget -q -O /home/${USER_NAME}/downloads/awscli/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
  && unzip /home/${USER_NAME}/downloads/awscli/awscliv2.zip -d /home/${USER_NAME}/downloads/awscli \
  && sudo /home/${USER_NAME}/downloads/awscli/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin \
  && rm -rf /home/${USER_NAME}/downloads/awscli

# install azure-cli
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -sL http://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg > /dev/null \
  && sudo add-apt-repository "deb [arch=amd64] http://packages.microsoft.com/repos/azure-cli/ focal main" \
  && sudo apt-get update \
  && sudo apt-get install --no-install-recommends azure-cli -y \
  && sudo apt-get clean \
  && sudo rm -rf /var/lib/apt/lists/*

# install gcloud-sdk
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
  && curl http://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - \
  && sudo apt-get update \
  && sudo apt-get install --no-install-recommends google-cloud-sdk -y \
  && sudo apt-get install --no-install-recommends google-cloud-sdk-app-engine-python -y \
  && sudo apt-get install --no-install-recommends google-cloud-sdk-app-engine-python-extras -y \
  && sudo apt-get install --no-install-recommends google-cloud-sdk-app-engine-go -y \
  && sudo apt-get clean \
  && sudo rm -rf /var/lib/apt/lists/*

# install kubernetes tools
# helm
RUN wget -q -O /home/${USER_NAME}/downloads/helm-v${HELM_VER}-linux-amd64.tar.gz https://get.helm.sh/helm-v${HELM_VER}-linux-amd64.tar.gz \
  && mkdir /home/${USER_NAME}/downloads/helm-v${HELM_VER} \
  && tar zxvf /home/${USER_NAME}/downloads/helm-v${HELM_VER}-linux-amd64.tar.gz -C /home/${USER_NAME}/downloads/helm-v${HELM_VER} \
  && sudo cp -a /home/${USER_NAME}/downloads/helm-v${HELM_VER}/linux-amd64/helm /usr/local/bin/helm
#kubectl
RUN wget -q -O /home/${USER_NAME}/downloads/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
  && sudo cp -a /home/${USER_NAME}/downloads/kubectl /usr/local/bin/kubectl \
  && chmod 755 /usr/local/bin/kubectl \
  && sudo chown root:root /usr/local/bin/kubectl

# install hashicorp terraform
RUN wget -q -O /home/${USER_NAME}/downloads/terraform_${TERRAFORM_VER}_linux_amd64.zip ${HASHICORP_URL}/terraform/${TERRAFORM_VER}/terraform_${TERRAFORM_VER}_linux_amd64.zip \
  && unzip /home/${USER_NAME}/downloads/terraform_${TERRAFORM_VER}_linux_amd64.zip -d /home/${USER_NAME}/downloads/terraform_${TERRAFORM_VER} \
  && sudo cp -a /home/${USER_NAME}/downloads/terraform_${TERRAFORM_VER}/terraform /usr/local/bin/ \
  && chmod 755 /usr/local/bin/terraform \
  && sudo chown root:root /usr/local/bin/terraform

# install yq
RUN wget -q -O ${HOME}/downloads/yq_${YQ_VER} ${YQ_URL} \
  && sudo cp -a ${HOME}/downloads/yq_${YQ_VER} /usr/local/bin/ \
  && sudo mv /usr/local/bin/yq_${YQ_VER} /usr/local/bin/yq \
  && chmod 755 /usr/local/bin/yq \
  && sudo chown root:root /usr/local/bin/yq

# install npm json2yaml
RUN sudo npm install json2yaml

# setup for test-kitchen
RUN sudo gem install test-kitchen \
  && sudo gem install kitchen-ansible \
  && sudo gem install kitchen-docker \
# && sudo gem install kitchen-inspec \
  && sudo gem install kitchen-terraform \
  && sudo gem install kitchen-verifier-serverspec \
  && sudo gem install bundle

# install of ansible and other required pip packages
RUN python3 -m pip install --no-cache-dir ansible ansible-cmdb ansible-lint pylint jmespath-terminal psutil \
# cleanup tmp
  && rm -rf /tmp/* /var/tmp/*
