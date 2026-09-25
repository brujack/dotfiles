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


    def test_splits_before_a_sentence_that_starts_with_a_digit(self):
        text = "First part ends here. 2026 is the year that follows."
        sentences = rc.split_sentences(text)
        self.assertEqual(
            sentences,
            ["First part ends here.", "2026 is the year that follows."],
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

    def test_a_fenced_block_inside_a_list_item_does_not_swallow_the_next_bullet(self):
        text = "- a\n```\ncode here\n```\ntail text\n- b\n"
        units = rc.extract_units(text)
        self.assertIn("tail text", units)
        self.assertIn("- b", units)
        self.assertNotIn("tail text\n- b", units)

    def test_heading_only_paragraph_is_not_a_unit(self):
        text = "### Some Heading\n\nReal prose paragraph.\n"
        units = rc.extract_units(text)
        self.assertEqual(units, ["Real prose paragraph."])


class TestFindHeadingSpan(unittest.TestCase):
    def test_ignores_a_heading_shaped_line_inside_fenced_code(self):
        text = (
            "### Version Pinning\n\n"
            "```bash\n"
            "# comment that looks like a heading\n"
            "GO_VER=1.2.3\n"
            "```\n\n"
            "Real trailing prose that belongs to Version Pinning.\n\n"
            "### Next Section\n\n"
            "Other text.\n"
        )
        lines = text.splitlines(keepends=True)
        start, end, _level = rc.find_heading_span(lines, "### Version Pinning")
        span_text = "".join(lines[start:end])
        self.assertIn("Real trailing prose", span_text)
        self.assertNotIn("### Next Section", span_text)

    def test_parent_section_span_excludes_a_nested_child_heading(self):
        text = (
            "## Parent\n\n"
            "Parent intro text that must move.\n\n"
            "### Child\n\n"
            "Child body text that must not leak into the parent span.\n\n"
            "## Next Top\n\n"
            "Unrelated trailing text.\n"
        )
        lines = text.splitlines(keepends=True)
        start, end, _level = rc.find_heading_span(lines, "## Parent")
        span_text = "".join(lines[start:end])
        self.assertIn("Parent intro text", span_text)
        self.assertNotIn("Child body text", span_text)
        self.assertNotIn("### Child", span_text)

    def test_start_search_skips_a_heading_shaped_line_inside_a_fence(self):
        text = (
            "```text\n"
            "### Widget\n"
            "```\n\n"
            "Intro text before the real heading.\n\n"
            "### Widget\n\n"
            "Real widget body.\n\n"
            "### Next\n\n"
            "Other text.\n"
        )
        lines = text.splitlines(keepends=True)
        start, end, _level = rc.find_heading_span(lines, "### Widget")
        span_text = "".join(lines[start:end])
        self.assertIn("Real widget body", span_text)
        self.assertNotIn("Intro text before", span_text)


class TestAnalyzeSectionsNesting(unittest.TestCase):
    def test_parent_and_child_both_listed_produce_no_double_count(self):
        text = (
            "## Parent\n\n"
            "Parent intro text that must move.\n\n"
            "### Child\n\n"
            "Child body text that should not be duplicated.\n\n"
            "## Next Top\n\n"
            "Unrelated trailing text.\n"
        )
        lines = text.splitlines(keepends=True)
        spans = rc.resolve_spans(lines, ["## Parent", "### Child"])
        analysis = rc.analyze_sections(lines, spans, [], set())
        child_count = sum(1 for u in analysis.units if "Child body text" in u)
        self.assertEqual(child_count, 1)

    def test_unknown_section_heading_is_an_error(self):
        pre_text = "# Doc\n\nSome text.\n"
        lines = pre_text.splitlines(keepends=True)
        with self.assertRaises(rc.MapError):
            rc.resolve_spans(lines, ["### Does Not Exist"])

    def test_duplicate_section_heading_is_an_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            map_path = Path(tmp) / "map.md"
            map_path.write_text(
                "```relocation-map\n"
                "SECTION | ### Widget\n"
                "SECTION | ### Widget\n"
                "```\n",
                encoding="utf-8",
            )
            with self.assertRaises(rc.MapError):
                rc.parse_map(map_path)


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


    def test_short_unit_requires_a_whole_line_match_not_a_substring(self):
        short_unit = "It stays warm."  # 14 normalised chars, well under 40
        pre_text = f"# Doc\n\n{short_unit}\n\nOther untouched paragraph.\n"
        # The short unit's text is embedded inside a longer, unrelated line
        # -- never as its own whole line -- so it must NOT count as present.
        post_text = (
            "# Doc\n\nXIt stays warm.Y unrelated wrapper text\n\n"
            "Other untouched paragraph.\n"
        )
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp)
            (dest_dir / "dotfiles-x.md").write_text(
                "### X\n\nUnrelated dest content.\n", encoding="utf-8"
            )
            results = rc.run_check(pre_text, post_text, dest_dir, rc.MapData())
        check1 = next(r for r in results if r[0] == 1)
        self.assertFalse(check1[1])
        self.assertIn("It stays warm", check1[2])

    def test_short_unit_matches_an_indented_copy_of_the_same_line(self):
        short_unit = "It stays warm."
        pre_text = f"# Doc\n\n{short_unit}\n\nOther untouched paragraph.\n"
        # The target's copy of the same short unit is indented -- still the
        # same whole line once stripped, and must still count as present.
        post_text = f"# Doc\n\n  {short_unit}\n\nOther untouched paragraph.\n"
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp)
            results = rc.run_check(pre_text, post_text, dest_dir, rc.MapData())
        check1 = next(r for r in results if r[0] == 1)
        self.assertTrue(check1[1], check1[2])

    def test_wrapped_short_unit_falls_back_to_substring_matching(self):
        # This unit is short once normalised (its newline collapses to a
        # space) but was never a single physical LINE -- no whole line of
        # the target can equal it, so it must fall back to substring
        # matching against the flattened blob, like any long unit.
        pre_text = "# Doc\n\n- It stays\n  warm.\n\nOther untouched paragraph.\n"
        post_text = "# Doc\n\n- It stays\n  warm.\n\nOther untouched paragraph.\n"
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp)
            results = rc.run_check(pre_text, post_text, dest_dir, rc.MapData())
        check1 = next(r for r in results if r[0] == 1)
        self.assertTrue(check1[1], check1[2])


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

    def test_bloat_bound_counts_unmoved_fences_and_headings_as_raw_bytes(self):
        widget = "This sentence about widgets has no rule keyword in it today."
        fence_block = (
            "```text\n"
            "some fenced content that must still count toward the floor\n"
            "```\n"
        )
        unmoved = (
            "# Doc\n\n" + fence_block + "\nKeep this structure around please.\n"
        )
        pre_text = unmoved + "\n### Widget\n\n" + widget + "\n"
        post_text = unmoved  # only the Widget span is gone; the unmoved part
        # (heading, fence, blank lines and all) is byte-for-byte untouched.
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp)
            (dest_dir / "dotfiles-x.md").write_text(
                "### Widget\n\n" + widget + "\n", encoding="utf-8"
            )
            map_data = rc.MapData(section_headings=["### Widget"])
            results = rc.run_check(
                pre_text, post_text, dest_dir, map_data, min_relocated=0, slack=0
            )
        check3 = next(r for r in results if r[0] == 3)
        self.assertTrue(check3[1], check3[2])

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

    def test_fails_when_units_relocated_but_no_pointer_written(self):
        moved = "A paragraph that must relocate somewhere without a pointer."
        pre_text = f"# Doc\n\nKeep me around please.\n\n{moved}\n"
        post_text = "# Doc\n\nKeep me around please.\n"  # no pointer at all
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
                min_relocated=0,
                slack=1_000_000,
            )
        check4 = next(r for r in results if r[0] == 4)
        self.assertFalse(check4[1])
        self.assertIn("pointer count=0", check4[2])

    def test_fails_when_a_move_unit_lands_under_the_wrong_heading(self):
        unit_text = "This paragraph must move to the Widget heading specifically."
        pre_text = f"# Doc\n\n{unit_text}\n"
        post_text = "# Doc\n\n"
        with tempfile.TemporaryDirectory() as tmp:
            dest_dir = Path(tmp)
            # The unit really is present in dest -- just under the WRONG
            # heading, not the one the MOVE record names.
            (dest_dir / "dotfiles-x.md").write_text(
                f"### Other Heading\n\n{unit_text}\n\n"
                "### Widget\n\nUnrelated widget text.\n",
                encoding="utf-8",
            )
            move = rc.MoveRecord(rc.normalize(unit_text)[:60], "dotfiles-x.md", "Widget")
            map_data = rc.MapData(move_records=[move])
            results = rc.run_check(
                pre_text,
                post_text,
                dest_dir,
                map_data,
                min_relocated=0,
                slack=1_000_000,
            )
        check4 = next(r for r in results if r[0] == 4)
        self.assertFalse(check4[1])
        self.assertIn("not found under heading", check4[2])


