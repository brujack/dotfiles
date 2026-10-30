# pre-commit hook: triage the ggshield scan's exit code

- **Date:** 2026-10-30
- **Approved:** 2026-10-30
- **Backlog row:** "The pre-commit hook resolves ggshield but never checks it is _usable_, and an unusable scanner blocks every commit" (P2 — CI)

## Problem

`scripts/pre-commit-hook.sh` runs `"${_ggshield}" secret scan pre-commit "$@" || exit 1`. Every
non-zero exit blocks the commit, so a scanner that resolves but cannot scan — a bad, revoked or
missing credential, or GitGuardian unreachable — blocks every commit in the repo. The unblock an
author reaches for is `git commit --no-verify`, which also drops `make lint` and the rest of the
chain. A degraded secret scan therefore pushes the author toward disabling every gate at once.

## Premise check

Measured 2026-10-30 on `claude`, ggshield 1.56.1 (`/home/linuxbrew/.linuxbrew/bin/ggshield`),
`secret scan pre-commit` in a throwaway repo under the session scratchpad with one benign staged
file. Population: one machine, one ggshield version, the `pre-commit` subcommand only.

| Condition                                | How produced                               | rc                                                                     |
| ---------------------------------------- | ------------------------------------------ | ---------------------------------------------------------------------- |
| ambient credential, clean file           | no override                                | 0                                                                      |
| malformed credential                     | `GITGUARDIAN_API_KEY=bogus0000`            | 3                                                                      |
| no credential                            | `HOME=<empty dir>`, `GITGUARDIAN_API_KEY=` | 3                                                                      |
| server unreachable, valid credential     | `HTTPS_PROXY=http://127.0.0.1:9`           | 4                                                                      |
| custom instance URL with no stored token | `GITGUARDIAN_API_URL=https://127.0.0.1:9`  | 3 (auth fails before any network call; not a reachability measurement) |
| non-HTTPS instance URL                   | `GITGUARDIAN_API_URL=http://127.0.0.1:9`   | 2                                                                      |

The codes match ggshield's own `ExitCode` enum (`ggshield/core/errors.py`, 1.56.1): `SUCCESS=0`,
`SCAN_FOUND_PROBLEMS=1`, `USAGE_ERROR=2`, `AUTHENTICATION_ERROR=3`,
`GITGUARDIAN_SERVER_UNAVAILABLE=4`, `UNEXPECTED_ERROR=128`. The found-a-secret case (rc 1) was not
measured live: producing it needs a real-shaped secret sent to GitGuardian. It rests on the enum.

Two corrections to the backlog row follow:

- The row recorded an unreachable instance as rc 3. On 1.56.1 it is rc 4. The row's probe likely
  hit the custom-URL auth path in the table above, or an older version. The design below does
  not depend on which: an unreachable server reaching the hook as rc 3 is still warn-and-continue.
- The row's finding that `ggshield api-status` exits 0 while printing `unhealthy` stands, but it
  no longer matters. The scan's own exit code separates "found a secret" from "could not scan",
  so no pre-flight probe is needed.

## Chunking: rc 4 does not always mean "nothing scanned"

Read in the installed 1.56.1 source (`ggshield/verticals/secret/secret_scanner.py`):

- `pre-commit` sends staged changes as documents in chunks. A chunk closes at
  `maximum_documents_per_scan` documents, or when the JSON-encoded payload would pass
  `maximum_payload_size - 10240`. A document over `maximum_document_size` (raw bytes) is skipped,
  not sent.
- The chunks are scanned concurrently. In `_collect_results`, a `ConnectionError` or `Timeout`
  on any chunk raises `ServiceUnavailableError` (rc 4) and **discards the results already
  collected**, including secrets found by chunks that finished.
- So for a multi-chunk commit, rc 4 can mean "a secret was found and then thrown away".

The limits are server preferences, cached in `~/.cache/ggshield/auth_check.yaml`. For this
account on 2026-10-30 (`claude`): `maximum_documents_per_scan: 20`, `maximum_document_size:
1048576`, `maximum_payload_size: 26214400`. Recent commit sizes (`git log --since=2026-07-01
--shortstat origin/master`, non-merge): 7 of 1101 touched more than 20 files, the largest 32.
Multi-chunk commits happen in this repo, rarely.

No condition the hook can evaluate cheaply and reliably separates a single-chunk rc 4 from a
multi-chunk one: the chunk count depends on server preferences, `GG_MAX_DOCS`, and JSON-escaped
payload size. This is why rc 4 blocks (see Decision).

