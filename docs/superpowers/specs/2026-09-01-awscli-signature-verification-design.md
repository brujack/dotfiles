# AWS CLI download signature verification — design

Date: 2026-09-01
Backlog rows: #6 (live), #23 (falsified — see Backlog Hygiene)

## Problem

`lib/developer.sh` downloads the AWS CLI installer over HTTPS and hands it to `sudo`
without verifying that AWS produced it. Two functions do this, and only one of them has
ever been examined.

`update_aws_cli` (`lib/developer.sh:17-44`) fetches `AWSCLIV2.pkg` (macOS) or
`awscli-exe-linux-$(uname -m).zip` (Linux) and runs `sudo -H installer` /
`sudo -H aws/install`. Error propagation here is correct as of #250 (`97a7678f`): every
step carries `|| return 1`. What it has never had is any integrity check.

`install_aws_tools` (`lib/developer.sh:65-92`) is the first-install path — the one a fresh
machine takes — and has neither. `wget`, `sudo installer`, `unzip` and `sudo -H aws/install`
are all unchecked, there is no `|| return` anywhere in the function, and there is no
verification of any kind.

`ci.md`'s third-party-binary rule requires integrity verification before executing a
downloaded artifact. Measured 2026-09-01: **zero `sha256sum` calls exist anywhere under
`lib/` or `scripts/`** — all four occurrences in the repo are in `.github/workflows/ci.yml`.
The rule has never been applied to a runtime install path here.

### Population note

The claim "zero verification in runtime install paths" is measured over `lib/` and
`scripts/` in this repo only, by `grep -rn sha256sum`. It is not a claim about the other
eight repos, and it is not a claim that no _other_ verification mechanism exists — the
Homebrew bootstrap pins a git commit SHA (`HOMEBREW_INSTALL_SHA`), which is a different
mechanism and is out of scope here.

## What AWS actually publishes

Measured 2026-09-01 by probing the CDN and inspecting the artifacts, not from
documentation or recall.

| URL                                                           | status  |
| ------------------------------------------------------------- | ------- |
| `awscli.amazonaws.com/AWSCLIV2.pkg`                           | 200     |
| `awscli.amazonaws.com/AWSCLIV2-2.31.0.pkg`                    | 200     |
| `awscli.amazonaws.com/awscli-exe-linux-x86_64.zip`            | 200     |
| `awscli.amazonaws.com/awscli-exe-linux-x86_64-2.31.0.zip`     | 200     |
| `awscli.amazonaws.com/awscli-exe-linux-x86_64.zip.sig`        | **200** |
| `awscli.amazonaws.com/awscli-exe-linux-x86_64-2.31.0.zip.sig` | 200     |
| `awscli.amazonaws.com/AWSCLIV2.pkg.sig`                       | **404** |
| `awscli.amazonaws.com/AWSCLIV2.pkg.sha256`                    | **404** |

Three consequences, and the first is the one that shaped the whole design:

**A detached signature exists for Linux, so verification does not require a version pin.**
This was the opposite of the assumption going in. A signature is per-artifact; a checksum
is per-version. Because AWS signs each artifact, the rolling URL can stay and `-t update`
keeps tracking latest. No `AWSCLI_VER` constant, no `check-versions` arm, no human
fetch-and-hash on every AWS release.

**macOS has no detached signature at all.** The pkg is Apple-signed and notarized, so the
verification mechanism there is `pkgutil --check-signature`, not GPG. The asymmetry is
forced by what AWS publishes, not chosen.

**AWS publishes no sha256 for either artifact.** A checksum-based design would have meant
recording a hash _we_ computed — trust-on-first-use, weaker than a signature, and stale on
every release.

## Approach

Two verification helpers in `lib/developer.sh`, each taking already-downloaded paths so
neither owns a fetcher. `update_aws_cli` keeps `curl`, `install_aws_tools` keeps `wget` —
no unification, which keeps both the diff and the existing mock surface where they are.

```
_aws_verify_zip <zip> <sig>   # Linux:  throwaway keyring, vendored key, gpg --verify
_aws_verify_pkg <pkg>         # macOS:  pkgutil --check-signature, assert the team ID
```

Neither takes the key or the expected identity as an argument. `_aws_verify_zip` resolves
the vendored key from the repo root and reads `AWSCLI_GPG_FPR`; `_aws_verify_pkg` reads
`AWSCLI_APPLE_TEAM_ID`. Both constants come from `lib/constants.sh`, already sourced by
every caller. Passing them in would let a caller weaken the check, which is the opposite of
what a verification helper is for.

