# Move checkov out of the shared uv lock into Homebrew

- **Date:** 2026-11-28
- **Status:** Draft

## Problem

dotfiles has 30 open Dependabot alerts (re-measured 2026-11-28 with
`gh api repos/brujack/dotfiles/dependabot/alerts?state=open`), every one traced to `checkov`,
which `pyproject.toml` declares in the `runtime` group of the one lock that builds the
`ansible` venv:

| Package    | Alerts      | Locked  | Fixed in | Why the lock cannot move                                                                        |
| ---------- | ----------- | ------- | -------- | ----------------------------------------------------------------------------------------------- |
| virtualenv | 24 (8 high) | 21.14.5 | 21.14.9  | every virtualenv from 21.14.6 needs `packaging>=26.3`; checkov declares `packaging<24.0,>=23.0` |
| asteval    | 4           | 1.0.6   | 1.0.9    | checkov pins `asteval==1.0.6`                                                                   |
| ecdsa      | 2           | 0.19.2  | none     | no upstream fix (0.19.2 is the latest on PyPI)                                                  |

checkov 3.4.11 (2026-11-25, the newest on PyPI) still declares all three constraints, so no
checkov release clears them. virtualenv enters through `pre-commit` in the `test-lint` group,
and `requirements-ci.txt` (rendered from `test-lint`) is installed live from dotfiles master by
ai-config and state-ledger CI, so the 8 high virtualenv alerts reach two other repos' CI.

Two Backlog rows record this (`30 Dependabot alerts, all held by checkov's pins`,
`30 virtualenv alerts blocked by checkov's packaging<24 pin`); both name moving checkov out of
the shared lock as the fix. The operator held that on 2026-11-10 and lifted the hold on
2026-11-28, choosing the move.

## Measurements (2026-11-28, `claude`, pinned uv 0.13.0)

- **Removal is self-contained.** In a scratch copy of `pyproject.toml` and `uv.lock` with the
  `"checkov>=3.3.13"` line deleted, `uv lock` removed 42 packages (269 to 227) and changed no
  other package's version. The 42: aiodns, aiomultiprocess, argcomplete, asteval,
  bc-detect-secrets, bc-jsonpath-ng, bc-python-hcl2, beartype, boto3, botocore,
  cached-property, cachetools, checkov, click-option-group, cloudsplaining, contextlib2,
  dockerfile-parse, dpath, ecdsa, importlib-metadata, junit-xml, markdown, networkx, orjson,
  ply, policy-sentry, prettytable, pycares, pycep-parser, rdflib, regex, rustworkx, s3transfer,
  schema, semantic-version, spdx-tools, tabulate, termcolor, unidiff, uritools, xmltodict,
  zipp. Population: this repo's lock only.
- **virtualenv then resolves.** `uv lock --upgrade-package virtualenv` on that copy moved
  virtualenv 21.14.5 to 21.15.14 and packaging 23.2 to 26.4, with no cooldown applied. Under
  the 14-day cooldown (ADR-0057) at 2026-11-28 the newest eligible releases are virtualenv
  21.15.6 (2026-11-06) and packaging 26.3 (2026-08-04); both clear every virtualenv advisory
  (all fixed by 21.14.9).
- **boto3 and cloudsplaining go with checkov.** Neither is declared in `pyproject.toml`
  (`tests/setup_env/developer.bats` pins boto3's absence and says checkov and cloudsplaining
  are why it is still installed). `git grep -E 'amazon\.aws|community\.aws|import boto|cloudsplaining'`
  across the nine repos found only docs: no playbook or script uses either.
- **Who runs checkov.** `terraform_ansible/proxmox/Makefile` and
  `terraform_ansible/cloudflare/Makefile` (`make lint`), and ai-config's `security-review`
  skill (`checkov -d . --framework terraform`). Each calls `checkov` from `PATH`. No CI job in
  the fleet runs it. `etch-config` pip-installs `checkov` into its own `ansible` venv
  (`studio/ansible.yaml`, `workstation/ansible.yaml`, `etch-cli-test/ansible.yaml`).
- **The Homebrew formula.** `brew info checkov`: stable 3.4.11, bottled, `python@3.15`, its own
  virtualenv. Its formula (`Formula/c/checkov.rb`, homebrew-core HEAD 2026-11-28) vendors
  `asteval-1.0.6`, `ecdsa-0.19.2` and `packaging-23.2`.
- **PATH.** On `claude`, `env -i HOME=$HOME PATH=/usr/bin:/bin zsh -l -c 'command -v checkov'`
  prints `/home/bruce/.pyenv/shims/checkov` (`.zprofile` runs `pyenv init --path`), while
  linuxbrew's `bin` is added only by the interactive `.config/.zshrc.d/6_path.zsh` (`path+=`).

## Design

Install checkov from Homebrew and remove it from the lock.

1. **`pyproject.toml`.** Delete the `"checkov>=3.3.13",` line and the comment block attached to
   it (the floor rationale and the accepted-risk text). No other declaration changes.
2. **`Brewfile`.** Add `brew "checkov"                              # [HAS_DEVTOOLS]` in
   alphabetical position, tagged like `tflint` and `tfsec`. Every mac installs it; the tag only
   sets drift expectations.
3. **Linux.** Add `checkov` to the formula list in `_install_ubuntu_brew_packages`
   (`lib/linux_ubuntu.sh`), so `brew_install_formula checkov` runs on every Ubuntu box that
   runs that function. This is wider than the venv (developer boxes only); accepted for one
   list rather than a new gated branch.
4. **Lock and renderings.** Regenerate `uv.lock` and the five `requirements-*.txt` renderings
   with the pinned uv. The change is the 42 removals plus virtualenv and packaging, each at its
   newest release at least 14 days old at the commit (21.15.6 and 26.3 if committed on
   2026-11-28). No other package moves.
