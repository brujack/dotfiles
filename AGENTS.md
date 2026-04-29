# AGENTS.md

Cursor agent instructions for this repo.

## Source of truth (exhaustive)

- `CLAUDE.md` is exhaustive and authoritative for this repository.
- Treat all rules in `CLAUDE.md` as required, not advisory.
- If this file and `CLAUDE.md` conflict, follow `CLAUDE.md`.
- Also apply global Cursor rules from `~/.cursor/rules/` when they do not conflict.

## Required compliance behavior

- Before editing, read relevant sections in `CLAUDE.md`.
- During implementation, follow the repository's exact standards for shell style, idempotency, install guards, profile/capability usage, and symlink strategy.
- After changes, run the validations required by `CLAUDE.md` (`make lint`, `make test`, and targeted suites as applicable).
- Keep docs in sync when required by `CLAUDE.md` (including `README.md` and `CLAUDE.md` updates).

## Dotfiles-specific must-follow items

- Preserve selective Cursor user linking: only `settings.json`, `keybindings.json`, and `snippets` from `.cursor/User`.
- Do not introduce broad linking of volatile/local editor state.
- Preserve pre-commit and pre-push hook behavior and CI conventions.
- Never commit local-only state or secrets (for example `config/local.sh`, credentials, tokens, or machine-local caches).

## Drift control

- When `CLAUDE.md` changes, update this file in the same change so both remain aligned.
