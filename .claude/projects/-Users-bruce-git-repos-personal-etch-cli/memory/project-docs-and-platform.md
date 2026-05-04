---
name: docs/src and platform support notes
description: docs/src is inherited mdbook not built in CI; checklist for dropping platform support
type: project
---

**docs/src/ is inherited from comtrya and not built in CI**
The `docs/src/` directory is mdbook source inherited from the comtrya upstream. It is not compiled or validated in CI. It can drift silently — treat it as best-effort documentation that needs manual review when making changes. There is no CI gate catching stale content there.

**Why:** Discovered when Windows cleanup found four docs files still referencing Windows/winget/FreeBSD/NetBSD after those platforms were dropped in Phase 3.

**How to apply:** When making any behavioral or platform change, explicitly check `docs/src/` for stale references. Don't assume CI would have caught it.

---

**Checklist for dropping platform support**
When removing support for a platform (e.g., Windows), these locations need checking beyond the obvious provider files:

1. `#[cfg(not(target_os))]` stubs in atoms and actions — these are no-op fallbacks left for the removed platform
2. `#[cfg(target_os)]` guards on test imports and test functions — need to be removed to make tests unconditional
3. Import guards — `#[cfg(unix)] use crate::atoms::file::Chown` etc.
4. `Cargo.toml` — `[target.'cfg(unix)'.dependencies]` section; calling those crates unconditionally is fine if the project is now unix-only
5. `docs/src/` — package tables, supported-systems lists, variant examples, privilege escalation descriptions
6. README.md and CLAUDE.md — platform support claims

**Why:** Phase 3 removed 11 provider files but left `#[cfg(not(unix))]` stubs in five files. The stubs were no-ops but compiled dead code with no-op behavior, and the docs still listed Windows/winget/FreeBSD/NetBSD as supported.

---

**Comtrya heritage cleanup — complete as of 2026-05-04**
The following comtrya-origin files were removed as not applicable to this fork:
`shell.nix`, `Justfile`, `check.sh`, `.trunk/`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `.vscode/settings.json`

When inheriting any forked project, these file types commonly reference the upstream community and go stale immediately: `CONTRIBUTING.md` (tool refs, maintainer Discord handles), `CODE_OF_CONDUCT.md` (community name), `.vscode/settings.json` (schema URLs), meta-linter configs (`.trunk/`, stale version pins), and dev-shell files (`shell.nix`, `Justfile`) for toolchains the fork doesn't use.
