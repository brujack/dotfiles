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

The whole body runs in a `( )` subshell with an `EXIT` trap. That is not style: `trap ...
RETURN` is **not** function-scoped in bash, and using it here was a defect — see the second
correction below.

```bash
_aws_verify_zip() {
  local _zip="$1" _sig="$2"

  command -v "${_AWS_GPG_BIN:-gpg}" >/dev/null 2>&1 || {
    log_error "gpg not found; cannot verify the awscli signature"
    log_error "install: brew install gnupg  /  apt-get install gnupg"
    return 1
  }

  (
    _ring="$(mktemp -d)" || exit 1
    # gpg 2.x spawns gpg-agent AND scdaemon bound to the homedir; both survive
    # its deletion. Measured: 3 verifications leave 3 of each orphaned. EXIT in a
    # subshell fires exactly once, with _ring guaranteed in scope.
    trap 'gpgconf --homedir "${_ring}" --kill all >/dev/null 2>&1; rm -rf "${_ring}"' EXIT

    # _status lives INSIDE _ring so the same trap removes it.
    _status="${_ring}/status"
    _err="${_ring}/err"

    "${_AWS_GPG_BIN:-gpg}" --homedir "${_ring}" --batch --import "${_key}" \
      >/dev/null 2>"${_err}" || { _aws_gpg_fail "${_err}" "could not import the vendored key"; exit 1; }

    "${_AWS_GPG_BIN:-gpg}" --homedir "${_ring}" --batch --status-fd 1 \
      --verify "${_sig}" "${_zip}" >"${_status}" 2>"${_err}"

    # Reject BEFORE accepting, and split the two causes: they demand opposite
    # operator responses. VALIDSIG is emitted for both, and gpg exits 0 for both.
    if grep -qE '^\[GNUPG:\] (REVKEYSIG|KEYREVOKED)' "${_status}"; then
      log_error "AWS signing key REVOKED — do not install; investigate"
      exit 1
    fi
    if grep -qE '^\[GNUPG:\] (EXPSIG|EXPKEYSIG|KEYEXPIRED)' "${_status}"; then
      log_error "vendored key or signature expired — refresh keys/aws-cli-team.asc"
      exit 1
    fi
    if ! grep -q "^\[GNUPG:\] VALIDSIG ${AWSCLI_GPG_FPR} " "${_status}"; then
      _aws_gpg_fail "${_err}" "signature did not verify against the vendored key"
      exit 1
    fi
    exit 0
  )
}
```

`_aws_gpg_fail` prints the caller's message plus the tail of gpg's stderr. That stderr is
captured rather than discarded deliberately: it is the only stream separating "no valid
OpenPGP data found" (a truncated or HTML `.sig`) from a genuine bad signature, and discarding
it would reproduce, on the verify side, exactly the misattribution the Fetching section
argues against on the fetch side.

Note the shape of every reject: `if ... then ... fi`, never `grep ... && return 1`. The latter
is one reorder away from inverting the helper — if a reject line ever becomes the last command
in the function, a **clean** signature produces no match, `grep` exits 1, and the helper
rejects a good artifact while the diff reads as a harmless line move.

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

**Policy: reject, fail closed, and split the two causes.** They demand opposite operator
responses — `EXPSIG`/`EXPKEYSIG`/`KEYEXPIRED` means _our vendored snapshot aged out_, remedied
by `git pull` and a refreshed key file; `REVKEYSIG`/`KEYREVOKED` means _AWS actively revoked
this key_, remedied by stopping and investigating. Collapsing them into one message hands the
one certain event on this path the loudest label the system has, with no remedy attached —
which is the misattribution this spec argues against elsewhere and then committed here.

`gpg --assert-signer` (2.4.1+) expresses this more directly and was considered. It is not
used because it would introduce a gpg version floor this repo does not currently state,
while the reject arm is portable to whatever gpg a machine has.

#### Correction: `EXPSIG` was missing, and the quoted sentence names it

