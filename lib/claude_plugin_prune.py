#!/usr/bin/env python3
"""Prune redundant project/local records from Claude's installed_plugins.json.

A project or local record is removed only when its plugin also has a user-scope
record that is at least as new (see the design spec, section "Record prune").
Runs on Python 3.9: timestamps are parsed with an explicit format because
datetime.fromisoformat rejects a trailing "Z" before 3.11.

Exit codes: 0 done or nothing to do, 3 refused, 4 file changed during prune.
Prints exactly one stdout line.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from datetime import datetime, timezone

_TS_FORMAT = "%Y-%m-%dT%H:%M:%S.%fZ"
_BACKUP_PREFIX = "installed_plugins-"
_BACKUP_SUFFIX = ".json"
_PRUNABLE_SCOPES = ("project", "local")
_CHANGED_LINE = "skipped: plugins file changed during prune"


def parse_ts(s):
    """Return a datetime for a "...%f Z" timestamp, or None if absent or invalid."""
    if not isinstance(s, str):
        return None
    try:
        return datetime.strptime(s, _TS_FORMAT)
    except ValueError:
        return None


def should_remove(record, user_record):
    """True when a project/local record is redundant given the plugin's user record."""
    if user_record is None or record.get("scope") not in _PRUNABLE_SCOPES:
        return False
    # Equal versions decide first: no timestamp is read.
    mine_v, user_v = record.get("version"), user_record.get("version")
    if _nonempty_str(mine_v) and _nonempty_str(user_v) and mine_v == user_v:
        return True
    mine = parse_ts(record.get("lastUpdated"))
    theirs = parse_ts(user_record.get("lastUpdated"))
    if mine is None or theirs is None:
        return False
    return theirs >= mine


def _refuse(reason):
    return 3, "refused: " + reason


def _prune_records(plugins):
    """Return (new plugins map, removed count, kept count)."""
    new_plugins = {}
    removed = kept = 0
    for plugin_id, records in plugins.items():
        if not isinstance(records, list):
            new_plugins[plugin_id] = records
            continue
        user_record = next(
            (r for r in records if isinstance(r, dict) and r.get("scope") == "user"), None
        )
        survivors = []
        for r in records:
            if isinstance(r, dict) and should_remove(r, user_record):
                removed += 1
            else:
                survivors.append(r)
                kept += 1
        new_plugins[plugin_id] = survivors
    return new_plugins, removed, kept


def _nonempty_str(v):
    return isinstance(v, str) and v != ""


def _write_backup(raw, backup_dir, stamp):
    """Write the bytes already read from the plugins file; return the backup path."""
    os.makedirs(backup_dir, exist_ok=True)
    dest = os.path.join(backup_dir, _BACKUP_PREFIX + stamp + _BACKUP_SUFFIX)
    try:
        with open(dest, "wb") as dst:
            dst.write(raw)
    except OSError:
        # Cleanup only: a truncated backup must not look like a real one.
        _remove_quietly(dest)
        raise
    return dest


def _trim_backups(backup_dir, keep):
    """Best-effort retention after a successful replace: a failure here is cleanup only."""
    try:
        listing = os.listdir(backup_dir)
    except OSError:
        return
    names = sorted(
        n for n in listing if n.startswith(_BACKUP_PREFIX) and n.endswith(_BACKUP_SUFFIX)
    )
    for n in names[: max(0, len(names) - keep)]:
        try:
            os.remove(os.path.join(backup_dir, n))
        except OSError:
            pass


def _signature(st):
    return (st.st_mtime_ns, st.st_ino, st.st_size)


def _remove_quietly(path):
    """Cleanup of this run's own artefact; a failure must not skip later cleanup."""
    try:
        os.remove(path)
    except OSError:
        pass


def prune(path, backup_dir, keep, dry_run, before_restat=None):
    """Prune `path`. Returns (exit_code, stdout_line).

    Race guard: mtime, inode and size of the resolved file and of the link path itself are compared before reading and again just
    before os.replace. A write landing between that re-stat and os.replace is
    still lost; this cannot be closed without a lock Claude Code does not take.
    Any OSError becomes a refusal (exit 3) and leaves the plugins file as it was;
    pruning never proceeds without a backup.
    """
    if keep < 1:
        raise ValueError("keep must be at least 1")
    try:
        return _prune(path, backup_dir, keep, dry_run, before_restat)
    except OSError as exc:
        return _refuse("%s" % exc)


def _prune(path, backup_dir, keep, dry_run, before_restat):
    # Resolve a symlinked plugins file so the temp file and the replace target
    # live beside the real file and the link survives.
    real = os.path.realpath(path)
    try:
        before = os.stat(real)
        link_before = os.lstat(path)
    except FileNotFoundError:
        return 0, "no plugins file"
    now = datetime.now(timezone.utc)
    with open(real, "rb") as f:
        raw = f.read()
    try:
        data = json.loads(raw)
    except ValueError as exc:
        return _refuse("cannot parse plugins file: %s" % exc)
    if not isinstance(data, dict):
        return _refuse("plugins file is not a JSON object")
    if data.get("version") != 2:
        return _refuse("unsupported plugins file version %r" % (data.get("version"),))
    plugins = data.get("plugins")
    if not isinstance(plugins, dict):
        return _refuse("no plugins object")

    new_plugins, removed, kept = _prune_records(plugins)
    line = "pruned at %s: removed %d, kept %d" % (now.strftime("%Y-%m-%dT%H:%M:%SZ"), removed, kept)
    if removed == 0 or dry_run:
        return 0, line

    backup = _write_backup(raw, backup_dir, now.strftime("%Y%m%dT%H%M%S%fZ"))
    tmp = None
    try:
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(real), suffix=".tmp")
        new_data = dict(data)
        new_data["plugins"] = new_plugins
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(new_data, f, indent=2, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, before.st_mode & 0o7777)
        if before_restat is not None:
            before_restat()
        try:
            changed = (
                _signature(os.stat(real)) != _signature(before)
                or _signature(os.lstat(path)) != _signature(link_before)
            )
        except FileNotFoundError:
            changed = True
        if changed:
            _remove_quietly(tmp)
            _remove_quietly(backup)
            return 4, _CHANGED_LINE
        os.replace(tmp, real)
    except (OSError, ValueError, TypeError) as exc:
        # Cleanup, then report: the plugins file was not replaced.
        if tmp is not None:
            _remove_quietly(tmp)
        _remove_quietly(backup)
        return _refuse("cannot write plugins file: %s" % exc)
    _trim_backups(backup_dir, keep)
    return 0, line


def _keep_arg(value):
    n = int(value)
    if n < 1:
        raise argparse.ArgumentTypeError("--keep must be at least 1")
    return n


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--file", required=True)
    parser.add_argument("--backup-dir", required=True)
    parser.add_argument("--keep", type=_keep_arg, default=5)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    code, line = prune(args.file, args.backup_dir, args.keep, args.dry_run)
    print(line)
    return code


if __name__ == "__main__":
    sys.exit(main())
