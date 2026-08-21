# Changelog


## Documentation

- pip check is not sufficient, and results are discarded

- backlog the untested no_legacy exception path

- backlog the tolerated double detect_env call

- backlog the missing CI job timeouts

- record CI figures and close out #223

- ADR-0021 — hand-typed test oracle for the identity table

- ADR-0021's own receipt was wrong, fourth time

- say lines, not occurrences

- backlog the oracle comment's comment-to-code ratio

- name the receipt's expiry condition

- the closing rule rejected its own example

- document the mutation that actually isolates the variable (#224)

- backlog pep621 for dotfiles' renovate config

- spec adding uv to the Brewfile

- uv needs two edits, not one — Linux ignores the Brewfile

- revise uv spec against three lens findings

- backlog uv's unpinned drift, with its revisit trigger

- --inexact does not protect conflicting packages

- round 2 — two of my own corrections were defective

- record the Multi-Lens Review section

- plan adding uv to both platforms' install paths

- index the brewfile-uv plan

- Task 3 needs ssh -A, measured before dispatch

- coverage figures from CI for #225

- mark brewfile-uv plan done

- uv is installed on Linux but not reachable

- the reachability table was measured wrong

- linuxbrew on the login-shell PATH

- retire the linuxbrew login-PATH design

- backlog names .zshenv, not .zprofile

- brew reachability via a tracked .zshenv

- scope the .zshenv fix to Linux only

- name what would widen the .zshenv scope

- exclude cruncher, gate on PROFILE not LINUX

- include cruncher, dormant, per operator

- cruncher may become native Linux

- .zshenv design blocked, assumption refuted

- v2 -- guard on non-interactive, append not prepend

- v2 blocked -- same class as v1, one file over

- v2's exported append degrades tmux panes

- resolve brew by prefix inside setup_env.sh

- block the setup_env probe -- no consumer

- record the salvage path and the cruncher risk

- close the brew-reachability thread, four designs

- a capability tag does not gate installation

- close v2, its recommendation was stale on arrival

- bats' EXIT trap is what prints the TAP line

- clearing the trap and never installing one are opposite



## Features

- install uv on macOS and Linux (#225)



## Refactoring

- resolve legacy identity vars from one table (#223)


