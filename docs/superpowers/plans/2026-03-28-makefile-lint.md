# Makefile Lint Target Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `lint` target to the Makefile that runs `bash -n` and `zsh -n` on all `.sh` files in the repo, and wire it as a prerequisite of `make test`.

**Architecture:** Single Makefile edit — add `lint` target, add `lint` to `.PHONY`, make `test` depend on `lint`, update `help`. No other files change.

**Tech Stack:** GNU Make, bash, zsh

---

## File Structure

**Modified:**

- `Makefile` — add `lint` target, update `.PHONY`, `test`, and `help`

---

### Task 1: Add lint target to Makefile

**Files:**

- Modify: `Makefile`

- [ ] **Step 1: Establish baseline — run make test and confirm it passes**

```bash
make test
```

Expected: all 89 BATS tests pass, exit 0.

- [ ] **Step 2: Apply the Makefile changes**

Replace the entire contents of `Makefile` with:

```makefile
BATS := $(shell command -v bats 2>/dev/null)
SHELL_FILES := $(shell find . -name "*.sh" -not -path "*/node_modules/*")

.PHONY: test test-unit lint help

help:
	@printf "Available targets:\n"
	@printf "  make test       Run all BATS tests\n"
	@printf "  make test-unit  Run unit tests only\n"
	@printf "  make lint       Check bash/zsh syntax of all .sh files\n"
	@printf "  make help       Show this help\n"

lint:
	@failed=0; \
	for f in $(SHELL_FILES); do \
	  bash -n "$$f" && printf "bash  OK  %s\n" "$$f" || { printf "bash FAIL %s\n" "$$f"; failed=1; }; \
	  zsh  -n "$$f" && printf "zsh   OK  %s\n" "$$f" || { printf "zsh  FAIL %s\n" "$$f"; failed=1; }; \
	done; \
	exit $$failed

test: lint
ifndef BATS
	$(error bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux))
endif
	bats --recursive tests/

test-unit:
ifndef BATS
	$(error bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux))
endif
	bats tests/setup_env/unit.bats tests/zshrc.d/unit.bats
```

Note: `SHELL_FILES` is defined once at the top so `make lint` and `make test` share the same file list without duplication.

- [ ] **Step 3: Run make lint to verify all .sh files pass**

```bash
make lint
```

Expected: one `bash  OK` and one `zsh   OK` line per `.sh` file, exit 0. Files covered: `setup_env.sh`, `scripts/*.sh`, `kubernetes_stuff/*.sh`.

- [ ] **Step 4: Verify make lint catches a syntax error**

Append a deliberate syntax error to `setup_env.sh`:

```bash
printf "if [[\n" >> setup_env.sh
```

Then run:

```bash
make lint
```

Expected: at least one `bash FAIL ./setup_env.sh` or `zsh  FAIL ./setup_env.sh` line, exit non-zero.

- [ ] **Step 5: Revert the syntax error**

```bash
# Remove the last line appended in Step 4
head -n -1 setup_env.sh > /tmp/setup_env_tmp.sh && mv /tmp/setup_env_tmp.sh setup_env.sh
```

Then verify the file is clean:

```bash
bash -n setup_env.sh && printf "clean\n"
```

Expected: `clean`

- [ ] **Step 6: Verify make test runs lint then BATS**

```bash
make test
```

Expected: lint output (all OK) followed by 89 BATS tests passing, exit 0.

- [ ] **Step 7: Verify make test fails when lint fails**

Append syntax error again:

```bash
printf "if [[\n" >> setup_env.sh
```

Then run:

```bash
make test; printf "exit: %d\n" $?
```

Expected: lint output showing FAIL, `make test` exits non-zero, BATS does **not** run (no `ok 1 ...` lines).

- [ ] **Step 8: Revert syntax error**

```bash
head -n -1 setup_env.sh > /tmp/setup_env_tmp.sh && mv /tmp/setup_env_tmp.sh setup_env.sh
bash -n setup_env.sh && printf "clean\n"
```

Expected: `clean`

- [ ] **Step 9: Run full test suite one final time**

```bash
make test
```

Expected: all 89 tests pass, exit 0.

- [ ] **Step 10: Commit**

```bash
git add Makefile
git commit -m "feat: add lint target to Makefile for bash/zsh syntax checking

Checks all .sh files with bash -n and zsh -n. make test depends on
lint so syntax errors block the test run.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
