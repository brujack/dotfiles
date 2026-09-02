# AWS CLI Download Signature Verification Implementation Plan

> **Status: DONE**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify that AWS produced the AWS CLI installer before handing it to `sudo`, on both the update path and the first-install path.

**Architecture:** Two verification helpers in `lib/developer.sh` — `_aws_verify_zip` (GPG detached signature, Linux) and `_aws_verify_pkg` (`pkgutil` team ID, macOS) — plus a shared `_aws_gpg_fail` reporter. Both are called by `update_aws_cli` and `install_aws_tools`, so the fresh-machine path and the weekly path get identical treatment. The trust anchor is a vendored public key at `keys/aws-cli-team.asc` pinned by fingerprint in `lib/constants.sh`.

**Tech Stack:** bash, gnupg 2.x, `pkgutil` (macOS builtin), bats, `scripts/run-bash-coverage.sh`.

**Spec:** [2026-09-01-awscli-signature-verification-design.md](../specs/2026-09-01-awscli-signature-verification-design.md)

## Global Constraints

- `AWSCLI_GPG_FPR` is `FB5DB77FD5C118B80511ADA8A6310ACC4672475C` — measured from AWS's docs page and verified end-to-end against the real artifact. No spaces.
- `AWSCLI_APPLE_TEAM_ID` is `94KV3E626L` — measured from `pkgutil --check-signature` on the real pkg.
- The reject list is `EXPSIG|EXPKEYSIG|KEYEXPIRED|REVKEYSIG|KEYREVOKED`. `EXPSIG` is signature expiry, distinct from key expiry. `BADSIG`/`ERRSIG` are deliberately excluded — the accept arm already covers them.
- Reject arms run **before** the accept arm. `VALIDSIG` is emitted for expired keys, revoked keys and expired signatures. gpg exits 0 for the first two; `EXPSIG` exits 1 (measured, GnuPG 2.5.22). The helper branches on `${_status}` content, never on gpg's exit status, so all three are uniform.
- Every reject is `if ... then ... fi` with an explicit terminal `exit 0`. Never `grep ... && return 1` — one reorder from rejecting a clean signature.
- `_aws_verify_zip`'s body runs in a `( )` subshell with an `EXIT` trap. `trap ... RETURN` is **not** function-scoped in bash and fires again with `_ring` out of scope; `gpgconf --homedir ""` resolves to the operator's real `~/.gnupg`.
- `_status` and `_err` live **inside** `_ring` so the one trap removes them.
- gpg's stderr is captured, never `2>/dev/null` — it is the only stream separating "no valid OpenPGP data" from a bad signature.
- Every `curl` fetching an artifact or signature carries `-f`.
- Coverage: the floor is 91% and holds when `C >= 0.91N - 21.5`. For `N ≈ 56` new coverable lines, `C >= 30`. `lib/developer.sh` is 216 coverable lines at base.
- No `AWSCLI_VER` pin, no `check-versions` arm, no ETag bracket. All three were considered and rejected on measurement; see the spec.

## Verification Planning

**Command that proves the whole change works:**

```bash
make test && make bash-coverage
```

**Expected observable:** `make test` green with the new bats cases present; `make bash-coverage` reports ≥91% with `lib/developer.sh`'s denominator grown by ~56 lines and at least 30 of them covered.

**Edge cases that must be exercised to be confident** — each is a task acceptance gate below, not a hope:

- An **expired** key and a **revoked** key each produce `VALIDSIG` _and_ gpg exit 0, and are still rejected, with **different** messages.
- A verification failure retries exactly once and then reports FAIL — the retry does not mask a genuine tamper.
- The operator's real `~/.gnupg` agent survives a verification.
- A leftover download does not suppress the install.
- `install_aws_tools` failing does not abort `-t setup` before `run_developer_or_ansible`.

---

### Task 1: Pin the key fingerprint and Apple team ID

```yaml-task
id: 1
description: Add AWSCLI_GPG_FPR and AWSCLI_APPLE_TEAM_ID to lib/constants.sh with a test deriving the fingerprint from the vendored key
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bash -c "source lib/constants.sh; [[ -n \${AWSCLI_GPG_FPR:-} ]]"'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/constants.sh
  - tests/setup_env/developer.bats
depends_on: []
```

**Base-tree value:** the first gate exits **1** (measured) — the constant does not exist.

**Files:** `lib/constants.sh` gains two `readonly`-style constants beside the existing `*_VER` block, each with the one-line consumer annotation that file's header demands. `keys/aws-cli-team.asc` already exists on this branch.

**Test:** derive the fingerprint from the vendored file and compare to the constant — two independent artifacts that can drift apart:

