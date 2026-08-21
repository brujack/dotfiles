MAKEFLAGS += --no-print-directory
# MAKEFLAGS is an exported environment variable, not a file-local setting --
# it removes print-directory variance at the source rather than repeating
# --no-print-directory at every -C call site, including ones not yet
# written. GNU Make >= 4.0 prints "Entering directory"/"Leaving directory" on
# stdout whenever -C changes directory; 3.81 (still shipped by macOS) does
# not. Any test that measures this must invoke make through
# `env -u MAKEFLAGS`, or it measures this exported variable rather than the
# Makefile (tests/scripts/makefile_lint_scope.bats; ci.md pitfall G).

BATS := $(shell command -v bats 2>/dev/null)
SHELLCHECK := $(shell command -v shellcheck 2>/dev/null)
UV := $(shell command -v uv 2>/dev/null)
PYTHON3 := $(shell command -v python3 2>/dev/null)

# SHELL_FILES is content-derived (every tracked file whose first line is a
# bash/sh shebang), not pathspec-derived: a pathspec cannot express "every
# tracked shell script" (shell.md), which is why the previous
# '*.sh' '*.bash' plus two named hooks left every extensionless mock under
# tests/mocks/ (64 of them) and config/local.sh.example out of scope, with
# the omission invisible in the gate's own output (tdd.md Coverage
# Denominators). The env -u strip for a leaked GIT_DIR (ci.md) now lives
# inside scripts/list-shell-files.sh rather than around this assignment,
# since the script's own git calls are what need it.
SHELL_FILES := $(shell ./scripts/list-shell-files.sh)
# Bats suites are shell too, and were never shellchecked — SHELL_FILES's
# shebang-derived set does not include them (a bats file carries no bash/sh
# shebang). They are linted separately because they need --severity=warning:
# bats' run/@test model emits SC2030 and SC2031 subshell notices structurally
# (over 2200 of them here) which say nothing about correctness, while
# SHELL_FILES runs at the default severity and should stay there.
#
# BATS_FILES is derived from `git ls-files`, not a filesystem walk: a walk
# also matches an untracked parked worktree under .claude/worktrees/ and the
# git-ignored, machine-local config/local.sh — neither should be linted here.
# The env -u prefix strips a GIT_DIR that git exports into this hook's
# environment when a push originates from a worktree (ci.md); without it this
# parse-time assignment can silently resolve against the wrong repository.
BATS_FILES := $(shell env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
                 git ls-files '*.bats')

# zsh -n needs its own file list: none of the globs above name a file zsh
# actually interprets. This is every tracked zsh source — the interactive
# init modules, the theme file, and the two dotfiles that are symlinked live
# into $HOME and sourced by an interactive zsh — derived from git ls-files
# for the same reason SHELL_FILES/BATS_FILES are. config/profiles.sh is
# named explicitly rather than picked up by a glob: it is a bash file (and
# stays in SHELL_FILES), but config/profiles.zsh sources it from
# .zprofile/1_init.zsh on every login and interactive shell, so zsh -n must
# parse it too.
ZSH_FILES := $(shell env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
                 git ls-files '*.zsh' '*.zsh-theme' '.zshrc' '.zprofile' 'config/profiles.sh')

# Message text only, never the $(error ...) call itself: $(error) fires wherever
# it is expanded, so folding it into a := assignment would abort every make
# invocation (including `make help`) at parse time regardless of target.
# One-shot fix leads; the durable fix (full provisioning re-run) follows.
BATS_MISSING := bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux). Durable fix: ./setup_env.sh -t setup_user (full provisioning re-run)

.PHONY: test test-python test-unit lint bash-coverage install-hooks ledger-symlink help changelog validate-plan sync-agent-guidance check-agent-guidance

help:
	@printf "Available targets:\n"
	@printf "  make test              Run all BATS tests\n"
	@printf "  make test-unit         Run unit tests only\n"
	@printf "  make lint              bash -n + ShellCheck over SHELL_FILES, zsh -n over ZSH_FILES\n"
	@printf "  make bash-coverage     Measure bash line coverage via PS4 xtrace tracer\n"
	@printf "  make install-hooks     Install pre-commit and pre-push hooks (run once per checkout)\n"
	@printf "  make sync-agent-guidance  Regenerate .cursor/rules/global-claude-standards.mdc from CLAUDE.md\n"
	@printf "  make check-agent-guidance Fail if the generated Cursor rule has drifted from CLAUDE.md\n"
	@printf "  make sync-requirements-ci  Render requirements-ci.txt from uv.lock's test-lint group\n"
	@printf "  make check-requirements-ci Fail if requirements-ci.txt has drifted from uv.lock\n"
	@printf "  make help              Show this help\n"

