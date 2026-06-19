# pip-venv-audit Design

## Context

The ansible pyenv virtualenv is now a "do-all" Python environment covering Ansible/DevOps,
data science/ML, CLI tool development, and general Python scripting. The venv grew
organically and has gaps versus world-class Python practice: no pytest, no ruff in-venv,
redundant tools (black/isort superseded by ruff), missing data science stack, and all
projects running `python3 -m unittest` instead of pytest.

Both the math repo (8 Python sub-projects) and ai-config repo use `ruff check` for
linting (already the standard) but `python3 -m unittest` for testing. Test files use
`unittest.TestCase` — pytest runs these natively, so test file contents do not change.

## Goals

1. Add missing world-class Python tooling to the ansible venv
2. Remove redundant tools (black, isort) — ruff covers both
3. Move ruff from brew to venv for consistent versioning
4. Migrate all Python projects to pytest as the standard test runner
5. Update python.md standards and relevant CLAUDE.md files

## Venv Changes (developer.sh)

### Add

| Package        | Purpose                                    |
| -------------- | ------------------------------------------ |
| `ruff`         | Linter + formatter (replaces black, isort) |
| `pytest`       | Standard test runner                       |
| `pytest-cov`   | Coverage plugin for pytest                 |
| `pytest-xdist` | Parallel test execution                    |
| `mypy`         | Strict type checker (complements pyright)  |
| `pandas`       | Data analysis                              |
| `matplotlib`   | Data visualization                         |
| `seaborn`      | Statistical visualization                  |
| `ipython`      | Interactive Python shell                   |
| `jupyterlab`   | Notebook environment                       |
| `pre-commit`   | Git hook management                        |
| `radon`        | Cyclomatic complexity metrics              |
| `vulture`      | Dead code detection                        |

### Remove

| Package | Reason                                                                        |
| ------- | ----------------------------------------------------------------------------- |
| `black` | `ruff format` is black-compatible and replaces it; not called in any Makefile |
| `isort` | `ruff check --select I` handles import sorting; not called in any Makefile    |

Both are present in the venv but not invoked by any Makefile in math or ai-config.

### Brew

`ruff` is manually installed via brew (not tracked in Brewfile). After venv recreate,
run once:

```bash
brew uninstall ruff
```

Document in dotfiles CLAUDE.md that ruff is venv-managed going forward.

## Test Runner Migration

### Pattern (math sub-projects)

Applied to: factorial, pi, e, fib, amicable, collatz, perfect-numbers, sq.

```makefile
# Before
test: lint
	python3 -m unittest test_<module> -v
coverage:
	python3 -m coverage run -m unittest test_<module>
	python3 -m coverage report --fail-under=90

# After
test: lint
	pytest test_<module>.py -v
coverage:
	pytest --cov=<module> --cov-report=term-missing --cov-fail-under=90 test_<module>.py
```

Test file contents are **unchanged** — pytest discovers and runs `unittest.TestCase`
subclasses natively. New tests written pytest-style going forward.

### ai-config

```makefile
# Before
test: lint typecheck ...
	python3 -m unittest discover -s tests -p 'test_*.py' -v
coverage:
	coverage run --source=.claude/scripts -m unittest discover -s tests -p 'test_*.py'
	coverage report -m --fail-under=90

# After
test: lint typecheck ...
	pytest tests/ -v
coverage:
	pytest --cov=.claude/scripts --cov-report=term-missing --cov-fail-under=90 tests/
```

### goldbach

No Python Makefile — only goldbach-rs. No changes required.

## Standards Updates

### ~/.claude/standards/python.md

- **Linting:** `ruff check .` (unchanged)
- **Formatting:** Add `ruff format --check .` to lint target; `ruff format .` to apply
- **Import sorting:** `ruff check --select I .` — handled by ruff, no separate isort needed
- **Test runner:** `pytest` (replaces `python3 -m unittest`)
- **Coverage:** `pytest --cov=<module> --cov-report=term-missing --cov-fail-under=90`
- **Type checking:** `pyright` (fast, IDE-integrated) + `mypy` (stricter inference, CI gate)
- **Quality (advisory):** `radon cc -s .` for complexity; `vulture .` for dead code
- **Toolchain note:** `ruff` replaces `black` and `isort` — do not install black/isort in new venvs
- **Data science:** pandas, matplotlib, seaborn, ipython, jupyterlab available in ansible venv

### dotfiles/CLAUDE.md

- Update ansible venv package list to reflect additions and removals
- Note that ruff is venv-managed (not brew); `brew uninstall ruff` required once

### math/CLAUDE.md (if exists) and ai-config/CLAUDE.md

- Update testing commands to `pytest` pattern
- Update coverage commands to `pytest --cov` pattern

## Acceptance Criteria

- [ ] `pip list | grep ruff` shows ruff in venv
- [ ] `pip list | grep black` returns nothing
- [ ] `pip list | grep isort` returns nothing
- [ ] `pytest --version` works in ansible venv
- [ ] Each math sub-project: `make test` passes with pytest runner
- [ ] ai-config: `make test` passes with pytest runner
- [ ] `ruff format --check .` added to lint targets and passes
- [ ] python.md updated with new standards
- [ ] dotfiles CLAUDE.md updated
- [ ] `brew list ruff` returns nothing (after manual uninstall)

## Implementation Notes

- `recreate_python_venv` in developer.sh is the canonical place for venv package lists;
  both `setup_ansible()` and `recreate_python_venv()` must stay in sync (already enforced
  by the existing pattern)
- pytest-cov and coverage can coexist; existing `coverage` package stays for any scripts
  that invoke it directly
- mypy and pyright can coexist; they catch different issues and complement each other
- ruff format is black-compatible by default — no configuration needed to match prior
  black output
- **One-time format pass required per project before adding `ruff format --check .` to
  lint:** run `ruff format .` in each sub-project first, commit the diff, then add the
  check to the Makefile lint target. Otherwise `make lint` fails immediately on
  pre-existing style divergence. Do this as the first task in each project's PR.