## Latency of a degraded scan

Measured 2026-10-30 on `claude`, same scratch repo, one staged file:

- Refused proxy (`HTTPS_PROXY=http://127.0.0.1:9`): rc 4 in under a second.
- Blackholed proxy (`HTTPS_PROXY=http://10.255.255.1:9`): rc 4 after 28 s.
- Blackholed proxy with `GITGUARDIAN_API_TIMEOUT=10`: rc 4 after 16 s.

The hook does not set a timeout. An offline commit waits up to about 28 s, then blocks.

## Existing gates on the same hazard

- CI `secret-scan` (gitleaks over `HEAD~50..HEAD` of the PR merge ref,
  `.github/workflows/ci.yml`) is in `auto-merge`'s `needs:`. Every PR commit is scanned,
  regardless of what the local hook did. gitleaks is a different detector set from GitGuardian,
  so it backstops the class, not the same secrets.
- Direct-to-master pushes of inert `.md` files and the root `LICENSE` run no CI. A commit made
  under a degraded scan and pushed that way is scanned by nothing.

## Prior art

- ggshield's own `--fail-on-server-error/--no-fail-on-server-error`
  (`GITGUARDIAN_FAIL_ON_SERVER_ERROR`, config `secret.fail_on_server_error`, added in 1.50.0,
  default fail-closed) turns rc 4 into exit 0 with a warning, with the same chunk-discard hole.
  A machine setting it `false` would let a multi-chunk rc 4 through silently. The hook therefore
  pins `--fail-on-server-error`.
- `ai-devops/scripts/pre-commit` already does a three-way triage: block on 1, warn and continue
  on every other non-zero code. That fails open on rc 2, rc 128 and rc 4. Its comment cites
  unreachable as rc 3. `ai-config/scripts/pre-commit-hook.sh` resolves with bare `command -v`
  and runs the scan as its last command, so absence is silent and any non-zero rc blocks.
  Neither is changed here.

## Decision

Operator, 2026-10-30, in three steps:

1. Allowlist 3 and 4: warn and continue only on the codes ggshield documents as environmental.
   Everything else outside 0 blocks. Unknown fails closed.
2. After round 1 showed the chunk-discard behaviour: rc 4 warns only for 20 staged paths or fewer.
3. After round 2 found every new defect in that arm (a failed path count read as 0 and admitted
   rc 4; the 20-path bound does not hold under JSON-escaped payload sizing; the threshold mirrors a
   server preference nothing re-reads): **rc 4 always blocks.** Only rc 3 warns and continues.

The reasoning for the asymmetry: rc 3 (bad, expired or missing credential) persists until a human
re-authenticates, so blocking on it blocks every commit, which is the harm this spec removes. rc 4
(server unreachable) is transient and clears on retry, and it is the code that can hide a
discarded finding.

## Design

In `scripts/pre-commit-hook.sh`, replace `"${_ggshield}" secret scan pre-commit "$@" || exit 1`
with:

1. Run `"${_ggshield}" secret scan pre-commit --fail-on-server-error "$@"` and capture its rc.
2. `case` on the rc:

| rc | Action | stderr |
|----|--------|--------|
| 0 | continue, exit 0 | none |
| 1 | exit 1 | none added (ggshield prints its findings) |
| 3 | continue, exit 0 | `pre-commit: ggshield could not authenticate (exit 3) — SECRET SCAN DID NOT RUN`, then a remedy line naming `ggshield auth login` and `GITGUARDIAN_API_KEY` |
| 4 | exit 1 | `pre-commit: GitGuardian unreachable (exit 4) — blocking: a partial scan can discard findings`, then a remedy line: retry when the network is back |
| any other | exit 1 | `pre-commit: ggshield failed (exit <rc>) — unknown failure, blocking`; for rc 2 also a line noting that `--fail-on-server-error` needs ggshield 1.50.0 or later |

- The phrase `SECRET SCAN DID NOT RUN` is the one the unresolved-binary branch already prints.
  Only rc 3 joins it, because only rc 3 continues without a result.
- The comment above the `case` records the enum, the 2026-10-30 measurements, the chunk-discard
  behaviour behind the rc 4 block, and why 2 and 128 block. rc 2 is a usage error, but also what
  a 401 during the scan produces: a key revoked inside the 300 s auth cache
  (`core/auth_check_cache.py`) passes the startup check, gets rc 2 on that one commit, and rc 3 on
  the next. rc 128 includes quota exhaustion (`QuotaLimitReachedError`).
