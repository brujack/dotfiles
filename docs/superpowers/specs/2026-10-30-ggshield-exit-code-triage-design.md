# pre-commit hook: triage the ggshield scan's exit code

- **Date:** 2026-10-30
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

- `pre-commit` sends staged files as documents in chunks. A chunk closes at
  `maximum_documents_per_scan` documents, or when the payload would pass
  `maximum_payload_size - 10240`. A document over `maximum_document_size` is skipped, not sent.
- The chunks are scanned concurrently. In `_collect_results`, a `ConnectionError` or `Timeout`
  on any chunk raises `ServiceUnavailableError` (rc 4) and **discards the results already
  collected**, including secrets found by chunks that finished.
- So for a multi-chunk commit, rc 4 can mean "a secret was found and then thrown away". For a
  single-chunk commit, rc 4 means no result was ever collected.

The limits are server preferences, cached in `~/.cache/ggshield/auth_check.yaml`. For this
account on 2026-10-30 (`claude`): `maximum_documents_per_scan: 20`, `maximum_document_size:
1048576`, `maximum_payload_size: 26214400`. Twenty documents of at most 1 MiB each stay under the
payload ceiling, so with these preferences the staged-file count alone decides the chunk count.
`GG_MAX_DOCS` overrides the document limit on the client side. Population: one account's server
preferences, read once; nothing in the hook re-reads them.

Recent commit sizes (`git log --since=2026-07-01 --shortstat origin/master`, non-merge): the five
largest touched 26, 26, 26, 30 and 32 files. Multi-chunk commits happen in this repo.

## Latency of a degraded scan

Measured 2026-10-30 on `claude`, same scratch repo, one staged file:

- Refused proxy (`HTTPS_PROXY=http://127.0.0.1:9`): rc 4 in under a second.
- Blackholed proxy (`HTTPS_PROXY=http://10.255.255.1:9`): rc 4 after 28 s.
- Blackholed proxy with `GITGUARDIAN_API_TIMEOUT=10`: rc 4 after 16 s.

28 s is tolerable for a hook that then continues, so the hook does not set a timeout.

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
  default fail-closed) turns rc 4 into exit 0 with a warning. It has the same chunk-discard hole,
  it cannot express the single-chunk condition, and its warning does not carry the hook's
  `SECRET SCAN DID NOT RUN` marker. The hook therefore pins `--fail-on-server-error` so that a
  machine-level `false` cannot silently pre-empt the hook's rc 4 arm.
- `ai-devops/scripts/pre-commit` already does a three-way triage: block on 1, warn and continue
  on every other non-zero code. That fails open on rc 2 and rc 128, and on multi-chunk rc 4. Its
  comment cites unreachable as rc 3. `ai-config/scripts/pre-commit-hook.sh` resolves with bare
  `command -v` and runs the scan as its last command, so absence is silent and any non-zero rc
  blocks. Neither is changed here.

## Decision

Operator, 2026-10-30, in two steps:

1. Allowlist 3 and 4: warn and continue only on the codes ggshield documents as environmental.
   Everything else outside 0 blocks. Unknown fails closed.
2. After the round-1 review showed the chunk-discard behaviour: rc 4 warns and continues only
   when the staged set fits one chunk (at most 20 staged paths). Otherwise rc 4 blocks.

## Design

In `scripts/pre-commit-hook.sh`, replace `"${_ggshield}" secret scan pre-commit "$@" || exit 1`
with:

1. Run `"${_ggshield}" secret scan pre-commit --fail-on-server-error "$@"` and capture its rc.
2. `case` on the rc:

| rc                           | Action           | stderr                                                                                                                                                                                                                        |
| ---------------------------- | ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0                            | continue, exit 0 | none                                                                                                                                                                                                                          |
| 1                            | exit 1           | none added (ggshield prints its findings)                                                                                                                                                                                     |
| 3                            | continue, exit 0 | `pre-commit: ggshield could not authenticate (exit 3) — SECRET SCAN DID NOT RUN`, then a remedy line naming `ggshield auth login` and `GITGUARDIAN_API_KEY`                                                                   |
| 4, at most 20 staged paths   | continue, exit 0 | `pre-commit: GitGuardian unreachable (exit 4) — SECRET SCAN DID NOT RUN`, then a line saying CI `secret-scan` still gates the PR                                                                                              |
| 4, more than 20 staged paths | exit 1           | `pre-commit: GitGuardian unreachable (exit 4) during a multi-chunk scan of <n> staged paths — ggshield discards partial findings, blocking`, then a remedy line (retry when online, or split the commit to 20 paths or fewer) |
| any other                    | exit 1           | `pre-commit: ggshield failed (exit <rc>) — unknown failure, blocking`; for rc 2 also a line noting that `--fail-on-server-error` needs ggshield 1.50.0 or later                                                               |

- The staged-path count is `git diff --cached --name-only -z` counted by NUL. It counts
  deletions too, which only overcounts. Overcounting makes rc 4 block more often, never less.
- The threshold 20 is a hook constant, `_GG_SINGLE_CHUNK_MAX=20`. Its comment records the server
  preference it mirrors, the date read, and that a lower server value would make the rc 4 allow-path
  admit multi-chunk commits. It is not an environment override.
- The phrase `SECRET SCAN DID NOT RUN` is the one the unresolved-binary branch already prints.
  Every path where no scan result exists shares one greppable marker. The multi-chunk rc 4 block
  does not print it, because part of the scan may have run.
