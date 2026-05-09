# Design: Anthropic & Claude API Weekly Digest

**Date:** 2026-05-08  
**Status:** Accepted

## Context

The repo already has `scripts/whats-new-claude-code.sh` which fetches the Claude Code CHANGELOG from GitHub, diffs it against a stored state file, summarizes new content with `claude -p`, and commits a weekly digest to `docs/claude-code-new-features/`. A Monday 8am Eastern remote routine runs it automatically.

The same pattern should cover Anthropic/Claude platform updates: model launches, API feature releases, deprecations, and Python SDK changes. These are tracked in two separate upstream sources.

## Sources

| Source                           | URL                                                                                   | Format                                                             |
| -------------------------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| Anthropic Platform release notes | `https://platform.claude.com/docs/en/release-notes/api`                               | SSR HTML (Next.js) — `curl -sL` returns full text embedded in HTML |
| Anthropic Python SDK CHANGELOG   | `https://raw.githubusercontent.com/anthropics/anthropic-sdk-python/main/CHANGELOG.md` | Raw markdown — identical to Claude Code CHANGELOG fetch            |

The platform page covers high-level news: model launches, beta feature announcements, deprecations. The SDK CHANGELOG covers library-level changes: new API methods, bug fixes, breaking changes.

## Approach

Two state files, one combined digest (Approach A). Each source is fetched and diffed against its own state file independently. Both diffs are concatenated under labelled headers and passed to `claude -p` in a single call. A single output digest is written.

Rejected alternatives:

- **Single combined state file**: noisy diffs when HTML structure changes; hard to debug.
- **claude -p browser fetch**: no state diffing possible; re-summarizes everything each run.

## Directory Layout

```
dotfiles/
├── docs/
│   └── anthropic-new-features/
│       ├── README.md                    # usage and schedule docs
│       ├── .platform-state.txt          # last-fetched platform notes (HTML-stripped text)
│       ├── .sdk-state.md                # last-fetched Python SDK CHANGELOG.md
│       └── features-YYYY-MM-DD.md       # weekly digest committed each Monday
├── scripts/
│   └── whats-new-anthropic.sh           # new script
```

State files are committed to the repo so diffs are reproducible across machines. The `.` prefix keeps them out of casual directory listings.

## Script Architecture

```
whats-new-anthropic.sh
├── fetch_platform_notes()    curl -sL platform page | python3 -c "strip HTML tags, collapse whitespace"
├── fetch_sdk_changelog()     curl -sf raw GitHub CHANGELOG.md
├── extract_new_platform()    diff .platform-state.txt against fetched text → new lines only
├── extract_new_sdk()         diff .sdk-state.md against fetched SDK content → new lines only
├── [exit 0 if both diffs empty — no new content]
├── generate_summary()        claude -p with combined prompt:
│                               "## Platform Release Notes\n{platform_diff}\n## Python SDK\n{sdk_diff}"
│                             Output sections:
│                               ## Model & API Changes
│                               ## SDK Changes
│                               ## Bug Fixes
│                             Rules: one bullet per change, skip version numbers/dates in bullets,
│                             omit empty sections, under 400 words total
├── write_output()            features-YYYY-MM-DD.md:
│                               # Anthropic & Claude API — What's New (YYYY-MM-DD)
│                               {summary}
│                               ---
│                               Sources: platform release notes | Python SDK CHANGELOG
├── update_state_files()      overwrite .platform-state.txt and .sdk-state.md
├── commit_and_push()         git add both state files + output file, commit, push
└── send_ntfy()               optional, same NTFY_URL env var as existing script
```

## HTML Extraction

The platform page is server-side rendered (Next.js). `curl -sL` returns the actual content. Extraction:

```bash
strip_html() {
  python3 -c "
import sys, re
content = sys.stdin.read()
text = re.sub(r'<[^>]+>', ' ', content)
text = re.sub(r'\s+', ' ', text).strip()
print(text)
"
}
```

