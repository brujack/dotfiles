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
gpg --homedir "${_ring}" --batch --import "${_key}" || return 1
gpg --homedir "${_ring}" --batch --status-fd 1 --verify "${_sig}" "${_zip}" \
  | grep -q "^\[GNUPG:\] VALIDSIG ${AWSCLI_GPG_FPR} " || return 1
```

The keyring is a `mktemp -d` containing only the vendored key, so a zero exit already
implies our key signed it. The `VALIDSIG` fingerprint assertion is belt — and it is what
lets a test discriminate, since a test asserting only on exit status cannot tell a correct
verification from a stubbed `gpg` that exits 0.

Note the pipeline: `gpg`'s own status is discarded by the pipe, deliberately, because the
`VALIDSIG` line is the stronger assertion and is absent on every failure path. This is the
one place in the change where `shell.md`'s "a pipeline's exit status is the last command's"
is _intended_ rather than a defect, and it needs a comment saying so.

### macOS: `_aws_verify_pkg`

```bash
pkgutil --check-signature "${_pkg}" \
  | grep -q "Developer ID Installer: AMZN Mobile LLC (${AWSCLI_APPLE_TEAM_ID})" || return 1
```

**`pkgutil`'s exit code is not sufficient and this is the load-bearing detail.** Measured
against the real 59.8MB pkg: rc=0, with the chain leaf
`Developer ID Installer: AMZN Mobile LLC (94KV3E626L)` and
`Notarization: trusted by the Apple notary service`. Any Apple-notarized package from any
developer would also produce rc=0, so the guard asserts the team ID string.

**Known gap, stated rather than closed.** The control run was a garbage file, which returns
rc=1 with `Could not open package` — a _parse_ failure. That control discriminates "is a
package" from "is not a package"; it does **not** discriminate "signed by AWS" from "signed
by someone else". No differently-signed pkg was available to prove the team-ID assertion
fires. The test suite inherits this limit: it can pin the parse and the string match against
a stub, and cannot prove the assertion against a real mis-signed artifact.

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

## Testing

Mocks already exist for `gpg`, `pkgutil`, `wget`, `unzip` and `installer` under
`tests/mocks/`, so the apparatus is largely in place.

New cases, in `tests/setup_env/developer.bats`:

| case                                             | asserts                                                            |
| ------------------------------------------------ | ------------------------------------------------------------------ |
| verifier absent (gpg, Linux)                     | returns non-zero, message names `gpg`, installer never invoked     |
| verifier absent (pkgutil, macOS)                 | returns non-zero, message names `pkgutil`, installer never invoked |
| bad signature                                    | returns non-zero, `sudo installer` / `aws/install` never invoked   |
| fingerprint mismatch                             | `VALIDSIG` with a different fingerprint returns non-zero           |
| team ID mismatch                                 | `pkgutil` rc=0 with a different team ID returns non-zero           |
| vendored key fingerprint equals `AWSCLI_GPG_FPR` | two derivations — a key swap without a constant bump goes red      |
| leftover download does not suppress install      | `install_aws_tools` still installs when a stale zip/pkg is present |

**Every negative case needs a positive control in the same file.** A suite of only-fails
cannot distinguish "correctly rejecting" from "never ran" — the vacuous-pass failure
`shell.md` documents for PATH mocks. Each verifier gets at least one case where verification
_succeeds_ and the installer _is_ invoked.

The key-fingerprint test derives the expected value from the vendored file
(`gpg --with-colons --fingerprint`) and compares it to the constant. Deriving both from the
same source would be the circular check `behavior.md` warns about; here the file and the
constant are genuinely two artifacts that can drift apart.

## Out of scope, deliberately

- **No `AWSCLI_VER` pin and no `check-versions` arm.** Signatures are per-artifact, so the
  rolling URL stays and `-t update` keeps tracking latest.
- **No fan-out** of the verification pattern to the repo's other unverified downloads. That
  is a separate sweep with its own scope question.
- **`update_rust` is untouched.** #250 closed its error propagation and there is no artifact
  to verify — `rustup self update` uses rustup's own signed channel.

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
shebangs, so `.asc` is invisible to it and the lint scope is unchanged). Bash coverage: the
instrumented set is `setup_env.sh` plus tracked `config/*.sh`, `lib/*.sh`, `scripts/*.sh`
and two hooks, so `lib/developer.sh`'s new lines join the denominator and must be covered
to hold the 91% CI floor.
