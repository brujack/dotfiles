> **Status: DONE**

# pip-venv-audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 13 world-class Python packages to the ansible pyenv venv, migrate 8 math sub-projects and ai-config from unittest to pytest, add ruff format checking to all lint targets, and update all standards documentation.

**Architecture:** T1 updates developer.sh (foundation) and immediately pip installs new packages; T2/T3 update docs in parallel (different repos); T4-T7 migrate math sub-projects sequentially (same repo — avoid concurrent commits); T8 migrates ai-config Makefile (after T3 sets standards); T9 updates dotfiles superpowers README. Each project migration runs `ruff format .` first (one-time format pass, commit separately) then updates the Makefile. Pytest runs `unittest.TestCase` natively — test file `.py` contents are unchanged.

**Tech Stack:** pyenv, pyenv-virtualenv, ruff (venv-managed after this plan), pytest, pytest-cov, pytest-xdist, mypy, pandas, matplotlib, seaborn, ipython, jupyterlab, pre-commit, radon, vulture

## Global Constraints

- Both `setup_ansible()` and `recreate_python_venv()` in `lib/developer.sh` must have identical `_pip_pkgs` arrays (plus macOS-only `mlx`); update both functions in T1
- ruff becomes venv-managed after this plan; `brew uninstall ruff` is a manual one-time user step post-venv-recreate — document it, do not automate
- black and isort are transitive deps of ansible-lint; they appear in `pip list` but are NOT in `_pip_pkgs`; the "remove" goal is satisfied by not adding them explicitly
- One-time format pass per project: `ruff format .` → commit → THEN add `ruff format --check .` to Makefile lint target; skipping this order causes lint failure on pre-existing style divergence
- pytest runs `unittest.TestCase` subclasses natively — `.py` test file contents do NOT change
- Math repo: `~/git-repos/personal/math/`
- ai-config repo: `~/git-repos/personal/ai-config/`
- Coverage `--cov=` module names: factorial→`factorial`, pi→`pi`, e→`e`, fib→`fib`, amicable→`amicable`, collatz→`collatz`, perfect-numbers dir→`perfect_numbers` (underscore), sq→`sq`
- Math sub-projects use cosmic-ray for mutation testing — do NOT change the `mutants:` targets
- After T1, immediately pip install new packages in the ansible venv before T4-T8 run acceptance gates

---

## Session-Level Verification

**Command that proves the whole change works:**

```bash
# 1. Venv has new packages
eval "$(pyenv init -)" && pyenv activate ansible
pip list | grep -E "^(ruff|pytest|mypy|pandas|jupyterlab|radon|vulture) "

# 2. Math sub-projects all pass with pytest runner
for d in factorial fib pi e amicable collatz perfect-numbers sq; do
  echo "=== $d ===" && make -C ~/git-repos/personal/math/$d test
done

# 3. ai-config passes with pytest runner
make -C ~/git-repos/personal/ai-config test

# 4. Dotfiles BATS tests still pass
make test
```

**Expected:** All `make test` commands exit 0; pip list shows all 7 spot-checked packages.

**Edge cases:** `ruff format --check .` passes in every project (verifies format pass was committed first); coverage still ≥90% per-project.

---

### Task 1: Add 13 packages to ansible venv in developer.sh

```yaml-task
id: 1
description: Append ruff, pytest, pytest-cov, pytest-xdist, mypy, pandas, matplotlib, seaborn, ipython, jupyterlab, pre-commit, radon, vulture to both _pip_pkgs arrays in developer.sh; immediately pip install them into the active ansible venv — config change with no testable logic
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "pytest-cov" lib/developer.sh'
    exit_code: 0
  - cmd: 'grep -q "jupyterlab" lib/developer.sh'
    exit_code: 0
  - cmd: 'grep -q "vulture" lib/developer.sh'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/developer.sh
depends_on: []
```

**Files:**

- `lib/developer.sh` — `setup_ansible()` (~line 202) and `recreate_python_venv()` (~line 232)