The first reject list was `(EXPKEYSIG|REVKEYSIG|KEYREVOKED|KEYEXPIRED)`. `DETAILS:476` puts
**`EXPSIG`** in the same mutually-exclusive set, and `DETAILS:484` defines it as "the
signature with the keyid is good, but **the signature is expired**" — _signature_ expiry,
independent of _key_ expiry. So the arm closed three of four cases while transcribing from the
very sentence this spec quotes, which names the fourth. It is now in the list.

`BADSIG` and `ERRSIG` are deliberately **not** added: both are already covered by the accept
arm's failure to match, and a reject list that grows by superstition is harder to reason about
than one whose every member is justified.

#### Correction: `trap ... RETURN` is not function-scoped, and this one killed the real keyring

The previous snippet used `trap ... RETURN` at function scope. Reproduced on bash 5.3.15 and
3.2.57, identically:

```
  in _verify
TRAP FIRED ring=[/tmp/FAKE_RING]     <- intended: _ring in scope
  caller doing more work
TRAP FIRED ring=[]                   <- caller returns; _ring is a dead local
  outer done
TRAP FIRED ring=[]                   <- and again, one level further out

$ gpgconf --homedir "" --list-dirs homedir
/Users/bruce/.gnupg
```

An empty `--homedir` resolves to the **operator's real GnuPG home**. So each leaked firing ran
`gpgconf --homedir ~/.gnupg --kill all`, killing the live `gpg-agent`, `dirmngr` and
`scdaemon` — and **silently**, because the trap body carries `>/dev/null 2>&1` and `rm -rf ""`
exits 0. A cleanup whose failure mode is worse than the leak it cleans: round 1 established the
leaked agents are inert (fds on `/dev/null`, no deadlock possible), and the remedy reached into
the operator's real keyring infrastructure instead.

The `( )` + `EXIT` form fires exactly once, with `_ring` guaranteed in scope. Found
independently by two lenses in the same round.

#### Correction: `_status` was never created

The previous snippet redirected gpg's stdout to `${_status}` without declaring it anywhere.
An undeclared variable makes the redirect fail, so the file never exists, both greps read a
nonexistent path, neither matches, and the helper returns 1. **That is fail-closed, so nothing
surfaces it** — every reject-case test stays green against a helper that never ran gpg.
`_status` now lives inside `_ring`, which also means the one trap removes it.

#### Scope correction: not fleet-wide

This section previously said the 2027-07-01 expiry fails "fleet-wide". Measured against
`config/profiles.sh`: `HAS_AWS` ∧ Linux is `linux_workstation` + `wsl2_workstation` —
`workstation` and `cruncher`, **2 of 7 machines**, and per `USER.md` `cruncher` is the WSL2
backup-of-last-resort. macOS reaches `_aws_verify_pkg`, which has no key and no expiry. The
inflated figure argued _for_ the `doctor` arm that was then deferred, which is the wrong
direction for an error to point.

#### Key durability, measured rather than assumed

Both round-2 lenses independently named "AWS keeps signing with this key" as the assumption
that breaks the design. Measured across the v2 release history:

```
2.0.30  2.5.0  2.10.0  2.15.0  2.20.0  2.25.0  2.31.0  2.36.37
   -> all eight .sig files:  keyid=A6310ACC4672475C
docs page BEGIN PGP PUBLIC KEY BLOCK count: 2 (diffed — identical; no successor staged)
```

One issuer key across the whole of v2. So `AWSCLI_GPG_FPR` as a single scalar is sound, and
the keyring-of-N-fingerprints restructure is not needed. The boundary: this is _never rotated
in v2 history_, not _will never rotate_. A future rotation now fails closed and loudly rather
than degrading silently, which is the right direction to be wrong in.

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

So the call site becomes `install_aws_tools || log_warn`, paired with a `doctor` arm.

