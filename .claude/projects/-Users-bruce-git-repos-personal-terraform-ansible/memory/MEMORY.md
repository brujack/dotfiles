# Memory Index

- [AWS Terraform future work](project_aws_terraform.md) — aws-terraform/ directory is planned for a future session after ansible improvements
- [Always run pr-review skill before pushing](feedback_pr_review.md) — pr-review must be invoked before every push/PR in this repo; was skipped on cloudflare-v5-migration
- [cloudflared uses remote API config, not local ingress rules](project_cloudflared_remote_config.md) — local config.yml ingress is ignored; all tunnel routes managed via cloudflare_zero_trust_tunnel_cloudflared_config in Terraform
- [Cloudflare Access bypass pattern for unauthenticated services](project_cf_access_bypass_pattern.md) — services needing unauthenticated access need explicit bypass ZT application or wildcard policy blocks them
- [Cloudflare Terraform credentials](reference_cloudflare_credentials.md) — source ~/.cloudflared/.tf_cloudflare_creds before every terraform command