- The resolution logic above the scan, and the unresolved-binary branch, are unchanged.

## Testing

TDD in `tests/scripts/pre_commit_hook.bats`, using the existing `_write_ggshield_mock <rc>` stub:

- One test per rc in {0, 1, 2, 3, 4, 5, 128}, each asserting the hook's exit status from the
  table above. rc 5 stands for "a code ggshield adds later".
- Every exit-0 case (rc 0 and rc 3) asserts the mock was invoked (`MOCK_CALLS_FILE`) with
  `--fail-on-server-error`. Without this, both pass through the unresolved-binary branch, which
  also exits 0.
- rc 3: output contains `SECRET SCAN DID NOT RUN` and `(exit 3)`.
- rc 1 and rc 4: output does not contain `SECRET SCAN DID NOT RUN`.
- rc 2, 4, 5 and 128: output contains `exit <rc>`. rc 2 output also names 1.50.0.
- The existing test "pre-commit-hook.sh exits 1 when ggshield fails" stays as the rc 1 case.
- Mutation controls before commit: map rc 3 to block; map `*)` to continue; map rc 4 to
  continue; drop `--fail-on-server-error`; route rc 3 to the unresolved-binary message. Each must
  turn at least one test red.

## Docs

- `CLAUDE.md`, the pre-commit bullet ("If unresolvable, exit 0 but announce the skip..."): add
  that scan rc 3 warns and continues, and every other non-zero rc (rc 4 included) blocks.
- `docs/superpowers/README.md`: mark the backlog row done.
- Backlog rows in ai-devops (fails open on rc 2, 4 and 128; comment cites unreachable as 3) and in
  ai-config (bare `command -v`, silent when absent, no triage), each in its own repo's
  `docs/superpowers/README.md`.
- Backlog row in this repo: ggshield drops a chunk on a 429 or other unhandled 4xx and still
  exits 0 (`handle_scan_chunk_error`); the hook cannot see it.

## Requirements

- **R1.** `[PR1]` `scripts/pre-commit-hook.sh` exits 0 when the ggshield scan exits 0 or 3.
- **R2.** `[PR1]` `scripts/pre-commit-hook.sh` exits 1 when the ggshield scan exits any value other than 0 or 3.
- **R3.** `[PR1]` For scan rc 3 the hook prints `SECRET SCAN DID NOT RUN` and `(exit 3)` on stderr; for scan rc 1 and rc 4 it does not print `SECRET SCAN DID NOT RUN`.
- **R4.** `[PR1]` For every blocking scan rc other than 1 the hook prints the rc on stderr, and for rc 2 it also names ggshield 1.50.0.
- **R5.** `[PR1]` The hook passes `--fail-on-server-error` to `ggshield secret scan pre-commit`.
- **R6.** `[PR1]` `tests/scripts/pre_commit_hook.bats` covers scan rc 0, 1, 2, 3, 4, 5 and 128, and the rc 0 and rc 3 cases assert the scanner was invoked with `--fail-on-server-error`.
- **R7.** `[PR1]` The `CLAUDE.md` pre-commit bullet states that scan rc 3 warns and continues and every other non-zero scan rc blocks.
- **V1.** Mutation controls: mapping rc 3 to block, mapping the default arm to continue, mapping rc 4 to continue, dropping `--fail-on-server-error`, and routing rc 3 to the unresolved-binary message each turn at least one test red.
- **V2.** A commit in the feature worktree with ggshield ambient and authenticated prints ggshield's `No secrets have been found` and exits 0.
- **N1.** No pre-flight `ggshield api-status` probe or any other extra network call.
- **N2.** No change to how ggshield is resolved (`GGSHIELD_BIN`, `PATH`, `GGSHIELD_FALLBACK_PATHS`) or to the unresolved-binary branch.
- **N3.** No edits to the ai-devops or ai-config hooks in this change.
- **N4.** The hook does not set `GITGUARDIAN_API_TIMEOUT`.
- **N5.** The hook does not count staged paths or read ggshield's server preferences.

## Multi-Lens Review

