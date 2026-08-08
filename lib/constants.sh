#!/usr/bin/env bash
# shellcheck disable=SC2034 # file-wide: every constant here is read by other lib/*.sh files via `source`
# This is a version-pin/URL/directory-location file, so the linter cannot
# see the cross-file `source` usage above (a directive placed before the
# first real command in a file applies file-wide, per the linter's own
# scoping rules — verified empirically rather than assumed, since a
# per-line directive here would otherwise silently do nothing). Genuinely
# dead pins (no consumer found via `git grep -w <VAR>` across the whole
# repo) were deleted rather than suppressed — see git history for
# CHRUBY_VER, GIT_VER, GIT_URL, TFLINT_VER, TFLINT_URL, TFSEC_VER,
# TFSEC_URL, WSL_HOME. Each remaining constant's real consumer is noted
# below for readability.
# lib/constants.sh — version pins, download URLs, directory locations

# software versions to install
# read by tests/helpers/common.bash:load_setup_env (exported for mocks) and tests/setup_env/unit.bats
BATS_VER="1.13.0"
# read by lib/workflows.sh:run_check_versions (_run_cv_check)
GITLEAKS_VER="8.30.1"
CF_TERRAFORMING_VER="0.27.0"
# read by lib/linux_ubuntu.sh:_install_ubuntu_hashicorp
CONSUL_VER="2.0.0"
DOCKER_COMPOSE_VER="v5.1.4"
# npm global packages — pinned by exact version at both lib/workflows.sh call sites.
# Unlike the GitHub-release pins above, these are NOT covered by
# `./setup_env.sh -t check-versions`: only jscpd publishes GitHub releases matching
# its npm version. See docs/superpowers/plans/2026-07-29-npm-global-pinning.md.
# read by lib/workflows.sh:_require_npm_pins and run_developer_or_ansible
EXA_MCP_SERVER_VER="3.2.1"
# read by lib/workflows.sh:_require_npm_pins and run_developer_or_ansible
FIRECRAWL_CLI_VER="1.19.27"
# read by lib/workflows.sh:_require_npm_pins and run_developer_or_ansible
JSCPD_VER="5.0.14"
# read by lib/workflows.sh:_require_npm_pins and run_developer_or_ansible
JSON2YAML_VER="1.1.0"
# read by lib/linux_ubuntu.sh:_install_ubuntu_go, lib/helpers.sh:_doctor_check_versions, lib/workflows.sh:run_check_versions
GO_VER="1.26"
# Linux architecture: kernel names (x86_64/aarch64) → Debian/GitHub names (amd64/arm64)
_LINUX_ARCH="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
GO_DOWNLOAD_FILENAME="go1.26.4.linux-${_LINUX_ARCH}.tar.gz"
# read by lib/linux_ubuntu.sh:_install_ubuntu_go
GO_DOWNLOAD_URL="https://go.dev/dl/${GO_DOWNLOAD_FILENAME}"
KIND_VER="0.32.0"
# read by lib/linux_ubuntu.sh:_install_ubuntu_hashicorp
NOMAD_VER="2.0.3"
# read by lib/linux_ubuntu.sh:_install_ubuntu_hashicorp
PACKER_VER="1.15.4"
# read by lib/developer.sh:setup_ansible, lib/helpers.sh:_doctor_check_versions, lib/workflows.sh:run_check_versions
PYTHON_VER="3.14.6"
# read by lib/developer.sh:install_ruby_tools
RUBY_INSTALL_VER="0.10.2"
# read by lib/developer.sh:install_ruby, lib/helpers.sh:_doctor_check_versions, lib/workflows.sh:run_check_versions, .config/.zshrc.d/5_general.zsh
RUBY_VER="4.0.5"
# read by lib/workflows.sh:run_check_versions
SHELLCHECK_VER="0.11.0"
# read by tests/setup_env/unit.bats semver check (terraform installs via package manager, no lib/ consumer)
TERRAFORM_VER="1.15.6"
# read by lib/linux_ubuntu.sh:_install_ubuntu_hashicorp, lib/workflows.sh:run_check_versions
VAGRANT_VER="2.4.9"
# read by lib/linux_ubuntu.sh:_install_ubuntu_hashicorp
VAULT_VER="2.0.2"
# read by lib/linux_ubuntu.sh:_install_ubuntu_gui_tools
VIRTUALBOX_VER="virtualbox-7.1"
YQ_VER="4.53.3"
# read by lib/helpers.sh:_doctor_check_versions, lib/workflows.sh:run_check_versions
ZSH_VER="5.10"
# read by lib/linux_ubuntu.sh:_install_ubuntu_k8s_tools
KUBERNETES_VER="v1.36"

# read by lib/linux_ubuntu.sh:_install_ubuntu_cloud_tools
CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v${CF_TERRAFORMING_VER}/cf-terraforming_${CF_TERRAFORMING_VER}_linux_${_LINUX_ARCH}.tar.gz"
# read by lib/linux_ubuntu.sh:_install_ubuntu_misc
DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VER}/docker-compose-$(uname -s)-$(uname -m)"
# read by lib/linux_ubuntu.sh:_install_ubuntu_hashicorp
HASHICORP_URL="https://releases.hashicorp.com"
# read by lib/linux_ubuntu.sh:_install_ubuntu_k8s_tools
KIND_URL="https://kind.sigs.k8s.io/dl/v${KIND_VER}/kind-linux-${_LINUX_ARCH}"
# read by lib/linux_ubuntu.sh:_install_ubuntu_k8s_tools
TELEPRESENCE_URL="https://app.getambassador.io/download/tel2/linux/${_LINUX_ARCH}/latest/telepresence"
# read by lib/linux_ubuntu.sh:_install_ubuntu_misc
YQ_URL="https://github.com/mikefarah/yq/releases/download/v${YQ_VER}/yq_linux_${_LINUX_ARCH}"

# locations of directories
# read by lib/macos.sh:install_macos_casks/install_macos_packages, lib/workflows.sh:run_brew_install, lib/helpers.sh:run_doctor
BREWFILE_LOC="${HOME}/brew"
# read throughout lib/helpers.sh (setup_dotfile_symlinks), lib/macos.sh, lib/workflows.sh, lib/developer.sh, lib/update_summary.sh — always paired with PERSONAL_GITREPOS
DOTFILES="dotfiles"
GITREPOS="${HOME}/git-repos"
PERSONAL_GITREPOS="${GITREPOS}/personal"
readonly AI_CONFIG="ai-config"
# read by lib/helpers.sh:setup_dotfile_symlinks and lib/workflows.sh:setup_claude_mcp/setup_ai_config
readonly AI_CONFIG_DIR="${PERSONAL_GITREPOS}/${AI_CONFIG}"

HOSTNAME=$(hostname -s)

# oh-my-zsh bootstrap branch — no tagged releases; master is the distribution branch
# update check: ./setup_env.sh -t check-versions --update
# read by lib/helpers.sh:setup_dotfile_symlinks and lib/workflows.sh:_check_cv_oh_my_zsh
OH_MY_ZSH_VER="master"

# Homebrew install script commit SHA — content-addressable; avoids HEAD which can change
# update check: ./setup_env.sh -t check-versions --update
# read by lib/macos.sh:install_homebrew, lib/workflows.sh:_check_cv_homebrew_install, scripts/bootstrap_linux.sh, scripts/bootstrap_mac.sh
HOMEBREW_INSTALL_SHA="5e78e698e405a17b63b5fe41ff747f9fccf39472"
