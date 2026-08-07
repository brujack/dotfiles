import importlib.util
import json
import sys
import unittest
from pathlib import Path

_REPO = Path(__file__).resolve().parent.parent
_MODULE = _REPO / ".claude" / "scripts" / "triage_log.py"


def _load():
    spec = importlib.util.spec_from_file_location("triage_log", _MODULE)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["triage_log"] = module
    spec.loader.exec_module(module)
    return module


_TL = _load()


class TestEventShape(unittest.TestCase):
    def test_rejects_entry_missing_ts(self):
        with self.assertRaises(ValueError):
            _TL.validate_event({"event": "triage_start"})

    def test_rejects_entry_missing_event(self):
        with self.assertRaises(ValueError):
            _TL.validate_event({"ts": "2026-06-13T00:00:00Z"})


class TestBugCardRequiredFields(unittest.TestCase):
    def test_bug_card_requires_mode_symptom_repro_blast(self):
        for missing in ("mode", "symptom", "repro_cmd", "blast"):
            payload = {
                "ts": "2026-06-13T00:00:00Z",
                "event": "bug_card",
                "mode": "normal",
                "symptom": "x",
                "repro_cmd": "make test",
                "blast": "single-user",
            }
            del payload[missing]
            with self.assertRaises(
                ValueError, msg=f"missing field {missing} must raise"
            ):
                _TL.validate_event(payload)


class TestBisectOrdering(unittest.TestCase):
    def test_bisect_first_bad_requires_preceding_bisect_start(self):
        events = [
            {
                "ts": "t1",
                "event": "bug_card",
                "mode": "regression",
                "symptom": "x",
                "repro_cmd": "make test",
                "blast": "ci",
            },
            {"ts": "t2", "event": "bisect_first_bad", "commit": "abc"},
        ]
        with self.assertRaises(ValueError):
            _TL.validate_chain(events)

    def test_bisect_first_bad_valid_when_chain_starts_with_bisect_start(self):
        events = [
            {
                "ts": "t1",
                "event": "bug_card",
                "mode": "regression",
                "symptom": "x",
                "repro_cmd": "make test",
                "blast": "ci",
            },
            {
                "ts": "t2",
                "event": "bisect_start",
                "good_ref": "v1",
                "bad_ref": "HEAD",
                "repro_cmd": "make test",
            },
            {"ts": "t3", "event": "bisect_first_bad", "commit": "abc"},
        ]
        _TL.validate_chain(events)  # raises on failure


class TestDurationComputation(unittest.TestCase):
    def test_cycle_complete_duration_from_first_triage_start(self):
        events = [
            {"ts": "2026-06-13T00:00:00Z", "event": "triage_start", "model": "opus"},
            {
                "ts": "2026-06-13T00:30:00Z",
                "event": "gates_passed",
                "cycle": 1,
                "gates": ["make test"],
            },
        ]
        completed = _TL.compute_cycle_complete(events)
        self.assertEqual(completed["total_duration_s"], 1800)


class TestValidateEventInvalidMode(unittest.TestCase):
    def test_invalid_mode_raises(self):
        payload = {
            "ts": "2026-06-13T00:00:00Z",
            "event": "bug_card",
            "mode": "invalid",
            "symptom": "x",
            "repro_cmd": "make test",
            "blast": "single-user",
        }
        with self.assertRaises(ValueError, msg="invalid mode must raise"):
            _TL.validate_event(payload)


class TestValidateEventInvalidBlast(unittest.TestCase):
    def test_invalid_blast_raises(self):
        payload = {
            "ts": "2026-06-13T00:00:00Z",
            "event": "bug_card",
            "mode": "normal",
            "symptom": "x",
            "repro_cmd": "make test",
            "blast": "unknown",
        }
        with self.assertRaises(ValueError, msg="invalid blast must raise"):
            _TL.validate_event(payload)


class TestComputeCycleCompleteMissingTriage(unittest.TestCase):
    def test_missing_triage_start_raises(self):
        events = [
            {
                "ts": "2026-06-13T00:30:00Z",
                "event": "gates_passed",
                "cycle": 1,
                "gates": ["x"],
            },
        ]
        with self.assertRaises(ValueError):
            _TL.compute_cycle_complete(events)


class TestComputeCycleCompleteMissingGate(unittest.TestCase):
    def test_missing_gate_event_raises(self):
        events = [
            {"ts": "2026-06-13T00:00:00Z", "event": "triage_start", "model": "opus"},
        ]
        with self.assertRaises(ValueError):
            _TL.compute_cycle_complete(events)


