---
name: GitHub Actions security and output patterns
description: Three required patterns for GitHub Actions workflows in this repo — expression injection prevention, GITHUB_OUTPUT delimiter, and action body quoting
type: feedback
originSessionId: b2beea3f-133e-4d51-9337-b4ce23d640fd
---

## Rule 1: Use env vars for workflow inputs in `run:` blocks

Never interpolate `${{ inputs.* }}` or `${{ github.* }}` directly into a `run:` shell script. Pass through an `env:` block instead.

**Wrong:**

```yaml
run: git tag "pi-v${{ inputs.version }}"
```

**Correct:**

```yaml
env:
  VERSION: ${{ inputs.version }}
run: git tag "pi-v${VERSION}"
```

**Why:** GitHub Actions evaluates expressions before the shell runs, so a malicious input like `"; rm -rf /; echo "` executes as shell. Even on personal repos with restricted dispatch access, this is the recommended pattern per GitHub's own security guidance.

**How to apply:** Any `run:` block that uses a workflow input or user-controlled expression must route through `env:`.

---

## Rule 2: Use randomized delimiter for GITHUB_OUTPUT multiline values

Never use a fixed `EOF` delimiter in `$GITHUB_OUTPUT` heredocs.

**Wrong:**

```bash
echo 'notes<<EOF'
echo "$NOTES"
echo 'EOF'
```

**Correct:**

```bash
DELIMITER="EOF_$(openssl rand -hex 8)"
{
  printf 'notes<<%s\n' "${DELIMITER}"
  printf '%s\n' "${NOTES}"
  printf '%s\n' "${DELIMITER}"
} >> "$GITHUB_OUTPUT"
```

**Why:** If any line of the output (e.g. a commit message) contains the literal string `EOF`, it terminates the multiline value prematurely and silently truncates or corrupts subsequent output. A random suffix makes this impossible.

**How to apply:** Every multiline `$GITHUB_OUTPUT` write in this repo uses the randomized delimiter pattern.

---

## Rule 3: Quote `body:` in softprops/action-gh-release

```yaml
# Wrong
body: ${{ steps.notes.outputs.notes }}

# Correct
body: "${{ steps.notes.outputs.notes }}"
```

**Why:** Release notes may contain YAML special characters (colons, brackets, leading dashes). Unquoted, the YAML parser misreads the value. Quoted, the value passes through correctly.

**How to apply:** Any `softprops/action-gh-release` step that uses an expression for `body:` must quote it.
