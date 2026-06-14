#!/usr/bin/env bash
# pre-commit hook: lint + secrets scan
cd "$(git rev-parse --show-toplevel)" || exit 1

make lint || exit 1

if command -v ggshield &>/dev/null; then
  ggshield secret scan pre-commit "$@" || exit 1
fi