Both are called by both `update_aws_cli` and `install_aws_tools`, so the first-install path
and the update path get identical treatment.

### Linux: `_aws_verify_zip`

```bash
_ring="$(mktemp -d)" || return 1
# gpg 2.x spawns gpg-agent AND scdaemon bound to the homedir; both survive its
# deletion. Measured: 3 verifications leave 3 of each orphaned. This is cleanup,
# not propagation, so it runs on every path (tdd.md's cleanup exception).
trap 'gpgconf --homedir "${_ring}" --kill all >/dev/null 2>&1; rm -rf "${_ring}"' RETURN

gpg --homedir "${_ring}" --batch --import "${_key}" || return 1
gpg --homedir "${_ring}" --batch --status-fd 1 --verify "${_sig}" "${_zip}" \
  >"${_status}" 2>/dev/null

# Reject BEFORE accepting. VALIDSIG is emitted for an expired or revoked key too,
# so an accept-only assertion is not sufficient -- see the correction below.
grep -qE '^\[GNUPG:\] (EXPKEYSIG|REVKEYSIG|KEYREVOKED|KEYEXPIRED)' "${_status}" && return 1
grep -q "^\[GNUPG:\] VALIDSIG ${AWSCLI_GPG_FPR} " "${_status}" || return 1
```

The keyring is a `mktemp -d` containing only the vendored key, so a zero exit already
implies our key signed it. The `VALIDSIG` fingerprint assertion is belt — and it is what
lets a test discriminate, since a test asserting only on exit status cannot tell a correct
verification from a stubbed `gpg` that exits 0.

#### Correction: `VALIDSIG` is not absent on every failure path

An earlier version of this section piped `gpg` into `grep -q` and argued the discarded exit
status was deliberate, "because the `VALIDSIG` line is the stronger assertion and is absent
on every failure path." **That premise is false**, and it was the load-bearing sentence of
the Linux design.

GnuPG's own `DETAILS` (2.5.22, `/opt/homebrew/share/doc/gnupg/DETAILS:552`) states that
`VALIDSIG` is emitted alongside "GOODSIG, EXPSIG, EXPKEYSIG, or REVKEYSIG (depending on the
date and the state of the signature and signing key)". Measured directly against throwaway
keys — generated, signed, then expired and revoked:

```
EXPIRED KEY   [GNUPG:] EXPKEYSIG ...   [GNUPG:] VALIDSIG <fpr> ...   gpg exit: 0
REVOKED KEY   [GNUPG:] REVKEYSIG ...   [GNUPG:] VALIDSIG <fpr> ...   gpg exit: 0
              [GNUPG:] KEYREVOKED
  the original accept-only grep, on a REVOKED key:  ACCEPTS (helper returns 0)
```

Dropping the pipe would not have helped: **gpg exits 0 in both cases.** The fix is to reject
on the bad-status lines first, which is what the snippet above now does.

**This has a date on it.** The vendored key carries an expiry — measured via
`gpg --show-keys --with-colons`, `expires=1814472778` = **2027-07-01**, 302 days from
2026-09-01. Without the reject arm the Linux mechanism would silently degrade on that date
from "AWS signed this with a live key" to "AWS signed this with a lapsed key", reporting
PASS throughout, with no test that could go red. Revocation is the sharper case: the one
event where AWS actively says _stop trusting this artifact_ is the one an accept-only guard
ignores.

**Policy: reject both, fail closed.** The consequence is explicit — on 2027-07-01 the aws
section starts failing fleet-wide until the vendored key is refreshed. That is an
availability cliff on a known date, and nothing in this change warns of its approach; a
`doctor` arm warning at N days out is deferred to a backlog row rather than built here.

`gpg --assert-signer` (2.4.1+) expresses this more directly and was considered. It is not
used because it would introduce a gpg version floor this repo does not currently state,
while the reject arm is portable to whatever gpg a machine has.

### macOS: `_aws_verify_pkg`

```bash
pkgutil --check-signature "${_pkg}" \
  | grep -q "Developer ID Installer: AMZN Mobile LLC (${AWSCLI_APPLE_TEAM_ID})" || return 1
```

