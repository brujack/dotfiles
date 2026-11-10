import errno
import importlib.util
import json
import os
import re
import shutil
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path

_REPO = Path(__file__).resolve().parent.parent
_MODULE = _REPO / "lib" / "claude_plugin_prune.py"


def _load():
    spec = importlib.util.spec_from_file_location("claude_plugin_prune", _MODULE)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["claude_plugin_prune"] = module
    spec.loader.exec_module(module)
    return module


P = _load()

OLD = "2026-09-01T00:00:00.000Z"
USER_TS = "2026-10-01T00:00:00.000Z"
NEW = "2026-10-15T00:00:00.000Z"


_LIVE_ROOT = None


def setUpModule():
    global _LIVE_ROOT
    _LIVE_ROOT = tempfile.mkdtemp()
    for name in ("p1", "p2", "p3", "p4", "p"):
        os.mkdir(os.path.join(_LIVE_ROOT, name))


def tearDownModule():
    shutil.rmtree(_LIVE_ROOT, ignore_errors=True)


def live(name):
    return os.path.join(_LIVE_ROOT, name)


def rec(scope, version, ts=USER_TS, **extra):
    r = {"scope": scope, "version": version, "installPath": "/x/" + version}
    if ts is not None:
        r["lastUpdated"] = ts
    r.update(extra)
    return r


def fixture():
    return {
        "version": 2,
        "other": {"keep": True},
        "plugins": {
            "a@m": [
                rec("user", "1.0"),
                rec("project", "1.0", projectPath=live("p1")),
                rec("project", "0.9", OLD, projectPath=live("p2")),
                rec("project", "2.0", NEW, projectPath=live("p3")),
            ],
            "b@m": [rec("user", "3.0"), rec("managed", "3.0")],
            "c@m": [rec("project", "1.0", projectPath=live("p4"))],
        },
    }


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.file = os.path.join(self.tmp, "installed_plugins.json")
        self.bdir = os.path.join(self.tmp, "backups")

    def write(self, data):
        with open(self.file, "w") as f:
            if isinstance(data, str):
                f.write(data)
            else:
                json.dump(data, f)

    def raw(self):
        with open(self.file) as f:
            return f.read()

    def backups(self):
        if not os.path.isdir(self.bdir):
            return []
        return sorted(os.listdir(self.bdir))

    def run_prune(self, **kw):
        args = dict(path=self.file, backup_dir=self.bdir, keep=5, dry_run=False)
        args.update(kw)
        return P.prune(**args)


class PathGoneTest(Base):
    def test_missing_or_non_string_or_relative_is_not_gone(self):
        self.assertFalse(P.path_gone({}))
        self.assertFalse(P.path_gone({"projectPath": ""}))
        self.assertFalse(P.path_gone({"projectPath": None}))
        self.assertFalse(P.path_gone({"projectPath": 5}))
        self.assertFalse(P.path_gone({"projectPath": "rel/path"}))

    def test_existing_directory_and_file_not_gone(self):
        self.assertFalse(P.path_gone({"projectPath": live("p1")}))
        f = os.path.join(self.tmp, "afile")
        open(f, "w").close()
        self.assertFalse(P.path_gone({"projectPath": f}))

    def test_dangling_symlink_not_gone(self):
        link = os.path.join(self.tmp, "dangling")
        os.symlink(os.path.join(self.tmp, "absent-target"), link)
        self.assertFalse(P.path_gone({"projectPath": link}))

    def test_absent_absolute_path_is_gone(self):
        self.assertTrue(P.path_gone({"projectPath": os.path.join(self.tmp, "absent")}))

    def test_path_under_regular_file_not_gone(self):
        f = os.path.join(self.tmp, "afile")
        open(f, "w").close()
        self.assertFalse(P.path_gone({"projectPath": os.path.join(f, "x")}))

    def test_other_oserror_not_gone(self):
        with mock.patch.object(
            P.os, "lstat", side_effect=PermissionError(errno.EACCES, "denied")
        ):
            self.assertFalse(P.path_gone({"projectPath": "/anything"}))


