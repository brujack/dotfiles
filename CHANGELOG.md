# Changelog


## Bug Fixes

- Ubuntu 26.04 housekeeping — HAS_FLATPAK, VirtualBox 7.1, dead OS vars (#147)

- add gitguardian/tap to install_macos_casks brew trust (#148)

- migrate restart_fah from init.d to systemctl (#150)

- suppress dependency prompt with NONINTERACTIVE=1 (#151)

- add molecule and molecule-plugins[docker] to ansible venv (#152)

- rbenv init on Linux never ran due to chruby guard (#153)

- Ubuntu 26.04 compatibility — ruby-build, Python build deps, helm/cloudflare/azure-cli APT repos (#154)

- Ubuntu 26.04 setup — nala comment filter, helm script, dotnet non-fatal (#155)

- refresh ruby-build defs from git for Ubuntu 26.04 (#156)

- purge stale helm/azure-cli sources.list.d on Ubuntu 26.04 (#157)

- drop rbenv local — silently overwrites project .ruby-version on every shell start (#158)

- add DEBIAN_FRONTEND=noninteractive to all nala/apt installs (#159)

- pass --yes to brew upgrade to skip Homebrew 6.0 prompt (#160)

- run _install_ubuntu_rust after brew so rustup is available to configure (#163)

- mkdir custom/themes after oh-my-zsh git clone (#164)

- symlink pyenv into PYENV_ROOT/bin when installed via brew

- remove duplicate powershell.md @-include



## Documentation

- mark ubuntu-2604-pr4 Done, update test count to 765

- mark ubuntu-2604-pr5 Done after PR #147

- add HAS_FLATPAK to capability table

- update test count 769 → 772, mark ubuntu-2604-p3 Done after PR #149

- mark P3-6 resolved — restart_fah SysV init fixed in PR #150

- add pip-venv-audit backlog item

- add pip-venv-audit spec

- add ansible venv pkg list and ruff venv note

- move pip-venv-audit to All Plans (In Progress)

- add pip-venv-audit implementation plan

- mark pip-venv-audit Done

- bump test count floor 729→779, update BATS count to 782

- add env -i pyenv mock pattern and ubuntu26 noble fallback note

- ADR-0013, plan status Done, 806 test count after PR #162

- add Claude Code weekly features digest 2026-06-22

- add Anthropic weekly features digest 2026-06-22

- update Anthropic platform state 2026-06-22

- add bug-scan to Phase 3 chain

- bump test count floor to 806, note 810 tests as of 2026-06-25



## Features

- add ruff, pytest, mypy, data science stack

- add OpenTofu install for macOS and Ubuntu (#161)

- replace curl|bash installs with brew/apt/SHA-pin (#162)

- dotfiles adds powershell.md language standard



## Testing

- fix opentofu tests failing when tofu installed on macOS


