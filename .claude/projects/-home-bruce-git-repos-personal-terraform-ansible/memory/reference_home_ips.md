---
name: Home ISP IP addresses
description: Bell and Rogers WAN IPs for conecrazy.ca DNS records; pfSense DYNDNS causes drift
type: reference
originSessionId: afe40797-6af6-4b15-9aea-73e3f52ca23b
---

Home has dual ISP (Bell primary, Rogers secondary). pfSense DYNDNS updates Cloudflare A records
dynamically, so `dns.tf` will drift whenever the WAN IP changes — run `terraform plan` to check.

Known IPs (as of 2026-04-26):

- Bell (primary): `184.147.129.245`
- Rogers (secondary): `174.116.120.53`

Affected records: `cloudflare_dns_record.conecrazy_ca` and `cloudflare_dns_record.home_conecrazy_ca`

**Note:** When `terraform plan` shows drift on these two records, it's likely pfSense picked up a
new IP. Update `dns.tf` to match the desired primary before applying.
