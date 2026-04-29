BATS := $(shell command -v bats 2>/dev/null)
SHELLCHECK := $(shell command -v shellcheck 2>/dev/null)
KCOV := $(shell command -v kcov 2>/dev/null)
SHELL_FILES := $(shell find . -name "*.sh" -not -path "*/node_modules/*" -not -path "*/.cursor/plugins/cache/*")

.PHONY: test test-unit lint coverage install-hooks sync-agent-guidance check-agent-guidance help

help:
	@printf "Available targets:\n"
	@printf "  make test       Run all BATS tests\n"
	@printf "  make test-unit  Run unit tests only\n"
	@printf "  make lint       Check bash/zsh syntax + ShellCheck all .sh files\n"
	@printf "  make coverage   Run kcov coverage gate (requires kcov; CI-enforced)\n"
	@printf "  make install-hooks Install pre-commit and pre-push hooks (run once per checkout)\n"
	@printf "  make sync-agent-guidance Regenerate Cursor guidance from .claude sources\n"
	@printf "  make check-agent-guidance Fail if Cursor guidance drift is detected\n"
	@printf "  make help       Show this help\n"

lint:
	@failed=0; \
	for f in $(SHELL_FILES); do \
	  bash -n "$$f" && printf "bash  OK  %s\n" "$$f" || { printf "bash FAIL %s\n" "$$f"; failed=1; }; \
	  zsh  -n "$$f" && printf "zsh   OK  %s\n" "$$f" || { printf "zsh  FAIL %s\n" "$$f"; failed=1; }; \
	done; \
	if [ -n "$(SHELLCHECK)" ]; then \
	  shellcheck $(SHELL_FILES) && printf "shellcheck OK\n" || { printf "shellcheck FAIL\n"; failed=1; }; \
	else \
	  printf "shellcheck not found, skipping (install: brew install shellcheck)\n"; \
	fi; \
	exit $$failed

test: lint
ifndef BATS
	$(error bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux))
endif
	bats --recursive tests/

coverage:
ifeq ($(KCOV),)
	@printf "kcov not found — skipping coverage (CI enforces the gate). Install: brew install kcov\n"
else
	@bash scripts/run-coverage.sh
endif

install-hooks:
	ln -sf "$(shell pwd)/scripts/pre-commit-hook.sh" .git/hooks/pre-commit
	ln -sf "$(shell pwd)/scripts/pre-push" .git/hooks/pre-push
	@printf "Pre-commit and pre-push hooks installed\n"

sync-agent-guidance:
	@bash scripts/sync-agent-guidance.sh sync

check-agent-guidance:
	@bash scripts/sync-agent-guidance.sh check

test-unit:
ifndef BATS
	$(error bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux))
endif
	bats tests/setup_env/unit.bats tests/setup_env/profiles.bats tests/zshrc.d/unit.bats
