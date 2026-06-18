#!/usr/bin/env bash
# lib/constants.sh — version pins, download URLs, directory locations

# software versions to install
BATS_VER="1.13.0"
GITLEAKS_VER="8.30.1"
CF_TERRAFORMING_VER="0.27.0"
CHRUBY_VER="0.3.9"
CONSUL_VER="2.0.0"
DOCKER_COMPOSE_VER="v5.1.4"
GIT_VER="2.54.0"
GO_VER="1.26"
# Linux architecture: kernel names (x86_64/aarch64) → Debian/GitHub names (amd64/arm64)
_LINUX_ARCH="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
GO_DOWNLOAD_FILENAME="go1.26.4.linux-${_LINUX_ARCH}.tar.gz"
GO_DOWNLOAD_URL="https://go.dev/dl/${GO_DOWNLOAD_FILENAME}"
KIND_VER="0.32.0"
NOMAD_VER="2.0.3"
PACKER_VER="1.15.4"
PYTHON_VER="3.14.6"
RUBY_INSTALL_VER="0.10.2"
RUBY_VER="4.0.5"
SHELLCHECK_VER="0.11.0"
TERRAFORM_VER="1.15.6"
TFLINT_VER="0.63.1"
TFSEC_VER="1.28.14"
VAGRANT_VER="2.4.9"
VAULT_VER="2.0.2"
VIRTUALBOX_VER="virtualbox-7.1"
YQ_VER="4.53.3"
ZSH_VER="5.10"
KUBERNETES_VER="v1.36"

CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v${CF_TERRAFORMING_VER}/cf-terraforming_${CF_TERRAFORMING_VER}_linux_${_LINUX_ARCH}.tar.gz"
GIT_URL="https://mirrors.edge.kernel.org/pub/software/scm/git"
DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VER}/docker-compose-$(uname -s)-$(uname -m)"
HASHICORP_URL="https://releases.hashicorp.com"
KIND_URL="https://kind.sigs.k8s.io/dl/v${KIND_VER}/kind-linux-${_LINUX_ARCH}"
TELEPRESENCE_URL="https://app.getambassador.io/download/tel2/linux/${_LINUX_ARCH}/latest/telepresence"
TFLINT_URL="https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VER}/tflint_linux_${_LINUX_ARCH}.zip"
TFSEC_URL="https://github.com/liamg/tfsec/releases/download/v${TFSEC_VER}/tfsec-linux-${_LINUX_ARCH}"
YQ_URL="https://github.com/mikefarah/yq/releases/download/v${YQ_VER}/yq_linux_${_LINUX_ARCH}"

# locations of directories
BREWFILE_LOC="${HOME}/brew"
DOTFILES="dotfiles"
GITREPOS="${HOME}/git-repos"
PERSONAL_GITREPOS="${GITREPOS}/personal"
readonly AI_CONFIG="ai-config"
readonly AI_CONFIG_DIR="${PERSONAL_GITREPOS}/${AI_CONFIG}"
WSL_HOME="/mnt/c/Users/${USER}"

HOSTNAME=$(hostname -s)
