# apt fixtures

Real captured output; never hand-edited. Captured 2026-10-17.

## update-clean-resolute.txt

- Host: Ubuntu 26.04 (resolute), `apt 3.2.0 (amd64)`, unprivileged, no sudo.
- Command: `apt -o Dir::State::Lists=$d/lists -o Dir::Cache=$d/cache -o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts=$d/parts -o Debug::NoLocking=1 -o APT::Sandbox::User=$(id -un) update` with the host's `sources.list.d` copied to `$d/parts` (`*.orig` skipped).
- rc: 0

## update-stale-rotated-resolute.txt

- Same host, version and options as above. `$d/parts/docker.list` had `signed-by` pointed at `/etc/apt/keyrings/opentofu-archive-keyring.gpg` (wrong key). This is the second `update` run over the stale source (the first also gave rc 0).
- rc: 0 (both runs)
- Considered line: `Warning: Failed to fetch https://download.docker.com/linux/ubuntu/dists/resolute/InRelease  ... NO_PUBKEY 7EA0A9C3F273FCD8` (apt 3.x prefixes `Warning:`/`Error:`).

## update-stale-rotated-noble.txt

- Container `ubuntu:24.04`, `apt 2.8.3 (amd64)`, `nala 0.15.1`, root inside `docker run --rm`.
- Docker source added with its real key, `apt update`, then `signed-by` swapped to a throwaway key. File is the second stale `apt update` run (lines 42-58 of the container transcript, the output of that one run).
- rc: 0
- Considered line: `W: Failed to fetch https://download.docker.com/linux/ubuntu/dists/noble/InRelease  ... NO_PUBKEY 7EA0A9C3F273FCD8` (apt 2.x uses `W:`/`E:`).

## V1

Question: does apt print a considered line carrying `EXPKEYSIG`/`KEYEXPIRED` and the URL when a signing key expires?

Setup: key with 120 s expiry, one-suite local repo (hand-built `Release`, `gpg --clearsign` to `InRelease`), served by `python3 -m http.server --bind 127.0.0.1 18765`, `apt 3.2.0`, same Dir:: overrides as above.

- Fetch while key valid: rc 0, `Get:1 http://127.0.0.1:18765 test InRelease [492 B]`.
- Expiry run 1 (after ~135 s): rc 0. Yes. `Warning: Failed to fetch http://127.0.0.1:18765/dists/test/InRelease  The following signatures were invalid: EXPKEYSIG 0391781A0D9CE7DB v1@example.invalid`
- Expiry run 2: rc 0. Yes, identical line.
- Result: token is `EXPKEYSIG` (not `KEYEXPIRED`); URL present on the same line. Second run still reports it (no `Hit` silencing).

## V2

rc of every run over a stale source (all 0; apt and nala exit 0 despite the signer failure):

| release | apt version | nala version | apt update (clean) | apt update stale #1 | apt update stale #2 | nala full-upgrade -y | nala full-upgrade --no-update -y |
|---|---|---|---|---|---|---|---|
| noble (24.04) | 2.8.3 | 0.15.1 | 0 | 0 | 0 | 0 | 0 |
| resolute (26.04, container) | 3.2.0 | 0.16.0 | 0 | 0 | 0 | 0 | 0 |
| resolute (26.04, host, unprivileged) | 3.2.0 | n/a | 0 | 0 | 0 | n/a | n/a |

Notes:
- `nala full-upgrade -y` surfaces the stale signer as a Python `Warning: W:An error occurred during the signature verification ... NO_PUBKEY ...` line (from `apt/cache.py`) plus an indented `NO_PUBKEY` line; `nala full-upgrade --no-update -y` prints only `All packages are up to date.` (no signer information).
- Prefix differs: apt 2.8 `W:`, apt 3.2 `Warning:`/`Error:`; nala wraps as `Warning: W:...`.
