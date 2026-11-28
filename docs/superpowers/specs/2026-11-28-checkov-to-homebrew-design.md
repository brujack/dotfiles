# Move checkov out of the shared uv lock into Homebrew

- **Date:** 2026-11-28
- **Status:** Draft

## Problem

dotfiles has 30 open Dependabot alerts (re-measured 2026-11-28 with
`gh api repos/brujack/dotfiles/dependabot/alerts?state=open`). They are 15 advisories, each
reported twice (once on `uv.lock`, once on a rendering), and every one traces to `checkov`,
which `pyproject.toml` declares in the `runtime` group of the one lock that builds the
`ansible` venv:

| Package    | Advisories (alerts) | Severity                | Locked  | Fixed in | Why the lock cannot move                                                                        |
| ---------- | ------------------- | ----------------------- | ------- | -------- | ----------------------------------------------------------------------------------------------- |
| virtualenv | 12 (24)             | 4 high, 5 medium, 3 low | 21.14.5 | 21.14.9  | every virtualenv from 21.14.6 needs `packaging>=26.3`; checkov declares `packaging<24.0,>=23.0` |
| asteval    | 2 (4)               | medium                  | 1.0.6   | 1.0.9    | checkov pins `asteval==1.0.6`                                                                   |
| ecdsa      | 1 (2)               | high                    | 0.19.2  | none     | no upstream fix (0.19.2 is the latest on PyPI)                                                  |

checkov 3.4.11 (2026-11-25, the newest on PyPI) still declares all three constraints, so no
checkov release clears them.

The virtualenv alerts are local: virtualenv enters through `pre-commit` in the `test-lint`
group and appears only in `uv.lock` and `requirements-ci.txt`, the local development set. No
other repo installs that file: ai-config CI installs `requirements-ci-test.txt` and
`requirements-ci-audit.txt`, state-ledger CI those two plus `requirements-ci-mutation.txt`
(`git grep 'dotfiles/master/requirements' -- .github` in each, 2026-11-28). The asteval and
ecdsa alerts sit on `uv.lock` and `requirements-runtime-ci.txt`, which has no consumer.

Two Backlog rows record this (`30 Dependabot alerts, all held by checkov's pins`,
`30 virtualenv alerts blocked by checkov's packaging<24 pin`); both name moving checkov out of
the shared lock as the fix. The operator held that on 2026-11-10 and lifted the hold on
2026-11-28, choosing the move.

What the move achieves: the 12 virtualenv advisories (24 alerts) are fixed in the venv. The
asteval and ecdsa advisories (6 alerts) are not fixed: the Homebrew formula vendors the same
versions, so they leave Dependabot's view and are recorded in ADR-0063 instead.

## Measurements (2026-11-28, pinned uv 0.13.0 unless stated)

- **Removal is self-contained.** In a scratch copy of `pyproject.toml` and `uv.lock` with the
  `"checkov>=3.3.13"` line deleted, `uv lock` removed 42 packages (269 to 227), added none and
  changed no other package's version. The 42: aiodns, aiomultiprocess, argcomplete, asteval,
  bc-detect-secrets, bc-jsonpath-ng, bc-python-hcl2, beartype, boto3, botocore,
  cached-property, cachetools, checkov, click-option-group, cloudsplaining, contextlib2,
  dockerfile-parse, dpath, ecdsa, importlib-metadata, junit-xml, markdown, networkx, orjson,
  ply, policy-sentry, prettytable, pycares, pycep-parser, rdflib, regex, rustworkx, s3transfer,
  schema, semantic-version, spdx-tools, tabulate, termcolor, unidiff, uritools, xmltodict,
  zipp. Population: this repo's lock. Reproduced independently by two review lenses.
- **virtualenv then resolves.** `uv lock --upgrade-package virtualenv` with
  `--exclude-newer 2026-11-14T00:00:00Z` (the 14-day cooldown, ADR-0057, at 2026-11-28) moves
  virtualenv 21.14.5 to 21.15.6 (2026-11-06) and packaging 23.2 to 26.3 (2026-08-04). Without
  the cutoff it reaches 21.15.14 and 26.4 (2026-11-23, inside the cooldown).
