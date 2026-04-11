BATS := $(shell command -v bats 2>/dev/null)
SHELLCHECK := $(shell command -v shellcheck 2>/dev/null)
SHELL_FILES := $(shell find . -name "*.sh" -not -path "*/node_modules/*" -not -path "*/.cursor/plugins/cache/*")

.PHONY: test test-unit lint install-hooks help

help:
	@printf "Available targets:\n"
	@printf "  make test       Run all BATS tests\n"
	@printf "  make test-unit  Run unit tests only\n"
	@printf "  make lint          Check bash/zsh syntax + ShellCheck all .sh files\n"
	@printf "  make install-hooks Install pre-commit hook (runs make lint before each commit)\n"
	@printf "  make help          Show this help\n"

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

install-hooks:
	ln -sf "$(shell pwd)/scripts/pre-commit-hook.sh" .git/hooks/pre-commit
	@printf "Pre-commit hook installed at .git/hooks/pre-commit\n"

test-unit:
ifndef BATS
	$(error bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux))
endif
	bats tests/setup_env/unit.bats tests/setup_env/profiles.bats tests/zshrc.d/unit.bats
