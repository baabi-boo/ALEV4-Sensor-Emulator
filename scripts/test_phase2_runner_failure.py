#!/usr/bin/env python3
"""Execute Phase 2 failure paths and prove stale successes are invalidated.

Each scenario copies the production runner into an owned temporary repository.
Scenario fixtures replace tests or one file-open operation, never production
files. Each intended failure must escape as a nonzero Octave process exit. An
initial write failure cannot invalidate old evidence, so that case explicitly
proves the old report must never substitute for the current process status.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from test_runner_failure import RunnerFailureTestError, matlab_string, read_report

ROOT = Path(__file__).resolve().parents[1]


def verify_failure_paths(octave: str, source_root: Path = ROOT) -> dict:
    results = []
    cases = (("missing_prerequisite", True, "ALEV4:MissingSubmodules"),
             ("late_assertion", False, "ALEV4:InjectedPhase2Failure"),
             ("malformed_suite_inventory", False, "ALEV4:Phase2SuiteFailed"),
             ("duplicate_test_names", False, "ALEV4:Phase2SuiteFailed"),
             ("initial_report_write_failure", False, "ALEV4:ReportWrite"))
    for name, require_phase1, expected_error in cases:
        with tempfile.TemporaryDirectory(prefix="alev4-phase2-failure-") as temporary:
            fixture = Path(temporary) / "mini repository's"
            matlab_dir = fixture / "matlab"
            tests = matlab_dir / "tests"
            package = matlab_dir / "+alev4"
            output = fixture / "output"
            for directory in (tests, package, output):
                directory.mkdir(parents=True, exist_ok=True)
            for filename in ("run_phase2_tests.m", "setup_project.m"):
                shutil.copyfile(source_root / "matlab" / filename, matlab_dir / filename)
            shutil.copyfile(source_root / "matlab/+alev4/sourceProvenance.m",
                            package / "sourceProvenance.m")
            if not require_phase1:
                count = 2 if name in ("malformed_suite_inventory", "duplicate_test_names") else 1
                inventory = "[t t]" if name == "duplicate_test_names" else "t"
                (tests / "test_phase2_core.m").write_text(
                    "function r=test_phase2_core()\n"
                    "t=struct('name','fixture','status','passed','passed',true);\n"
                    f"r=struct('status','passed','passed',true,'test_count',{count},'tests',{inventory});\n"
                    "end\n", encoding="utf-8")
                (tests / "test_phase2_config.m").write_text(
                    "function r=test_phase2_config()\n"
                    "error('ALEV4:InjectedPhase2Failure','Intentional late assertion');\n"
                    "end\n", encoding="utf-8")
            report_path = output / "phase2-validation.json"
            report_path.write_text(json.dumps({
                "schema_version": "1.0", "phase": 2, "status": "passed",
                "phase2_passed": True, "stale_success_marker": "must_disappear"
            }), encoding="utf-8")
            stale_bytes = report_path.read_bytes()
            write_failure = name == "initial_report_write_failure"
            if write_failure:
                # Inject a deterministic write refusal even when a test host
                # runs with privileges that would defeat chmod-based fixtures.
                # Only this temporary report's write-open fails; the production
                # runner and its writeReport implementation are copied unchanged.
                (matlab_dir / "fopen.m").write_text(
                    "function varargout=fopen(varargin)\n"
                    f"if nargin>=2 && isequal(varargin{{1}},{matlab_string(report_path)}) "
                    "&& isequal(varargin{2},'wb')\n"
                    "varargout{1}=-1; if nargout>1, varargout{2}='Injected write refusal'; end; return;\n"
                    "end\n"
                    "[varargout{1:nargout}]=builtin('fopen',varargin{:});\n"
                    "end\n", encoding="utf-8")
            expression = (
                "restoredefaultpath; "
                f"addpath({matlab_string(matlab_dir)}); "
                f"assert(strcmp(which('run_phase2_tests'), "
                f"{matlab_string(matlab_dir / 'run_phase2_tests.m')})); "
                "try; "
                f"run_phase2_tests({matlab_string(output)}, "
                f"{'true' if require_phase1 else 'false'}); "
                "catch err; fprintf('RUNNER_ERROR_IDENTIFIER:%s\\n',err.identifier); rethrow(err); end;"
            )
            environment = os.environ.copy()
            environment.pop("OCTAVE_PATH", None)
            try:
                completed = subprocess.run(
                    [octave, "--no-gui", "--quiet", "--no-init-file",
                     "--no-site-file", "--eval", expression],
                    cwd=fixture, env=environment, capture_output=True, text=True,
                    timeout=60, check=False)
            except (OSError, subprocess.TimeoutExpired) as error:
                raise RunnerFailureTestError(f"Cannot execute {name} scenario.") from error
            if completed.returncode == 0:
                raise RunnerFailureTestError(f"{name} incorrectly exited successfully.")
            marker = "RUNNER_ERROR_IDENTIFIER:" + expected_error
            if marker not in completed.stdout.splitlines():
                raise RunnerFailureTestError(f"{name} did not throw the intended {expected_error}.")
            if write_failure:
                if report_path.read_bytes() != stale_bytes:
                    raise RunnerFailureTestError("Initial write refusal unexpectedly changed old evidence.")
                results.append({"scenario": name, "status": "passed",
                                "observed_error": expected_error,
                                "nonzero_exit": completed.returncode,
                                "stale_report_unchanged": True,
                                "report_invalidation_possible": False,
                                "current_process_failure_required": True})
                continue
            report = read_report(report_path)
            if report.get("status") != "failed" or report.get("phase2_passed") is not False:
                raise RunnerFailureTestError(f"{name} left stale or ambiguous success.")
            if "stale_success_marker" in report:
                raise RunnerFailureTestError(f"{name} preserved the old success record.")
            observed = report.get("error", {}).get("identifier")
            if observed != expected_error:
                raise RunnerFailureTestError(
                    f"{name} failed at {observed!r}, expected {expected_error!r}.")
            if (report.get("runtime") != "GNU Octave" or
                    not isinstance(report.get("runtime_version"), str) or
                    not report["runtime_version"] or report.get("phase") != 2 or
                    report.get("schema_version") != "1.0" or
                    report.get("calibrated_alev4") is not False):
                raise RunnerFailureTestError(f"{name} lacks actual runtime/schema evidence.")
            results.append({"scenario": name, "status": "passed",
                            "observed_error": observed, "nonzero_exit": completed.returncode,
                            "stale_success_removed": True,
                            "runtime_version": report["runtime_version"]})
    return {"status": "passed", "test": "phase2_runner_failure_contract",
            "scenarios": results}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--octave", default="octave")
    arguments = parser.parse_args(argv)
    executable = shutil.which(arguments.octave)
    if executable is None:
        print("FAIL: Octave is required; missing runtime is not a pass.", file=sys.stderr)
        return 1
    try:
        result = verify_failure_paths(executable)
    except (RunnerFailureTestError, OSError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
