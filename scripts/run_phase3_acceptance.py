#!/usr/bin/env python3
"""Run Phase 3 plus preserved Phase 1/2 numerical, file, and repeat gates.

The default is an exact-revision release check and requires a clean worktree.
--development executes the same gates but never reports release acceptance.
All commands and exit statuses are retained; no missing gate is a pass.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def matlab_string(value: Path | str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def command_environment() -> dict[str, str]:
    # Caller overrides can redirect Git's worktree, index or configuration.
    # Apply the same isolation to child gates, including their Git reads.
    return {name: value for name, value in os.environ.items() if not name.startswith("GIT_")}


def git(*args: str) -> str:
    return subprocess.check_output(["git", "-C", str(ROOT), *args],
                                   text=True, env=command_environment()).strip()


def source_is_clean() -> bool:
    status = git("status", "--porcelain=v1", "--untracked-files=all", "--ignore-submodules=none")
    # Status can hide changed bytes when an index entry is assume-unchanged
    # (lowercase -v tag) or skip-worktree (S). Inspect every initialized index:
    # ls-files --recurse-submodules alone omits the gitlink entries themselves.
    indexes = (
        git("ls-files", "-v", "-z"),
        git("submodule", "foreach", "--quiet", "--recursive", "git ls-files -v -z"),
    )
    hidden = any(entry and (entry[0].islower() or entry[0] == "S")
                 for index in indexes for entry in index.split("\0"))
    return not status and not hidden


def artifact_identities(directory: Path) -> tuple[tuple[int, int], int, set[tuple[int, int]]]:
    """Inspect actual directory entries without accepting symlink artifacts."""
    root_stat = directory.lstat()
    if not stat.S_ISDIR(root_stat.st_mode):
        raise ValueError(f"Demo evidence needs a regular non-symlink directory: {directory}")
    identities = set()
    count = 0
    pending = [directory]
    while pending:
        for path in pending.pop().iterdir():
            information = path.lstat()
            if stat.S_ISDIR(information.st_mode):
                pending.append(path)
                continue
            if not stat.S_ISREG(information.st_mode):
                raise ValueError(f"Demo evidence contains a non-regular or symlink artifact: {path}")
            identities.add((information.st_dev, information.st_ino))
            count += 1
    if not count:
        raise ValueError(f"Demo evidence directory contains no artifact files: {directory}")
    return (root_stat.st_dev, root_stat.st_ino), count, identities


def execute(args: argparse.Namespace) -> dict:
    if args.output_root.exists() or args.output_root.is_symlink():
        raise ValueError("Acceptance output must be a new directory; existing evidence is never overwritten.")
    output = args.output_root.resolve()
    if output.exists() or output.is_symlink():
        raise ValueError("Acceptance output must be a new directory; existing evidence is never overwritten.")
    if Path(git("rev-parse", "--show-toplevel")).resolve() != ROOT.resolve():
        raise ValueError("Acceptance source must be the actual repository worktree root.")
    source = git("rev-parse", "HEAD")
    if args.expected_commit and args.expected_commit != source:
        raise ValueError("The requested source revision does not match the local checkout.")
    initial_clean = source_is_clean()
    if not initial_clean and not args.development:
        raise ValueError("Release acceptance requires a clean source worktree without assume-unchanged or "
                         "skip-worktree index flags; use --development for nonrelease checks.")
    output.mkdir(parents=True)
    logs = output / "logs"
    logs.mkdir()
    receipt = output / "acceptance.json"
    report = {
        "schema_version": "1.0", "phase": 3, "status": "running",
        "release_accepted": False, "development": args.development,
        "source_revision": source, "source_tree": git("rev-parse", "HEAD^{tree}"),
        "source_clean_at_start": initial_clean,
        "started_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "commands": [], "repeat_identity_checks": [],
        "synthetic": True, "calibrated_alev4": False,
        "native_matlab_executed": False,
    }

    def save() -> None:
        receipt.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    def command(label: str, argv: list[str], result: Path | None = None) -> None:
        index = len(report["commands"]) + 1
        stdout = result or logs / f"{index:02d}-{label}.stdout.txt"
        stderr = logs / f"{index:02d}-{label}.stderr.txt"
        stdout.parent.mkdir(parents=True, exist_ok=True)
        entry = {"label": label, "argv": argv, "exit_code": None,
                 "stdout": str(stdout.relative_to(output)), "stderr": str(stderr.relative_to(output))}
        report["commands"].append(entry)
        save()
        print(f"Running {label}", flush=True)
        with stdout.open("wb") as out, stderr.open("wb") as err:
            completed = subprocess.run(argv, cwd=ROOT, stdout=out, stderr=err,
                                       env=command_environment(), check=False)
        entry["exit_code"] = completed.returncode
        save()
        if completed.returncode:
            raise RuntimeError(f"{label} failed with exit {completed.returncode}; see {stdout} and {stderr}")

    def octave(label: str, code: str) -> None:
        command(label, [args.octave, "--no-gui", "--quiet", "--eval", "addpath('matlab'); " + code])

    def check_repeat_identity(number: int, phase: Path) -> None:
        entry = {"phase": number, "status": "running", "nonaliased": False,
                 "primary": str((phase / "demo").relative_to(output)),
                 "repeat": str((phase / "demo-repeat").relative_to(output)),
                 "primary_file_count": None, "repeat_file_count": None}
        report["repeat_identity_checks"].append(entry)
        save()
        try:
            # These are direct children of the newly created output root.
            # Reject a redirected phase directory as well as artifact links.
            if not stat.S_ISDIR(output.lstat().st_mode) or not stat.S_ISDIR(phase.lstat().st_mode):
                raise ValueError("Phase evidence needs regular non-symlink directories.")
            primary_root, count, primary_ids = artifact_identities(phase / "demo")
            entry["primary_file_count"] = count
            repeat_root, count, repeat_ids = artifact_identities(phase / "demo-repeat")
            entry["repeat_file_count"] = count
            if primary_root == repeat_root:
                raise ValueError("Repeated demo aliases the primary directory.")
            if not primary_ids.isdisjoint(repeat_ids):
                raise ValueError("Repeated demo artifacts alias primary files, including cross-filename aliases.")
            entry["status"] = "passed"
            entry["nonaliased"] = True
        except Exception as error:
            entry["status"] = "failed"
            entry["error"] = str(error)
            raise
        finally:
            save()

    save()
    try:
        command("dependencies-before", [sys.executable, "scripts/verify_submodules.py", "--require-checkout"])
        command("python-tests", [sys.executable, "-m", "unittest", "discover", "-s", "scripts/tests", "-v"])
        phase3 = output / "phase3"
        validation = phase3 / "validation"
        octave("all-numerical-gates", f"r=run_phase3_tests({matlab_string(validation)},true); assert(r.phase3_passed);")
        for number, script in ((1, "test_runner_failure.py"), (2, "test_phase2_runner_failure.py"),
                               (3, "test_phase3_runner_failure.py")):
            command(f"phase{number}-runner-failures", [sys.executable, f"scripts/{script}", "--octave", args.octave],
                    validation / f"phase{number}-runner-failures.json")
        # Each demo/repeat is a separate numerical process. No normalized or
        # ignored byte differences are allowed by the independent verifiers.
        for number in (1, 2, 3):
            phase = output / f"phase{number}"
            (phase / "validation").mkdir(parents=True, exist_ok=True)
            if number == 1:
                origin = validation / "phase2-regression/phase1-regression/phase1-validation.json"
            elif number == 2:
                origin = validation / "phase2-regression/phase2-validation.json"
            else:
                origin = None
            if origin is not None:
                shutil.copyfile(origin, phase / "validation" / f"phase{number}-validation.json")
            for suffix in ("demo", "demo-repeat"):
                octave(f"phase{number}-{suffix}",
                       f"setup_project(true); phase{number}_demo({matlab_string(phase / suffix)});")
            check_repeat_identity(number, phase)
            command(f"phase{number}-artifact-verification", [sys.executable,
                    f"scripts/verify_phase{number}_artifacts.py", str(phase),
                    "--expected-commit", source, "--compare-dir", str(phase / "demo-repeat")],
                    phase / "validation" / f"phase{number}-acceptance.json")
        command("dependencies-after", [sys.executable, "scripts/verify_submodules.py", "--require-checkout"])
        final_source = git("rev-parse", "HEAD")
        final_clean = source_is_clean()
        report["source_clean_at_end"] = final_clean
        if final_source != source:
            raise RuntimeError("Source revision changed during acceptance.")
        if not final_clean and not args.development:
            raise RuntimeError("Source worktree changed or has assume-unchanged/skip-worktree index flags "
                               "during release acceptance.")
        report["status"] = "development_passed" if args.development else "passed"
        report["release_accepted"] = not args.development
        report["files"] = {}
        for path in sorted(output.rglob("*")):
            if path.is_file() and path != receipt:
                data = path.read_bytes()
                report["files"][str(path.relative_to(output))] = {
                    "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    except Exception as error:
        report["status"] = "failed"
        report["release_accepted"] = False
        report["error"] = str(error)
        save()
        raise
    finally:
        report["finished_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
        save()
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, default=ROOT / "outputs/phase3-acceptance")
    parser.add_argument("--expected-commit")
    parser.add_argument("--octave", default="octave")
    parser.add_argument("--development", action="store_true")
    args = parser.parse_args()
    try:
        result = execute(args)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"status": result["status"], "release_accepted": result["release_accepted"],
                      "source_revision": result["source_revision"], "output_root": str(args.output_root.resolve())}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
