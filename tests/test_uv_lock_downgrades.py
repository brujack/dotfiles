"""Tests for scripts/uv_lock_downgrades.py: the PEP 440 downgrade check on uv output."""

import subprocess
import sys
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "uv_lock_downgrades.py"


def run_check(text: str) -> tuple[int, str]:
    proc = subprocess.run(
        [sys.executable, str(SCRIPT)],
        input=text,
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.returncode, proc.stdout


class DowngradeCheckTest(unittest.TestCase):
    def test_plain_upgrade_passes(self) -> None:
        self.assertEqual(run_check("Updated acme v5.7.0 -> v5.9.0\n"), (0, ""))

    def test_plain_downgrade_flagged(self) -> None:
        self.assertEqual(run_check("Updated acme v2.0 -> v1.9\n"), (1, "acme\n"))

    def test_comma_form_upgrade_passes(self) -> None:
        text = "Updated six v1.15.0, v1.16.0 -> v1.16.0\n"
        self.assertEqual(run_check(text), (0, ""))

    def test_comma_form_downgrade_flagged(self) -> None:
        text = "Updated six v1.15.0, v1.16.0 -> v1.15.0\n"
        self.assertEqual(run_check(text), (1, "six\n"))

    def test_post_release_ordering_passes(self) -> None:
        text = "Updated dateutil v2.9.0.post0 -> v2.9.0.post1\n"
        self.assertEqual(run_check(text), (0, ""))

    def test_post_release_downgrade_flagged(self) -> None:
        text = "Updated dateutil v2.9.0.post1 -> v2.9.0\n"
        self.assertEqual(run_check(text), (1, "dateutil\n"))

    def test_garbage_updated_line_is_unparseable(self) -> None:
        code, out = run_check("Updated acme sideways\n")
        self.assertEqual(code, 1)
        self.assertEqual(out, "unparseable: Updated acme sideways\n")

    def test_invalid_version_is_unparseable(self) -> None:
        code, out = run_check("Updated acme vbanana -> v1.0\n")
        self.assertEqual(code, 1)
        self.assertTrue(out.startswith("unparseable: "))

    def test_added_and_removed_ignored(self) -> None:
        text = "Added cloudpickle v3.1.2\nRemoved greenlet v3.5.5\n"
        self.assertEqual(run_check(text), (0, ""))

    def test_empty_input_passes(self) -> None:
        self.assertEqual(run_check(""), (0, ""))

    def test_mixed_reports_only_offenders(self) -> None:
        text = "Updated a v1 -> v2\nUpdated b v3 -> v2\nUpdated c x\n"
        code, out = run_check(text)
        self.assertEqual(code, 1)
        self.assertEqual(out, "b\nunparseable: Updated c x\n")


if __name__ == "__main__":
    unittest.main()