**Changes — both `_pip_pkgs` arrays become (append 13 packages after `pip-audit`):**

```bash
local _pip_pkgs=(ansible ansible-lint molecule "molecule-plugins[docker]" certbot certbot-dns-cloudflare checkov boto3 docker gmpy2 jmespath mpmath netaddr pylint psutil bpytop HttpPy j2cli wheel shell-gpt pyright cosmic-ray hypothesis passlib scikit-learn scipy bandit pip-audit ruff pytest pytest-cov pytest-xdist mypy pandas matplotlib seaborn ipython jupyterlab pre-commit radon vulture)
[[ -n ${MACOS:-} ]] && _pip_pkgs+=(mlx)
```

**Steps:**

- [ ] Read `lib/developer.sh` lines 195-240 to confirm current array content in both functions
- [ ] Edit `setup_ansible()` `_pip_pkgs` to append the 13 new packages after `pip-audit`
- [ ] Edit `recreate_python_venv()` `_pip_pkgs` identically
- [ ] Confirm both arrays match (only difference: macOS `mlx` guard at the end)
- [ ] Run `make lint` — shellcheck must pass
- [ ] Run `make test` — all BATS tests must pass
- [ ] Immediately pip install the new packages into the active ansible venv:
  ```bash
  eval "$(pyenv init -)" && pyenv activate ansible && \
    pip install ruff pytest pytest-cov pytest-xdist mypy pandas matplotlib seaborn \
    ipython jupyterlab pre-commit radon vulture
  ```
- [ ] Invoke `caveman:caveman-commit` to generate commit message
- [ ] `git add lib/developer.sh && git commit`

**Interfaces:**

- Consumes: nothing (foundation task)
- Produces: `developer.sh` with 13 new packages in both arrays; ansible venv with pytest/ruff/mypy/data science stack immediately installed

---

### Task 2: Update dotfiles CLAUDE.md

```yaml-task
id: 2
description: Add ansible venv package list section to dotfiles CLAUDE.md and note ruff is now venv-managed — docs-only, no behavior change
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "pytest" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -q "venv-managed" CLAUDE.md'
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
depends_on: [1]
parallel_group: docs
```

**Files:**

- `CLAUDE.md` — Key Conventions section, Python environments paragraph

**Changes:**

Search for "Python environments managed via pyenv" in CLAUDE.md. Add sub-bullets after that line:

```markdown
- **Ansible venv packages (explicit):** ansible, ansible-lint, molecule, molecule-plugins[docker], certbot, certbot-dns-cloudflare, checkov, boto3, docker, gmpy2, jmespath, mpmath, netaddr, pylint, psutil, bpytop, HttpPy, j2cli, wheel, shell-gpt, pyright, cosmic-ray, hypothesis, passlib, scikit-learn, scipy, bandit, pip-audit, ruff, pytest, pytest-cov, pytest-xdist, mypy, pandas, matplotlib, seaborn, ipython, jupyterlab, pre-commit, radon, vulture (+macOS: mlx)
- **ruff is venv-managed** (not brew); run `brew uninstall ruff` once after venv recreate to remove the legacy brew install
- **Test runner:** `pytest` — runs `unittest.TestCase` tests natively; test file contents do not change
```

**Steps:**

- [ ] Search CLAUDE.md for "pyenv" or "ansible venv" to locate the right section
- [ ] Add the package list and ruff note sub-bullets
- [ ] Invoke `caveman:caveman-commit` to generate commit message
- [ ] `git add CLAUDE.md && git commit`

**Interfaces:**

- Consumes: T1's package list (which 13 packages were added)
- Produces: CLAUDE.md documenting current venv state and ruff brew migration

---

### Task 3: Update python.md standards in ai-config

