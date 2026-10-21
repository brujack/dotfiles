# doctor: report dangling Homebrew links and unlinked kegs

- **Date:** 2026-10-20
- **Status:** Draft (Phase 1)
- **Trigger:** backlog P1 "nothing reports dangling Homebrew links or unlinked kegs". On
  2026-10-04 on the Studio, `-t update --brew-only` left 5 dangling `/opt/homebrew/opt` links
  and an unlinked `uv` keg, and no update section or `doctor` check named them.

## Problem

The backlog row makes two claims. They were checked separately on 2026-10-20.

**"Nothing reports it": true.** `run_doctor` (`lib/helpers.sh:481`) calls 20 checks. None of
them reads Homebrew's link state. `git grep -nE 'brew doctor|dangling|unlinked'` over `lib/`,
`setup_env.sh` and `scripts/` finds only comments about unrelated symlinks. No spec or ADR in
dotfiles or ai-config proposes such a check.

**"It happens": not at present.** These readings were taken on 2026-10-20. Each covers one
machine's live prefix.

- Studio: `find -L /opt/homebrew/opt -maxdepth 1 -type l` returned 0 entries.
- Studio: `uv` is linked (`/opt/homebrew/opt/uv -> ../Cellar/uv/0.13.3`).
- Studio: `brew doctor check_for_broken_symlinks check_for_unlinked_but_not_keg_only`
  printed `Your system is ready to brew.` with rc 0, in 5 s.
- `claude`: the same `find` over `/home/linuxbrew/.linuxbrew/opt` returned 0 entries.

The 2026-10-04 reading is the only time the hazard has been observed. Nothing says how often
it happens.

**Mechanism: the links broke after cleanup.** This is derived from Homebrew's source. The
2026-10-04 transcript is not retained, so it was not observed directly.

- **Cleanup prunes.** `brew cleanup` with no arguments prunes every broken symlink under the
  prefix link directories, `opt` included.
  - The routine is `prune_prefix_symlinks_and_directories` (`Library/Homebrew/cleanup.rb:977`).
    It walks `Keg.must_exist_subdirectories` (`keg.rb:155`: the keg link dirs plus `opt` and
    `var/homebrew/linked`).
  - It runs last in `clean!`, after formula cleanup and autoremove (`cleanup.rb:448-482`). So a
    link that cleanup's own removals break is pruned in the same pass.
- **The test for "broken".** It is `Utils::Path.resolved_path_exists?`, defined only at
  `utils/path.rb:89`: `path.dirname.join(path.readlink).exist?`. `exist?` follows the whole link
  chain, which is effectively the test `find -L` makes. Its last change was 2026-09-05, before the
  incident.
- **Cleanup ran on 2026-10-04.** dotfiles#315's body records that run summarizing `[OK] brew`
  with 7 cask failures. Before #315, a cask failure did not abort `brew_update`, so the final
  `brew cleanup` ran and exited 0.

The conclusion: the 5 `opt` links that survived were not broken when cleanup's prune ran. They
broke later in that run, or afterwards. `check_for_broken_symlinks` applies the same walk and the
same test at the moment doctor runs. So a `-t doctor` run after the breakage reports them, and
`brew cleanup --prune-prefix` removes them.

Which later step broke them is not established. It does not change this design.

An unlinked keg means a link step failed partway through an upgrade. Cleanup does not relink, so
cleanup never repairs that case.

The gap is detection. A degraded prefix stays silent until a tool fails to run, and on
2026-10-04 the update summary said `[OK]` over it.

## Design

### Upstream check, not a reimplementation

Homebrew already checks both conditions (`Library/Homebrew/diagnostic.rb`).

- `check_for_broken_symlinks` (`:451`) walks the same `Keg.must_exist_subdirectories` that
  cleanup prunes, with the same `resolved_path_exists?` test.
- `check_for_unlinked_but_not_keg_only` (`:1194`) lists every Cellar rack that has no
  `var/homebrew/linked` entry and is not keg-only. It rescues `UntrustedTapError` as keg-only
  (`:1200`), so a keg from an untrusted tap is never reported. That limit is Homebrew's, and
  this check inherits it.

`brew doctor <check> <check>` runs only the named checks (`cmd/doctor.rb:55`), and
`brew doctor --list-checks` lists both names. An unknown name gives rc 1 with
`Error: No check available by the name: …`. dotfiles calls this command and does not walk the
prefix itself.

A hidden `brew doctor --json` (added 2026-07-17) is not used. Being hidden, it is no more of a
contract than the text, and it gives broken-symlink paths only inside message text.

