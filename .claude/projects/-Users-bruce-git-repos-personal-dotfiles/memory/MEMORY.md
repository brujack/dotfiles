# Memory Index

- [macOS + Linux capability migration complete](project_capability_migration.md) — both specs implemented and merged; mas-brewfile-integration was already done
- [Next steps plans created](project_next_steps.md) — 5 specs+plans created 2026-04-08; secrets guardrails implemented first (PR #5 merged)
- [helpers.sh symlink loop bug fixed](feedback_symlink_loop.md) — skip projects/ in first .claude/\* loop to prevent circular symlinks
- [math repo ADR and CI hardening](project_math_repo.md) — 6 ADRs added, CI lint enforced, secrets guardrail added 2026-04-09
- [Always use feature branches](feedback_feature_branches.md) — implementation goes on feature branch → PR → CI auto-merge; never commit directly to master
- [Mock pass-through for filesystem commands](feedback_mock_passthrough.md) — ln/chmod/mv/cp mocks must call real binary; log-only mocks cause silent test failures
- [Dotfiles session 2026-04-11](project_dotfiles_prs.md) — CI hygiene, update summary, bootstrap tests; 554 tests on master after PR #56 (brewfile drift)
- [BATS direct-call error-capture pattern](feedback_bats_direct_call_pattern.md) — use `fn || _rc=$?` not bare `fn; local _rc=$?` to avoid ERR trap firing before assertion
- [Subagent worktree path must be explicit](feedback_subagent_worktree_path.md) — state worktree path prominently at top of implementer prompt or subagent commits to wrong repo
- [User profile](user_profile.md) — 45yr systems/devops engineer; optimize for readability/maintainability; push back when warranted; don't over-engineer
- [Mock detection mechanism](feedback_mock_detection_mechanism.md) — use dpkg -l/rpm -q/brew list instead of command -v for package detection; command -v bypasses mock PATH when binary is really installed
- [Bash coverage gate status](project_bash_coverage.md) — kcov/bashcov both fail in GH Actions; CI job is non-blocking; floors defined but gate not enabled
- [Subagent verbatim-copy must read source file](feedback_subagent_verbatim_copy.md) — extraction tasks must read actual source file; plan code examples may be stale
- [Rebase feature branch before final code review](feedback_rebase_before_final_review.md) — rebase onto master first so reviewer only sees intentional changes, not stale-branch artifacts
- [Test that conditional file writes don't create the file on false branch](feedback_conditional_file_write_test.md) — OK/skip path tests must assert `[ ! -f detail_file ]` to catch regressions where the file is always written
- [OS gate test update pattern](feedback_os_gate_test_update.md) — when adding a platform gate to an existing function, all prior tests need the gate var set explicitly or they pass vacuously via SKIP
- [Direct master commits bypass CI](feedback_direct_master_ci_bypass.md) — new CI steps added via direct master commits never run until the next PR; verify on Linux before adding
