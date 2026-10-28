# softwareupdate fixtures

Real captured output; never hand-edited.

## list-restart-pending.txt

- Captured 2026-10-28 on the Studio (macOS 27.0.1), unprivileged: `softwareupdate -l 2>/dev/null` over ssh. rc 0.
- One update pending that needs a restart (`Action: restart`). Stdout carries the tool's header lines and a tab-indented `Title:` line around the one `* Label:` line, which is what `_update_softwareupdate_labels` filters.
