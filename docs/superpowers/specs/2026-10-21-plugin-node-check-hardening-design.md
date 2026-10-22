# Plugin node-path check: no false PASS, cause-specific doctor remedy, symlinked cache root

## Problem

Three backlog rows, all about the plugin node-path check (`_plugin_stale_node_paths`,
`lib/helpers.sh`) that `repair_plugin_node_paths` and `_doctor_check_plugin_node_paths`
consume:

1. **A config the check never read reports clean.** The finder greps each config for a
   versioned Cellar node and emits a line per dead pin. Two inputs give it empty stdout:
   - an unreadable file: grep exits 2 with `Permission denied` on stderr;
   - a file grep classifies as binary (a NUL byte): GNU grep exits **0**, prints
     `grep: <file>: binary file matches` on stderr and nothing on stdout.

   Either way doctor prints `[PASS] no plugin pins a missing node binary` over a file it did
   not scan. The backlog row's proposed fix ("capture grep rc >= 2") covers only the first;
   the binary case exits 0.

2. **Doctor's remedy cannot clear two of the causes it reports.** Every stale pin gets
   `run: setup_env.sh -t update --brew-only`, which re-runs the same repair. When the keg's
   `opt/` link is missing (formula not installed) or the config is not writable, the re-run
   fails identically. Since dotfiles#361 the repair's own `cannot repair` lines name the real
   remedy; doctor does not.
3. **A symlinked cache root is scanned as empty.** `[[ -d "${_cache}" ]]` follows a symlink,
   but `find "${_cache}"` (default `-P`) does not descend a symlinked starting point, so the
   finder returns rc 0 with no output: doctor PASSes and the update section reports clean.

### Measurements (2026-10-21)

| Claim                        | Command                                                           | Population                                                         | Result                                                  |
| ---------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------ | ------------------------------------------------------- |
| unreadable → empty, rc 2     | `grep -oE <pin-regex> <chmod-000 file>` under `bash -c`           | one temp fixture, GNU grep on `claude`                             | `rc=2 out=[]`                                           |
| binary → empty, rc 0         | same, file with a trailing `\0`                                   | one temp fixture                                                   | `rc=0`, stderr `binary file matches`, stdout empty      |
| symlinked root not descended | `find <link>` vs `find <link>/`, one file under the target        | one temp fixture                                                   | 0 vs 1                                                  |
| hazard occurs                | per-config `[ -r ]` and a NUL grep over `~/.claude/plugins/cache` | every hooks/plugin config on `claude` (132) and `workstation` (78) | 0 unreadable, 0 with NUL, root a real directory on both |
| root shape on macOS          | `ls -ld ~/.claude/plugins/cache`                                  | the Studio                                                         | real directory                                          |

The defects are real in the code. The hazards for 1 and 3 have not occurred on any measured
machine; the operator chose to fix them anyway (scope A) because each fix is small and item 1
is a doctor PASS that claims more than its mechanism checked.

## Design

### 1. Classify each config before grepping it

`_plugin_stale_node_paths` checks every config `find` yields before running grep:

- not readable (`[[ -r ]]` fails) → emit `<file>\tunreadable`;
- contains a NUL byte → emit `<file>\tbinary`. Detect it with
  `tr -d '\000' < "${_file}" | cmp -s - "${_file}"` (true means no NUL), which behaves the
  same under GNU and BSD;
- otherwise grep as today, under `LC_ALL=C`, so an invalid UTF-8 sequence cannot make grep
  classify a text file as binary.

A real pin always starts with `/`, so the two tags cannot collide with one. No `grep -a`:
it would find a pin inside a binary config, but the repair reads the file with `$(<file)`,
which drops NUL bytes, so the rewrite would corrupt it. A binary config is refused, never
rewritten.

Consumers:

- `repair_plugin_node_paths`: for a tag line print
  `cannot repair <file>: not readable as text — check its permissions and contents`, set
  `_failed=1`, `continue`. The file is not touched. rc stays 0/1/2, so the `-t update`
  section and `run_setup_or_developer` need no change: both already warn on rc 1.
- `_doctor_check_plugin_node_paths`: for a tag line
  `doctor_fail "<file>" "cannot be read as text — check its permissions and contents"`.
  No PASS when any config was unread.

