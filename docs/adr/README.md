# Architectural Decision Records

Cross-cutting decisions that apply across personal repos. Repo-specific decisions live in that repo's own `docs/adr/`.

| ADR                                                            | Title                                                   | Date       | Status   |
| -------------------------------------------------------------- | ------------------------------------------------------- | ---------- | -------- |
| [0001](0001-use-bats-for-shell-testing.md)                     | Use BATS for shell testing                              | 2026-03-27 | Accepted |
| [0002](0002-use-gitleaks-for-secret-scanning.md)               | Use gitleaks for secret scanning                        | 2026-04-08 | Accepted |
| [0003](0003-profile-capability-model-for-machine-detection.md) | Profile/capability model for machine detection          | 2026-03-31 | Accepted |
| [0004](0004-lib-modular-structure-for-setup-env.md)            | Modular lib/ structure for setup_env.sh                 | 2026-03-31 | Accepted |
| [0005](0005-require-secrets-guarding-in-all-personal-repos.md) | Require secrets guarding in all personal repos          | 2026-04-09 | Accepted |
| [0006](0006-shell-script-testability-conventions.md)           | Shell script testability conventions                    | 2026-04-11 | Accepted |
| [0007](0007-branch-protection-automation.md)                   | Codify branch protection via script                     | 2026-05-19 | Accepted |
| [0008](0008-bash-coverage-ps4-xtrace.md)                       | Use PS4 xtrace for bash coverage measurement            | 2026-06-01 | Accepted |
| [0009](0009-powerlevel10k-removal-starship-sole-prompt.md)     | Powerlevel10k removal — Starship as sole prompt         | 2026-05-27 | Accepted |
| [0010](0010-renovate-replacing-dependabot.md)                  | Renovate replacing Dependabot for dependency updates    | 2026-05-18 | Accepted |
| [0011](0011-linux-sh-split-ubuntu-shared.md)                   | linux.sh split into linux_ubuntu.sh and linux_shared.sh | 2026-04-28 | Accepted |
| [0012](0012-brewfile-drift-detection.md)                       | Brewfile drift detection in update summary              | 2026-04-29 | Accepted |
| [0013](0013-no-curl-bash-installs.md)                          | Replace curl\|bash installers with verified installs    | 2026-06-22 | Accepted |
| [0014](0014-state-ledger-cmdb-integration.md)                  | State-ledger CMDB integration for update run metadata   | 2026-06-28 | Accepted |
| [0015](0015-release-sbom-vulnerability-monitoring.md)          | Continuous vulnerability monitoring of release SBOMs    | 2026-07-16 | Accepted |