class ShouldRemoveTest(unittest.TestCase):
    def test_same_version_unparsable_ts_removed(self):
        self.assertTrue(P.should_remove(rec("project", "1", "garbage"), rec("user", "1")))

    def test_same_version_missing_ts_removed(self):
        self.assertTrue(P.should_remove(rec("project", "1", None), rec("user", "1", None)))

    def test_diff_version_missing_or_bad_ts_kept(self):
        self.assertFalse(P.should_remove(rec("project", "2", None), rec("user", "1")))
        self.assertFalse(P.should_remove(rec("project", "2", "bad"), rec("user", "1")))
        self.assertFalse(P.should_remove(rec("project", "2"), rec("user", "1", "bad")))
        self.assertFalse(P.should_remove(rec("project", "2"), rec("user", "1", None)))

    def test_diff_version_older_removed_equal_removed_newer_kept(self):
        self.assertTrue(P.should_remove(rec("project", "0", OLD), rec("user", "1", USER_TS)))
        self.assertTrue(P.should_remove(rec("project", "0", USER_TS), rec("user", "1", USER_TS)))
        self.assertFalse(P.should_remove(rec("project", "2", NEW), rec("user", "1", USER_TS)))

    def test_user_and_managed_never_removed(self):
        self.assertFalse(P.should_remove(rec("user", "1"), rec("user", "1")))
        self.assertFalse(P.should_remove(rec("managed", "1"), rec("user", "1")))

    def test_gone_path_removed_without_user_record(self):
        r = rec("project", "1", projectPath="/nonexistent-dotfiles-test/gone")
        self.assertTrue(P.should_remove(r, None))

    def test_gone_path_removed_even_when_user_record_older(self):
        r = rec("project", "2", NEW, projectPath="/nonexistent-dotfiles-test/gone")
        self.assertTrue(P.should_remove(r, rec("user", "1", OLD)))

    def test_gone_path_user_scope_kept(self):
        r = rec("user", "1", projectPath="/nonexistent-dotfiles-test/gone")
        self.assertFalse(P.should_remove(r, None))
        self.assertFalse(P.should_remove(r, rec("user", "1")))

    def test_existing_path_without_user_record_kept(self):
        self.assertFalse(P.should_remove(rec("project", "1", projectPath=live("p1")), None))

    def test_local_scope_removable(self):
        self.assertTrue(P.should_remove(rec("local", "1"), rec("user", "1")))

    def test_no_user_record(self):
        self.assertFalse(P.should_remove(rec("project", "1"), None))


class ParseTsTest(unittest.TestCase):
    def test_valid(self):
        d = P.parse_ts("2026-11-05T02:57:23.774Z")
        self.assertEqual((d.year, d.microsecond), (2026, 774000))

    def test_invalid(self):
        self.assertIsNone(P.parse_ts("x"))
        self.assertIsNone(P.parse_ts(None))
        self.assertIsNone(P.parse_ts(5))


