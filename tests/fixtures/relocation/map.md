# Relocation map fixture

Used by `tests/test_relocation_check.py` and by Task 1's acceptance gate 3
(`measure`) against the real `CLAUDE.md` at `2e38f5e4`. This is a test fixture,
not the plan's real relocation map — it exists only to give `measure` one real
moving section so its counts are non-zero.

Every unit in `### Mock Pattern`'s body-only span is listed INLINE or MOVE
below, so this fixture satisfies the completeness rule (every SECTION unit
must match exactly one INLINE or MOVE record). The two units carrying a rule
sentence are MOVE records rather than INLINE, so `measure`'s
`rule_sentences` count stays non-zero — INLINE units are excluded from that
count by design, since they never leave `CLAUDE.md`. Neither the dest file
nor the dest heading below is real; `measure` never resolves them (only
`check` does), and this fixture only exercises `measure`.

```relocation-map
SECTION | ### Mock Pattern

INLINE | See `~/git-repos/personal/ai-config/docs/knowledge/dotfiles-
INLINE | **Pass-through mocks:** `ln`, `chmod`, `mv`, `cp`, and `tee`
INLINE | **`env -i` subprocess strips PATH** — `setup_ansible()`'s py
MOVE | **`tests/mocks/curl` parses short-option clusters, not just | dotfiles-test-seams.md | Mock Pattern
MOVE | **`-o`'s write is now deferred until after the exit code is | dotfiles-test-seams.md | Mock Pattern
```