- **packaging moves in every rendering.** One lock resolves one packaging version for every
  group, so `requirements-ci-test.txt`, `-ci-audit.txt` and `-ci-mutation.txt`, which
  ai-config and state-ledger CI install from dotfiles master, go from `packaging==23.2` to
  26.3. 17 remaining locked packages depend on packaging, among them ansible-core,
  ansible-lint, ansible-compat, molecule, pytest and pip-audit.
- **packaging 26.3 runs.** A scratch venv synced from the cooldown lock (`--group runtime
--group test-lint`, `claude`, Python 3.14) imports packaging 26.3; `ansible` (core
  2.21.6), `ansible-lint` 26.11.0, `molecule` 26.11.0, `pre-commit` 4.7.0, `pip-audit`
  2.10.1 and `pytest` 9.1.1 each print their version; `ansible-lint --offline -q` over a
  `git archive` of terraform_ansible's `ansible/` exits 0 under that venv and under the
  current one, with no traceback in either. Population: one machine, one consumer tree; the
  ai-config and state-ledger suites are not run here (their first PR CI after merge is that
  check).
- **boto3 and cloudsplaining go with checkov.** Neither is declared in `pyproject.toml`
  (`tests/setup_env/developer.bats` pins boto3's absence and says checkov and cloudsplaining
  are why it is still installed). `git grep -E 'amazon\.aws|community\.aws|import boto|cloudsplaining'`
  across the nine repos found only docs. The math and ai-config sessions each confirmed,
  2026-11-28, that nothing in their repo imports any of the 42 or calls checkov from the
  shared venv.
- **Who runs checkov.** `terraform_ansible/proxmox/Makefile:17` and
  `terraform_ansible/cloudflare/Makefile:14` (`make lint`, also run by terraform_ansible's
  pre-push hook for changes under those components), and ai-config's `security-review` skill
  (`checkov -d . --framework terraform 2>&1 || true`, a fallback when tfsec is absent). Each
  calls bare `checkov` from `PATH`. No CI job in the fleet runs it.
- **The Homebrew formula.** `brew info checkov`: stable 3.4.11, bottled for
  `arm64_golden_gate`, `arm64_tahoe`, `arm64_sequoia`, `arm64_linux` and `x86_64_linux` (no
  Intel-mac bottle), `python@3.15`, its own virtualenv. Its formula (`Formula/c/checkov.rb`,
  homebrew-core HEAD 2026-11-28) vendors `asteval-1.0.6`, `ecdsa-0.19.2` and `packaging-23.2`.
  It is not installed on `claude` or the Studio today.
- **`-t update` installs no new formula.** Its brew section calls only `brew_update`
  (`lib/helpers.sh`), which runs `brew update`, `brew trust`, `brew upgrade --yes`,
  `brew upgrade --cask --greedy --yes` and `brew cleanup`. New formulae are installed only by
  `install_macos_casks` (`brew bundle`, reached from `-t setup`, `-t developer` and
  `-t brew_install`) and `_install_ubuntu_brew_packages` (reached from `-t setup` and
  `-t developer`). Its pip section runs `uv sync --frozen` (`uv_sync_venv`), an exact sync that
  removes packages the lock no longer has, then `pyenv rehash`.
- **PATH.** On `claude`, interactive zsh lists `~/.pyenv/shims` before
  `/home/linuxbrew/.linuxbrew/bin` (`.zprofile` runs `pyenv init --path`;
  `.config/.zshrc.d/6_path.zsh` appends linuxbrew with `path+=`). A login non-interactive
  shell (`env -i HOME=$HOME PATH=/usr/bin:/bin zsh -l -c 'command -v checkov'`) finds checkov
  through the pyenv shim and has no linuxbrew `bin`. A plain `ssh workstation '…'` finds
  neither checkov nor brew today. tflint and tfsec on Linux are pinned binaries in
  `/usr/local/bin`, not linuxbrew formulae.