**What a probe can still write.** `brew doctor` does not change link state, but it is not
side-effect free:

- **API cache.** `brew.rb:139-141` runs `Homebrew::API.fetch_api_files!` before every Ruby
  command. It downloads when the cache under `HOME` is missing or older than 7 days
  (`api.rb:236-245`).
  - Measured 2026-10-20 on `claude`, with a fresh temp `HOME` under `env -i`: rc 0 in 3.2 s,
    37 MB written under that `HOME`.
- **Portable Ruby.** Every `brew` call re-pours portable Ruby into the prefix when
  `vendor/portable-ruby/current` does not match the pin (`utils/ruby.sh:136-139`).
  - Measured 2026-10-20 on `claude`: re-poured 4.0.7_1 from cache.

The probe sets `HOMEBREW_NO_AUTO_UPDATE=1`. That stops a refresh of an existing cache, but
neither write above can be switched off. `HOMEBREW_NO_INSTALL_FROM_API` must not be set: with
no local core tap, `diagnostic.rb:1202` maps `FormulaUnavailableError` to "not keg-only", so
every keg-only rack would read as unlinked.

Both writes are accepted. They are what any interactive `brew` command does. A `timeout` kill
during a pour is the one harmful case, and the 60 s bound sits well above the 6 s worst measured
run.

### Unit

`_doctor_check_brew_links` goes in `lib/helpers.sh`. `run_doctor` calls it directly after
`_doctor_check_gnu_coreutils`. It prints a `Homebrew links:` header.

**Brew resolution, first hit wins:**

1. `_BREW_BIN`, the test seam and operator override.
2. `command -v brew`.
3. The entries of `_BREW_FALLBACK_PATHS`, in order. The default is `/opt/homebrew/bin/brew`,
   then `/usr/local/bin/brew`, then `/home/linuxbrew/.linuxbrew/bin/brew`.

The fixed paths matter because `-t doctor` bypasses the brew prereq and can run over `ssh`, cron
or launchd. linuxbrew's `PATH` entry exists only in interactive zsh (`CLAUDE.md`, Linux
workstation brew PATH).

A `_BREW_BIN` that is set but not executable prints a WARN that names it. It never falls through
to resolution, because an override the operator named must not be silently replaced. When no
candidate resolves, the check prints `  brew not found — skipped` and changes no counter.

**Timeout resolution, first hit wins:**

1. `command -v timeout`.
2. The entries of `_TIMEOUT_FALLBACK_PATHS`, in order. The default is
   `/opt/homebrew/bin/gtimeout`, then `/usr/local/bin/gtimeout`.

Measured 2026-10-20 over `ssh studio`:

- `command -v timeout` prints nothing, and `/usr/bin/timeout` is absent.
- `/opt/homebrew/bin/gtimeout` exists. It is GNU coreutils 9.12 with the same arguments, and
  `gtimeout 1 sleep 3` gives rc 124.

Without the fallback, the bound would be missing in exactly the contexts the brew fallbacks
exist for.

**Probe:**

```bash
local _out _rc
if [[ -n "${_timeout_bin}" ]]; then
  _out="$(HOMEBREW_NO_AUTO_UPDATE=1 "${_timeout_bin}" "${_DOCTOR_BREW_TIMEOUT:-60}" \
    "${_brew}" doctor --quiet check_for_broken_symlinks check_for_unlinked_but_not_keg_only \
    </dev/null 2>&1)"
else
  _out="$(HOMEBREW_NO_AUTO_UPDATE=1 "${_brew}" doctor --quiet \
    check_for_broken_symlinks check_for_unlinked_but_not_keg_only </dev/null 2>&1)"
fi
_rc=$?
```

- Declare `_out` and `_rc` before the assignment. Never write `local _out="$(…)"`: `local`'s own
  status replaces the command's and `_rc` reads 0. Measured in bash: the form above captures
  rc 124 and rc 3, and the `local` form captures 0.
- `--quiet` drops the "Please note that these warnings are just used to help the Homebrew
  maintainers…" preamble that `cmd/doctor.rb` prints before the first finding
  (`if first_warning && !args.quiet?`). It also drops the "ready" line, which does not matter:
  the verdict comes from the rc. Findings still print.
- stdout and stderr go to one variable. Findings arrive on stderr as `Warning: …`.
- When no `timeout` resolves, the probe runs unbounded. This is the same accepted degrade
  `_doctor_check_dev_tools` documents, and its `[[ -n ]]` branch is the model here.