class PruneTest(Base):
    def test_four_record_fixture(self):
        before = fixture()
        self.write(before)
        rc, line = self.run_prune()
        self.assertEqual(rc, 0)
        self.assertIn("removed 2, kept", line)
        after = json.loads(self.raw())
        self.assertEqual(after["version"], 2)
        self.assertEqual(after["other"], before["other"])
        self.assertEqual(after["plugins"]["b@m"], before["plugins"]["b@m"])
        a = after["plugins"]["a@m"]
        self.assertEqual(a[0], before["plugins"]["a@m"][0])
        self.assertEqual([r["projectPath"] for r in a[1:]], [live("p3")])
        self.assertEqual(after["plugins"]["c@m"], before["plugins"]["c@m"])
        self.assertEqual(len(self.backups()), 1)
        # backup holds the before-state
        with open(os.path.join(self.bdir, self.backups()[0])) as f:
            self.assertEqual(json.load(f), before)

    def test_summary_line_format(self):
        self.write(fixture())
        _, line = self.run_prune()
        self.assertRegex(
            line, r"^pruned at \d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ: removed \d+, kept \d+$"
        )
        self.assertIn("kept 5", line)  # user, project, user, managed, project

    def test_backup_name_format(self):
        self.write(fixture())
        self.run_prune()
        self.assertRegex(self.backups()[0], r"^installed_plugins-\d{8}T\d{12}Z\.json$")

    def test_refusals(self):
        cases = {
            "malformed": "{not json",
            "no_plugins": json.dumps({"version": 2}),
            "plugins_not_object": json.dumps({"version": 2, "plugins": []}),
            "version3": json.dumps({"version": 3, "plugins": {}}),
            "not_object": "[]",
        }
        for name, text in cases.items():
            with self.subTest(name):
                self.write(text)
                rc, line = self.run_prune()
                self.assertEqual(rc, 3)
                self.assertTrue(line.startswith("refused: "), line)
                self.assertEqual(self.raw(), text)
                self.assertEqual(self.backups(), [])

    def test_mtime_change_exit4(self):
        self.write(fixture())
        orig = self.raw()

        def touch():
            st = os.stat(self.file)
            os.utime(self.file, ns=(st.st_atime_ns, st.st_mtime_ns + 5_000_000_000))

        rc, line = self.run_prune(before_restat=touch)
        self.assertEqual(rc, 4)
        self.assertEqual(line, "skipped: plugins file changed during prune")
        self.assertEqual(self.raw(), orig)
        self.assertEqual([n for n in os.listdir(self.tmp) if n.endswith(".tmp")], [])

    def test_inode_change_exit4(self):
        self.write(fixture())
        orig = self.raw()

        def replace():
            copy = self.file + ".copy"
            shutil.copy2(self.file, copy)
            os.replace(copy, self.file)

        rc, line = self.run_prune(before_restat=replace)
        self.assertEqual(rc, 4)
        self.assertEqual(self.raw(), orig)
        self.assertEqual(sorted(os.listdir(self.tmp)), ["backups", "installed_plugins.json"])

    def test_dry_run(self):
        self.write(fixture())
        orig = self.raw()
        rc, line = self.run_prune(dry_run=True)
        self.assertEqual(rc, 0)
        self.assertIn("removed 2", line)
        self.assertEqual(self.raw(), orig)
        self.assertFalse(os.path.exists(self.bdir))

    def test_nothing_to_remove(self):
        data = {"version": 2, "plugins": {"a@m": [rec("user", "1")]}}
        self.write(data)
        orig = self.raw()
        rc, line = self.run_prune()
        self.assertEqual(rc, 0)
        self.assertIn("removed 0, kept 1", line)
        self.assertEqual(self.raw(), orig)
        self.assertFalse(os.path.exists(self.bdir))

    def test_backup_retention(self):
        self.write(fixture())
        os.makedirs(self.bdir)
        for i in range(6):
            name = "installed_plugins-2026010%dT000000000000Z.json" % (i + 1)
            Path(self.bdir, name).write_text("{}")
        Path(self.bdir, "unrelated.txt").write_text("keep")
        self.run_prune()
        b = [n for n in self.backups() if n.startswith("installed_plugins-")]
        self.assertEqual(len(b), 5)
        self.assertNotIn("installed_plugins-20260101T000000000000Z.json", b)
        self.assertTrue(b[-1] > "installed_plugins-20260106")
        self.assertIn("unrelated.txt", self.backups())
        self.assertTrue(b[-1] > "installed_plugins-2026010")

    def test_keep_one(self):
        self.write(fixture())
        os.makedirs(self.bdir)
        Path(self.bdir, "installed_plugins-20260101T000000000000Z.json").write_text("{}")
        self.run_prune(keep=1)
        self.assertEqual(len(self.backups()), 1)
        self.assertNotIn("20260101", self.backups()[0])

    def test_missing_file(self):
        rc, line = self.run_prune()
        self.assertEqual((rc, line), (0, "no plugins file"))


