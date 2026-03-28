.PHONY: test lint help

help:
	@printf "Available targets:\n"
	@printf "  make test   Run PSScriptAnalyzer lint then Pester tests\n"
	@printf "  make lint   Run PSScriptAnalyzer on setup_windows.ps1\n"
	@printf "  make help   Show this help\n"

lint:
	pwsh -NoProfile -File ./run-lint.ps1

test:
	pwsh -NoProfile -File ./run-tests.ps1
