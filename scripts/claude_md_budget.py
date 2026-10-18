#!/usr/bin/env python3
"""Refuse a revision whose CLAUDE.md exceeds the byte ceiling.

Usage: claude_md_budget.py <rev>

Exit 0: CLAUDE.md absent at <rev>, or at most CEILING bytes.
Exit 1: CLAUDE.md larger than CEILING bytes.
Exit 2: usage error or a git failure (unknown revision, unreadable object).

Size is measured in bytes, not characters. There is deliberately no flag,
environment variable or commit trailer that skips or changes the ceiling.
"""

import subprocess
import sys

# Set by ADR-0047 from the spec's dry runs; raising it needs an amendment to that ADR.
CEILING = 105_000


def _git(*args: str) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["git", *args],
        capture_output=True,
        stdin=subprocess.DEVNULL,
        check=False,
    )


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: claude_md_budget.py <rev>", file=sys.stderr)
        return 2
    rev = argv[0]

    listing = _git("ls-tree", rev, "--", "CLAUDE.md")
    if listing.returncode != 0:
        sys.stderr.write(listing.stderr.decode("utf-8", errors="replace"))
        return 2
    if not listing.stdout.strip():
        return 0

    shown = _git("show", f"{rev}:CLAUDE.md")
    if shown.returncode != 0:
        sys.stderr.write(shown.stderr.decode("utf-8", errors="replace"))
        return 2

    size = len(shown.stdout)
    if size > CEILING:
        print(f"CLAUDE.md is {size} bytes, ceiling {CEILING}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
