#!/bin/bash
# scripts/bootstrap_mac.sh
# Run once on a fresh Mac before setup_env.sh.
# Installs Homebrew and bash 5 — the only two prerequisites for setup_env.sh.

set -e

if [[ $(uname -s) != "Darwin" ]]; then
  printf "[ERROR] This script is macOS only.\n" >&2
  exit 1
fi

# Install Homebrew if missing
if ! command -v brew &>/dev/null; then
  printf "[INFO]  Installing Homebrew...\n"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  printf "[INFO]  Homebrew already installed.\n"
fi

# Ensure brew is on PATH (Apple Silicon path)
if [[ -f /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Install bash 5 if missing or version < 5
BASH_VER=$(brew list --versions bash 2>/dev/null | awk '{print $2}' | cut -d. -f1)
if [[ "${BASH_VER:-0}" -lt 5 ]]; then
  printf "[INFO]  Installing bash 5...\n"
  brew install bash
else
  printf "[INFO]  bash 5 already installed.\n"
fi

printf "[INFO]  Bootstrap complete. You can now run: ./setup_env.sh -t <type>\n"
