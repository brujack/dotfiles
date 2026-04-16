# Linux Package Update Tracking Design

**Date:** 2026-04-15
**Status:** Approved

## Context

The update summary system already tracks brew formula/cask updates with pre/post
snapshots and name+version diffs. Linux package updates (`apt`/`nala`, `snap`,
`dnf`, `yum`) currently run inside `update_system_packages()` with no tracking —
they produce no structured output in the summary. Additionally, Linux package
updates are incorrectly bundled into the `mas` section in `run_update`.

## Goal

Show per-package name and version for every Linux package manager update, in
their own dedicated summary sections, using the same pre/post diff pattern as
brew. Each manager shows `[SKIP] not applicable` on systems that don't use it.

## Design

### Section order (`update_summary.sh`)

Four new sections added to `_UPDATE_SECTION_ORDER` after `softwareupdate` and
before `mas`:

```bash
readonly _UPDATE_SECTION_ORDER=(
  brew softwareupdate apt snap dnf yum mas claude pip gems
  oh-my-zsh p10k tpm tfenv cheat.sh
)
```

`apt` and `snap` are adjacent (both Ubuntu). `dnf` and `yum` follow (RHEL
family).

### Pre-snapshot commands (`_update_record_start`)

| Section | Distro guard         | Command                                                |
| ------- | -------------------- | ------------------------------------------------------ |
| `apt`   | `UBUNTU`             | `dpkg-query -W -f='${Package} ${Version}\n'`           |
| `snap`  | `UBUNTU`             | `snap list --color=never \| awk 'NR>1 {print $1, $2}'` |
| `dnf`   | `REDHAT` or `FEDORA` | `rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n'`       |
| `yum`   | `CENTOS`             | `rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n'`       |

If the distro guard is not satisfied, `_update_record_start` calls
`_update_skip "<section>" "not applicable"` and returns immediately. This means
`_update_record_end` must check for an existing SKIP file and bail out without
overwriting it.

### Post-snapshot and diff (`_update_record_end`)

Same `comm -13` diff pattern as brew:

1. Run the same list command as pre-snapshot, write to `post_<section>`
2. Diff with `_update_diff_lines pre_<section> post_<section>`
3. Count changed lines with `grep -c .`
4. If count > 0: `"N package(s) (name1 ver1, name2 ver2, ...)"`
5. If count = 0: `"no changes"`
6. If no pre-snapshot file: fall back to `"updated"`
7. If SKIP file already exists for the section: return without overwriting

### `run_update` changes (`workflows.sh`)

Remove `update_system_packages` from the `mas` block.

Add a new `# ── Linux system packages` block between `softwareupdate` and
`claude`:

```bash
if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_PKGS:-} ]]; then
  if [[ -n ${LINUX} ]]; then
    _update_record_start "apt"
    _update_record_start "snap"
    _update_record_start "dnf"
    _update_record_start "yum"
    update_system_packages
    local _pkg_ec=$?
    _update_record_end "apt"  "${_pkg_ec}"
    _update_record_end "snap" "${_pkg_ec}"
    _update_record_end "dnf"  "${_pkg_ec}"
    _update_record_end "yum"  "${_pkg_ec}"
  else
    _update_skip "apt"  "not applicable"
    _update_skip "snap" "not applicable"
    _update_skip "dnf"  "not applicable"
    _update_skip "yum"  "not applicable"
  fi
else
  _update_skip "apt"  "flag not set"
  _update_skip "snap" "flag not set"
  _update_skip "dnf"  "flag not set"
  _update_skip "yum"  "flag not set"
fi
```

The `_update_record_start` calls handle the per-distro "not applicable" skip
internally, so managers not applicable on the current distro write their SKIP
file before `update_system_packages` runs and `_update_record_end` leaves them
untouched.

### `process_args` changes (`helpers.sh`)

Add `--pkgs-only` flag mirroring the existing `--brew-only`, `--mas-only`
pattern:

```bash
--pkgs-only) [[ -n "${UPDATE_PKGS+x}" ]] || readonly UPDATE_PKGS=1 ;;
```

Uses `${VAR+x}` guard (bash 3.2 compatible) to survive double-invocation, same
as all other flags in `process_args`.

### New mocks (`tests/mocks/`)

| Mock         | Subcommand               | Controlled by           |
| ------------ | ------------------------ | ----------------------- |
| `dpkg-query` | `-W`                     | `MOCK_DPKG_OUTPUT`      |
| `rpm`        | `-qa`                    | `MOCK_RPM_OUTPUT`       |
| `snap`       | `list` (extend existing) | `MOCK_SNAP_LIST_OUTPUT` |

All mocks follow the standard pattern: log to `MOCK_CALLS_FILE`, check
`MOCK_<CMD>_EXIT` for forced failure, return mock output, otherwise pass through
to real binary.

## Tests

### `tests/setup_env/update_summary.bats`

**`_update_record_start` — pre-snapshot:**

- `apt` creates `pre_apt` when `UBUNTU` is set
- `apt` writes SKIP "not applicable" when `UBUNTU` is unset
- `snap` creates `pre_snap` when `UBUNTU` is set
- `snap` writes SKIP "not applicable" when `UBUNTU` is unset
- `dnf` creates `pre_dnf` when `REDHAT` or `FEDORA` is set
- `dnf` writes SKIP "not applicable" otherwise
- `yum` creates `pre_yum` when `CENTOS` is set
- `yum` writes SKIP "not applicable" otherwise

**`_update_record_end` — diff and result:**

- Reports name+version for changed packages (apt, snap, dnf, yum)
- Reports "no changes" when pre equals post (all four)
- Does not overwrite existing SKIP file (all four) — checked by testing that
  `status_<section>` still reads `SKIP` after `_update_record_end` is called
  on a section whose `_update_record_start` wrote SKIP

**`process_args` — `--pkgs-only` flag:**

- `--pkgs-only` sets `UPDATE_PKGS=1`
- Calling `process_args --pkgs-only` twice does not crash (double-invocation
  safety for `readonly` guard)

### `tests/setup_env/workflows.bats`

- On Ubuntu: `apt` and `snap` run; `dnf` and `yum` show "not applicable"
- On RHEL/Fedora: `dnf` runs; `apt`, `snap`, `yum` show "not applicable"
- On CentOS: `yum` runs; `apt`, `snap`, `dnf` show "not applicable"
- On macOS: all four show "not applicable"
- `UPDATE_PKGS` unset and `_run_all=0`: all four show "flag not set"
- `update_system_packages` is not called from the `mas` block

## Summary output examples

**Ubuntu 24.04:**

```
[OK]   apt              14 package(s) (curl 7.88.1, git 2.44.0, ...)
[OK]   snap             2 package(s) (firefox 124.0, chromium 123.0)
[SKIP] dnf              not applicable
[SKIP] yum              not applicable
```

**RHEL 9:**

```
[SKIP] apt              not applicable
[SKIP] snap             not applicable
[OK]   dnf              8 package(s) (curl 7.76.1-26.el9, ...)
[SKIP] yum              not applicable
```