- The bound is a separate `_DOCTOR_BREW_TIMEOUT` with a 60 s default. It is not
  `_DOCTOR_PROBE_TIMEOUT`, whose 10 s default belongs to the dev-tools arm, so tuning one never
  retunes the other. The probe measured 1.4-1.9 s on `claude`, 5.3-6 s on the Studio, and 3.2 s
  on `claude` with a cold API cache.

**Parsing.**

- Lines starting with `==>` or `✔` are progress output (the API download, a Ruby pour) and are
  skipped everywhere.
- **Broken symlinks.** The header is a line containing `Broken symlinks were found`. Its entries
  are the indented lines that follow, up to the next blank or unindented line. `append_indented_list`
  (`diagnostic.rb:86`) renders each as `  <path>`, and a blank line and
  ``Remove them with `brew cleanup` `` follow the list.
- **Unlinked kegs.** The header is a line containing `You have unlinked kegs in your Cellar`.
  Homebrew prints two unindented explanation lines after it, then ``Run `brew link` on these:``,
  then the indented kegs (`diagnostic.rb:1209-1218`). So the keg list is anchored on the
  ``Run `brew link` on these:`` line, not on the header.
- Colour wraps only `Warning:`, so a "contains" header match survives it.

**Verdicts.** Every verdict is one line, in the compact shape `_doctor_check_pyenv_shims` already
uses (`lib/helpers.sh:1378`, `missing: N entries (a, b…) — run: pyenv rehash`). `doctor_warn`
prints a single line, so no detail carries a newline.

| Probe result | Verdict | Detail |
| --- | --- | --- |
| rc 0 | `doctor_pass "brew links"` | none |
| rc 1, broken-symlinks header present | one `doctor_warn "brew links"` | `broken symlinks: <N> (<path>, <path>…) — run: brew cleanup --prune-prefix` |
| rc 1, unlinked-kegs header present | one `doctor_warn "brew links"` | `unlinked kegs: <N> (<keg>, <keg>…) — run: brew link <every keg>` |
| rc 1, neither header | `doctor_warn "brew links"` | `brew doctor rc 1:` plus the first line starting `Warning:` or `Error:`, else the first non-progress, non-empty line |
| rc 124 with a timeout resolved | `doctor_warn "brew links"` | `brew doctor did not finish in <N>s` |
| any other rc | `doctor_warn "brew links"` | `brew doctor rc <N>:` plus the last non-progress, non-empty line |

When both headers are present, each produces its own WARN, so there are 2. The names shown in
parentheses are capped at 10, ending with `… <M> more` past that.

The `brew link` command names every keg, not just the 10 shown. `brew link` takes several
formulae in one call, so it is one paste however many kegs there are. A conflicting link makes
`brew link` fail with its own message naming `--overwrite`, and the check does not repeat it.

`brew cleanup --prune-prefix` deletes no kegs, caches or logs. It does remove every broken link,
every empty directory (and every directory holding only `.DS_Store`, `utils/path.rb:64-73`) under
the prune directories, and broken `Caskroom` links (`cleanup.rb:977-1027`). That is the same prune
a bare `brew cleanup` runs on every `-t update`, so recommending it adds no new kind of deletion.

Findings are WARN, not FAIL:

- Homebrew itself reports them as warnings.
- The two remedies clear them without a dotfiles run.
- A FAIL would change `-t doctor`'s exit code for prefix housekeeping.

An rc 1 the parser does not recognise still warns and never passes. Unrecognised output fails
closed. Trusting rc 0 is right, because `cmd/doctor.rb:72` sets `Homebrew.failed` for any finding.

### Fixtures

Stub outputs are not typed by hand. V1 captures them from the real probe on the Studio, run bare
with the probe's own argv (`brew doctor --quiet <the two checks> 2>&1`), never through
`-t doctor`, whose rendering is not raw.

- `tests/fixtures/brew/doctor-broken-symlinks.txt` is captured with one planted dangling link.
- `tests/fixtures/brew/doctor-unlinked-kegs.txt` is captured with one keg unlinked.

Both captures change the Studio's live prefix for the length of one bare probe. They need the
operator's "yes" before they run.

### Tests

`tests/helpers/common.bash` `load_mocks` exports two things at setup scope (tdd-009). This is the
same pattern as `_BREW_AZ_BIN` and `_CARGO_BIN`.

- **`_BREW_BIN`** points to a recording stub that prints nothing and exits 0. The stub logs its
  argv under `BATS_TEST_TMPDIR`, never through a `${MOCK_CALLS_FILE:-/tmp/mock_calls}` fallback.
