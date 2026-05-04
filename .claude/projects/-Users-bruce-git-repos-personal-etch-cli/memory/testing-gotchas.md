---
name: Testing gotchas
description: Non-obvious testing pitfalls specific to etch-cli discovered during coverage work
type: project
originSessionId: a4242489-88b7-4c64-a990-e129cc91fc71
---

**normpath::normalize() requires path existence on macOS**
`normpath::normalize()` calls `fs::canonicalize()` on macOS/Linux, which requires the path to exist. Tests using `DirectoryAction::resolve()` (which calls `normalize()` internally) must create the directory first or the test panics with "Failed to resolve path".

**Why:** Discovered when writing `plan_appends_slash_dot_when_to_ends_with_slash` test for `directory/copy.rs`.

**How to apply:** Before calling any action's `plan()` that resolves a `files/<path>` directory, create `tmp.path().join("files").join(the_path)` first.

---

**mlua `pairs::<i64, LuaValue>().count()` includes conversion errors**
When iterating a Lua table with `pairs::<i64, LuaValue>()`, keys that fail the `i64` conversion yield `Err` items — and `Iterator::count()` still counts them. So `count() == 0` is never true for a non-empty string-keyed table. This was the root cause of the `lua_value_to_json` object detection bug.

**Why:** Discovered via coverage analysis showing lines 35-42 of `utilities/lua.rs` were unreachable.

**How to apply:** To distinguish array tables from object tables in mlua, use `sequence_values::<LuaValue>()` (iterates only consecutive integer keys from 1) instead of counting `pairs::<i64>()`.

---

**`tracing-test` crate for asserting log content**
Added `tracing-test = "0.2"` and `tracing-subscriber = "0.3"` as dev deps in `lib/Cargo.toml`. Use `#[traced_test]` + `logs_contain(msg)` to assert error messages in logging paths. Used in `manifests/load.rs` to verify Tera render failures produce useful error messages.

---

**CI tarpaulin threshold is ≥65%, not ≥79%**
The CI job runs `cargo tarpaulin --fail-under 65`. The higher local figure (~79%) includes macOS-only tests. Never raise the CI gate above 65 without verifying Linux coverage first.