**The OS performs no signature enforcement on this path, so this helper is the only check —
measured, not assumed.** Review raised the possibility that `sudo installer` validates the
signature chain itself, which would make this arm redundant. It does not. An unsigned package
built with `pkgbuild` installs cleanly as root:

```
$ pkgutil --check-signature /tmp/unsigned.pkg
   Status: no signature
   rc=1
$ sudo installer -pkg /tmp/unsigned.pkg -target /
installer: Package name is unsigned
installer: Installing at base path /
installer: The install was successful.
   rc=0
$ ls -l /tmp/pkgdest/marker.txt
-rw-r--r--@ 1 root  wheel  3 ...
```

`installer` names the defect in its own output and proceeds anyway. Since it does not refuse
an **unsigned** package, it a fortiori does not refuse a **wrongly-signed** one, so
`_aws_verify_pkg` is not a second opinion layered over an OS check — it is the only thing
standing between a network artifact and `sudo`. That makes the macOS arm's value higher than
this spec originally argued, not lower.

(Method note: an earlier attempt at this probe returned `rc=1` from a non-tty shell where
`sudo` could not read a password. `installer` never ran. That is the guard-absorbs-its-own-
failure shape this spec warns about, occurring in the spec's own verification — a non-zero
exit that means "the checker could not run", read as though it meant "the checker refused".
The measurement above was taken in a real terminal.)

**`pkgutil`'s exit code is not sufficient and this is the load-bearing detail.** Measured
against the real 59.8MB pkg: rc=0, with the chain leaf
`Developer ID Installer: AMZN Mobile LLC (94KV3E626L)` and
`Notarization: trusted by the Apple notary service`. Any Apple-notarized package from any
developer would also produce rc=0, so the guard asserts the team ID string.

**Gap partly closed in review, and the closing artifact is not portable.** This section
originally recorded that no differently-signed pkg was available, so the team-ID assertion
could not be shown to fire. That is no longer true on a developer mac: any third-party
notarized installer works as a real control. Measured against one already present on this
machine:

```
pkgutil --check-signature "<a Microsoft-signed .pkg>"
   Status: signed by a developer certificate issued by Apple for distribution
   Notarization: trusted by the Apple notary service
    1. Developer ID Installer: Microsoft Corporation (UBF8T346G9)
   rc=0
  the AWS team-ID grep against this non-AWS pkg:  no match (correctly rejects)
```

That confirms both halves: rc=0 for a notarized package from a different signer, so the exit
code is genuinely insufficient, **and** the team-ID assertion fires correctly against a real
mis-signed artifact rather than only against a stub.

The residual gap is portability, not existence. Such a package is machine-dependent — it is
whatever happens to be installed — so it cannot be a fixture. The `test` job runs on
`ubuntu-latest`, where `pkgutil` does not exist at all, so the committed suite still drives
this path through a stub. The control above is a one-off measurement recorded here, not a
repeatable gate.

An unsigned control is reproducible and is worth having in the suite: `pkgbuild` produces one
offline in about a second, and it returns `Status: no signature`, rc=1 — measured. That pins
the unsigned case; the wrong-signer case remains stub-driven in CI.

### Fail-closed on a missing verifier

No verifier means no install. Return non-zero, naming the missing binary and the remedy, so
the aws section reports FAIL rather than silently installing an unverified artifact —
`USER.md`'s fail-closed-on-unknown, and the trust-signal rule in the other direction: a PASS
meaning "nobody checked" is not a PASS.

The cost is bounded and measured: `gnupg` is in `Brewfile:40` (tagged `[HAS_DEVTOOLS]`,
which per `CLAUDE.md` selects drift expectations and does **not** gate installation, so
every mac installs it) and in `ubuntu_common_packages.txt:16`. `HAS_AWS` and `HAS_DEVTOOLS`
are carried by the same four profiles — measured against `config/profiles.sh:42-48`, where
`aws` and `devtools` co-occur in `personal_laptop`, `mac_workstation`, `linux_workstation`
and `wsl2_workstation`, and `mac_mini` carries neither. There is no profile that has AWS and
lacks gpg.
`pkgutil` is at `/usr/sbin/pkgutil`, a macOS builtin.