- **`_BREW_FALLBACK_PATHS`** is set to `"${BATS_TEST_TMPDIR:-/nonexistent}/no-brew"`.

Both are `export`, not plain assignment. Three existing tests reach the check through a
subprocess and depend on the exported values: `unit.bats:555` and `:1472` run
`bash setup_env.sh -t doctor`, and `:1960` runs an unstubbed `run_doctor` on the unmocked `PATH`.

What this guarantees:

- No `run_doctor` test reaches `tests/mocks/brew`'s `*)` arm.
- No test reaches a real brew through `command -v` or through a fallback path. Every machine the
  suite runs on has a real brew at a default fallback path: `claude`, GitHub's ubuntu image (off
  `PATH`) and the macOS runner.
- With `BATS_TEST_TMPDIR` empty, the stub path becomes `/nonexistent/…`. R4 then gives a WARN,
  which fails closed.

No existing count assertion changes. The `run_doctor` asserts count fails and warnings, never
passes.

`tests/setup_env/doctor_brew_links.bats` points `_BREW_BIN` at a per-test stub in
`BATS_TEST_TMPDIR`. The stub prints a fixture, exits with a chosen rc, and appends its argv to a
call log.

- **Brew absent everywhere.** Unset `_BREW_BIN`, set `_BREW_FALLBACK_PATHS` to a missing path, and
  run the check under a scoped `PATH`: a private directory of `#!/bin/bash` stubs for the commands
  the check needs, with no `brew`. This is the mechanism the dev-tools timeout tests use; the
  inherited `PATH` is never edited. Result: the skip line, and pass, warn and fail unchanged.
- **`command -v` wins.** `_BREW_BIN` unset, a brew stub on the scoped `PATH`, and the fallback list
  pointing at a second stub. Only the `PATH` stub's log records a call.
- **Fallback used.** `_BREW_BIN` unset, no brew on the scoped `PATH`, and `_BREW_FALLBACK_PATHS`
  listing a missing path then a stub. The stub's log records the call.
- **`_BREW_BIN` not executable.** WARN naming the path, and the call log stays empty.
- **rc 0.** One PASS, and the call log holds exactly one call whose argv is
  `doctor --quiet check_for_broken_symlinks check_for_unlinked_but_not_keg_only`.
- **Broken-symlinks fixture, rc 1.** One WARN line containing the fixture's path and
  `brew cleanup --prune-prefix`.
- **Unlinked-keg fixture, rc 1.** One WARN line containing the fixture's keg and
  `brew link <that keg>`.
- **Both fixtures concatenated, rc 1.** Exactly 2 WARN lines.
- **Progress lines.** A fixture prefixed with captured `==> Downloading Homebrew API data` and
  `✔︎ JSON API …` lines, rc 1: the same WARN as without them.
- **Unrecognised output, rc 1.** Output whose first line is progress and whose second is
  `Warning: Something new`: one WARN whose detail is `brew doctor rc 1: Warning: Something new`.
  PASS is unchanged.
- **Timeout.** A stub that sleeps, under `_DOCTOR_BREW_TIMEOUT=1` with a resolved timeout: WARN
  containing `did not finish`.
- **No timeout.** Scoped `PATH` without `timeout`, and `_TIMEOUT_FALLBACK_PATHS` set to a missing
  path. The stub still runs, the verdict is PASS, and nothing reports rc 127.
- **Timeout via fallback.** Scoped `PATH` without `timeout`, and `_TIMEOUT_FALLBACK_PATHS` pointing
  at a recording wrapper for the real `timeout`. The wrapper's log shows it was called with the
  bound. The real `timeout` is located as `doctor_dev_tools.bats:45-48` does, and the test skips
  when there is none; on macOS, `timeout` may exist only under gnubin.
- **rc 3.** WARN containing `rc 3`.
- **12 paths.** 10 names shown and `… 2 more`.
- **12 kegs.** 10 names shown and `… 2 more`, and the `brew link` command names all 12.
- **`run_doctor`.** It calls `_doctor_check_brew_links`. Run `run_doctor` with the check stubbed to
  record a call.

The new seams `_BREW_BIN`, `_BREW_FALLBACK_PATHS`, `_TIMEOUT_FALLBACK_PATHS` and
`_DOCTOR_BREW_TIMEOUT` get rows in `ai-config/docs/knowledge/dotfiles-test-seams.md`, and a
one-line rule in `CLAUDE.md` Test Seams, in the same change.

## Requirements

