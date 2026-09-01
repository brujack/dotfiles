# August 2026 Retrospective

**Period:** 2026-08-01 → 2026-08-31
**PRs merged:** 55 (#195–#250, #242 absent)
**Commits:** 50+
**Test count:** ~1099 → 1545 (+446, CI-measured 2026-08-28 on `3530241`)
**Bash coverage:** 91% (3442/3758 commands; CI gate raised from 90% → 91%)

---

## PRs Merged

### Shell Quality / ShellCheck
| PR | Title |
|----|-------|
| #197 | fix(tests): shellcheck the bats suites, revive six inert assertions |
| #200 | fix(shellcheck): clear 271 findings, derive lint scope from git ls-files |
| #218 | fix(shell): stop six functions reporting success for work that did not happen |
| #219 | feat(lint): derive the shell lint scope from first-line shebang |

### Coverage Overhaul
| PR | Title |
|----|-------|
| #199 | fix(coverage): measure the whole repo, and count commands not lines |
| #201 | fix(coverage): correct the denominator, widen the instrumented set |
| #202 | fix(coverage): stop the tracer silencing every traced stderr |
| #203 | fix(coverage): refuse to report a figure over a red suite |
| #204 | fix(coverage): close three instrument deferrals and reject unknown flags |
| #206 | docs(coverage): record why the --json guard branch is untested |
| #215 | docs: publish CI's coverage figure and close out the #214 plan |

### ZSH / Profile / Identity
| PR | Title |
|----|-------|
| #220 | fix(zshrc): guard keychain on interactive shell to stop bats hang |
| #221 | fix(zshrc): quote the keychain path expansion |
| #222 | fix(zshrc): collapse four hostname tables into one |
| #223 | refactor(profiles): resolve legacy identity vars from one table |
| #224 | docs(oracle): document the mutation that actually isolates the variable |

### GNU Make / macOS Build
| PR | Title |
|----|-------|
| #208 | feat(bats): provision bats on macOS and point zsh -n at the zsh files |
| #210 | docs(backlog): macs are blind to the Make 4.x behaviour class |
| #211 | docs(spec): GNU Make 4.x on macOS |
| #212 | docs(spec): make the MAKEFLAGS rule enforceable |
| #213 | docs(spec): delete the duplicated round-3 review section |
| #214 | feat(make): resolve macOS make to GNU 4.x and close the version-skew class |
| #216 | docs: setup_user now installs GNU make on macOS |
| #217 | docs(adr-0018): the gnubin prepend reaches interactive shells only |

### Python / uv / Dependencies
| PR | Title |
|----|-------|
| #225 | feat: install uv on macOS and Linux |
| #226 | feat: declare the venv package set once, install it from a lock |
| #227 | chore(deps): bump asteval from 1.0.6 to 1.0.9 |
| #228 | fix: drop boto3, floor checkov, take shell-gpt 1.5.1 |
| #229 | docs: scope the accepted-risk claim to the deployment |
| #230 | docs: #227's actor was Dependabot, not Renovate |
| #231 | fix: cosmic-ray belongs in test-lint, not runtime |
| #232 | feat: render requirements-runtime-ci.txt alongside the test-lint one |
| #233 | fix: drop pylint — GPL-2.0-or-later and invoked by nothing |
| #235 | feat: ci-test and ci-mutation renderings, scoped by purpose |
| #236 | feat: resize the CI slices, add ci-audit, gate the lock |

### Renovate
| PR | Title |
|----|-------|
| #237 | feat(renovate): enable npm and pinDigests, document the pip_requirements trap |
| #238 | fix(renovate): inline the preset — this repo has never once been processed |
| #240 | chore(deps): pin actions/checkout action to d23441a (Renovate) |
| #241 | chore(deps): update actions/checkout action to v7 (Renovate) |
| #243 | ci: hold unlabelled Renovate PRs for triage |

### Detect Env / Identity Failure
| PR | Title |
|----|-------|
| #239 | fix(detect_env): fail closed when the identity table does not load |

### Cadence / LaunchAgents
| PR | Title |
|----|-------|
| #244 | feat(cadence): weekly LaunchAgent that summons Renovate triage |
| #245 | fix(cadence): call install_ledger_drift_agent from run_setup_user |
| #246 | fix(cadence): authenticate to ntfy, and give the heartbeat one path and a written bound |
| #247 | ci: cap all 7 job runtimes with timeout-minutes |
| #248 | fix(cadence): put ~/.local/bin on the LaunchAgent PATH |
| #249 | fix(cadence): keep the detector's stderr out of the finding count |

### Git Hooks
| PR | Title |
|----|-------|
| #195 | fix(pre-push): fail closed on unrecognized paths |
| #198 | fix(git-hooks): read core.hooksPath through git config includes |

### Pre-commit / ggshield
| PR | Title |
|----|-------|
| #234 | fix: resolve ggshield past PATH and announce the skip |

### Update / Exit Contract
| PR | Title |
|----|-------|
| #250 | fix(update): exit non-zero when a section fails |

### Misc / Docs / Config
| PR | Title |
|----|-------|
| #196 | chore: adopt warp agent execution profile defaults |
| #205 | fix(capture): honor exported LEDGER_BIN and MACHINE_ID_PATH |
| #207 | docs(rsync): record why ratna alone has no --exclude=personal |
| #209 | docs(backlog): CI's pinned download has no retry, so one 503 fails the job |

---

## Recurring Patterns / Gotchas

### 1. "Zero as baseline" oracle defect (three instances)
A check satisfied by any non-zero result — Renovate PRs at 0 for 98 days, coverage
instrumented over only 36% of the repo, 64 mock files outside lint scope — is
structurally unfalsifiable. The fix was always the same: derive the denominator from
a content-based source (`git ls-files` + first-line shebang), not from a literal list
or a pathspec that silently drops extensionless files.

### 2. Interactive-vs-non-interactive actor boundary
The `make` version split (GNU 4.4.1 in terminals, 3.81 for launchd/hooks/cron),
ggshield PATH resolution, Homebrew PATH on the Linux workstation, and the
`keychain` BATS hang all trace to the same root: **who actually runs this code?**
A test or diagnostic that runs as an interactive shell answers for a different actor
and will give the wrong answer for cron, launchd, and editor-spawned hooks. Each
fix added an actor-aware seam (`_OVERRIDE_*`, `GGSHIELD_FALLBACK_PATHS`) and an
explicit measurement of the non-interactive actor.

### 3. Both halves of a seam must land in the same commit
`_OVERRIDE_BATS_BIN` shipped with the test half committed and production half
stashed — CI ran without the seam, `command -v bats` resolved the real binary,
the guard did not fire, and the tracer ran the full suite for 60s before timing out.
Two hours of "unreproducible" followed. Rule: if a seam is needed for a test, it
ships in the same PR, not the next one.

### 4. Provenance figures must be read from a single run
Coverage ratio and disagreement count were repeatedly cited from different CI runs,
producing pairs that never existed. The fix was to state run/job IDs alongside each
figure and enforce "read all four from one run" in the CLAUDE.md text.

### 5. Cadence: detector stdout/stderr contract matters
The ledger-drift detector was printing a banner to stdout, so every finding was
over-counted by 1, and the **clean path** emitted `"findings": 1` on a fleet with
zero drift. Only discovered because stderr was finally plumbed through (#249). The
fix was to move banners to stderr and document the contract: stdout = one finding
per line, nothing else.

### 6. Renovate was never running
`extends` with a private preset (`ai-config`) fails at `initRepo` before any
extraction — 0 PRs in 98 days, no error surfaced. Fixed by inlining the preset
(#238). Verified by #240 (Renovate ran and pinned all 6 `actions/checkout` refs
within 24 h).

### 7. Dependabot security auto-PRs silently walked back checkov a year (#227)
`uv.lock`-only edit passed all CI checks (internally consistent lock). Decision:
keep vulnerability alerts, disable auto-PRs fleet-wide. Now Python has no automated
update path — a named gap, not a steady state.

---

## Test Health

- **Count:** 1099 → 1545 (+446). Floor is 840; no regression risk.
- **Coverage gate:** Raised from 90% → 91%. Sits exactly on the floor for the
  fifth consecutive CI measurement; no margin. Any instrumented line added without
  a test will breach immediately.
- **Instrumented set:** Grew from 13 hardcoded files (36% of repo) to all 34 files
  matched by `git ls-files` + shebang predicate. The denominator is now 3758
  commands vs. ~1400 before. The 91% figure is therefore not comparable to any
  figure before August.
- **Heuristic disagreements:** 18-20 per run (union-rule lines the static heuristic
  missed). Non-zero is a to-do, not a failure. Reduced from 192 after the
  heredoc/continuation exclusion rules landed.
- **No known flaky tests.** The bats hang (16 leaked ssh-agents from keychain) was
  fixed in #220; previously masked on macOS/CI by the Linux-only binary path.
- **64 mock files** in `tests/mocks/` now linted by `make lint` (#219/#200). Two had
  real shellcheck findings (fixed on branch).

---

## What Went Well

- **ShellCheck debt cleared in one pass.** 271 findings behind three blanket
  suppressions were resolved — 194 real quoting fixes, 12 dead-variable deletes,
  4 `$?` rewrites, 1 unreachable function. The `.shellcheckrc` now carries a single
  structural `SC1091` suppression, which is correct.
- **Coverage now measures what it claims to.** The previous 91% was computed over
  36% of the repo; the current 91% is over the full instrumented set.
- **Renovate shipped its first real PRs** within 24 h of the inline-preset fix
  after 98 days of silence. The `automerge: patch/minor` + `hold: major` split
  behaved exactly as configured.
- **Profile/identity table consolidated** from 5 separate files to one
  `PROFILE_LEGACY` in `config/profiles.sh` + one shared oracle. The "adding a new
  machine" procedure dropped from 5 edits in 5 files to 3 edits in 2 files.
- **uv migration complete.** `pyproject.toml` + `uv.lock` are now the declaration;
  both venv-creating sites install from the lock. The venv-snapshot-before-sync
  path exists and its rollback procedure is documented.
- **The cadence system delivered its first production signals.** Heartbeat, ntfy
  authentication, `~/.local/bin` on the plist `PATH`, stderr isolation — all
  required real fixes found only after the system was live.

---

## What to Improve

1. **Coverage margin is zero.** Five consecutive measurements at exactly 91%. The
   next PR that adds instrumented lines without tests will breach the gate. Consider
   a 92% short-term target or a denominator freeze test.
2. **CI has no retry on pinned downloads.** A single 503 from the shellcheck or uv
   CDN fails the job. Backlog item exists; no fix yet. Low urgency (rare) but
   annoying.
3. **`scripts/sync_git_repos.sh` cannot run non-interactively on the Linux
   workstation** — Homebrew is on PATH only in interactive zsh. The update workflow
   works because it is launched interactively, but any cron or agent invocation
   silently fails at the `env which brew` gate. No fix scheduled.
4. **Python has no automated update path.** Dependabot auto-PRs are off, Renovate
   `pep621` is not enabled. Alerts will fire with nothing proposing fixes. Named
   gap; not a steady state.
5. **`covered > coverable` guard is new and untested under adversarial heuristics.**
   The guard fires correctly on construction violations but relies on the exclusion
   rules being well-calibrated. The `--count-coverable` and `--file-coverage` flags
   let a developer inspect a single file cheaply; encourage using them before adding
   new exclusion rules.
6. **Conditional `includeIf` git config is invisible to the core.hooksPath probe.**
   The probe runs once per sweep from an arbitrary directory; a gitdir-conditional
   include is only visible from a matching repo. Accepted as a known boundary but
   worth revisiting if fleet machines start using worktree-scoped configs.

---

## Action Items for September

| Priority | Item |
|----------|------|
| High | Implement `-t update` cd-guard spec (plan exists: `docs/superpowers/plans/2026-08-31-update-run-cd-guards.md`, 7 tasks) |
| High | Implement update-run truthfulness exit contract spec (#250 landed the exit; spec covers broader truthfulness) |
| Medium | Enable Renovate `pep621` manager to close the Python update gap |
| Medium | Add CI retry for pinned downloads (shellcheck, uv) |
| Low | Investigate raising coverage gate to 92% once cd-guard tests land |
| Low | Document `_OVERRIDE_RUN_TMPDIR_ROOT` in the seams table in CLAUDE.md (already in coverage section; consolidate) |
