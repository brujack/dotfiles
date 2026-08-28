# Changelog


## Bug Fixes

- inline the preset — this repo has never once been processed (#238)

- fail closed when the identity table does not load (#239)

- call install_ledger_drift_agent from run_setup_user (#245)

- authenticate to ntfy, and give the heartbeat one path and a written bound (#246)



## CI

- hold unlabelled Renovate PRs for triage (#243)

- cap all 7 job runtimes with timeout-minutes (#247)



## Documentation

- tracer's case-label regex misses numeric labels

- the preset fix is necessary and not sufficient

- narrow the Renovate row — PENDING is not INERT, Monday is the test

- the cause is mode=silent, set above every repo's config

- file the BASH_SOURCE tracer row I said I would not claim unmeasured

- sync CLAUDE.md figures, document renovate.json state, ADR-0022

- land two shipped backlog rows, correct one that went false

- spec bash-version guard for config/profiles.sh

- address Step 8 lens findings on the bash-guard spec

- measure the fragility claim, move its test to Group B

- rebuild the doctor fix on a sentinel after round 2

- cut the bash-version guard, narrow to the real gap

- prohibit env -i in the test harness, fix five case defects

- make T3's safety self-verifying, generalize the stopping rule

- plan the identity-table fail-closed change

- record #239's CI figures and close the plan

- Renovate is confirmed working here, and mode=silent is not

- add Anthropic weekly features digest 2026-08-24

- add Claude Code weekly features digest 2026-08-24

- projects/ IS symlinked, and this file said otherwise

- record CI's coverage figure and a counter-example to the local-vs-CI rule

- surface the weekly cadence in README's layout and usage tables

- record two review findings against ADR-0024

- document the heartbeat contract and amend ADR-0024

- design job timeout-minutes for all 7 CI jobs

- fix two self-review findings in the timeout spec

- address round-1 lens findings on the timeout spec

- reduce the guard and correct two over-claims

- drop the guard test, ship the seven timeout lines

- record the 6 Dependabot alerts as upgrade-proof

- scope the no-guard bet to the population actually counted

- name the self-reference in the no-guard bet

- plan the seven timeout-minutes lines

- two CI jobs documented advisory actually gate

- mark the timeout plan Done

- ADR-0025 — no mechanical guard for CI job timeouts



## Features

- resize the CI slices, add ci-audit, gate the lock (#236)

- enable npm and pinDigests, document the pip_requirements trap (#237)

- weekly LaunchAgent that summons Renovate triage (#244)


