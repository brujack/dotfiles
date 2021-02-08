# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.158.0/containers/ubuntu/.devcontainer/base.Dockerfile

# [Choice] Ubuntu version: bionic, focal
ARG VARIANT="focal"
FROM mcr.microsoft.com/vscode/devcontainers/base:0-${VARIANT}

# Options for setup script
ARG INSTALL_ZSH="true"
ARG UPGRADE_PACKAGES="true"
ARG Z_GIT="https://github.com/rupa/z.git"

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