- The comment above the `case` records the enum, the 2026-10-30 measurements, the chunk-discard
  behaviour, and why 2 and 128 block. rc 2 is a usage error, but also what a 401 during the scan
  produces: a key revoked inside the 300 s auth cache (`core/auth_check_cache.py`) passes the
  startup check, gets rc 2 on that one commit, and rc 3 on the next. rc 128 includes quota
  exhaustion (`QuotaLimitReachedError`).
- The resolution logic above the scan, and the unresolved-binary branch, are unchanged.

## Testing

TDD in `tests/scripts/pre_commit_hook.bats`, using the existing `_write_ggshield_mock <rc>` stub:

- One test per rc in {0, 1, 2, 3, 5, 128}, each asserting the hook's exit status from the table
  above. rc 5 stands for "a code ggshield adds later".
- rc 4 three times: with 1 staged path (exit 0), with exactly 20 (exit 0) and with 21 (exit 1).
- rc 0: assert the mock was invoked (`MOCK_CALLS_FILE`) with `--fail-on-server-error`, so the
  exit-0 case fails if the hook stops running the scan or drops the flag.
- rc 3 and rc 4 at 1 and 20 paths: output contains `SECRET SCAN DID NOT RUN`.
- rc 1 and rc 4 at 21 paths: output does not contain `SECRET SCAN DID NOT RUN`.
- rc 2, 5 and 128, and rc 4 at 21 paths: output contains `exit <rc>`. rc 2 output also names
  1.50.0.
- The existing test "pre-commit-hook.sh exits 1 when ggshield fails" stays as the rc 1 case.
- Mutation controls before commit: map rc 3 to block; map `*)` to continue; change the threshold
  comparison from `<=` to `<`; drop `--fail-on-server-error`. Each must turn at least one test red.

## Docs

- `CLAUDE.md`, the pre-commit bullet ("If unresolvable, exit 0 but announce the skip..."): add
  that rc 3 warns and continues, rc 4 warns and continues only for 20 staged paths or fewer, and
  every other non-zero rc blocks.
- `docs/superpowers/README.md`: mark the backlog row done.
- Backlog rows in ai-devops (fails open on rc 2, 128 and multi-chunk rc 4; comment cites
  unreachable as 3) and in ai-config (bare `command -v`, silent when absent, no triage), each in
  its own repo's `docs/superpowers/README.md`.
- Backlog row in this repo: ggshield drops a chunk on a 429 or other unhandled 4xx and still
  exits 0 (`handle_scan_chunk_error`); the hook cannot see it.

## Requirements

- **R1.** `[PR1]` `scripts/pre-commit-hook.sh` exits 0 when the ggshield scan exits 0 or 3, or exits 4 with at most 20 staged paths.
- **R2.** `[PR1]` `scripts/pre-commit-hook.sh` exits 1 when the ggshield scan exits 4 with more than 20 staged paths, or exits any value other than 0, 3 or 4.
- **R3.** `[PR1]` The hook prints `SECRET SCAN DID NOT RUN` and the rc on stderr for scan rc 3, and for scan rc 4 with at most 20 staged paths; it does not print `SECRET SCAN DID NOT RUN` for scan rc 1 or for scan rc 4 with more than 20 staged paths.
- **R4.** `[PR1]` For every blocking scan rc other than 1 the hook prints the rc on stderr, and for rc 2 it also names ggshield 1.50.0.
- **R5.** `[PR1]` The hook passes `--fail-on-server-error` to `ggshield secret scan pre-commit`.
- **R6.** `[PR1]` `tests/scripts/pre_commit_hook.bats` covers scan rc 0, 1, 2, 3, 5 and 128, and rc 4 with 1, 20 and 21 staged paths, and the rc 0 case asserts the scanner was invoked with `--fail-on-server-error`.
- **R7.** `[PR1]` The `CLAUDE.md` pre-commit bullet states the rc 3 and single-chunk rc 4 warn-and-continue rule.
- **V1.** Mutation controls: mapping rc 3 to block, mapping the default arm to continue, changing the threshold comparison, and dropping `--fail-on-server-error` each turn at least one test red.
- **V2.** A commit in the feature worktree with ggshield ambient and authenticated prints ggshield's `No secrets have been found` and exits 0.
- **N1.** No pre-flight `ggshield api-status` probe or any other extra network call.
- **N2.** No change to how ggshield is resolved (`GGSHIELD_BIN`, `PATH`, `GGSHIELD_FALLBACK_PATHS`) or to the unresolved-binary branch.
- **N3.** No edits to the ai-devops or ai-config hooks in this change.
- **N4.** The hook does not set `GITGUARDIAN_API_TIMEOUT`.

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
Disposition: Latency: Accepted, reason: 28 s measured, tolerable for a hook that then continues
(N4). rc 0 test: Addressed, it now asserts the scanner was invoked with the pinned flag.
Persistence: Accepted, reason: CI `secret-scan` gates every PR.

### Risk

Finding: rc 4 can occur while a secret is staged. `_collect_results` raises
`ServiceUnavailableError` on the first chunk that times out and discards findings from chunks that
completed (verified in `secret_scanner.py`). The CI backstop is gitleaks, a different detector set.
A 401 during the scan is rc 2, so a revoked key still blocks for one commit. ggshield's native
fail-open re-implemented outside it. A 429 or other unhandled 4xx drops a chunk and exits 0
(pre-existing, invisible to the hook).
Assumption: rc 4 means no findings exist; true only when the commit is one chunk. Settled: chunks
close at 20 documents for this account, and five recent commits touched 26-32 files.
Disposition: Addressed: rc 4 warns and continues only at 20 staged paths or fewer, and blocks
otherwise (operator decision, 2026-10-30). The rc 2 path is recorded in the comment. The
429 hole goes to the backlog.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
