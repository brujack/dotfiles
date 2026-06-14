BATS := $(shell command -v bats 2>/dev/null)
SHELLCHECK := $(shell command -v shellcheck 2>/dev/null)
KCOV := $(shell command -v kcov 2>/dev/null)
SHELL_FILES := $(shell find . -name "*.sh" -not -path "*/node_modules/*" -not -path "*/coverage/*")

.PHONY: test test-unit lint coverage bash-coverage push-bash-coverage install-hooks help changelog validate-plan

help:
	@printf "Available targets:\n"
	@printf "  make test              Run all BATS tests\n"
	@printf "  make test-unit         Run unit tests only\n"
	@printf "  make lint              Check bash/zsh syntax + ShellCheck all .sh files\n"
	@printf "  make coverage          Run kcov coverage gate (requires kcov; CI-enforced)\n"
	@printf "  make bash-coverage     Measure bash line coverage via PS4 xtrace tracer\n"
	@printf "  make push-bash-coverage  Run bash-coverage and push badge JSON to coverage-data branch\n"
	@printf "  make install-hooks     Install pre-commit and pre-push hooks (run once per checkout)\n"
	@printf "  make help              Show this help\n"

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

bash-coverage:
ifndef BATS
	$(error bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux))
endif
	@bash scripts/run-bash-coverage.sh

push-bash-coverage:
ifndef BATS
	$(error bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux))
endif
	@bash scripts/push-bash-coverage.sh

install-hooks:
	ln -sf "$(shell pwd)/scripts/pre-commit-hook.sh" .git/hooks/pre-commit
	ln -sf "$(shell pwd)/scripts/pre-push" .git/hooks/pre-push
	ln -sf "$(shell pwd)/scripts/commit-msg" .git/hooks/commit-msg
	@printf "Pre-commit, pre-push, and commit-msg hooks installed\n"

test-unit:
ifndef BATS
	$(error bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux))
endif
	bats tests/setup_env/unit.bats tests/setup_env/profiles.bats tests/zshrc.d/unit.bats

changelog:
	git-cliff -o CHANGELOG.md

# 10-80-10 cycle (ai-config ADR-0009/0010) — validate a plan file
validate-plan:
ifndef PLAN
	@printf "error: PLAN is required, e.g. make validate-plan PLAN=docs/superpowers/plans/foo.md\n" >&2
	@exit 2
endif
	@python3 ~/.claude/scripts/validate-plan.py "$(PLAN)"