**The `doctor` arm watches key expiry, not tool presence** — a round-2 correction. Tool
presence is the _contingent_ failure; key expiry is _certain_, _dated_ (2027-07-01), and
produces the same observable. Building the arm for the contingent failure while deferring the
guaranteed one is backwards, so the arm warns at N days out and the backlog row now covers
only the residual question of how AWS rotates.

**It must be gated on `HAS_AWS`, and the spec previously did not say so.**
`_doctor_check_tools` (`lib/helpers.sh:465`) carries an unconditional
`_common_tools=(git zsh curl tmux bats)` plus OS-conditional arms, and has no
capability-conditional arm at all — so the obvious implementation appends to that array.
`PROFILE_CAPS[mac_mini]="gui printing"` carries no `aws`, three hostnames map to it
(`office`, `office-1`, `home-1`), and `run_doctor` exits non-zero on any failure. Ungated,
`-t doctor` goes permanently red on machines that are correctly not supposed to have the AWS
CLI — an alert firing on correct state, which is the failure this spec names two sections
earlier.

Note the asymmetry this preserves rather than introduces:
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

**The zip and its `.sig` are two fetches from a rolling URL**, so an AWS release landing
between them yields a fingerprint mismatch on a benign event. Under fail-closed that is
reported as a security failure.

**The response is a single retry, and nothing more:**

```bash
if ! _aws_verify_zip "${_zip}" "${_sig}"; then
  _aws_fetch_both || return 1        # one retry; a release cannot land twice
  _aws_verify_zip "${_zip}" "${_sig}" || return 1
fi
```

#### Correction: the ETag bracket was over-engineering, and it absorbed its own failure

A previous version bracketed the two fetches with `curl -fsSI ... | awk` HEAD requests and
compared ETags. Both round-2 lenses independently said to cut it, and the arithmetic is
decisive. Measured from the v2 CHANGELOG: **976 releases across ~6.5 years**, one per ~2.4
days, against a ~30 s window, on the **2** Linux machines that reach this code, weekly:

```
P(release inside the window) per run   ~1.4e-4
expected spurious failures             ~1 per 12-20 years
standing cost                          2 extra HEADs per run, an awk parse,
                                       a comparison, 2 test rows, and lines
                                       against a coverage floor with zero margin
```

Retry-on-verification-failure covers **every** state the bracket covered _and_ two it did
not — a truncated download and a CDN edge inconsistency both leave the ETag unchanged, so the
bracket misses them and reports them as signature failures, while a retry recovers.

Worse, the bracket absorbed its own failure. `curl -fsSI` on a 404 sets rc=22 **and still
emits headers**, and `$(curl ... | awk ...)` takes awk's status, so the failure is discarded
and a plausible ETag is parsed out of the error response. A missing header, a stripped ETag,
or two failed HEADs all yield `before == after` — **equal**, i.e. the _success_ verdict,
having measured nothing. That is `behavior.md`'s guard-absorbs-its-own-failure, in the very
mechanism added to prevent a misattribution. And because both HEADs hit the same warm
CloudFront edge (`X-Cache: Hit`, `Age: 74175`), it was likelier to fire on cache variance than
on its actual cause.

#### Correction: the CDN _does_ expose a version signal

The paragraph above previously said the CDN "offers no version signal", and that was an
instrument error, not a fact. The probe grepped for `x-amz-meta`, which matches nothing here;
the header is `x-amz-version-id`:

```
x-amz-version-id: ahtpaCJQzcSBj6vYLmTFEUx7RyCGdtBh    (the zip)
x-amz-version-id: mVm8Ujy52vYvDd_Y.qX6Q2bFLCAxZoPy    (the .sig, independently versioned)
?versionId=<id> HEAD -> 200                           (publicly readable)
```

The grep failed toward _absent_, and _absent_ was the answer that justified the conclusion
already being reached — the correlated-sign failure `behavior.md` describes. What survives:
S3 object versioning would only **narrow** the race, since the two objects carry independent
versionIds and a release can still land between the two HEADs, and the retry above closes it
more cheaply either way. What does not survive is the claim that the option did not exist. The
GitHub half of that paragraph is unaffected and was independently re-confirmed:
`aws/aws-cli` publishes no releases, `releases/latest` returns 404, so `_fetch_github_latest`
(`workflows.sh:715`) genuinely cannot be reused.

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