lint:
	@if [ -z "$(SHELL_FILES)" ]; then \
	  printf 'lint: derived shell file list is EMPTY — refusing to report a pass having linted nothing.\n' >&2; \
	  printf '      scripts/list-shell-files.sh is missing, broken, or not executable — try:\n' >&2; \
	  printf '      chmod +x scripts/list-shell-files.sh\n' >&2; \
	  exit 1; \
	fi
	@if [ -z "$(ZSH_FILES)" ]; then \
	  printf 'lint: derived zsh file list is EMPTY — refusing to report a pass having linted nothing.\n' >&2; \
	  printf '      (git absent from PATH, or this tree was exported without .git?)\n' >&2; \
	  exit 1; \
	fi
	@failed=0; bash_ok=0; \
	for f in $(SHELL_FILES); do \
	  bash -n "$$f" && bash_ok=$$((bash_ok + 1)) || failed=1; \
	done; \
	if [ "$$failed" -eq 0 ]; then \
	  printf "bash -n OK (%s files)\n" "$$bash_ok"; \
	fi; \
	for f in $(ZSH_FILES); do \
	  zsh  -n "$$f" && printf "zsh   OK  %s\n" "$$f" || { printf "zsh  FAIL %s\n" "$$f"; failed=1; }; \
	done; \
	if [ -n "$(SHELLCHECK)" ]; then \
	  if [ -n "$(SHELL_FILES)" ]; then \
	    shellcheck $(SHELL_FILES) && printf "shellcheck OK\n" || { printf "shellcheck FAIL\n"; failed=1; }; \
	  fi; \
	  if [ -n "$(BATS_FILES)" ]; then \
	    shellcheck --severity=warning $(BATS_FILES) && printf "shellcheck bats OK\n" || { printf "shellcheck bats FAIL\n"; failed=1; }; \
	  fi; \
	else \
	  printf "shellcheck not found, skipping (install: brew install shellcheck)\n"; \
	fi; \
	exit $$failed

test: lint check-requirements-ci test-python
ifndef BATS
	$(error $(BATS_MISSING))
endif
	bats --recursive tests/

# The only Python in this repo is .claude/scripts/triage_log.py, vendored from
# ai-config so bug-fix-cycle can emit telemetry here. It ships with its suite
# rather than untested: a repo gating at 90% coverage does not take unverified
# code to unblock a gate.
test-python:
ifndef PYTHON3
	@printf "python3 not found, skipping Python tests (install: brew install python@3 / apt-get install python3)\n"
else
	python3 -m unittest discover -s tests -p 'test_*.py'
endif

bash-coverage:
ifndef BATS
	$(error $(BATS_MISSING))
endif
	@bash scripts/run-bash-coverage.sh

ledger-symlink:
	@mkdir -p "${HOME}/.local/bin"
	@if [ ! -L "${HOME}/.local/bin/ledger" ]; then \
		ln -s "${HOME}/.local/share/state-ledger/scripts/ledger.py" "${HOME}/.local/bin/ledger"; \
		chmod +x "${HOME}/.local/share/state-ledger/scripts/ledger.py" 2>/dev/null || true; \
		printf "ledger symlink created\n"; \
	else \
		printf "ledger symlink already exists\n"; \
	fi

install-hooks: ledger-symlink
	ln -sf "$(shell pwd)/scripts/pre-commit-hook.sh" .git/hooks/pre-commit
	ln -sf "$(shell pwd)/scripts/pre-push" .git/hooks/pre-push
	ln -sf "$(shell pwd)/scripts/commit-msg" .git/hooks/commit-msg
	@printf "Pre-commit, pre-push, and commit-msg hooks installed\n"

test-unit:
ifndef BATS
	$(error $(BATS_MISSING))
endif
	bats tests/setup_env/unit.bats tests/setup_env/profiles.bats tests/zshrc.d/unit.bats

changelog:
	git-cliff -o CHANGELOG.md

sync-agent-guidance:
	./scripts/sync-agent-guidance.sh sync

check-agent-guidance:
	./scripts/sync-agent-guidance.sh check

sync-requirements-ci:
	./scripts/sync-requirements-ci.sh sync

# Guarded like lint's shellcheck: a gate that hard-fails on a missing tool locks
# the machine out of committing the very change that would install it. CI
# installs a pinned uv, so the check genuinely runs there rather than skipping.
check-requirements-ci:
ifeq ($(UV),)
	@printf "uv not found, skipping requirements-ci drift check (install: brew install uv)\n"
else
	@./scripts/sync-requirements-ci.sh check
endif

# Introspection: `make print-VARNAME` prints a Makefile variable's resolved
# value, for tests that need to assert against the Makefile's own derivation
# rather than re-deriving it themselves.
print-%:
	@printf '%s\n' "$($*)"

# 10-80-10 cycle (ai-config ADR-0009/0010) — validate a plan file
validate-plan:
ifndef PLAN
	@printf "error: PLAN is required, e.g. make validate-plan PLAN=docs/superpowers/plans/foo.md\n" >&2
	@exit 2
endif
	@python3 ~/.claude/scripts/validate-plan.py "$(PLAN)"
