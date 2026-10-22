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
   not scan. On macOS, BSD grep prints `Binary file <file> matches` on **stdout** (rc 0), so
   the binary case there yields a bogus pin line instead (round-1 Risk lens, measured on the
   Studio). The backlog row's proposed fix ("capture grep rc >= 2") covers only the first;
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

### 1. Tag any config the scan could not read cleanly

`_plugin_stale_node_paths` greps each config on its own, in the C locale, capturing stdout
and stderr together and the exit status:

```bash
_out="$(LC_ALL=C grep -oE '<pin regex>' "${_file}" 2>&1)"; _rc=$?
```

`LC_ALL=C` is load-bearing on macOS. Measured 2026-10-21 on the Studio (BSD grep 2.6.0,
`/usr/bin/grep`): a config whose pin line also holds one `\xff` byte gives `rc=1 out=[]`
under `en_US.UTF-8`, identical to "no match", and `rc=0` with the pin under `LC_ALL=C`. GNU
grep 3.12 prints the pin in every locale. The pin regex is ASCII, and both greps still flag a
NUL byte under `LC_ALL=C` (round-2 Goal-fit and Risk lenses).

Every line the pin regex can print starts with `/`. Two cases tag the file, and none of its
lines is used:

- `_rc` is 2 or more → `<file>\tunreadable` (GNU and BSD grep: permission denied, I/O
  error, file gone);
- otherwise, any output line does not start with `/` → `<file>\tnontext` (GNU grep's
  `grep: <file>: binary file matches` on stderr, BSD grep's `Binary file <file> matches` on
  stdout, any other diagnostic).

Otherwise the lines are the candidate pins, deduplicated and checked with `[[ -x ]]` as
today. rc 1 (no match) is a clean file. An empty `_out` must not be fed to the dedupe as a
line: `sort -u <<< ""` yields one empty line. The assignment and its `$?` stay on separate
statements from any `local` declaration, or `$?` is `local`'s.

Reading grep's own result catches the listed causes and unlisted ones (a file changed
between `find` and grep); an enumerated pre-check (`[[ -r ]]`, a `tr | cmp` NUL probe) was
refuted in round 1. No `grep -a`: the repair reads the file with `$(<file)`, which drops NUL
bytes, so a non-text config must be refused, never rewritten. No temp file is needed for
stderr, so the no-trap rule for `lib/helpers.sh` is untouched.

The two tags exist because their remedies differ. For a `nontext` file the remedy names the
plugin, taken from the cache-relative path `<marketplace>/<plugin>/<version>/…`; no command
is given, because no shell command repairs a config holding binary data, and
`claude plugins install` is not verified to replace an already-cached version (operator
choice, 2026-10-21).

Consumers:

- `repair_plugin_node_paths`: the file is not touched, `_failed=1`, `continue`, after
  printing
  - `unreadable`: `cannot repair <file>: cannot be read — run: chmod u+r <file>`;
  - `nontext`: `cannot repair <file>: contains non-text data — reinstall plugin <plugin>@<marketplace>`.

  rc stays 0/1/2.
- `_doctor_check_plugin_node_paths`: `doctor_fail "<file relative to the cache>"` with
  `cannot be read — run: chmod u+r <file>` or
  `contains non-text data — reinstall plugin <plugin>@<marketplace>`. A tagged config is a
  FAIL, so doctor never PASSes over a file it did not scan.
- In every `chmod` remedy, `<file>` is the absolute path, not doctor's cache-relative label,
  so a pasted command works from any directory.
- The two callers' summary warnings are reworded, the only change to them:
  - `run_update`'s `plugin-node` section:
    `plugin config(s) could not be checked or repaired — see detail`;
  - `run_setup_or_developer`:
    `plugin node paths: some configs could not be checked or repaired — see the 'cannot repair' lines above`.

### 2. Doctor names the cause-specific remedy

Extract the `_formula`/`_stable` derivation from `repair_plugin_node_paths` into
`_plugin_stable_node <node>`, which prints `<formula>\t<stable path>`. The repair and doctor
both call it (two callers).

For each stale pin doctor chooses, in this order:

- `opt/` link not executable → `pins missing <node> — run: brew install <formula>`;
- config not writable → `pins missing <node> — run: chmod u+w <file> && setup_env.sh -t update --brew-only`;
- otherwise → `pins missing <node> — run: setup_env.sh -t update --brew-only` (unchanged).

