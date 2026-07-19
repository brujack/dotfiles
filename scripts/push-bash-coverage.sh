#!/usr/bin/env bash
# Runs bash coverage measurement and pushes bash.json to the coverage-data branch.
# Intended for scheduled use (e.g. cron at 2am).
#
# Usage: bash scripts/push-bash-coverage.sh

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: push-bash-coverage.sh [-h|--help]

Runs bash coverage measurement (scripts/run-bash-coverage.sh) and pushes
the resulting coverage/bash.json badge to the coverage-data branch if it
changed. Intended for scheduled use (e.g. cron at 2am).
USAGE
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BADGE_JSON="${REPO_ROOT}/coverage/bash.json"
COVERAGE_WORKTREE="${REPO_ROOT}/.coverage-data-worktree"

cd "${REPO_ROOT}" || exit 1

# Run coverage measurement and produce badge JSON
bash "${REPO_ROOT}/scripts/run-bash-coverage.sh" --json "${BADGE_JSON}"
overall_pct=$(python3 -c "import json; d=json.load(open('${BADGE_JSON}')); print(d['message'].rstrip('%'))" 2>/dev/null)
if [[ -z "${overall_pct}" ]]; then
    printf "ERROR: failed to read coverage percentage from %s\n" "${BADGE_JSON}" >&2
    exit 1
fi

printf "Coverage: %s%%\n" "${overall_pct}"

# Ensure we have the latest coverage-data branch
git fetch origin coverage-data 2>/dev/null || {
    printf "ERROR: coverage-data branch not found on remote\n" >&2
    exit 1
}

# Set up worktree
if [[ -d "${COVERAGE_WORKTREE}" ]]; then
    git worktree remove --force "${COVERAGE_WORKTREE}" 2>/dev/null || true
fi
git worktree add "${COVERAGE_WORKTREE}" coverage-data

# Copy the badge JSON
cp "${BADGE_JSON}" "${COVERAGE_WORKTREE}/bash.json"

# Commit and push if changed
if git -C "${COVERAGE_WORKTREE}" diff --quiet bash.json 2>/dev/null; then
    printf "bash.json unchanged (%s%%) — skipping push\n" "${overall_pct}"
else
    git -C "${COVERAGE_WORKTREE}" add bash.json
    # Use null hooksPath — coverage-data branch has no Makefile so lint hook fails
    git -C "${COVERAGE_WORKTREE}" -c core.hooksPath=/dev/null \
        commit -m "ci: update bash coverage badge to ${overall_pct}%"
    git -C "${COVERAGE_WORKTREE}" push origin coverage-data
    printf "Pushed bash.json (%s%%) to coverage-data branch\n" "${overall_pct}"
fi

# Clean up worktree
git worktree remove "${COVERAGE_WORKTREE}"
