"""Tests for scripts/uv_lock_downgrades.py: the PEP 440 downgrade check on uv output."""

import subprocess
import sys
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "uv_lock_downgrades.py"


def run_raw(data: bytes) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT)], input=data, capture_output=True, check=False
    )


def run_check(text: str) -> tuple[int, str]:
    proc = run_raw(text.encode("utf-8"))
    return proc.returncode, proc.stdout.decode("utf-8")


def upd(old: str, new: str) -> str:
    return f"Updated a {old} -> {new}\n"


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

    def test_lowest_fork_downgrade_flagged(self) -> None:
        text = "Updated a v1.0, v3.0 -> v0.5, v3.0\n"
        self.assertEqual(run_check(text), (1, "a\n"))

    def test_trailing_zeros_equal_no_downgrade(self) -> None:
        self.assertEqual(run_check(upd("v1.0", "v1.0.0")), (0, ""))
        self.assertEqual(run_check(upd("v1.0.0", "v1.0")), (0, ""))

    def test_release_compared_numerically(self) -> None:
        self.assertEqual(run_check(upd("v1.9", "v1.10")), (0, ""))
        self.assertEqual(run_check(upd("v1.10", "v1.9")), (1, "a\n"))

    def test_prerelease_to_final_is_upgrade(self) -> None:
        self.assertEqual(run_check(upd("v1.0rc1", "v1.0")), (0, ""))

    def test_final_to_prerelease_is_downgrade(self) -> None:
        self.assertEqual(run_check(upd("v1.0", "v1.0rc1")), (1, "a\n"))

    def test_prerelease_order_a_b_rc(self) -> None:
        self.assertEqual(run_check(upd("v1.0a2", "v1.0b1")), (0, ""))
        self.assertEqual(run_check(upd("v1.0b2", "v1.0rc1")), (0, ""))
        self.assertEqual(run_check(upd("v1.0rc1", "v1.0b9")), (1, "a\n"))

    def test_dev_sorts_below_final_and_below_prerelease(self) -> None:
        self.assertEqual(run_check(upd("v1.0", "v1.0.dev1")), (1, "a\n"))
        self.assertEqual(run_check(upd("v1.0.dev1", "v1.0a1")), (0, ""))
        self.assertEqual(run_check(upd("v1.0a1", "v1.0a1.dev1")), (1, "a\n"))

    def test_dev_numbers_order(self) -> None:
        self.assertEqual(run_check(upd("v1.0.dev1", "v1.0.dev2")), (0, ""))

    def test_post_above_final(self) -> None:
        self.assertEqual(run_check(upd("v1.0", "v1.0.post1")), (0, ""))
        self.assertEqual(run_check(upd("v1.0.post1", "v1.0")), (1, "a\n"))

    def test_post_with_dev_is_below_post(self) -> None:
        self.assertEqual(run_check(upd("v1.0.post1", "v1.0.post1.dev1")), (1, "a\n"))

    def test_epoch_dominates_release(self) -> None:
        self.assertEqual(run_check(upd("v1!0.1", "v2.0")), (1, "a\n"))
        self.assertEqual(run_check(upd("v2.0", "v1!0.1")), (0, ""))

    def test_local_version_unparseable(self) -> None:
        code, out = run_check(upd("v1.0", "v1.0+local"))
        self.assertEqual(code, 1)
        self.assertEqual(out, "unparseable: Updated a v1.0 -> v1.0+local\n")

    def test_standard_library_only(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertNotRegex(source, r"(?m)^\s*(import|from)\s+packaging")

    def test_undecodable_input_exits_2(self) -> None:
        proc = run_raw(b"Updated a v1 -> v\xff\n")
        self.assertEqual(proc.returncode, 2)
        self.assertEqual(proc.stdout, b"")


if __name__ == "__main__":
    unittest.main()
