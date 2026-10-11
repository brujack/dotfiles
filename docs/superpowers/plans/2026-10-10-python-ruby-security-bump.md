# Python 3.14.8 / Ruby 4.0.7 security bump Implementation Plan

spec: docs/superpowers/specs/2026-10-10-python-ruby-security-bump-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Move the Python and Ruby pins to their security releases.

**Architecture:** Two constants in `lib/constants.sh` and the `chruby` duplicate in `.config/.zshrc.d/5_general.zsh`. No logic change.

**Tech Stack:** bash, zsh.

## Global Constraints

- `PYTHON_VER="3.14.8"`, `RUBY_VER="4.0.7"`; no `pyproject.toml` or `uv.lock` change.

---

### Task 1: Bump the pins

```yaml-task
id: 1
description: Set PYTHON_VER 3.14.8 and RUBY_VER 4.0.7 in constants.sh and the zsh chruby duplicate
role: executor
model: sonnet
tdd: not-applicable
requirements: [R1, R2]
acceptance:
  - cmd: grep -qx 'PYTHON_VER="3.14.8"' lib/constants.sh
    exit_code: 0
  - cmd: grep -qx 'RUBY_VER="4.0.7"' lib/constants.sh
    exit_code: 0
  - cmd: grep -qx 'RUBY_VER="4.0.7"' .config/.zshrc.d/5_general.zsh
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 1
files_touched: [lib/constants.sh, .config/.zshrc.d/5_general.zsh]
depends_on: []
```

`tdd: not-applicable`: a value-only change to pins no test reads; `make test` is the regression gate.

Executed inline on 2026-10-10 as commit `fab3bf28` on `fix/python-ruby-security-bump`; this plan was written afterwards so `spec-alignment-review` has the plan it resolves through.
