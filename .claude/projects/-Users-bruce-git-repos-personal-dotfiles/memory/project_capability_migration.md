---
name: macOS + Linux capability migration complete
description: Both capability migration specs implemented and merged to master; next pending spec is mas-brewfile-integration
type: project
---

Both specs merged to master on 2026-04-07 (PR #4):
- `2026-04-05-macos-setup-capability-migration-design.md` — done
- `2026-04-05-linux-setup-capability-migration-design.md` — done

**Why:** Migrate setup_env.sh from deprecated hostname vars to HAS_* capability vars; introduce wsl2_workstation profile for cruncher.

**Next:** All three specs complete. No pending migration work.
