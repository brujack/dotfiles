# ADR-0052: pre-commit triages the ggshield scan exit code

**Date:** 2026-10-30
**Status:** Accepted

## Context

`scripts/pre-commit-hook.sh` ran `ggshield secret scan pre-commit "$@" || exit 1`, so every
non-zero exit blocked the commit. A scanner that resolves but cannot scan, such as a bad,
revoked or missing credential, therefore blocked every commit in the repo. The escape an
author reaches for is the hook-bypass flag, which also drops `make lint` and the rest of the
chain.

ggshield 1.56.1 types its exit codes (`ggshield/core/errors.py`): 0 clean, 1 found, 2 usage,
3 auth, 4 server unavailable, 128 unexpected. Measured 2026-10-30: a bad or missing key exits 3
and an unreachable server exits 4, so the scan's own code separates "found a secret" from
"could not scan" without a pre-flight probe.

Exit 4 is not always "nothing scanned". The pre-commit scan sends staged files in chunks of
the server's `maximum_documents_per_scan` (20 for this account). When one chunk times out,
`_collect_results` raises `ServiceUnavailableError` and discards the findings of chunks that
already finished. A multi-chunk commit can therefore exit 4 with a secret found and thrown
away. Commits here exceed 20 paths occasionally (7 of 1101 since July).

Alternatives considered and rejected:

- **Warn and continue on 3 and 4.** It lets a multi-chunk exit 4 through with findings
  discarded.
- **Warn on 4 only for a single-chunk commit (20 staged paths or fewer).** A failed path
  count read as 0 and admitted exit 4. The bound does not hold under JSON-escaped payload
  sizing. The threshold mirrors a server preference nothing re-reads.
- **An `api-status` pre-flight probe.** It exits 0 while printing `unhealthy`, and it adds a
  network call.
- **ai-devops' shape (block on 1, warn on everything else).** It fails open on 2, 4, 128 and
  any future code.

## Decision

The hook captures the scan's exit code and branches on it:

- 0 continues.
- 3 warns `SECRET SCAN DID NOT RUN` with a `ggshield auth login` remedy, and continues.
- 1 (found), 2 (usage error, or a 401 during the scan), 4 (unreachable) and every other code
  block with a cause-specific message. Unknown fails closed.

The scan pins `--fail-on-server-error`, so a machine-level `fail_on_server_error: false`
cannot turn exit 4 into a silent 0. The flag needs ggshield 1.50.0 or later, and the exit-2
message says so.

The asymmetry is deliberate. Exit 3 persists until a human re-authenticates, so blocking on it
blocks every commit. Exit 4 is transient, clears on retry, and is the code that can hide a
discarded finding.

## Consequences

- A lapsed credential no longer blocks commits. The commit is announced as unscanned on
  stderr, and CI `secret-scan` (gitleaks, a different detector set) still gates every PR.
  Direct-to-master pushes of inert `.md` files and the root `LICENSE` get no scan.
- An offline commit is blocked after up to about 28 s (measured with a blackholed proxy),
  until the network returns.
- A key revoked inside ggshield's 300 s auth cache gets exit 2, and blocks, on one commit. The
  next commit sees exit 3.
- A ggshield older than 1.50.0 rejects the pinned flag with exit 2 and blocks every commit
  until it is upgraded. The Studio, `claude` and the workstation run 1.56.1.
- ggshield's own gap is out of reach: a 429 or other unhandled 4xx drops a chunk and still
  exits 0. It is recorded in the backlog.

## Related

- Spec: [`docs/superpowers/specs/2026-10-30-ggshield-exit-code-triage-design.md`](../superpowers/specs/2026-10-30-ggshield-exit-code-triage-design.md)
- Plan: [`docs/superpowers/plans/2026-10-30-ggshield-exit-code-triage.md`](../superpowers/plans/2026-10-30-ggshield-exit-code-triage.md)
- Shipped in dotfiles#408 (`6d8110aa`)
- [ADR-0016](0016-auto-install-git-hooks.md): how the hooks are installed
