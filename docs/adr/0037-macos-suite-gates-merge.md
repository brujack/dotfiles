# ADR-0037: The macOS test suite gates merge

**Date:** 2026-10-02
**Status:** Accepted.

## Context

The dotfiles session moved from the Mac Studio to the Linux `claude` box on 2026-09-19.
Until then the pre-push hook ran the whole suite on macOS on every push. Afterwards
nothing did: CI ran `make test` only on `ubuntu-latest`, and `lint-macos` only checks
syntax.

On 2026-10-02 the suite was run on the Studio at `af2d024` and gave 2155 ok and 6 not ok.
Five of the six failed because tests inherited `MACOS` from the parent shell, which is set
in an interactive mac shell and unset over `ssh` and on a runner. The sixth,
`_install_ubuntu_edge_source ... truncated key`, failed because GnuPG 2.5.24 exits 0 when
it dearmors a truncated key where GnuPG 2.4.8 exits 2.

ADR-0008 moved the `bash-coverage` job off macOS runners because of queues of 30 to 60
minutes. That reason no
longer holds for this repository's job: `lint-macos` queued a median of 8 seconds and a
maximum of 12 seconds over the last 40 successful runs.

## Decision

1. **A `test-macos` job on `macos-latest` runs `make test`** under the system GNU Make 3.81,
   and it is in `auto-merge`'s `needs:`.
2. **It is in `needs:` from the commit that adds it.** The merge step is a plain
   `gh pr merge --squash` with no `--auto`, so a job outside `needs:` would let a PR merge
   while that job was red.
3. **Homebrew bash, bats-core, parallel and coreutils are installed unpinned**, and a
   version banner step prints the versions so a red run with no code change is diagnosable.
   coreutils is there because macOS ships no `timeout` and six tests use it to bound a
   hang; every provisioned mac has it as an untagged Brewfile entry. shellcheck and uv are
   pinned and checked by sha256.
4. **`scripts/ci-suite-report.sh` prints every `not ok` block** and fails unless the number
   of executed tests equals the number declared in `tests/` and is above zero, so a run
   that stopped early or found nothing cannot pass.
5. **The job runs with `permissions: contents: read`.** The repository's default workflow
   token is read-write and this job runs unpinned Homebrew bottles.
6. **Tests that run a real platform tool set the platform themselves.** The five that run
   a real `stat` or `date` set `MACOS` from `uname -s`. A helper that unset every inherited
   platform variable was built and then removed: with it deleted, the suite stayed green
   under hostile exported variables on both the Studio and `claude`, so nothing could tell
   it was there.
7. **The Edge bootstrap keyring must list the pinned fingerprint `MS_GPG_FPR`**, because
   GnuPG 2.5 exits 0 on a truncated key.

## Consequences

- **The gate can fail, which was checked rather than assumed.** Its first run was red with
  twelve tests: the predicted six plus six that need `timeout`. After coreutils was added
  it was red with exactly the predicted six. Four re-runs of that job gave the same six
  three times, and six plus one timing-sensitive test once
  (`_install_ubuntu_powershell: a hanging pwsh probe is bounded by timeout`, whose 3-second
  margin was widened to 18).
- **Cost.** The macOS job took between 9m08s and 11m46s over five runs of one commit on a
  3-vCPU runner. `bash-coverage` on the same PR took about 9m40s, so the PR's wall clock is about
  the same.
- **Unpinned Homebrew tools can turn the job red with no code change.** The banner step is
  the diagnostic.
- **Some tests skip on macOS.** The tests that need GNU `ar` skip there, and the
  `makefile_lint_scope.bats` arms that need make 4 or later skip there. Both are covered
  on `ubuntu-latest`.
- **A hosted runner is not a provisioned mac.** Defects that only appear when
  `setup_env.sh` runs for real are still uncovered; a backlog row in
  `docs/superpowers/README.md` tracks it.
- **A macOS failure cannot be reproduced on the Linux development box**, only on the
  Studio over `ssh` or in CI; `CLAUDE.md` carries the command.

## Related

- ADR-0008 (`bash-coverage` moved off macOS runners; its queue-time reason no longer holds
  for this job)
- ADR-0035 (parallel bats under a validated `JOBS` knob)
- `docs/superpowers/specs/2026-10-02-macos-test-gate-design.md`
- `docs/superpowers/plans/2026-10-02-macos-test-gate.md`
- brujack/dotfiles#306
