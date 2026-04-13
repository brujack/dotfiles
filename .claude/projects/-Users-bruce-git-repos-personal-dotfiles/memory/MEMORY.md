# Memory Index

- [macOS + Linux capability migration complete](project_capability_migration.md) — both specs implemented and merged; mas-brewfile-integration was already done
- [Next steps plans created](project_next_steps.md) — 5 specs+plans created 2026-04-08; secrets guardrails implemented first (PR #5 merged)
- [helpers.sh symlink loop bug fixed](feedback_symlink_loop.md) — skip projects/ in first .claude/* loop to prevent circular symlinks
- [math repo ADR and CI hardening](project_math_repo.md) — 6 ADRs added, CI lint enforced, secrets guardrail added 2026-04-09
- [Always use feature branches](feedback_feature_branches.md) — implementation goes on feature branch → PR → CI auto-merge; never commit directly to master
- [Mock pass-through for filesystem commands](feedback_mock_passthrough.md) — ln/chmod/mv/cp mocks must call real binary; log-only mocks cause silent test failures
- [Dotfiles session 2026-04-11](project_dotfiles_prs.md) — CI hygiene, update summary, bootstrap tests, security tooling; 345 tests on master
- [BATS direct-call error-capture pattern](feedback_bats_direct_call_pattern.md) — use `fn || _rc=$?` not bare `fn; local _rc=$?` to avoid ERR trap firing before assertion
