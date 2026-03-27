BATS := $(shell command -v bats 2>/dev/null)

.PHONY: test test-unit help

help:
	@printf "Available targets:\n"
	@printf "  make test       Run all BATS tests\n"
	@printf "  make test-unit  Run unit tests only\n"
	@printf "  make help       Show this help\n"

test:
ifndef BATS
	$(error bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux))
endif
	bats --recursive tests/

test-unit:
ifndef BATS
	$(error bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux))
endif
	bats tests/setup_env/unit.bats tests/zshrc.d/unit.bats
