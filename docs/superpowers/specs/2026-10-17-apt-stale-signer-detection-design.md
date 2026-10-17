# apt stale-signer detection in `-t update`

- **Date:** 2026-10-17
- **Status:** Approved (Phase 1 complete)
- **Approved:** 2026-10-17
- **Backlog row:** P2 bugs and security, "A rotated or expired third-party apt key goes stale silently"
- **Prior work:** `2026-10-15-hashicorp-apt-design.md` (round 4 E1''', round 5 G1⁗/E1⁗)

## Problem

A box that has already fetched a third-party apt source keeps its old index files when the
source's signer changes. The refresh exits 0, prints warning lines that name the source and a
signature token, and does nothing else. The source stops updating. `-t update`'s `apt` section
still shows `[OK]`, and the run exits 0. The warnings scroll past mid-stream and survive only in
`err_apt`, which nothing reads unless the section fails.

The `[OK]` depends on `nala full-upgrade` also exiting 0. nala refreshes the lists itself
(`--update` is the default for upgrade), but that refresh does not fail the command. The installed
nala 0.16.0 source shows this: `setup_cache()` sends a `FetchFailedException` to
`apt_error(err, update=False)`, which under sudo prints and returns. That was established by
reading the source, not by a run. V2 measures it.

Today only HashiCorp has a detector, `_hashicorp_rotation_hint_fires` (`lib/linux_ubuntu.sh`). It
runs during `-t setup`/`-t developer`, for that one host, against the output of
`apt-get update --error-on=any`. HashiCorp's source is transient (it exists only while its install
step runs), so `-t update` never sees it.

## Measurements

All measured 2026-10-17 unless stated otherwise.

- **M1, current state.** Ran `sudo -n apt-get update 2>&1`, then
  `grep -E '^(W|E|Warning|Error):'`, on `claude` and `workstation` (both resolute, apt 3.2.0).
  Both gave rc 0 and 0 matching lines. No source is stale on either box today.
- **M2, silent rc 0 after a signer change.** From the HashiCorp spec's measurements table, a
  single source with `List-Cleanup=0` on `claude`/`workstation`, resolute. "Fetched once, keyring
  swapped, no `--error-on`" gave rc 0, `W:` lines only, and the old index was used. With
  `--error-on=any` the same case gave rc 100 and `E: Failed to fetch …`.
  - Not measured: the full sources set, the `apt` front end, noble, expiry.
- **M3, existing fixture.** `tests/fixtures/apt/update-hashicorp-stale-rotated.txt` was captured
  with `apt-get update --error-on=any` (rc 100), not with the production form. Its `E:` lines are
  that flag's output. It is a valid input for the HashiCorp install step, which runs that form, and
  not a valid input for `-t update`. (The first draft of this spec claimed otherwise. Step 8 round 1
  caught it.)
- **M4, host apt prints.** From a clean `apt-get update` capture on `claude` (13 sources):
  `pkgs.k8s.io` is printed as `prod-cdn.packages.k8s.io`, a redirect. Every other source prints
  the host its `.list`/`.sources` file names. `download.virtualbox.org` is `http://`.
- **M5, key expiry horizon.** `gpg --with-colons --list-keys` over each `signed-by` keyring on
  `claude` only. `kubernetes-apt-keyring.gpg` primary `9A296436` expires **2026-12-28**.
  `githubcli-archive-keyring.gpg` holds `75716059` (expired 2026-09-05) and `62313325` (no
  expiry), so it still verifies.
- **M6, which install paths re-fetch a key.** From reading `lib/linux_ubuntu.sh` and
  `lib/developer.sh`, which applies to all Linux boxes:
  - Every `-t developer` run re-fetches docker, k8s, teleport, cloudflare, virtualbox and
    github-cli.
  - nvidia re-fetches only when its keyring is absent, gcloud only when its `.list` is absent,
    and opentofu only when `tofu` is absent.
  - edge, microsoft-prod and albert are fingerprint-pinned, and nothing re-fetches them by design.
  - All three Step 8 lenses confirmed the guards against the code.

**Premise correction.** The backlog row says "nothing re-fetches a key". M6 shows that is false for
six hosts under `-t developer` and conditionally true for three more. The real gap is the routine
path: `-t update` never re-fetches and never reports, and `-t developer` is run rarely.

## Design

### 1. One refresh — `update_apt_packages` (`lib/linux_shared.sh`)

- The refresh stays `sudo -H apt update`. Its output already reaches `err_apt` through
  `run_update`'s `2>&1 | tee` (`lib/workflows.sh`).
- `nala full-upgrade` gains `--no-update`, so the lists are fetched once per run, by the
  `apt update` that has just succeeded. This removes nala's second copy of the errors from
  `err_apt`, and the second network round trip.
- Nothing else in the function changes: its return codes, its other flags, and its stdin
  redirect stay as they are.

### 2. Parser — `_apt_stale_signer_hosts` (`lib/linux_shared.sh`)

- Reads apt output on stdin.
- Considers only lines that start with `W:`, `E:`, `Warning:` or `Error:`. This is
  case-sensitive, so apt's `WARNING: apt does not have a stable CLI interface` is excluded.
- A considered line must contain one of these tokens: `NO_PUBKEY`, `EXPKEYSIG`, `EXPSIG`,
  `KEYEXPIRED`, `REVKEYSIG`, `is not signed`, `is no longer signed`.
- For every `http://` or `https://` URL on such a line, it takes the URL's authority. It prints
  `host<TAB>token` once per distinct host, in order of first appearance, with the token from the
  first line that named that host. A token line with no URL is ignored.
- The prefixes and the token list each exist once.
- `_hashicorp_rotation_hint_fires` becomes a call to `_apt_stale_signer_hosts` that checks for
  `apt.releases.hashicorp.com` among the hosts. Because every URL on a line is taken, it still
  fires whenever the host appears anywhere on a token line, so its behaviour does not narrow.
  Widening the prefixes changes nothing for it, because its input comes from `apt-get`, which
  prints only `W:`/`E:`.

### 3. Remedy routing — `_apt_signer_remedy <host>`

A `case` on the host apt prints (M4), returning one remedy string:

| Host(s)                                                                                                                                                                | Class                  | Remedy text (substance)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `download.docker.com`, `pkgs.k8s.io`, `prod-cdn.packages.k8s.io`, `deb.releases.teleport.dev`, `pkg.cloudflareclient.com`, `download.virtualbox.org`, `cli.github.com` | re-fetched every run   | re-run `./setup_env.sh -t developer` (it re-fetches this key); if this line persists after that run, the publisher's own key is at fault, so refresh it by hand                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `nvidia.github.io`                                                                                                                                                     | re-fetched when absent | `sudo rm /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg`, then re-run `./setup_env.sh -t developer`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `packages.cloud.google.com`                                                                                                                                            | re-fetched when absent | `sudo rm /etc/apt/sources.list.d/google-cloud-sdk.list`, then re-run `./setup_env.sh -t developer`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `packages.opentofu.org`                                                                                                                                                | re-fetched when absent | two steps, because the install step re-fetches only when `tofu` is absent. **Stage and show:** `d=$(mktemp -d) && curl -fsSL -o "$d/key" https://packages.opentofu.org/opentofu/tofu/gpgkey && gpg --batch --dearmor -o "$d/ring" "$d/key" && gpg --show-keys "$d/ring" && echo "$d"`. Compare the printed fingerprint with OpenTofu's published key. **Then install:** `sudo install -m 0644 "$d/ring" /etc/apt/keyrings/opentofu-archive-keyring.gpg.new && sudo mv -f /etc/apt/keyrings/opentofu-archive-keyring.gpg.new /etc/apt/keyrings/opentofu-archive-keyring.gpg && rm -rf "$d"`. A failed download, or a body that is not a key (captive portal, HTML error), stops at the dearmor and never reaches the live keyring, the same stage-then-move shape as `_install_apt_keyring` |
| `packages.microsoft.com`                                                                                                                                               | pinned                 | verify Microsoft's new key, replace `keys/microsoft.asc` and bump `MS_GPG_FPR` in `lib/constants.sh`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `download.opensuse.org`                                                                                                                                                | pinned                 | verify the albert OBS key's new fingerprint and bump `ALBERT_GPG_FPR` in `lib/constants.sh`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| anything else                                                                                                                                                          | unknown                | dotfiles has no remedy for this host; refresh its key by hand                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |

- `apt.releases.hashicorp.com` is deliberately absent, because its source is never present
  when `-t update` runs. If it ever appears, it takes the unknown branch, which still WARNs.
- A comment above the `case` names the guarded install functions (`_install_ubuntu_nvidia`,
  `_install_ubuntu_cloud_tools`, `_install_ubuntu_misc`). A change to one of those guards
  updates its row in the same change.

### 4. Reporting and verdict — `run_update` (`lib/workflows.sh`)

- After `update_apt_packages 2>&1 | tee err_apt`, `run_update` runs `_apt_stale_signer_hosts`
  over `err_apt`. That file is the only input.
- **rc 0 and at least one stale host.** `_update_record_end "apt" 0`, then the section is
  marked WARN with a result that **keeps** what `_update_record_end` wrote and appends to it:
  `<existing result>; signer check failed for <host>[, <host>…] — see detail`. `_update_warn`
  overwrites `result_apt`, so the existing text is read first and passed back in. The upgraded
  package list stays visible for as long as a source stays stale. Then
  `detail_apt` is written with one line per host:
  `<host> is not updating: signature check failed (<token>): signer rotated or expired, or a proxy served unsigned data; <remedy>`.
  The detail holds only these lines, never a `tail` of `err_apt`, so no budget can push them out.
  The run exits 0.
- **rc ≠ 0.** The section FAILs as today, and `_update_record_end`'s FAIL path writes the
  `err_apt` tail into `detail_apt`. If any host is stale, its lines are appended after that tail.
- **rc 0 and no stale host.** OK, as today.
- `update_apt_packages`' contract does not change, so `update_system_packages` and its test are
  unaffected.

### 5. Coverage bound (stated, not hidden)

**Rotation is measured.** Step 8 round 2's goal-fit lens used an unprivileged sandbox apt, with
`Dir::State::Lists`, `Dir::Cache` and `sourcelist` moved to a scratch directory. It fetched docker
once, then pointed `signed-by` at an unrelated keyring:

- `apt update` printed `Hit:1 …InRelease`, then `Err:1 …InRelease`, then
  `Warning: … NO_PUBKEY 7EA0A9C3F273FCD8`, with rc 0.
- A third run gave the same result.

apt re-verifies a cached `InRelease` even on a `Hit`. The warning repeats on every run until the
key is fixed, and detection fires on the first `-t update` after a rotation. The earlier guess
that a `304` skips verification was wrong for this case.

**Expiry is not measured.** gpgv checks expiry at the current time, so the same re-verification
probably yields `EXPKEYSIG`/`KEYEXPIRED` on every run once the key expires. V1 measures that in
the same sandbox. If V1 shows silence, this section is amended to state the bound plainly, and a
backlog row records the predictive doctor check this spec declines (Alternatives).

## Alternatives

- **Predictive doctor expiry check.** Declined by the operator 2026-10-17. Revisit if V1 shows
  expiry is silent.
- **Auto re-fetch in `-t update`.** Declined by the operator: trust would change without the
  operator seeing it, and `-t update` would gain a write path into `/etc/apt`.
- **Generic WARN with no remedy routing.** Declined by the operator.
- **A second capture inside `update_apt_packages`, with an `apt-get` refresh, `mktemp` and a
  tmp-root seam.** This was the first draft. It was replaced (Step 8 round 1, goal-fit and risk),
  because `err_apt` already holds the stream, and because a second capture meant two parser
  inputs once nala's own refresh was counted.
- **Measuring nala instead of passing `--no-update`.** Rejected: two copies of every error would
  stay in `err_apt`, and the second refresh is redundant work.
- **A drift guard deriving the host table from the code.** It was in the approved outline and is
  dropped here. The hosts cannot be derived statically: nvidia's `.list` comes from upstream, and
  k8s is printed under a redirect host (M4). The cost of drift is bounded, because an unmapped host
  still WARNs, only with the unknown remedy. **Dropped with the operator's confirmation,
  2026-10-17.**

## Testing

Fixtures are captured from real output, never hand-typed, and each is committed with its command,
tool versions and rc. A multi-host fixture is built by concatenating captured files, so every line
is still real. The fixtures come from V2:

- **stale-rotated:** a fetched source with its keyring swapped, full sources set, production
  `apt update 2>&1`, rc 0.
- **the same case on noble.**
- **clean:** the M1 capture, re-taken with `apt update`.

Cases:

1. **Positive control.** The stale-rotated fixture yields exactly `<host><TAB><token>` for the
   source V2 staled, and nothing else.
2. The clean fixture yields empty output.
3. A two-host concatenation yields two lines in first-appearance order.
4. A token line carrying two URLs yields both hosts.
5. `_apt_signer_remedy`: one case per class, plus the unknown branch, each asserting the
   substance from the table (host, path or constant name).
6. Through `run_update`, with the apt mock printing the stale fixture and nala exiting 0:
   - the summary row is `WARN`,
   - its result keeps the package-count text and also names the host,
   - `detail_apt` contains the `… is not updating …` line and the remedy,
   - the run exits 0.
7. The same with a failing nala: the row is FAIL, and `detail_apt` holds the error tail
   followed by the stale line.
8. The nala argv in the mock call log matches `^nala full-upgrade .*--no-update`. Placement
   matters: nala's root callback accepts only `--version` and `--license`, so
   `nala --no-update full-upgrade` would be rejected on every run, and a check for presence
   alone would pass it.
9. The existing `_hashicorp_rotation_hint_fires` tests pass unchanged.

**Harness changes these cases need. They are planned edits, not gate-cheating:**

- `tests/mocks/apt` gains `MOCK_APT_STDOUT_FILE`. When it is set, the mock prints that file to
  stdout. Today the mock prints nothing.
- `tests/setup_env/linux_shared.bats:127` asserts nala's exact argv with `grep -qxF`. It gains
  `[--no-update]` in the position R1 places it. This is the only existing assertion that changes.

## Requirements

- **R1.** `update_apt_packages` passes `--no-update` to `nala full-upgrade` after the `full-upgrade` verb, and is otherwise unchanged, including its return codes.
- **R2.** `_apt_stale_signer_hosts` reads stdin and prints one `host<TAB>token` line per distinct host, in first-appearance order, for lines starting `W:`, `E:`, `Warning:` or `Error:` (case-sensitive) that contain one of `NO_PUBKEY`, `EXPKEYSIG`, `EXPSIG`, `KEYEXPIRED`, `REVKEYSIG`, `is not signed`, `is no longer signed`, taking the authority of every `http://` or `https://` URL on the line and ignoring token lines without a URL.
- **R3.** The prefix set and the token list are each defined once, and `_hashicorp_rotation_hint_fires` decides by checking whether `_apt_stale_signer_hosts` lists `apt.releases.hashicorp.com`.
- **R4.** `_apt_signer_remedy <host>` returns the remedy for each host and class in Design section 3's table, and the unknown-host text for any other host.
- **R5.** When `update_apt_packages` returns 0 and `_apt_stale_signer_hosts` over `err_apt` lists at least one host, `run_update` records the `apt` section with `_update_record_end "apt" 0` and then marks it WARN with the result `<the result _update_record_end wrote>; signer check failed for <hosts, comma-joined> — see detail`, and writes `detail_apt` containing, per host, `<host> is not updating: signature check failed (<token>): signer rotated or expired, or a proxy served unsigned data; <remedy>`.
- **R6.** When `update_apt_packages` returns non-zero, the `apt` section FAILs as today and any stale-host lines are appended to `detail_apt` after the error tail.
- **R7.** A run whose only non-OK section is the `apt` stale-signer WARN exits 0.
- **R8.** Tests 1-9 in the Testing section exist and pass, with fixtures captured from real output and committed with their command, tool versions and rc.
- **V1.** In the unprivileged sandbox of Design section 5, point a fetched source's `signed-by` at a keyring whose key is expired at run time (built with `gpg --faked-system-time`), run `apt update` twice, and record whether each run prints a considered line carrying `EXPKEYSIG` or `KEYEXPIRED` and the URL. Record the result in this spec. If the first is silent, amend Design section 5 to state the bound and add a P2 backlog row for the doctor expiry check.
- **V2.** In a sandbox holding the full sources set of `claude` (and again on noble, in an `ubuntu:24.04` container), fetch once, swap one source's keyring, then record the output and rc of `apt update 2>&1` and of `nala full-upgrade --no-update -y` and `nala full-upgrade -y`. Commit the captures as the Testing fixtures, and confirm both `apt update` and nala exit 0.
- **V3.** After merge, run `./setup_env.sh -t update` on `claude`; the `apt` row reads OK and `detail_apt` carries no stale-host line, because no source is stale today (M1).
- **N1.** `-t update` does not write, fetch or delete any keyring, source file or apt trust setting.
- **N2.** No doctor check and no keyring-expiry parsing are added.
- **N3.** The install-time key-fetch conditions in `_install_ubuntu_nvidia`, `_install_ubuntu_cloud_tools` and `_install_ubuntu_misc` are unchanged.
- **N4.** The base step's `apt update` call and message (`lib/linux_ubuntu.sh:223`) are unchanged; its stale `E:/W:` wording stays with its own P3 row.
- **N5.** A stale signer alone never turns the `apt` section into FAIL or the run's exit code non-zero.

## Multi-Lens Review

Reviewed at commit: `ed61410d` (Step 7 self-review commit, before Step 8 dispatch)

**Orchestrator checks made after the reports, before dispositions:**

- **nala exit status.** Settled by reading the installed nala 0.16.0 source, not by a run.
  `setup_cache()` (`nala/install.py`) refreshes on `full-upgrade`. A `FetchFailedException` goes
  to `apt_error(err, update=False)`, because the command is not `update`. Under sudo, `apt_error`
  prints and returns (`nala/error.py`), and nala continues. So nala exits 0 over a stale source,
  but it prints a second, differently formatted copy of the errors into `err_apt`.
- **Fixture provenance.** M3 was wrong. `update-hashicorp-stale-rotated.txt` was captured with
  `apt-get update --error-on=any` (rc 100), the form `lib/linux_ubuntu.sh:1146` uses, not with
  plain `apt-get update`. Per the HashiCorp spec's measurements table, the production form without
  `--error-on` gives "rc 0, `W:` lines only". The ergonomics lens read the two rows of that table as
  contradicting each other. They do not: each row is a different command.

### Goal-Fit

Finding:

1. **HIGH:** nala's built-in refresh (`--update` is the default for upgrade) is not modelled. It
   writes a second copy of the errors into `err_apt`, so two host lists can be parsed from two
   different inputs.
2. **MEDIUM:** a simpler path exists. Parse `err_apt` in `run_update` with
   `^(W|E|Warning|Error):`. That drops R1's `mktemp` capture, the `apt`→`apt-get` switch (test 7)
   and the tmp-root seam (test 8), and moves the remedy lines into `detail_apt`, which ends the
   dependence on the `tail -10` budget.
3. **LOW:** the k8s expiry case, the motivating example, depends on V1.

Reads-it test passes: the consumer is the summary WARN row and `detail_apt`, persisted in
`~/.dotfiles-update.log`.

Assumption: nala exits 0 over a signature failure. It is now settled by reading the source
(above), not by a run.

Disposition: **Addressed (operator, 2026-10-17).**

- Finding 1: `nala --no-update` (R1).
- Finding 2: adopted wholesale. The parse moved to `run_update` over `err_apt`, and the second
  capture, the `apt-get` switch and the tmp seam were deleted (Design sections 1 and 4; R5, R6).
- Finding 3: stands as stated in Design section 5.
- Assumption: V2 now measures nala's rc as well.

### Ergonomics

Finding:

1. **MAJOR:** the same nala refresh. Fix: pass `--no-update`, or measure nala.
2. **MEDIUM:** the opentofu remedy pipes `curl` into `gpg --yes`. A failed curl writes an empty or
   truncated live keyring.
3. **MINOR:** the "re-fetched every run" remedy is a full `-t developer` run for one key.
   `install_github_cli_linux` sits last in an `|| return 1` chain (`lib/workflows.sh:620-628`), and
   its own `wget | sudo tee` (`lib/developer.sh:512`) writes an empty keyring on a failed fetch,
   which is a pre-existing defect.

Every guard the remedy table cites matches the code. No false positive was found on a healthy box.

Assumption: `apt-get update` and nala both exit 0 when the **full** sources set is refreshed over a
source whose signer changed. M2 measured a single source with `List-Cleanup=0`.

Disposition: **Addressed (operator, 2026-10-17).**

- Finding 1: `--no-update` (R1).
- Finding 2: the opentofu remedy now downloads to a file, checks it is non-empty, then dearmors.
- Finding 3: the heavy remedy is accepted as is (rare event). The gh empty-keyring defect becomes
  a P2 backlog row.
- Assumption: V2 measures the full sources set, for both `apt update` and nala.

### Risk

Finding:

1. **MAJOR:** the same nala refresh. Fix: `--no-update`, or measure it.
2. **MAJOR:** M3's fixture provenance is false (confirmed above). Test 5 runs an rc-100 capture
   behind a mock that exits 0.
3. **MINOR:** `update_system_packages` (`lib/linux_shared.sh:160-163`) maps rc 2 to 1. It has no
   production caller, but `tests/setup_env/linux_shared.bats:44` uses it.
4. **MINOR:** the HashiCorp refactor narrows what fires, from "host anywhere on a token line" to
   "first URL on the line". R3 does not state this.
5. **MINOR:** the second capture is over-engineered, because `err_apt` already tees the stream.
   The nested pipe needs `PIPESTATUS[0]`. Adding `</dev/null` would cost nothing.

Assumption: nala exits 0. Settled by reading the source (above).

Disposition: **Addressed (operator, 2026-10-17).**

- Finding 1: `--no-update`.
- Finding 2: M3 corrected, fixtures recaptured in production form by V2.
- Finding 3: moot, since `update_apt_packages`' rc contract no longer changes.
- Finding 4: the parser takes every URL on a line (R2), so nothing narrows.
- Finding 5: moot, since the second capture was removed.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2 — spec at `6f8c72e9`

Same three lenses, fresh. Each was told the round-1 section is history. The adversarial gate was
not triggered. No finding breaks the design.

| # | Lens | Sev | Finding | Disposition |
|---|------|-----|---------|-------------|
| G1 | goal-fit | MAJOR | §5's 304-silence mechanism is contradicted by measurement. In a sandbox, apt re-verifies a cached `InRelease` on a `Hit` and warns `NO_PUBKEY` at rc 0 on every run | Addressed: §5 rewritten with the measurement; V1 narrowed to expiry |
| G2 / K2 / K3 | goal-fit, risk | MINOR | `tests/mocks/apt` prints nothing, and `linux_shared.bats:127`'s exact-argv assertion breaks under R1. Neither is named | Addressed: Testing names `MOCK_APT_STDOUT_FILE` and the one assertion edit |
| G3 | goal-fit | LOW | `err_apt` now also holds nala and dpkg output, so a false positive is possible, at worst a WARN | Accepted (operator, 2026-10-17): the worst case is a spurious WARN, and no matching line exists in a real `~/.dotfiles-update.log` |
| E1 / K4 | ergonomics, risk | MEDIUM | `_update_warn` overwrites `result_apt`, so the upgraded-package list disappears while a source is stale | Addressed: the WARN result keeps the existing text and appends to it (§4, R5, test 6) |
| E2 | ergonomics | MINOR | The re-fetch remedy nags forever when the publisher itself ships a bad key | Addressed: the remedy says that if the line persists after `-t developer`, the publisher's key is at fault |
| E3 | ergonomics | MEDIUM | The opentofu remedy's `[ -s ]` check passes a captive-portal or HTML body into the live keyring | Addressed: two-step stage, show the fingerprint, then `install` to `.new` and `mv` |
| K1 | risk | MAJOR | `--no-update` placed before the verb is rejected by nala's root callback, and a presence-only test 8 would pass it | Addressed: R1 places the flag after the verb; test 8 asserts the order |

**Assumption lines.**

- **Goal-fit:** expiry yields a token line on a `Hit`. Unmeasured; V1 settles it.
- **Ergonomics and risk:** the piped `apt` front end puts the token and the URL on one
  `Warning:` line. Confirmed by goal-fit's sandbox run (`apt update`: rc 0, one `Warning:` line
  with the URL and `NO_PUBKEY`; `apt-get`: the same with `W:`). V2 re-captures it on the full
  sources set and on noble.

**Stop.** Review ends here (operator, 2026-10-17). Round 2's findings sit in the test apparatus
(mock knobs, an argv assertion, flag order) or are wording-level. Every round-1 correction
removed surface: the second capture, the apt-get switch, the tmp seam and the rc-2 contract.
Phase 2's first red test is the next instrument, not a third lens round.
