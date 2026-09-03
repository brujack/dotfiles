# ADR-0028: AWS CLI download signature verification

**Date:** 2026-09-01
**Status:** Accepted

## Context

`lib/developer.sh` downloads the AWS CLI installer over HTTPS and hands it to `sudo` with
no integrity check. Two functions do this: `update_aws_cli` (the weekly `-t update` path)
and `install_aws_tools` (the first-install path a fresh machine takes). Neither has ever
verified that AWS produced the artifact it is about to run as root.

`ci.md`'s third-party-binary rule requires integrity verification before executing a
downloaded artifact. Measured 2026-09-01: zero `sha256sum` calls exist anywhere under
`lib/` or `scripts/` — every occurrence in the repo is in `.github/workflows/ci.yml`. The
rule had never been applied to a runtime install path here. (This is a claim about
`lib/` and `scripts/` in this repo only; it says nothing about the other eight repos, and
it does not claim no other verification mechanism exists — the Homebrew bootstrap already
pins a git commit SHA, a different mechanism, out of scope here.)

### What AWS actually publishes

Measured 2026-09-01 by probing the CDN and inspecting the artifacts, not from
documentation or recall:

| URL                                                    | status  |
| ------------------------------------------------------ | ------- |
| `awscli.amazonaws.com/AWSCLIV2.pkg`                    | 200     |
| `awscli.amazonaws.com/awscli-exe-linux-x86_64.zip`     | 200     |
| `awscli.amazonaws.com/awscli-exe-linux-x86_64.zip.sig` | **200** |
| `awscli.amazonaws.com/AWSCLIV2.pkg.sig`                | **404** |
| `awscli.amazonaws.com/AWSCLIV2.pkg.sha256`             | **404** |

AWS publishes a detached GPG signature for the Linux zip and nothing for the macOS pkg.
The pkg is Apple-signed and notarized instead. AWS publishes no sha256 for either
artifact.

## Decision

Verify by signature, not by checksum, with a vendored public key pinned by fingerprint —
GPG detached-signature verification on Linux, `pkgutil` team-ID assertion on macOS. Two
helpers in `lib/developer.sh`, `_aws_verify_zip` and `_aws_verify_pkg`, called by both
`update_aws_cli` and `install_aws_tools` so the weekly path and the first-install path get
identical treatment. The trust anchor is `keys/aws-cli-team.asc`, vendored rather than
fetched — a key that arrives over the same channel it authenticates is not a trust
anchor — with its fingerprint pinned in `lib/constants.sh` as `AWSCLI_GPG_FPR` and the
Apple team ID as `AWSCLI_APPLE_TEAM_ID`.

### Rejected: `AWSCLI_VER` pin plus a computed sha256

AWS publishes no sha256 for either artifact, so this would mean recording a hash _we_
computed on first sight of the artifact — trust-on-first-use, weaker than a signature, and
stale on every release, requiring a `check-versions` arm to notice and a human to
fetch-and-rehash. It was also unnecessary: a detached `.sig` exists for the Linux
artifact, and a signature is per-artifact rather than per-version, so the rolling URL can
stay exactly as it is and `-t update` keeps tracking latest with no version constant at
all.

### Rejected: an ETag bracket around the two fetches

The zip and its `.sig` are two independent fetches from a rolling URL, so an AWS release
landing between them produces a genuine fingerprint mismatch on a benign event. A design
considered bracketing both fetches with `curl -fsSI` HEAD requests and comparing ETags,
failing closed if they differed.

Measured from the v2 CHANGELOG: 976 releases across roughly 6.5 years, about one every 2.4
days, against a roughly 30-second window between the two fetches, on the 2 Linux machines
that reach this code, run weekly. Expected spurious failures: about 1 per 12–20 years. The
standing cost — 2 extra HEAD requests per run, an `awk` parse, a comparison, additional
test rows, and lines against a coverage floor with zero margin — bought protection against
an event that will not occur in this repo's lifetime.

Retry-on-verification-failure covers every case the ETag bracket covered and two it did
not: a truncated download and a CDN edge inconsistency both leave the ETag unchanged, so
the bracket would have missed them and reported them as signature failures, while a retry
recovers.

The bracket also failed on its own terms: `curl -fsSI` on a 404 sets rc=22 and still
emits headers, and `$(curl ... | awk ...)` takes `awk`'s exit status, discarding curl's.
Two failed HEADs therefore produced identical (empty) parsed ETags — `before == after`,
read as "equal", the success verdict, having measured nothing. The guard absorbed its own
failure in exactly the mechanism built to prevent a misattribution.

### Rejected: versioned-URL resolution

A version-pinned URL, resolved the way the repo already resolves other tools' latest
releases via `_fetch_github_latest` (`lib/workflows.sh`), was considered as an alternative
to the rolling URL. `aws/aws-cli` publishes no GitHub releases — `releases/latest` returns
404 — so the existing helper cannot resolve a version this way at all. Only the tags API
carries version information, which would add a rate-limited GitHub dependency to the
weekly update path for no integrity benefit, since the signature mechanism already made a
version pin unnecessary.

## The macOS/Linux asymmetry is forced, not chosen

AWS publishes a detached `.sig` for the Linux zip and none for the macOS pkg — measured
200 versus 404. The pkg is Apple-signed and notarized instead, so the verification
mechanism on macOS is necessarily different: `pkgutil --check-signature` rather than GPG.
This is not a design preference; it is the only mechanism the artifact supports.

Two measurements justify the macOS arm's existence and were not assumed:

**`sudo installer` performs no signature enforcement of its own.** An unsigned package
built with `pkgbuild` installs cleanly as root:

```
$ sudo installer -pkg /tmp/unsigned.pkg -target /
installer: Package name is unsigned
installer: Installing at base path /
installer: The install was successful.
   rc=0
```

