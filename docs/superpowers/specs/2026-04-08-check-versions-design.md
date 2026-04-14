# Version Drift Detection Design

**Status:** Draft
**Date:** 2026-04-08

## Goal

Add `-t check-versions` that compares pinned tool versions in `lib/constants.sh` against the latest releases on GitHub. Exits 0 if all pinned versions are current, 1 if any are outdated.

## Tools Checked

Only tools that have a GitHub releases page and a reliable way to get the installed version:

| Tool       | Pinned constant  | GitHub repo           | Installed version cmd  |
| ---------- | ---------------- | --------------------- | ---------------------- |
| Go         | `GO_VER`         | `golang/go`           | `go version`           |
| Python     | `PYTHON_VER`     | `python/cpython`      | `python3 --version`    |
| Ruby       | `RUBY_VER`       | `ruby/ruby`           | `ruby --version`       |
| zsh        | `ZSH_VER`        | `zsh-users/zsh`       | `zsh --version`        |
| YQ         | `YQ_VER`         | `mikefarah/yq`        | `yq --version`         |
| Shellcheck | `SHELLCHECK_VER` | `koalaman/shellcheck` | `shellcheck --version` |
| Vagrant    | `VAGRANT_VER`    | `hashicorp/vagrant`   | `vagrant --version`    |

Tools not checked (no reliable GitHub releases API or installed via brew with automatic versioning): `BATS_VER`, `CONSUL_VER`, `NOMAD_VER`, `TERRAFORM_VER`, `VAULT_VER` — these are HashiCorp tools where release patterns differ.

## Architecture

### New function `run_check_versions()` in `lib/workflows.sh`

Dispatched from `setup_env.sh` via:

```bash
[[ -n ${CHECK_VERSIONS:-} ]] && { run_check_versions; exit $?; }
```

### GitHub releases API

Latest release fetched via:

```bash
curl -sf "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep '"tag_name"' \
  | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' \
  | sed 's/^v//'
```

Strip leading `v` for consistent comparison. If `curl` fails or returns empty, soft-fail: print `[WARN] <tool>: could not fetch latest version` and continue (not counted as outdated).

### Version comparison

String equality on the full version string (after stripping `v` prefix and any trailing metadata). If pinned == latest → `[OK]`. If different → `[OUTDATED]`.

No semver range logic — exact match only. This is intentional: if you've pinned `1.26` and latest is `1.26.1`, that's flagged as outdated, prompting a deliberate update of the constant.

### Installed version check

If the tool is not installed (`command -v` fails), print `[SKIP] <tool>: not installed` and don't count as outdated. Installation presence is covered by `run_doctor`.

### Output format

```
=== Version Check ===

  [OK]       go          pinned=1.26     latest=1.26
  [OUTDATED] python3     pinned=3.14.3   latest=3.15.0
  [OK]       ruby        pinned=4.0.2    latest=4.0.2
  [SKIP]     vagrant     not installed
  [WARN]     shellcheck  could not fetch latest version

1 outdated, 1 skipped, 1 warning, 3 OK
```

Exit 0 if no `[OUTDATED]` lines. Exit 1 if any `[OUTDATED]`.

### `process_args()` in `lib/helpers.sh`

Add `check-versions` as a valid `-t` type:

```bash
check-versions) readonly CHECK_VERSIONS=1 ;;
```

### `usage()` update

Add `check-versions` to the types table:

```
  check-versions : Compare pinned tool versions in lib/constants.sh against latest GitHub releases
```

## Rate Limiting

GitHub's unauthenticated API allows 60 requests/hour. With 7 tools, a single run uses 7 requests — well within limits. No auth token required.

If a `GITHUB_TOKEN` env var is set, it's passed as `Authorization: Bearer ${GITHUB_TOKEN}` to increase the limit (useful in CI).

## Testing

New tests in `tests/setup_env/unit.bats`:

- `process_args` sets `CHECK_VERSIONS` for `-t check-versions`
- `run_check_versions` exits 0 when all versions match (mock curl to return matching version)
- `run_check_versions` exits 1 when any version is outdated (mock curl to return newer version)
- `run_check_versions` soft-fails (exits 0) when curl returns error for one tool
- `run_check_versions` skips tool when not installed

Mock `curl` via `MOCK_CURL_STDOUT` and `MOCK_CURL_EXIT` from existing mock infrastructure.

## Files Modified

| Action | File                                                                      |
| ------ | ------------------------------------------------------------------------- |
| Modify | `lib/helpers.sh` — add `check-versions` to `process_args()` and `usage()` |
| Modify | `lib/workflows.sh` — add `run_check_versions()`                           |
| Modify | `setup_env.sh` — add dispatch line for `CHECK_VERSIONS`                   |
| Modify | `tests/setup_env/unit.bats` — add version check tests                     |
| Modify | `CLAUDE.md` — add `check-versions` to Entry Points table                  |
| Modify | `README.md` — add `check-versions` to Usage table                         |
