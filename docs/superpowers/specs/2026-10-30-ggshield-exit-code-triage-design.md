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
  hit the custom-URL auth path in the table above, or an older version. Either way the design
  below treats 3 and 4 alike, so it holds under both readings.
- The row's finding that `ggshield api-status` exits 0 while printing `unhealthy` stands, but it
  no longer matters. The scan's own exit code separates "found a secret" from "could not scan",
  so no pre-flight probe is needed.

## Existing gates on the same hazard

- CI `secret-scan` (gitleaks over recent commits, `.github/workflows/ci.yml`) is in
  `auto-merge`'s `needs:`. Every PR is scanned regardless of what the local hook did.
- Direct-to-master pushes of inert `.md` files and the root `LICENSE` run no CI. A commit made
  under a degraded scan and pushed that way is scanned by nothing.

## Prior art

`ai-devops/scripts/pre-commit` already does a three-way triage: block on 1, warn and continue on
every other non-zero code. That fails open on rc 2 (usage error) and rc 128 (unexpected crash),
and its comment cites unreachable as rc 3. `ai-config/scripts/pre-commit-hook.sh` resolves with
bare `command -v` and runs the scan as its last command, so absence is silent and any non-zero rc
blocks. Neither is changed here.

## Decision

Operator, 2026-10-30: allowlist 3 and 4. Warn and continue only on the two codes ggshield
documents as environmental. Everything else outside 0 blocks. Unknown fails closed.

## Design

In `scripts/pre-commit-hook.sh`, replace `"${_ggshield}" secret scan pre-commit "$@" || exit 1`
with a capture of the scan's rc and a `case` on it:

| rc        | Action           | stderr                                                                                                                                                      |
| --------- | ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0         | continue, exit 0 | none                                                                                                                                                        |
| 1         | exit 1           | none added (ggshield prints its findings)                                                                                                                   |
| 3         | continue, exit 0 | `pre-commit: ggshield could not authenticate (exit 3) — SECRET SCAN DID NOT RUN`, then a remedy line naming `ggshield auth login` and `GITGUARDIAN_API_KEY` |
| 4         | continue, exit 0 | `pre-commit: GitGuardian unreachable (exit 4) — SECRET SCAN DID NOT RUN`, then a line saying CI `secret-scan` still gates the PR                            |
| any other | exit 1           | `pre-commit: ggshield failed (exit <rc>) — unknown failure, blocking`                                                                                       |

- The phrase `SECRET SCAN DID NOT RUN` is the one the unresolved-binary branch already prints.
  Every degraded path then shares one greppable marker.
- The comment above the `case` records the enum, the 2026-10-30 measurements, and why 2 and 128
  block (a usage error or a crash is not known to be environmental).
- The resolution logic above the scan, and the unresolved-binary branch, are unchanged.

## Testing

TDD in `tests/scripts/pre_commit_hook.bats`, using the existing `_write_ggshield_mock <rc>` stub:

- One test per rc in {0, 1, 2, 3, 4, 5, 128}, each asserting the hook's exit status from the
  table above. rc 5 stands for "a code ggshield adds later".
- rc 3 and rc 4: output contains `SECRET SCAN DID NOT RUN`.
- rc 1: output does not contain `SECRET SCAN DID NOT RUN`, so a block is never reported as a skip.
- rc 2, 5 and 128: output contains `exit <rc>`.
- The existing test "pre-commit-hook.sh exits 1 when ggshield fails" stays as the rc 1 case.
- Mutation controls before commit: map rc 3 to block, and map `*)` to continue. Each must turn
  at least one new test red.

## Docs

- `CLAUDE.md`, the pre-commit bullet ("If unresolvable, exit 0 but announce the skip..."): add
  that rc 3 and 4 warn and continue, and that every other non-zero rc blocks.
- `docs/superpowers/README.md`: mark the backlog row done.
- Backlog rows in ai-devops (fails open on rc 2 and 128; comment cites unreachable as 3) and in
  ai-config (bare `command -v`, silent when absent, no triage), each in its own repo's
  `docs/superpowers/README.md`.

## Requirements

- **R1.** `[PR1]` `scripts/pre-commit-hook.sh` exits 0 when the ggshield scan exits 0, 3 or 4.
- **R2.** `[PR1]` `scripts/pre-commit-hook.sh` exits 1 when the ggshield scan exits any value other than 0, 3 or 4.
- **R3.** `[PR1]` For scan rc 3 and rc 4 the hook prints `SECRET SCAN DID NOT RUN` and the rc on stderr; for scan rc 1 it does not print `SECRET SCAN DID NOT RUN`.
- **R4.** `[PR1]` For a blocking scan rc other than 1 the hook prints the rc on stderr.
- **R5.** `[PR1]` `tests/scripts/pre_commit_hook.bats` covers scan rc 0, 1, 2, 3, 4, 5 and 128.
- **R6.** `[PR1]` The `CLAUDE.md` pre-commit bullet states the rc 3/4 warn-and-continue rule.
- **V1.** Mutation controls: mapping rc 3 to block, and mapping the default arm to continue, each turn at least one test red.
- **V2.** A commit in the feature worktree with ggshield ambient and authenticated still runs the scan and exits 0.
- **N1.** No pre-flight `ggshield api-status` probe or any other extra network call.
- **N2.** No change to how ggshield is resolved (`GGSHIELD_BIN`, `PATH`, `GGSHIELD_FALLBACK_PATHS`) or to the unresolved-binary branch.
- **N3.** No edits to the ai-devops or ai-config hooks in this change.
