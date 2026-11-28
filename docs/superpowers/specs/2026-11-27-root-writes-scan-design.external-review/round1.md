Tools: Read, Bash, SubagentHandback

The core is right; keep it. The scan watches the write itself instead of a ledger standing in for it. It resolves each root with `pwd -P` and counts entries below the root, which closes the macOS `/etc` blind walk. Emptiness is decided by a listing that does not depend on the walk. Wiring it only in CI keeps local noise out. Three premise figures hold at 291f0a56: 123 tracked `.bats` files, 64 without `load_mocks`. I also measured the `find` behaviour the design relies on (GNU findutils 4.10.0, Linux 7.0.0-43). A file copied in with `cp -p` and an old mtime is missed by `-newer` and caught by `-cnewer`. A symlinked start point without `-H` visits 1 entry. So R2's predicate and the R6 mutation test both do what they say.

## F1.1 Pruning is the planned way to clear a hit, but the script has nowhere to put it, and the stop rule lets you prune where the cited escape landed

V1 and V2 both say a hit is cleared by pruning its subtree "by spec amendment". But no requirement, design paragraph or test covers how a prune works. R2 and R3 define roots only. N3 ("no fixed list of directories") reads against any exclusion list. So the first hit on a hosted runner adds a new mechanism, mid-rollout, with no test.

The stop rule also protects only four paths wholesale: `/etc`, `/private/etc`, `/usr/local/bin` and `/opt/homebrew`. Pruning `/etc/apt`, `/etc/apt/keyrings`, `/usr/share/keyrings` or `/etc/sysctl.d` is allowed. Yet the real escape the spec cites landed in `/etc/apt`. Those are also the install targets in `lib/`, which name these roots 50 times (32 in `lib/linux_ubuntu.sh`).

- **Failure:** a runner-image apt timer touches `/etc/apt/apt.conf.d` during V1. The amendment prunes `/etc/apt`. A later docker-keyring escape like the 2026-11-26 one then goes green.
- **Fix:**
  - Specify now a per-OS prune list in the script, applied as `-path <p> -prune`. Each entry cites the V1 or V2 run that produced it. Amend N3 to allow it.
  - Add a test: a write beside a pruned subtree is still reported, and a write inside it is not.
  - Restate the stop rule: no prune may equal or contain a directory that `lib/` installs into. Named today: `/etc/apt`, `/etc/docker`, `/etc/sysctl.d`, `/usr/share/keyrings`, `/usr/local/bin`, `/opt/homebrew`.
  - This changes R2, R10, N3 and V1/V2.

## F1.2 On Linux, shard 1's `make test-prereqs` runs outside the scan window, but on macOS the same work is inside it

In `ci.yml`, `test-shard` runs `make test-prereqs` as its own step, "Run test prerequisites (shard 1 only)" at line 88. Only the next step, `make bash-coverage`, gets wrapped. On macOS, shard 1 runs `make test` (line 292), which includes `test-prereqs`.

So lint, `check-lock`, `check-requirements-ci` and the Python suite are scanned on macOS only. The manual instrument this replaces wrapped all of `make test`.

- **Failure:** a Python test that writes under `/usr/local` reddens macOS shard 1 only. If the write is Linux-only, it is never seen.
- **Fix:** either scan the same set on both OSes, or say in a non-goal that the Linux prerequisites are out of scope.
  - To scan the same set: move `mark` into its own step that runs before both test-prereqs and the suite, and keep `check` in the suite step.
  - This changes R9, and V2 records the wider window.

## F1.3 R9 (the CI wiring) has no test after merge

R10 tests R1–R8 against fixture roots. Nothing pins R9: that `mark` comes before make in both steps, that `check` runs after a failing make, and how the step's exit status is built from make, report and check. V3 proves the wiring once, on a scratch branch that is never merged. After that, a workflow edit can quietly undo it, for example dropping the `check` line or exiting with `report_rc` in the macOS block. Every run would then stay green.

- **Fix:** add a test in the repo's existing per-job style ("a CI-file assertion must parse per job", CLAUDE.md). It asserts, for each of the two steps, mark before make, check after make with no early `exit` between them, and that the step's final exit can come from `check`. Extend R10 to cover R9.

## Smaller items

- **F1.4 (unmeasured):** both hosted runners have passwordless sudo, so R7's "any non-zero `find` status fails" applies on both. As I recall, root `find` on macOS can still get `Operation not permitted` under SIP/TCC. I did not check whether any directory under `/private/etc`, `/usr/local` or `/opt` does this. V1 has a rule for hits only, not for a non-zero status. To check: on `macos-latest`, run `sudo -n find /private/etc /usr/local /opt -xdev >/dev/null; echo $?` and capture stderr. V1 should record `find`'s status and stderr, and the spec should state the outcome when they are non-clean: the gate does not ship.
- **F1.5:** on macOS, `BATS_TEST_TMPDIR` sits under `/var/folders`, which `pwd -P` resolves to `/private/var/folders`. Fixture tests that compare reported paths with the unresolved fixture path will fail on the Studio and macOS shards, but not on Linux. Resolve the expected path in the test too.

No `## External Review` author-response table exists yet, so there are no accepted / not accepted lines.

Fix F1.1–F1.3 before the plan. F1.1 is the only one that changes the design, by adding a small prune mechanism that must be specified up front. The design otherwise stopped moving in round 3, and V1/V2 will surface the rest with real data, so another review round would cost more than it finds.

Recommend: stop
