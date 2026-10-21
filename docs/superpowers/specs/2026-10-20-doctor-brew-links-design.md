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

**Likely mechanism.** This is inferred from the source and was not reproduced.

- `brew cleanup` with no arguments prunes every broken symlink under the prefix link
  directories, `opt` included. That is `prune_prefix_symlinks_and_directories`
  (`Library/Homebrew/cleanup.rb:977`), which walks `Keg.must_exist_subdirectories`
  (`keg.rb:155`: the keg link dirs plus `opt` and `var/homebrew/linked`).
- `brew_update` (`lib/helpers.sh:203-230`) runs `brew cleanup` last. It returns 1 before
  cleanup when `brew update` or `brew upgrade --yes` fails.
- So dangling links that survive a run point to a run that failed hard.
- An unlinked keg means a link step failed partway through an upgrade. Cleanup does not
  relink, so it never repairs that case.

The gap is detection. A degraded prefix stays silent until a tool fails to run.

## Design

### Upstream check, not a reimplementation

Homebrew already checks both conditions (`Library/Homebrew/diagnostic.rb`).

- `check_for_broken_symlinks` (`:451`) walks the same `Keg.must_exist_subdirectories` that
  cleanup prunes. Its remedy is `brew cleanup`.
- `check_for_unlinked_but_not_keg_only` (`:1194`) lists every Cellar rack that has no
  `var/homebrew/linked` entry and is not keg-only. Its remedy is `brew link`.

`brew doctor <check> <check>` runs only the named checks, and `brew doctor --list-checks`
lists both names. dotfiles calls this command and does not walk the prefix itself.

### Unit

`_doctor_check_brew_links` goes in `lib/helpers.sh`. `run_doctor` calls it directly after
`_doctor_check_gnu_coreutils`. It prints a `Homebrew links:` header.

**Brew resolution, first hit wins:**

1. `_BREW_BIN`, the test seam and operator override.
2. `command -v brew`.
3. The entries of `_BREW_FALLBACK_PATHS`, in order. The default is `/opt/homebrew/bin/brew`,
   then `/usr/local/bin/brew`, then `/home/linuxbrew/.linuxbrew/bin/brew`.

The fixed paths matter because `-t doctor` bypasses the brew prereq and can run over `ssh`,
cron or launchd. linuxbrew's `PATH` entry exists only in interactive zsh (`CLAUDE.md`, Linux
workstation brew PATH).

A `_BREW_BIN` that is set but not executable prints a WARN that names it. It never falls
through to resolution, because an override the operator named must not be silently replaced.
When no candidate resolves, the check prints `  brew not found — skipped` and changes no
counter.

**Probe:**

```bash
"${_timeout_bin}" "${_DOCTOR_PROBE_TIMEOUT:-60}" "${_brew}" doctor \
  check_for_broken_symlinks check_for_unlinked_but_not_keg_only </dev/null
```

- stdout and stderr are captured together into one variable.
- `_timeout_bin` is resolved with `command -v timeout`, as in `_doctor_check_dev_tools`.
- If `timeout` is absent the probe runs unbounded. Stock macOS has no `timeout` unless the
  coreutils gnubin is on `PATH`. This is the same accepted degrade that `_doctor_check_dev_tools`
  documents.
- The default is 60 s, not that arm's 10 s, because this probe measured 5 s on the Studio and
  10 s leaves too little margin under load.

**Verdicts:**

| Probe result                                                  | Verdict                        | Detail                                                    |
| ------------------------------------------------------------- | ------------------------------ | --------------------------------------------------------- |
| rc 0                                                          | `doctor_pass "brew links"`     | none                                                      |
| rc 1 and output holds `Broken symlinks were found`            | one `doctor_warn "brew links"` | the indented paths that follow, then `run: brew cleanup`  |
| rc 1 and output holds `You have unlinked kegs in your Cellar` | one `doctor_warn "brew links"` | the indented keg names, then `run: brew link <keg>`       |
| rc 1 and output holds neither header                          | `doctor_warn "brew links"`     | `brew doctor rc 1:` plus the first non-empty output line  |
| rc 124 with `timeout` present                                 | `doctor_warn "brew links"`     | `brew doctor did not finish in <N>s`                      |
| any other rc                                                  | `doctor_warn "brew links"`     | `brew doctor rc <N>:` plus the last non-empty output line |

When both headers are present, each one produces its own WARN, so there are 2. Each list is
capped at 10 entries. Past that, a final `… <M> more` line follows.

Findings are WARN, not FAIL.

- Homebrew itself reports them as warnings.
- `brew cleanup` or `brew link` clears them without a dotfiles run.
- A FAIL would change `-t doctor`'s exit code for prefix housekeeping.

An rc 1 the parser does not recognise still warns and never passes. Unrecognised output fails
closed.

### Fixtures

