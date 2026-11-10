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

# _merge_run_block: print the body of the merge step's `run: |` block with its
# common indentation (10 spaces) stripped, up to the first less-indented line.
_merge_run_block() {
  _merge_step | awk '
    in_run && substr($0, 1, 10) == "          " { print substr($0, 11); next }
    in_run { exit }
    /^        run: \|$/ { in_run = 1 }
  '
}

# _expected_run_block: the run block, exactly. A substring check per line would
# let an inverted `if`, or a merge moved past `fi`, pass.
_expected_run_block() {
  cat <<'BLOCK'
merge="${RUNNER_TEMP}/auto-merge-merge.sh"
if git show "${BASE_SHA}:scripts/auto-merge-merge.sh" > "${merge}"; then
  bash "${merge}" "${PR_NUMBER}" "${HEAD_SHA}"
else
  echo "no merge script on the base commit -- retry off, single direct merge"
  gh pr merge "${PR_NUMBER}" --squash --match-head-commit "${HEAD_SHA}"
fi
BLOCK
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
  run _merge_run_block
  [ "$status" -eq 0 ]
  [ "$output" = "$(_expected_run_block)" ]
  # no other line of the step may name the script: only the git show line
  local stray
  stray="$(_merge_step | awk '/scripts\/auto-merge-merge\.sh/ && !/git show/' | wc -l)"
  [ "${stray}" -eq 0 ]
}

@test "fallback is one direct merge pinned to the head commit" {
  run _merge_run_block
  [ "$status" -eq 0 ]
  [ "$output" = "$(_expected_run_block)" ]
  local merges
  merges="$(_merge_step | awk '/gh pr merge/' | wc -l)"
  [ "${merges}" -eq 1 ]
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
