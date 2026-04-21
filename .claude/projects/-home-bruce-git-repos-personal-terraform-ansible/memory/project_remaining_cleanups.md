---
name: Remaining role cleanups
description: All stub verify.yml roles done — no remaining cleanup work
type: project
originSessionId: 53884645-837c-4251-ac1c-d04814df0368
---

**Dead environment-detection code: DONE (PR #38).** Removed from 21 roles.

**Stub verify.yml — Batch 1 (Docker Compose roles): DONE (PR #39).** 5 roles.

**Stub verify.yml — Batch 2 (service + config roles): DONE (PR #40).** 7 roles.

**Stub verify.yml — Batch 3 (remaining 9 roles): DONE (PR pending).** 9 roles.
docker_server_mounts (local-only, needs NFS guard var), downloads, emotive_users (idempotence fixed), k3s, kind, netdata, nodejs, teleport_node, teleport_server.

**Also fixed:** emotive_users idempotence — added re-stat after git clone so find+chown pattern runs on first converge. docker_server_mounts now testable in molecule via `docker_server_mounts_nfs_enabled: false` guard.

**How to apply:** All stub verify work is complete. No remaining role cleanups needed.
