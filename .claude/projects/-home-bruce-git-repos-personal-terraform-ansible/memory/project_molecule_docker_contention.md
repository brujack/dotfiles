---
name: Molecule parallel tests starve Docker on workstation
description: Running the full molecule matrix (6 parallel jobs) consumes enough Docker resources to pause/restart other containers on the workstation
type: project
originSessionId: 402fec12-b704-4e7e-8098-742ab5b711ad
---

The pre-push hook and `make test-ci` run 30 molecule roles at 6 parallel jobs by default. Each job spins up a Docker container with systemd. This is heavy enough to starve other Docker containers running on the same machine (they stop and eventually restart).

**Why:** The workstation runs production-like Docker services alongside development. The molecule matrix saturates Docker daemon resources (CPU, memory, network).

**How to apply:** Warn the user before triggering a full molecule run that their containers will be disrupted briefly. If they need to avoid disruption, suggest `PARALLEL_JOBS=2 make test-ci` or `make test-ci-seq` (sequential) to reduce contention. Also relevant: the pre-push hook always runs the full matrix on any `ansible/` change, so pushing from the workstation will cause this.
