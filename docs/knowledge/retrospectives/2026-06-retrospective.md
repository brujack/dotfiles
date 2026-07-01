# June 2026 Retrospective

**Period:** 2026-06-01 → 2026-06-30
**PRs merged:** 54 (#116–#169)
**Commits:** 50
**Test count:** 729 → 848 (+119)
**Bash coverage:** 90% (CI-gated via PS4 xtrace)

---

## PRs Merged

### Coverage & CI Infrastructure
| PR | Title |
|----|-------|
| #116 | ci(bash-coverage): replace kcov gate with macOS xtrace gate at 90% |
| #117 | test(coverage): add 3 tests targeting uncovered branches |
| #118 | test(coverage): cover 3 behavioral gaps in helpers/linux_ubuntu |
| #126 | test(update): isolate run_update --claude-only from real HOME |

### Features
| PR | Title |
|----|-------|
| #119 | feat(update): capture stderr per-section for richer failure output |
| #124 | feat: add -t recreate-venv to force-recreate a pyenv virtualenv |
| #128 | feat: adopt 10-80-10 execution cycle (ai-config ADR-0009/0010) |
| #129 | feat(developer): cosmic-ray in ansible venv; fix CoP plugin rename |
| #143 | feat(ubuntu): Ubuntu 26.04 Resolute Raccoon detection and package files |
| #146 | feat(linux): ARM64 support + version bumps |
| #161 | feat(devtools): add OpenTofu install for macOS and Ubuntu |
| #162 | feat(security): replace curl\|bash installs with brew/apt/SHA-pin |
| #165 | feat(brew): add cargo-cyclonedx and cyclonedx-python |
| #166 | feat: state-ledger CMDB integration (T5/T6/T7) |
| #167 | feat(ledger): wire state-ledger writes into dotfiles update |
| #168 | feat(ledger): wire state-ledger into setup/developer/recreate_venv runs |

### Bug Fixes
| PR | Title |
|----|-------|
| #121 | fix(brew): trust remaining third-party taps for Homebrew 6.0 |
| #122 | fix(setup): symlink ~/.claude/projects to ai-config |
| #123 | fix(update): prepend ruby-install bin to PATH |
| #125 | fix: exa-mcp install, npm update, and GIT_DIR test isolation |
| #127 | fix(recreate-venv): tolerate missing virtualenv in delete step |
| #130 | fix(developer): rehash pyenv shims after pip install |
| #132 | fix(pre-commit): add missing existence check for validate_memory.py fallback path |
| #135 | fix(developer): guard mlx pip install behind macOS check |
| #136 | fix(update): brew trust, pip dep pins, Brewfile drift |
| #137 | fix(brewfile): remove docker formula and dotnet cask aliases |
| #138 | fix(setup): add docker formula, remove kitchen |
| #139 | fix(brewfile): remove docker formula and powershell cask duplicates |
| #140 | fix(brewfile): remove chef tap and trust reference |
| #141 | fix(linux): fix 6 Ubuntu Noble setup failures + move Steam to Flatpak |
| #142 | fix(linux): apt-get for base packages, sudo for flatpak Steam |
| #144 | fix(ubuntu): cgroup v2 daemon.json, glances via apt, passlib for Python 3.13 |
| #145 | fix(packages): nala, ruby, Go PPA cleanup for Ubuntu 26.04 |
| #147 | fix: Ubuntu 26.04 housekeeping — HAS_FLATPAK, VirtualBox 7.1, dead OS vars |
| #148 | fix(macos): add gitguardian/tap to install_macos_casks brew trust |
| #150 | fix(scripts): migrate restart_fah from init.d to systemctl |
| #151 | fix(brew): suppress dependency prompt with NONINTERACTIVE=1 |
| #152 | fix(developer): add molecule and molecule-plugins[docker] to ansible venv |
| #153 | fix(zshrc): rbenv init on Linux never ran due to chruby guard |
| #154 | fix: Ubuntu 26.04 compatibility — ruby-build, Python build deps, helm/cloudflare/azure-cli APT repos |
| #155 | fix: Ubuntu 26.04 setup — nala comment filter, helm script, dotnet non-fatal |
| #156 | fix(ruby): refresh ruby-build defs from git for Ubuntu 26.04 |
| #157 | fix(apt): purge stale helm/azure-cli sources.list.d on Ubuntu 26.04 |
| #158 | fix(zshrc): drop rbenv local — silently overwrites project .ruby-version |
| #159 | fix(apt): add DEBIAN_FRONTEND=noninteractive to all nala/apt installs |
| #160 | fix(brew): pass --yes to brew upgrade to skip Homebrew 6.0 prompt |
| #163 | fix(linux): run _install_ubuntu_rust after brew; mkdir keyrings for opentofu |
| #164 | fix(helpers): mkdir custom/themes after oh-my-zsh git clone |

### Refactors / Chores / Docs
| PR | Title |
|----|-------|
| #120 | chore: resolve all 5 backlog items from prior retro |
| #131 | refactor(memory): adopt canonical .claude/memory + .claude/retrospectives layout |
| #133 | chore: remove per-repo memory/retrospective plumbing |
| #134 | docs(knowledge): pointer stub per ADR-0020 |
| #149 | chore(ubuntu): P3 cleanup — nala consistency, dead OS branches, snap auto-deps |
| #169 | docs: add Anthropic/Claude Code weekly feature digests (4 runs) |

---

## Recurring Patterns and Gotchas

### Ubuntu 26.04 Resolute Raccoon required a long tail of fixes
At least 15 PRs (#141–#163) addressed Ubuntu 26.04 compatibility. Issues clustered into two waves: the initial port (#141–#149 around June 16-18) and a second cleanup sweep (#154–#159 on June 20-21) after real-machine testing exposed more failures. Individual pain points:
- APT sources for helm, azure-cli, cloudflare left stale `.sources.list.d` entries from Noble
- `ruby-build` Homebrew bottle lagged upstream; needed a git-based refresh
- `DEBIAN_FRONTEND=noninteractive` missing from many `apt`/`nala` calls, causing interactive prompts in CI
- `nala` comment filtering broke on a subtle format difference
- Python 3.13 compatibility: `passlib` install needed a workaround; `gmpy2` build deps changed

**Takeaway:** Ubuntu major-version upgrades need a dedicated pre-flight checklist and ideally a staging run on a fresh VM before landing the initial feature PR.

### Homebrew 6.0 tap trust model required multiple patches
Five PRs (#121, #136, #148, #151, #160) addressed Homebrew 6.0 compatibility. The new `brew trust` requirement for third-party taps and the interactive `--yes` prompt were the root causes. Both should have been anticipated and handled in a single PR.

**Takeaway:** When Homebrew releases a major version, do a pre-flight audit of all `brew` call sites and Brewfile entries before the version becomes the default.

### Brewfile deduplication failures clustered (#137–#140)
Four consecutive PRs in mid-June cleaned up formula/cask duplicates that caused `brew bundle` to fail with "Could not symlink" errors. The CLAUDE.md dedup rule exists but isn't enforced mechanically.

**Takeaway:** A CI lint step (`scripts/check-brewfile-dedup.sh`) that exits non-zero on duplicate tool entries would catch this class of error before merge.

### State-ledger integration was split across three same-day PRs (#166–#168)
All three PRs landed within hours on June 26-29 but were committed separately by design (coverage sprint anti-pattern note in CLAUDE.md). Each was clean and well-scoped, but the inter-PR doc update churn (test count updates, CLAUDE.md edits per PR) was noisy.

### Warp terminal settings churned three times
`chore(warp)` commits enabled the SSH tmux wrapper, then disabled it, then accepted deprecation. This indicates the setting was experimental and the expected behavior wasn't stable. No user-visible regression, but the noise in the log is worth avoiding.

---

## Test Health

| Date | Count | Notes |
|------|-------|-------|
| ~Jun 1 | 729 | Floor before June coverage push |
| Jun 25 | 810 | After coverage sprint PRs #116–#118 + interim work |
| Jun 26 | 834 | After PR #166 (state-ledger T5/T6/T7) |
| Jun 28 | 840 | After PR #168 (ledger wiring for setup/developer/recreate_venv) |
| Jun 29 | 848 | After additional ledger tests |

**Coverage gate:** `bash-coverage` CI job replaced the non-functional kcov approach with a PS4/xtrace method. Now gates at 90% overall on `ubuntu-latest`. The approach was validated and merged as #116.

**Flaky tests:** The `run_update` test hang caused by real `pip` being invoked when `MOCK_PYENV_WHICH_STDOUT` is unset was documented in CLAUDE.md. Not fixed mechanically yet — `MOCK_PYENV_WHICH_STDOUT` must be set manually by the test author.

**Known untraceable lines:** Per CLAUDE.md coverage section, ~25-30 lines per file are structural non-traceables (function declaration lines, heredoc content, multi-line array literals). Per-file ceilings are documented; per-file floors not yet enforced by CI.

---

## What Went Well

- **Ubuntu 26.04 support landed completely.** Despite the fix churn, the new OS is now fully supported with detection, package files, ARM64 patches, and clean APT sources.
- **Security posture improved significantly.** #162 replaced all `curl | bash` install patterns with SHA-pinned downloads or brew/apt equivalents — a material security hardening.
- **Test count grew +119 in one month.** The coverage sprint delivered real tests, not synthetic padding.
- **State-ledger integration completed** across all four run types (`update`, `setup_user`, `setup`, `developer`, `recreate_venv`) giving a CMDB audit trail for every setup run.
- **OpenTofu** and **cyclonedx** tooling added — infrastructure-as-code ecosystem coverage is expanding.
- **10-80-10 cycle adopted** (PR #128) — structured Architect → Execute → Review phases are now first-class in the repo's workflow.
- **CI coverage gate** now functional and blocking after the kcov replacement.

---

## What to Improve

1. **No Brewfile dedup lint.** Four PRs (#137–#140) were needed to clear duplicate formula/cask pairs. A lightweight `scripts/check-brewfile-dedup.sh` check added to `make lint` would prevent recurrence.

2. **Ubuntu major-version testing procedure is ad-hoc.** The wave of June 20 fix PRs (5 PRs in one day) shows the process was reactive, not proactive. A written checklist or Makefile target (`make test-ubuntu-fresh`) for validating on a clean VM would reduce this.

3. **Per-file bash coverage floors not enforced.** CLAUDE.md documents target floors (90% for key files) but CI only gates the overall average. A file-level floor would catch regressions in individual modules earlier.

4. **`run_update` mock isolation not enforced by default.** The `MOCK_PYENV_WHICH_STDOUT` footgun is documented but not made obvious. Consider making the default mock path in `tests/setup_env/setup()` point to the mock binary so tests don't silently fall through to real pip.

5. **Warp settings experimentation in main branch.** The three chore(warp) commits within weeks suggest feature-flag style experiments. A `config/local.sh` override pattern or separate branch would keep main's history cleaner.

---

## Action Items for Next Period

- [ ] **Brewfile dedup lint** — add `scripts/check-brewfile-dedup.sh` and wire it into `make lint`
- [ ] **Ubuntu upgrade runbook** — document the pre-flight checklist in `docs/knowledge/dotfiles-ubuntu-upgrade.md`
- [ ] **Per-file coverage floors** — extend `scripts/run-bash-coverage.sh` to emit per-file percentages and optionally fail on known-floor violations
- [ ] **Default pyenv mock in test setup()** — set `MOCK_PYENV_WHICH_STDOUT` to the mocks path in `tests/helpers/common.bash` so tests don't accidentally run real pip
- [ ] **Bump CI test count floor** — currently gated at 806; should be raised to 848 (or to 840 conservatively) to catch test deletions