5. **Tests (`tests/setup_env/developer.bats`).**
   - Replace `checkov carries a floor at or above 3.3.13` with a test asserting
     `pyproject.toml` declares no `checkov` (a re-add would re-block virtualenv), with a
     positive control that `"ansible"` is still declared.
   - Add a test asserting `Brewfile` carries a `brew "checkov"` line tagged `[HAS_DEVTOOLS]`
     and the `_install_ubuntu_brew_packages` list names `checkov`.
   - Correct the boto3 test's comment: boto3 is no longer installed at all once checkov leaves.
6. **ADR-0063, `docs/adr/0063-checkov-from-homebrew.md`.** Records the move, the measurements
   above, and that the asteval (GHSA-9w56-46f6-3qhx, GHSA-89v8-rhwq-hf77) and ecdsa
   (GHSA-wj6h-64fc-37mp) advisories still apply inside the Homebrew install, where Dependabot
   does not see them. It carries the accepted-risk condition from the deleted comment: none is
   reachable while every policy checkov evaluates is the operator's own, and that expires
   silently if checkov is pointed at a repository with third-party custom policies. It also
   records that Homebrew applies no 14-day cooldown to checkov.
7. **Backlog.** Close both checkov rows as fixed by this change. Add an etch-config Backlog row
   (its `ansible.yaml` still pip-installs checkov into its venv).
8. **Notice.** Before merge, message the ai-config and state-ledger sessions: their CI installs
   `requirements-ci.txt` from dotfiles master, and virtualenv and packaging move in it.

### Transition on a provisioned box

`-t update` runs `uv sync --frozen` (`uv_sync_venv`), which removes checkov from the venv, and
the update path's `pyenv rehash` then drops the stale `checkov` shim. The brew section installs
the formula. Until both have run, `checkov` may resolve to a shim with no target; re-running
`-t update` completes it. No migration code is added.

### Not handled

- A login non-interactive shell on Linux (`ssh claude 'make lint'`, cron) finds checkov today
  through the pyenv shim and will not after the move, because linuxbrew's `bin` is
  interactive-only. tflint and every other linuxbrew tool already behave this way; sessions,
  hooks and terraform_ansible's `make lint` run from interactive shells.
- Homebrew updates checkov without a cooldown, the same as tflint and tfsec.

## Alternatives rejected

- **`uv tool install checkov`.** Isolates checkov and could keep a cooldown, but needs a new
  install function, an update section and tests for one tool.
- **A second lock for checkov alone.** Keeps the cooldown and Dependabot's view of asteval and
  ecdsa, at the cost of a second lock and sync path. Too heavy for one tool.
- **Keep holding.** Leaves 8 high virtualenv alerts in a rendering two other repos' CI installs,
  with no upstream release in sight.

## Requirements

- **R1.** `pyproject.toml` declares no `checkov` dependency, and the comment block describing
  the checkov floor and the asteval/ecdsa accepted risk is removed from it.
- **R2.** `Brewfile` contains the line `brew "checkov"` with the trailing tag `# [HAS_DEVTOOLS]`,
  in alphabetical position.
- **R3.** The formula list in `_install_ubuntu_brew_packages` (`lib/linux_ubuntu.sh`) includes
  `checkov`.
- **R4.** `uv.lock` and all five `requirements-*.txt` renderings contain no `checkov`,
  `asteval` or `ecdsa` entry, and `virtualenv` is at 21.14.9 or later in `uv.lock` and
  `requirements-ci.txt`.
- **R5.** Compared with master, `uv.lock` changes only by removing packages and by moving
  `virtualenv` and `packaging`; `make check-requirements-ci` passes.
- **R6.** `tests/setup_env/developer.bats` asserts that `pyproject.toml` declares no `checkov`
  (with a positive control that `"ansible"` is declared) and no longer asserts a checkov floor.
- **R7.** `tests/setup_env/developer.bats` asserts that `Brewfile` has a `brew "checkov"` line
  tagged `[HAS_DEVTOOLS]` and that the `_install_ubuntu_brew_packages` list names `checkov`.
- **R8.** `docs/adr/0063-checkov-from-homebrew.md` exists, is listed in `docs/adr/README.md`,
  and names GHSA-9w56-46f6-3qhx, GHSA-89v8-rhwq-hf77 and GHSA-wj6h-64fc-37mp as still present
  in the Homebrew install, the third-party-policy expiry condition, and the absent cooldown.
- **R9.** Both checkov Backlog rows in `docs/superpowers/README.md` are removed or marked fixed
  by this change.
- **V1.** The moved `virtualenv` and `packaging` versions each have a PyPI upload time at least
  14 days before the commit that sets them.
- **V2.** After merge, `./setup_env.sh -t update` on `claude` and on the Studio leaves
  `command -v checkov` resolving under the brew prefix (not `~/.pyenv/shims`) and
  `checkov --version` printing the formula's version.
- **V3.** `make lint` in `terraform_ansible/proxmox` passes on `claude` with the Homebrew
  checkov.
- **V4.** Dependabot reports 0 open alerts on dotfiles after merge.
- **V5.** The ai-config and state-ledger sessions were notified before merge.
- **N1.** No package other than `virtualenv` and `packaging` changes version in `uv.lock`.
- **N2.** No change to etch-config, terraform_ansible or ai-config source or configuration;
  the only write outside dotfiles is one Backlog row in etch-config's
  `docs/superpowers/README.md`, committed there separately.
- **N3.** No new install function, update section or migration code for checkov.
- **N4.** `checkov` is not added to `Brewfile.devtools` or `Brewfile.gui`.