```yaml-task
id: 3
description: Update ai-config/.claude/standards/python.md with pytest as standard test runner, ruff format checking, mypy, ruff-replaces-black/isort note, and data science tools availability — docs-only, no behavior change
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "pytest" ~/git-repos/personal/ai-config/.claude/standards/python.md'
    exit_code: 0
  - cmd: 'grep -q "ruff format" ~/git-repos/personal/ai-config/.claude/standards/python.md'
    exit_code: 0
  - cmd: 'grep -q "mypy" ~/git-repos/personal/ai-config/.claude/standards/python.md'
    exit_code: 0
max_retries: 3
files_touched:
  - ~/git-repos/personal/ai-config/.claude/standards/python.md
depends_on: [1]
parallel_group: docs
```

**Files:**

- `~/git-repos/personal/ai-config/.claude/standards/python.md`

**Work in:** `~/git-repos/personal/ai-config/`

**Changes — update/add these sections:**

**Linting section** — add after `ruff check .`:

```markdown
**Formatting:** `ruff format --check .` (check); `ruff format .` (apply). Black-compatible by default.

**Import sorting:** `ruff check --select I .` — handled by ruff; do not use separate isort.
```

**Test runner** — update or add section:

```markdown
### Test Runner

`pytest` (replaces `python3 -m unittest`).

- pytest discovers and runs `unittest.TestCase` subclasses natively — test file contents unchanged
- New tests written pytest-style going forward
- Invocation: `pytest <test_file>.py -v`
```

**Coverage** — update:

```markdown
### Coverage

`pytest --cov=<module> --cov-report=term-missing --cov-fail-under=90 <test_file>.py`

Replaces `python3 -m coverage run -m unittest ...` + `coverage report`.
```

**Type checking** — add mypy:

```markdown
### Type Checking

- **pyright** — fast, IDE-integrated (`pyright .`)
- **mypy** — stricter inference, CI gate (`mypy .`)
- Both coexist; they catch different issues
```

**Add Toolchain note:**

```markdown
### Toolchain

- `ruff` replaces both `black` (formatting) and `isort` (import sorting) — do NOT install black/isort in new venvs
- `radon cc -s .` — cyclomatic complexity (advisory)
- `vulture .` — dead code detection (advisory)
```

**Add Data science note:**

```markdown
### Data Science (ansible venv)

Available: pandas, matplotlib, seaborn, ipython, jupyterlab
```

**Steps:**

- [ ] `cd ~/git-repos/personal/ai-config/`
- [ ] Read `~/.claude/standards/python.md` (= `ai-config/.claude/standards/python.md`) for current content
- [ ] Update Linting section with format and import-sort notes
- [ ] Update or add Test Runner section with pytest
- [ ] Update Coverage section with pytest-cov invocation
- [ ] Add/update Type Checking to include mypy
- [ ] Add Toolchain note section
- [ ] Add Data Science section
- [ ] Invoke `caveman:caveman-commit` to generate commit message
- [ ] Commit in the ai-config repo

**Interfaces:**

- Consumes: T1's package list (which tools are now in the venv)
- Produces: python.md as the updated canonical Python standards reference

---

### Task 4: Migrate math factorial and fib to pytest

```yaml-task
id: 4
description: Run ruff format pass then update lint/test/coverage Makefile targets to ruff format check and pytest for factorial and fib sub-projects; commits to math repo
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "ruff format --check" ~/git-repos/personal/math/factorial/Makefile'
    exit_code: 0
  - cmd: 'grep -q "pytest test_factorial.py" ~/git-repos/personal/math/factorial/Makefile'
    exit_code: 0
  - cmd: make -C ~/git-repos/personal/math/factorial test
    exit_code: 0
  - cmd: 'grep -q "ruff format --check" ~/git-repos/personal/math/fib/Makefile'
    exit_code: 0
  - cmd: 'grep -q "pytest test_fib.py" ~/git-repos/personal/math/fib/Makefile'
    exit_code: 0
  - cmd: make -C ~/git-repos/personal/math/fib test
    exit_code: 0
max_retries: 3
files_touched:
  - ~/git-repos/personal/math/factorial/Makefile
  - ~/git-repos/personal/math/fib/Makefile
depends_on: [1]
```