The state file stores this stripped text. The diff compares stripped text → stripped text, avoiding false positives from HTML attribute churn.

## Test Seams

The script reuses the same seam pattern as `whats-new-claude-code.sh`:

| Variable                  | Effect                                                      |
| ------------------------- | ----------------------------------------------------------- |
| `_OVERRIDE_FEATURES_DIR`  | Redirects output and state files to a temp dir              |
| `_OVERRIDE_DOTFILES_ROOT` | Redirects the repo root used for `cd` before git operations |

No new seam variables (`_OVERRIDE_*`) required. Two new mock env vars are needed because the script makes two `curl` calls with different URLs:

| Mock var                    | Used for                                                                |
| --------------------------- | ----------------------------------------------------------------------- |
| `MOCK_CURL_PLATFORM_STDOUT` | Content returned when curl URL contains `platform.claude.com`           |
| `MOCK_CURL_SDK_STDOUT`      | Content returned when curl URL contains `githubusercontent.com`         |
| `MOCK_CURL_STDOUT`          | Fallback for single-URL tests (backward-compatible with existing tests) |
| `MOCK_CURL_EXIT`            | Simulating fetch failures (applies to all curl calls)                   |
| `MOCK_CLAUDE_STDOUT`        | Summary output in tests                                                 |
| `MOCK_CLAUDE_EXIT`          | Simulating claude CLI failure                                           |
| `MOCK_GIT_EXIT`             | Simulating commit/push failures                                         |

The `curl` mock is updated to check `$*` for the URL pattern and select `MOCK_CURL_PLATFORM_STDOUT` or `MOCK_CURL_SDK_STDOUT` when set, falling back to `MOCK_CURL_STDOUT`. This is backward-compatible — existing tests that set only `MOCK_CURL_STDOUT` continue to work unchanged.

Both new vars are added to the mock env vars table in `CLAUDE.md`.

## Schedule and Integration

- **Remote routine**: `whats-new-anthropic` — Monday 8am Eastern, same as Claude Code routine
- **Slash command**: `/whats-new-anthropic` added to the `whats-new` skill
- **CLAUDE.md**: `docs/anthropic-new-features/` added to the Layout table; no new seam entries needed (existing seam vars are reused)
- **`docs/superpowers/README.md`**: New row added to the All Plans table

## Error Handling

Mirrors `whats-new-claude-code.sh` exactly:

- Fetch failure → print error to stderr, return 1
- Empty summary from `claude -p` → print error, return 1
- `commit_and_push` failure → print warning (changes are committed locally), non-fatal
- ntfy failure → print warning, non-fatal
- `--dry-run` flag → print to stdout, no file writes, no commit

## Testing

New BATS test file: `tests/scripts/whats-new-anthropic.bats`

Required test cases (following mandatory categories from tdd.md):

**Happy path:**

- Both sources have new content → summary written, state files updated, output committed

**Boundary values:**

- Only platform source has new content → SDK diff skipped, summary still generated
- Only SDK source has new content → platform diff skipped, summary still generated
- Both diffs empty → exit 0, no output file written, no commit

**Error paths:**

- Platform fetch fails → exit 1, no state files modified
- SDK fetch fails → exit 1, no state files modified
- `claude -p` fails → exit 1, no state files modified
- Empty summary from claude → exit 1
- commit_and_push fails → non-zero exit, warning printed

**State transition:**

- State files updated only after successful summary generation
- `--dry-run` → no files written, no state files modified, no commit
- Idempotency: running twice on same day skips (output file already exists)

**Both-branches:**

- State file present vs absent (first run)

## Out of Scope

- Claude Apps help center release notes (support.claude.com — JS-heavy, no clean extraction path)
- Anthropic blog/news (no RSS feed, JS-heavy)
- TypeScript/Node.js SDK CHANGELOG (Python SDK covers the same API surface)
