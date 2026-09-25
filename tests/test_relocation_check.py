"""Tests for scripts/relocation_check.py.

Loaded via sys.path insertion, the same pattern test_phrase_check.py uses for
a script that is not a package.

Every test uses a tiny in-memory or tmpdir fixture, never the real CLAUDE.md,
except test_measure_against_real_claude_md_has_rule_sentences, which is the
one required exception: it runs `measure` against the real file at `2e38f5e4`
via the fixture map (tests/fixtures/relocation/map.md) and asserts only that
rule_sentences > 0.
"""

from __future__ import annotations

import io
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

_REPO = Path(__file__).resolve().parent.parent
_SCRIPTS = _REPO / "scripts"
sys.path.insert(0, str(_SCRIPTS))

import relocation_check as rc


class TestSplitSentences(unittest.TestCase):
    def test_keeps_e_g_whole_and_splits_after_trailing_backtick(self):
        text = (
            "Use it (e.g. `ledger init`) must still read. "
            "**Both** call sites must branch. "
            "Done `x`."
        )
        sentences = rc.split_sentences(text)
        self.assertEqual(
            sentences,
            [
                "Use it (e.g. `ledger init`) must still read.",
                "**Both** call sites must branch.",
                "Done `x`.",
            ],
        )


class TestExtractUnits(unittest.TestCase):
    def test_fenced_code_is_excluded(self):
        text = (
            "Intro paragraph text.\n\n"
            "```bash\n"
            "echo must never run this\n"
            "```\n\n"
            "Outro paragraph text.\n"
        )
        units = rc.extract_units(text)
        self.assertEqual(units, ["Intro paragraph text.", "Outro paragraph text."])

    def test_bullet_list_splits_into_items(self):
        text = (
            "- First item text.\n"
            "- Second item text.\n"
            "- Third item with\n"
            "  a wrapped continuation line.\n"
        )
        units = rc.extract_units(text)
        self.assertEqual(
            units,
            [
                "- First item text.",
                "- Second item text.",
                "- Third item with\n  a wrapped continuation line.",
            ],
        )

    def test_heading_only_paragraph_is_not_a_unit(self):
        text = "### Some Heading\n\nReal prose paragraph.\n"
        units = rc.extract_units(text)
        self.assertEqual(units, ["Real prose paragraph."])


class TestParseMap(unittest.TestCase):
    def test_fixture_map_parses(self):
        map_path = _REPO / "tests" / "fixtures" / "relocation" / "map.md"
        data = rc.parse_map(map_path)
        self.assertEqual(data.section_headings, ["### Mock Pattern"])
        self.assertEqual(data.inline_anchors, [])
        self.assertEqual(data.waive_sentences, set())
        self.assertEqual(data.move_records, [])


class TestCheck1(unittest.TestCase):
    def test_fails_when_moved_unit_altered_in_destination(self):
        unit_text = "This is a relocated unit that must be moved intact."
        pre_text = f"# Doc\n\n{unit_text}\n\nOther untouched paragraph.\n"
        post_text = "# Doc\n\nOther untouched paragraph.\n"
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp)
            altered = unit_text.replace("must", "should")
            (dest_dir / "dotfiles-x.md").write_text(
                f"### X\n\n{altered}\n", encoding="utf-8"
            )
            results = rc.run_check(pre_text, post_text, dest_dir, rc.MapData())
        check1 = next(r for r in results if r[0] == 1)
        self.assertFalse(check1[1])
        self.assertIn("must be moved intact", check1[2])


