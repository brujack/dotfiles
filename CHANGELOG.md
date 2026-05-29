# Changelog


## Bug Fixes

- fix choco prefix-match bug; clean early-learning patterns (#86)

- skip nextest update when rustup not found

- tag mas as HAS_PRINTING to suppress Linux brew-drift false positive (#92)

- store 20KB state snapshots and cap claude -p prompt

- truncate current content before diff to match 20KB state window (#93)



## CI

- remove bash-coverage from auto-merge gate (#87)

- add bash and PowerShell coverage badges (#88)



## Documentation

- ADR-0007 — Codify branch protection via script

- update ADR-0007 — required_signatures removed

- add Anthropic weekly features digest 2026-05-25

- add Claude Code weekly features digest 2026-05-25

- remove RHEL/dnf/yum references after distro cleanup

- add missing Brewfile variants, docs/ subdirs, gitconfig_windows

- add getting started guide and fix Windows setup section

- move coverage-brewfile-helpers to Done, add backlog items

- update BATS test count to 590

- update test count to 602 and mark coverage-run-update-optional-tools Done

- update test count to 609 and mark coverage-run-update-sections Done

- update test count to 614 and mark coverage-install-terraform-skill Done

- update test count to 616, mark coverage-setup-env-direct-run Done, clear backlog

- document setup_env prereq bypass test assertion pattern

- note count assertion caveat for section removal

- mark coverage-workflows-setup-chains Done

- mark coverage-update-summary-gaps Done

- update bash coverage to 85% (2026-05-28, 662 tests)



## Features

- add Renovate dependency updates

- add git-cliff config and make target (#91)

- enable brew-drift check on Linux

- add memory and CPU to right prompt

- add bash coverage measurement via PS4 xtrace tracer



## Refactoring

- remove RHEL, CentOS, and Fedora support (#89)

- drop Ubuntu 18.04/20.04/22.04 support (#90)

- remove Elementary OS support

- remove powerlevel10k support (#99)



## Testing

- add brewfile helper function tests (#94)

- add run_update optional-tools installed-path tests (#95)

- add run_update claude/npm/pip section tests (#96)

- add install_terraform_skill tests (#97)

- add setup_env.sh -t doctor/-t check-versions bypass tests (#98)

- cover preamble bash-version and brew error paths (#100)

- cover update_rust branches and clone_personal_repos (#101)

- cover setup_dotfile_symlinks and credential dirs (#102)

- cover run_update single-flag isolation (#103)

- cover setup_claude_plugins branches and run_setup_user chain (#104)

- cover npm, tpm/tfenv/zsh-autosuggestions, default case (#105)

- coverage for _check_one_version and run_check_versions (#106)