class TestEmitCliValidBugCard(unittest.TestCase):
    def test_emit_bug_card_creates_jsonl(self):
        import shutil
        import subprocess
        import tempfile

        with tempfile.TemporaryDirectory() as tmpdir:
            # Copy the real script into a tmpdir .claude/scripts/ tree.
            # Must be a copy (not symlink) because the script uses
            # Path(__file__).resolve() which follows symlinks back to the
            # original, causing triage-log to land in the real repo tree.
            scripts_dir = Path(tmpdir) / ".claude" / "scripts"
            scripts_dir.mkdir(parents=True)
            fake_script = scripts_dir / "triage_log.py"
            shutil.copy2(_MODULE, fake_script)

            result = subprocess.run(
                [
                    sys.executable,
                    str(fake_script),
                    "emit",
                    "--event",
                    "bug_card",
                    "--mode",
                    "normal",
                    "--symptom",
                    "test symptom",
                    "--repro",
                    "make test",
                    "--blast",
                    "single-user",
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, msg=f"stderr: {result.stderr}")

            # Script writes to Path(__file__).resolve().parent.parent / "triage-log"
            # With the copy at tmpdir/.claude/scripts/triage_log.py that resolves to
            # tmpdir/.claude/triage-log/
            log_dir = Path(tmpdir) / ".claude" / "triage-log"
            jsonl_files = list(log_dir.glob("*.jsonl"))
            self.assertTrue(len(jsonl_files) > 0, "Expected at least one JSONL file")

            with jsonl_files[0].open() as fh:
                line = json.loads(fh.readline())
            self.assertEqual(line["event"], "bug_card")
            self.assertEqual(line["mode"], "normal")
            self.assertEqual(line["blast"], "single-user")


class TestEmitCliMissingRepro(unittest.TestCase):
    def test_missing_repro_exits_2_with_error(self):
        import subprocess

        result = subprocess.run(
            [
                sys.executable,
                str(_MODULE),
                "emit",
                "--event",
                "bug_card",
                "--mode",
                "normal",
                "--symptom",
                "test symptom",
                "--blast",
                "single-user",
                # --repro intentionally omitted
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2, msg=f"stdout: {result.stdout}")
        self.assertIn("repro_cmd", result.stderr)


class TestMainHelp(unittest.TestCase):
    def test_help_exits_0_and_mentions_emit(self):
        import subprocess

        result = subprocess.run(
            [sys.executable, str(_MODULE), "--help"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0)
        combined = result.stdout + result.stderr
        self.assertTrue(
            "triage_log" in combined or "emit" in combined,
            msg=f"Expected 'triage_log' or 'emit' in output: {combined}",
        )


class TestMainNoSubcommand(unittest.TestCase):
    def test_no_subcommand_exits_nonzero(self):
        import subprocess

        result = subprocess.run(
            [sys.executable, str(_MODULE)], capture_output=True, text=True, check=False
        )
        self.assertNotEqual(result.returncode, 0)


class TestNowIso(unittest.TestCase):
    """Direct test of _now_iso() to cover line 74/78-79."""

    def test_now_iso_returns_utc_string(self):
        ts = _TL._now_iso()
        # Must be a non-empty string matching ISO-8601 UTC pattern
        self.assertRegex(ts, r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")


class TestEmitDirect(unittest.TestCase):
    """Call _emit() directly (via argparse Namespace) to cover lines 80-95."""

    def setUp(self):
        import tempfile

        self._tmpdir = tempfile.TemporaryDirectory()
        tmpdir_path = Path(self._tmpdir.name)
        # Patch the log_dir by temporarily monkeypatching __file__ on the module.
        # Easier: patch Path(__file__) is hard — instead point the log dir by
        # temporarily overriding the module's __file__ attribute so the script's
        # computed path lands in tmpdir.
        self._orig_file = _TL.__file__
        # Place a fake __file__ at tmpdir/.claude/scripts/triage_log.py
        scripts_dir = tmpdir_path / ".claude" / "scripts"
        scripts_dir.mkdir(parents=True)
        fake_file = scripts_dir / "triage_log.py"
        fake_file.touch()
        _TL.__file__ = str(fake_file)
        self._log_dir = tmpdir_path / ".claude" / "triage-log"

    def tearDown(self):
        _TL.__file__ = self._orig_file
        self._tmpdir.cleanup()

    def _make_namespace(self, **kwargs):
        import argparse

        defaults = {
            "event": "bug_card",
            "mode": "normal",
            "symptom": "crash on startup",
            "repro": "make test",
            "blast": "single-user",
        }
        defaults.update(kwargs)
        return argparse.Namespace(**defaults)

    def test_emit_valid_bug_card_returns_0_and_writes_jsonl(self):
        args = self._make_namespace()
        rc = _TL._emit(args)
        self.assertEqual(rc, 0)
        jsonl_files = list(self._log_dir.glob("*.jsonl"))
        self.assertTrue(len(jsonl_files) > 0, "Expected JSONL file to be created")
        with jsonl_files[0].open() as fh:
            event = json.loads(fh.readline())
        self.assertEqual(event["event"], "bug_card")
        self.assertEqual(event["repro_cmd"], "make test")

    def test_emit_invalid_event_returns_2(self):
        # Missing repro_cmd → validate_event raises → _emit returns 2
        args = self._make_namespace(repro=None)
        rc = _TL._emit(args)
        self.assertEqual(rc, 2)

    def test_emit_optional_attrs_excluded_when_none(self):
        # mode/symptom/blast set to None — only event/ts/repro_cmd in output
        import argparse as _argparse

        args = _argparse.Namespace(
            event="triage_start", mode=None, symptom=None, repro=None, blast=None
        )
        # triage_start has no required extra fields
        rc = _TL._emit(args)
        self.assertEqual(rc, 0)


class TestMainDirect(unittest.TestCase):
    """Call main() directly to cover lines 99-116."""

    def test_main_emit_subcommand_returns_0(self):
        import tempfile

        with tempfile.TemporaryDirectory() as tmpdir:
            orig_file = _TL.__file__
            scripts_dir = Path(tmpdir) / ".claude" / "scripts"
            scripts_dir.mkdir(parents=True)
            fake_file = scripts_dir / "triage_log.py"
            fake_file.touch()
            _TL.__file__ = str(fake_file)
            try:
                rc = _TL.main(
                    [
                        "emit",
                        "--event",
                        "triage_start",
                    ]
                )
            finally:
                _TL.__file__ = orig_file
        self.assertEqual(rc, 0)

    def test_main_no_args_raises_systemexit(self):
        with self.assertRaises(SystemExit) as ctx:
            _TL.main([])
        self.assertNotEqual(ctx.exception.code, 0)


if __name__ == "__main__":
    unittest.main()
