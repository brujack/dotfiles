Tools: Read, Bash, SubagentHandback

The spec gets the core right, and none of it should change. It compares the symlink's raw bytes (`hash-object --no-filters`) with the local default branch's blob, so it runs no repo-supplied code and does not fire on branch names or origin lag. It checks that the ref exists (`show-ref`) before the blob lookup, so rc 1 from the lookup can only mean "path not on the branch". An empty or failed hash is an `error` and is never compared. Copy-installed hooks are left alone. The pre-push self-check is rightly rejected. V1's mutation is not vacuous: the R4 case's target *is* the working-tree file, so a working-tree comparison always reads `match` and goes red.

### F1.1 R1 picks a stale leftover `master` when both `main` and `master` exist

**Defect.** R1 chooses `main` only when `refs/heads/master` is absent. A `main` repo that still has a local `master` (a common leftover after a GitHub default-branch rename) is therefore judged against the stale `master` blob.

**Failure.** Take a clean main checkout on `main` whose hook is unchanged. If `pre-push` changed on `main` since `master` was left behind, doctor warns `scripts/pre-push differs from master`. The remedy then tells the operator to diff against the wrong branch and "return to a clean master", which means switching branches, the very thing section 2 says the remedy must not ask for. The Measured section says only that claude has no such leftover. The three Macs and the Windows box were not looked at.

**Measurement.** git 2.53.0, Linux 7.0.0-43, fixture in scratch. Ran `git init -b main`, committed `scripts/pre-push`, ran `git branch master`, then committed a change to the hook on `main`. Results:
- `show-ref --verify -q refs/heads/master` gives rc=0.
- main blob `8b2fe54…`, master blob `039e4d0…`, working-tree hash `8b2fe54…`.
- R1 selects `master`, so the result is `drift`, although the checkout is clean.

**Smallest fix.** When both refs exist, use the one HEAD is symbolically on if it is `main` or `master`. Otherwise fall back to `master`, or return `error` with "both main and master exist". Change R1 to say this, and add a fourth R1 case to R10 (both exist, HEAD on `main`).

### F1.2 The doctor arm cannot build R8's remedy from what `_git_hooks_identity` returns

**Defect.** R8's message needs both `<default>` and `<candidate>` (`git -C <dir> diff <default> -- <candidate>`). The doctor loop receives only `_word` and `_reason` (`IFS=$'\t' read -r _word _reason`, `lib/helpers.sh:1028`). Neither R4/R5 nor section 2 says how the arm gets those two values.

**Failure.** The implementer has to choose between two bad routes:
- Parse the English reason, which breaks silently if the wording changes.
- Re-derive the default branch in `helpers.sh`, which duplicates R1 and can disagree with it (especially after the F1.1 fix).

**Smallest fix.** Make `drift` print machine fields, for example `drift<TAB><reason><TAB><default><TAB><candidate>`, and have the doctor read `_word _reason _default _cand`. Existing words print fewer fields, so their reads are unaffected. Record the field order in R4/R5, and have R8's test assert the remedy line for both a `master` repo and a `main` repo.

### Smaller items

- **F1.3 V3 does not isolate its side effects.** This review's own incident makes that matter.
  - `make install-hooks` in the scratch clone first runs `ledger-symlink`, which does `mkdir -p` and `ln -s` under `${HOME}/.local/bin` (Makefile:309-317).
  - Doctor finds repos at `${GITREPOS}/personal/<name>` (`lib/constants.sh:217`).
  - V3 should name `HOME=<scratch>` and `GITREPOS=<scratch>`, with the clone at `<scratch>/personal/dotfiles`. It should also call `_doctor_check_git_hooks` rather than the full `-t doctor`, since nothing else is under test.
- **F1.4 Round 3's "Disposition:" line is empty.** Its assumption is a real known limit: an unpushed local commit to a hook script on the default branch becomes the reference and reads `match`. Record it under Design next to the CRLF limit, so the gap is chosen rather than left open. Reading `refs/remotes/origin/<default>` would close it without network, but N2 forbids that ref; that is the trade.
- **F1.5 Stale cross-references in Multi-Lens Review round 1.** "V4 adds a copy-side positive check" names a verification that does not exist. "R8 makes a failed or empty hash an `error`" is now R6. Annotate both as superseded.

There was no previous `Author response` table, so there are no accepted or not-accepted lines.

The design is stable after three rounds. Fix F1.1 and F1.2 before the plan; both are small, local edits to R1, R4/R5, R8 and R10. F1.3 to F1.5 are wording and test apparatus. The first red tests will find anything else, so another round is not worth its cost.

Recommend: stop
