---
name: Docker file-level bind mounts track inodes — mount the directory instead
description: Mounting a single file into a container breaks when Ansible atomically rewrites it; the container keeps the old inode
type: feedback
---

Docker file-level bind mounts (e.g. `/opt/ntfy/server.yml:/etc/ntfy/server.yml:ro`) track the inode of the file at mount time. When Ansible's `template` module writes a new version (atomic rename → new inode), the container still sees the old inode's content even though `cat` on the host shows the new content.

**Why:** Ansible template writes to a temp file then renames — new inode. Docker bind mount keeps pointing at the original inode. Host reads via filename (new inode); container reads via mount (old inode). Restart resolves it but is easy to miss.

**How to apply:** Always mount the parent directory in docker-compose, not a single file:

```yaml
# Wrong — inode staleness
- /opt/ntfy/server.yml:/etc/ntfy/server.yml:ro

# Right — directory mount, inode-independent
- /opt/ntfy:/etc/ntfy:ro
```

Any time a Docker volume mounts a single file that Ansible manages via `template`, switch to directory mount.
