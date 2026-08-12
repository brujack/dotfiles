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
PYTHON3 := $(shell command -v python3 2>/dev/null)
SHELL_FILES := $(shell env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
                 git ls-files '*.sh' '*.bash' 'scripts/pre-push' 'scripts/commit-msg')
# Bats suites are shell too, and were never shellchecked — the globs above
# only match *.sh/*.bash/the two extensionless hooks. They are linted
# separately rather than folded into SHELL_FILES because they need
# --severity=warning: bats' run/@test model emits SC2030 and SC2031 subshell
# notices structurally (over 2200 of them here) which say nothing about
# correctness, while the files above run at the default severity and should
# stay there.
#
# Both lists are derived from `git ls-files`, not a filesystem walk: a walk
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
# for the same reason SHELL_FILES/BATS_FILES are.
ZSH_FILES := $(shell env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
                 git ls-files '*.zsh' '*.zsh-theme' '.zshrc' '.zprofile')

# Message text only, never the $(error ...) call itself: $(error) fires wherever
# it is expanded, so folding it into a := assignment would abort every make
# invocation (including `make help`) at parse time regardless of target.
# One-shot fix leads; the durable fix (full provisioning re-run) follows.
BATS_MISSING := bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux). Durable fix: ./setup_env.sh -t setup_user (full provisioning re-run)

.PHONY: test test-python test-unit lint bash-coverage push-bash-coverage install-hooks ledger-symlink help changelog validate-plan sync-agent-guidance check-agent-guidance

help:
	@printf "Available targets:\n"
	@printf "  make test              Run all BATS tests\n"
	@printf "  make test-unit         Run unit tests only\n"
	@printf "  make lint              bash -n + ShellCheck over SHELL_FILES, zsh -n over ZSH_FILES\n"
	@printf "  make bash-coverage     Measure bash line coverage via PS4 xtrace tracer\n"
	@printf "  make push-bash-coverage  Run bash-coverage and push badge JSON to coverage-data branch\n"
	@printf "  make install-hooks     Install pre-commit and pre-push hooks (run once per checkout)\n"
	@printf "  make sync-agent-guidance  Regenerate .cursor/rules/global-claude-standards.mdc from CLAUDE.md\n"
	@printf "  make check-agent-guidance Fail if the generated Cursor rule has drifted from CLAUDE.md\n"
	@printf "  make help              Show this help\n"

lint:
	@if [ -z "$(SHELL_FILES)" ]; then \
	  printf 'lint: derived shell file list is EMPTY — refusing to report a pass having linted nothing.\n' >&2; \
	  printf '      (git absent from PATH, or this tree was exported without .git?)\n' >&2; \
	  exit 1; \
	fi
	@if [ -z "$(ZSH_FILES)" ]; then \
	  printf 'lint: derived zsh file list is EMPTY — refusing to report a pass having linted nothing.\n' >&2; \
	  printf '      (git absent from PATH, or this tree was exported without .git?)\n' >&2; \
	  exit 1; \
	fi
	@failed=0; \
	for f in $(SHELL_FILES); do \
	  bash -n "$$f" && printf "bash  OK  %s\n" "$$f" || { printf "bash FAIL %s\n" "$$f"; failed=1; }; \
	done; \
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

test: lint test-python
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

push-bash-coverage:
ifndef BATS
	$(error $(BATS_MISSING))
endif
	@bash scripts/push-bash-coverage.sh

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
