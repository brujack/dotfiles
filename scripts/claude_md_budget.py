#!/usr/bin/env python3
"""Refuse a revision whose CLAUDE.md exceeds the byte ceiling.

Usage: claude_md_budget.py <rev>

Exit 0: CLAUDE.md absent at <rev>, or a regular file of at most CEILING bytes.
Exit 1: CLAUDE.md larger than CEILING bytes, or not a regular file (symlink,
        submodule, directory, other mode).
Exit 2: usage error or a git failure (unknown revision, unreadable object).

Size is measured in bytes, not characters. There is deliberately no flag,
environment variable or commit trailer that skips or changes the ceiling.
"""

import os
import subprocess
import sys

# Set by ADR-0047 from the spec's dry runs; raising it needs an amendment to that ADR.
CEILING = 105_000

_REGULAR_MODES = ("100644", "100755")
_MODE_DESCRIPTIONS = {
    "120000": "a symlink",
    "160000": "a submodule",
    "040000": "a directory",
}
_MODE_REMEDY = "Commit CLAUDE.md as a regular file."
_GIT_VARS = ("GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE")


def _git(*args: str) -> subprocess.CompletedProcess[bytes]:
    # A hook-exported GIT_DIR would override the repository found from the cwd.
    env = {k: v for k, v in os.environ.items() if k not in _GIT_VARS}
    return subprocess.run(
        ["git", *args],
        capture_output=True,
        stdin=subprocess.DEVNULL,
        env=env,
        check=False,
    )


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: claude_md_budget.py <rev>", file=sys.stderr)
        return 2
    rev = argv[0]

    # --full-tree: without it ls-tree is relative to the cwd, so a run from a
    # subdirectory would find no CLAUDE.md and pass.
    listing = _git("ls-tree", "--full-tree", rev, "--", "CLAUDE.md")
    if listing.returncode != 0:
        sys.stderr.write(listing.stderr.decode("utf-8", errors="replace"))
        return 2
    entry = listing.stdout.decode("utf-8", errors="replace").strip()
    if not entry:
        print(f"CLAUDE.md absent at {rev}; nothing to measure.")
        return 0

    # "<mode> <type> <sha>\tCLAUDE.md". `git show rev:CLAUDE.md` on a symlink
    # returns the link target path, so only a regular file may be sized.
    mode = entry.split(maxsplit=1)[0]
    if mode not in _REGULAR_MODES:
        kind = _MODE_DESCRIPTIONS.get(mode)
        description = f"{kind} (git mode {mode})" if kind else f"git mode {mode}"
        print(
            f"CLAUDE.md at {rev} must be a regular file, but it is {description}. "
            f"{_MODE_REMEDY}",
            file=sys.stderr,
        )
        return 1

    shown = _git("show", f"{rev}:CLAUDE.md")
    if shown.returncode != 0:
        sys.stderr.write(shown.stderr.decode("utf-8", errors="replace"))
        return 2

    size = len(shown.stdout)
    if size > CEILING:
        print(f"CLAUDE.md is {size} bytes, ceiling {CEILING}", file=sys.stderr)
        return 1
    print(f"CLAUDE.md at {rev} is {size} bytes (ceiling {CEILING}).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
