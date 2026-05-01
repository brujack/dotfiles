---
name: Bash version string comparison pitfall
description: Lexicographic < inside [[ ]] gives wrong results for semver strings; always extract integer minor and use -lt/-gt
type: feedback
---

Do NOT compare semver strings like `"1.16"` with `[[ ${VER} < "1.21" ]]`. Bash `[[` uses lexicographic order: `"1.16" < "1.21"` is **false** because at position 3, `'6' > '2'` in ASCII. The expression silently produces the wrong branch dispatch.

**Why:** Caught during `_install_ubuntu_go` refactor (PR #69). The plan code had `[[ ${GO_VER} < "1.21" ]]`; fixing it to `[[ ${_minor} -lt 21 ]]` required extracting the integer minor version first via `cut -d. -f2`.

**How to apply:** For any version-gated branch, extract the integer component and use `-lt`/`-gt`/`-eq`:

```bash
local _minor
_minor=$(printf '%s' "${VER}" | cut -d. -f2)
if [[ ${_minor} -lt 21 ]]; then ...
```

Never rely on `<`/`>` string operators for version numbers where any digit exceeds 9 in a component before the split point, or where minor versions are two digits.
