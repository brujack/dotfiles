# Changelog


## Bug Fixes

- export -f install_homebrew stub for subshell visibility (#111)

- use ruby-install gem path; trust Homebrew taps on Linux

- trust remaining third-party taps for Homebrew 6.0 (#121)

- guard setup_claude_mcp against symlinked mcp.json

- symlink ~/.claude/projects to ai-config instead of leaving unset (#122)

- prepend ruby-install bin to PATH so it takes precedence over system gem (#123)

- exa-mcp install, npm update, and GIT_DIR test isolation (#125)

- tolerate missing virtualenv in delete step (#127)



## CI

- replace kcov gate with macOS xtrace gate at 90% (#116)



## Documentation

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

- add 5 backlog items from 2026-06-05 retro

- update BATS test count 729 → 731 in CLAUDE.md

- note brew trust coupling when adding new taps

- add Claude Code weekly features digest 2026-06-08



## Features

- capture stderr per-section for richer failure output (#119)

- add -t recreate-venv to force-recreate a pyenv virtualenv (#124)

- add terraform-skill to plugin install and update lists



## Testing

- cover xcodebuild-fail, no-brew error paths (#110)

- cover doctor/process_args error paths (#112)

- cover OMZ-installed and Cursor-not-installed paths (#113)

- cover run_update pip block, 718 tests (#114)

- cover _check_one_version and _run_cv_check arg behavior, 720 tests (#115)

- add 3 tests targeting uncovered branches in linux_ubuntu/developer (#117)

- cover 3 behavioral gaps in helpers/linux_ubuntu (#118)

- isolate run_update --claude-only from real HOME (#126)