**Files:**

- `~/git-repos/personal/math/factorial/Makefile`
- `~/git-repos/personal/math/fib/Makefile`

**Work in:** `~/git-repos/personal/math/`

**Pattern (apply to both sub-projects; substitute `factorial`/`fib` as appropriate):**

**Step A — format pass (MUST come before Makefile edit):**

```bash
cd ~/git-repos/personal/math/factorial
ruff format .
git -C ~/git-repos/personal/math/factorial diff
# If changes exist:
git -C ~/git-repos/personal/math/factorial add factorial.py test_factorial.py
git -C ~/git-repos/personal/math/factorial commit -m "style(factorial): ruff format pass"
```

**Step B — Makefile changes:**

`lint:` recipe — add second line:

```makefile
lint:
	ruff check .
	ruff format --check .
```

`test:` recipe — change runner (note `.py` extension added):

```makefile
test: lint
	pytest test_factorial.py -v
```

`coverage:` recipe — replace two lines with one:

```makefile
coverage:
	pytest --cov=factorial --cov-report=term-missing --cov-fail-under=90 test_factorial.py
```

**Steps:**

- [ ] `cd ~/git-repos/personal/math/factorial && ruff format . && git diff`
- [ ] If format changed files: `git add factorial.py test_factorial.py && git commit -m "style(factorial): ruff format pass"`
- [ ] Edit `factorial/Makefile`: add `ruff format --check .` to lint, change test to `pytest test_factorial.py -v`, replace coverage two-liner with `pytest --cov=factorial ...`
- [ ] `make -C factorial lint` — must pass
- [ ] `make -C factorial test` — must pass
- [ ] `git -C ~/git-repos/personal/math/ add factorial/Makefile && git commit`
- [ ] Repeat all steps for `fib/` (module: `fib`, test file: `test_fib.py`, coverage: `--cov=fib`)
- [ ] Invoke `caveman:caveman-commit` before each commit

**Interfaces:**

- Consumes: T1 (pytest installed in venv)
- Produces: factorial and fib Makefiles using pytest runner and ruff format check

---

### Task 5: Migrate math pi and e to pytest

```yaml-task
id: 5
description: Run ruff format pass then update lint/test/coverage Makefile targets to ruff format check and pytest for pi and e sub-projects; commits to math repo
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "ruff format --check" ~/git-repos/personal/math/pi/Makefile'
    exit_code: 0
  - cmd: 'grep -q "pytest test_pi.py" ~/git-repos/personal/math/pi/Makefile'
    exit_code: 0
  - cmd: make -C ~/git-repos/personal/math/pi test
    exit_code: 0
  - cmd: 'grep -q "ruff format --check" ~/git-repos/personal/math/e/Makefile'
    exit_code: 0
  - cmd: 'grep -q "pytest test_e.py" ~/git-repos/personal/math/e/Makefile'
    exit_code: 0
  - cmd: make -C ~/git-repos/personal/math/e test
    exit_code: 0
max_retries: 3
files_touched:
  - ~/git-repos/personal/math/pi/Makefile
  - ~/git-repos/personal/math/e/Makefile
depends_on: [4]
```

**Files:**

- `~/git-repos/personal/math/pi/Makefile`
- `~/git-repos/personal/math/e/Makefile`

**Work in:** `~/git-repos/personal/math/`

**Apply the same format-pass-then-Makefile-edit pattern from T4 to both `pi/` and `e/`:**

For `pi/`:

- Source files to format: `pi.py test_pi.py` (and any other `.py` in the dir)
- Test runner: `pytest test_pi.py -v`
- Coverage: `pytest --cov=pi --cov-report=term-missing --cov-fail-under=90 test_pi.py`

For `e/`:

- Source files to format: `e.py test_e.py`
- Test runner: `pytest test_e.py -v`
- Coverage: `pytest --cov=e --cov-report=term-missing --cov-fail-under=90 test_e.py`

**Steps:**

