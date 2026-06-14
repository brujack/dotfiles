#!/usr/bin/env bash
# pre-commit hook: lint + secrets scan
cd "$(git rev-parse --show-toplevel)" || exit 1

make lint || exit 1

# Memory + retrospective frontmatter schema check (ADR-0014)
_changed_memory=$(git diff --cached --name-only \
    | grep -E '^\.claude/(memory|retrospectives)/.+\.md$' || true)
if [[ -n "${_changed_memory}" ]]; then
    if [[ -f .claude/scripts/validate_memory.py ]]; then
        _VM=.claude/scripts/validate_memory.py
    elif [[ -f "${HOME}/.claude/scripts/validate_memory.py" ]]; then
        _VM="${HOME}/.claude/scripts/validate_memory.py"
    else
        printf "pre-commit: validate-memory skipped (ai-config not installed)\n" >&2
        _VM=""
    fi
    if [[ -n "${_VM}" ]]; then
        # shellcheck disable=SC2086
        python3 "${_VM}" --files ${_changed_memory} || exit 1
    fi
fi

if command -v ggshield &>/dev/null; then
  ggshield secret scan pre-commit "$@" || exit 1
fi
