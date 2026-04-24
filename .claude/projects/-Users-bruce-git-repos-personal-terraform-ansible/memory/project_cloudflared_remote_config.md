---
name: cloudflared uses remote API config, not local ingress rules
description: When a cloudflare tunnel is configured via ZT dashboard, cloudflared ignores local config.yml ingress rules and polls the Cloudflare API instead
type: project
---

cloudflared tunnel on bastion uses **remotely managed config** polled from the Cloudflare API. The local `/etc/cloudflared/config.yml` only carries tunnel credentials (tunnel ID + credentials-file path). Any ingress rules written into config.yml are silently ignored.

Symptom: config.yml shows the right ingress rules, cloudflared is restarted, requests still return 404. The journalctl "Updated to new configuration" log line shows the actual loaded config — if ingress rules differ from config.yml, it's using remote API config.

**Why:** The tunnel was originally configured through the Cloudflare ZT dashboard, which switches cloudflared to remote-managed mode.

**How to apply:** All tunnel ingress rules must be managed via `cloudflare_zero_trust_tunnel_cloudflared_config` in Terraform (`cloudflare/conecrazy_ca.tf`). Never add ingress rules to the Ansible config.yml template — they won't be loaded. Import ID format: `<account_id>/<tunnel_id>`.
