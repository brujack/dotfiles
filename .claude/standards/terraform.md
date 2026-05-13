## Terraform

### Linting

```bash
terraform fmt        # format check
tflint               # static analysis
checkov              # security/compliance scan (no credentials required)
```

All three run via `make lint`. `terraform validate` requires credentials and runs separately.

### Idempotency

- Resources declare desired state by design — do not work around this with `local-exec` provisioners that have side effects
- `local-exec` and `remote-exec` provisioners are not idempotent; avoid them except for bootstrapping that cannot be expressed as state
- Data sources are always safe; prefer them over provisioners for read operations

### Terratest

Use `terraform.InitAndPlanAndShowWithStructNoLogTempPlanFile` for a typed `*terraform.PlanStruct`. Standard test structure:

1. Assert **no destructive actions** (`Delete()`, `Replace()`) on any resource
2. Assert the **exact set of managed resources** via an `expected*` map — catches unintended additions and removals
3. Assert **key attributes** from `rc.Change.After`

**`*terraform.PlanStruct` API:**

- Iterate resources with `plan.RawPlan.ResourceChanges` (slice of `*tfjson.ResourceChange`)
- Look up by address with `plan.ResourceChangesMap` (map) — do NOT use `plan.ResourceChanges` directly, that field does not exist
- Destructive action checks: `rc.Change.Actions.Delete()` / `rc.Change.Actions.Replace()` — no `Is` prefix (terraform-json ≥ v0.13.0)

**Check block assertions** (requires terraform-json ≥ v0.23.0):

Always assert count before iterating — a loop over an empty `Checks` slice passes vacuously:

```go
assert.NotEmpty(t, plan.RawPlan.Checks)
for _, c := range plan.RawPlan.Checks {
    assert.Equal(t, tfjson.CheckStatusPass, c.Status)
}
```

**Nested block encoding in plan JSON:**

Single-instance HCL blocks (`cpu {}`, `memory {}`, `disk {}`) are encoded as `[]interface{}` — a one-element slice of `map[string]interface{}`. All JSON numbers unmarshal to `float64`. Use typed helper functions to extract nested block values rather than repeated type assertions inline.

**Top-level list attributes** (e.g. `tags`) appear directly as `[]interface{}`. Use `assert.ElementsMatch` for order-independent comparison.