class TestCliEndToEnd(unittest.TestCase):
    def test_check_success_path_on_a_tiny_fixture(self):
        moved = "A small unit that must move somewhere else today."
        pre_text = f"# Doc\n\nKeep me around please.\n\n{moved}\n"
        post_text = (
            "# Doc\n\nKeep me around please.\n\n"
            "**Before** touching this **on** widgets, read "
            "`ai-config/docs/knowledge/dotfiles-x.md` § `X`.\n"
        )
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


def _has_commit(rev: str) -> bool:
    """True if `rev` resolves to a real commit in this checkout. actions/
    checkout's default depth-1 shallow clone does not carry the pinned
    2e38f5e4 revision this test reads, so a CI shallow clone must skip it
    rather than fail on a GitError that says nothing about the code."""
    env = dict(os.environ)
    for var in rc._GIT_ENV_STRIP:
        env.pop(var, None)
    result = subprocess.run(
        ["git", "cat-file", "-e", f"{rev}^{{commit}}"],
        cwd=_REPO,
        env=env,
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


_HAS_2E38F5E4 = _has_commit("2e38f5e4")


class TestMeasureAgainstRealClaudeMd(unittest.TestCase):
    @unittest.skipUnless(
        _HAS_2E38F5E4, "2e38f5e4 not present in this checkout (shallow clone?)"
    )
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