Reviewed at commit: `710c91ce` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Worth building, premise verified (hook line and the 3/4 mapping, before and during the
scan). Missed: ggshield's native `--no-fail-on-server-error` handles rc 4, and a machine setting it
`false` would make the hook's rc 4 arm dead and the skip silent. A 401 during the scan, within the
300 s auth cache, exits 2, not 3, so "rc 2 always means misuse" is wrong for that path. Reads-it:
it changes a decision (block to continue); nothing persists the warning beyond stderr.
Assumption: a revoked credential surfaces as rc 3, not rc 2. Source reading says rc 2 for exactly
one commit inside the cache TTL, then rc 3.
Disposition: Addressed: the hook pins `--fail-on-server-error`, and the design comment records the
rc 2 path. Persistence: Accepted, reason: CI `secret-scan` gates every PR.

### Ergonomics

Finding: rc 4 has no latency bound; the spec measured only a refused port, and a blackholed route
could take minutes (60 s timeout, 5 retries). The rc 0 test would pass if the hook never ran the
scan. The warning is not persisted.
Assumption: an outage reaches the hook as rc 4 quickly. Settled by measurement on 2026-10-30:
28 s blackholed, 16 s with `GITGUARDIAN_API_TIMEOUT=10`.
Disposition: Latency: Accepted, reason: 28 s measured (N4). rc 0 test: Addressed, it now asserts
the scanner was invoked with the pinned flag. Persistence: Accepted, reason: CI `secret-scan` gates
every PR.

### Risk

Finding: rc 4 can occur while a secret is staged. `_collect_results` raises
`ServiceUnavailableError` on the first chunk that times out and discards findings from chunks that
completed (verified in `secret_scanner.py`). The CI backstop is gitleaks, a different detector set.
A 401 during the scan is rc 2, so a revoked key still blocks for one commit. ggshield's native
fail-open re-implemented outside it. A 429 or other unhandled 4xx drops a chunk and exits 0
(pre-existing, invisible to the hook).
Assumption: rc 4 means no findings exist; true only when the commit is one chunk. Settled: chunks
close at 20 documents for this account, and recent commits touched up to 32 files.
Disposition: Addressed: round 1 gated rc 4 on 20 staged paths or fewer (operator, 2026-10-30);
superseded in round 2 by rc 4 always blocking. The rc 2 path is recorded in the comment. The 429
hole goes to the backlog.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2

Reviewed at commit: `c2010bea` (round-1 revision). All three lenses re-ran, because the revision
changed design substance.

- **Goal-Fit (`c2010bea`).** Finding: still worth building; rc 3 alone solves the stated harm.
  The single-chunk rc 4 arm costs the most for the least value: a git subprocess, a constant that
  mirrors a server preference and drifts silently, three tests and a mutation control. The
  revision added a fail-open: a failed `git diff --cached` count reads 0 and admits rc 4. The rc 3
  and rc 4 (1, 20 paths) tests pass through the unresolved-binary branch. Assumption: rc 4
  outages are frequent enough to justify an arm; no outage data. Disposition: Addressed: rc 4
  always blocks (operator, 2026-10-30), which removes the count, the constant and the fail-open;
  every exit-0 test asserts the scanner was invoked.
- **Ergonomics (`c2010bea`).** Finding: the rc 3 and rc 4 (1, 20 paths) exit-0 tests pass if the
  hook never runs the scanner, because the unresolved-binary branch prints the same marker and
  exits 0. The >20-path block is acceptable: 7 of 1101 commits since July exceeded 20 files, and
  the PreToolUse guard already refuses the bypass flag for agents. Assumption: one document per
  staged path. Disposition: Addressed: every exit-0 test asserts invocation and `(exit 3)`; a
  mutation control routes rc 3 to the unresolved message. The path-count assumption is moot (N5).
- **Risk (`c2010bea`).** Finding: the rc 4 allow-path fails open when the path count fails; only
  the 21-path test exercises the counter. "Twenty documents of at most 1 MiB stay under the payload
  ceiling" is false: the size limit is on raw bytes, chunks are sized on JSON-escaped bytes (up to
  6x). Checked clean: path count bounds documents, renames, merges, `"$@"`, rc 4 from the metadata
  step, the flag's existence. Assumption: the server's `maximum_documents_per_scan` stays at least
  20 on every machine; nothing re-reads it. Disposition: Addressed: rc 4 always blocks, so the
  count, the bound and the preference are no longer read (N5); the payload sentence is corrected
  in the Chunking section.

Stop signals after round 2: every round-2 finding sat in the rc 4 arm or the test apparatus, and
the round-2 correction removed mechanism (path count, constant, three tests, one requirement)
without adding any. Both signals point to stopping.
