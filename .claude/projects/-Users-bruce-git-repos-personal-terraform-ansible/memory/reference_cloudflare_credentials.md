---
name: Cloudflare Terraform credentials
description: Where to find the Cloudflare API token for terraform runs in cloudflare/
type: reference
---

Cloudflare API token is in `~/.cloudflared/.tf_cloudflare_creds` (exports `CLOUDFLARE_API_TOKEN`).

Must be sourced before any terraform command:

```bash
source ~/.cloudflared/.tf_cloudflare_creds && make plan
source ~/.cloudflared/.tf_cloudflare_creds && make apply
```

The `make plan` target runs tflint + tfsec + terraform plan and saves the plan to `terraform-plan`. `make apply` applies that saved plan.
