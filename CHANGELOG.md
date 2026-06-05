# Changelog


## Bug Fixes

- remove stCommitMsg commit template reference

- wire gitlab includeIf, drop stale commit template and needrestart

- guard readonly vars against re-source crash

- fix RUBY_VER, guard pyenv ansible, drop redundant plugin clone

- export -f install_homebrew stub for subshell visibility (#111)



## CI

- replace kcov gate with macOS xtrace gate at 90% (#116)



## Documentation

- update test count to 674, mark coverage-workflows-gaps Done

- mark coverage-update-summary-casks Done

- add spec for helpers.sh gaps-2 coverage

- add plan for coverage-helpers-gaps-2

- update test count to 693, mark coverage-helpers-gaps-2 Done

- document load_setup_env OS detection side effect

- update bash coverage to 90% (2026-05-30, 693 tests)

- clear stale backlog entry (coverage-helpers-gaps-2 done)

- add coverage-per-file-gaps plan (In Progress)

- mark coverage-per-file-gaps Done, 705 tests

- add doctor test conventions section

- add per-file gap backlog and ceiling notes

- update test count to 709, mark coverage-macos-install-errors Done

- update test count to 714, mark coverage-helpers-doctor-error-paths Done

- mark coverage-helpers-setup-functions Done, 716 tests

- mark coverage-workflows-pip-update Done, 718 tests

- add Claude Code weekly features digest 2026-06-01

- add Anthropic weekly features digest 2026-06-01

- mark coverage-workflows-minor-paths Done, 720 tests

- update BATS test count to 723 after PR #117

- mark coverage-more-tests Done, 723 tests

- mark coverage-gap-tests Done, 726 tests

- add ADR-0008 for PS4 xtrace bash coverage approach

- add ADR-0009 and ADR-0010 for recent decisions

- add ADR-0011 and ADR-0012 for April decisions

- replace Powerlevel10k with Starship in README

- update BATS test count to 729 after PR #119

- document run_update pip hang pattern in Testing Rules

- remove DoD section (all items covered by global behavior.md)



## Features

- capture stderr per-section for richer failure output (#119)



## Testing

- raise update_summary.sh coverage from 82% to 97% (#107)

- raise helpers.sh coverage from 83% to ≥90% (#108)

- per-file coverage gaps — helpers.sh and workflows.sh (#109)

- cover xcodebuild-fail, no-brew error paths (#110)

- cover doctor/process_args error paths (#112)

- cover OMZ-installed and Cursor-not-installed paths (#113)

- cover run_update pip block, 718 tests (#114)

- cover _check_one_version and _run_cv_check arg behavior, 720 tests (#115)

- add 3 tests targeting uncovered branches in linux_ubuntu/developer (#117)

- cover 3 behavioral gaps in helpers/linux_ubuntu (#118)