class TestCheck2(unittest.TestCase):
    _PRE = (
        "# Doc\n\n"
        "### Widget\n\n"
        "You must always flush the cache before reuse. It stays warm otherwise.\n\n"
        "### Gadget\n\n"
        "Trailing text.\n"
    )
    _POST = (
        "# Doc\n\n"
        "### Widget\n\n"
        "It stays warm otherwise.\n\n"
        "### Gadget\n\n"
        "Trailing text.\n"
    )
    _RULE_SENTENCE = "You must always flush the cache before reuse."

    def test_fails_when_rule_sentence_deleted_but_survives_in_dest_while_check1_passes(
        self,
    ):
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp)
            (dest_dir / "dotfiles-x.md").write_text(
                "### Widget history\n\n"
                "You must always flush the cache before reuse. It stays warm otherwise.\n",
                encoding="utf-8",
            )
            map_data = rc.MapData(section_headings=["### Widget"])
            results = rc.run_check(
                self._PRE, self._POST, dest_dir, map_data, min_relocated=0, slack=1_000_000
            )
        by_number = {n: (ok, detail) for n, ok, detail in results}
        self.assertFalse(by_number[2][0])
        self.assertIn(self._RULE_SENTENCE, by_number[2][1])
        self.assertTrue(by_number[1][0])

    def test_passes_with_a_waive_for_that_sentence(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp)
            (dest_dir / "dotfiles-x.md").write_text(
                "### Widget history\n\n"
                "You must always flush the cache before reuse. It stays warm otherwise.\n",
                encoding="utf-8",
            )
            map_data = rc.MapData(
                section_headings=["### Widget"],
                waive_sentences={self._RULE_SENTENCE},
            )
            results = rc.run_check(
                self._PRE, self._POST, dest_dir, map_data, min_relocated=0, slack=1_000_000
            )
        by_number = {n: ok for n, ok, _ in results}
        self.assertTrue(by_number[2])


class TestCheck3(unittest.TestCase):
    def test_fails_on_an_empty_relocation(self):
        text = "# Doc\n\nKeep me around please.\n"
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp)
            results = rc.run_check(
                text, text, dest_dir, rc.MapData(), min_relocated=60_000, slack=8_000
            )
        check3 = next(r for r in results if r[0] == 3)
        self.assertFalse(check3[1])
        self.assertIn("no relocated units", check3[2])

    def test_fails_on_a_relocation_below_60000_bytes(self):
        moved = "A small unit that must move somewhere else today."
        pre_text = f"# Doc\n\nKeep me around please.\n\n{moved}\n"
        post_text = "# Doc\n\nKeep me around please.\n"
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp)
            (dest_dir / "dotfiles-x.md").write_text(
                f"### X\n\n{moved}\n", encoding="utf-8"
            )
            results = rc.run_check(
                pre_text,
                post_text,
                dest_dir,
                rc.MapData(),
                min_relocated=60_000,
                slack=1_000_000,
            )
        check3 = next(r for r in results if r[0] == 3)
        self.assertFalse(check3[1])
        self.assertIn("< min 60000", check3[2])

    def test_fails_when_post_exceeds_floor_plus_slack(self):
        widget = "This sentence has no rule keyword in it at all today."
        pre_text = (
            "# Doc\n\nKeep me around please.\n\n### Widget\n\n" + widget + "\n"
        )
        post_core = "# Doc\n\nKeep me around please.\n"
        bloat = "Extra padding text that nobody asked to keep here. " * 500
        post_text = post_core + "\n" + bloat
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp)
            (dest_dir / "dotfiles-x.md").write_text(
                "### Widget\n\n" + widget + "\n", encoding="utf-8"
            )
            map_data = rc.MapData(section_headings=["### Widget"])
            results = rc.run_check(
                pre_text, post_text, dest_dir, map_data, min_relocated=0, slack=8_000
            )
        check3 = next(r for r in results if r[0] == 3)
        self.assertFalse(check3[1])
        self.assertIn("> floor", check3[2])


class TestCheck4(unittest.TestCase):
    def _run(self, post_text: str, dest_files: dict[str, str]):
        pre_text = "# Doc\n\nSomething unrelated.\n"
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp)
            for name, content in dest_files.items():
                (dest_dir / name).write_text(content, encoding="utf-8")
            return rc.run_check(pre_text, post_text, dest_dir, rc.MapData())

    def test_fails_on_a_missing_file(self):
        post_text = (
            "# Doc\n\n**Before** touching this **on** widgets, read "
            "`ai-config/docs/knowledge/dotfiles-missing.md` § `Some Heading`.\n"
        )
        results = self._run(post_text, {})
        check4 = next(r for r in results if r[0] == 4)
        self.assertFalse(check4[1])
        self.assertIn("missing file", check4[2])

    def test_fails_on_a_missing_heading(self):
        post_text = (
            "# Doc\n\n**Before** touching this **on** widgets, read "
            "`ai-config/docs/knowledge/dotfiles-x.md` § `Some Heading`.\n"
        )
        results = self._run(
            post_text, {"dotfiles-x.md": "### Other Heading\n\nSome text.\n"}
        )
        check4 = next(r for r in results if r[0] == 4)
        self.assertFalse(check4[1])
        self.assertIn("heading not found", check4[2])

    def test_fails_on_a_duplicate_heading(self):
        post_text = (
            "# Doc\n\n**Before** touching this **on** widgets, read "
            "`ai-config/docs/knowledge/dotfiles-x.md` § `Some Heading`.\n"
        )
        results = self._run(
            post_text,
            {
                "dotfiles-x.md": (
                    "### Some Heading\n\nText A.\n\n### Some Heading\n\nText B.\n"
                )
            },
        )
        check4 = next(r for r in results if r[0] == 4)
        self.assertFalse(check4[1])
        self.assertIn("duplicated", check4[2])