- **R1.** `[PR1]` `run_doctor` calls `_doctor_check_brew_links` directly after `_doctor_check_gnu_coreutils`.
- **R2.** `[PR1]` The probe runs `brew doctor --quiet check_for_broken_symlinks check_for_unlinked_but_not_keg_only` with `HOMEBREW_NO_AUTO_UPDATE=1` and stdin from `/dev/null`, and never sets `HOMEBREW_NO_INSTALL_FROM_API`.
- **R3.** `[PR1]` Brew resolves from `_BREW_BIN`, then `command -v brew`, then `_BREW_FALLBACK_PATHS` (default `/opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew`), first hit wins, and a test covers each of the three sources winning.
- **R4.** `[PR1]` A set but non-executable `_BREW_BIN` produces a WARN naming it and the probe does not run.
- **R5.** `[PR1]` With no brew resolvable, the check prints `brew not found — skipped` and changes no doctor counter.
- **R6.** `[PR1]` Timeout resolves from `command -v timeout`, then `_TIMEOUT_FALLBACK_PATHS` (default `/opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout`); when one resolves the probe is bounded by `_DOCTOR_BREW_TIMEOUT` (default 60 s), and when none resolves the probe runs unbounded and its rc is judged as if no timeout were involved.
- **R7.** `[PR1]` rc 0 produces exactly one PASS labelled `brew links`.
- **R8.** `[PR1]` rc 1 produces one single-line WARN per recognised finding, showing the count and at most 10 names plus `… <M> more`; the broken-symlinks WARN ends `run: brew cleanup --prune-prefix` and the unlinked-kegs WARN ends `run: brew link` followed by every unlinked keg name.
- **R9.** `[PR1]` The unlinked-keg list is read from the indented lines after ``Run `brew link` on these:``, and lines starting with `==>` or `✔` are never parsed as entries or used as detail.
- **R10.** `[PR1]` rc 1 with no recognised finding, rc 124 with a resolved timeout, and any other non-zero rc each produce a WARN and never a PASS; the rc 1 detail is the first `Warning:` or `Error:` line when one exists.
- **R11.** `[PR1]` No outcome of this check calls `doctor_fail`.
- **R12.** `[PR1]` `load_mocks` exports `_BREW_BIN` to a recording stub that exits 0 and logs under `BATS_TEST_TMPDIR`, and exports `_BREW_FALLBACK_PATHS` to a missing path under `BATS_TEST_TMPDIR`.
- **R13.** `[PR1]` Test fixtures for the two findings are files under `tests/fixtures/brew/` captured from the bare real probe in V1 with R2's argv.
- **R14.** `[PR1]` `_BREW_BIN`, `_BREW_FALLBACK_PATHS`, `_TIMEOUT_FALLBACK_PATHS` and `_DOCTOR_BREW_TIMEOUT` are documented in `dotfiles-test-seams.md` and as a one-line rule in `CLAUDE.md` Test Seams.
- **V1.** On the Studio, with the operator's "yes" before each step: (a) Immediately before, confirm `find -L /opt/homebrew/opt -maxdepth 1 -type l` returns 0. Plant `ln -s /nonexistent /opt/homebrew/opt/zz-doctor-probe`, run the bare probe with R2's argv and save its output as the broken-symlinks fixture, then `rm` the link and confirm the `find` returns 0 again. (b) Choose a `<keg>` that is not keg-only and for which `brew uses --installed <keg>` prints nothing. Run `brew unlink <keg>`, run the bare probe and save its output as the unlinked-kegs fixture, then run `brew link <keg>`; confirm `brew link` exits 0 and `/opt/homebrew/var/homebrew/linked/<keg>` exists. (c) Once the branch is built, plant the link again, run `./setup_env.sh -t doctor` once, confirm the single-line WARN shows the path and `brew cleanup --prune-prefix`, then `rm` the link and confirm the `find` returns 0.
- **V2.** On the Studio and on `claude`, the merged check on the real, clean prefix prints PASS for `brew links`.
- **V3.** On `claude`, `env -i HOME="${HOME}" PATH=/usr/bin:/bin bash ./setup_env.sh -t doctor` (brew not on `PATH`, as for ssh, cron and launchd) still finds linuxbrew through the fallback paths and prints PASS rather than the skip line.
- **N1.** `brew_update` and every `-t update` section are unchanged.
- **N2.** The check never runs a command that changes link state (`brew cleanup`, `brew link`, `brew unlink`, `ln`, `rm`); the API cache and portable-Ruby writes that every `brew` command makes are accepted.
- **N3.** No new line in the `-t update` summary.
- **N4.** The check does not walk the prefix itself; Homebrew's two named checks are the only detector.

