# Python PR Review Reference

## Security
- No `eval()`, `exec()`, or `pickle.loads()` on untrusted data
- No `subprocess` calls with `shell=True` and unsanitised input
- No hardcoded secrets — check for `password =`, `api_key =`, `token =` literals
- SQL: parameterised queries only — no f-string or %-format SQL construction
- File paths: validate and sanitise before use (path traversal risk)

## TDD / Tests
- `pytest` is the standard — `python -m pytest --tb=short` must pass
- New functions must have corresponding tests in `tests/` or `test_*.py`
- Coverage: `pytest --cov` if configured; flag untested branches in new code
- Fixtures and mocks used appropriately — no real network/filesystem calls in unit tests

## Code Quality
- `ruff check` or `flake8` — no linting errors
- `mypy` or `pyright` type checking if the project uses type hints
- No bare `except:` — catch specific exceptions
- No mutable default arguments (`def foo(x=[]):`)
- `with` statements for all file/resource handling
- Comprehensions preferred over `map`/`filter` with lambdas where readable
- No `import *`

## Logic
- `None` checks before attribute access
- Iterator exhaustion: generators used only once
- Dataclass / pydantic models used for structured data rather than raw dicts
- Async code: `await` not forgotten on coroutines; no blocking calls in async context

## Commands to run
```bash
python -m pytest --tb=short 2>&1
ruff check . 2>&1          # or: flake8 .
mypy . 2>&1                # if mypy configured
bandit -r . 2>&1           # security scanner if installed
```
