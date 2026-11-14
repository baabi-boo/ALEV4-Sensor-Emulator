#!/usr/bin/env python3
"""Exercise the actual Phase 3 runner's acceptance and failure boundaries.

The runner, setup, and provenance reader are copied unchanged into owned
temporary repositories. Small fixture suites let the real runner reach each
control-flow boundary; they are never installed in the production tests and
do not establish numerical, ISETCam, or Phase 2 acceptance. Missing Octave is
an error, never a skipped/passed integration test.

A full fixture-control run first produces the success record used by every
rerun. Failures after invalidation must replace it. If the initial report
write itself fails, the previous success survives on disk and the current
nonzero process status must still win. A final-write refusal and an error
after the runner returns exercise the other two report/process boundaries.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from test_runner_failure import RunnerFailureTestError, matlab_string, read_report

ROOT = Path(__file__).resolve().parents[1]
SUITES = {
    "test_phase3_geometry": "geometry",
    "test_phase3_geometry_edges": "geometry_edges",
    "test_phase3_sampling": "sampling",
    "test_phase3_optics": "optics",
    "test_phase3_integration": "integration",
    "test_phase3_artifacts": "spatial_io",
    "test_phase3_numerical_edges": "numerical_edges",
    "test_phase3_demo": "demo_contract",
    "test_phase3_iset": "iset_spatial",
}
ISET_PATH_SENTINELS = (
    "ieInitSession", "ieSessionSet", "sceneCreate", "sceneGet", "sceneSet",
    "oiCreate", "oiSet", "oiCompute", "oiGet", "pixelCreate", "pixelGet",
    "sensorCreate", "sensorSet", "sensorGet", "sensorCompute",
)
PASSED_SUITE = (
    "t=struct('name','temporary_fixture_control','status','passed','passed',true);\n"
    "r=struct('status','passed','passed',true,'test_count',1,'tests',t,'fixture_only',true);\n"
)
PASSED_PHASE2 = (
    "assert(nargin==2 && islogical(varargin{2}) && isequal(varargin{2},true));\n"
    "iset=struct('status','passed','fixture_only',true);\n"
    "phase1=struct('status','passed','phase1_passed',true,'iset',iset,'fixture_only',true);\n"
    "r=struct('status','passed','phase2_passed',true,'phase1_required',true,"
    "'phase1',phase1,'fixture_only',true);\n"
)


@dataclass(frozen=True)
class Scenario:
    name: str
    require_phase2: bool = False
    expected_error: str | None = "ALEV4:Phase3SuiteFailed"
    function: str = "test_phase3_geometry"
    mutation: str = ""
    remove: tuple[str, ...] = ()
    expected_status: str = "failed"
    write_failure_at: int = 0
    fail_after_return: bool = False


SCENARIOS = (
    Scenario("core_only_never_accepted", expected_error=None,
             remove=("test_phase3_iset", "run_phase2_tests"), expected_status="core_only"),
    Scenario("missing_prerequisite", True, "ALEV4:MissingSubmodules"),
    Scenario("missing_iset_suite", True, "Octave:undefined-function",
             remove=("test_phase3_iset",)),
    Scenario("false_iset_suite", True, function="test_phase3_iset", mutation="r.passed=false;"),
    Scenario("skipped_iset_suite", True, function="test_phase3_iset", mutation="r.status='skipped';"),
    Scenario("missing_iset_pass_flag", True, function="test_phase3_iset", mutation="r=rmfield(r,'passed');"),
    Scenario("missing_iset_inventory", True, function="test_phase3_iset", mutation="r=rmfield(r,'tests');"),
    Scenario("missing_phase2_prerequisite", True, "Octave:undefined-function",
             remove=("run_phase2_tests",)),
    Scenario("false_phase2_prerequisite", True, "ALEV4:Phase2Prerequisite",
             "run_phase2_tests", "r.phase2_passed=false;"),
    Scenario("core_only_phase2_prerequisite", True, "ALEV4:Phase2Prerequisite",
             "run_phase2_tests", "r.status='core_only'; r.phase2_passed=false;"),
    Scenario("missing_phase2_pass_flag", True, "ALEV4:Phase2Prerequisite",
             "run_phase2_tests", "r=rmfield(r,'phase2_passed');"),
    Scenario("malformed_phase2_prerequisite", True, "ALEV4:Phase2Prerequisite",
             "run_phase2_tests", "r=[];"),
    Scenario("numeric_phase2_pass_flag", True, "ALEV4:Phase2Prerequisite",
             "run_phase2_tests", "r.phase2_passed=1;"),
    Scenario("malformed_phase2_status", True, "ALEV4:Phase2Prerequisite",
             "run_phase2_tests", "r.status={'passed'};"),
    Scenario("missing_phase1_prerequisite", True, "ALEV4:Phase2Prerequisite",
             "run_phase2_tests", "r=rmfield(r,'phase1');"),
    Scenario("false_phase1_prerequisite", True, "ALEV4:Phase2Prerequisite",
             "run_phase2_tests", "r.phase1.phase1_passed=false;"),
    Scenario("missing_phase1_requirement", True, "ALEV4:Phase2Prerequisite",
             "run_phase2_tests", "r=rmfield(r,'phase1_required');"),
    Scenario("false_phase1_requirement", True, "ALEV4:Phase2Prerequisite",
             "run_phase2_tests", "r.phase1_required=false;"),
    Scenario("numeric_phase1_pass_flag", True, "ALEV4:Phase2Prerequisite",
             "run_phase2_tests", "r.phase1.phase1_passed=1;"),
    Scenario("missing_preserved_iset", True, "ALEV4:Phase2Prerequisite",
             "run_phase2_tests", "r.phase1=rmfield(r.phase1,'iset');"),
    Scenario("failed_preserved_iset", True, "ALEV4:Phase2Prerequisite",
             "run_phase2_tests", "r.phase1.iset.status='failed';"),
    Scenario("malformed_preserved_iset", True, "ALEV4:Phase2Prerequisite",
             "run_phase2_tests", "r.phase1.iset.status={'passed'};"),
    Scenario("late_assertion", expected_error="ALEV4:InjectedPhase3Failure",
             function="test_phase3_demo", mutation="error('ALEV4:InjectedPhase3Failure','Intentional late assertion');"),
    # Octave's missing feval target has an empty identifier; its process exit
    # and exact recorded identifier still have to match this specific fixture.
    Scenario("missing_required_suite", expected_error="", remove=("test_phase3_numerical_edges",)),
    Scenario("malformed_suite_inventory", mutation="r.test_count=2;"),
    Scenario("missing_suite_inventory", mutation="r=rmfield(r,'tests');"),
    Scenario("empty_suite_inventory", mutation="r.test_count=0; r.tests=struct([]);"),
    Scenario("fractional_test_count", mutation="r.test_count=1.5;"),
    Scenario("nonfinite_test_count", mutation="r.test_count=NaN;"),
    Scenario("unpassed_inventory_test", mutation="r.tests.passed=false;"),
    Scenario("skipped_inventory_test", mutation="r.tests.status='skipped';"),
    Scenario("missing_inventory_pass_flag", mutation="r.tests=rmfield(r.tests,'passed');"),
    Scenario("blank_inventory_test_name", mutation="r.tests.name='   ';"),
    Scenario("duplicate_test_names", mutation="r.test_count=2; r.tests=[t t];"),
    Scenario("false_suite_pass_flag", mutation="r.passed=false;"),
    Scenario("numeric_suite_pass_flag", mutation="r.passed=1;"),
    Scenario("numeric_inventory_pass_flag", mutation="r.tests.passed=1;"),
    Scenario("malformed_suite_status", mutation="r.status={'passed'};"),
    Scenario("malformed_inventory_status", mutation="r.tests.status={'passed'};"),
    Scenario("malformed_tests_type", mutation="r.tests=1;"),
    Scenario("initial_report_write_failure", expected_error="ALEV4:ReportWrite",
             expected_status="passed", write_failure_at=1),
    Scenario("final_report_write_failure", True, "ALEV4:ReportWrite",
             expected_status="running", write_failure_at=2),
    Scenario("process_failure_after_success", True, "ALEV4:InjectedProcessFailure",
             expected_status="passed", fail_after_return=True),
)


def write_fixture_function(matlab_dir: Path, name: str, mutation: str = "") -> None:
    directory = matlab_dir if name == "run_phase2_tests" else matlab_dir / "tests"
    body = PASSED_PHASE2 if name == "run_phase2_tests" else PASSED_SUITE
    (directory / f"{name}.m").write_text(
        f"function r={name}(varargin)\n{body}{mutation}\nend\n", encoding="utf-8")


def create_fixture(temporary: str, source_root: Path) -> tuple[Path, Path, Path]:
    fixture = Path(temporary) / "mini repository's"
    matlab_dir, output = fixture / "matlab", fixture / "output"
    for relative in ("matlab/tests", "matlab/+alev4", "matlab/examples", "output",
                     "third_party/isetcam/sensor", "third_party/isethdrsensor/scripts"):
        (fixture / relative).mkdir(parents=True, exist_ok=True)
    for relative in ("run_phase3_tests.m", "setup_project.m", "+alev4/sourceProvenance.m"):
        source = source_root / "matlab" / relative
        destination = matlab_dir / relative
        shutil.copyfile(source, destination)
        if destination.read_bytes() != source.read_bytes():
            raise RunnerFailureTestError("The isolated fixture changed production runner/setup bytes.")
    for name in (*SUITES, "run_phase2_tests"):
        write_fixture_function(matlab_dir, name)
    # The unchanged setup validates these exact temporary paths. None of these
    # sentinels can perform or masquerade as an ISET computation: any execution
    # raises. Only the temporary test_phase3_iset fixture supplies gate results.
    for name in ISET_PATH_SENTINELS:
        (fixture / "third_party/isetcam/sensor" / f"{name}.m").write_text(
            f"function varargout={name}(varargin)\n"
            "error('ALEV4:FixtureISETExecution','Path sentinel must never execute');\nend\n",
            encoding="utf-8")
    return fixture, matlab_dir, output


def run_fixture(octave: str, fixture: Path, matlab_dir: Path, output: Path,
                require_phase2: bool, fail_after_return: bool = False) -> subprocess.CompletedProcess:
    expression = "restoredefaultpath; " + f"addpath({matlab_string(matlab_dir)}); "
    for name in ("run_phase3_tests", "setup_project"):
        expression += (f"assert(strcmp(which('{name}'), "
                       f"{matlab_string(matlab_dir / (name + '.m'))})); ")
    expression += (
        "try; "
        f"run_phase3_tests({matlab_string(output)},{'true' if require_phase2 else 'false'}); "
    )
    if fail_after_return:
        expression += "error('ALEV4:InjectedProcessFailure','Failure after runner returned'); "
    expression += "catch err; fprintf('RUNNER_ERROR_IDENTIFIER:%s\\n',err.identifier); rethrow(err); end;"
    environment = os.environ.copy()
    environment.pop("OCTAVE_PATH", None)
    try:
        return subprocess.run(
            [octave, "--no-gui", "--quiet", "--no-init-file", "--no-site-file", "--eval", expression],
            cwd=fixture, env=environment, capture_output=True, text=True, timeout=60, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RunnerFailureTestError("Cannot execute the isolated Octave runner scenario.") from error


def check_report_identity(report: dict, name: str) -> None:
    if (report.get("runtime") != "GNU Octave" or
            not isinstance(report.get("runtime_version"), str) or not report["runtime_version"] or
            report.get("phase") != 3 or report.get("schema_version") != "1.0" or
            report.get("calibrated_alev4") is not False):
        raise RunnerFailureTestError(f"{name} lacks actual runtime/schema evidence.")


def check_full_control(report: dict) -> None:
    check_report_identity(report, "full fixture control")
    if (report.get("status") != "passed" or report.get("phase3_passed") is not True or
            report.get("phase2_required") is not True or
            report.get("phase2", {}).get("phase2_passed") is not True or
            report.get("phase2", {}).get("fixture_only") is not True):
        raise RunnerFailureTestError("The full fixture control failed before negative scenarios.")
    for field in SUITES.values():
        suite = report.get(field, {})
        if suite.get("status") != "passed" or suite.get("passed") is not True or suite.get("fixture_only") is not True:
            raise RunnerFailureTestError(f"The full fixture control did not execute {field}.")


def inject_report_write_refusal(matlab_dir: Path, report_path: Path, call_number: int) -> None:
    # Target exactly one production report open. Metadata reads and all other
    # fopen calls still use the native operation. This also works as root.
    (matlab_dir / "fopen.m").write_text(
        "function varargout=fopen(varargin)\npersistent opens=0;\n"
        f"if nargin>=2 && isequal(varargin{{1}},{matlab_string(report_path)}) && isequal(varargin{{2}},'wb')\n"
        f"opens=opens+1; if opens=={call_number}\n"
        "varargout{1}=-1; if nargout>1, varargout{2}='Injected write refusal'; end; return;\nend\nend\n"
        "[varargout{1:nargout}]=builtin('fopen',varargin{:});\nend\n", encoding="utf-8")


def verify_failure_paths(octave: str, source_root: Path = ROOT) -> dict:
    with tempfile.TemporaryDirectory(prefix="alev4-phase3-control-") as temporary:
        fixture, matlab_dir, output = create_fixture(temporary, source_root)
        completed = run_fixture(octave, fixture, matlab_dir, output, True)
        if completed.returncode:
            raise RunnerFailureTestError(f"Full fixture control failed: {completed.stderr[-2000:]}")
        prior_success = read_report(output / "phase3-validation.json")
        check_full_control(prior_success)
    prior_success["stale_success_marker"] = "must_disappear"
    results = []
    for scenario in SCENARIOS:
        with tempfile.TemporaryDirectory(prefix="alev4-phase3-failure-") as temporary:
            fixture, matlab_dir, output = create_fixture(temporary, source_root)
            if scenario.name in ("core_only_never_accepted", "missing_prerequisite"):
                shutil.rmtree(fixture / "third_party")
            for name in scenario.remove:
                directory = matlab_dir if name == "run_phase2_tests" else matlab_dir / "tests"
                (directory / f"{name}.m").unlink()
            if scenario.mutation:
                write_fixture_function(matlab_dir, scenario.function, scenario.mutation)
            report_path = output / "phase3-validation.json"
            report_path.write_text(json.dumps(prior_success), encoding="utf-8")
            stale_bytes = report_path.read_bytes()
            if scenario.write_failure_at:
                inject_report_write_refusal(matlab_dir, report_path, scenario.write_failure_at)
            completed = run_fixture(octave, fixture, matlab_dir, output,
                                    scenario.require_phase2, scenario.fail_after_return)
            if scenario.expected_error is None:
                if completed.returncode:
                    raise RunnerFailureTestError(f"{scenario.name} failed: {completed.stderr[-2000:]}")
            else:
                if completed.returncode == 0:
                    raise RunnerFailureTestError(f"{scenario.name} incorrectly exited successfully.")
                marker = "RUNNER_ERROR_IDENTIFIER:" + scenario.expected_error
                if marker not in completed.stdout.splitlines():
                    raise RunnerFailureTestError(
                        f"{scenario.name} did not throw {scenario.expected_error!r}; "
                        f"stdout={completed.stdout[-1000:]!r}; stderr={completed.stderr[-1000:]!r}")
            report = read_report(report_path)
            check_report_identity(report, scenario.name)
            if report.get("status") != scenario.expected_status:
                raise RunnerFailureTestError(f"{scenario.name} left unexpected report status {report.get('status')!r}.")
            if scenario.write_failure_at == 1:
                if report_path.read_bytes() != stale_bytes:
                    raise RunnerFailureTestError("Initial write refusal changed the prior full success record.")
            elif "stale_success_marker" in report:
                raise RunnerFailureTestError(f"{scenario.name} preserved the old full success record.")
            if scenario.expected_status == "passed":
                check_full_control(report)
            elif report.get("phase3_passed") is not False:
                raise RunnerFailureTestError(f"{scenario.name} incorrectly permits full acceptance.")
            if scenario.expected_status == "failed" and report.get("error", {}).get("identifier") != scenario.expected_error:
                raise RunnerFailureTestError(f"{scenario.name} failed without recording its actual error.")
            if scenario.expected_status == "core_only":
                phase2 = report.get("phase2", {})
                if (report.get("phase2_required") is not False or phase2.get("status") != "not_run" or
                        phase2.get("phase2_passed") is not False or "iset_spatial" in report):
                    raise RunnerFailureTestError("Core-only execution incorrectly reports prerequisite completion.")
                if any(report.get(field, {}).get("passed") is not True
                       for field in SUITES.values() if field != "iset_spatial"):
                    raise RunnerFailureTestError("The core-only control did not finish all standalone suites.")
            results.append({
                "scenario": scenario.name, "status": "passed", "observed_error": scenario.expected_error,
                "process_exit": completed.returncode, "observed_report_status": report["status"],
                "observed_phase3_passed": report["phase3_passed"],
                "stale_success_removed": "stale_success_marker" not in report,
                "report_invalidation_possible": scenario.write_failure_at != 1,
                "current_process_failure_required": scenario.expected_error is not None,
                "runtime_version": report["runtime_version"],
            })
    return {"status": "passed", "test": "phase3_runner_failure_contract", "fixture_suites_only": True,
            "numerical_acceptance_executed": False, "scenario_count": len(results),
            "nonzero_process_scenarios": sum(result["process_exit"] != 0 for result in results),
            "control_runtime": "GNU Octave", "control_runtime_version": prior_success["runtime_version"],
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