## Multi-Lens Review

Reviewed at commit: `c631baab` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding:

1. The "Likely mechanism" paragraph contradicts the only recorded incident. dotfiles#315's body
   records the 2026-10-04 Studio run summarizing `[OK] brew` with 7 cask failures. Before #315,
   a cask failure did not abort `brew_update`, so `brew cleanup` ran and exited 0, and 5 dangling
   `opt` links survived it anyway. So "survivors imply a hard failure" is unsupported, and
   `run: brew cleanup` may not be the right remedy.
2. The Probe snippet runs `"${_timeout_bin}"` unconditionally. With `timeout` absent that is
   `"" 60 brew …` and rc 127: a WARN on every stock-macOS ssh, cron or launchd run.
   `_doctor_check_dev_tools` branches on `[[ -n "${_timeout_bin}" ]]`. No test covers that path.
3. Under `load_mocks`, `command -v brew` resolves to `tests/mocks/brew`, whose `*)` arm exits
   `MOCK_BREW_EXIT:-0`. Every end-to-end `run_doctor` test silently gains a PASS, and tests that
   set `MOCK_BREW_EXIT` gain a WARN (`tests/setup_env/unit.bats:1055`, `:2969` assert counts).
   `load_mocks` should export `_BREW_BIN` to a stub, as it does for `_BREW_AZ_BIN`.
4. Reads-it test passes narrowly. The only consumer is the operator reading interactive
   `-t doctor`. The output changes a decision (run cleanup or link) but persists nowhere, and the
   hazard is born in `-t update`, which N1 and N3 keep it out of. This is a conscious choice, not
   a defect.