### Three seams this change must declare, not discover in Phase 2

- **`_AWS_GPG_BIN` / `_AWS_PKGUTIL_BIN`** — the verifier-absent rows are otherwise
  untestable. Driving absence through `PATH` means removing `/opt/homebrew/bin`, which also
  holds `git` and `make`; `shell.md` names that class and this repo has three precedents
  (`_OVERRIDE_BATS_BIN`, `GGSHIELD_BIN`/`GGSHIELD_FALLBACK_PATHS`, `MINIMAL_PATH`). Both are
  read unconditionally in production, granting nothing beyond what editing `PATH` already
  grants.
- **`_AWS_KEY_PATH`** — points `_aws_verify_zip` at a fixture key so real-gpg cases can drive
  the fingerprint-mismatch arm.

### Assertions must reach the intermediate artifact, not just the return code

**Every reject row passes against a helper that never invoked gpg.** With `${_status}` empty
for _any_ reason — gpg absent, gpg crashed, a failed redirect, a stdout-silent stub,
`--status-fd` changing — the reject greps miss, the accept grep misses, and the helper returns
non-zero. That is fail-closed and correct in production, and it makes the negative cases
non-discriminating in test.

So the expired- and revoked-key rows assert on `${_status}`'s **contents**: that it contained
`VALIDSIG <fpr>` **and** `EXPKEYSIG` (or `REVKEYSIG`), _and_ that the helper still returned
non-zero. Asserting the return code alone re-creates, one layer in, the exact vacuous pass
this section exists to prevent — and those two rows are the regression test for the defect
round 1 actually found, so they are the last ones that should be satisfiable by an inert
helper.

`_aws_verify_pkg` still needs the `pkgutil` mock, because the `test` job runs on
`ubuntu-latest` where `pkgutil` does not exist. That mock gains a stdout knob and keeps its
existing exit knob and `:-1` default: `MOCK_PKGUTIL_EXIT` has **3 live consumers**
(`tests/setup_env/macos.bats:45,56,66`, the Rosetta check at `lib/macos.sh:25`), so this is a
backward-compatible shared-fixture change, not a new file.

New cases, in `tests/setup_env/developer.bats`. Those marked **real gpg** run against a
throwaway key rather than a stub.

| case                                             | asserts                                                                        | fixture              |
| ------------------------------------------------ | ------------------------------------------------------------------------------ | -------------------- |
| good signature, live key                         | helper returns 0 **and** the installer IS invoked                              | real gpg             |
| **expired key**                                  | `_status` held `VALIDSIG <fpr>` AND `EXPKEYSIG`, gpg exited 0, helper failed   | real gpg             |
| **expired signature (`EXPSIG`)**                 | `_status` held `VALIDSIG <fpr>` AND `EXPSIG`, gpg exited 0, helper failed      | real gpg             |
| **revoked key**                                  | `_status` held `VALIDSIG <fpr>` AND `REVKEYSIG`, gpg exited 0, helper failed   | real gpg             |
| revoked vs expired message                       | the two produce **different** messages, each naming its own remedy             | real gpg             |
| fingerprint mismatch                             | a valid signature from a _different_ key returns non-zero                      | real gpg             |
| corrupt signature                                | returns non-zero, `aws/install` never invoked, gpg's stderr reaches the caller | real gpg             |
| the vendored key verifies a real AWS signature   | `keys/aws-cli-team.asc` actually works, not merely parses                      | real gpg             |
| vendored key fingerprint equals `AWSCLI_GPG_FPR` | two derivations — a key swap without a constant bump goes red                  | real gpg             |
| verifier absent (gpg)                            | returns non-zero, message names `gpg`, installer never invoked                 | `_AWS_GPG_BIN`       |
| verifier absent (pkgutil)                        | returns non-zero, message names `pkgutil`, installer never invoked             | `_AWS_PKGUTIL_BIN`   |
| the real keyring is untouched                    | `~/.gnupg` agent still alive after a verification — the trap regression        | real gpg             |
| unsigned pkg                                     | `pkgutil` reports `no signature`, helper returns non-zero                      | pkgbuild, macOS-only |
| team ID mismatch                                 | `pkgutil` rc=0 with a different team ID returns non-zero                       | stub                 |
| good pkg signature                               | helper returns 0 **and** `sudo installer` IS invoked                           | stub                 |
| verification fails once, then succeeds           | one retry happens and the section reports OK                                   | stub                 |
| verification fails twice                         | reports FAIL — the retry does not mask a genuine tamper                        | stub                 |
| `.sig` fetch 404s                                | message says _could not fetch_, NOT _did not verify_                           | stub                 |
| leftover download does not suppress install      | `install_aws_tools` still installs when a stale zip/pkg is present             | stub                 |
| `install_aws_tools` failure does not abort setup | caller warns and `run_setup_or_developer` continues                            | stub                 |