### 2. Doctor names the cause-specific remedy

Extract the `_formula`/`_stable` derivation from `repair_plugin_node_paths` into
`_plugin_stable_node <node>`, which prints `<formula>\t<stable path>`. The repair and doctor
both call it (two callers).

For each stale pin doctor chooses:

- `opt/` link not executable → `pins missing <node> — run: brew install <formula>`;
- config not writable → `pins missing <node> — check write permission on <file>`;
- otherwise → `pins missing <node> — run: setup_env.sh -t update --brew-only` (unchanged).

A full disk cannot be predicted from doctor; it keeps the generic remedy, and the repair's
own line names free space.

### 3. Descend a symlinked cache root

`find "${_cache}/"` instead of `find "${_cache}"`. Measured 2026-10-21 on a temp fixture:
`find "<dir>/" -type f` prints `<dir>/p/f`, with no doubled slash, under GNU find on `claude`
and BSD find on the Studio, so doctor's `${_file#"${_cache}/"}` label is unchanged. Test 5
pins it.

## Testing

In `tests/setup_env/plugin_node_paths.bats`, under the existing `_OVERRIDE_CLAUDE_PLUGIN_CACHE`
setup seam:

1. An unreadable config (`chmod 000`, root-skip): finder emits `<file>\tunreadable`;
   repair returns 1 with the not-readable line and leaves the file byte-identical; doctor
   FAILs it and sets the failure flag; no `[PASS]` line.
2. A config with a NUL byte holding a stale pin: finder emits `<file>\tbinary` and not the
   pin; repair returns 1 and leaves the file byte-identical (`cmp` against a saved copy);
   doctor FAILs it.
3. A readable sibling config in the same cache is still reported and repaired (one bad file
   does not stop the scan).
4. Doctor remedy, one test each: missing `opt/` link → `run: brew install node`;
   read-only config with the `opt/` link present → `check write permission on`; writable
   config with the link present → `run: setup_env.sh -t update --brew-only`.
5. A cache root that is a symlink to a directory holding a stale pin: the finder reports it;
   doctor's label is the path relative to the cache, with no doubled slash.
6. Existing tests keep passing; the doctor test asserting the `-t update --brew-only` text
   uses the writable, link-present fixture, so it still holds.

## Requirements

- **R1.** `_plugin_stale_node_paths` emits `<file>\tunreadable` for a config it cannot read and `<file>\tbinary` for a config containing a NUL byte, and emits no pin line for either.
- **R2.** `_plugin_stale_node_paths` runs its pin grep under `LC_ALL=C` and does not use `grep -a`.
- **R3.** For an `unreadable` or `binary` line, `repair_plugin_node_paths` prints `cannot repair <file>: not readable as text — check its permissions and contents`, leaves the file unchanged, and returns 1.
- **R4.** For an `unreadable` or `binary` line, `_doctor_check_plugin_node_paths` calls `doctor_fail` with `cannot be read as text — check its permissions and contents` and does not print `no plugin pins a missing node binary`.
- **R5.** `_plugin_stable_node <node>` prints `<formula>\t<stable path>`, and both `repair_plugin_node_paths` and `_doctor_check_plugin_node_paths` use it.
- **R6.** For a stale pin, doctor's remedy is `run: brew install <formula>` when the `opt/` node is not executable, else `check write permission on <file>` when the config is not writable, else `run: setup_env.sh -t update --brew-only`.
- **R7.** `_plugin_stale_node_paths` passes `"${_cache}/"` to `find`, so a symlinked cache root is descended.
- **V1.** `make test` exits 0 and CI is green, including `bash-coverage` at or above 91%.
- **V2.** On `claude` and `workstation`, `./setup_env.sh -t doctor` prints the same plugin node-path verdict before and after the change (both are clean today).
- **N1.** No change to `repair_plugin_node_paths`'s rewrite sequence (`-w`, `mktemp`, `cp -p`, `printf`, `mv -f`) or its rc contract (0/1/2).
- **N2.** No change to `run_setup_or_developer` or `run_update`'s `plugin-node` section.
- **N3.** A config tagged `unreadable` or `binary` is never written.
