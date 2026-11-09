"""Tests for scripts/uv_lock_cooldown.py: cutoff, plan, verify, diff and held."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "uv_lock_cooldown.py"
CUTOFF = "2026-10-26T19:00:00Z"
OLD = "2026-01-01T00:00:00.000Z"
NEW = "2026-11-06T08:37:19.779Z"
NEW_SECONDS = "2026-11-06T08:37:19Z"  # reports truncate to whole seconds


def pkg(name: str, version: str, upload: str | None = OLD, wheel: str | None = None) -> str:
    """Render one registry [[package]] block; upload=None omits upload-time."""
    lines = [
        "[[package]]",
        f'name = "{name}"',
        f'version = "{version}"',
        'source = { registry = "https://pypi.org/simple" }',
    ]
    if upload is not None:
        lines.append(f'sdist = {{ url = "u", hash = "sha256:0", size = 1, upload-time = "{upload}" }}')
    if wheel is not None:
        lines.append(
            "wheels = [\n"
            f'    {{ url = "w", hash = "sha256:1", size = 1, upload-time = "{wheel}" }},\n]'
        )
    return "\n".join(lines) + "\n"


EDITABLE = '[[package]]\nname = "proj"\nversion = "0.1.0"\nsource = { editable = "." }\n'


class Case(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)

    def lock(self, name: str, *blocks: str) -> str:
        path = self.dir / name
        path.write_text("version = 1\n\n" + EDITABLE + "\n" + "\n".join(blocks), encoding="utf-8")
        return str(path)

    def run_helper(self, *args: str) -> tuple[int, str, str]:
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), *args], capture_output=True, text=True, check=False
        )
        return proc.returncode, proc.stdout, proc.stderr

    def plan(self, base: str, new: str) -> tuple[int, list[str], str]:
        report = str(self.dir / "report.tsv")
        code, out, _ = self.run_helper("plan", base, new, CUTOFF, report)
        return code, out.splitlines(), Path(report).read_text(encoding="utf-8")


class CutoffTest(Case):
    def test_cutoff_subtracts_days(self) -> None:
        self.assertEqual(
            self.run_helper("cutoff", "2026-11-09T19:00:00Z", "14")[:2],
            (0, "2026-10-26T19:00:00Z\n"),
        )

    def test_cutoff_accepts_offset(self) -> None:
        code, out, _ = self.run_helper("cutoff", "2026-11-09T14:00:00-05:00", "14")
        self.assertEqual((code, out), (0, "2026-10-26T19:00:00Z\n"))

    def test_cutoff_bad_now_exit_2(self) -> None:
        self.assertEqual(self.run_helper("cutoff", "yesterday", "14")[0], 2)

    def test_cutoff_bad_days_exit_2(self) -> None:
        self.assertEqual(self.run_helper("cutoff", "2026-11-09T19:00:00Z", "x")[0], 2)


class PlanTest(Case):
    def test_unchanged_package_emits_nothing(self) -> None:
        base = self.lock("b.lock", pkg("a", "1.0", NEW))
        new = self.lock("n.lock", pkg("a", "1.0", NEW))
        self.assertEqual(self.plan(base, new), (0, [], ""))

    def test_fresh_change_with_aged_base_caps_with_exclude_newer(self) -> None:
        base = self.lock("b.lock", pkg("a", "1.0"))
        new = self.lock("n.lock", pkg("a", "2.0", NEW))
        code, lines, report = self.plan(base, new)
        self.assertEqual(code, 0)
        self.assertEqual(lines, ["--upgrade-package", "a", "--exclude-newer-package", f"a={CUTOFF}"])
        self.assertEqual(report, f"a\t2.0\t{NEW_SECONDS}\n")

    def test_fresh_base_version_is_pinned(self) -> None:
        base = self.lock("b.lock", pkg("a", "1.0", NEW))
        new = self.lock("n.lock", pkg("a", "2.0", NEW))
        code, lines, report = self.plan(base, new)
        self.assertEqual((code, lines), (0, ["--upgrade-package", "a==1.0"]))
        self.assertEqual(report, f"a\t2.0\t{NEW_SECONDS}\n")

    def test_added_fresh_package_caps(self) -> None:
        base = self.lock("b.lock", pkg("a", "1.0"))
        new = self.lock("n.lock", pkg("a", "1.0"), pkg("z", "0.1", NEW))
        code, lines, _ = self.plan(base, new)
        self.assertEqual(
            (code, lines), (0, ["--upgrade-package", "z", "--exclude-newer-package", f"z={CUTOFF}"])
        )

    def test_aged_change_emits_nothing(self) -> None:
        base = self.lock("b.lock", pkg("a", "1.0"))
        new = self.lock("n.lock", pkg("a", "2.0", OLD))
        self.assertEqual(self.plan(base, new), (0, [], ""))

    def test_missing_upload_time_is_fresh(self) -> None:
        base = self.lock("b.lock", pkg("a", "1.0"))
        new = self.lock("n.lock", pkg("a", "2.0", None))
        code, lines, report = self.plan(base, new)
        self.assertEqual(code, 0)
        self.assertEqual(lines[:2], ["--upgrade-package", "a"])
        self.assertTrue(report.startswith("a\t2.0\t"))

    def test_upload_exactly_at_cutoff_is_aged(self) -> None:
        base = self.lock("b.lock", pkg("a", "1.0"))
        new = self.lock("n.lock", pkg("a", "2.0", CUTOFF))
        self.assertEqual(self.plan(base, new), (0, [], ""))

    def test_one_second_after_cutoff_is_fresh(self) -> None:
        base = self.lock("b.lock", pkg("a", "1.0"))
        new = self.lock("n.lock", pkg("a", "2.0", "2026-10-26T19:00:01Z"))
        self.assertEqual(self.plan(base, new)[1][:2], ["--upgrade-package", "a"])

    def test_earliest_file_time_decides_age(self) -> None:
        base = self.lock("b.lock", pkg("a", "1.0"))
        new = self.lock("n.lock", pkg("a", "2.0", NEW, wheel=OLD))
        self.assertEqual(self.plan(base, new), (0, [], ""))

    def test_multi_version_name_compared_as_set(self) -> None:
        base = self.lock("b.lock", pkg("a", "1.0"), pkg("a", "2.0"))
        same = self.lock("s.lock", pkg("a", "2.0"), pkg("a", "1.0"))
        self.assertEqual(self.plan(base, same), (0, [], ""))
        grown = self.lock("g.lock", pkg("a", "1.0"), pkg("a", "2.0"), pkg("a", "3.0", NEW))
        self.assertEqual(self.plan(base, grown)[1][:2], ["--upgrade-package", "a"])

    def test_names_sorted(self) -> None:
        base = self.lock("b.lock", pkg("a", "1.0"), pkg("b", "1.0"))
        new = self.lock("n.lock", pkg("b", "2.0", NEW), pkg("a", "2.0", NEW))
        lines = self.plan(base, new)[1]
        self.assertEqual(lines[1], "a")
        self.assertEqual(lines[5], "b")


class VerifyTest(Case):
    def test_fresh_changed_and_added_named(self) -> None:
        base = self.lock("b.lock", pkg("a", "1.0"))
        final = self.lock("f.lock", pkg("a", "2.0", NEW), pkg("z", "0.1", NEW))
        code, out, _ = self.run_helper("verify", base, final, CUTOFF)
        self.assertEqual((code, out), (1, "a\nz\n"))

    def test_only_aged_or_base_versions_pass(self) -> None:
        base = self.lock("b.lock", pkg("a", "1.0", NEW), pkg("b", "1.0"))
        final = self.lock("f.lock", pkg("a", "1.0", NEW), pkg("b", "2.0", OLD))
        self.assertEqual(self.run_helper("verify", base, final, CUTOFF)[:2], (0, ""))


class DiffTest(Case):
    def test_updated_added_removed(self) -> None:
        base = self.lock("b.lock", pkg("a", "1.0"), pkg("gone", "3.0"))
        final = self.lock("f.lock", pkg("a", "2.0"), pkg("new", "0.1"))
        code, out, _ = self.run_helper("diff", base, final)
        self.assertEqual(
            (code, out), (0, "Updated a v1.0 -> v2.0\nRemoved gone v3.0\nAdded new v0.1\n")
        )

    def test_multi_version_sides_joined(self) -> None:
        base = self.lock("b.lock", pkg("six", "1.15.0"), pkg("six", "1.16.0"))
        final = self.lock("f.lock", pkg("six", "1.16.0"))
        out = self.run_helper("diff", base, final)[1]
        self.assertEqual(out, "Updated six v1.15.0, v1.16.0 -> v1.16.0\n")

    def test_equal_version_sets_empty_despite_wheel_changes(self) -> None:
        base = self.lock("b.lock", pkg("a", "1.0", OLD, wheel=OLD))
        final = self.lock("f.lock", pkg("a", "1.0", OLD, wheel=NEW))
        self.assertEqual(self.run_helper("diff", base, final)[:2], (0, ""))


class HeldTest(Case):
    def test_line_format(self) -> None:
        report = self.dir / "r.tsv"
        report.write_text(f"a\t2.0\t{NEW_SECONDS}\n", encoding="utf-8")
        final = self.lock("f.lock", pkg("a", "1.5", OLD))
        code, out, _ = self.run_helper("held", str(report), final)
        self.assertEqual((code, out), (0, f"- a: newest 2.0 uploaded {NEW_SECONDS}; took 1.5\n"))

    def test_multiple_final_versions_joined(self) -> None:
        report = self.dir / "r.tsv"
        report.write_text(f"a\t3.0\t{NEW_SECONDS}\n", encoding="utf-8")
        final = self.lock("f.lock", pkg("a", "2.0"), pkg("a", "1.0"))
        self.assertEqual(
            self.run_helper("held", str(report), final)[1],
            f"- a: newest 3.0 uploaded {NEW_SECONDS}; took 1.0, 2.0\n",
        )


class ErrorTest(Case):
    def test_zero_registry_packages_exit_2(self) -> None:
        empty = self.lock("e.lock")
        good = self.lock("g.lock", pkg("a", "1.0"))
        self.assertEqual(self.run_helper("diff", empty, good)[0], 2)

    def test_package_without_version_exit_2(self) -> None:
        bad = self.dir / "bad.lock"
        bad.write_text(
            '[[package]]\nname = "a"\nsource = { registry = "https://pypi.org/simple" }\n',
            encoding="utf-8",
        )
        good = self.lock("g.lock", pkg("a", "1.0"))
        self.assertEqual(self.run_helper("diff", str(bad), good)[0], 2)

    def test_unparseable_toml_exit_2(self) -> None:
        bad = self.dir / "bad.lock"
        bad.write_text("not [ toml", encoding="utf-8")
        good = self.lock("g.lock", pkg("a", "1.0"))
        self.assertEqual(self.run_helper("verify", str(bad), good, CUTOFF)[0], 2)

    def test_missing_file_exit_2(self) -> None:
        good = self.lock("g.lock", pkg("a", "1.0"))
        self.assertEqual(self.run_helper("diff", str(self.dir / "nope"), good)[0], 2)

    def test_wrong_argument_count_exit_2(self) -> None:
        self.assertEqual(self.run_helper("diff", "only-one")[0], 2)

    def test_no_subcommand_exit_2(self) -> None:
        self.assertEqual(self.run_helper()[0], 2)

    def test_unknown_subcommand_exit_2(self) -> None:
        self.assertEqual(self.run_helper("bogus")[0], 2)

    def test_bad_cutoff_exit_2(self) -> None:
        good = self.lock("g.lock", pkg("a", "1.0"))
        self.assertEqual(self.run_helper("verify", good, good, "garbage")[0], 2)

    def test_malformed_report_row_exit_2(self) -> None:
        report = self.dir / "r.tsv"
        report.write_text("only-one-field\n", encoding="utf-8")
        good = self.lock("g.lock", pkg("a", "1.0"))
        self.assertEqual(self.run_helper("held", str(report), good)[0], 2)


if __name__ == "__main__":
    unittest.main()