A full disk cannot be predicted from doctor; it keeps the generic remedy, and the repair's
own line names free space. A pin naming a versioned formula Homebrew has since disabled
would make `brew install` fail too; accepted, since a pin names the node binary that ran the
plugin and the fleet's node is the unversioned `node` formula.

### 3. Descend a symlinked cache root

`find "${_cache}/"` instead of `find "${_cache}"`. Measured 2026-10-21 on a temp fixture:
`find "<dir>/" -type f` prints `<dir>/p/f`, with no doubled slash, under GNU find on `claude`
and BSD find on the Studio, so doctor's `${_file#"${_cache}/"}` label is unchanged. Test 5
pins it.

## Testing

In `tests/setup_env/plugin_node_paths.bats`, under the existing `_OVERRIDE_CLAUDE_PLUGIN_CACHE`
setup seam:

1. An unreadable config (`chmod 000`, root-skip): finder emits `<file>\tunreadable`; repair
   returns 1 with the `cannot be read — run: chmod u+r` line and leaves the file
   byte-identical; doctor FAILs it and sets the failure flag; no `[PASS]` line.
2. A config with a NUL byte holding a stale pin, in a fixture whose marketplace and plugin
   names differ (`mkt/plg/1.0.0`): finder emits `<file>\tnontext` and not the pin; repair
   returns 1 with `reinstall plugin plg@mkt`, which a swapped derivation would fail, and leaves the file byte-identical (`cmp` against a saved copy);
   doctor FAILs it.
3. A config whose stale pin is preceded on the same line by one `\xff` byte, placed
   between the opening `"` and the pin path (`"\377/…/Cellar/node/<v>/bin/node"`), no NUL,
   with the test's `LC_ALL` set to `en_US.UTF-8`: the file is not tagged and the pin is
   reported. The byte position is load-bearing: measured on the Studio, a `\xff` as the last
   byte before `\n`, or on another line, still prints the pin under BSD grep in a UTF-8
   locale, so a fixture placed there passes without the fix. The test first asserts
   `locale -a` lists `en_US.UTF-8` and fails if not, because a missing locale silently falls
   back to C and makes the case vacuous. It discriminates only on the macOS CI leg (BSD
   `/usr/bin/grep`); GNU grep prints the pin in every locale and placement, so on Linux it is
   a regression guard only.
4. A readable sibling config in the same cache is still reported and repaired (one bad file
   does not stop the scan).
5. Doctor remedy, one test each: missing `opt/` link → `run: brew install node`; read-only
   config with the `opt/` link present → `run: chmod u+w <file> && setup_env.sh -t update --brew-only`;
   writable config with the link present → `run: setup_env.sh -t update --brew-only`.
6. A cache root that is a symlink to a directory holding a stale pin: the finder reports it;
   doctor's label is the path relative to the cache, with no doubled slash.
7. The two reworded summary warnings: the existing `-t update` and
   `run_setup_or_developer` rc-1 tests assert the new text.
8. Existing tests keep passing; "ignores a bare node interpreter" and the PASS test guard the
   empty-`_out` dedupe trap.

## Requirements

- **R1.** `_plugin_stale_node_paths` emits `<file>\tunreadable` when grep on the file exits 2 or more, else `<file>\tnontext` when grep prints any line that does not start with `/`, and emits none of a tagged file's pins.
- **R2.** `_plugin_stale_node_paths` runs the per-file grep as `LC_ALL=C grep -oE`, captures its stdout and stderr together without a temp file or trap, and does not use `grep -a`.
- **R3.** For a tagged line, `repair_plugin_node_paths` leaves the file unchanged, returns 1, and prints `cannot repair <file>: cannot be read — run: chmod u+r <file>` (`unreadable`) or `cannot repair <file>: contains non-text data — reinstall plugin <plugin>@<marketplace>` (`nontext`), with plugin and marketplace taken from the cache-relative path.
- **R4.** For a tagged line, `_doctor_check_plugin_node_paths` calls `doctor_fail` with `cannot be read — run: chmod u+r <file>` or `contains non-text data — reinstall plugin <plugin>@<marketplace>`, and does not print `no plugin pins a missing node binary`.
- **R5.** `_plugin_stable_node <node>` prints `<formula>\t<stable path>`, and both `repair_plugin_node_paths` and `_doctor_check_plugin_node_paths` use it.
- **R6.** For a stale pin, doctor's remedy is `run: brew install <formula>` when the `opt/` node is not executable, else `run: chmod u+w <file> && setup_env.sh -t update --brew-only` when the config is not writable, else `run: setup_env.sh -t update --brew-only`.
- **R7.** `_plugin_stale_node_paths` passes `"${_cache}/"` to `find`, so a symlinked cache root is descended.
- **R8.** `run_update`'s `plugin-node` warning reads `plugin config(s) could not be checked or repaired — see detail`, and `run_setup_or_developer`'s reads `plugin node paths: some configs could not be checked or repaired — see the 'cannot repair' lines above`.
- **V1.** `make test` exits 0 and CI is green, including `bash-coverage` at or above 91%.
- **V2.** On `claude`, `workstation` and the Studio, `./setup_env.sh -t doctor` prints the literal `[PASS] no plugin pins a missing node binary` line before and after the change, recorded beside the count of configs the finder scanned there (`find <cache>/ -type f \( -path '*/hooks/hooks.json' -o -path '*/.claude-plugin/plugin.json' \) | wc -l`).
- **N1.** No change to `repair_plugin_node_paths`'s rewrite sequence (`-w`, `mktemp`, `cp -p`, `printf`, `mv -f`) or its rc contract (0/1/2).
- **N2.** No change to `run_setup_or_developer` or `run_update`'s `plugin-node` section beyond the two warning strings in R8.
- **N3.** A config tagged `unreadable` or `nontext` is never written.

