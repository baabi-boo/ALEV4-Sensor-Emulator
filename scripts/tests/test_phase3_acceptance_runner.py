"""Acceptance orchestration contracts; mocked gates are not physics evidence.

Temporary output files exercise the actual receipt, copy, log, and checksum
paths. Only subprocess execution and Git snapshots are mocked so each failure
boundary can be selected without rerunning the numerical acceptance suite.
"""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "run_phase3_acceptance.py"
SPEC = importlib.util.spec_from_file_location("phase3_acceptance_runner", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Cannot import the Phase 3 acceptance runner.")
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
SOURCE = "1" * 40
GATES = (
    "dependencies-before", "python-tests", "all-numerical-gates",
    "phase1-runner-failures", "phase2-runner-failures", "phase3-runner-failures",
    "phase1-demo", "phase1-demo-repeat", "phase1-artifact-verification",
    "phase2-demo", "phase2-demo-repeat", "phase2-artifact-verification",
    "phase3-demo", "phase3-demo-repeat", "phase3-artifact-verification",
    "dependencies-after",
)


class Phase3AcceptanceRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="alev4-phase3-acceptance-unit-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.root = self.directory / "repository's"
        self.root.mkdir()
        self.args = argparse.Namespace(
            output_root=self.directory / "fresh output's",
            expected_commit=SOURCE, octave="fixture octave executable", development=False)
        self.start_status = ""
        self.end_status = ""
        self.end_source = SOURCE
        self.source_root = self.root
        self.head_reads = 0
        self.status_reads = 0
        self.fail_label = None
        self.fail_code = 19
        self.missing_label = None
        self.omit_numerical = None
        self.mutate_demo = None
        self.root_patch = mock.patch.object(runner, "ROOT", self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)
        self.git_patch = mock.patch.object(runner, "git", side_effect=self.git_snapshot)
        self.git_mock = self.git_patch.start()
        self.addCleanup(self.git_patch.stop)
        self.process_patch = mock.patch.object(runner.subprocess, "run", side_effect=self.command)
        self.process_mock = self.process_patch.start()
        self.addCleanup(self.process_patch.stop)

    def git_snapshot(self, *arguments: str) -> str:
        if arguments == ("rev-parse", "--show-toplevel"):
            return str(self.source_root)
        if arguments == ("rev-parse", "HEAD"):
            self.head_reads += 1
            return SOURCE if self.head_reads % 2 else self.end_source
        if arguments == ("rev-parse", "HEAD^{tree}"):
            return "2" * 40
        if arguments == ("status", "--porcelain=v1", "--untracked-files=all", "--ignore-submodules=none"):
            self.status_reads += 1
            return self.start_status if self.status_reads % 2 else self.end_status
        if arguments == ("ls-files", "-v", "-z"):
            return "H source.txt\0"
        if arguments == ("submodule", "foreach", "--quiet", "--recursive", "git ls-files -v -z"):
            return ""
        self.fail(f"Unexpected source query: {arguments!r}")

    def receipt(self) -> dict:
        return json.loads((self.args.output_root / "acceptance.json").read_text(encoding="utf-8"))

    def numerical_fixtures(self) -> None:
        validation = self.args.output_root / "phase3/validation"
        paths = {
            1: validation / "phase2-regression/phase1-regression/phase1-validation.json",
            2: validation / "phase2-regression/phase2-validation.json",
            3: validation / "phase3-validation.json",
        }
        for phase, path in paths.items():
            if self.omit_numerical == phase:
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps({
                "schema_version": "1.0", "phase": phase, "status": "passed",
                f"phase{phase}_passed": True, "fixture_only": True,
            }), encoding="utf-8")

    def command(self, argv, *, cwd, stdout, stderr, env, check):
        self.assertEqual(cwd, self.root)
        self.assertIs(check, False)
        self.assertFalse(any(name.startswith("GIT_") for name in env))
        label = self.receipt()["commands"][-1]["label"]
        if label == self.missing_label:
            raise FileNotFoundError("Required gate executable is unavailable.")
        if label == "all-numerical-gates":
            self.numerical_fixtures()
        if label.endswith(("-demo", "-demo-repeat")):
            phase, suffix = label.split("-", 1)
            directory = self.args.output_root / phase / suffix
            (directory / "nested").mkdir(parents=True)
            for path in (directory / "payload.bin", directory / "nested/metadata.json"):
                path.write_bytes(b"artificial acceptance fixture only\n")
            if self.mutate_demo:
                self.mutate_demo(int(phase[-1]), suffix, directory)
        stdout.write(json.dumps({"status": "passed", "fixture_only": True}).encode("utf-8"))
        stderr.write(b"temporary gate diagnostic\n")
        return subprocess.CompletedProcess(argv, self.fail_code if label == self.fail_label else 0)

    def execute(self) -> dict:
        with contextlib.redirect_stdout(io.StringIO()):
            return runner.execute(self.args)

    def assert_failed_receipt(self, label: str | None = None) -> dict:
        receipt = self.receipt()
        self.assertEqual(receipt["status"], "failed")
        self.assertIs(receipt["release_accepted"], False)
        self.assertTrue(receipt["error"])
        self.assertIn("finished_utc", receipt)
        if label:
            self.assertEqual(receipt["commands"][-1]["label"], label)
        return receipt

    def test_clean_control_executes_every_gate_and_records_file_hashes(self) -> None:
        receipt = self.execute()
        self.assertEqual(receipt["status"], "passed")
        self.assertIs(receipt["release_accepted"], True)
        self.assertIs(receipt["source_clean_at_start"], True)
        self.assertIs(receipt["source_clean_at_end"], True)
        self.assertEqual(receipt["source_revision"], SOURCE)
        self.assertEqual([entry["label"] for entry in receipt["commands"]], list(GATES))
        self.assertEqual([entry["phase"] for entry in receipt["repeat_identity_checks"]], [1, 2, 3])
        for check in receipt["repeat_identity_checks"]:
            self.assertEqual(check["status"], "passed")
            self.assertIs(check["nonaliased"], True)
            self.assertEqual(check["primary_file_count"], 2)
            self.assertEqual(check["repeat_file_count"], 2)
        for entry in receipt["commands"]:
            self.assertEqual(entry["exit_code"], 0)
            if entry["label"].startswith("dependencies-"):
                self.assertIn("--require-checkout", entry["argv"])
            if entry["label"].endswith("-artifact-verification"):
                argv = entry["argv"]
                self.assertEqual(argv[argv.index("--expected-commit") + 1], SOURCE)
                self.assertIn("--compare-dir", argv)
                self.assertNotEqual(Path(argv[2]) / "demo", Path(argv[argv.index("--compare-dir") + 1]))
        numerical = receipt["commands"][2]["argv"]
        self.assertEqual(numerical[0], self.args.octave)
        self.assertIn("run_phase3_tests(", numerical[-1])
        self.assertIn(",true)", numerical[-1])
        self.assertIn("assert(r.phase3_passed)", numerical[-1])
        self.assertIn("output''s", numerical[-1])
        self.assertNotIn("acceptance.json", receipt["files"])
        for relative, descriptor in receipt["files"].items():
            content = (self.args.output_root / relative).read_bytes()
            self.assertEqual(descriptor, {"bytes": len(content), "sha256": hashlib.sha256(content).hexdigest()})

    def test_dirty_start_cannot_release_or_execute_gates(self) -> None:
        for status in (" M matlab/source.m", "M  matlab/source.m", "?? new-source.m", " m third_party/isetcam"):
            with self.subTest(status=status):
                self.head_reads = self.status_reads = 0
                self.start_status = status
                with self.assertRaisesRegex(ValueError, "clean source worktree"):
                    self.execute()
                self.assertFalse(self.args.output_root.exists())
                self.process_mock.assert_not_called()

    def test_source_must_be_actual_worktree_root(self) -> None:
        self.source_root = self.directory / "different-worktree"
        with self.assertRaisesRegex(ValueError, "actual repository worktree root"):
            self.execute()
        self.assertFalse(self.args.output_root.exists())
        self.process_mock.assert_not_called()

    def test_every_gate_removes_git_overrides_and_preserves_other_environment(self) -> None:
        contaminated = {"GIT_DIR": "/unrelated/repository", "GIT_WORK_TREE": "/unrelated/tree",
                        "GIT_INDEX_FILE": "/unrelated/index", "GIT_COMMON_DIR": "/unrelated/common",
                        "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "core.worktree",
                        "GIT_CONFIG_VALUE_0": "/unrelated/tree", "GIT_CONFIG_PARAMETERS": "redirected",
                        "GIT_FUTURE_OVERRIDE": "redirected", "ALEV4_ACCEPTANCE_ENV_TEST": "retained"}
        with mock.patch.dict(os.environ, contaminated):
            self.execute()
        self.assertEqual(self.process_mock.call_count, len(GATES))
        for call in self.process_mock.call_args_list:
            environment = call.kwargs["env"]
            self.assertFalse(any(name.startswith("GIT_") for name in environment))
            self.assertEqual(environment["ALEV4_ACCEPTANCE_ENV_TEST"], "retained")

    def test_wrong_expected_revision_is_rejected_before_output_creation(self) -> None:
        self.args.expected_commit = "3" * 40
        with self.assertRaisesRegex(ValueError, "source revision"):
            self.execute()
        self.assertFalse(self.args.output_root.exists())
        self.process_mock.assert_not_called()

    def test_source_revision_change_cannot_release(self) -> None:
        self.end_source = "4" * 40
        with self.assertRaisesRegex(RuntimeError, "Source revision changed"):
            self.execute()
        self.assert_failed_receipt("dependencies-after")

    def test_source_becoming_dirty_cannot_release(self) -> None:
        for index, status in enumerate((" M matlab/source.m", "?? new-source.m", " m third_party/isetcam")):
            with self.subTest(status=status):
                self.args.output_root = self.directory / f"changed-source-{index}"
                self.head_reads = self.status_reads = 0
                self.end_status = status
                with self.assertRaisesRegex(RuntimeError, "worktree changed"):
                    self.execute()
                receipt = self.assert_failed_receipt("dependencies-after")
                self.assertIs(receipt["source_clean_at_end"], False)

    def test_development_success_is_never_release_acceptance(self) -> None:
        for index, status in enumerate(("", " M matlab/source.m")):
            with self.subTest(status=status):
                self.args.output_root = self.directory / f"development-{index}"
                self.args.development = True
                self.head_reads = self.status_reads = 0
                self.start_status = self.end_status = status
                receipt = self.execute()
                self.assertEqual(receipt["status"], "development_passed")
                self.assertIs(receipt["release_accepted"], False)
                self.assertEqual(len(receipt["commands"]), len(GATES))

    def test_nonzero_exit_from_every_required_gate_stops_acceptance(self) -> None:
        for index, label in enumerate(GATES):
            with self.subTest(gate=label):
                self.args.output_root = self.directory / f"failed-gate-{index}"
                self.head_reads = self.status_reads = 0
                self.fail_label = label
                with self.assertRaisesRegex(RuntimeError, "failed with exit 19"):
                    self.execute()
                receipt = self.assert_failed_receipt(label)
                self.assertEqual(receipt["commands"][-1]["exit_code"], 19)
                self.assertEqual([entry["label"] for entry in receipt["commands"]], list(GATES[:index + 1]))

    def test_nonzero_current_process_overrides_successful_numerical_report(self) -> None:
        self.fail_label = "all-numerical-gates"
        with self.assertRaises(RuntimeError):
            self.execute()
        numerical = self.args.output_root / "phase3/validation/phase3-validation.json"
        self.assertIs(json.loads(numerical.read_text())["phase3_passed"], True)
        self.assert_failed_receipt("all-numerical-gates")

    def test_missing_gate_executable_cannot_release(self) -> None:
        for index, label in enumerate(("all-numerical-gates", "phase3-runner-failures", "phase3-artifact-verification")):
            with self.subTest(gate=label):
                self.args.output_root = self.directory / f"missing-gate-{index}"
                self.head_reads = self.status_reads = 0
                self.missing_label = label
                with self.assertRaises(FileNotFoundError):
                    self.execute()
                receipt = self.assert_failed_receipt(label)
                self.assertIsNone(receipt["commands"][-1]["exit_code"])

    def test_zero_exit_without_required_prerequisite_reports_cannot_release(self) -> None:
        for phase in (1, 2):
            with self.subTest(phase=phase):
                self.args.output_root = self.directory / f"missing-report-{phase}"
                self.head_reads = self.status_reads = 0
                self.omit_numerical = phase
                with self.assertRaises(FileNotFoundError):
                    self.execute()
                self.assert_failed_receipt()

    def test_same_and_cross_filename_hardlinked_repeats_cannot_release(self) -> None:
        for phase in (1, 2, 3):
            for cross_filename in (False, True):
                with self.subTest(phase=phase, cross_filename=cross_filename):
                    self.args.output_root = self.directory / f"hardlink-{phase}-{cross_filename}"
                    self.head_reads = self.status_reads = 0

                    def alias(number, suffix, directory):
                        if number == phase and suffix == "demo-repeat":
                            source = directory.parent / "demo/payload.bin"
                            target = directory / ("nested/metadata.json" if cross_filename else "payload.bin")
                            target.unlink()
                            os.link(source, target)

                    self.mutate_demo = alias
                    with self.assertRaisesRegex(ValueError, "alias primary files"):
                        self.execute()
                    receipt = self.assert_failed_receipt(f"phase{phase}-demo-repeat")
                    check = receipt["repeat_identity_checks"][-1]
                    self.assertEqual(check["phase"], phase)
                    self.assertEqual(check["status"], "failed")
                    self.assertIs(check["nonaliased"], False)
                    self.assertEqual(check["primary_file_count"], 2)
                    self.assertEqual(check["repeat_file_count"], 2)
                    self.assertNotIn(f"phase{phase}-artifact-verification",
                                     [entry["label"] for entry in receipt["commands"]])

    def test_symlink_demo_roots_files_and_nested_directories_cannot_release(self) -> None:
        for kind in ("primary-root", "repeat-root", "primary-file", "repeat-directory", "phase-root"):
            with self.subTest(kind=kind):
                self.args.output_root = self.directory / kind
                self.head_reads = self.status_reads = 0

                def alias(number, suffix, directory):
                    if number != 1 or suffix != "demo-repeat":
                        return
                    primary = directory.parent / "demo"
                    if kind == "repeat-root":
                        shutil.rmtree(directory)
                        directory.symlink_to(primary, target_is_directory=True)
                    else:
                        target = primary if kind == "primary-root" else primary / "payload.bin" \
                            if kind == "primary-file" else directory / "nested" \
                            if kind == "repeat-directory" else directory.parent
                        saved = target.with_name(target.name + "-saved")
                        target.rename(saved)
                        target.symlink_to(saved, target_is_directory=saved.is_dir())

                self.mutate_demo = alias
                with self.assertRaisesRegex(ValueError, "symlink"):
                    self.execute()
                receipt = self.assert_failed_receipt("phase1-demo-repeat")
                self.assertEqual(receipt["repeat_identity_checks"][-1]["status"], "failed")
                self.assertIs(receipt["repeat_identity_checks"][-1]["nonaliased"], False)

    def test_zero_exit_without_demo_files_cannot_release(self) -> None:
        for missing in (False, True):
            with self.subTest(missing=missing):
                self.args.output_root = self.directory / f"missing-demo-{missing}"
                self.head_reads = self.status_reads = 0

                def remove(number, suffix, directory):
                    if number == 1 and suffix == "demo-repeat":
                        shutil.rmtree(directory)
                        if not missing:
                            directory.mkdir()

                self.mutate_demo = remove
                with self.assertRaises((ValueError, FileNotFoundError)):
                    self.execute()
                receipt = self.assert_failed_receipt("phase1-demo-repeat")
                self.assertEqual(receipt["repeat_identity_checks"][-1]["status"], "failed")
                self.assertIs(receipt["repeat_identity_checks"][-1]["nonaliased"], False)

    def test_existing_directory_is_refused_without_overwriting_evidence(self) -> None:
        self.args.output_root.mkdir()
        evidence = self.args.output_root / "acceptance.json"
        previous = b'{"status":"passed","release_accepted":true}\n'
        evidence.write_bytes(previous)
        with self.assertRaisesRegex(ValueError, "new directory"):
            self.execute()
        self.assertEqual(evidence.read_bytes(), previous)
        self.process_mock.assert_not_called()
        self.git_mock.assert_not_called()

    def test_existing_file_is_refused(self) -> None:
        self.args.output_root.write_bytes(b"keep this existing file\n")
        with self.assertRaisesRegex(ValueError, "new directory"):
            self.execute()
        self.assertEqual(self.args.output_root.read_bytes(), b"keep this existing file\n")
        self.process_mock.assert_not_called()

    def test_dangling_output_symlink_is_refused_before_resolution(self) -> None:
        destination = self.directory / "must remain absent"
        self.args.output_root.symlink_to(destination, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "new directory"):
            self.execute()
        self.assertTrue(self.args.output_root.is_symlink())
        self.assertFalse(destination.exists())
        self.git_mock.assert_not_called()
        self.process_mock.assert_not_called()

    def test_symlink_to_existing_evidence_is_refused(self) -> None:
        destination = self.directory / "existing evidence"
        destination.mkdir()
        evidence = destination / "acceptance.json"
        evidence.write_bytes(b"prior evidence\n")
        self.args.output_root.symlink_to(destination, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "new directory"):
            self.execute()
        self.assertEqual(evidence.read_bytes(), b"prior evidence\n")
        self.process_mock.assert_not_called()

    def test_successful_output_cannot_be_reused(self) -> None:
        self.execute()
        evidence = self.args.output_root / "acceptance.json"
        previous = evidence.read_bytes()
        self.process_mock.reset_mock()
        with self.assertRaisesRegex(ValueError, "new directory"):
            self.execute()
        self.assertEqual(evidence.read_bytes(), previous)
        self.process_mock.assert_not_called()


