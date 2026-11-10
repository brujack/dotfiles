#!/usr/bin/env bats
# The auto-merge job in .github/workflows/ci.yml: skips drafts, and runs
# scripts/auto-merge-merge.sh from the BASE commit (never the PR's copy), with a
# single direct merge as the fallback when the base has no script.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  WF="${REPO_ROOT}/.github/workflows/ci.yml"
}

# _job <name>: print one top-level job of ci.yml (to the next top-level job or
# end of file), full-line comments dropped.
_job() {
  awk -v want="$1" '
    /^  [a-z-]+:$/ { job=$1; sub(/:$/,"",job) }
    job == want && !/^[[:space:]]*#/ { print }
  ' "${WF}"
}

# _merge_step: print the "Auto-merge passing PRs" step of the auto-merge job,
# full-line comments dropped.
_merge_step() {
  _job auto-merge | awk '
    /^      - / { in_step = ($0 ~ /name: Auto-merge passing PRs/) }
    in_step { print }
  '
}

@test "auto-merge job skips drafts" {
  run _job auto-merge
  [ "$status" -eq 0 ]
  local want="    if: github.event_name == 'pull_request' && github.event.pull_request.draft == false"
  local hits
  hits="$(printf '%s\n' "$output" | awk -v want="${want}" '$0 == want' | wc -l)"
  [ "${hits}" -eq 1 ]
}

@test "merge step stays gated on the hold step and gets BASE_SHA" {
  run _merge_step
  [ "$status" -eq 0 ]
  [[ "$output" == *"if: steps.hold.outputs.merge == 'true'"* ]]
  [[ "$output" == *'BASE_SHA: ${{ github.event.pull_request.base.sha }}'* ]]
}

@test "merge step runs the script read from the base commit, never the checkout" {
  run _merge_step
  [ "$status" -eq 0 ]
  [[ "$output" == *'git show "${BASE_SHA}:scripts/auto-merge-merge.sh"'* ]]
  [[ "$output" == *'bash "${merge}" "${PR_NUMBER}" "${HEAD_SHA}"'* ]]
  # every other mention of the script path must be the git show line
  local stray
  stray="$(printf '%s\n' "$output" | awk '/scripts\/auto-merge-merge\.sh/ && !/git show/' | wc -l)"
  [ "${stray}" -eq 0 ]
}

@test "fallback is one direct merge pinned to the head commit" {
  run _merge_step
  [ "$status" -eq 0 ]
  [[ "$output" == *"retry off"* ]]
  [[ "$output" == *'gh pr merge "${PR_NUMBER}" --squash --match-head-commit "${HEAD_SHA}"'* ]]
}

@test "no --auto anywhere in the auto-merge job" {
  local hits
  hits="$(_job auto-merge | awk '/--auto/' | wc -l)"
  [ "${hits}" -eq 0 ]
}

@test "scripts/auto-merge-merge.sh is tracked" {
  run git -C "${REPO_ROOT}" ls-files --error-unmatch scripts/auto-merge-merge.sh
  [ "$status" -eq 0 ]
}

@test "job helper reads its own job, not a neighbour's" {
  # positive control: the gate lives in auto-merge and nowhere else
  run _job auto-merge
  [[ "$output" == *"auto-merge-gate.sh"* ]]
  run _job test
  [[ "$output" != *"auto-merge-gate.sh"* ]]
  [[ "$output" != *"auto-merge-merge.sh"* ]]
  run _job no-such-job
  [ -z "$output" ]
}