```bash
_fpr="$(gpg --show-keys --with-colons keys/aws-cli-team.asc | awk -F: '/^fpr/{print $10; exit}')"
[[ "${_fpr}" == "${AWSCLI_GPG_FPR}" ]]
```

Deriving both from the same source would be the circular check `behavior.md` warns about. This is not that: the file and the constant are separate artifacts.

**Interfaces:**

- Produces: `AWSCLI_GPG_FPR` (40-hex, no spaces), `AWSCLI_APPLE_TEAM_ID` (`94KV3E626L`). Every later task reads both from `lib/constants.sh`.

---

### Task 2: `_aws_gpg_fail` and `_aws_verify_zip`, against real gpg

```yaml-task
id: 2
description: Add the GPG verification helper and its failure reporter, tested against a throwaway key rather than a stub
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bash -c "source lib/developer.sh; declare -f _aws_verify_zip >/dev/null"'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/developer.sh
  - tests/setup_env/developer.bats
depends_on: [1]
```

**Base-tree value:** the first gate exits **1** (measured) — the function does not exist.

**Files:** `lib/developer.sh` gains `_aws_gpg_fail` and `_aws_verify_zip`. Copy the body verbatim from the spec's Linux section — subshell, `EXIT` trap, `_status`/`_err` inside `_ring`, reject-before-accept, split revoked/expired messages, explicit `exit 0`.