- **etch-config.** `etch-config/{studio,workstation,etch-cli-test}/ansible.yaml` recreate
  `~/.pyenv/versions/ansible` and pip-install an unpinned `checkov` into it. On workstation the
  venv's `checkov-3.4.3.dist-info/INSTALLER` reads `uv` (`bin/checkov` dated 2026-11-08), so no
  `etch apply` has written that venv since `-t update` last synced it.

## Design

Install checkov from Homebrew and remove it from the lock.

1. **`pyproject.toml`.** Delete the `"checkov>=3.3.13",` line and the comment block attached to
   it (the floor rationale and the accepted-risk text). No other declaration changes.
2. **`Brewfile`.** Add `brew "checkov"                              # [HAS_DEVTOOLS]` in
   alphabetical position, tagged like `tflint` and `tfsec`, preceded by a one-line comment:
   `# vendors asteval 1.0.6 and ecdsa 0.19.2 with open advisories; see docs/adr/0063-checkov-from-homebrew.md`.
   Every mac installs it; the tag only sets drift expectations. An Intel mac has no bottle and
   builds it from source.
3. **Linux.** Add `checkov` to the `for _f in` formula list in `_install_ubuntu_brew_packages`
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
   - Add a test asserting `Brewfile` carries a `brew "checkov"` line tagged `[HAS_DEVTOOLS]`,
     and that the formula list extracted from the `for _f in` loop of
     `_install_ubuntu_brew_packages` names `checkov`; the extraction must yield a non-empty
     list (positive control: it also names `uv`).
   - Correct the boto3 test's comment: boto3 is no longer installed at all once checkov leaves.
6. **ADR-0063, `docs/adr/0063-checkov-from-homebrew.md`.** Records the move, the measurements
   above, and that the asteval (GHSA-9w56-46f6-3qhx, GHSA-89v8-rhwq-hf77) and ecdsa
   (GHSA-wj6h-64fc-37mp) advisories still apply inside the Homebrew install, where Dependabot
   does not see them. It carries the accepted-risk condition from the deleted comment: none is
   reachable while every policy checkov evaluates is the operator's own, and that expires
   silently if checkov is pointed at a repository with third-party custom policies. It also
   records that Homebrew applies no 14-day cooldown to checkov, and the rollout order below.
7. **Backlog.** Close both checkov rows as fixed by this change. Add an etch-config Backlog row
   in etch-config's own `docs/superpowers/README.md`: its `ansible.yaml` still pip-installs
   checkov into the venv dotfiles syncs, which would restore the pyenv shim ahead of the
   Homebrew copy and pull packaging below 24.
8. **Notice.** Before merge, message the ai-config and state-ledger sessions with the PR number:
   `packaging` moves from 23.2 to the cooldown-eligible release in `requirements-ci-test.txt`,
   `requirements-ci-audit.txt` and `requirements-ci-mutation.txt`, so each watches its first PR
   CI after the merge. (ai-config was told on 2026-11-28 that packaging moves.)

### Rollout order

`-t update` removes checkov from the venv (exact `uv sync`, then `pyenv rehash`) and installs
no new formula, so on a box without the formula the first update after merge leaves no
`checkov` at all, and re-running it does not help. To avoid that gap:

1. Before merge, with the operator's approval, run `brew install checkov` on `claude`,
   `workstation` and the Studio, the three development machines. The pyenv shim stays ahead of
   the Homebrew copy on `PATH` until the update removes it, so `checkov` resolves throughout.
2. Merge. The next `-t update` on each of those machines removes the venv copy and the shim.
3. Any other machine gets the formula at its next `-t developer` (Linux) or `-t brew_install`
   (macOS); until then it has no checkov. None of them runs terraform_ansible's `make lint`.

No migration code is added.

### Not handled