5. Verdict count is adequate: one PASS case (rc 0, where Homebrew's rc is the authority), and
   the fixture tests assert a named path or keg, so an empty parser goes red.

Assumption: `brew cleanup` clears the dangling `opt` links this check reports. The 10-04 record
suggests a cleanup that exited 0 left 5. Settle it in V1 with the operator's "yes": plant the
link, run the remedy, re-run the probe. The 10-04 transcript is not retained: on the Studio,
`~/.local/share/dotfiles/` holds only `cadence`, `renovate-held` and `venv-snapshots`, and no
`err_brew*`, `detail_brew*` or update log dated 2026-10-03 to 2026-10-06 exists under `~`
(searched 2026-10-20).

Disposition: Addressed (1-3), Accepted (4). Operator 2026-10-20: "I accept". 1: mechanism paragraph rewritten as unknown, V1(b) now tests the remedy. 2: probe branches on a resolved timeout, with a no-timeout test. 3: `load_mocks` exports `_BREW_BIN` (R12). 4, accepted: the operator chose doctor-only reporting. 5: no action.

### Ergonomics

Finding:

1. N2 is false as written. Every `brew` call, `doctor` included, runs `brew vendor-install ruby`
   when `vendor/portable-ruby/current` does not match the pin (`utils/ruby.sh:136-139`). This
   was triggered on `claude` under `env -i`: it re-poured portable-ruby 4.0.7_1 from cache. On a
   cold cache it would be a network download. A `timeout` kill mid-pour could leave `brew` broken.
   The `==>` lines it prints would become the "first non-empty line" detail.
2. Remedies:
   - `brew cleanup` deletes old kegs and caches. `brew cleanup --prune-prefix` does only the
     symlink prune (`cleanup.rb:977`).
   - `brew link <keg>` must print the real keg name, one line per keg.
   - A conflicting link needs `--overwrite`, or can be left to `brew link`'s own error.
3. Over ssh to the Studio, `command -v timeout` prints nothing. The gnubin `timeout` exists but is
   not on that `PATH`. So the bound is absent in exactly the contexts that motivate the fallback
   brew paths.
4. V1 holds the planted link in the live prefix for a whole `-t doctor` run. Capture with the bare
   probe, then run doctor once for rendering.
5. The rc-0 PASS case passes with an empty stub that never ran. Assert the stub was called in that
   same case.
6. Minor: `_DOCTOR_PROBE_TIMEOUT` would carry two defaults (10 for dev-tools, 60 here).

Measured: probe rc 0 in 1.9 s on `claude` and 6 s on the Studio. 23 keg-only racks on the Studio
raise no WARN.

Assumption: that probe output in non-interactive contexts is only the two checks' text, with no
side effects, inside the timeout. The portable-ruby pour shows it can go either way. How often it
happens after a `brew update` bumps the pin is unknown. Confirm by comparing
`readlink vendor/portable-ruby/current` with `vendor/portable-ruby-version` after the next pin
bump, before any other brew command.

Disposition: Addressed. Operator 2026-10-20: "I accept". 1: N2 narrowed to link state, `HOMEBREW_NO_AUTO_UPDATE=1`, and progress lines skipped (R9). 2: `brew cleanup --prune-prefix` and per-keg `brew link <keg>` (R8). 3: `_TIMEOUT_FALLBACK_PATHS` with gtimeout (R6). 4: V1 captures with the bare probe and runs doctor only once at the end. 5: the rc-0 case asserts the stub call and argv. 6: separate `_DOCTOR_BREW_TIMEOUT`.

### Risk

Finding:

1. The probe is not offline. `brew.rb:139-141` runs `Homebrew::API.fetch_api_files!` before every
   Ruby command, and `api.rb:236-245` downloads when the cache is missing or older than 7 days.
   `HOMEBREW_NO_AUTO_UPDATE` only stops the refresh of an existing cache. Do not use
   `HOMEBREW_NO_INSTALL_FROM_API`: with no local core tap, `diagnostic.rb:1202` maps
   `FormulaUnavailableError` to "not keg-only", so every keg-only rack would read as unlinked.
2. The "brew absent everywhere" test cannot reach the skip branch as written.
   - Under `load_mocks`, `command -v brew` finds the mock.
   - Without `load_mocks`, on `claude` it finds the real `/home/linuxbrew/.linuxbrew/bin/brew`.
   - CLAUDE.md forbids absence by `PATH` editing.
   - The dev-tools timeout tests show the scoped-`PATH` stub mechanism. Name it.
3. Same as Goal-fit 3: `load_mocks` should export `_BREW_BIN` to a recording stub. Otherwise a
   future unstubbed `run_doctor` test without mocks runs real brew from a fake `HOME`.
4. The unlinked-keg finding prints the header, then two unindented explanation lines, then
   ``Run `brew link` on these:``, then the indented kegs (`diagnostic.rb:1209-1218`). A parser
   that stops at the first unindented line finds 0 kegs. Anchor on the `Run `brew link`` line.
5. Same as Ergonomics 6: use a separate timeout variable or document the coupling.
6. V1 says run `-t doctor` and "save the raw probe output". Doctor's rendering is not raw, so
   capture with the bare `brew doctor <checks> 2>&1`. Also require `brew link` rc 0 and
   `var/homebrew/linked/<keg>` present afterwards.

Smaller points: an unlinked keg from an untrusted tap is never reported (`UntrustedTapError` is
rescued as keg-only, `diagnostic.rb:1200`). Under `GITHUB_ACTIONS`, `opoo` emits `::warning::`
annotations, so the format changes; doctor never runs in CI.

Premise verified: named checks run alone (`cmd/doctor.rb:55`). An unknown name gives rc 1. Findings
go to stderr as `Warning: …`. Homebrew has no localisation. Probe rc 0 in 5.8 s on the Studio and
1.4 s on `claude`.

Assumption: the probe finishes quickly with no network access under cron, launchd or a bats
`HOME`, whose API cache is missing or stale.

Measured by the orchestrator 2026-10-20 on `claude`, in a fresh temp `HOME` under `env -i`:

- rc 0 in 3.2 s.
- Printed `==> Downloading Homebrew API data` and `✔︎ JSON API packages.x86_64_linux.jws.json`
  before `Your system is ready to brew.`
- Wrote 37 MB under the temp `HOME`.

So the cold-cache case fits the bound on this link. It does add two non-finding lines the parser
must skip. It also writes 37 MB into any `HOME` that reaches real brew, which is a further reason
for the `load_mocks` default stub.

Disposition: Addressed (1-6), Accepted (smaller points). Operator 2026-10-20: "I accept". 1: the probe's writes are documented and accepted, and `HOMEBREW_NO_INSTALL_FROM_API` is forbidden (R2). 2: the absence test uses a scoped `PATH` of stubs. 3: R12. 4: unlinked kegs anchored on ``Run `brew link` on these:`` (R9). 5: `_DOCTOR_BREW_TIMEOUT`. 6: V1 split into a, b, c, d, with the `brew link` rc and linked entry checked. Accepted: untrusted-tap kegs are never reported (Homebrew's limit, stated in the Design), and the `GITHUB_ACTIONS` format is irrelevant because doctor never runs in CI.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

## Multi-Lens Review — Round 2

Reviewed at commit: `cb25381c` (round-1 revision). All three lenses re-ran, because round 1
changed design substance.

### Goal-Fit (round 2)

