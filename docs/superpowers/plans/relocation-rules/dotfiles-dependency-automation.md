### renovate.json inlines the shared preset (private-repo visibility)

lead: none

- Inline the shared Renovate preset into `renovate.json`, don't `extends` it — ai-config is private, dotfiles public, and an unfetchable `extends` throws `config-validation` at `initRepo` and silently abandons the repo (measured: `extends` gave 8 errors/0 extractions; inlined gave 0/1). ADR-0010's "each repo extends the preset" no longer holds.
- Hand-sync `extends`/`schedule`/`labels`/`packageRules` with canonical `ai-config/renovate-presets/default.json` — nothing detects drift between the copies.
  trigger: edit | renovate.json, extends, packageRules
  covers:
  - a: "Measured 2026-08-23 with config as the only variable: the re"
  - b: "`ai-config/renovate-presets/default.json` stays canonical; k"

### Renovate confirmed working: pinDigests and auto-merge in production

lead: none

- Treat Renovate as confirmed running here, not merely configured: #240 pinned every `actions/checkout` ref to a digest and auto-merged, #241 raised a major bump and did not — `packageRules` working as written — and `pinDigests: true` moved this repo from 0-of-6 pinned refs to 6-of-6.
- Do not cite the `mode=silent` finding as a live constraint without re-reading a current Mend job log — silent mode is no longer in force here (a created branch is the one thing it forbids).
  trigger: edit | renovate.json, packageRules, pinDigests, mode=silent
  covers:
  - a: "Do not cite the silent-mode finding as a live constraint wit"
  - b: (none — verdict complete)

### The zero-PR oracle was structurally unfalsifiable under silent mode

lead: none

- Never conclude Renovate is inactive from a zero-PR count alone: under `mode=silent` zero was the only reachable value, so every "not running" verdict built on it was unprovable either way.
- Before concluding anything from what a mechanism has not done, establish what it was even permitted to do — this holds even once silent mode is lifted elsewhere.
  trigger: conclude | zero-PR count, mode=silent, Renovate liveness
  covers:
  - a: "Under silent mode no repo could ever author a PR, so zero wa"
  - b: "The lesson survives the lift: establish what a mechanism is "

### pip_requirements deliberately absent from enabledManagers

lead: none

- Do not add `pip_requirements` to `renovate.json`'s `enabledManagers` — deliberately absent. Its pattern allows only one suffix after "requirements", so of five generated renderings only `requirements-ci.txt` matches, by luck not design; `tests/setup_env/requirements_ci.bats` pins it since a rename would silently widen scope.
- All five renderings are generated from `uv.lock`; enabling the manager would raise PRs against generated files `check-requirements-ci` fails. The real declaration is `pyproject.toml`, owned by `pep621`.
  trigger: edit | renovate.json, enabledManagers, requirements-*.txt
  covers:
  - a: "Measured against all five renderings: only `requirements-ci."
  - b: "**`pip_requirements` is deliberately absent from `enabledMan"

### Dependabot: security auto-PRs off, vulnerability alerts on (fleet-wide)

lead: none

- Keep Dependabot security auto-PRs OFF, vulnerability alerts ON, fleet-wide across all 18 non-archived repos (decided 2026-08-21) — a GitHub repo-Settings toggle no tracked file captures (`dependabot.yml` governs version updates, not security), so absence from any file is not evidence it's unset.
- Rationale: alerts are the signal, auto-PRs an unreviewed write path — #227 auto-merged an unattended lockfile edit because it passed CI. Don't re-enable auto-PRs without deliberately re-opening that path; 16 of 18 repos had alerts off entirely before this decision.
  trigger: edit | GitHub repo Settings, vulnerability-alerts, automated-security-fixes
  covers:
  - a: (none retained above pointer)
  - b: "**Decided 2026-08-21, fleet-wide across all 18 non-archived "

### Dependabot: mechanical details (repo-wide toggle, ordering)

lead: none

- `automated-security-fixes` is repo-wide — there is no per-ecosystem toggle, so "turn Dependabot off for Python only" is not expressible.
- The flag cannot be cleared while alerts are off: `DELETE automated-security-fixes` 422s "Vulnerability alerts must be enabled…" on a repo left inert but latently armed. Always call `PUT vulnerability-alerts` first, then `DELETE automated-security-fixes` — never the reverse.
  trigger: call | GitHub API, PUT vulnerability-alerts, DELETE automated-security-fixes
  covers:
  - a: "- **`automated-security-fixes` is repo-wide — GitHub offers "
  - b: "Order the calls: `PUT vulnerability-alerts`, then `DELETE aut"

### Consequence: Python has no automated dependency update path

lead: none

- Do not assume Python packages get automated update PRs here: Dependabot's write path is closed (auto-PRs off) and Renovate manages no Python anywhere (`pep621` enabled in no repo), including this one, despite `pyproject.toml`/`uv.lock` living here — vulnerability alerts will fire with nothing proposing a fix.
  trigger: assume | pyproject.toml, uv.lock, Python dependency updates
  covers:
  - a: (none retained above pointer)
  - b: (none — verdict complete)
