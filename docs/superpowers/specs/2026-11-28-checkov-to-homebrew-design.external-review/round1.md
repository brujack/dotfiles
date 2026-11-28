Tools: Read, Bash, SubagentHandback

Three things in this spec are right and should stay. First, the premise holds and was re-measured rather than inherited. Second, the transition gap (`-t update` removes checkov from the venv but never installs a new formula) is closed by ordering: the formula goes on before merge. That needs no migration code. Third, the alert accounting is honest: the six asteval and ecdsa alerts are described as hidden, not fixed. I reproduced the core claim. With the `checkov>=3.3.13` line deleted, `uv lock --upgrade-package virtualenv --exclude-newer 2026-11-14T00:00:00Z` (uv 0.13.10 Homebrew, not the pinned 0.13.0; Linux `claude`) removed 42 packages. It changed exactly two versions: virtualenv 21.14.5 to 21.15.6 and packaging 23.2 to 26.3. Of the three renderings other repos consume, only packaging changes in each; none loses a package.

## F1.1 The 42 removed packages leave the default interpreter, and only part of the fleet was checked for importers

**Defect.** Interactive shells activate the ansible venv (`.config/.zshrc.d/7_final.zsh:69`, `pyenv activate ansible`). It is therefore the `python3` that every script in all nine repos gets. The removal takes 42 packages out of that interpreter, among them tabulate, regex, markdown, termcolor, networkx, orjson, xmltodict, prettytable, cachetools, importlib-metadata and zipp. The evidence that nothing uses them comes from two places:

- A `git grep` across the nine repos for AWS and cloudsplaining patterns only.
- A statement from the math and ai-config sessions, each about its own repo.

That evidence is self-reported, and it leaves out seven of the nine repos for the other ~38 packages: terraform_ansible, state-ledger, etch-cli, etch-config, ai-devops, the site, and dotfiles itself.

**Concrete failure.** Any script or ansible task that relied on one of these as a transitive dependency fails after the first `-t update` with `ModuleNotFoundError`. An ansible task fails at run time, not at lint time. For example, `ansible.utils.from_xml` / `to_xml` need xmltodict. `ansible-lint --offline` (Measurements) does not execute filters, so its exit 0 does not cover this case.

**Measurement.** In this clone (dotfiles), `git grep -nE '(import|from) +(tabulate|markdown|regex|networkx|termcolor|orjson|boto3|xmltodict|prettytable|argcomplete|cachetools|semantic_version|importlib_metadata|zipp|rdflib|dpath|schema)\b'` finds no code hits. I was not permitted to read the other repos, so they are unmeasured.

**Smallest fix.** Before the plan, run one mechanical grep across all nine repos and quote it in Measurements. Use import names, not distribution names: `hcl2`, `detect_secrets`, `jsonpath_ng`, `pycep`, `spdx_tools`, `junit_xml`, `cached_property`, `policy_sentry`, `click_option_group`, `dockerfile_parse`, `semantic_version`, `importlib_metadata`, plus the plain names. Include the ansible filters `from_xml` and `to_xml`. The grep replaces the "sessions confirmed" sentence. No requirement changes unless it finds something.

## F1.2 Visibility is lost for checkov's whole dependency tree, not just three advisories, and nothing will notice new ones

**Defect.** Design 6 and R8 record three known GHSAs in ADR-0063. After the move, Dependabot sees none of the ~40 packages the formula vendors. That covers advisories that do not exist yet: on boto3, regex, orjson, rdflib and the rest. Homebrew also upgrades checkov with no cooldown. The ADR is a point-in-time list that nothing re-reads. The Brewfile comment points a reader at it, but nothing prompts that reader.

**Concrete failure.** A high-severity advisory lands next month on a vendored package, say bc-python-hcl2. The Dependabot count stays at 0, and an operator reads that 0 as clean.

**Measurement.** pip-audit 2.10.1 (the version already in the lock) accepts `--path PATH  restrict to the specified installation path` (`uv tool run --from pip-audit==2.10.1 pip-audit --help`, Linux). So a check against the formula's own site-packages is a single command. The path would be something like `$(brew --prefix checkov)/libexec/lib/python3.15/site-packages`. That layout is from memory; check it with `ls "$(brew --prefix checkov)/libexec/lib"` on a box that has the formula.

**Smallest fix.**

- Widen R8: the ADR states that the whole vendored tree is unmonitored, not only the three named advisories.
- The ADR names the `pip-audit --path` command as the manual re-check.
- Add a Backlog row if you want it automated later.

N3 (no new install function or update section) still stands.

## F1.3 The lock procedure as measured leaves `exclude-newer` in `uv.lock`, and V1 is checked by hand when a checker already exists

**Defect.** Design 4 gives no procedure. The one command quoted in Measurements writes the cutoff into the lock. After that run, `uv.lock` contains `[options]` / `exclude-newer = "2026-11-14T00:00:00Z"`.

**Concrete failure.** `uv lock --check` then exits 1 (`hint: To update the lockfile, run uv lock`). That is `make check-lock`, a `test-prereqs` prerequisite, so the suite goes red. It is caught, but the cost is a confusing round for the executor. A plain `uv lock` afterwards prints "Global exclude-newer cutoff removed" and keeps 21.15.6 and 26.3. With that second step the lock diff is exactly the 42 removals plus the two updates. I measured that with a tomllib diff of package versions, master against the result.

**Smallest fix.** Write the two-step procedure into Design 4:

1. `uv lock --upgrade-package virtualenv --exclude-newer <cutoff>`.
2. A plain `uv lock`.

This is the same pattern `scripts/refresh-uv-lock.sh:_refresh_cooldown` already uses. Make V1 mechanical with `python3 scripts/uv_lock_cooldown.py verify <master uv.lock> uv.lock <cutoff>` instead of hand-reading PyPI upload times.

## Smaller items

- **F1.4** Design 2 says an Intel mac builds checkov from source. It does not say whether any fleet mac is Intel, or whether the Studio's macOS has a bottle (arm64 bottles exist only for golden_gate, tahoe and sequoia). This matters because of `lib/macos.sh:198`: `brew bundle --file .../Brewfile || return 1`. A failed source build in the main Brewfile therefore skips the `Brewfile.gui` and `Brewfile.devtools` bundles. State the fleet facts. If an Intel mac exists, record the trade-off.
- **F1.5** V3 checks that `command -v checkov` resolves under the brew prefix. The dotfiles rehash hook registers shims for every `versions/*/bin/*`, so if another pyenv version still holds a checkov, the shim survives and V3 fails. checkov would still work: pyenv 2.8.15 fell through to the next `PATH` entry. With a scratch `PYENV_ROOT` holding a `checkov` shim and `PYENV_VERSION` naming a version without it, the call printed the fake brew copy's output, rc 0. Fix: add `ls ~/.pyenv/versions/*/bin/checkov` to V2, or assert on `checkov --version` matching the formula version.
- **F1.6** R2's "alphabetical position" has no test in R7. Either drop the word or accept that it is checked in review only.

No prior `Author response` table exists (this is the first external round), so there are no accepted or not-accepted lines.

None of these findings changes the design. F1.1 needs one grep before the plan. F1.2 and F1.3 are wording in the ADR and in Design 4/V1, and can be fixed at plan time. The design has stopped moving, so another round would cost more than it finds.

Recommend: stop
