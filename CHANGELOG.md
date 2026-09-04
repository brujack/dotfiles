# Changelog


## Bug Fixes

- put ~/.local/bin on the LaunchAgent PATH (#248)

- keep the detector's stderr out of the finding count (#249)

- mktemp -t is not portable, use an explicit template

- exit non-zero when a section fails (#250)

- stop run_update reporting OK over failures it cannot see (#251)



## CI

- cap all 7 job runtimes with timeout-minutes (#247)



## Documentation

- two CI jobs documented advisory actually gate

- mark the timeout plan Done

- ADR-0025 — no mechanical guard for CI job timeouts

- correct advisory claim on two blocking jobs

- 7 orphaned worktrees hold 192 unique permission rules

- sync coverage provenance and the plist re-install requirement

- _count over-count now has a measured instance

- sync the figure and its provenance to #249

- ADR-0026 — the cadence detector contract is two streams

- -t update run truthfulness design

- retire the pip-check row, correct the summary row

- narrow update-truthfulness scope after multi-lens review

- correct the exit-rate window and the always-returns-0 claim

- ship the err_* one-liner ahead of the exit contract

- update-run truthfulness, 6 tasks

- sync the figure to CI's run on #250

- record the -t update exit contract

- add Anthropic weekly features digest 2026-08-31

- add Claude Code weekly features digest 2026-08-31

- update_run cd guards split 3/2, not 5

- self-review fixes to cd-guards spec

- record round-1 multi-lens review

- revise cd-guards spec on round-1 findings

- revise on round-2 findings, close review

- correct cheat.sh curl line refs

- 7 tasks for the cd-guards spec

- cadence_notify test defeated by real local.sh

- record measured gate falsifiability

- curl mock emits stdout alongside -o

- correct install-path function name to run_setup_user

- err_cheat.sh carries the body, not just errors

- gate 4 was impossible, corrected to -eq 1

- name the two docs this branch falsifies

- date the cheat.sh artifact sizes

- post-merge sync for #251

- correct update-run exit contract and summary sample in README

- awscli download signature verification design

- correct the coverage budget and an overstated inference

- drop the superseded coverage paragraph

- record CI coverage for #252 and close the shipped backlog row



## Features

- verify awscli download signatures before sudo (#252)


