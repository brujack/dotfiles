# Changelog


## Bug Fixes

- strip GIT_DIR from the sweep's make invocation (#190)

- strip inherited git repo-location vars before make test (#191)

- install json2yaml globally, and pin it (#193)

- fail closed on unrecognized paths (#195)

- shellcheck the bats suites, revive six inert assertions (#197)

- read core.hooksPath through git config includes (#198)



## Documentation

- cut the hooksPath spec down to what survived review

- fold the git-hooks summary row into the hooksPath spec

- split the strip from the detector, promote the unexplained writer

- fix two test specifications that could not fail

- plan the hooksPath work as two PRs

- mark hooks-gitdir-strip plan done (dotfiles#190)

- spec stripping inherited git vars in BATS setup

- record Step 8 multi-lens review on git-env spec

- revise git-env spec per Step 8 dispositions

- record Step 8 round-2 lens findings on git-env spec

- cut git-env spec to the boundary fix

- record the round-3 lens skip and its reasoning

- close two gaps from the independent spec review

- settle both implementer items with real measurements

- add the plan DONE banner, correct the CI job list

- backlog the git-hook self-coverage gap

- close out npm global pinning, file its two follow-on rows

- retire the json2yaml backlog row, fixed in dotfiles#193

- document hooksPath doctor check in README, backlog two deferrals

- spec the two git-hook detection gaps

- record multi-lens review — Gap 2 premise refuted

- reframe Gap 2 as advisory, apply lens corrections

- round 2 lenses — detector is blind to include-borne pins

- split the hooksPath item out of the pre-push spec

- plan the pre-push self-coverage fix

- record the .zsh scope widening on the pre-push spec

- sync spec Design section with the widened regex

- ADR-0017 — the pre-push trigger fails closed

- correct ADR-0017's inert set and fail-open gap

- reconcile the pre-push plan with what shipped

- mark the pre-push plan Done (dotfiles#195)

- sync README and backlog after the fail-closed pre-push change

- backlog the core.quotePath path-anchor gap

- re-scope the maintainability backlog row, premise falsified

- add Claude Code weekly features digest 2026-08-03

- add Anthropic weekly features digest 2026-08-03

- mark the 2026-07-29 hooksPath spec contract superseded

- correct the projects/ memory tracking claim



## Features

- pin npm global packages, add jscpd (#192)

- detect global/system core.hooksPath pins (#194)


