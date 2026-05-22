#!/usr/bin/env bash
# lib/constants.sh — version pins, download URLs, directory locations

# software versions to install
BATS_VER="1.11.0"
GITLEAKS_VER="8.21.2"
CF_TERRAFORMING_VER="0.16.1"
CHRUBY_VER="0.3.9"
CONSUL_VER="1.16.0"
DOCKER_COMPOSE_VER="v2.20.2"
GIT_VER="2.53.0"
GO_VER="1.26"
# following go vars are for linux where go version is >= 1.21
GO_DOWNLOAD_FILENAME="go1.26.1.linux-amd64.tar.gz"
GO_DOWNLOAD_URL="https://go.dev/dl/${GO_DOWNLOAD_FILENAME}"
KIND_VER="0.31.0"
NOMAD_VER="1.6.1"
PACKER_VER="1.15.1"
PYTHON_VER="3.14.3"
RUBY_INSTALL_VER="0.9.1"
RUBY_VER="4.0.2"
SHELLCHECK_VER="0.11.0"
TERRAFORM_VER="1.3.5"
TFLINT_VER="0.61.0"
TFSEC_VER="1.28.4"
VAGRANT_VER="2.4.9"
VAULT_VER="1.14.1"
VIRTUALBOX_VER="virtualbox-7.0"
YQ_VER="4.52.5"
ZSH_VER="5.10"
KUBERNETES_VER="v1.35"

CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v${CF_TERRAFORMING_VER}/cf-terraforming_${CF_TERRAFORMING_VER}_linux_amd64.tar.gz"
GIT_URL="https://mirrors.edge.kernel.org/pub/software/scm/git"
DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VER}/docker-compose-$(uname -s)-$(uname -m)"
HASHICORP_URL="https://releases.hashicorp.com"
KIND_URL="https://kind.sigs.k8s.io/dl/v${KIND_VER}/kind-linux-amd64"
TELEPRESENCE_URL="https://app.getambassador.io/download/tel2/linux/amd64/latest/telepresence"
TFLINT_URL="https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VER}/tflint_linux_amd64.zip"
TFSEC_URL="https://github.com/liamg/tfsec/releases/download/v${TFSEC_VER}/tfsec-linux-amd64"
YQ_URL="https://github.com/mikefarah/yq/releases/download/v${YQ_VER}/yq_linux_amd64"

# locations of directories
BREWFILE_LOC="${HOME}/brew"
DOTFILES="dotfiles"
GITREPOS="${HOME}/git-repos"
PERSONAL_GITREPOS="${GITREPOS}/personal"
readonly AI_CONFIG="ai-config"
readonly AI_CONFIG_DIR="${PERSONAL_GITREPOS}/${AI_CONFIG}"
WSL_HOME="/mnt/c/Users/${USER}"

HOSTNAME=$(hostname -s)