## Multi-Lens Review

Reviewed at commit: `8c4e1119` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Item 2 carries the real value; items 1 and 3 are accepted operator scope. Item 1 over-builds and still leaks: the `unreadable` and `binary` tags reach every consumer as the same text (R3, R4), so the split changes no decision, while the grep inside `< <(grep … | sort -u)` keeps discarding its own rc and stderr. Any failure the pre-checks did not enumerate (a file changed between `find` and grep) still yields an empty, clean result. Simpler: grep each file with stderr captured and tag it unread on rc >= 2 or non-empty stderr; one tag, no `tr`/`cmp`, no locale reasoning. `LC_ALL=C` (R2) defends nothing reproducible: GNU grep 3.12 under `en_US.UTF-8` matched a pin in a file with a lone `\xff`, rc 0, no stderr. V2 is the only PASS-expecting case and passes on an empty finder.
Assumption: R6's `run: brew install <formula>` assumes the pinned formula is still installable. A pin naming a disabled versioned formula (`node@18`) would move the dead end, not remove it. Open because `claude`'s cache holds no Cellar pins today; settle by reading where context-mode records `process.execPath` (mksglu/context-mode#1090) and `brew info --json=v2 <formula> | jq '.formulae[0].disabled'`.
Disposition: Addressed — one `unread` tag from grep's own rc and output replaces the two enumerated tags and `tr`/`cmp`; R2's `LC_ALL=C` dropped; V2 now asserts the literal PASS line. Assumption accepted, operator 2026-10-21: a pin names the node binary that ran the plugin, and the fleet's node is the unversioned `node` formula.

### Ergonomics

Finding: the new unread FAIL/WARN has no pasteable remedy ("check its permissions and contents"), against the operator's paste-one-remedy-then-rerun workflow, so it fires on every doctor, update and setup run until tuned out, which then hides the real stale-pin case. R6's "check write permission on <file>" has the same defect; `helpers.sh` already uses a pasteable `ls -l` remedy elsewhere. The cache path encodes `<marketplace>/<plugin>/<version>`, so a reinstall command is derivable. N2 freezes two summary strings that become wrong for an unread file with no pin: `-t update`'s "stale node path(s) could not be repaired" and setup's "some pins could not be repaired". V2 passes vacuously; it should assert the literal `[PASS] no plugin pins a missing node binary` line.
Assumption: that FAIL is the right severity for "config not scanned", i.e. the operator acts on such a line rather than tuning it out. Settled by asking the operator; if a FAIL with no pasteable remedy gets ignored, the remedy must be a command or the severity `doctor_warn`.
Disposition: Addressed — remedies for an unread or non-writable config are the pasteable `run: ls -l <file>`, still a doctor FAIL (operator chose FAIL over WARN); N2 relaxed so R8 rewords the two summary warnings; V2 asserts the literal PASS line.

### Risk

Finding: the NUL detector is not portable. With `LC_ALL=C` on grep only, BSD `tr` on the Studio in `en_US.UTF-8` aborts on an invalid byte: a no-NUL file holding one `\xff` gave `tr: Illegal byte sequence`, rc 1, so `tr | cmp -s` reports "has NUL" and the file is tagged `binary` on macOS only (GNU `tr` on `claude` returned 0). Fail-closed, so nothing is corrupted, but test 2 (a NUL fixture) would not catch it. Separately, the problem statement is Linux-only: BSD `/usr/bin/grep -oE` prints `Binary file nul.json matches` on **stdout**, rc 0, so on macOS today the binary case yields a bogus pin line, not a false PASS. 0 of 131 Studio configs are affected.
Assumption: that `tr -d '\000' | cmp -s` answers only "is there a NUL?" on every platform. Refuted on macOS by the probe above.
Disposition: Addressed — the NUL probe is gone; an unread file is detected from grep's own output, which catches BSD's stdout `Binary file … matches` too; test 3 pins that a lone `\xff` byte is not tagged, on both CI legs; problem statement corrected for BSD.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2

Reviewed at commit: `d3953898` (all three lenses, design substance changed in round 1).

#### Goal-Fit

Finding: macOS false-clean survives the revision. BSD grep under `en_US.UTF-8` returns `rc=1 out=[]` for a pin line holding one `\xff` byte, so the file reads as clean; `LC_ALL=C` restores the pin. Reproduced by the orchestrator on the Studio. Test 3 as written could pass or fail depending on runner locale and byte placement.
Assumption: that grep's rc plus first character separates "scanned clean" from "not scanned" in the operator's real locale. Refuted for BSD under `en_US.UTF-8`; holds under `LC_ALL=C`.
Disposition: Addressed — R2 adds `LC_ALL=C`; test 3 puts the byte on the pin's line under a UTF-8 locale.

#### Ergonomics

Finding: `run: ls -l <file>` only inspects; pasted and re-run, doctor shows the same FAIL, against the paste-then-rerun loop. V2's PASS is also what an empty scan prints; pair it with the scanned-config count (132 on `claude`, 78 on `workstation`).
Assumption: that a non-writable plugin config is an accident, not a deliberate pin. 0 of 132 on `claude` are non-writable.
Disposition: Addressed — remedies change state (`chmod u+r`, `chmod u+w … && setup_env.sh -t update --brew-only`); non-text data names the plugin to reinstall without a command (operator chose A, 2026-10-21); V2 records the config count. Assumption accepted: a stale pin in a read-only config breaks its hook whether or not the mode was deliberate, so FAIL is right.

#### Risk

Finding: No issues. GNU grep 3.12 and BSD grep 2.6.0 under C, `en_US.UTF-8` and `C.UTF-8`: clean, no-pin and lone-`\xff` files give empty stderr and `/`-prefixed lines; NUL is caught by the not-`/` rule on both. Real caches: 132 (`claude`), 131 (Studio), 78 (`workstation`), 0 tagged; `workstation` has 2 live pins, so V2 is not vacuous there. Implementation traps: `sort -u <<< ""` yields one empty line; `local _out=$(…)` loses grep's rc.
Assumption: no uncertain assumption found; weakest is that `test-macos` resolves BSD `/usr/bin/grep` (ci.yml adds no gnubin).
Disposition: N/A — clean; both traps recorded in Design §1.

### Round 3 (scoped Risk re-review of §1, §2's R6 remedy, Testing, R1–R4, R6, V2)

Reviewed at commit: `b31da998`.

Finding: test 3 could pass without the fix: under BSD grep in a UTF-8 locale a `\xff` before or inside the match drops the pin, but one as the last byte before `\n` or on another line does not, and the spec did not fix the position; a missing locale also falls back to C silently. Test 2's `ctx/ctx` fixture cannot catch a swapped `<plugin>@<marketplace>` derivation. The `chmod` remedies must name the absolute path, since doctor's label is cache-relative. Clean probes: real cache depth (131 configs at depth 5, one at depth 7, components 1/2 always marketplace/plugin); `LC_ALL=C` still flags NUL and rc-2 files on both greps; bare `setup_env.sh` matches existing remedies; no rc-2-with-pins case.
Assumption: that `macos-latest`'s `/usr/bin/grep` drops a match after an invalid byte as the Studio's 2.6.0-FreeBSD does; if not, test 3 guards nothing in CI. Settled by the first test-macos run of test 3 against the pre-fix code (Phase 2 RED step).
Disposition: (pending operator) proposed Addressed — test 3 fixes the byte position and asserts the locale exists; test 2 uses `mkt/plg/1.0.0`; §1 states `<file>` in `chmod` remedies is absolute. Findings have moved from design to test apparatus, so review stops here. Assumption to be checked by Phase 2's RED run on the macOS leg.

