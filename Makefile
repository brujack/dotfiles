MAKEFLAGS += --no-print-directory
# MAKEFLAGS is an exported environment variable, not a file-local setting --
# it removes print-directory variance at the source rather than repeating
# --no-print-directory at every -C call site, including ones not yet
# written. GNU Make >= 4.0 prints "Entering directory"/"Leaving directory" on
# stdout whenever -C changes directory; 3.81 (still shipped by macOS) does
# not. Any test that measures this must invoke make through
# `env -u MAKEFLAGS`, or it measures this exported variable rather than the
# Makefile (tests/scripts/makefile_lint_scope.bats; ci.md pitfall G).

# JOBS is the bats worker count for `make test`. Validated here in pure make --
# no $(shell), no fork -- and BEFORE every other assignment in this file, so a
# bad value aborts at parse time rather than after four subprocesses have run.
# The three terms are: exactly one word, nothing left once the digits are
# stripped, and no leading zero. $(origin JOBS) is in the message because a
# command-line JOBS reaches a nested make through BOTH MAKEFLAGS and the
# recipe environment, so "where did this value come from" is a real question.
JOBS ?= 12
_JOBS_NONDIGIT := $(subst 0,,$(subst 1,,$(subst 2,,$(subst 3,,$(subst 4,,$(subst 5,,$(subst 6,,$(subst 7,,$(subst 8,,$(subst 9,,$(JOBS)))))))))))
ifneq ($(words $(JOBS))$(_JOBS_NONDIGIT)$(filter 0%,$(JOBS)),1)
$(error JOBS must be a positive integer, got '$(JOBS)' (from $(origin JOBS)))
endif

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

# Detection asks what the binary IS, not that a binary of that name exists.
# moreutils ships an incompatible `parallel` under the same name (dpkg
# diverts it to /usr/bin/parallel.moreutils on this box), and `command -v`
# is true for it -- so a presence check would send `bats --jobs` at a program
# that does something else with those arguments instead of taking the serial
# path this promises. The guard is required rather than defensive:
# bats-exec-suite calls parallel even when it is absent, so without it
# `bats --jobs` dies with `command not found` rather than declining cleanly.
HAVE_PARALLEL := $(shell parallel --version 2>/dev/null | grep -q '^GNU parallel' && echo yes)

# Files that run alone, after the parallel phase. Empty today: the per-file
# check measured all 54 files clean at --jobs 12, and the one file that was
# not was fixed (39704a12) rather than carved out. A name here needs a
# measurement beside it, not a suspicion -- a carve-out is a permanent
# exemption from the gate everything else runs under.
BATS_SERIAL_FILES :=
# A filesystem walk, not `git ls-files`: an untracked .bats file is exactly
# what a TDD red step produces, and a tracked-only list would report it green
# by never running it. This is the same set `bats --recursive tests/` walks.
BATS_ALL_FILES := $(shell find tests -name '*.bats' 2>/dev/null | sort)
BATS_PARALLEL_FILES := $(filter-out $(BATS_SERIAL_FILES),$(BATS_ALL_FILES))

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
	@printf "  make lint              bash -n + ShellCheck over SHELL_FILES, zsh -n over ZSH_FILES, lib EXIT-trap ratchet\n"
	@printf "  make bash-coverage     Measure bash line coverage via PS4 xtrace tracer\n"
	@printf "  make install-hooks     Install pre-commit and pre-push hooks (run once per checkout)\n"
	@printf "  make sync-agent-guidance  Regenerate .cursor/rules/global-claude-standards.mdc from CLAUDE.md\n"
	@printf "  make check-agent-guidance Fail if the generated Cursor rule has drifted from CLAUDE.md\n"
	@printf "  make sync-requirements-ci  Render both CI requirements files from uv.lock\n"
	@printf "  make check-requirements-ci Fail if either rendering has drifted from uv.lock\n"
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
	  if [ "$${_OVERRIDE_PLATFORM:-$$(uname -s)}" = Darwin ]; then \
	    printf "shellcheck not found, skipping (install: brew install shellcheck)\n"; \
	  else \
	    printf "shellcheck not found, skipping (install: ./setup_env.sh -t developer on Ubuntu (installs the pinned SHELLCHECK_VER))\n"; \
	  fi; \
	fi; \
	if [ -f scripts/check-lib-exit-traps.sh ]; then \
	  bash scripts/check-lib-exit-traps.sh || failed=1; \
	else \
	  printf "scripts/check-lib-exit-traps.sh missing, skipping (restore it: git checkout scripts/check-lib-exit-traps.sh)\n"; \
	fi; \
	exit $$failed

test: lint check-lock check-requirements-ci test-python
ifndef BATS
	$(error $(BATS_MISSING))
endif
ifeq ($(HAVE_PARALLEL),yes)
	bats --jobs $(JOBS) $(BATS_PARALLEL_FILES)
else
	@printf "GNU parallel not found, running bats serially (install: brew install parallel / sudo apt-get install parallel)\n"
	bats $(BATS_ALL_FILES)
endif
ifneq ($(strip $(BATS_SERIAL_FILES)),)
	bats $(BATS_SERIAL_FILES)
endif

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

# check-requirements-ci compares each RENDERING against uv.lock -- it runs
# `uv export --frozen`, which reads the lock, so an unchanged lock renders
# unchanged output. It therefore cannot see a pyproject.toml that the lock no
# longer satisfies: measured 2026-08-22, bumping a manifest constraint and
# leaving uv.lock untouched gives `uv lock --check` rc=1 and the drift gate
# rc=0. Rendering-to-lock and lock-to-manifest are different relationships and
# only one of them had a gate.
#
# This matters ahead of enabling Renovate's pep621 manager: a bump whose
# updateArtifacts step fails produces exactly that state, and without this
# target it would go green through CI and land a manifest the lock cannot
# satisfy. Same missing-tool guard as above, for the same reason.
check-lock:
ifeq ($(UV),)
	@printf "uv not found, skipping uv.lock consistency check (install: brew install uv)\n"
else
	@$(UV) lock --check
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
