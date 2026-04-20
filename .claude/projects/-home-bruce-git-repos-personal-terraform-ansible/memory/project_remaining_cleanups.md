---
name: Remaining role cleanups
description: 22 roles have dead env-detection code, 21 have stub verify.yml files — potential future batch cleanup
type: project
originSessionId: 1849ac56-b366-4acc-a759-3bf934f8700b
---

Two remaining cleanup patterns across the codebase (as of 2026-04-20):

**Dead environment-detection code: DONE (PR #38).** Removed from 21 roles. The `common` role was excluded — it actually uses `common_is_bare_metal_environment` to gate bare-metal package installation (discovered when molecule test failed during verification).

**Stub verify.yml files (21 roles):** uptime_kuma, teleport_server, teleport_node, prometheus_node_exporter, plex_server, nut_server, nut_client, nodejs, netdata, lb, kind, k3s, homepage, heimdall, fah, emotive_users, downloads, docker_server_mounts, dashy, cloudflared_server, apt_cacher_ng. Each just asserts `true` with a TODO comment.

**Why:** These are technical debt — the dead code wastes ~110 lines per role and the stub verifies provide no test coverage. Both patterns have established fixes (bind_server is the template for verify, teleport for dead code removal).

**How to apply:** Could be batched into 1-2 PRs. Dead code removal is purely mechanical. Verify assertions require reading each role's tasks to know what to assert on.