Stub outputs are not typed by hand. V1 runs the real probe against a planted dangling link on
the Studio. Its exact output is saved as `tests/fixtures/brew/doctor-broken-symlinks.txt`. The
unlinked-keg fixture is captured the same way in V1, using `brew unlink` on a keg that is not
keg-only and then `brew link` to restore it.

Both captures need the operator's "yes" before they run, because they modify the Studio's live
prefix for the length of one command.

### Tests

`tests/setup_env/doctor_brew_links.bats` points `_BREW_BIN` at a stub in `BATS_TEST_TMPDIR`. The
stub prints a fixture, exits with a chosen rc, and records its argv.

- Brew absent everywhere: `_BREW_BIN` unset and `_BREW_FALLBACK_PATHS` set to a missing path,
  with `command -v brew` failing. Result is the skip line, and pass, warn and fail are unchanged.
- `_BREW_BIN` not executable: WARN naming the path, and the stub is not called.
- rc 0: PASS.
- Broken-symlinks fixture with rc 1: one WARN containing the fixture's path and `brew cleanup`.
- Unlinked-keg fixture with rc 1: one WARN containing the keg and `brew link`.
- Both fixtures concatenated with rc 1: exactly 2 WARNs.
- Unrecognised output with rc 1: WARN containing `rc 1`, and PASS unchanged.
- A stub that sleeps, run under `_DOCTOR_PROBE_TIMEOUT=1`: WARN containing `did not finish`.
- rc 3: WARN containing `rc 3`.
- 12 paths: the output shows 10 paths and `… 2 more`.
- argv: the recorded argv is exactly `doctor check_for_broken_symlinks
check_for_unlinked_but_not_keg_only`.
- `run_doctor` calls `_doctor_check_brew_links`. Run `run_doctor` with the check stubbed to
  record a call.

The new seams `_BREW_BIN` and `_BREW_FALLBACK_PATHS` get a row in
`ai-config/docs/knowledge/dotfiles-test-seams.md` and a one-line rule in `CLAUDE.md` Test Seams,
in the same change.

## Requirements

- **R1.** `[PR1]` `run_doctor` calls `_doctor_check_brew_links` directly after `_doctor_check_gnu_coreutils`.
- **R2.** `[PR1]` The probe runs `brew doctor check_for_broken_symlinks check_for_unlinked_but_not_keg_only` with stdin from `/dev/null`. When `timeout` is on `PATH` the probe is bounded by it, with a default of 60 s overridable by `_DOCTOR_PROBE_TIMEOUT`; when `timeout` is absent the probe runs unbounded.
- **R3.** `[PR1]` Brew resolves from `_BREW_BIN`, then `command -v brew`, then `_BREW_FALLBACK_PATHS` (default `/opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew`), first hit wins.
- **R4.** `[PR1]` A set but non-executable `_BREW_BIN` produces a WARN naming it and the probe does not run.
- **R5.** `[PR1]` With no brew resolvable, the check prints `brew not found — skipped` and changes no doctor counter.
- **R6.** `[PR1]` rc 0 produces exactly one PASS labelled `brew links`.
- **R7.** `[PR1]` rc 1 produces one WARN per recognised header (broken symlinks, unlinked kegs), listing at most 10 entries plus a `… <M> more` line, with `brew cleanup` or `brew link` as the remedy.
- **R8.** `[PR1]` rc 1 with no recognised header, rc 124, and any other non-zero rc each produce a WARN and never a PASS.
- **R9.** `[PR1]` No outcome of this check calls `doctor_fail`.
- **R10.** `[PR1]` Test fixtures for the two findings are files under `tests/fixtures/brew/` captured from the real probe in V1.
- **R11.** `[PR1]` `_BREW_BIN` and `_BREW_FALLBACK_PATHS` are documented in `dotfiles-test-seams.md` and as a one-line rule in `CLAUDE.md` Test Seams.
- **V1.** On the Studio, with the operator's approval, plant `ln -s /nonexistent /opt/homebrew/opt/zz-doctor-probe`, run `./setup_env.sh -t doctor`, see a WARN naming that path, save the raw probe output as the fixture, then `rm` the link and confirm `find -L /opt/homebrew/opt -maxdepth 1 -type l` returns 0. Do the same for an unlinked keg via `brew unlink <keg>` and `brew link <keg>`, where `<keg>` is not keg-only and `brew uses --installed <keg>` prints nothing, so no other formula loses a dependency while it is unlinked.
- **V2.** On the Studio and on `claude`, the merged check on the real, clean prefix prints PASS for `brew links`.
- **V3.** On `claude`, `env -i HOME="${HOME}" PATH=/usr/bin:/bin bash ./setup_env.sh -t doctor` (brew not on `PATH`, as for ssh, cron and launchd) still finds linuxbrew through the fallback paths and prints PASS rather than the skip line.
- **N1.** `brew_update` and every `-t update` section are unchanged.
- **N2.** The check never runs `brew cleanup`, `brew link` or any other command that modifies the prefix.
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

Disposition:

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

Disposition:

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

Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
