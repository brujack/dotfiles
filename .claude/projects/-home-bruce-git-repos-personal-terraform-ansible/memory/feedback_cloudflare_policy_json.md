---
name: Cloudflare v5 access policy JSON structure in Terraform plan output
description: Policy include/require rules serialise as flat objects with all rule type keys present; everyone={} not null for bypass
type: feedback
originSessionId: afe40797-6af6-4b15-9aea-73e3f52ca23b
---

When asserting Cloudflare Zero Trust access policy attributes from `rc.Change.After` in Terratest,
the policy JSON structure is:

```json
"policies": [
  {
    "decision": "allow",
    "include": [
      {
        "geo": {"country_code": "CA"},
        "email": null,
        "everyone": null,
        ... (all other rule type keys present as null)
      }
    ],
    "require": [
      {
        "email": {"email": "bjackson@pobox.com"},
        "geo": null,
        "everyone": null,
        ...
      }
    ]
  }
]
```

**Key gotchas:**

- Every include/require rule object contains ALL possible rule type keys — only the active one is
  non-null. Type-assert the specific key you care about (e.g. `rule["geo"].(map[string]interface{})`)
  rather than checking for key existence.
- `everyone` bypass rule serialises as `{}` (empty map), not `null`. Use `assert.NotNil` to verify.
- Extract geo country codes with `ElementsMatch` since rule order is not guaranteed.

**How to apply:** Use this pattern when writing Terratest assertions for ZT access policies:

```go
includes := policy["include"].([]interface{})
var codes []string
for _, inc := range includes {
    rule := inc.(map[string]interface{})
    if geo, ok := rule["geo"].(map[string]interface{}); ok {
        codes = append(codes, geo["country_code"].(string))
    }
}
assert.ElementsMatch(t, []string{"CA", "US"}, codes)
```
