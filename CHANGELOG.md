# Changelog


## Bug Fixes

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

- build Ruby against system OpenSSL, not linuxbrew's pkg-config openssl@3 (fixes gem HTTPS "OpenSSL is not available")



## Documentation

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

- update test count to 834 after state-ledger-integration PR #166

- state-ledger integration — ADR-0014, test count 840, plan index

- update CLAUDE.md — ledger wiring for all run_* functions, 848 tests

- add PR #168 to superpowers plan index

- add Claude Code weekly features digest 2026-06-29

- add Anthropic weekly features digest 2026-06-29 (#169)

- compact CLAUDE.md layout tree, drop 3 redundant rows

- remove Installation Guards duplicate of shell.md



## Features

- add ruff, pytest, mypy, data science stack

- add OpenTofu install for macOS and Ubuntu (#161)

- replace curl|bash installs with brew/apt/SHA-pin (#162)

- dotfiles adds powershell.md language standard

- add cargo-cyclonedx and cyclonedx-python (#165)

- add advisory skill scan after claude plugin update

- state-ledger CMDB integration (T5/T6/T7) (#166)

- wire state-ledger writes into dotfiles update (#167)

- wire state-ledger into setup/developer/recreate_venv runs (#168)



## Testing

- fix opentofu tests failing when tofu installed on macOS

- add systemctl mock so restart_fah.sh tests don't exec real systemctl on Linux


