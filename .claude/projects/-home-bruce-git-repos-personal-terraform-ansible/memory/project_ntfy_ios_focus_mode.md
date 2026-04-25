---
name: ntfy iOS Focus Mode gotcha
description: ntfy notifications silently blocked by iPhone Personal Focus mode — check allowed apps before troubleshooting infrastructure
type: project
originSessionId: afe40797-6af6-4b15-9aea-73e3f52ca23b
---

When ntfy notifications stop working on iPhone, check iOS Focus Mode (Settings → Focus → Personal → Allowed Apps) before debugging server infrastructure. ntfy must be explicitly added to the allowed apps list or notifications are silently dropped.

**Why:** Lost 1.5h troubleshooting server config (upstream-base-url, etc.) when the actual cause was a phone setting. The server was working correctly the entire time.

**How to apply:** If ntfy notifications stop working after an iPhone iOS update, Focus Mode change, or phone restore, check allowed apps first — before touching ansible roles, ntfy config, or Cloudflare tunnels.