One actor caveat: gpg resolves via Homebrew, and `/opt/homebrew/bin` is absent from a
profile-less `PATH`. That does not bite here, because `setup_env.sh:30` already gates every
workflow on `env which brew`, so any actor that reaches these functions has Homebrew's bin
on `PATH` by construction. Recorded because the general form of this trap
(`CLAUDE.md`'s actor table) has cost this repo real time twice.

## Key vendoring

- **`keys/aws-cli-team.asc`** — new top-level directory, the ASCII-armoured public key as
  AWS publishes it.
- **`AWSCLI_GPG_FPR`** in `lib/constants.sh` — the full 40-hex fingerprint, no spaces.
- **`AWSCLI_APPLE_TEAM_ID`** in `lib/constants.sh` — `94KV3E626L`.

The key is vendored rather than fetched because a key that arrives over the same channel it
authenticates is not a trust anchor. Vendoring makes rotation a reviewable diff and removes
a network dependency (a keyserver fetch would make an update run fail for reasons unrelated
to AWS; `keyserver.ubuntu.com` was in fact unreachable from this machine during design —
`can't connect to the dirmngr`).

### Provenance, measured

The key was taken from AWS's own documentation page
(`docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html`), which is the
out-of-band anchor. The signature file alone could not have established it: an attacker
replacing the artifact replaces its signature too.

```
FPR FB5DB77FD5C118B80511ADA8A6310ACC4672475C
UID AWS CLI Team <aws-cli@amazon.com>

[GNUPG:] GOODSIG A6310ACC4672475C AWS CLI Team <aws-cli@amazon.com>
[GNUPG:] VALIDSIG FB5DB77FD5C118B80511ADA8A6310ACC4672475C ... FB5DB77FD5C118B80511ADA8A6310ACC4672475C
```

Verified end-to-end against the real 73,380,499-byte Linux zip using the exact file that
will ship.

**Two provenance caveats, both recorded rather than resolved.**

The docs page carries the key block **twice**. A naive `sed` range extraction yields a
58-line file with two BEGIN/END pairs, and `gpg --import` accepts it silently
(`Total number processed: 2, imported: 1`). The two blocks were diffed, found identical,
and one was kept. A doubled file would have worked, so nothing would have surfaced it.

A second independent source was attempted — the `awsdocs/aws-cli-user-guide` GitHub repo,
which does contain a key block — and the extraction failed (`Total number processed: 0`).
That cross-check is **unresolved**, not negative: it is evidence about the extraction, not
about the key. The vendored key therefore rests on one source plus an end-to-end signature
verification, not on two agreeing sources.

## `install_aws_tools`, beyond verification

Rewriting these lines surfaces a pre-existing defect fixed in the same change, per
`behavior.md`'s Leave It Better middle tier.

Both branches guard on `[[ ! -f <download> ]]`. A leftover download from an interrupted run
therefore **suppresses the install entirely**, and the function returns success having done
nothing. The guard tests for the wrong thing: it wants "is aws already installed", which is
what the `command -v aws` check at the bottom of each branch is already asking, after the
fact. The install becomes conditional on the tool's absence, not on a file's absence.

Error propagation is brought to the same standard #250 set for `update_aws_cli`: `|| return 1`
on every step, and the downloaded artifact removed on installer failure so the next run
re-fetches rather than re-using a partial file.

### The caller must degrade, because this change arms a dormant guard

`lib/workflows.sh:236` is already `install_aws_tools || return 1`, and `setup_env.sh`'s
`_run_or_exit run_setup_or_developer` exits on that. **That guard has never fired**, because
the function body has no `|| return` anywhere — which is the defect above. Adding propagation
therefore arms a call-site guard that has been inert since it was written, and that is a
behaviour change hidden inside a diff framed as bringing error handling to an existing
standard.

Armed as-is, a transient `wget` failure or a missing `gpg` on a fresh machine aborts
`-t setup` / `-t developer` **before** `setup_vim_plugins` and before
`run_developer_or_ansible` — losing pyenv, the ansible venv, ruby and rust because the AWS
CLI did not download. It also skips `_ledger_write_run_entry "setup" 0`.

The repo has already decided this exact question 18 lines above, with a comment saying why:

```bash
# a machine that cannot install the weekly cadence must still complete
# setup_user, and doctor's stale-heartbeat arm is what reports the gap
# rather than this line failing the whole workflow.
install_renovate_held_agent || log_warn "renovate cadence agent not installed — see above"
```

So the call site becomes `install_aws_tools || log_warn`, paired with a `doctor` arm that
reports a missing `aws` binary. Note the asymmetry this preserves rather than introduces:
`update_aws_cli` already degrades correctly — `_update_record_end "aws" "${PIPESTATUS[0]}"`
records a section FAIL and the run continues. Only the provisioning path escalates, and only
because of a guard nobody has ever seen execute.

### Fetching, and the rolling-URL race

Two changes to how the artifacts are fetched, both in the callers rather than the helpers.

**`curl` needs `-f`.** `lib/developer.sh:22` and `:40` are `curl "<url>" -o "<file>" || return 1`
with no `-f`, so a 404 or a CDN error page is written to disk and `curl` exits 0. Feeding
that to a signature verifier produces "no valid OpenPGP data found", the assertion misses,
and the operator is told the AWS artifact **failed signature verification** when the cause
was the network. `ci.md` documents this exact misattribution costing 200 consecutive daily
runs. Adding a second network fetch (the `.sig`) to that idiom, and giving its failure the
loudest available label, is the worst case; the `.sig` fetch needs `-f` and a message that
distinguishes _could not fetch the signature_ from _the signature did not verify_.

**The zip and its `.sig` are two fetches from a rolling URL.** An AWS release landing between
them yields a genuine fingerprint-verified mismatch on a completely benign event — reported,
under fail-closed, as a security failure, weekly, on seven machines. A security-shaped alert
that fires on routine releases is precisely what trains an operator to ignore the channel.

Resolving a versioned URL was the first choice and was **rejected on measurement**: the CDN
offers no version signal (`num_redirects=0`, no version header, `awscli.amazonaws.com/latest`
404s), and `aws/aws-cli` publishes **no GitHub releases** — `releases/latest` returns 404, so
the repo's existing `_fetch_github_latest` (`workflows.sh:715`) cannot be reused and would
silently return empty. Only the `tags` API carries the version, which would put a
rate-limited GitHub dependency on the weekly update path.

The CDN does return an `ETag`, which is a content identity. Bracket the fetches with it:

```bash
_etag_before=$(curl -fsSI "${_url}" | awk -F'"' '/^[Ee][Tt]ag:/{print $2}')
curl -fsS -o "${_zip}" "${_url}"     || return 1
curl -fsS -o "${_sig}" "${_url}.sig" || return 1
_etag_after=$(curl -fsSI "${_url}" | awk -F'"' '/^[Ee][Tt]ag:/{print $2}')
```

An unchanged ETag means no release landed between the fetches. A changed one means re-fetch
both **once** and re-verify before reporting anything; a genuine tamper still fails on the
second pass. This detects the race rather than preventing it, which is sufficient because
the response is a retry, and it stays entirely within the CDN already in use — no new
dependency, no rate limit, no new failure point.

## Testing

**The mocks that exist cannot express this design's central assertion, and an earlier version
of this section claimed the opposite** — "the apparatus is largely in place". Measured:

```
tests/mocks/gpg      appends argv to MOCK_CALLS_FILE; exit 0 UNCONDITIONALLY (no failure knob)
tests/mocks/pkgutil  appends argv to MOCK_CALLS_FILE; exit "${MOCK_PKGUTIL_EXIT:-1}"
```

Neither writes anything to **stdout**, and both helpers assert on stdout. So against today's
fixtures every negative case passes for the wrong reason: deleting `${AWSCLI_GPG_FPR}` from
the pattern entirely leaves all of them green, and so would replacing the helper body with an
unconditional `return 1`. That is exactly the vacuous pass this section then goes on to warn
about — the rule was stated and the fixtures defeated it.

**The decisive form of the problem: no mock-based case could ever have surfaced the
`VALIDSIG` defect above**, because the mock would encode the same false belief the design
held. A fixture built from the author's premise inherits the author's premise — the
measured-do-not-re-derive foreclosure in `behavior.md`.

So `_aws_verify_zip` is tested against **real gpg**, not a stub: generate a throwaway key in
`BATS_TEST_TMPDIR`, sign a fixture file, and drive the helper with `tests/mocks` stripped from
`PATH`. Offline, sub-second, and gpg is present on both development machines and both CI
runners. This is the only shape that can exercise the expired- and revoked-key arms at all,
since `gpg --quick-generate-key` with a short lifetime and the auto-generated revocation
certificate produce both states directly.

That collides with this spec's own principle that the helpers take no key or identity
argument, "because passing them in would let a caller weaken the check". That reasoning is
sound for _arguments_ and it also forecloses the only test that runs real gpg. The repo's
documented answer is an `_OVERRIDE_*` env seam — `CLAUDE.md`'s Test Seams section carries
`_OVERRIDE_BATS_BIN` and `GGSHIELD_FALLBACK_PATHS` for precisely this
"the branch is otherwise unreachable" reason — which is not a caller-weakening argument.

`_aws_verify_pkg` still needs the `pkgutil` mock, because the `test` job runs on
`ubuntu-latest` where `pkgutil` does not exist. That mock gains a stdout knob and keeps its
existing exit knob and `:-1` default: `MOCK_PKGUTIL_EXIT` has **3 live consumers**
(`tests/setup_env/macos.bats:45,56,66`, the Rosetta check at `lib/macos.sh:25`), so this is a
backward-compatible shared-fixture change, not a new file.

New cases, in `tests/setup_env/developer.bats`:

New cases. Those marked **real gpg** run against a throwaway key rather than a stub.

| case                                             | asserts                                                             | fixture  |
| ------------------------------------------------ | ------------------------------------------------------------------- | -------- |
| good signature, live key                         | helper returns 0 **and** the installer IS invoked                   | real gpg |
| **expired key**                                  | returns non-zero despite `VALIDSIG` being present and gpg exiting 0 | real gpg |
| **revoked key**                                  | returns non-zero despite `VALIDSIG` being present and gpg exiting 0 | real gpg |
| fingerprint mismatch                             | a valid signature from a _different_ key returns non-zero           | real gpg |
| corrupt signature                                | returns non-zero, `aws/install` never invoked                       | real gpg |
| the vendored key verifies a real AWS signature   | `keys/aws-cli-team.asc` actually works, not merely parses           | real gpg |
| verifier absent (gpg, Linux)                     | returns non-zero, message names `gpg`, installer never invoked      | PATH     |
| verifier absent (pkgutil, macOS)                 | returns non-zero, message names `pkgutil`, installer never invoked  | PATH     |
| unsigned pkg                                     | `pkgutil` reports `no signature`, helper returns non-zero           | pkgbuild |
| team ID mismatch                                 | `pkgutil` rc=0 with a different team ID returns non-zero            | stub     |
| good pkg signature                               | helper returns 0 **and** `sudo installer` IS invoked                | stub     |
| vendored key fingerprint equals `AWSCLI_GPG_FPR` | two derivations — a key swap without a constant bump goes red       | real gpg |
| ETag changed mid-fetch                           | re-fetches once and re-verifies rather than reporting a failure     | stub     |
| `.sig` fetch 404s                                | message says _could not fetch_, NOT _did not verify_                | stub     |
| leftover download does not suppress install      | `install_aws_tools` still installs when a stale zip/pkg is present  | stub     |
| `install_aws_tools` failure does not abort setup | caller warns and `run_setup_or_developer` continues                 | stub     |

**Every negative case needs a positive control in the same file.** A suite of only-fails
cannot distinguish "correctly rejecting" from "never ran" — the vacuous-pass failure
`shell.md` documents for PATH mocks. Each verifier gets at least one case where verification
_succeeds_ and the installer _is_ invoked; those are the first and the "good pkg signature"
rows above, and they are the only rows that discriminate a working helper from
`return 1`.

The expired- and revoked-key rows are the two that the previous version of this plan could
not have contained, because the design believed those states were unreachable. They are
listed first among the negatives deliberately: they are the regression test for the defect
review actually found.

The key-fingerprint test derives the expected value from the vendored file
(`gpg --with-colons --fingerprint`) and compares it to the constant. Deriving both from the
same source would be the circular check `behavior.md` warns about; here the file and the
constant are genuinely two artifacts that can drift apart. The separate
"vendored key verifies a real AWS signature" row exists because the fingerprint test only
_reads_ the key: a well-formed `.asc` that cannot verify anything — a wrong key, a truncated
one, or the doubled-block file described under Provenance — passes a fingerprint comparison.
Without that row, the one artifact this change introduces is the one thing nothing exercises.

## Out of scope, deliberately

- **No `AWSCLI_VER` pin and no `check-versions` arm.** Signatures are per-artifact, so the
  rolling URL stays and `-t update` keeps tracking latest.
- **No fan-out** of the verification pattern to the repo's other unverified downloads. That
  is a separate sweep with its own scope question.
- **`update_rust` is untouched.** #250 closed its error propagation and there is no artifact
  to verify — `rustup self update` uses rustup's own signed channel.
- **No `doctor` arm warning that the vendored key nears expiry.** The key lapses
  2027-07-01 and, under the fail-closed policy above, the aws section then fails fleet-wide
  until someone refreshes it. Nothing in this change signals the approach. This is a real gap
  with a date, deferred rather than dismissed, and it gets a backlog row in the same change
  per `behavior.md`'s Backlog Rows for Deferred Findings. The `doctor` arm this change _does_
  add is a different one — tool presence for `aws`, required by the caller-degradation
  decision above.
- **Whether the upstream key already carries a later expiry than the vendored copy.** If AWS
  extends the existing key in place — same fingerprint, new self-signature — the vendored file
  becomes a stale snapshot of a still-live key while the rotation story assumes a reviewable
  diff. Unmeasured, and it belongs with the expiry backlog row rather than here.

## Backlog hygiene

Three rows retired in this change:

- **#7** and **#13** — both already marked Resolved/Closed in their own notes, still sitting
  in the Backlog table.
- **#23** — _falsified_. The row states `update_aws_cli` and `update_rust` "swallow every
  failure except `cd`". Measured against `lib/developer.sh` at this branch's merge-base:
  every step in both functions carries `|| return 1`, landed by `97a7678f`
  (`fix(update): exit non-zero when a section fails (#250)`). The row predates that commit.
  It is retired with a one-line note recording what closed it, so the next reader does not
  re-derive it.

The retirement of #23 is itself a data point: one of the four rows opened during this
session's triage was stale, and the recommendation that started this work was built on it.
Whether the rate generalises across the other 67 rows is unmeasured, and a full backlog
staleness sweep was declined as its own piece of work.

## Verification

`make test` — the new bats cases plus no regression in the existing suite (1601 tests, a
figure CI-measured on `b5e01e6b` per `CLAUDE.md`, not re-measured on this branch's base;
the one intervening commit is docs-only and cannot move it). `make lint` —
shellcheck at default severity over the changed files, which now include a new top-level
`keys/` directory containing no shell (`scripts/list-shell-files.sh` derives scope from
shebangs, so `.asc` is invisible to it and the lint scope is unchanged).

**Bash coverage is the tightest constraint in this change and it has no slack.** The
instrumented set is `setup_env.sh` plus tracked `config/*.sh`, `lib/*.sh`, `scripts/*.sh` and
two hooks, so every new line in `lib/developer.sh` joins the denominator. `CLAUDE.md` records
the CI figure at **91% against a 91% floor for five consecutive measurements** — the margin is
zero by design, so that an uncovered addition breaches immediately rather than eroding.

Two new helpers plus a rewritten `install_aws_tools` is a material addition to the
denominator, and the success paths are the expensive ones to cover. This is the concrete
reason the real-gpg fixture is not optional: under stdout-silent mocks the `VALIDSIG`-matched
branch and both installer-invocation lines are **unreachable**, so they would sit in the
denominator and out of the numerator, and the `bash-coverage` job would go red on something
that is not a coverage problem. An earlier version of this section asserted the new lines
"must be covered" while specifying an apparatus that could not cover them.

## Multi-Lens Review

Reviewed at commit: `2d358245` (Step 7 self-review commit, before Step 8 dispatch)

Round 1: three lenses, 780,796 subagent tokens. All three independently reached the same
blocker, which was the spec's own load-bearing sentence.

### Goal-Fit

Finding: Three. (1) The stated apparatus cannot express the design's central assertion —
both verifier mocks are stdout-silent while both helpers assert on stdout, so all five
negative cases pass vacuously and the mandated positive control is unimplementable as
scoped; this collides with a `bash-coverage` floor that has zero margin. (2) The zip and its
`.sig` are two fetches from a rolling URL, so an AWS release between them produces a genuine
signature mismatch on a benign event — a security-shaped alert on a routine release. (3) The
macOS arm may be redundant with `sudo installer`'s own signature-chain validation, which the
spec never states, leaving ~40% of the change's cost unquantified. It also verified the
premise and found the fail-closed cost argument was made from the _weaker_ of two available
arguments: Brewfile presence, where call order (`workflows.sh:229/233` before `:236`) is the
strong one.

Assumption: that `sudo installer -pkg` will install a package that is unsigned or signed by
a non-AMZN Developer ID — i.e. that `_aws_verify_pkg` adds a check the OS does not already
perform. Settled by `pkgbuild`ing an unsigned pkg and attempting to install it.

Disposition: **Addressed** for (1) and (2) — the Testing section now specifies a real-gpg
fixture and states why mocks structurally cannot catch the `VALIDSIG` defect; the fetch
section adds `curl -f` and an ETag bracket. (3) is **Addressed by refutation**: the probe was
run in a real terminal and `sudo installer` installed an unsigned package with rc=0, printing
`installer: Package name is unsigned` and proceeding. The OS performs no enforcement on this
path, so the macOS arm is not redundant — it is the only check. The lens's hypothesis was
well-formed, worth the probe, and false; the spec now carries the measurement rather than the
open question.

### Ergonomics

Finding: Six, of which two are ranked highest. (1) `lib/workflows.sh:236`'s
`install_aws_tools || return 1` is a **dormant** guard that this change arms — after it, a
transient `wget` failure or missing `gpg` aborts `-t setup` before `setup_vim_plugins` and
`run_developer_or_ansible`, costing pyenv, the ansible venv, ruby and rust; the repo already
decided this case 18 lines above with `install_renovate_held_agent || log_warn`. (2)
`VALIDSIG` is emitted for expired and revoked keys per GnuPG's `DETAILS`, so the pipe
justification rests on a false premise. Also: `curl` at `developer.sh:22,40` has no `-f`, so
a 404 renders as a tamper alert; `mktemp -d` + `gpg --homedir` leaks a daemon per run; the
vendored key expires 2027-07-01 with no freshness signal; and no test case ever verifies a
signature _with_ the vendored key. It narrowed one of the spec's own claims: `setup_env.sh:30`'s
brew gate is conditional with three bypasses, so the sentence was broader than the mechanism
even though the conclusion survives.

Assumption: that AWS keeps publishing a `.sig` for the rolling URL signed by the vendored
key — signature _presence_ was measured once, key _durability_ was not, and they are
different questions.

Disposition: **Addressed.** (1) → caller becomes `install_aws_tools || log_warn` plus a
`doctor` tool-presence arm, matching the sibling precedent. (2) → reject-before-accept, with
the correction written into the spec rather than the claim quietly deleted. `curl -f`, the
gpg-agent trap, and the vendored-key-actually-verifies test row are all in. The key-expiry
`doctor` arm is **Accepted, reason: deferred to a backlog row** — the operator chose
fail-closed without the warning arm, so the 2027-07-01 cliff is a known, dated, recorded gap
rather than a silent one.

### Risk

Finding: One blocker, one bounded leak, one apparatus finding. The blocker: measured against
generated keys, `VALIDSIG` is present and **gpg exits 0** for both expired and revoked keys,
and the spec's exact grep _accepts a revoked key_. Dropping the pipe would not have helped.
The leak: `gpg --homedir` spawns `gpg-agent` **and** `scdaemon`, both surviving homedir
deletion, 3 verifications leaving 3 of each. The apparatus: no mock-based case can ever
surface the blocker, because the mock encodes the same false premise.

It cleared three hazards the dispatch prompt specifically pointed it at, which is the more
useful half: the pipe _does_ fail closed against a missing or non-executable checker (it
asserts a positive marker, so 126/127 cannot be absorbed); `grep` resolves to BSD grep with
no ugrep wrapper, and the `shell.md` divergence is `-q`+`-v`-specific; and the caller already
uses `PIPESTATUS[0]`. It also refused the analogy this session expected for the daemon leak —
the agent's fds are `/dev/null`, so unlike the `keychain`/`ssh-agent` incident it cannot
deadlock the suite. Leak, not deadlock. And it produced the differently-signed `pkgutil`
control the spec recorded as unavailable, using a Microsoft-signed pkg already on the machine.

Assumption: that AWS publishes a renewed or successor signing key, discoverably and in time,
before 2027-07-01 — and specifically whether AWS extends the key _in place_, in which case
the vendored copy expires while upstream does not, and no upstream event exists to notice.

Disposition: **Addressed** for the blocker and the leak — reject-before-accept and a `RETURN`
trap killing the agent and removing the homedir. The in-place-extension question is
**Accepted, reason: unmeasured, recorded in Out of Scope alongside the expiry backlog row**;
it changes the rotation story but not this change's mechanism.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
