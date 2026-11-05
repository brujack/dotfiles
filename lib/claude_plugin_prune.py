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
    if record.get("version") == user_record.get("version"):
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


def _write_backup(path, backup_dir, stamp):
    os.makedirs(backup_dir, exist_ok=True)
    name = _BACKUP_PREFIX + stamp + _BACKUP_SUFFIX
    dest = os.path.join(backup_dir, name)
    with open(path, "rb") as src, open(dest, "wb") as dst:
        dst.write(src.read())


def _trim_backups(backup_dir, keep):
    names = sorted(
        n
        for n in os.listdir(backup_dir)
        if n.startswith(_BACKUP_PREFIX) and n.endswith(_BACKUP_SUFFIX)
    )
    excess = names[: max(0, len(names) - max(keep, 0))]
    for n in excess:
        os.remove(os.path.join(backup_dir, n))


def prune(path, backup_dir, keep, dry_run, before_restat=None):
    """Prune `path`. Returns (exit_code, stdout_line)."""
    try:
        before = os.stat(path)
    except FileNotFoundError:
        return 0, "no plugins file"
    now = datetime.now(timezone.utc)
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError) as exc:
        return _refuse("cannot read plugins file: %s" % exc)
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

    _write_backup(path, backup_dir, now.strftime("%Y%m%dT%H%M%S%fZ"))
    _trim_backups(backup_dir, keep)

    new_data = dict(data)
    new_data["plugins"] = new_plugins
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(path)), suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(new_data, f, indent=2)
            f.write("\n")
        os.chmod(tmp, before.st_mode & 0o7777)
        if before_restat is not None:
            before_restat()
        try:
            after = os.stat(path)
        except FileNotFoundError:
            os.remove(tmp)
            return 4, _CHANGED_LINE
        if (after.st_mtime_ns, after.st_ino) != (before.st_mtime_ns, before.st_ino):
            os.remove(tmp)
            return 4, _CHANGED_LINE
        os.replace(tmp, path)
    except BaseException:
        # Cleanup only: never leave a temp file behind, then re-raise.
        if os.path.exists(tmp):
            os.remove(tmp)
        raise
    return 0, line


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--file", required=True)
    parser.add_argument("--backup-dir", required=True)
    parser.add_argument("--keep", type=int, default=5)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    code, line = prune(args.file, args.backup_dir, args.keep, args.dry_run)
    print(line)
    return code


if __name__ == "__main__":
    sys.exit(main())
