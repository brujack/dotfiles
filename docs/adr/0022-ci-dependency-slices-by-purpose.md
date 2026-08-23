# ADR-0022: CI dependency renderings are sliced by purpose, not by CI-versus-local

## Status

Accepted — 2026-08-23

## Context

Five repos consume this repo's `uv.lock` for their CI Python dependencies, via generated
`requirements-*.txt` renderings. The first rendering carried the whole `test-lint` group:
80 pins. `etch-cli` runs exactly three tools — `ruff`, `pytest`, `pytest-cov` — and so
installed **77 packages it never runs** on every PR.

The obvious remedy was a `ci` group meaning "test-lint minus whatever no CI invokes".
Measured, it is nearly worthless: dropping every genuinely-uninvoked tool takes the
rendering 80 → 73 pins, so the consumer still installs 70 it does not run.

A second framing was tried and also rejected: that this was a **deletion** problem. It is
not. The packages are legitimately in the venv because a human might use any of them; the
defect was that CI inherited the venv's *shape*. Nothing needed removing from anywhere — a
job needed to stop installing what it does not run.

## Decision

Slice the renderings by **purpose**, derived from the fleet's actual CI job layout rather
than from any one consumer's needs:

| group | rendering | pins | what it is |
| --- | --- | --- | --- |
| `test-lint` | `requirements-ci.txt` | 80 | the full local/dev test set |
| `runtime` | `requirements-runtime-ci.txt` | 229 | `terraform_ansible` — ansible/molecule, no test tooling |
| `ci-test` | `requirements-ci-test.txt` | 19 | exactly what a per-PR `test`/`lint` job runs |
| `ci-mutation` | `requirements-ci-mutation.txt` | 30 | exactly what a mutation job runs |
| `ci-audit` | `requirements-ci-audit.txt` | 28 | dependency auditing |

`ci-test`'s membership is decided by measurement, not preference: `ai-config`'s `ci.yml`
`test` job and every `math` `*-py.yml` `test` job run `ruff`, `pytest`, `pytest-cov`,
`hypothesis`, `pyright` and `mypy` **in one job**, so all six belong.

Two boundary calls, both made on measured cost:

- **`pyright` and `mypy` fold in** (+3 and +6 pins, 11 → 19). Cheap relative to a third
  group and a third render target.
- **`pip-audit` splits out** (+24 pins, more than doubling `ci-test`). Separated on
  **purpose** — auditing is not test/lint, matching what `rust.md` records for `cargo audit`
  — with the cost making the distinction pay rather than motivating it. A repo running a
  linter and a test suite should not install an SBOM library to do it.
- **`hypothesis` folds in at +2** despite `etch-cli` not using it, on the same
  cheaper-than-the-machinery reasoning.

The rule is stated in `pyproject.toml` above the group, not left to reviewers.

## Consequences

- `etch-cli` installs **19 pins instead of 80** — 61 fewer packages per PR.
- The per-PR path stops carrying `cosmic-ray`'s closure: an ORM, an HTTP client and a git
  library (`sqlalchemy`, `aiohttp`, `gitpython`, `yarl`, `frozenlist`, `multidict`) to run a
  linter.
- All five renderings are `uv export` slices of one lock, so they compose with **zero version
  disagreements — by construction, not by luck**. Measured: 268 packages across five files,
  0 conflicts. A consumer needing two installs them as two `pip install -r` lines, required
  anyway since `--require-hashes` forbids mixing a hashed file with a loose extra.
- **The predicted failure is erosion** — a repo needs one more tool, it lands in `ci-test`
  because that is where tools go, and in a year `ci-test` is the union again. Two tests guard
  it: one fails if any mutation whale appears in `ci-test`, one fails if `ci-test` stops
  being materially smaller than the full rendering. Both mutation-verified.
- Nothing is deleted. The lock is unchanged at 269 packages and no machine's venv moves.

## Related

- `pyproject.toml` — the groups and the boundary rule
- `scripts/sync-requirements-ci.sh` — renders all five
- `tests/setup_env/requirements_ci.bats` — the boundary and drift guards
- ADR-0010 (Renovate replacing Dependabot) — its "each repo extends a shared preset" clause
  no longer holds; see CLAUDE.md's Dependency Automation section