- A login non-interactive shell on Linux (`zsh -l -c '…'`, cron) finds checkov today through
  the pyenv shim and will not after the move, because linuxbrew's `bin` is added only by the
  interactive `6_path.zsh`. A plain `ssh workstation 'make lint'` already fails at checkov
  today, so that path does not regress. Sessions, hooks and terraform_ansible's `make lint` run
  from interactive shells, where linuxbrew is on `PATH`.
- Homebrew updates checkov without a cooldown.

## Alternatives rejected

- **`uv tool install checkov`.** Isolates checkov and could keep a cooldown, but needs a new
  install function, an update section and tests for one tool.
- **A second lock for checkov alone.** Keeps the cooldown and Dependabot's view of asteval and
  ecdsa, at the cost of a second lock and sync path. Too heavy for one tool.
- **`[tool.uv] override-dependencies = ["packaging>=26.3"]`.** One line, keeps the cooldown,
  but forces checkov past its own `packaging<24` pin (runtime risk inside checkov) and clears
  none of the asteval or ecdsa alerts.
- **Keep holding.** Leaves 12 virtualenv advisories in the local venv with no upstream release
  in sight.

## Requirements

- **R1.** `pyproject.toml` declares no `checkov` dependency, and the comment block describing
  the checkov floor and the asteval/ecdsa accepted risk is removed from it.
- **R2.** `Brewfile` contains the line `brew "checkov"` with the trailing tag `# [HAS_DEVTOOLS]`,
  in alphabetical position, directly preceded by a comment naming
  `docs/adr/0063-checkov-from-homebrew.md`.
- **R3.** The `for _f in` formula list in `_install_ubuntu_brew_packages` (`lib/linux_ubuntu.sh`)
  includes `checkov`.
- **R4.** `uv.lock` and all five `requirements-*.txt` renderings contain no `checkov`,
  `asteval` or `ecdsa` entry, and `virtualenv` is at 21.14.9 or later in `uv.lock` and
  `requirements-ci.txt`.
- **R5.** Compared with master, `uv.lock` changes only by removing packages and by moving
  `virtualenv` and `packaging`; `make check-requirements-ci` passes.
- **R6.** `tests/setup_env/developer.bats` asserts that `pyproject.toml` declares no `checkov`
  (with a positive control that `"ansible"` is declared) and no longer asserts a checkov floor.
- **R7.** `tests/setup_env/developer.bats` asserts that `Brewfile` has a `brew "checkov"` line
  tagged `[HAS_DEVTOOLS]`, and that the formula list of the `for _f in` loop in
  `_install_ubuntu_brew_packages` names `checkov`, with a positive control that the same
  extracted list names `uv`.
- **R8.** `docs/adr/0063-checkov-from-homebrew.md` exists, is listed in `docs/adr/README.md`,
  and names GHSA-9w56-46f6-3qhx, GHSA-89v8-rhwq-hf77 and GHSA-wj6h-64fc-37mp as still present
  in the Homebrew install, the third-party-policy expiry condition, the absent cooldown, and
  the rollout order (formula installed on the three development machines before merge).
- **R9.** Both checkov Backlog rows in `docs/superpowers/README.md` are removed or marked fixed
  by this change.
- **V1.** The moved `virtualenv` and `packaging` versions each have a PyPI upload time at least
  14 days before the commit that sets them.
- **V2.** Before merge, `brew install checkov` has run on `claude`, `workstation` and the Studio
  (operator-approved), and on each `command -v checkov` still resolves (to the pyenv shim).
- **V3.** After merge, `./setup_env.sh -t update` on `claude`, `workstation` and the Studio
  leaves `command -v checkov` resolving under the brew prefix (not `~/.pyenv/shims`) and
  `checkov --version` printing the formula's version.
- **V4.** `make lint` in `terraform_ansible/proxmox` passes on `claude` with the Homebrew
  checkov.
- **V5.** After merge, `gh api repos/brujack/dotfiles/dependabot/alerts?state=open` exits 0,
  returns a JSON array, and lists no virtualenv, asteval or ecdsa alert.
