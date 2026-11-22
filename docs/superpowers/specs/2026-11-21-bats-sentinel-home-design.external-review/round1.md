Tools: Read, Bash, SubagentHandback

The core mechanism is right; keep it. Using bats' own `setup_suite.bash` lookup puts the boundary where every invocation passes through it: make, coverage, pre-push, CI and a direct `bats tests/x.bats`. Making the hooks regular files that source one helper avoids the symlink `BASH_SOURCE` trap. The parts that took ten rounds now match bats 1.13.0's source on `claude`. I read `/usr/libexec/bats-core/bats` lines 455-495 (`potential_setup_suite_file` is the first argument's directory) and `bats-exec-suite` lines 245-300 (`setup_suite` runs under `set -eET`; `teardown_suite … || status=$?` runs from the EXIT trap; a teardown failure is reported only when `BATS_SETUP_SUITE_COMPLETED` is set). These are: the unset-first rule for the sentinel variable, the `[[ -e ]]` removal check that the always-0 `tests/mocks/rm` cannot fool, the subshelled `cd`, and `PARALLEL_HOME`. The premise also holds. `tests/bats-files.txt` puts every listed file in exactly the four directories R9 names (7/42/61/4). `pinned_uv.bats` unsets `PINNED_UV_BIN` in `setup()`, so R4's export does not make the resolver's default-path tests vacuous.

## F1.1 The residue gate does not protect the real HOME, and the spec never says what it is for

- **Defect.** Once `setup_suite` swaps `HOME`, a test that writes `$HOME` writes the sentinel, which is thrown away. So the residue failure (R5's listing branch, R6, and V2, V4, V5, V6 second half, plus about half of R10's fixtures) never prevents a write to the operator's home. What it actually enforces is the per-file convention the Problem section calls a failure: "redirect HOME in that test's setup()".
- **Its real jobs, both unstated.** (a) Hermeticity inside one run: under `--jobs 24` the 60 files that do not redirect `HOME` share one sentinel home, so one test's leftover can change another's result. (b) Defence for a run that loads no hook, for example `--setup-suite-file` or a directory without `setup_suite.bash`. But R10's directory guard already covers the second case, and the residue check cannot fire there, because there is no sentinel.
- **Concrete cost.**
  - A future maintainer, or an F16-class test, hits `not ok teardown_suite` for a write that harmed nothing. Nothing in the spec says why the fix is mandatory, so the gate reads as decoration and invites a silencing edit.
  - Most of rounds 7-10 went into this gate's own apparatus: residue ordering, the `rm` shim, the single-line `residue:` format, and V5's draft-PR CI control. That is machinery growth tied to a decision whose rationale was never written down.
- **Smallest fix.** No design switch at this stage. Add one Design §1 sentence stating the gate's purpose (a) and (b) above, and that it is not what protects the real `HOME`.
  - If the operator decides (a) is not worth enforcing, the cheaper design is the sentinel plus R7 removal only. That drops R5's residue branch, R6, R10's residue fixtures, V2, V4, V5 and V6's second half.
  - Either way, record the choice. This changes the Design §1 prose and possibly the residue clauses of R5, R6 and R10.
- **Measurement.** None needed: this follows from R2. The sentinel is in place before any `.bats` file runs (`bats-exec-suite` line 296 runs before the `parallel` launch).

## Smaller items

- **F1.2.** V9's evidence is self-attributed. It runs `find "$HOME" -newer <stamp>` on `claude`, where the clone itself is under `/home/bruce/git-repos` and seven peer sessions write `$HOME` the whole time. The excluded entries are then whatever the agent judges to be peers'. That is self-reported evidence for the one class (writes that bypass `HOME`) nothing else checks.
  - Fix on Linux: use a mechanical observer. `strace -f -qq -e trace=%file -e status=successful -o <log> make test-bats </dev/null`, then grep the log for write-flagged `openat`/`mkdir`/`rename`/`unlink` calls under the real home, outside the sentinel and the clone. A read-only home is also available unprivileged: `bwrap --dev-bind / / --ro-bind <dir> <dir> sh -c 'touch <dir>/x'` gave `Read-only file system`, rc 1 (bubblewrap 0.11.1, Linux 7.0.0-43, `claude`). It is only a complement, because a test that swallows write errors would hide behind it.
  - The Studio keeps `find`, but should take a same-length control window without the suite and diff against it.
  - This changes V9's method sentence only.

No prior `## External Review` round, so there is no `Author response` table to answer.

Before the plan: record F1.1's rationale. F1.2 is a change to verification wording and can go in with the plan. The design itself has not moved since round 8. Rounds 8-10 and this one found only verification and test-apparatus defects, so another round is not worth its cost.

Recommend: stop
