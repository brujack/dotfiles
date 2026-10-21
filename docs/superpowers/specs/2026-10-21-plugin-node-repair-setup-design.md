# Plugin node-path repair: atomic rewrite, and run it from setup/developer

- **Date:** 2026-10-21
- **Status:** Draft (Phase 1)
- **Trigger:** backlog P2 rows "`repair_plugin_node_paths` rewrites in place, not atomically"
  and "`-t setup` and `-t developer` never run the plugin node-path repair"
  (`docs/superpowers/README.md`).

## Problem

Each claim was checked on 2026-10-21.

**1. The hazard is live on both Linux development boxes.** context-mode writes
`process.execPath` into its cached `hooks/hooks.json` and `.claude-plugin/plugin.json` on Linux
(upstream mksglu/context-mode#1090). On `workstation`, context-mode 1.0.169's two configs pin
`/home/linuxbrew/.linuxbrew/Cellar/node/26.12.0/bin/node`, which is executable today (read with
`grep -oE` over those two files and `[ -x ]` on each path). linuxbrew node is present on both
`workstation` and `claude` at 26.12.0 (`ls` of `Cellar/node`). It is a dependency, not a request:
the workstation's `INSTALL_RECEIPT.json` says `installed_on_request: false`, and the kegs whose
receipts list node as a runtime dependency are `codeburn`, `mongodb-atlas-cli` and `mongosh`, all
three on the linuxbrew list in `lib/linux_ubuntu.sh`. `claude`'s configs pin no Cellar path, since
#288's repair already moved them to `opt/node`. The Studio is clean, because upstream skips the
rewrite on macOS (#288). So the next linuxbrew upgrade that moves node breaks the workstation's
context-mode hooks.

**2. `-t setup` and `-t developer` upgrade node without repairing.** The backlog row named
`brew bundle`, which is macOS only. On Linux the upgrade comes from `brew_update`'s
`brew upgrade --yes` (`lib/helpers.sh`), which `_install_ubuntu_brew_packages` calls inside
`install_ubuntu_packages`, inside `run_setup_or_developer`. macOS reaches `brew_update` and
`brew bundle` through `install_macos_packages`. `repair_plugin_node_paths` has one caller,
`run_update`'s `plugin-node` section (`grep -rn repair_plugin_node_paths lib/ setup_env.sh`).

**3. The rewrite is not atomic.** `repair_plugin_node_paths` writes
`printf '%s\n' "${_content//…}" > "${_file}"`. The redirect truncates before writing, so a failed
write (ENOSPC, EIO) leaves an empty or partial config, and the next doctor run PASSes it because it
no longer holds a stale path.

## Design

### Atomic rewrite in `repair_plugin_node_paths` (`lib/helpers.sh`)

For each stale pin, after the existing `opt/` check:

1. If `[[ ! -w "${_file}" ]]`, refuse with the existing `cannot repair <file>: rewrite failed`
   message and `_failed=1`. A temp-plus-rename replaces a read-only file whenever its directory is
   writable, so without this check the atomic version would rewrite files the current one refuses.
2. Create the temp file beside the config: `_tmp="$(mktemp "${_file}.XXXXXX")"`. Same directory,
   so the rename never crosses a filesystem.
3. `cp -p "${_file}" "${_tmp}"` copies the mode (`mktemp` creates 0600, and `-p` works on GNU and
   BSD `cp`). Then `printf '%s\n' "${_content//…}" > "${_tmp}"` writes the new content into it.
4. `mv -f "${_tmp}" "${_file}"`.
5. If any of steps 2-4 fails: `rm -f "${_tmp}"` (only when `_tmp` is non-empty), print
   `cannot repair <file>: rewrite failed`, set `_failed=1`, and continue with the next file. The
   original config is unchanged in every failure case.

Each `cannot repair` line ends with the remedy for its cause, because doctor's remedy
(`setup_env.sh -t update --brew-only`) re-runs this same repair and cannot clear either cause:

- missing `opt/` link: `cannot repair <file>: <node> is gone and <opt path> does not exist — run: brew install <formula>`
- failed rewrite: `cannot repair <file>: rewrite failed — check write permission and free space in <dir>`

The existing `cannot repair <file>: rewrite failed` text stays a prefix, so current assertions on it
keep matching.

No EXIT or RETURN trap (lib files are checked by `check-lib-exit-traps.sh`); cleanup is explicit,
as in `_install_apt_keyring`. The return contract is unchanged: 0 nothing stale or all repaired,
1 any pin not repaired, 2 no plugin cache.

### Run the repair from `run_setup_or_developer` (`lib/workflows.sh`)

Immediately after the platform package block (the `MACOS` `install_macos_packages` call and the
`UBUNTU` `install_ubuntu_packages` block), and before `install_cargo_tools`:

```bash
  # The package step can upgrade brew node, which strands any plugin config
  # pinned to the old Cellar path (see _claude_plugin_cache_dir).
  local _plugin_node_rc=0
  repair_plugin_node_paths || _plugin_node_rc=$?
  if [[ ${_plugin_node_rc} -eq 1 ]]; then
    log_warn "plugin node paths: some pins could not be repaired — see the 'cannot repair' lines above"
  fi
```

- It runs unconditionally. The repair only rewrites a pin whose node binary is gone, so it is a
  no-op unless node changed, whatever changed it.
- rc 2 (no plugin cache) is silent, and rc 1 warns and continues, in the same degrade-not-abort
  shape as the cargo and aws steps. The function's exit status is unaffected.
- The repair's own `repaired …` and `cannot repair …` lines go to the terminal as they do today.
- `-t update` is unchanged.

### Testing

`tests/setup_env/plugin_node_paths.bats` (seams already at setup scope:
`_OVERRIDE_CLAUDE_PLUGIN_CACHE`, a fake brew prefix):

1. A failed rename (`MOCK_MV_FAIL_ARGS` matching the config path) leaves the config
   byte-identical, leaves no `<file>.*` temp beside it, returns 1, and prints `rewrite failed`.
2. A failed temp creation (the plugin directory made read-only, `chmod 555`; `mktemp` itself fails
   there) leaves the config byte-identical and returns 1. Skipped as root, like the existing
   read-only test, and the test restores the directory to 755 before it ends so bats can delete it.
2b. A failed copy (`MOCK_CP_EXIT=1`; `tests/mocks/cp` otherwise swallows a real `cp` failure with
   `|| true`) leaves the config byte-identical, leaves no temp, and returns 1. The write-to-temp
   failure branch has no seam and is not tested; it shares the cleanup path with 2 and 2b.
3. A repaired config keeps its original mode (seed 0640, assert 0640 after, read with
   `stat -c %a` falling back to `stat -f %Lp` so `test-macos` runs it), the pin is rewritten to the
   `opt/` path, and no temp is left.
3b. Each `cannot repair` line carries its remedy: `run: brew install node` for a missing `opt/`
   link, and `check write permission and free space` for a failed rewrite.
4. The existing "returns 1 for a file it cannot write" test still passes: a 0444 config in a
   writable directory is refused and keeps its stale pin.
5. Existing repair tests keep passing.

`tests/setup_env/cargo_tools_update.bats` or a new block beside the existing
`run_setup_or_developer` tests:

6. `run_setup_or_developer` calls `repair_plugin_node_paths` after `install_macos_packages` and
   before `install_cargo_tools` (order log, as in the existing cargo ordering test).
7. With the repair stubbed to return 1, the run returns 0 and prints
   `plugin node paths: some pins could not be repaired — see the 'cannot repair' lines above`.
8. With the repair stubbed to return 2, the run returns 0 and prints no `plugin node paths` line.
9. Under `UBUNTU`, the call comes after `install_ubuntu_packages`.

Tests 1 and 2 fail against the current in-place write: it never calls `mktemp` or `mv` and needs
no directory write permission, so under both conditions it rewrites the config and returns 0, and
the byte-identical assertion fails. Test 3 passes against the current code (an in-place write
keeps the inode and its mode) and guards against a rename that drops the mode to `mktemp`'s 0600. Test 4 fails if the `-w` check is dropped. Tests 6 and 9 fail if the
call is missing or misplaced.

## Out of scope

- A snapshot of node versions to gate the repair (operator chose unconditional, 2026-10-21).
- Repairing after a manual `brew upgrade` or a Claude Code background plugin update; doctor
  remains the backstop there.
- Changing `run_update`'s `plugin-node` section.
- Doctor's own remedy for a stale pin (`-t update --brew-only`) is circular for the two
  unrepairable causes; `_doctor_check_plugin_node_paths` is out of scope (N1), so that is filed as
  a backlog row in this change.
- The knowledge-file sentence in ai-config `dotfiles-test-seams.md` saying a `-t setup` node
  upgrade does not run the repair; updated in a separate ai-config change after merge.

## Requirements

- **R1.** `[atomic]` `repair_plugin_node_paths` writes each repaired config to a temp file created by `mktemp "${_file}.XXXXXX"` in the config's directory and renames it over the config with `mv -f`; no redirect writes the config path directly.
- **R2.** `[atomic]` When temp creation, the copy, the write or the rename fails, the original config is byte-identical afterwards, no temp file remains beside it, the function prints `cannot repair <file>: rewrite failed`, and it returns 1.
- **R3.** `[atomic]` A config that is not writable (`[[ ! -w ]]`) is refused with the same message and left unchanged, even when its directory is writable.
- **R4.** `[atomic]` A repaired config keeps its original file mode.
- **R5.** `[setup]` `run_setup_or_developer` calls `repair_plugin_node_paths` unconditionally, after the platform package step (`install_macos_packages` / `install_ubuntu_packages`) and before `install_cargo_tools`.
- **R6.** `[setup]` A repair rc of 1 prints a `plugin node paths: some pins could not be repaired — see the 'cannot repair' lines above` warning and does not stop or change the exit status of `run_setup_or_developer`; rc 2 prints nothing.
- **R7.** `[atomic]` A `cannot repair` line for a missing `opt/` link ends with `— run: brew install <formula>`, and one for a failed rewrite ends with `— check write permission and free space in <dir>`.
- **V1.** `make test` exits 0 and CI is green, including `bash-coverage` at or above 91%.
- **V2.** On `workstation`, after the next `-t developer` that upgrades linuxbrew node, `setup_env.sh -t doctor` reports `no plugin pins a missing node binary`.
- **N1.** No change to `_plugin_stale_node_paths`, `_doctor_check_plugin_node_paths` or `run_update`'s `plugin-node` section.
- **N2.** No snapshot or comparison of node versions gates the repair.
- **N3.** No EXIT or RETURN trap is added to `lib/helpers.sh`.

## Multi-Lens Review

Reviewed at commit: `ba6d7d49` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: No issues. Premise verified on `workstation`: all six cached context-mode versions (1.0.162-1.0.169) pin `Cellar/node/26.12.0`. Upstream will not heal it: `hooks/normalize-hooks.mjs:126` rewrites a config only for a placeholder or a stale cache-version path, and a dead MCP command stops `start.mjs` booting. Raised as a preference, not a flaw: call the repair inside `brew_update` after its `brew cleanup`, covering every brew upgrade path.
Assumption: the old `Cellar/node/<ver>` is deleted within the same run, before the repair; confident it holds (`brew_update` runs `brew cleanup`, nothing sets `HOMEBREW_NO_INSTALL_CLEANUP`).
Disposition: Accepted, reason: operator kept the `run_setup_or_developer` placement (2026-10-21); in `brew_update` the repair would run twice under `run_update` and its output would land in `err_brew`, and `brew_update`'s 0/1/2 contract would have to absorb its rc.

### Ergonomics

Finding: the rc-1 warning pointed at doctor, whose remedy (`-t update --brew-only`) re-runs the same failing repair; neither unrepairable cause (missing `opt/` link, failed write) clears that way. Test 3 passed vacuously if the repair did nothing.
Assumption: a repaired `opt/` pin lasts (context-mode does not write the versioned path back at runtime). Answered by goal-fit's read of `normalize-hooks.mjs:126` and `claude`'s configs (15 `opt/node` pins, 0 Cellar pins, one rewritten 2026-10-21).
Disposition: Addressed — each `cannot repair` line now carries its cause's remedy (R7), the setup warning points at those lines (R6), test 3 asserts the rewrite, and doctor's circular remedy is filed as a backlog row (N1 keeps doctor out of scope).

### Risk

Finding: no load-bearing flaw; mechanics verified by running them (mode restored through `cp -p`, no symlinked or hardlinked configs among 133 on `claude`, `mktemp` fails in a 555 directory, a leftover temp is never matched by the `find`). Gaps: copy and write failures in R2 untested (`tests/mocks/cp` swallows `cp` failures); test 2 must restore the directory mode; test 3's mode read must work with BSD `stat`.
Assumption: same as Ergonomics; answered there.
Disposition: Addressed — test 2b (`MOCK_CP_EXIT=1`) added, the write-to-temp branch stated as untested, test 2 restores 755, test 3 uses `stat -c %a` with a `stat -f %Lp` fallback.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