class Phase3AcceptanceIndexFlagsTests(unittest.TestCase):
    """Real recursive Git indexes with artificial external acceptance gates."""

    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="alev4-phase3-index-flags-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.root = self.directory / "repository's"
        self.environment = {name: value for name, value in os.environ.items() if not name.startswith("GIT_")}
        self.real_run = subprocess.run

        def initialize(directory: Path) -> None:
            directory.mkdir()
            self.local_git("init", "--quiet", root=directory)
            (directory / "source.txt").write_text("committed temporary fixture\n", encoding="utf-8")
            self.local_git("add", "source.txt", root=directory)
            self.local_git("commit", "--quiet", "-m", "Temporary acceptance fixture", root=directory)

        leaf, dependency = self.directory / "leaf", self.directory / "dependency"
        for directory in (leaf, dependency, self.root):
            initialize(directory)
        self.local_git("submodule", "add", "--quiet", str(leaf), "nested", root=dependency)
        self.local_git("commit", "--quiet", "-am", "Temporary nested gitlink", root=dependency)
        self.local_git("submodule", "add", "--quiet", str(dependency), "third_party/dependency")
        self.local_git("commit", "--quiet", "-am", "Temporary dependency gitlink")
        self.local_git("submodule", "update", "--init", "--recursive", "--quiet")
        self.source = self.local_git("rev-parse", "HEAD")
        checked_dependency = self.root / "third_party/dependency"
        self.targets = (
            ("root-file", self.root, "source.txt"),
            ("dependency-file", checked_dependency, "source.txt"),
            ("nested-file", checked_dependency / "nested", "source.txt"),
            ("root-gitlink", self.root, "third_party/dependency"),
            ("nested-gitlink", checked_dependency, "nested"),
        )
        self.args = argparse.Namespace(output_root=self.directory / "output", expected_commit=self.source,
                                       octave="fixture octave executable", development=False)
        self.labels = []
        self.mutate_at_end = None
        root_patch = mock.patch.object(runner, "ROOT", self.root)
        root_patch.start()
        self.addCleanup(root_patch.stop)
        process_patch = mock.patch.object(runner.subprocess, "run", side_effect=self.command)
        process_patch.start()
        self.addCleanup(process_patch.stop)

    def local_git(self, *arguments: str, root: Path | None = None) -> str:
        return self.real_run(
            ["git", "-C", str(root or self.root), "-c", "user.name=Acceptance fixture",
             "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false",
             "-c", "core.hooksPath=/dev/null", "-c", "protocol.file.allow=always", *arguments],
            env=self.environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            check=True).stdout.strip()

    def receipt(self) -> dict:
        return json.loads((self.args.output_root / "acceptance.json").read_text(encoding="utf-8"))

    def command(self, argv, **kwargs):
        if argv[0] == "git":
            return self.real_run(argv, **kwargs)
        label = self.receipt()["commands"][-1]["label"]
        self.assertEqual(label, GATES[len(self.labels)])
        self.labels.append(label)
        self.assertFalse(any(name.startswith("GIT_") for name in kwargs["env"]))
        if label == "all-numerical-gates":
            validation = self.args.output_root / "phase3/validation"
            for relative in ("phase3-validation.json", "phase2-regression/phase2-validation.json",
                             "phase2-regression/phase1-regression/phase1-validation.json"):
                path = validation / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('{"fixture_only":true}\n', encoding="utf-8")
        if label.endswith(("-demo", "-demo-repeat")):
            phase, suffix = label.split("-", 1)
            path = self.args.output_root / phase / suffix / "payload.bin"
            path.parent.mkdir(parents=True)
            path.write_bytes(b"artificial acceptance fixture only\n")
        if label == "dependencies-after" and self.mutate_at_end:
            self.mutate_at_end()
        kwargs["stdout"].write(b'{"fixture_only":true}\n')
        return subprocess.CompletedProcess(argv, 0)

    @contextlib.contextmanager
    def flagged_source(self, target, flag: str, at_end: bool = False):
        name, root, relative = target
        path = root / relative
        original = path.read_bytes() if path.is_file() else None

        def apply() -> None:
            self.local_git("update-index", flag, relative, root=root)
            if original is not None:
                path.write_bytes(original + b"uncommitted source hidden by an index flag\n")
            # Establish the actual false-negative status predicate. Gitlink
            # controls retain their bytes but must still reject these flags.
            self.assertEqual(self.local_git("status", "--porcelain=v1", "--untracked-files=all",
                                            "--ignore-submodules=none"), "")

        self.args.output_root = self.directory / f"{name}-{flag}-{at_end}"
        self.labels = []
        try:
            if at_end:
                self.mutate_at_end = apply
            else:
                apply()
            yield
        finally:
            self.mutate_at_end = None
            if original is not None:
                path.write_bytes(original)
            self.local_git("update-index", "--no-" + flag[2:], relative, root=root)

    def execute(self) -> dict:
        with contextlib.redirect_stdout(io.StringIO()):
            return runner.execute(self.args)

    def test_valid_recursive_checkout_keeps_all_external_gates(self) -> None:
        receipt = self.execute()
        self.assertEqual(self.labels, list(GATES))
        self.assertEqual(receipt["status"], "passed")
        self.assertIs(receipt["release_accepted"], True)
        self.assertIs(receipt["source_clean_at_start"], True)
        self.assertIs(receipt["source_clean_at_end"], True)

    def test_root_and_recursive_index_flags_reject_release_before_gates(self) -> None:
        for target in self.targets:
            for flag in ("--assume-unchanged", "--skip-worktree"):
                with self.subTest(target=target[0], flag=flag), self.flagged_source(target, flag):
                    with self.assertRaisesRegex(ValueError, "clean source worktree"):
                        self.execute()
                    self.assertFalse(self.args.output_root.exists())
                    self.assertEqual(self.labels, [])

    def test_root_and_recursive_index_flags_reject_release_after_gates(self) -> None:
        for target in self.targets:
            for flag in ("--assume-unchanged", "--skip-worktree"):
                with self.subTest(target=target[0], flag=flag), self.flagged_source(target, flag, at_end=True):
                    with self.assertRaisesRegex(RuntimeError, "worktree changed"):
                        self.execute()
                    receipt = self.receipt()
                    self.assertEqual(self.labels, list(GATES))
                    self.assertEqual(receipt["status"], "failed")
                    self.assertIs(receipt["release_accepted"], False)
                    self.assertIs(receipt["source_clean_at_start"], True)
                    self.assertIs(receipt["source_clean_at_end"], False)

    def test_development_receipts_treat_index_flags_as_unclean(self) -> None:
        self.args.development = True
        for target in self.targets:
            for flag in ("--assume-unchanged", "--skip-worktree"):
                for at_end in (False, True):
                    with self.subTest(target=target[0], flag=flag, at_end=at_end), \
                            self.flagged_source(target, flag, at_end=at_end):
                        receipt = self.execute()
                        self.assertEqual(self.labels, list(GATES))
                        self.assertEqual(receipt["status"], "development_passed")
                        self.assertIs(receipt["release_accepted"], False)
                        self.assertIs(receipt["source_clean_at_start"], at_end)
                        self.assertIs(receipt["source_clean_at_end"], False)


