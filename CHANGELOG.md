# Changelog


## Bug Fixes

- add missing existence check for validate_memory.py fallback path (#132)

- guard mlx pip install behind macOS check (#135)

- brew trust, pip dep pins, Brewfile drift (#136)

- remove docker formula and dotnet cask aliases (#137)

- add docker formula, remove kitchen (#138)

- remove docker formula and powershell cask duplicates (#139)

- remove chef tap and trust reference (#140)

- fix 6 Ubuntu Noble setup failures + move Steam to Flatpak (#141)

- apt-get for base packages, sudo for flatpak Steam (#142)

- remove libncurses5-dev/libncursesw5-dev from common packages

- cgroup v2 daemon.json, glances via apt, passlib for Python 3.13 (#144)

- nala, ruby, Go PPA cleanup for Ubuntu 26.04 (#145)

- Ubuntu 26.04 housekeeping — HAS_FLATPAK, VirtualBox 7.1, dead OS vars (#147)

- add gitguardian/tap to install_macos_casks brew trust (#148)

- migrate restart_fah from init.d to systemctl (#150)

- suppress dependency prompt with NONINTERACTIVE=1 (#151)

- add molecule and molecule-plugins[docker] to ansible venv (#152)

- rbenv init on Linux never ran due to chruby guard (#153)



## Documentation

- pointer stub per ADR-0020 (#134)

- add Claude Code weekly features digest 2026-06-15

- add Anthropic weekly features digest 2026-06-15

- sync CLAUDE.md with recent changes

- sync CLAUDE.md and plan index after PR #138

- document formula/cask dedup rule and fix docker example

- add Ubuntu 26.04 Resolute Raccoon support spec

- add PR1 Ubuntu 26.04 detection and package files spec

- add Ubuntu 26.04 PR1 implementation plan

- mark ubuntu-2604-pr1 Done after PR #143

- sync CLAUDE.md and README for Ubuntu 26.04 support

- add PR2 Ubuntu 26.04 Docker cgroup v2 and Python 3.13 spec

- add Ubuntu 26.04 PR2 implementation plan

- mark ubuntu-2604-pr2 Done after PR #144

- update test count 749 → 753

- document brew upgrade node plugin fix for Linux

- mark ubuntu-2604-pr3 Done after PR #145

- update test count 753 → 759

- ubuntu-2604-pr4 — ARM64 support + version bumps

- ubuntu-2604-pr4 ARM64 support + version bumps

- mark ubuntu-2604-pr4 Done, update test count to 765

- mark ubuntu-2604-pr5 Done after PR #147

- add HAS_FLATPAK to capability table

- update test count 769 → 772, mark ubuntu-2604-p3 Done after PR #149

- mark P3-6 resolved — restart_fah SysV init fixed in PR #150



## Features

- Ubuntu 26.04 Resolute Raccoon detection and package files (#143)

- track and symlink .gitignore_global via dotfiles

- ARM64 support + version bumps (PR4) (#146)



## Testing

- tighten rbenv install assertion to match version-specific call


