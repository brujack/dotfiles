#!/usr/bin/env bats
# Scratch only (never merged): a deliberate escape for the root-writes rollout
# (spec docs/superpowers/specs/2026-11-27-root-writes-scan-design.md, V3). It
# calls the real /usr/bin/sudo, so it runs only on a hosted runner; a pre-push
# `make test` on a developer box skips it. It never calls load_mocks, so the
# mock-ledger guard cannot be what turns the step red: only the scan can.

@test "deliberate escape: write a file under /usr/local/bin through the real sudo" {
  [[ -n ${GITHUB_ACTIONS:-} ]] || skip "escape runs only on a hosted runner"
  /usr/bin/sudo -n touch /usr/local/bin/root-writes-escape
}