class HardeningTest(Base):
    def assert_refused_clean(self, rc, line, orig, bdir_before=None):
        self.assertEqual(rc, 3)
        self.assertEqual(len(line.splitlines()), 1)
        self.assertTrue(line.startswith("refused: "), line)
        self.assertEqual(self.raw(), orig)
        self.assertEqual([n for n in os.listdir(self.tmp) if n.endswith(".tmp")], [])
        if bdir_before is not None:
            self.assertEqual(self.backups(), bdir_before)

    def test_keep_below_one_rejected(self):
        self.write(fixture())
        orig = self.raw()
        for bad in (0, -1):
            with self.assertRaises(ValueError):
                self.run_prune(keep=bad)
        with self.assertRaises(SystemExit) as cm:
            with mock.patch("sys.stderr"):
                P.main(["--file", self.file, "--backup-dir", self.bdir, "--keep", "0"])
        self.assertNotEqual(cm.exception.code, 0)
        self.assertEqual(self.raw(), orig)
        self.assertFalse(os.path.exists(self.bdir))

    def test_backup_dir_is_file_refused(self):
        self.write(fixture())
        orig = self.raw()
        Path(self.bdir).write_text("i am a file")
        rc, line = self.run_prune()
        self.assert_refused_clean(rc, line, orig)
        self.assertEqual(Path(self.bdir).read_text(), "i am a file")

    def test_mkstemp_failure_refused_and_backup_removed(self):
        self.write(fixture())
        orig = self.raw()
        with mock.patch.object(P.tempfile, "mkstemp", side_effect=OSError("boom")):
            rc, line = self.run_prune()
        self.assert_refused_clean(rc, line, orig, [])

    def test_replace_failure_refused(self):
        self.write(fixture())
        orig = self.raw()
        os.makedirs(self.bdir)
        for i in range(6):
            Path(self.bdir, "installed_plugins-2026010%dT000000000000Z.json" % (i + 1)).write_text("b%d" % i)
        before = self.backups()
        with mock.patch.object(P.os, "replace", side_effect=OSError("boom")):
            rc, line = self.run_prune()
        self.assert_refused_clean(rc, line, orig, before)
        self.assertEqual(Path(self.bdir, before[0]).read_text(), "b0")

    def test_partial_backup_write_removed(self):
        self.write(fixture())
        orig = self.raw()
        real_open = open
        bdir = self.bdir

        class Partial:
            def __init__(self, f):
                self.f = f

            def __enter__(self):
                return self

            def __exit__(self, *a):
                self.f.close()
                return False

            def write(self, data):
                self.f.write(data[:5])
                self.f.flush()
                raise OSError(errno.ENOSPC, "No space left on device")

        def fake_open(f, mode="r", *a, **k):
            if isinstance(f, str) and f.startswith(bdir) and "w" in mode:
                return Partial(real_open(f, mode, *a, **k))
            return real_open(f, mode, *a, **k)

        with mock.patch("builtins.open", side_effect=fake_open):
            rc, line = self.run_prune()
        self.assert_refused_clean(rc, line, orig, [])

    def test_listdir_failure_after_replace_still_ok(self):
        self.write(fixture())
        with mock.patch.object(P.os, "listdir", side_effect=OSError("boom")):
            rc, line = self.run_prune()
        self.assertEqual(rc, 0)
        self.assertRegex(line, r"^pruned at .*: removed 2, kept 5$")
        self.assertEqual(len(json.loads(self.raw())["plugins"]["a@m"]), 2)

    def test_tmp_removal_failure_does_not_skip_backup_removal(self):
        self.write(fixture())
        orig = self.raw()
        real_remove = os.remove

        def remove(p):
            if str(p).endswith(".tmp"):
                raise PermissionError(errno.EACCES, "denied")
            return real_remove(p)

        with mock.patch.object(P.os, "replace", side_effect=OSError("boom")), \
             mock.patch.object(P.os, "remove", side_effect=remove):
            rc, line = self.run_prune()
        self.assertEqual(rc, 3)
        self.assertEqual(self.raw(), orig)
        self.assertEqual(self.backups(), [])

    def test_symlink_replaced_between_read_and_restat_exit4(self):
        real_dir = os.path.join(self.tmp, "real")
        os.makedirs(real_dir)
        target = os.path.join(real_dir, "installed_plugins.json")
        with open(target, "w") as f:
            json.dump(fixture(), f)
        os.symlink(target, self.file)
        orig = Path(target).read_text()

        def swap_link():
            fresh = self.file + ".new"
            os.symlink(target, fresh)
            os.replace(fresh, self.file)

        rc, line = self.run_prune(before_restat=swap_link)
        self.assertEqual(rc, 4)
        self.assertEqual(Path(target).read_text(), orig)
        self.assertEqual(self.backups(), [])

    def test_json_dump_failure_refused(self):
        self.write(fixture())
        orig = self.raw()
        with mock.patch.object(P.json, "dump", side_effect=ValueError("bad")):
            rc, line = self.run_prune()
        self.assert_refused_clean(rc, line, orig, [])

    def test_fsync_failure_refused(self):
        self.write(fixture())
        orig = self.raw()
        with mock.patch.object(P.os, "fsync", side_effect=OSError("boom")):
            rc, line = self.run_prune()
        self.assert_refused_clean(rc, line, orig, [])

    def test_fsync_called_before_replace(self):
        self.write(fixture())
        calls = []
        real_fsync, real_replace = os.fsync, os.replace
        with mock.patch.object(P.os, "fsync", side_effect=lambda fd: (calls.append("fsync"), real_fsync(fd))[1]), \
             mock.patch.object(P.os, "replace", side_effect=lambda a, b: (calls.append("replace"), real_replace(a, b))[1]):
            self.run_prune()
        self.assertEqual(calls, ["fsync", "replace"])

    def test_unreadable_file_refused(self):
        self.write(fixture())
        orig = self.raw()
        real_open = open

        def fake_open(f, *a, **k):
            if isinstance(f, str) and os.path.realpath(f) == os.path.realpath(self.file):
                raise PermissionError("denied")
            return real_open(f, *a, **k)

        with mock.patch("builtins.open", side_effect=fake_open):
            rc, line = self.run_prune()
        self.assert_refused_clean(rc, line, orig, [])

    def test_stat_error_refused(self):
        with mock.patch.object(P.os, "stat", side_effect=PermissionError("denied")):
            rc, line = self.run_prune()
        self.assertEqual(rc, 3)
        self.assertTrue(line.startswith("refused: "))

    def test_missing_version_both_kept(self):
        a = rec("user", "x", None)
        b = rec("project", "x", None)
        del a["version"]
        del b["version"]
        self.assertFalse(P.should_remove(b, a))
        a["version"] = ""
        b["version"] = ""
        self.assertFalse(P.should_remove(b, a))
        a["version"] = 1
        b["version"] = 1
        self.assertFalse(P.should_remove(b, a))

    def test_backup_is_bytes_read_once(self):
        self.write(fixture())
        orig_bytes = Path(self.file).read_bytes()
        real_open = open
        opens = []

        def counting(f, *a, **k):
            if isinstance(f, str) and os.path.realpath(f) == os.path.realpath(self.file):
                opens.append(a)
            return real_open(f, *a, **k)

        with mock.patch("builtins.open", side_effect=counting):
            self.run_prune()
        self.assertEqual(len(opens), 1)
        self.assertEqual(Path(self.bdir, self.backups()[0]).read_bytes(), orig_bytes)

    def test_exit4_leaves_backup_dir_untouched(self):
        self.write(fixture())
        os.makedirs(self.bdir)
        for i in range(6):
            Path(self.bdir, "installed_plugins-2026010%dT000000000000Z.json" % (i + 1)).write_text("b%d" % i)
        before = {n: Path(self.bdir, n).read_text() for n in self.backups()}

        def touch():
            st = os.stat(self.file)
            os.utime(self.file, ns=(st.st_atime_ns, st.st_mtime_ns + 5_000_000_000))

        rc, _ = self.run_prune(before_restat=touch)
        self.assertEqual(rc, 4)
        after = {n: Path(self.bdir, n).read_text() for n in self.backups()}
        self.assertEqual(after, before)

    def test_size_change_exit4(self):
        self.write(fixture())

        def grow():
            st = os.stat(self.file)
            with open(self.file, "a") as f:
                f.write(" ")
            os.utime(self.file, ns=(st.st_atime_ns, st.st_mtime_ns))

        rc, line = self.run_prune(before_restat=grow)
        self.assertEqual(rc, 4)
        self.assertEqual(self.backups(), [])

    def test_symlink_preserved(self):
        real_dir = os.path.join(self.tmp, "real")
        os.makedirs(real_dir)
        target = os.path.join(real_dir, "installed_plugins.json")
        with open(target, "w") as f:
            json.dump(fixture(), f)
        os.symlink(target, self.file)
        rc, line = self.run_prune()
        self.assertEqual(rc, 0)
        self.assertTrue(os.path.islink(self.file))
        self.assertEqual(os.path.realpath(self.file), os.path.realpath(target))
        self.assertIn("removed 2", line)
        self.assertEqual(len(json.loads(Path(target).read_text())["plugins"]["a@m"]), 2)
        self.assertEqual([n for n in os.listdir(real_dir) if n.endswith(".tmp")], [])

    def test_format_indent2_no_trailing_newline_non_ascii(self):
        data = fixture()
        data["plugins"]["b@m"][0]["note"] = "caf\u00e9"
        self.write(data)
        self.run_prune()
        text = self.raw()
        self.assertFalse(text.endswith("\n"))
        self.assertIn('\n  "version": 2', text)
        self.assertIn("caf\u00e9", text)

    def test_mode_preserved(self):
        self.write(fixture())
        os.chmod(self.file, 0o644)
        self.run_prune()
        self.assertEqual(os.stat(self.file).st_mode & 0o777, 0o644)
        os.chmod(self.file, 0o600)
        self.write(fixture())
        os.chmod(self.file, 0o640)
        self.run_prune()
        self.assertEqual(os.stat(self.file).st_mode & 0o777, 0o640)

    def test_odd_shapes_untouched(self):
        data = {"version": 2, "plugins": {
            "x@m": "a string",
            "y@m": ["notdict", rec("user", "1"), rec("project", "1", projectPath=live("p"))],
        }}
        self.write(data)
        rc, line = self.run_prune()
        self.assertEqual(rc, 0)
        self.assertIn("removed 1, kept 2", line)
        after = json.loads(self.raw())["plugins"]
        self.assertEqual(after["x@m"], "a string")
        self.assertEqual(after["y@m"][0], "notdict")
        self.assertEqual(len(after["y@m"]), 2)

    def test_retention_newest_is_this_run(self):
        self.write(fixture())
        orig = Path(self.file).read_bytes()
        os.makedirs(self.bdir)
        for i in range(6):
            Path(self.bdir, "installed_plugins-2026010%dT000000000000Z.json" % (i + 1)).write_text("{}")
        before = set(self.backups())
        self.run_prune()
        new = set(self.backups()) - before
        self.assertEqual(len(new), 1)
        newest = new.pop()
        self.assertEqual(max(self.backups()), newest)
        self.assertEqual(Path(self.bdir, newest).read_bytes(), orig)
        self.assertEqual(len(self.backups()), 5)
        self.assertNotIn("installed_plugins-20260101T000000000000Z.json", self.backups())
        self.assertNotIn("installed_plugins-20260102T000000000000Z.json", self.backups())


