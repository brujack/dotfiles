#!/usr/bin/env bash
# scripts/bootstrap_linux.sh
# Run once on a fresh Linux machine before setup_env.sh.
# Installs Homebrew prerequisites and Homebrew.

set -e

if [[ $(uname -s) != "Linux" ]]; then
  printf "[ERROR] This script is Linux only.\n" >&2
  exit 1
fi

if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091 # /etc/os-release is standard on Linux
  . /etc/os-release
fi

if [[ "${ID:-}" == "ubuntu" ]] || [[ "${ID_LIKE:-}" == *"ubuntu"* ]]; then
  printf "[INFO]  Installing Homebrew prerequisites (Ubuntu)...\n"
  sudo apt-get update
  sudo apt-get install -y build-essential curl file git procps
elif [[ "${ID:-}" == "fedora" ]] || [[ "${ID_LIKE:-}" == *"fedora"* ]]; then
  printf "[INFO]  Installing Homebrew prerequisites (Fedora)...\n"
  sudo dnf groupinstall -y "Development Tools"
  sudo dnf install -y curl file git procps-ng
elif [[ "${ID:-}" == "centos" ]] || [[ "${ID_LIKE:-}" == *"rhel"* ]] || [[ "${ID:-}" == "rhel" ]]; then
  printf "[INFO]  Installing Homebrew prerequisites (RHEL/CentOS)...\n"
  sudo yum groupinstall -y "Development Tools"
  sudo yum install -y curl file git procps-ng
else
  printf "[WARN]  Unknown distro. Ensure Homebrew prerequisites are installed: build tools, curl, file, git, procps.\n"
fi

if ! command -v brew &>/dev/null; then
  printf "[INFO]  Installing Homebrew...\n"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  printf "[INFO]  Homebrew already installed.\n"
fi

# Ensure brew is in PATH for this shell
if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

printf "[INFO]  Bootstrap complete. You can now run: ./setup_env.sh -t <type>\n"