`installer` names the defect in its own output and proceeds anyway. `_aws_verify_pkg` is
therefore the only thing standing between a network artifact and `sudo` on macOS, not a
belt-and-suspenders addition to an OS check that already runs.

**`pkgutil --check-signature`'s exit code alone is not sufficient.** Measured against the
real pkg: rc=0, chain leaf `Developer ID Installer: AMZN Mobile LLC (94KV3E626L)`. Any
Apple-notarized package from any developer also produces rc=0 — confirmed against a
Microsoft-signed pkg already present on a development machine, chain leaf
`Developer ID Installer: Microsoft Corporation (UBF8T346G9)`, rc=0. The guard must assert
the team-ID string, not the exit code, or it accepts any notarized publisher's package as
if it were AWS's.

## Fail-closed policy and the reject-before-accept ordering

`_aws_verify_zip` branches on the content of gpg's `--status-fd` output, never on gpg's
own exit status, because GnuPG emits `VALIDSIG` for a good signature _and_ for one made
with an expired or revoked key — gpg exits 0 in both of those cases (`EXPKEYSIG` and
`REVKEYSIG`, respectively). `EXPSIG` — an expired _signature_, independent of key
expiry — exits 1, but is included in the reject list anyway for the same reason: the
helper never inspects gpg's exit status at all, so all three states are checked
uniformly against `${_status}`'s content.

The reject list, checked before the accept arm:

```
EXPSIG|EXPKEYSIG|KEYEXPIRED|REVKEYSIG|KEYREVOKED
```

`BADSIG` and `ERRSIG` are deliberately excluded — both are already covered by the accept
arm's failure to match `VALIDSIG`, and a reject list that grows by superstition is harder
to reason about than one whose every member is justified.

**Expired and revoked keys produce different messages, because they demand opposite
operator responses.** `EXPSIG`/`EXPKEYSIG`/`KEYEXPIRED` means the vendored snapshot aged
out — remedied by pulling the repo and refreshing the key file. `REVKEYSIG`/`KEYREVOKED`
means AWS actively revoked the key — remedied by stopping and investigating, not by
refreshing anything. Collapsing them into one message would hand the one certain,
active-compromise event on this path the loudest label the system has, with no correct
remedy attached.

**The vendored key expires 2027-07-01** (measured via `gpg --show-keys --with-colons`,
`expires=1814472778`). Without the reject arm, the Linux mechanism would silently degrade
on that date from "AWS signed this with a live key" to "AWS signed this with a lapsed
key", reporting a pass throughout, with no test able to catch it. On that date the `aws`
section of `-t update` begins failing on the machines that reach this path — 2 of 7
(`linux_workstation` and `wsl2_workstation`; macOS reaches `_aws_verify_pkg`, which has no
key and no expiry) — until the vendored key is refreshed. This is mitigated, not
eliminated, by a `doctor` arm added in the same change that warns when the key is within N
days of expiry, gated on `HAS_AWS` so it does not fire on machines correctly lacking the
AWS CLI.

## Consequences

**A vendored key must be refreshed before 2027-07-01**, or the `aws` section of `-t update`
starts failing on the two machines that reach the Linux verification path. The `doctor`
arm warns ahead of that date; nothing currently signals _how_ AWS will rotate the key
(in place, extending the same fingerprint, versus a new key entirely) — that remains an
open question, recorded rather than resolved.

**Four test seams exist purely to make otherwise-unreachable branches testable**:
`_AWS_GPG_BIN`, `_AWS_PKGUTIL_BIN`, `_AWS_KEY_PATH`, and `_AWS_BIN` (the analogous
override for the `aws` binary itself, used to drive `install_aws_tools`'s
already-installed branch). Driving a verifier-absent case through `PATH` directly would
mean removing `/opt/homebrew/bin`, which also holds `git` and `make` — the same
"delete a directory to delete one binary" hazard `shell.md` names for `tests/mocks`. Each
seam is read unconditionally in production and grants nothing beyond what editing `PATH`
already grants.

**18 pre-existing tests had to be updated** because gating the installer on verification
changed `update_aws_cli` and `install_aws_tools`'s contract for every existing caller,
including test callers. `tests/setup_env/extracted_functions.bats` carried tests asserting
the old contract (installer invoked unconditionally); `tests/setup_env/workflows.bats` and
`tests/setup_env/unit.bats` reached `install_aws_tools` transitively through
`run_setup_or_developer`. `shell.md`'s contract-widening rule — enumerate every call site
before changing a function's return contract — applies identically to test callers, and
cost this change two re-plans before that enumeration was done up front for the later
tasks.

**Neither verifier mock (`tests/mocks/gpg`, `tests/mocks/pkgutil`) can express this
design's central assertion** — both were stdout-silent while both helpers assert on
stdout, which would have made every negative test case pass vacuously. `_aws_verify_zip`
is therefore tested against a real, throwaway GPG key generated per test rather than a
stub; `_aws_verify_pkg` keeps a `pkgutil` stub (extended with a stdout knob) because the
`test` CI job runs on `ubuntu-latest`, where `pkgutil` does not exist at all.

## Related

- Spec: [2026-09-01-awscli-signature-verification-design.md](../superpowers/specs/2026-09-01-awscli-signature-verification-design.md)
- Plan: [2026-09-01-awscli-signature-verification.md](../superpowers/plans/2026-09-01-awscli-signature-verification.md)
- [ADR-0027](0027-update-run-exit-code-from-section-status.md) — the exit-code contract this change relies on to make a failed `aws` section externally visible
- [ADR-0013](0013-no-curl-bash-installs.md) — the prior integrity-verification decision this ADR extends to a second class of download
