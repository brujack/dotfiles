# Changelog


## Bug Fixes

- system OpenSSL for gem HTTPS + Linux test hermeticity (#171)

- detect silent install failure in recreate_ruby (#173)

- run gem update after ruby recreate (#174)

- harden ensure_state_ledger against SSH hangs and corrupt clones (#177)

- brace $0/$1/$2/$3 in sync-agent-guidance.sh (#179)

- scripts/ cleanup — kill_zombie multi-PID bug, mkill/html2ascii modernize (#183)

- remove dangling tw alias for deleted tmux-workstation.sh (#184)



## CI

- raise test count floor from 779 to 840 (#170)



## Documentation

- add July 2026 retro action items

- note load_mocks pyenv default; bump test count to 850

- add recreate-ruby design spec

- add recreate-ruby implementation plan

- mark recreate-ruby plan done, bump test count to 861

- sync test count and plan index for dotfiles#174

- add Anthropic weekly features digest 2026-07-06

- add Claude Code weekly features digest 2026-07-06

- add state-ledger bootstrap design spec

- add state-ledger bootstrap plan

- sync test count to 874 after PR #177

- fix stale sync-agent-guidance description in README

- add Claude Code weekly features digest 2026-07-13

- add Anthropic weekly features digest 2026-07-13

- ADR-0015 — continuous vulnerability monitoring of release SBOMs

- add sync-git-repos design spec

- fix sync-git-repos spec per review

- fix contradictory legacy-rsync gate wording

- fix sync-git-repos no-upstream + DRY hostname gate

- add sync-git-repos implementation plan

- mark sync-git-repos plan Done (PR dotfiles#182)

- add scripts-dir-cleanup design spec

- mark scripts-dir-cleanup Done (PR dotfiles#183)

- update stale test count 927 -> 937

- add scripts-world-class design spec

- mark scripts-world-class Done (PR dotfiles#185)

- add Anthropic weekly features digest 2026-07-20

- add Claude Code weekly features digest 2026-07-20



## Features

- add recreate-ruby entry point to setup_env.sh (#172)

- auto clone/pull state-ledger on setup/update runs (#176)

- implement sync-agent-guidance / check-agent-guidance targets (#178)

- replace rsync-only sync_git_repos.sh with git-native + legacy split (#182)

- scripts/ world-class pass — -h/--help sweep, modernize, delete dead coverage tool (#185)

- add -h/--help to run-bash-coverage.sh and .osx.sh (#186)

- add codex cask to Brewfile (#188)



## Testing

- add BATS coverage for git hooks, fix pre-push [ ] and bash-tracer.sh eval (#187)


