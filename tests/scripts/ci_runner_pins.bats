#!/usr/bin/env bats
# Runner-image pins in .github/workflows/ci.yml.
#
# ubuntu-latest moved from 24.04 to 26.04 on 2026-10-23, and Microsoft's
# packages.microsoft.com/ubuntu/26.04 repository ships no `powershell` package,
# so the powershell job failed `apt-get install -y powershell` with exit 100
# and held auto-merge on every PR. The job is pinned to ubuntu-24.04 until
# that repository carries the package.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  WF="${REPO_ROOT}/.github/workflows/ci.yml"
}

# _runs_on <job>: print the runs-on value of a top-level job in ci.yml.
_runs_on() {
  awk -v want="$1" '
    /^  [a-z-]+:$/ { job=$1; sub(/:$/,"",job); next }
    job == want && /^    runs-on:/ { sub(/^    runs-on:[[:space:]]*/,""); sub(/[[:space:]]*#.*$/,""); print; exit }
  ' "${WF}"
}

@test "powershell job is pinned to ubuntu-24.04" {
  run _runs_on powershell
  [ "$status" -eq 0 ]
  [ "$output" = "ubuntu-24.04" ]
}

@test "_runs_on reads a job's runs-on, not a neighbour's" {
  # positive control: the first job in the file runs on ubuntu-latest and
  # test-macos on macos-latest, so a parser that returned the first runs-on in
  # the file would fail here.
  run _runs_on test-macos
  [ "$output" = "macos-latest" ]
  run _runs_on no-such-job
  [ -z "$output" ]
}
