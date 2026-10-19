"""Tests for scripts/claude_md_budget.py: the CLAUDE.md byte-ceiling gate."""

import contextlib
import importlib.util
import io
import os
import subprocess
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "claude_md_budget.py"
CEILING = 105_000
_GIT_VARS = ("GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE")


def _env() -> dict[str, str]:
    env = {k: v for k, v in os.environ.items() if k not in _GIT_VARS}
    env["GIT_CONFIG_GLOBAL"] = "/dev/null"
    env["GIT_CONFIG_SYSTEM"] = "/dev/null"
    return env


def _git(repo: Path, *args: str) -> None:
    subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
        cwd=repo,
        env=_env(),
        check=True,
        capture_output=True,
        stdin=subprocess.DEVNULL,
    )


class BudgetTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.repo = Path(self._tmp.name)
        _git(self.repo, "init", "-q")

    def commit(self, claude_md: bytes | None) -> None:
        if claude_md is None:
            (self.repo / "other.txt").write_text("x")
            _git(self.repo, "add", "other.txt")
        else:
            (self.repo / "CLAUDE.md").write_bytes(claude_md)
            _git(self.repo, "add", "CLAUDE.md")
        _git(self.repo, "commit", "-q", "-m", "c")

    def run_script(
        self, *args: str, cwd: Path | None = None
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            cwd=cwd or self.repo,
            env=_env(),
            capture_output=True,
            text=True,
            stdin=subprocess.DEVNULL,
            check=False,
        )

    def test_exactly_at_ceiling_allowed(self) -> None:
        self.commit(b"a" * CEILING)
        self.assertEqual(self.run_script("HEAD").returncode, 0)

    def test_one_over_ceiling_refused(self) -> None:
        self.commit(b"a" * (CEILING + 1))
        result = self.run_script("HEAD")
        self.assertEqual(result.returncode, 1)
        self.assertIn("105001", result.stderr)
        self.assertIn("105000", result.stderr)

    def test_no_claude_md_allowed(self) -> None:
        self.commit(None)
        self.assertEqual(self.run_script("HEAD").returncode, 0)

    def test_unknown_revision_exits_2(self) -> None:
        self.commit(b"a")
        result = self.run_script("no-such-rev")
        self.assertEqual(result.returncode, 2)
        self.assertTrue(result.stderr.strip())

    def test_counts_bytes_not_characters(self) -> None:
        text = "é" * 52_501  # 52,501 characters, 105,002 bytes
        self.commit(text.encode("utf-8"))
        result = self.run_script("HEAD")
        self.assertEqual(result.returncode, 1)
        self.assertIn("105002", result.stderr)

    def test_no_argument_exits_2(self) -> None:
        self.commit(b"a")
        self.assertEqual(self.run_script().returncode, 2)

    def test_extra_argument_exits_2(self) -> None:
        self.commit(b"a")
        self.assertEqual(self.run_script("HEAD", "extra").returncode, 2)

    def test_unreadable_claude_md_blob_exits_2(self) -> None:
        # ls-tree lists the entry without reading the blob; git show then fails.
        self.commit(b"unreadable blob")
        blob = subprocess.run(
            ["git", "rev-parse", "HEAD:CLAUDE.md"],
            cwd=self.repo,
            env=_env(),
            check=True,
            capture_output=True,
            text=True,
            stdin=subprocess.DEVNULL,
        ).stdout.strip()
        (self.repo / ".git" / "objects" / blob[:2] / blob[2:]).unlink()
        result = self.run_script("HEAD")
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("must be a regular file", result.stderr)
        self.assertTrue(result.stderr.strip())

    def test_pass_prints_size_line(self) -> None:
        self.commit(b"a" * 1234)
        result = self.run_script("HEAD")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(
            result.stdout.strip(),
            "CLAUDE.md at HEAD is 1234 bytes (ceiling 105000).",
        )

    def test_absent_prints_absent_line(self) -> None:
        self.commit(None)
        result = self.run_script("HEAD")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(
            result.stdout.strip(),
            "CLAUDE.md absent at HEAD; nothing to measure.",
        )

    def test_subdirectory_run_sees_root_claude_md(self) -> None:
        self.commit(b"a" * (CEILING + 1))
        sub = self.repo / "sub"
        sub.mkdir()
        self.assertEqual(self.run_script("HEAD", cwd=sub).returncode, 1)

    def commit_symlink(self, target_content: bytes) -> None:
        (self.repo / "real.md").write_bytes(target_content)
        (self.repo / "CLAUDE.md").symlink_to("real.md")
        _git(self.repo, "add", "real.md", "CLAUDE.md")
        _git(self.repo, "commit", "-q", "-m", "symlink")

    def assert_not_regular(self, description: str) -> None:
        result = self.run_script("HEAD")
        self.assertEqual(result.returncode, 1)
        self.assertIn(
            f"CLAUDE.md at HEAD must be a regular file, but it is {description}.",
            result.stderr,
        )
        self.assertIn("Commit CLAUDE.md as a regular file.", result.stderr)
        # Shrinking does not help a mode refusal, so no size remedy.
        self.assertNotIn("ceiling", result.stderr)
        self.assertNotIn("bytes", result.stderr)

    def test_symlink_to_big_file_refused(self) -> None:
        self.commit_symlink(b"a" * (CEILING + 5000))
        self.assert_not_regular("a symlink (git mode 120000)")

    def test_symlink_to_small_file_refused(self) -> None:
        self.commit_symlink(b"a")
        self.assert_not_regular("a symlink (git mode 120000)")

    def test_gitlink_refused(self) -> None:
        self.commit(None)
        _git(
            self.repo,
            "update-index",
            "--add",
            "--cacheinfo",
            "160000,1111111111111111111111111111111111111111,CLAUDE.md",
        )
        _git(self.repo, "commit", "-q", "-m", "gitlink")
        self.assert_not_regular("a submodule (git mode 160000)")

    def test_directory_refused(self) -> None:
        (self.repo / "CLAUDE.md").mkdir()
        (self.repo / "CLAUDE.md" / "inner.txt").write_text("x")
        _git(self.repo, "add", "CLAUDE.md/inner.txt")
        _git(self.repo, "commit", "-q", "-m", "dir")
        self.assert_not_regular("a directory (git mode 040000)")

    def test_unrecognised_mode_uses_generic_description(self) -> None:
        # git canonicalises modes, so feed the module a listing it cannot normalise.
        spec = importlib.util.spec_from_file_location("claude_md_budget", SCRIPT)
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        listing = subprocess.CompletedProcess(
            [], 0, stdout=b"100664 blob abc\tCLAUDE.md\n", stderr=b""
        )
        stderr = io.StringIO()
        with (
            unittest.mock.patch.object(module, "_git", return_value=listing),
            contextlib.redirect_stderr(stderr),
        ):
            rc = module.main(["HEAD"])
        self.assertEqual(rc, 1)
        self.assertIn(
            "CLAUDE.md at HEAD must be a regular file, but it is git mode 100664. "
            "Commit CLAUDE.md as a regular file.",
            stderr.getvalue(),
        )

    def test_executable_regular_file_sized_normally(self) -> None:
        (self.repo / "CLAUDE.md").write_bytes(b"a" * CEILING)
        (self.repo / "CLAUDE.md").chmod(0o755)
        _git(self.repo, "add", "CLAUDE.md")
        _git(self.repo, "commit", "-q", "-m", "exec")
        self.assertEqual(self.run_script("HEAD").returncode, 0)
        (self.repo / "CLAUDE.md").write_bytes(b"a" * (CEILING + 1))
        _git(self.repo, "add", "CLAUDE.md")
        _git(self.repo, "commit", "-q", "-m", "exec big")
        result = self.run_script("HEAD")
        self.assertEqual(result.returncode, 1)
        self.assertIn("105001", result.stderr)

    def test_over_ceiling_has_no_mode_remedy(self) -> None:
        self.commit(b"a" * (CEILING + 1))
        result = self.run_script("HEAD")
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("regular file", result.stderr)


if __name__ == "__main__":
    unittest.main()