Finding:

1. V1(b) cannot fail. The detector and the remedy share one walk (`Keg.must_exist_subdirectories`)
   and one test (`Utils::Path.resolved_path_exists?`, `utils/path.rb:89`), so a planted
   `/nonexistent` link passes by construction. It also cannot tell apart the two readings of
   2026-10-04:
   - The links broke after cleanup, and the check catches them.
   - Homebrew's test did not count them as broken, and the check misses them.
2. Hidden `brew doctor --json` (added 2026-07-17) gives `affects` and `remediation.commands` for
   unlinked kegs, but not paths for broken symlinks. It is not a public contract.
3. With any finding present, the "neither header" detail is always Homebrew's "Please note…"
   preamble.

Assumption: the 2026-10-04 links broke after `brew cleanup`'s prune ran.

Orchestrator check 2026-10-20, Studio Homebrew source:

- The prune runs last in `clean!` (`cleanup.rb:448-482`).
- `resolved_path_exists?` is `path.dirname.join(path.readlink).exist?`, which follows the whole
  chain and so is effectively the test `find -L` makes.
- `git log -S resolved_path_exists` shows its last change on 2026-09-05, before the incident.

So the second reading needs links that `find -L` reports and Homebrew's test does not, and that
does not happen for an ordinary dangling link. The first reading holds.

Disposition: Addressed (1, 3), Accepted (2). Operator 2026-10-20: "Accepted".

- 1: V1(b) removed. The mechanism paragraph rewritten as the source-derived conclusion.
- 3: `--quiet` added (R2), and the fallback detail prefers a `Warning:` or `Error:` line (R10).
- 2, accepted: the switch is hidden, so it is no more stable than the text, and it does not give
  broken-symlink paths.

### Ergonomics (round 2)

Finding:

1. The multi-line WARN detail would break `doctor_warn`'s single-line layout. Ten `brew link`
   lines means ten pastes, and `brew link` takes several formulae at once. Use the one-line
   pyenv-shims shape (`lib/helpers.sh:1378`).
2. The "neither header" detail is the "Please note…" preamble. `--quiet` removes it.

Premise verified: the two checks are clean on both machines. The Studio has 238 racks, 215
linked entries and 23 keg-only racks, and raises no WARN.

Assumption: same as Goal-Fit round 2, settled as recorded there.

Disposition: Addressed. Operator 2026-10-20: "Accepted".

- 1: single-line WARNs. Names are capped at 10, and one `brew link` command names every keg
  (R8).
- 2: `--quiet` (R2).

### Risk (round 2)

Finding:

1. `_BREW_FALLBACK_PATHS` still defaults to real paths, and every machine the suite runs on has a
   real brew at one of them. `load_mocks` must also export it to a missing path. The stub must log
   under `BATS_TEST_TMPDIR`, not `${MOCK_CALLS_FILE:-/tmp/mock_calls}`. The export is load-bearing
   for `unit.bats:555`, `:1472` and `:1960`.
2. R3's resolution order is untested.
3. The fallback detail is the "Please note…" preamble.
4. V1(b) has no pre-check, and its post-check covers only `opt`.
5. `--prune-prefix` also removes empty and `.DS_Store`-only directories. Studio blast radius
   today: 0 empty directories and 0 broken links across the prune dirs and `Caskroom`.

Checked clean:

- (a) `_rc=$?` after the if/else captures the rc. The `local _out="$(…)"` form does not, which was
  measured.
- (c) `gtimeout` has compatible arguments.
- (e) No existing count assertion breaks.

Assumption: same as Goal-Fit round 2, settled as recorded there.

Disposition: Addressed (1-4), Accepted (5). Operator 2026-10-20: "Accepted".

- 1: R12 now exports both values, with the log under `BATS_TEST_TMPDIR`.
- 2: two resolution tests, and R3 requires them.
- 3: R10.
- 4: V1(b) removed; V1(a) and V1(c) check the `find` before and after.
- Smaller: the probe declares `local` first; the gtimeout-fallback test finds the real `timeout` as
  `doctor_dev_tools.bats:45-48` does; the "update existing count asserts" line is dropped.
- 5, accepted: a bare `brew cleanup` runs the same prune on every `-t update`. The Design now
  states what the prune removes.

### Stopping

Round 2's findings land in the apparatus (test isolation, fixture argv, output layout), except
Goal-Fit 1. That one was settled from source rather than by another round. The round-2
corrections removed V1(b) and replaced multi-line output with a single line, so the design
shrank. Both stop signals agree, and the operator accepted stopping after round 2.