**Seams:** `_AWS_GPG_BIN` (defaults `gpg`) and `_AWS_KEY_PATH` (defaults the repo's `keys/aws-cli-team.asc`). Both read unconditionally in production. They grant nothing beyond editing `PATH`, and without them the verifier-absent and fingerprint-mismatch branches are unreachable — a `PATH` strip removing `/opt/homebrew/bin` takes `git` and `make` with it.

**Tests — all real gpg, in `BATS_TEST_TMPDIR`, with `tests/mocks` stripped from `PATH`:**

```bash
gpg --homedir "$ring" --batch --quick-generate-key "Test <t@e>" default default 4h
```

Cases: good signature (returns 0); **expired key**; **revoked key** (import the auto-generated `.rev`); fingerprint mismatch (valid signature, different key); corrupt signature; verifier absent via `_AWS_GPG_BIN=/nonexistent`; the vendored key verifies a real AWS `.sig`.

**Assert on `${_status}` contents, not only the return code.** For the expired and revoked cases assert the file held `VALIDSIG <fpr>` **and** `EXPKEYSIG`/`REVKEYSIG`, that gpg exited 0, and that the helper still failed. A fail-closed guard cannot distinguish its own non-execution from a correct rejection — return-code-only assertions pass against a helper that never ran gpg.

**Also assert the real keyring survives:** capture `gpgconf --list-dirs homedir`'s agent liveness before and after. This is the regression test for the `trap RETURN` defect.

**Interfaces:**

- Consumes: `AWSCLI_GPG_FPR` from Task 1.
- Produces: `_aws_verify_zip <zip> <sig>` → 0 verified, 1 otherwise. `_aws_gpg_fail <errfile> <message>` → prints message plus the tail of gpg's stderr.

---

### Task 3: `_aws_verify_pkg` and the `pkgutil` mock stdout knob

```yaml-task
id: 3
description: Add the macOS verification helper and give tests/mocks/pkgutil a stdout knob, keeping its existing exit knob
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bash -c "source lib/developer.sh; declare -f _aws_verify_pkg >/dev/null"'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/developer.sh
  - tests/mocks/pkgutil
  - tests/setup_env/developer.bats
depends_on: [1]
```

**Base-tree value:** the first gate exits **1** — the function does not exist.

**Files:** `_aws_verify_pkg` asserts the team ID string, **not** `pkgutil`'s exit code — rc=0 is returned for any Apple-notarized package from any developer (measured). Reads `_AWS_PKGUTIL_BIN`.

**Mock change is backward-compatible.** `tests/mocks/pkgutil` currently appends argv to `MOCK_CALLS_FILE` and exits `${MOCK_PKGUTIL_EXIT:-1}`. Keep both. Add `MOCK_PKGUTIL_STDOUT`, printed when set. `MOCK_PKGUTIL_EXIT` has **3 live consumers** — `tests/setup_env/macos.bats:45,56,66`, the Rosetta check at `lib/macos.sh:25` — which must keep passing.

**Tests:** team ID mismatch (rc=0, different team ID → helper fails); good pkg signature (helper returns 0 **and** the installer IS invoked — the positive control); verifier absent via `_AWS_PKGUTIL_BIN=/nonexistent`.

**Unsigned-pkg case is macOS-only and needs a skip guard.** Both bats CI jobs run `ubuntu-latest`, where `pkgutil` does not exist; `lint-macos` runs no bats. Guard it, or CI goes red on every run.

**Interfaces:**

- Consumes: `AWSCLI_APPLE_TEAM_ID` from Task 1.
- Produces: `_aws_verify_pkg <pkg>` → 0 verified, 1 otherwise.

---

### Task 4: Wire verification into `update_aws_cli`

```yaml-task
id: 4
description: Fetch the .sig, add curl -f, call the verifiers, and retry once on verification failure
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'grep -c "curl -fsS" lib/developer.sh'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/developer.sh
  - tests/setup_env/developer.bats
  - tests/setup_env/extracted_functions.bats
depends_on: [2, 3]
```

**Base-tree value:** `lib/developer.sh:22` and `:40` are `curl "<url>" -o "<file>" || return 1` with **no `-f`** — a 404 lands on disk with rc=0 and would render as a signature failure.

**Scope widened mid-execution (re-plan 1 of 2), and the omission is instructive.**
`tests/setup_env/extracted_functions.bats` carries three pre-existing `update_aws_cli` tests
asserting the OLD contract — `status -eq 0` with the installer invoked. Gating the installer
on verification necessarily breaks all three, and the implementer, correctly staying inside
its declared scope, could not fix them.

The plan's original `files_touched` was derived by asking _what does this task edit_, and
`writing-plans` self-review item 8 checks exactly that: does the file list cover what the task
body describes touching. It did. The question neither asked is **what else calls the function
whose contract this changes** — a caller-enumeration, not a file-list check. `shell.md`'s
contract-widening entry states the same rule for production callers ("enumerate every call
site before editing any of them"); it applies identically to test callers, and nothing in the
plan-authoring path prompts for it.

**How to apply when authoring:** for any task that changes a function's return contract or
adds a gate, `grep -rn '<function>' tests/` and put every hit in `files_touched`. A test file
is a call site.

**Files:** macOS branch fetches the pkg and calls `_aws_verify_pkg`. Linux branch fetches zip **and** `${url}.sig`, then calls `_aws_verify_zip`. On verification failure, re-fetch both **once** and re-verify; a genuine tamper still fails on the second pass. Do not add an ETag bracket — measured at one spurious failure per 12–20 years, and it misses truncated downloads the retry catches.

**A `.sig` fetch failure must say _could not fetch_, not _did not verify_.** Different remedies; `ci.md` records this misattribution costing 200 consecutive daily runs.

**Tests:** verification fails once then succeeds → one retry, section OK; verification fails twice → FAIL; `.sig` fetch 404s → message names the fetch, not the signature.

**Interfaces:**

- Consumes: `_aws_verify_zip`, `_aws_verify_pkg`.

---

### Task 5: Rewrite `install_aws_tools`

```yaml-task
id: 5
description: Add error propagation and verification to the first-install path and fix its leftover-download guard
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bash -c "grep -A30 \"^install_aws_tools\" lib/developer.sh | grep -q \"|| return 1\""'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/developer.sh
  - tests/setup_env/developer.bats
  - tests/setup_env/workflows.bats
depends_on: [4]
```

**Base-tree value:** the first gate exits **1** — `install_aws_tools` (`lib/developer.sh:65-92`) contains no `|| return` anywhere and returns 0 unconditionally.

**`workflows.bats` is in scope from the start, by enumeration rather than discovery.** Task 4
cost two re-plans for exactly this omission, so the callers were counted before dispatch:
`grep -rn 'install_aws_tools' tests/` returns **15** references, all in
`tests/setup_env/workflows.bats` — 4 direct `install_aws_tools` tests at `:529`, `:538`,
`:550`, `:557`, plus `run_setup_or_developer` cases that stub it at `:1422-1429`. Changing
this function's contract necessarily reaches them. `tests/setup_env/unit.bats` also names
`run_setup_or_developer` but only asserts it is _defined_ (`:593-594`) and never calls it, so
it is deliberately excluded.

The rule Task 4 paid for, stated so it is not re-derived: **enumerate transitive callers, not
direct ones.** `shell.md` says to enumerate every call site before changing a return contract;
a test is a call site, and a caller of a caller is one too. The first correction to this plan
grepped for the function name and still missed 15 tests that reach it through `run_update`.

**Files:** `|| return 1` on every step; remove the downloaded artifact on installer failure so the next run re-fetches; call the verifiers before `sudo`.

**Fix the guard.** Both branches currently test `[[ ! -f <download> ]]`, so a leftover download from an interrupted run **suppresses the install entirely** and the function reports success having done nothing. The guard wants "is aws already installed" — which the `command -v aws` check at the bottom of each branch already asks, after the fact. Make the install conditional on the tool's absence, not a file's absence.

**Test:** a stale zip/pkg present → `install_aws_tools` still installs.

---

### Task 6: Degrade the caller, and add the key-expiry doctor arm

```yaml-task
id: 6
description: Change install_aws_tools call site to log_warn and add a HAS_AWS-gated doctor check for vendored key expiry
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'grep -q "install_aws_tools || log_warn" lib/workflows.sh'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - lib/helpers.sh
  - tests/setup_env/workflows.bats
  - tests/setup_env/unit.bats
depends_on: [5]
```

**Base-tree value:** the first gate exits **1** — `lib/workflows.sh:236` is `install_aws_tools || return 1`.

**Files:** that guard is **dormant** today (the function body has no `|| return`), and Task 5 arms it. Armed as-is, a transient `wget` failure aborts `-t setup` before `setup_vim_plugins` and `run_developer_or_ansible` — losing pyenv, the ansible venv, ruby and rust. Match the precedent 18 lines above at `lib/workflows.sh:218-219` (`install_renovate_held_agent || log_warn`).

**Doctor arm** warns when the vendored key is within N days of expiry — it lapses **2027-07-01**, and under fail-closed the aws section then fails until the key is refreshed. It watches expiry, not tool presence: expiry is certain and dated, tool presence is contingent.

**Gate it on `HAS_AWS`.** `_doctor_check_tools` (`lib/helpers.sh:465`) has an unconditional `_common_tools` array and no capability-conditional arm, so the obvious implementation appends to it. `PROFILE_CAPS[mac_mini]="gui printing"` carries no `aws` and three hostnames map to it (`office`, `office-1`, `home-1`); `run_doctor` exits non-zero on any failure, so an ungated arm makes `-t doctor` permanently red on machines correctly lacking the AWS CLI.

**Tests:** `install_aws_tools` failing → `run_setup_or_developer` continues and warns; doctor arm silent on a `mac_mini` profile; doctor arm warns on a near-expiry fixture key.

---

### Task 7: ADR-0028 — signature verification over checksum pinning

```yaml-task
id: 7
description: Write ADR-0028 recording the verification decision and its rejected alternatives (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: "test -f docs/adr/0028-awscli-download-signature-verification.md"
    exit_code: 0
  - cmd: 'grep -qE "Status:.*Accepted" docs/adr/0028-awscli-download-signature-verification.md'
    exit_code: 0
max_retries: 3
files_touched:
  - docs/adr/0028-awscli-download-signature-verification.md
  - docs/adr/README.md
depends_on: [6]
```

`tdd: not-applicable` — a decision record, no behaviour change.

**Why an ADR:** `repo-structure.md` names security guardrails in its significance list, and this is the first integrity check on any runtime install path in this repo — measured, zero `sha256sum` calls exist under `lib/` or `scripts/` today. Comparable-scope decisions here (ADR-0024, ADR-0026, ADR-0027) all got one at plan time rather than as post-merge backfill.

**The status gate is tolerant on purpose.** `grep -qE "Status:.*Accepted"` matches this directory's actual convention, `**Status:** Accepted` — 29 of 30 existing ADRs. A literal `grep -q "Status: Accepted"` cannot match those bytes and would force the implementer to write the directory's only format outlier: a gate that shapes the artifact instead of testing it.

**Content:** signature over checksum (AWS publishes a `.sig`, no sha256, so per-artifact verification needs no version pin); the macOS/Linux asymmetry as forced rather than chosen; the three rejected alternatives with their measurements — `AWSCLI_VER` pinning, the ETag bracket, versioned-URL resolution; and the fail-closed policy with its dated 2027-07-01 consequence.

---

### Task 8: Docs, coverage, and plan index

```yaml-task
id: 8
description: Record the new test seams in CLAUDE.md, update the coverage figure, mark the plan Done
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "_AWS_GPG_BIN" CLAUDE.md'
    exit_code: 0
  - cmd: make test
    exit_code: 0
  - cmd: make bash-coverage
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
  - docs/superpowers/README.md
  - docs/superpowers/plans/2026-09-01-awscli-signature-verification.md
depends_on: [7]
```

`tdd: not-applicable` — documentation and index updates only, no behaviour change.

**Base-tree value:** the first gate exits **1** — the seam is undocumented.

**Files:** `CLAUDE.md`'s Test Seams table gains `_AWS_GPG_BIN`, `_AWS_PKGUTIL_BIN`, `_AWS_KEY_PATH`, each with the reason the branch is otherwise unreachable. Update the Bash coverage figure and its denominator from `make bash-coverage`'s actual output — **report both, a percentage without its denominator is not a coverage figure.** Add the All Plans row and the `> **Status: DONE**` banner.

**If coverage lands under 91%,** the remedy is coverage rows for the `install_aws_tools` rewrite, not a floor change. The budget is `C >= 0.91N - 21.5`; at `N ≈ 56` that is 30 of 56 covered, leaving ~26 uncovered.