class TestCliEndToEnd(unittest.TestCase):
    def test_check_success_path_on_a_tiny_fixture(self):
        moved = "A small unit that must move somewhere else today."
        pre_text = f"# Doc\n\nKeep me around please.\n\n{moved}\n"
        post_text = "# Doc\n\nKeep me around please.\n"
        with tempfile.TemporaryDirectory() as repo_dir, tempfile.TemporaryDirectory() as dest_tmp:
            repo = Path(repo_dir)
            _init_git_repo(repo, {"CLAUDE.md": pre_text})
            dest_dir = Path(dest_tmp)
            (dest_dir / "dotfiles-x.md").write_text(
                f"### X\n\n{moved}\n", encoding="utf-8"
            )
            post_path = repo / "POST.md"
            post_path.write_text(post_text, encoding="utf-8")
            map_path = repo / "map.md"
            map_path.write_text("```relocation-map\n```\n", encoding="utf-8")

            old_cwd = Path.cwd()
            os.chdir(repo)
            try:
                buf = io.StringIO()
                with redirect_stdout(buf):
                    rc_code = rc.run(
                        [
                            "check",
                            "--pre-rev",
                            "HEAD",
                            "--post",
                            str(post_path),
                            "--dest",
                            str(dest_dir),
                            "--map",
                            str(map_path),
                            "--min-relocated",
                            "0",
                            "--slack",
                            "1000000",
                        ]
                    )
            finally:
                os.chdir(old_cwd)
        self.assertEqual(rc_code, 0)
        self.assertIn("CHECK1 PASS", buf.getvalue())
        self.assertIn("CHECK4 PASS", buf.getvalue())

    def test_git_failure_exits_nonzero(self):
        with tempfile.TemporaryDirectory() as repo_dir:
            repo = Path(repo_dir)
            _init_git_repo(repo, {"CLAUDE.md": "# Doc\n"})
            map_path = repo / "map.md"
            map_path.write_text("```relocation-map\n```\n", encoding="utf-8")

            old_cwd = Path.cwd()
            os.chdir(repo)
            try:
                buf = io.StringIO()
                with redirect_stdout(buf):
                    rc_code = rc.run(
                        ["measure", "--pre-rev", "deadbeefdeadbeef", "--map", str(map_path)]
                    )
            finally:
                os.chdir(old_cwd)
        self.assertNotEqual(rc_code, 0)


class TestMeasureAgainstRealClaudeMd(unittest.TestCase):
    def test_measure_against_real_claude_md_has_rule_sentences(self):
        map_path = _REPO / "tests" / "fixtures" / "relocation" / "map.md"
        buf = io.StringIO()
        old_cwd = Path.cwd()
        os.chdir(_REPO)
        try:
            with redirect_stdout(buf):
                rc_code = rc.run(
                    ["measure", "--pre-rev", "2e38f5e4", "--map", str(map_path)]
                )
        finally:
            os.chdir(old_cwd)
        self.assertEqual(rc_code, 0)
        output = buf.getvalue()
        match = None
        for token in output.split():
            if token.startswith("rule_sentences="):
                match = int(token.split("=", 1)[1])
        self.assertIsNotNone(match)
        self.assertGreater(match, 0)


def _init_git_repo(repo: Path, files: dict[str, str]) -> None:
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    for name, content in files.items():
        (repo / name).write_text(content, encoding="utf-8")
    subprocess.run(["git", "add", "."], cwd=repo, check=True)
    subprocess.run(
        [
            "git",
            "-c",
            "user.email=t@example.com",
            "-c",
            "user.name=T",
            "commit",
            "-q",
            "-m",
            "init",
        ],
        cwd=repo,
        check=True,
    )


if __name__ == "__main__":
    unittest.main()