**The `pkgbuild` row runs on zero CI runners and must say so.** Both bats jobs (`test`,
`bash-coverage`) are `ubuntu-latest`; `lint-macos` runs `bash -n`/`zsh -n` and no bats.
`pkgbuild` and `pkgutil` are macOS-only, so that row is local-only and needs an explicit
skip guard — unguarded it fails every CI run. Naming which suite a case belongs to is part
of specifying it.

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
figure CI-measured on `b5e01e6b` per `CLAUDE.md`, not re-measured on this branch's base; the
**six** intervening commits — `git log --oneline b5e01e6b..HEAD | wc -l`, corrected from
"one", which was asserted rather than counted — are all docs-only and cannot move it).
`make lint` —
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

---

## Multi-Lens Review — Round 2

Reviewed at commit: `bdc7fd04` (after the round-1 revision and the `installer` measurement)

Three lenses, ~776k subagent tokens. **Every finding was in the round-1 corrections, not the
original design** — which is the measured argument against budgeting review rounds on an
assumption of decaying yield. Two lenses independently found the same blocker.

### Goal-Fit

Finding: (1) The proportionality split is never stated — the expensive Linux arm (vendored
key, new `keys/` dir, constant, keyring, trap, reject arm, 9 real-gpg rows, a dated cliff)
protects **2** machines, while the cheap macOS arm protects **4**; "fails fleet-wide" was
wrong, and wrong in the direction that argued for the arm this spec then deferred. (2) The
ETag bracket fails the reads-it test both ways and is dominated by plain
retry-on-verification-failure, which additionally covers truncated downloads that leave the
ETag unchanged; measured rate ~1 spurious failure per 12–20 years. (3) The `doctor` arm was
built for the contingent failure (tool presence) while the certain, dated one (key expiry)
was deferred. (4) Two test rows had no implementable fixture: verifier-absent needs binary
seams, and the `pkgbuild` row runs on zero CI runners.

Premise check: it verified the claim that closed the design space — "the CDN offers no version
signal" — and **refuted it**. `x-amz-version-id` is present on both objects and `?versionId=`
is publicly readable. The spec's own probe had grepped for `x-amz-meta`.

Assumption: has the issuer key ID on the `.sig` ever changed across releases — i.e. can
`AWSCLI_GPG_FPR` be a scalar at all?

Disposition: **Addressed.** ETag bracket cut for retry; `doctor` arm moved to key expiry and
gated on `HAS_AWS`; both binary seams and the `pkgbuild` CI guard now named in the spec;
machine counts corrected throughout; the version-signal claim corrected as an instrument
error rather than quietly deleted. The assumption was **measured and holds**: eight `.sig`
files spanning 2.0.30 → 2.36.37 all carry `keyid=A6310ACC4672475C`, so the scalar is sound
and the keyring-of-N restructure is unnecessary.