- [ ] Format pass for `pi/`: `cd pi && ruff format . && git diff`; commit if changed
- [ ] Edit `pi/Makefile`: lint += `ruff format --check .`, test → pytest, coverage → pytest --cov
- [ ] `make -C pi lint && make -C pi test` — must pass
- [ ] `git add pi/Makefile && git commit`
- [ ] Format pass for `e/`: `cd e && ruff format . && git diff`; commit if changed
- [ ] Edit `e/Makefile`: lint += `ruff format --check .`, test → pytest, coverage → pytest --cov
- [ ] `make -C e lint && make -C e test` — must pass
- [ ] `git add e/Makefile && git commit`
- [ ] Invoke `caveman:caveman-commit` before each commit

**Interfaces:**

- Consumes: T4 completed (sequential in math repo to avoid commit conflicts)
- Produces: pi and e Makefiles using pytest runner and ruff format check

---

### Task 6: Migrate math amicable and collatz to pytest

```yaml-task
id: 6
description: Run ruff format pass then update lint/test/coverage Makefile targets to ruff format check and pytest for amicable and collatz sub-projects; commits to math repo
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "ruff format --check" ~/git-repos/personal/math/amicable/Makefile'
    exit_code: 0
  - cmd: 'grep -q "pytest test_amicable.py" ~/git-repos/personal/math/amicable/Makefile'
    exit_code: 0
  - cmd: make -C ~/git-repos/personal/math/amicable test
    exit_code: 0
  - cmd: 'grep -q "ruff format --check" ~/git-repos/personal/math/collatz/Makefile'
    exit_code: 0
  - cmd: 'grep -q "pytest test_collatz.py" ~/git-repos/personal/math/collatz/Makefile'
    exit_code: 0
  - cmd: make -C ~/git-repos/personal/math/collatz test
    exit_code: 0
max_retries: 3
files_touched:
  - ~/git-repos/personal/math/amicable/Makefile
  - ~/git-repos/personal/math/collatz/Makefile
depends_on: [5]
```

**Files:**

- `~/git-repos/personal/math/amicable/Makefile`
- `~/git-repos/personal/math/collatz/Makefile`

**Work in:** `~/git-repos/personal/math/`

**Apply the same format-pass-then-Makefile-edit pattern from T4:**

For `amicable/`:

- Test runner: `pytest test_amicable.py -v`
- Coverage: `pytest --cov=amicable --cov-report=term-missing --cov-fail-under=90 test_amicable.py`

For `collatz/`:

- Test runner: `pytest test_collatz.py -v`
- Coverage: `pytest --cov=collatz --cov-report=term-missing --cov-fail-under=90 test_collatz.py`

**Steps:**

- [ ] Format pass for `amicable/`: `ruff format . && git diff`; commit if changed
- [ ] Edit `amicable/Makefile`: lint += `ruff format --check .`, test → pytest, coverage → pytest --cov
- [ ] `make -C amicable lint && make -C amicable test` — must pass
- [ ] `git add amicable/Makefile && git commit`
- [ ] Format pass for `collatz/`: `ruff format . && git diff`; commit if changed
- [ ] Edit `collatz/Makefile`: lint += `ruff format --check .`, test → pytest, coverage → pytest --cov
- [ ] `make -C collatz lint && make -C collatz test` — must pass
- [ ] `git add collatz/Makefile && git commit`
- [ ] Invoke `caveman:caveman-commit` before each commit

**Interfaces:**

- Consumes: T5 completed (sequential in math repo)
- Produces: amicable and collatz Makefiles using pytest runner and ruff format check

---

### Task 7: Migrate math perfect-numbers and sq to pytest