class MainTest(Base):
    def test_main_missing_file(self):
        import io
        from contextlib import redirect_stdout

        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = P.main(["--file", self.file, "--backup-dir", self.bdir])
        self.assertEqual(rc, 0)
        self.assertEqual(buf.getvalue(), "no plugins file\n")

    def test_main_prunes_and_dry_run(self):
        import io
        from contextlib import redirect_stdout

        self.write(fixture())
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = P.main(["--file", self.file, "--backup-dir", self.bdir, "--dry-run"])
        self.assertEqual(rc, 0)
        self.assertRegex(buf.getvalue(), r"^pruned at .*removed 2")
        self.assertFalse(os.path.exists(self.bdir))
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = P.main(["--file", self.file, "--backup-dir", self.bdir, "--keep", "2"])
        self.assertEqual(rc, 0)
        self.assertEqual(len(self.backups()), 1)

    def test_main_refusal_exit3(self):
        import io
        from contextlib import redirect_stdout

        self.write("{bad")
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = P.main(["--file", self.file, "--backup-dir", self.bdir])
        self.assertEqual(rc, 3)

    def test_cli_subprocess(self):
        import subprocess

        self.write(fixture())
        r = subprocess.run(
            [sys.executable, str(_MODULE), "--file", self.file, "--backup-dir", self.bdir],
            capture_output=True, text=True, stdin=subprocess.DEVNULL,
        )
        self.assertEqual(r.returncode, 0)
        self.assertEqual(len(r.stdout.splitlines()), 1)


if __name__ == "__main__":
    unittest.main()
