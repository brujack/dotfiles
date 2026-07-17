# Changelog


## Bug Fixes

- remove duplicate powershell.md @-include

- system OpenSSL for gem HTTPS + Linux test hermeticity (#171)

- detect silent install failure in recreate_ruby (#173)

- run gem update after ruby recreate (#174)

- harden ensure_state_ledger against SSH hangs and corrupt clones (#177)

- brace $0/$1/$2/$3 in sync-agent-guidance.sh (#179)



## CI

- raise test count floor from 779 to 840 (#170)



## Documentation

- bump test count floor to 806, note 810 tests as of 2026-06-25

- update test count to 834 after state-ledger-integration PR #166

- state-ledger integration — ADR-0014, test count 840, plan index

- update CLAUDE.md — ledger wiring for all run_* functions, 848 tests

- add PR #168 to superpowers plan index

- add Claude Code weekly features digest 2026-06-29

- add Anthropic weekly features digest 2026-06-29 (#169)

- compact CLAUDE.md layout tree, drop 3 redundant rows

- remove Installation Guards duplicate of shell.md

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



## Features

- dotfiles adds powershell.md language standard

- add cargo-cyclonedx and cyclonedx-python (#165)

- add advisory skill scan after claude plugin update

- state-ledger CMDB integration (T5/T6/T7) (#166)

- wire state-ledger writes into dotfiles update (#167)

- wire state-ledger into setup/developer/recreate_venv runs (#168)

- add recreate-ruby entry point to setup_env.sh (#172)

- auto clone/pull state-ledger on setup/update runs (#176)

- implement sync-agent-guidance / check-agent-guidance targets (#178)



## Testing

- fix opentofu tests failing when tofu installed on macOS