- **V6.** The ai-config and state-ledger sessions were sent the PR number and the packaging
  move before merge.
- **N1.** No package other than `virtualenv` and `packaging` changes version in `uv.lock`.
- **N2.** No change to etch-config, terraform_ansible or ai-config source or configuration;
  the only write outside dotfiles is one Backlog row in etch-config's
  `docs/superpowers/README.md`, committed there separately.
- **N3.** No new install function, update section or migration code for checkov.
- **N4.** `checkov` is not added to `Brewfile.devtools` or `Brewfile.gui`.

## Multi-Lens Review

Reviewed at commit: `aef88473` (spec as first written, before Step 8 dispatch)

### Goal-Fit

Finding: The cross-repo half of the problem statement was false: no other repo installs
`requirements-ci.txt`, so the virtualenv alerts are local; packaging, not virtualenv, moves in
the three renderings ai-config and state-ledger install. The 30 alerts are 15 advisories
counted twice, and 6 (asteval, ecdsa) are hidden rather than fixed. The R7 change-detector is
weak; the ADR's expiry condition loses its reader once the pyproject comment goes (put a
pointer beside the Brewfile entry). etch-config writes the same venv. `override-dependencies`
should be listed as a rejected alternative. Removal premise verified (42 removed, 0 changed).
Assumption: Nothing reinstalls checkov into `~/.pyenv/versions/ansible` after `uv sync`
removes it; only etch-config's `pip.install` could. Confirm on workstation with the venv's
`checkov-*.dist-info/INSTALLER` and mtime.
Disposition: Addressed (operator, 2026-11-28). Problem statement, alert accounting, notice
step and V5 rewritten; Brewfile comment pointing at ADR-0063 added (R2); override-dependencies
listed under Alternatives; etch-config row strengthened. Assumption measured: INSTALLER reads
`uv`, `bin/checkov` dated 2026-11-08, so no etch apply has written the venv since.

### Ergonomics

Finding: Load-bearing: `-t update` never installs a new formula (`brew_update` only upgrades),
while `uv sync --frozen` removes the venv checkov, so the first update after merge leaves no
checkov on `claude`, workstation or the Studio and terraform_ansible pushes touching
proxmox/cloudflare fail. Fix: `brew install checkov` on the three development machines before
merge. The tflint comparison was wrong (tflint/tfsec are `/usr/local/bin` binaries on Linux);
plain `ssh workstation 'make lint'` already lacks checkov. R7 should grep the `for _f in` list,
not the file; V4 should check the API call's exit code and shape.
Assumption: No design-breaking uncertain assumption remains; the transition claim is a
confirmed defect. Nearest: whether the work macs have a checkov bottle.
Disposition: Addressed (operator, 2026-11-28). Rollout order section added (formula installed
before merge, V2, V3, R8); "Not handled" corrected; R7 scoped to the loop list with a `uv`
positive control; V5 checks exit code and shape; Intel-mac no-bottle stated in Design 2.

### Risk

Finding: Same load-bearing transition defect as Ergonomics. packaging moves 23.2 to 26.3 in
all five renderings and under 17 locked dependents; the notice must name every consumed file.
etch-config collision (same venv, shim ahead of linuxbrew) acceptable only if etch apply is
not run. No x86_64-macOS bottle. Disclosure of lost cooldown and hidden advisories adequate;
not over-engineered.
Assumption: packaging 26.3 is runtime-compatible with ansible-core, ansible-lint,
ansible-compat, molecule, pytest and pip-audit. Settle by syncing a scratch venv from the
cooldown lock and running them, plus ansible-lint over terraform_ansible.
Disposition: Addressed (operator, 2026-11-28). Assumption measured: every tool runs on
packaging 26.3 and `ansible-lint --offline` over terraform_ansible's `ansible/` exits 0 with
no traceback (Measurements). Notice names the three consumed renderings; rollout order added.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