class Phase3AcceptanceGitEnvironmentTests(unittest.TestCase):
    """Use actual Git reads to guard against inspecting a clean decoy tree."""

    def test_dirty_source_cannot_be_hidden_by_caller_git_overrides(self) -> None:
        with tempfile.TemporaryDirectory(prefix="alev4-phase3-git-env-") as temporary:
            directory = Path(temporary)
            repository, decoy = directory / "repository", directory / "clean-copy"
            repository.mkdir()
            environment = {name: value for name, value in os.environ.items() if not name.startswith("GIT_")}

            def local_git(*arguments, root=repository, env=environment):
                return subprocess.check_output(["git", "-C", str(root), *arguments],
                                               env=env, text=True, stderr=subprocess.PIPE).strip()

            local_git("init", "--quiet")
            source_file = repository / "source.txt"
            source_file.write_text("committed temporary fixture\n", encoding="utf-8")
            local_git("add", "source.txt")
            local_git("-c", "user.name=Acceptance fixture", "-c", "user.email=fixture@example.invalid",
                      "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
                      "commit", "--quiet", "-m", "Temporary acceptance environment fixture")
            source = local_git("rev-parse", "HEAD")
            local_git("clone", "--quiet", "--no-hardlinks", str(repository), str(decoy), root=directory)
            source_file.write_text("uncommitted source change\n", encoding="utf-8")
            status = ("status", "--porcelain=v1", "--untracked-files=all", "--ignore-submodules=none")
            self.assertTrue(local_git(*status))
            self.assertEqual(local_git(*status, root=decoy), "")
            overrides = (
                {"GIT_WORK_TREE": str(decoy)},
                {"GIT_DIR": str(decoy / ".git"), "GIT_WORK_TREE": str(decoy),
                 "GIT_INDEX_FILE": str(decoy / ".git/index"), "GIT_COMMON_DIR": str(decoy / ".git")},
                {"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "alev4.acceptancefixture",
                 "GIT_CONFIG_VALUE_0": "caller-override"},
                {"GIT_CONFIG_PARAMETERS": "'alev4.acceptancefixture=caller-override'"},
            )
            for index, override in enumerate(overrides):
                with self.subTest(override=tuple(override)):
                    # Establish real redirection/config injection before testing
                    # the production helper's environment isolation.
                    if index < 2:
                        self.assertEqual(local_git(*status, env={**environment, **override}), "")
                    else:
                        self.assertEqual(local_git("config", "--get", "alev4.acceptancefixture",
                                                   env={**environment, **override}), "caller-override")
                    args = argparse.Namespace(output_root=directory / f"output-{index}",
                                              expected_commit=source, octave="unneeded", development=False)
                    with mock.patch.object(runner, "ROOT", repository), mock.patch.dict(os.environ, override):
                        self.assertTrue(runner.git(*status))
                        if index >= 2:
                            with self.assertRaises(subprocess.CalledProcessError):
                                runner.git("config", "--get", "alev4.acceptancefixture")
                        with self.assertRaisesRegex(ValueError, "clean source worktree"):
                            runner.execute(args)
                    self.assertFalse(args.output_root.exists())


if __name__ == "__main__":
    unittest.main()