```yaml-task
id: 7
description: Run ruff format pass then update lint/test/coverage Makefile targets to ruff format check and pytest for perfect-numbers and sq sub-projects; commits to math repo
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "ruff format --check" ~/git-repos/personal/math/perfect-numbers/Makefile'
    exit_code: 0
  - cmd: 'grep -q "pytest test_perfect_numbers.py" ~/git-repos/personal/math/perfect-numbers/Makefile'
    exit_code: 0
  - cmd: make -C ~/git-repos/personal/math/perfect-numbers test
    exit_code: 0
  - cmd: 'grep -q "ruff format --check" ~/git-repos/personal/math/sq/Makefile'
    exit_code: 0
  - cmd: 'grep -q "pytest test_sq.py" ~/git-repos/personal/math/sq/Makefile'
    exit_code: 0
  - cmd: make -C ~/git-repos/personal/math/sq test
    exit_code: 0
max_retries: 3
files_touched:
  - ~/git-repos/personal/math/perfect-numbers/Makefile
  - ~/git-repos/personal/math/sq/Makefile
depends_on: [6]
```

**Files:**

- `~/git-repos/personal/math/perfect-numbers/Makefile`
- `~/git-repos/personal/math/sq/Makefile`

**Work in:** `~/git-repos/personal/math/`

**Apply the same format-pass-then-Makefile-edit pattern from T4:**

For `perfect-numbers/` (directory has hyphen; Python files use underscore):

- Source files: `perfect_numbers.py test_perfect_numbers.py`
- Test runner: `pytest test_perfect_numbers.py -v`
- Coverage: `pytest --cov=perfect_numbers --cov-report=term-missing --cov-fail-under=90 test_perfect_numbers.py`

For `sq/` (note: current coverage uses `coverage run` without `python3 -m`; replace both lines):

- Test runner: `pytest test_sq.py -v`
- Coverage: `pytest --cov=sq --cov-report=term-missing --cov-fail-under=90 test_sq.py`

**Current sq coverage recipe (two lines to replace):**

```makefile
coverage:
	coverage run -m unittest test_sq -v
	coverage report -m --fail-under=90
```

**Becomes:**

```makefile
coverage:
	pytest --cov=sq --cov-report=term-missing --cov-fail-under=90 test_sq.py
```

**Steps:**

- [ ] Format pass for `perfect-numbers/`: `ruff format . && git diff`; commit if changed
- [ ] Edit `perfect-numbers/Makefile`: lint += `ruff format --check .`, test → pytest, coverage → pytest --cov=perfect_numbers
- [ ] `make -C perfect-numbers lint && make -C perfect-numbers test` — must pass
- [ ] `git add perfect-numbers/Makefile && git commit`
- [ ] Format pass for `sq/`: `ruff format . && git diff`; commit if changed
- [ ] Edit `sq/Makefile`: lint += `ruff format --check .`, test → pytest, coverage → pytest --cov=sq; replace BOTH existing coverage lines with single pytest --cov line
- [ ] `make -C sq lint && make -C sq test` — must pass
- [ ] `git add sq/Makefile && git commit`
- [ ] Invoke `caveman:caveman-commit` before each commit

**Interfaces:**

- Consumes: T6 completed (sequential in math repo)
- Produces: all 8 math sub-projects migrated to pytest and ruff format check

---

### Task 8: Migrate ai-config Makefile to pytest

```yaml-task
id: 8
description: Run ruff format pass on ai-config scripts and tests, then update Makefile lint (remove conditional ruff guard, add ruff format check), test (pytest), and coverage (pytest --cov) targets in the ai-config repo
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "ruff format --check" ~/git-repos/personal/ai-config/Makefile'
    exit_code: 0
  - cmd: 'grep -q "pytest tests/" ~/git-repos/personal/ai-config/Makefile'
    exit_code: 0
  - cmd: make -C ~/git-repos/personal/ai-config test
    exit_code: 0
max_retries: 3
files_touched:
  - ~/git-repos/personal/ai-config/Makefile
depends_on: [3]
```

**Files:**

- `~/git-repos/personal/ai-config/Makefile`

**Work in:** `~/git-repos/personal/ai-config/`

**Step A — format pass first:**

```bash
cd ~/git-repos/personal/ai-config
ruff format .claude/scripts/ tests/
git diff
# If changes:
git add .claude/scripts/ tests/
git commit -m "style(ai-config): ruff format pass"
```

