# apt stale-signer detection in `-t update`

- **Date:** 2026-10-17
- **Status:** Draft (Phase 1)
- **Backlog row:** P2 bugs and security, "A rotated or expired third-party apt key goes stale silently"
- **Prior work:** `2026-10-15-hashicorp-apt-design.md` (round 4 E1''', round 5 G1⁗/E1⁗)

## Problem

A box that has already fetched a third-party apt source keeps its old index files when the
source's signer changes. `apt-get update` exits 0 and prints `W:`/`E:` lines naming the source
and a signature token, and nothing else happens. The source stops updating. `-t update`'s `apt`
section still shows `[OK]`, and the run exits 0. The warnings scroll past mid-stream in the
terminal and survive only in `err_apt`, which nothing reads unless the section fails.

Today only HashiCorp has a detector, `_hashicorp_rotation_hint_fires`
(`lib/linux_ubuntu.sh`). It runs during `-t setup`/`-t developer` for that one host. HashiCorp's
source is transient (it exists only while its install step runs), so `-t update` never sees it.

## Measurements

All measured 2026-10-17 unless stated otherwise.

| #   | What                               | Command                                                                                               | Population measured                                               | Result                                                                                                                                                                                                                                                                                                                                          |
| --- | ---------------------------------- | ----------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| M1  | Current state                      | `sudo -n apt-get update 2>&1`, then `grep -E '^(W\|E\|Warning\|Error):'`                              | `claude` and `workstation`, both resolute, apt 3.2.0, as of today | rc 0 on both, 0 matching lines. No source is stale on either box today.                                                                                                                                                                                                                                                                         |
| M2  | Silent rc 0 after a signer change  | reproduced in HashiCorp round 4 (E1''')                                                               | `claude` and `workstation`, resolute, HashiCorp source only       | rc 0, old lists kept, `W:` and `E:` lines printed. Not measured on noble. Not measured for expiry, only for a key mismatch.                                                                                                                                                                                                                     |
| M3  | Line shape                         | `tests/fixtures/apt/update-hashicorp-stale-rotated.txt` (captured in #340 with `apt-get update 2>&1`) | `claude`, resolute, one host                                      | Five token-bearing lines, each with `https://apt.releases.hashicorp.com`. Includes `W: OpenPGP signature verification failed: <url> …NO_PUBKEY…` and `E: The repository '<url> … InRelease' is not signed.`                                                                                                                                     |
| M4  | Host apt prints                    | clean `apt-get update` capture                                                                        | `claude`, 13 sources                                              | `pkgs.k8s.io` is printed as `prod-cdn.packages.k8s.io` (a redirect). Every other source prints the host its `.list`/`.sources` file names. `download.virtualbox.org` is `http://`.                                                                                                                                                              |
| M5  | Key expiry horizon                 | `gpg --with-colons --list-keys` over each `signed-by` keyring                                         | `claude` only                                                     | `kubernetes-apt-keyring.gpg` primary `9A296436` expires **2026-12-28**. `githubcli-archive-keyring.gpg` holds `75716059` (expired 2026-09-05) and `62313325` (no expiry), so it still verifies.                                                                                                                                                 |
| M6  | Which install paths re-fetch a key | read `lib/linux_ubuntu.sh`, `lib/developer.sh`                                                        | code, all Linux boxes                                             | Every `-t developer` run re-fetches docker, k8s, teleport, cloudflare, virtualbox and github-cli. The others re-fetch only on a condition: nvidia when its keyring is absent, gcloud when its `.list` is absent, opentofu when `tofu` is absent. edge, microsoft-prod and albert are fingerprint-pinned, and nothing re-fetches them by design. |

**Premise correction.** The backlog row says "nothing re-fetches a key". M6 shows that is false
for six hosts under `-t developer` and conditionally true for three more. The real gap is the
routine path: `-t update` never re-fetches and never reports, and `-t developer` is run rarely.

## Design

### 1. Detection — `lib/linux_shared.sh`

- `update_apt_packages` refreshes with `sudo -H apt-get update`, not `apt update`. On apt 3.x,
  `apt` prints `Warning:`/`Error:` and `apt-get` prints `W:`/`E:` (round 5 G1⁗). The output is
  shown live and also captured into a temp file. Only `apt-get`'s exit status decides failure,
  as it does today. The temp file sits in a `mktemp -d` directory and is removed on every path
  (`shell.md` subshell-EXIT-trap rule). It is never left in `$TMPDIR`.
- New `_apt_stale_signer_hosts` reads `apt-get update` output on stdin. For every line that
  starts with `W:` or `E:` and contains one of the tokens `NO_PUBKEY`, `EXPKEYSIG`, `EXPSIG`,
  `KEYEXPIRED`, `REVKEYSIG`, `is not signed` or `is no longer signed`, it takes the authority of
  the first `https?://` URL on the line. It prints `host<TAB>token`, once per distinct host, in
  order of first appearance, with the token from that first line. A line with a token but no
  URL is ignored (for example `E: Some index files failed to download`).
- The token list exists once. `_hashicorp_rotation_hint_fires` becomes a call to
  `_apt_stale_signer_hosts` that checks whether `apt.releases.hashicorp.com` is among the hosts.

### 2. Remedy routing — `_apt_signer_remedy <host>`

A `case` on the host apt prints (M4), returning one remedy string:

| Host(s)                                                                                                                                                                | Class                  | Remedy text (substance)                                                                                                                                                                                        |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `download.docker.com`, `pkgs.k8s.io`, `prod-cdn.packages.k8s.io`, `deb.releases.teleport.dev`, `pkg.cloudflareclient.com`, `download.virtualbox.org`, `cli.github.com` | re-fetched every run   | re-run `./setup_env.sh -t developer` (it re-fetches this key)                                                                                                                                                  |
| `nvidia.github.io`                                                                                                                                                     | re-fetched when absent | `sudo rm /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg`, then re-run `./setup_env.sh -t developer`                                                                                                  |
| `packages.cloud.google.com`                                                                                                                                            | re-fetched when absent | `sudo rm /etc/apt/sources.list.d/google-cloud-sdk.list`, then re-run `./setup_env.sh -t developer`                                                                                                             |
| `packages.opentofu.org`                                                                                                                                                | re-fetched when absent | `curl -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey \| sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/opentofu-archive-keyring.gpg` (the install step re-fetches only when `tofu` is absent) |
| `packages.microsoft.com`                                                                                                                                               | pinned                 | verify Microsoft's new key, replace `keys/microsoft.asc` and bump `MS_GPG_FPR` in `lib/constants.sh`                                                                                                           |
| `download.opensuse.org`                                                                                                                                                | pinned                 | verify the albert OBS key's new fingerprint and bump `ALBERT_GPG_FPR` in `lib/constants.sh`                                                                                                                    |
| anything else                                                                                                                                                          | unknown                | dotfiles has no remedy for this host; refresh its key by hand                                                                                                                                                  |

`apt.releases.hashicorp.com` is deliberately absent, because its source is never present when
`-t update` runs. If it ever appears, it takes the unknown branch, which still WARNs.

Each remedy names a function or path. When an install guard changes, the matching row is
updated in the same change. A comment above the `case` says so and names the functions:
`_install_ubuntu_nvidia`, `_install_ubuntu_cloud_tools`, `_install_ubuntu_misc`.

### 3. Reporting and verdict

- For each stale host, `update_apt_packages` emits one `log_warn` line:
  `apt: <host> is not updating: signature check failed (<token>): signer rotated or expired, or a proxy served unsigned data; <remedy>`.
  The lines are emitted **after** the upgrade and autoremove steps. That puts them last in
  `err_apt`, inside the `tail -10` budget of `_update_write_detail_from_err`.
- Return codes:
  - **0:** clean.
  - **1:** any step failed, as today.
  - **2:** at least one stale host, and every step succeeded.
  - If a step fails, the stale lines are still emitted before returning 1. That covers both
    `apt-get update` failing and a later step failing.
- `run_update` maps rc 2 the way the flatpak section does. It records `_update_record_end "apt" 0`,
  then `_update_warn "apt" "signer check failed for <host>[, <host>…] — see detail"`, then
  `_update_write_detail_from_err "apt" "update output"`. The host list in the summary comes from
  running `_apt_stale_signer_hosts` over `err_apt`, so the parser has one definition. A
  WARN-only run exits 0.
- The upgrade still runs when a host is stale. Updates from every other source must not stop
  because one source went stale.

### 4. Coverage bound (stated, not hidden)

A signer **rotation** produces a new `InRelease` signed by a key the box lacks. apt fetches it,
fails verification, and warns on every run until it is fixed. So detection fires on the first
`-t update` after the rotation.

**Expiry** is less certain. If upstream re-publishes `InRelease` after the box's copy of the key
has expired, apt fetches it, gets `EXPKEYSIG`, and warns. If upstream does not re-publish, apt
may get `304 Not Modified`, skip verification, and print nothing until the next publication. In
that case detection is bounded by the publisher's cadence, not the expiry date. V1 measures this.
If V1 shows silence, this section is amended to state the bound plainly, and a backlog row
records the predictive doctor check this spec declines (Alternatives).

## Alternatives

- **Predictive doctor expiry check** (read each `signed-by` keyring, WARN when no signing key
  outlives N days). It would have flagged k8s's 2026-12-28 expiry today. Declined by the operator
  2026-10-17 in favour of `-t update` only. It costs more surface: armored and binary keyrings,
  inline `Signed-By` blocks in `.sources` files, and subkey semantics. It also catches only
  expiry, not rotation. Revisit if V1 shows expiry is silent.
- **Auto re-fetch in `-t update`** for the re-fetchable hosts. Declined by the operator: trust
  would change without the operator seeing it, and `-t update` would gain a write path into
  `/etc/apt`.
- **Generic WARN with no remedy routing.** Declined by the operator: the operator would have to
  work out which of four routes applies.
- **A drift guard deriving the host table from the code.** It was in the outline the operator
  approved, and this spec drops it. The hosts cannot be derived statically: nvidia's
  `.list` comes from upstream (`nvidia.github.io` never appears as a literal in a source line),
  and k8s is printed under a redirect host (M4). A guard derived from the code would be wrong
  in exactly the cases that matter. The cost of drift is bounded: an unmapped host still WARNs,
  only with the unknown remedy. **This is a change from the approved outline and needs the
  operator's confirmation at spec review.**

## Testing

Fixtures are captured from real `apt-get update 2>&1` output, never hand-typed. A multi-host
fixture is built by concatenating captured files, so every line is still real.

- `tests/fixtures/apt/update-clean-claude.txt`: the M4 capture.
- `tests/fixtures/apt/update-hashicorp-stale-rotated.txt`: the existing M3 fixture.
- A k8s-redirect stale capture and a noble capture, both from V2.

Cases:

1. **Positive control (pins a specific derived value):** the stale-rotated fixture produces
   exactly `apt.releases.hashicorp.com<TAB>NO_PUBKEY` and nothing else.
2. The clean fixture produces empty output, and `update_apt_packages` returns 0.
3. The two-host concatenation produces two lines in first-appearance order.
4. `_apt_signer_remedy`: one case per class, plus the unknown branch, each asserting the
   substance from the table (host, path or constant name).
5. Through `run_update`, with the `apt-get` mock printing the stale fixture on stderr and
   exiting 0: the summary row is `WARN` and names the host, the detail file contains the
   `apt: … is not updating` line, and the run exits 0.
6. The stale fixture plus a failing `nala full-upgrade`: rc 1, and the stale line is still
   emitted.
7. The mock records that the refresh is `apt-get update`, not `apt update`.
8. The temp directory is gone after both a successful run and a failing one. The test uses its
   own tmp-root seam, because BSD `mktemp -d` with a template ignores `TMPDIR`.
9. The existing `_hashicorp_rotation_hint_fires` tests pass unchanged.

## Requirements

- **R1.** `update_apt_packages` refreshes with `sudo -H apt-get update`, shows its output live, captures it to a file inside a `mktemp -d` directory that is removed on every return path, and treats only `apt-get`'s exit status as refresh failure.
- **R2.** `_apt_stale_signer_hosts` reads stdin and prints one `host<TAB>token` line per distinct host, in first-appearance order, for lines starting `W:` or `E:` that contain one of `NO_PUBKEY`, `EXPKEYSIG`, `EXPSIG`, `KEYEXPIRED`, `REVKEYSIG`, `is not signed`, `is no longer signed`, taking the authority of the first `https?://` URL on the line and ignoring token lines without a URL.
- **R3.** The token list is defined once, and `_hashicorp_rotation_hint_fires` decides by calling `_apt_stale_signer_hosts`.
- **R4.** `_apt_signer_remedy <host>` returns the remedy for each host and class in Design section 2's table, and the unknown-host text for any other host.
- **R5.** For each stale host, `update_apt_packages` emits one `log_warn` line of the form `apt: <host> is not updating: signature check failed (<token>): signer rotated or expired, or a proxy served unsigned data; <remedy>`, after the upgrade and autoremove steps, or before returning 1 when a step failed.
- **R6.** `update_apt_packages` returns 0 with no stale host, 2 with at least one stale host when every step succeeded, and 1 when any step failed.
- **R7.** `run_update` records `apt` rc 2 as WARN via `_update_record_end "apt" 0` then `_update_warn "apt" "signer check failed for <hosts, comma-joined> — see detail"` and `_update_write_detail_from_err`, and a run whose only non-OK section is that WARN exits 0.
- **R8.** Tests 1-9 in the Testing section exist and pass, with fixtures captured from real `apt-get update 2>&1` output.
- **V1.** In an unprivileged sandbox, measure whether `apt-get update` warns for a source whose key has expired (key built with `--faked-system-time`) when upstream `InRelease` is unchanged since the last fetch, and when it is re-published. Record both results in this spec. If the first is silent, amend Design section 4 to state the bound and add a P2 backlog row for the doctor expiry check.
- **V2.** Capture a stale-signer `apt-get update 2>&1` for a redirected source (k8s or equivalent) and on noble (an `ubuntu:24.04` container on `claude`). Confirm `_apt_stale_signer_hosts` returns the host apt actually printed, and commit both captures as fixtures.
- **V3.** After merge, run `./setup_env.sh -t update` on `claude`. The `apt` row reads OK, and no `apt: … is not updating` line appears, because no source is stale today (M1).
- **N1.** `-t update` does not write, fetch or delete any keyring, source file or apt trust setting.
- **N2.** No doctor check and no keyring-expiry parsing are added.
- **N3.** The install-time key-fetch conditions in `_install_ubuntu_nvidia`, `_install_ubuntu_cloud_tools` and `_install_ubuntu_misc` are unchanged.
- **N4.** The base step's `apt update` call and message (`lib/linux_ubuntu.sh:223`) are unchanged; its stale `E:/W:` wording stays with its own P3 row.
- **N5.** A stale signer alone never turns the `apt` section into FAIL or the run's exit code non-zero.
