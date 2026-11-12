#!/usr/bin/env python3
"""Exercise the actual Octave runner's failure-reporting path.

The test copies the production runner/setup into an isolated miniature
repository with no submodules. An existing success report must be replaced by
a failure report, and the Octave process must exit unsuccessfully. Missing
Octave is an error, never a skipped/passed integration test.

Run after installing Octave:
    python3 scripts/test_runner_failure.py
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORT_LIMIT = 1_000_000


class RunnerFailureTestError(RuntimeError):
    """The runner did not invalidate stale evidence as required."""


def matlab_string(value: Path | str) -> str:
    """Quote one MATLAB/Octave character literal, not a shell command."""
    text = str(value)
    if any(character in text for character in ("\0", "\n", "\r")):
        raise RunnerFailureTestError("The test path contains unsupported control characters.")
    return "'" + text.replace("'", "''") + "'"


def read_report(path: Path) -> dict:
    try:
        with path.open("rb") as source:
            encoded = source.read(REPORT_LIMIT + 1)
        if len(encoded) > REPORT_LIMIT:
            raise RunnerFailureTestError("The failure report exceeds the test size limit.")
        report = json.loads(encoded.decode("utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise RunnerFailureTestError("The runner did not leave a readable JSON failure report.") from error
    if not isinstance(report, dict):
        raise RunnerFailureTestError("The runner's failure report is not a JSON object.")
    return report


def verify_failure_path(octave: str, source_root: Path = ROOT) -> dict:
    """Run the real failure path in owned temporary files, without a shell."""
    sources = [source_root / "matlab" / name for name in ("run_phase1_tests.m", "setup_project.m")]
    if not all(source.is_file() for source in sources):
        raise RunnerFailureTestError("The production MATLAB runner/setup files are missing.")

    # TemporaryDirectory owns the only cleanup target. No caller-supplied or
    # repository directory is removed. Spaces/apostrophes also exercise the
    # Octave-literal quoting used by the subprocess invocation.
    with tempfile.TemporaryDirectory(prefix="alev4-runner-failure-") as temporary:
        fixture = Path(temporary) / "mini repository's"
        matlab_dir = fixture / "matlab"
        output_dir = fixture / "output"
        matlab_dir.mkdir(parents=True)
        output_dir.mkdir()
        for source in sources:
            shutil.copyfile(source, matlab_dir / source.name)

        report_path = output_dir / "phase1-validation.json"
        stale_report = {
            "schema_version": "1.0",
            "phase": 1,
            "status": "passed",
            "phase1_passed": True,
            "calibrated_alev4": False,
            "stale_success_marker": "must_disappear",
        }
        report_path.write_text(json.dumps(stale_report), encoding="utf-8")

        expression = (
            "restoredefaultpath; "
            f"addpath({matlab_string(matlab_dir)}); "
            f"assert(strcmp(which('run_phase1_tests'), {matlab_string(matlab_dir / 'run_phase1_tests.m')})); "
            f"assert(strcmp(which('setup_project'), {matlab_string(matlab_dir / 'setup_project.m')})); "
            f"run_phase1_tests({matlab_string(output_dir)}, true);"
        )
        environment = os.environ.copy()
        # Preserve ordinary runtime/proxy variables but do not inherit a
        # project search path that could supply the missing fixture code.
        environment.pop("OCTAVE_PATH", None)
        command = [
            octave,
            "--no-gui",
            "--quiet",
            "--no-init-file",
            "--no-site-file",
            "--eval",
            expression,
        ]
        try:
            completed = subprocess.run(
                command,
                cwd=fixture,
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
                timeout=60,
            )
        except subprocess.TimeoutExpired as error:
            raise RunnerFailureTestError("The missing-submodule failure test timed out after 60 seconds.") from error
        except OSError as error:
            raise RunnerFailureTestError("Cannot execute the configured Octave runtime.") from error

        if completed.returncode == 0:
            raise RunnerFailureTestError("The runner incorrectly exited successfully with missing submodules.")
        report = read_report(report_path)
        if report.get("status") != "failed" or report.get("phase1_passed") is not False:
            raise RunnerFailureTestError("The failed rerun left a stale or ambiguous success report.")
        if "stale_success_marker" in report:
            raise RunnerFailureTestError("The stale report's fields survived the new invocation.")
        error_record = report.get("error")
        if not isinstance(error_record, dict) or error_record.get("identifier") != "ALEV4:MissingSubmodules":
            raise RunnerFailureTestError("The runner failed for a reason other than the intended missing-submodule gate.")
        if report.get("runtime") != "GNU Octave" or not isinstance(report.get("runtime_version"), str) or not report["runtime_version"]:
            raise RunnerFailureTestError("The new failure report lacks the actual Octave runtime identity.")
        if report.get("schema_version") != "1.0" or report.get("phase") != 1 or report.get("calibrated_alev4") is not False:
            raise RunnerFailureTestError("The failure report lost its schema, phase, or calibration boundary.")

        return {
            "status": "passed",
            "test": "failed_rerun_invalidates_stale_success",
            "runtime": report["runtime"],
            "runtime_version": report["runtime_version"],
            "observed_error": error_record["identifier"],
            "nonzero_exit": completed.returncode,
            "stale_success_removed": True,
        }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--octave", default="octave", help="Octave executable name or path.")
    arguments = parser.parse_args(argv)
    executable = shutil.which(arguments.octave)
    if executable is None:
        print("FAIL: Octave is required for the runner failure integration test; it was not found.", file=sys.stderr)
        return 1
    try:
        result = verify_failure_path(executable)
    except RunnerFailureTestError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