**Step B — Makefile changes:**

**`lint:` section** — replace the conditional ruff line with two unconditional lines:

Current (remove this line):

```makefile
	@command -v ruff >/dev/null && ruff check .claude/scripts/ tests/ || printf "ruff not installed: pip install ruff (skipped)\n" >&2
```

New (add these two lines, keep the shellcheck line):

```makefile
	ruff check .claude/scripts/ tests/
	ruff format --check .claude/scripts/ tests/
```

**`test:` section** — replace the unittest discover line (keep `bats tests/` and all dependencies):

Current:

```makefile
	python3 -m unittest discover -s tests -p 'test_*.py' -v
```

New:

```makefile
	pytest tests/ -v
```

**`coverage:` section** — remove the coverage guard and replace two lines with one:

Current (remove all three lines):

```makefile
	@command -v coverage >/dev/null || { printf "coverage not installed: pip install coverage\n" >&2; exit 1; }
	coverage run --source=.claude/scripts -m unittest discover -s tests -p 'test_*.py'
	coverage report -m --fail-under=90
```

New (single line):

```makefile
	pytest --cov=.claude/scripts --cov-report=term-missing --cov-fail-under=90 tests/
```

**Steps:**

- [ ] `cd ~/git-repos/personal/ai-config/`
- [ ] `ruff format .claude/scripts/ tests/ && git diff` — inspect changes
- [ ] If format changed files: `git add .claude/scripts/ tests/ && git commit -m "style(ai-config): ruff format pass"`
- [ ] Read `Makefile` lines 20-40 to confirm current lint/test/coverage structure
- [ ] Edit `lint:` — replace conditional ruff line with unconditional `ruff check` + `ruff format --check` lines; keep shellcheck line
- [ ] Edit `test:` — replace `python3 -m unittest discover ...` with `pytest tests/ -v`; keep `bats tests/` and all target dependencies
- [ ] Edit `coverage:` — remove guard + two lines; add single `pytest --cov=.claude/scripts ...` line
- [ ] `make lint` — must pass (ruff check, ruff format --check, shellcheck)
- [ ] `make test` — must pass (bats + pytest)
- [ ] Invoke `caveman:caveman-commit` to generate commit message
- [ ] `git add Makefile && git commit`

**Interfaces:**

- Consumes: T3 (python.md updated to show new standards); T1 (pytest in venv)
- Produces: ai-config Makefile using pytest runner, unconditional ruff, and ruff format check

---

### Task 9: Update dotfiles superpowers README

```yaml-task
id: 9
description: Move pip-venv-audit from backlog to All Plans table in docs/superpowers/README.md with status In Progress and link to plan file — docs-only, no behavior change
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "pip-venv-audit" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'grep -q "In Progress" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'grep -q "2026-06-19-pip-venv-audit" docs/superpowers/README.md'
    exit_code: 0
max_retries: 3
files_touched:
  - docs/superpowers/README.md
depends_on: [1, 2]
```

**Files:**

- `docs/superpowers/README.md`

**Changes:**

1. Remove the pip-venv-audit entry from the Backlog table.

2. Add a row to the All Plans table:

```markdown
| 2026-06-19 | [pip-venv-audit](plans/2026-06-19-pip-venv-audit.md) | [spec](specs/2026-06-19-pip-venv-audit-design.md) | In Progress |
```

**Steps:**

- [ ] Read `docs/superpowers/README.md` to see current state
- [ ] Remove the `pip-venv-audit` row from the Backlog section
- [ ] Add the row to the All Plans table (date 2026-06-19, both plan and spec links, status In Progress)
- [ ] Invoke `caveman:caveman-commit` to generate commit message
- [ ] `git add docs/superpowers/README.md && git commit`

**Interfaces:**

- Consumes: T2 (CLAUDE.md updated); T1 (plan commits are underway)
- Produces: README.md with pip-venv-audit tracked as In Progress in All Plans