### Ergonomics

Finding: (1) **BLOCKER** — `trap ... RETURN` is not function-scoped; it fires again on every
enclosing return with `_ring` out of scope, and `gpgconf --homedir ""` resolves to the
operator's real `~/.gnupg`, so the cleanup silently kills their live `gpg-agent`, `dirmngr`
and `scdaemon`. (2) **BLOCKER** — `curl -fsSI` on a 404 emits headers and the `$( | awk )`
discards curl's rc, so both HEADs failing yields equal ETags and the guard reports success
having measured nothing. (3) The one certain event on this path gets the loudest label with
no remedy attached, while the spec argues the opposite case for `curl` two sections earlier.
(4) The new `doctor` arm needs a `HAS_AWS` gate or `-t doctor` goes permanently red on the
three `mac_mini` hostnames. (5) "Fail-closed on a missing verifier" promised a message naming
the binary, and the snippet contained no `command -v` check to produce it.

Assumption: that `gpg --homedir <mktemp -d> --verify` works for every actor that reaches it,
not only an interactive shell with a live agent — including the AF_UNIX socket-path length
limit under macOS's long `$TMPDIR`.

Disposition: **Addressed** for 1–5: subshell + `EXIT` trap, ETag mechanism removed entirely
(so its absorption is moot), split revoked/expired messages, `HAS_AWS` gate stated, explicit
`command -v` pre-check added. The socket-path assumption is **Accepted, reason: not
reproduced in-session** — it is a real class and the right place to settle it is the first
red test in Phase 2, where the fixture runs on both platforms, rather than by more prose.

### Risk

Finding: HOLD, three defects, all in code the revision introduced. (1) The trap blocker, found
independently — plus the observation that the snippet declared `_ring` neither `local` nor
global, and that undeclared choice decides which failure you get. (2) **`EXPSIG` missing from
the reject list**, while the spec quotes the `DETAILS` sentence that names it; signature expiry
is independent of key expiry, so `VALIDSIG` is emitted, gpg exits 0, and the accept-grep
matches. (3) **`_status` never created** — the redirect fails, both greps miss, the helper
returns 1; fail-closed, so all nine reject rows stay green against a helper that never ran gpg.
Lesser: `2>/dev/null` on gpg discards the stream that disambiguates the failure;
`grep ... && return 1` is one reorder from inverting the helper; "one intervening commit" is
six.

Premise check: it re-verified the key expiry independently and **agreed** with the spec
(`2027-07-01 20:12:58Z`), and confirmed the vendored file now carries exactly one key block.

Assumption: that AWS signs the rolling artifact with the vendored key on an ongoing basis —
presence was measured once, provenance over time was not.

Disposition: **Addressed.** `EXPSIG` added (`BADSIG`/`ERRSIG` deliberately not, since the
accept arm covers them and a reject list should not grow by superstition); `_status` now
declared inside `_ring` so one trap removes both; gpg's stderr captured and surfaced; every
reject rewritten as `if ... then ... fi` with an explicit terminal `exit 0`; commit count
corrected. The provenance assumption is the same one Goal-Fit raised and is **measured and
holds** — see above.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Stopping

Round 3 is not being run, and the two signals now agree.

**Artifact location:** round 2's findings were design-located, which on its own argues for
another round. But every one of them was a defect *introduced by round 1's corrections*, and
the corrections for them are **removals**: the ETag bracket, its awk parse, its comparison and
its two test rows are gone; `trap RETURN` collapses to a subshell; the `doctor` arm moved
rather than multiplied. Nothing was added except `EXPSIG` — one token in an existing list —
and two declarations that should have been there from the start.

**Is the design getting smaller?** Yes, for the first time. Round 1 added six mechanisms;
round 2 removed one entirely and simplified two, and the remaining open items are a socket-path
question and a set of test assertions — both of which are settled by running the suite, not by
reading it. That is the apparatus boundary: prose review has reached its floor, and the next
instrument is Phase 2's first red test.
