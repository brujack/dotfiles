---
name: Terratest plan JSON numbers deserialise as float64
description: In Go, terraform-json Change.After values use float64 for all numbers — use float64 in assertions
type: feedback
originSessionId: afe40797-6af6-4b15-9aea-73e3f52ca23b
---

When asserting numeric attributes from `rc.Change.After.(map[string]interface{})` in Terratest,
all JSON numbers deserialise as `float64`, not `int`.

**Why:** Go's `encoding/json` unmarshals numbers into `interface{}` as `float64` by default.

**How to apply:** Use `float64` literals in expected values for any numeric plan attribute —
e.g. MX priority, port numbers, counts:

```go
type mxSpec struct {
    content  string
    priority float64  // not int
}
// ...
{content: "aspmx.l.google.com", priority: 1}  // not priority: 1
```

Applies to all `assert.Equal` calls against `Change.After` map values in cloudflare and proxmox tests.
