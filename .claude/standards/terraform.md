## Terraform

### Idempotency

- Resources declare desired state by design — do not work around this with `local-exec` provisioners that have side effects
- `local-exec` and `remote-exec` provisioners are not idempotent; avoid them except for bootstrapping that cannot be expressed as state
- Data sources are always safe; prefer them over provisioners for read operations
