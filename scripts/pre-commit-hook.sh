#!/usr/bin/env bash
# pre-commit hook: run make lint from the repo root
cd "$(git rev-parse --show-toplevel)" && make lint
