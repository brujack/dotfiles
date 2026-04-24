---
name: Cloudflare Access bypass policy for unauthenticated services
description: Services that need unauthenticated access (e.g. ntfy) require an explicit bypass Access application, otherwise wildcard *.conecrazy.ca ZT policies block them
type: project
---

Any service exposed through the Cloudflare tunnel that needs unauthenticated access (WebSocket/SSE subscriptions, public APIs, etc.) must have an explicit `cloudflare_zero_trust_access_application` with `decision = "bypass"`. Without it, a wildcard `*.conecrazy.ca` Access application in the ZT org will intercept and block the traffic.

A bypass policy takes precedence over wildcard policies for the specific subdomain.

**Why:** ntfy iOS/macOS app requires unauthenticated long-lived SSE/WebSocket connections to subscribe to topics. CF Access intercepts these before they reach ntfy.

**How to apply:** Add to `cloudflare/conecrazy_ca.tf`:

```hcl
resource "cloudflare_zero_trust_access_application" "service_conecrazy_ca" {
  app_launcher_visible       = false
  auto_redirect_to_identity  = false
  domain                     = "service.${local.zone}"
  enable_binding_cookie      = false
  http_only_cookie_attribute = false
  name                       = "service"
  session_duration           = "0s"
  skip_interstitial          = true
  type                       = "self_hosted"
  zone_id                    = cloudflare_zone.cf_zone.id

  policies = [
    {
      name       = "bypass"
      decision   = "bypass"
      precedence = 1
      include    = [{ everyone = {} }]
    }
  ]
}
```
