"""Offline dependency-gate regressions using disposable local Git fixtures."""
from __future__ import annotations

import contextlib
import importlib.util
import io
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "verify_submodules.py"
SPEC = importlib.util.spec_from_file_location("verify_submodules", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Cannot import the dependency verifier.")
verifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verifier)


class VerifySubmodulesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="alev4-dependency-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "repository with spaces"
        self.root.mkdir()
        self.git(self.root, "init", "-q")
        self.pins: dict[str, str] = {}
        declarations = []
        for path, url in verifier.EXPECTED.items():
            module = self.root / path
            module.mkdir(parents=True)
            self.git(module, "init", "-q")
            (module / "fixture.txt").write_text(f"{path}\n", encoding="utf-8")
            (module / ".gitignore").write_text("ignored/\n", encoding="utf-8")
            self.git(module, "add", "fixture.txt", ".gitignore")
            self.git(module, "commit", "-qm", "Offline fixture")
            self.git(module, "remote", "add", "origin", url)
            self.pins[path] = self.git(module, "rev-parse", "HEAD").strip()
            self.git(self.root, "update-index", "--add", "--cacheinfo", f"160000,{self.pins[path]},{path}")
            declarations.append(f'[submodule "{path}"]\n\tpath = {path}\n\turl = {url}\n')
        (self.root / ".gitmodules").write_text("".join(declarations), encoding="utf-8")
        self.git(self.root, "add", ".gitmodules")
        self.git(self.root, "commit", "-qm", "Pin offline dependency fixtures")
        self.first_path = next(iter(verifier.EXPECTED))
        self.module = self.root / self.first_path

    @staticmethod
    def git(root: Path, *arguments: str) -> str:
        environment = os.environ.copy()
        for name in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"):
            environment.pop(name, None)
        environment.update({
            "GIT_AUTHOR_NAME": "Offline Test",
            "GIT_AUTHOR_EMAIL": "offline@example.invalid",
            "GIT_COMMITTER_NAME": "Offline Test",
            "GIT_COMMITTER_EMAIL": "offline@example.invalid",
            "GIT_TERMINAL_PROMPT": "0",
        })
        return subprocess.run(
            ["git", "-C", str(root), *arguments],
            env=environment, check=True, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        ).stdout

    def test_default_and_checkout_modes_accept_clean_pins(self) -> None:
        self.assertEqual(verifier.verify_submodules(self.root), self.pins)
        self.assertEqual(verifier.verify_submodules(self.root, require_checkout=True), self.pins)

    def test_default_mode_does_not_require_initialized_checkouts(self) -> None:
        (self.module / ".git").rename(self.module / "detached-git-fixture")
        self.assertEqual(verifier.verify_submodules(self.root), self.pins)
        with self.assertRaisesRegex(verifier.VerificationError, "Uninitialized"):
            verifier.verify_submodules(self.root, require_checkout=True)

    def test_checkout_cannot_inherit_parent_git_repository(self) -> None:
        # A .git pointer intentionally resolving to the parent must not pass
        # merely because git rev-parse succeeds somewhere above the directory.
        (self.module / ".git").rename(self.module / "detached-git-fixture")
        (self.module / ".git").write_text("gitdir: ../../.git\n", encoding="utf-8")
        with self.assertRaises(verifier.VerificationError):
            verifier.verify_submodules(self.root, require_checkout=True)

    def test_wrong_checkout_commit_is_rejected(self) -> None:
        (self.module / "fixture.txt").write_text("new revision\n", encoding="utf-8")
        self.git(self.module, "add", "fixture.txt")
        self.git(self.module, "commit", "-qm", "Advance dependency")
        with self.assertRaisesRegex(verifier.VerificationError, "HEAD differs"):
            verifier.verify_submodules(self.root, require_checkout=True)

    def test_tracked_edits_are_rejected(self) -> None:
        (self.module / "fixture.txt").write_text("local edit\n", encoding="utf-8")
        with self.assertRaisesRegex(verifier.VerificationError, "tracked or untracked"):
            verifier.verify_submodules(self.root, require_checkout=True)

    def test_staged_edits_are_rejected(self) -> None:
        (self.module / "fixture.txt").write_text("staged edit\n", encoding="utf-8")
        self.git(self.module, "add", "fixture.txt")
        with self.assertRaisesRegex(verifier.VerificationError, "tracked or untracked"):
            verifier.verify_submodules(self.root, require_checkout=True)

    def test_untracked_files_are_rejected(self) -> None:
        (self.module / "new-file.txt").write_text("not reviewed\n", encoding="utf-8")
        with self.assertRaisesRegex(verifier.VerificationError, "tracked or untracked"):
            verifier.verify_submodules(self.root, require_checkout=True)

    def test_ignored_data_is_allowed(self) -> None:
        ignored = self.module / "ignored"
        ignored.mkdir()
        (ignored / "simulation.dat").write_bytes(b"temporary data")
        self.assertEqual(verifier.verify_submodules(self.root, require_checkout=True), self.pins)

    def test_wrong_origin_is_rejected_without_disclosing_credentials(self) -> None:
        secret = "do-not-print-this-token"
        self.git(self.module, "remote", "set-url", "origin", f"https://user:{secret}@example.invalid/other.git")
        with self.assertRaisesRegex(verifier.VerificationError, "origin differs") as captured:
            verifier.verify_submodules(self.root, require_checkout=True)
        self.assertNotIn(secret, str(captured.exception))
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            status = verifier.main(["--root", str(self.root), "--require-checkout"])
        self.assertEqual(status, 1)
        self.assertNotIn(secret, stderr.getvalue())

    def test_missing_origin_is_rejected(self) -> None:
        self.git(self.module, "remote", "remove", "origin")
        with self.assertRaisesRegex(verifier.VerificationError, "origin URL"):
            verifier.verify_submodules(self.root, require_checkout=True)

    def test_wrong_gitmodules_url_is_rejected_without_echo(self) -> None:
        secret = "hidden-url-password"
        path = self.root / ".gitmodules"
        text = path.read_text(encoding="utf-8")
        text = text.replace(next(iter(verifier.EXPECTED.values())), f"https://name:{secret}@example.invalid/repo.git")
        path.write_text(text, encoding="utf-8")
        with self.assertRaisesRegex(verifier.VerificationError, "Unexpected submodule") as captured:
            verifier.verify_submodules(self.root)
        self.assertNotIn(secret, str(captured.exception))

    def test_missing_or_malformed_declaration_fails(self) -> None:
        declaration = self.root / ".gitmodules"
        declaration.unlink()
        with self.assertRaisesRegex(verifier.VerificationError, "valid .gitmodules"):
            verifier.verify_submodules(self.root)
        declaration.write_text("[broken declaration\n", encoding="utf-8")
        with self.assertRaisesRegex(verifier.VerificationError, "valid .gitmodules"):
            verifier.verify_submodules(self.root)

    def test_missing_section_or_path_fails(self) -> None:
        declaration = self.root / ".gitmodules"
        original = declaration.read_text(encoding="utf-8")
        declaration.write_text("", encoding="utf-8")
        with self.assertRaisesRegex(verifier.VerificationError, "Missing .gitmodules section"):
            verifier.verify_submodules(self.root)
        declaration.write_text(original.replace(f"\tpath = {self.first_path}\n", ""), encoding="utf-8")
        with self.assertRaisesRegex(verifier.VerificationError, "Unexpected submodule"):
            verifier.verify_submodules(self.root)

    def test_plain_file_instead_of_committed_gitlink_fails(self) -> None:
        blob = self.git(self.root, "hash-object", "-w", "--", ".gitmodules").strip()
        self.git(self.root, "update-index", "--cacheinfo", f"100644,{blob},{self.first_path}")
        self.git(self.root, "commit", "-qm", "Replace dependency with ordinary blob")
        with self.assertRaisesRegex(verifier.VerificationError, "not a pinned Git submodule"):
            verifier.verify_submodules(self.root)

    def test_cli_success(self) -> None:
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            status = verifier.main(["--root", str(self.root), "--require-checkout"])
        self.assertEqual(status, 0)
        self.assertIn("clean matching checkouts", stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
