#!/usr/bin/env python3
"""Exercise the unchanged Phase 4 runner in isolated actual-Octave fixtures.

Only temporary suite/prerequisite reports and selected file-open operations
are controlled. The production runner, setup and provenance helper are copied
byte-for-byte; production tests and earlier phase runners are never replaced.
These controls establish failure reporting only, never scientific execution,
ISETCam execution or numerical acceptance. Missing Octave is an error.

Every scenario starts with a success produced by the full fixture control.
Successful invalidation must remove that stale success. When initial storage
fails, or the process fails after returning a passed report, the current
nonzero exit status must take precedence over the JSON success on disk.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
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
    "test_phase4_config": "config",
    "test_phase4_core": "core",
    "test_phase4_noise": "noise",
    "test_phase4_rng": "rng",
    "test_phase4_sequence": "sequence",
    "test_phase4_spatial": "spatial",
    "test_phase4_artifacts": "artifact_io",
    "test_phase4_demo": "demo_contract",
    "test_phase4_numerical_edges": "numerical_edges",
}
ISET_PATH_SENTINELS = (
    "ieInitSession", "ieSessionSet", "sceneCreate", "sceneGet", "sceneSet",
    "oiCreate", "oiSet", "oiCompute", "oiGet", "pixelCreate", "pixelGet",
    "sensorCreate", "sensorSet", "sensorGet", "sensorCompute",
)
COPIED_SOURCES = ("run_phase4_tests.m", "setup_project.m", "+alev4/sourceProvenance.m")
PASSED_SUITE = (
    "t=struct('name','temporary_fixture_control','status','passed','passed',true);\n"
    "r=struct('status','passed','passed',true,'test_count',1,'tests',t,'fixture_only',true);\n"
)
PASSED_PHASE3 = (
    "assert(nargin==2 && islogical(varargin{2}) && isequal(varargin{2},true));\n"
    + PASSED_SUITE
    + "iset_spatial=r;\n"
    "iset=struct('status','passed','test_count',1,'fixture_only',true);\n"
    "phase1=struct('status','passed','phase1_passed',true,'iset',iset,'fixture_only',true);\n"
    "phase2=struct('status','passed','phase2_passed',true,'phase1_required',true,"
    "'phase1',phase1,'fixture_only',true);\n"
    "r=struct('status','passed','phase3_passed',true,'phase2_required',true,"
    "'phase2',phase2,'iset_spatial',iset_spatial,'fixture_only',true);\n"
)


@dataclass(frozen=True)
class Scenario:
    name: str
    require_phase3: bool = False
    expected_error: str | None = "ALEV4:Phase4SuiteFailed"
    function: str = "test_phase4_config"
    mutation: str = ""
    remove_paths: tuple[str, ...] = ()
    expected_status: str = "failed"
    write_failure_at: int = 0
    fail_after_return: bool = False


# Each required suite gets its own missing/skipped/malformed/group/count
# controls. This detects an accidentally omitted invocation at any position,
# including the last suite; checking one representative suite is insufficient.
SUITE_MUTATIONS = {
    "skipped": "r.status='skipped';",
    "malformed": "r=[];",
    "false_suite_flag": "r.passed=false;",
    "false_group_flag": "r.tests.passed=false;",
    "skipped_group": "r.tests.status='skipped';",
    "test_count_mismatch": "r.test_count=2;",
    "missing_inventory": "r=rmfield(r,'tests');",
}
SUITE_SCENARIOS = tuple(
    scenario
    for function, field in SUITES.items()
    for scenario in (
        # Octave gives an absent feval target an empty error identifier.
        Scenario(f"{field}_missing", expected_error="",
                 remove_paths=(f"matlab/tests/{function}.m",)),
        *(Scenario(f"{field}_{kind}", function=function, mutation=mutation)
          for kind, mutation in SUITE_MUTATIONS.items()),
    )
)

INVENTORY_MUTATIONS = {
    "nonscalar_suite": "r=[r r];",
    "missing_suite_status": "r=rmfield(r,'status');",
    "malformed_suite_status": "r.status={'passed'};",
    "missing_suite_pass_flag": "r=rmfield(r,'passed');",
    "numeric_suite_pass_flag": "r.passed=1;",
    "nonscalar_suite_pass_flag": "r.passed=[true true];",
    "missing_test_count": "r=rmfield(r,'test_count');",
    "fractional_test_count": "r.test_count=1.5;",
    "nonfinite_test_count": "r.test_count=NaN;",
    "complex_test_count": "r.test_count=1+1i;",
    "logical_test_count": "r.test_count=true;",
    "nonscalar_test_count": "r.test_count=[1 1];",
    "empty_inventory": "r.test_count=0; r.tests=struct([]);",
    "malformed_inventory": "r.tests=1;",
    "missing_group_name": "r.tests=rmfield(r.tests,'name');",
    "blank_group_name": "r.tests.name='   ';",
    "malformed_group_name": "r.tests.name={'fixture'};",
    "matrix_group_name": "r.tests.name=['ab';'cd'];",
    "duplicate_group_names": "r.test_count=2; r.tests=[t t];",
    "missing_group_status": "r.tests=rmfield(r.tests,'status');",
    "malformed_group_status": "r.tests.status={'passed'};",
    "missing_group_pass_flag": "r.tests=rmfield(r.tests,'passed');",
    "numeric_group_pass_flag": "r.tests.passed=1;",
    "nonscalar_group_pass_flag": "r.tests.passed=[true true];",
}

PREREQUISITE_MUTATIONS = {
    "phase3_empty": "r=[];",
    "phase3_nonscalar": "r=[r r];",
    "phase3_missing_status": "r=rmfield(r,'status');",
    "phase3_malformed_status": "r.status={'passed'};",
    "phase3_core_only": "r.status='core_only'; r.phase3_passed=false;",
    "phase3_false_flag": "r.phase3_passed=false;",
    "phase3_missing_flag": "r=rmfield(r,'phase3_passed');",
    "phase3_numeric_flag": "r.phase3_passed=1;",
    "phase2_missing_requirement": "r=rmfield(r,'phase2_required');",
    "phase2_false_requirement": "r.phase2_required=false;",
    "phase2_numeric_requirement": "r.phase2_required=1;",
    "phase2_missing": "r=rmfield(r,'phase2');",
    "phase2_empty": "r.phase2=[];",
    "phase2_nonscalar": "r.phase2=[r.phase2 r.phase2];",
    "phase2_missing_status": "r.phase2=rmfield(r.phase2,'status');",
    "phase2_malformed_status": "r.phase2.status={'passed'};",
    "phase2_core_only": "r.phase2.status='core_only'; r.phase2.phase2_passed=false;",
    "phase2_false_flag": "r.phase2.phase2_passed=false;",
    "phase2_missing_flag": "r.phase2=rmfield(r.phase2,'phase2_passed');",
    "phase2_numeric_flag": "r.phase2.phase2_passed=1;",
    "phase1_missing_requirement": "r.phase2=rmfield(r.phase2,'phase1_required');",
    "phase1_false_requirement": "r.phase2.phase1_required=false;",
    "phase1_numeric_requirement": "r.phase2.phase1_required=1;",
    "phase1_missing": "r.phase2=rmfield(r.phase2,'phase1');",
    "phase1_empty": "r.phase2.phase1=[];",
    "phase1_nonscalar": "r.phase2.phase1=[r.phase2.phase1 r.phase2.phase1];",
    "phase1_missing_status": "r.phase2.phase1=rmfield(r.phase2.phase1,'status');",
    "phase1_malformed_status": "r.phase2.phase1.status={'passed'};",
    "phase1_core_only": "r.phase2.phase1.status='core_only'; r.phase2.phase1.phase1_passed=false;",
    "phase1_false_flag": "r.phase2.phase1.phase1_passed=false;",
    "phase1_missing_flag": "r.phase2.phase1=rmfield(r.phase2.phase1,'phase1_passed');",
    "phase1_numeric_flag": "r.phase2.phase1.phase1_passed=1;",
    "iset_spatial_missing": "r=rmfield(r,'iset_spatial');",
    "iset_spatial_empty": "r.iset_spatial=[];",
    "iset_spatial_nonscalar": "r.iset_spatial=[r.iset_spatial r.iset_spatial];",
    "iset_spatial_missing_status": "r.iset_spatial=rmfield(r.iset_spatial,'status');",
    "iset_spatial_malformed_status": "r.iset_spatial.status={'passed'};",
    "iset_spatial_skipped": "r.iset_spatial.status='skipped';",
    "iset_spatial_false_flag": "r.iset_spatial.passed=false;",
    "iset_spatial_missing_flag": "r.iset_spatial=rmfield(r.iset_spatial,'passed');",
    "iset_spatial_numeric_flag": "r.iset_spatial.passed=1;",
    "iset_spatial_false_group": "r.iset_spatial.tests.passed=false;",
    "iset_spatial_skipped_group": "r.iset_spatial.tests.status='skipped';",
    "iset_spatial_missing_inventory": "r.iset_spatial=rmfield(r.iset_spatial,'tests');",
    "iset_spatial_count_mismatch": "r.iset_spatial.test_count=2;",
    "iset_missing": "r.phase2.phase1=rmfield(r.phase2.phase1,'iset');",
    "iset_empty": "r.phase2.phase1.iset=[];",
    "iset_nonscalar": "r.phase2.phase1.iset=[r.phase2.phase1.iset r.phase2.phase1.iset];",
    "iset_missing_status": "r.phase2.phase1.iset=rmfield(r.phase2.phase1.iset,'status');",
    "iset_malformed_status": "r.phase2.phase1.iset.status={'passed'};",
    "iset_skipped": "r.phase2.phase1.iset.status='skipped';",
    "iset_failed": "r.phase2.phase1.iset.status='failed';",
    "iset_missing_count": "r.phase2.phase1.iset=rmfield(r.phase2.phase1.iset,'test_count');",
    "iset_zero_count": "r.phase2.phase1.iset.test_count=0;",
    "iset_fractional_count": "r.phase2.phase1.iset.test_count=1.5;",
    "iset_numeric_flag_as_count": "r.phase2.phase1.iset.test_count=true;",
}

SCENARIOS = (
    Scenario("core_only_never_accepted", expected_error=None,
             remove_paths=("third_party", "matlab/run_phase3_tests.m"),
             expected_status="core_only"),
    Scenario("missing_submodules", True, "ALEV4:MissingSubmodules", remove_paths=("third_party",)),
    Scenario("missing_setup", True, "Octave:undefined-function", remove_paths=("matlab/setup_project.m",)),
    Scenario("missing_iset_entrypoint", True, "ALEV4:ISETCamNotOnPath",
             remove_paths=("third_party/isetcam/sensor/ieInitSession.m",)),
    Scenario("missing_iset_required_api", True, "ALEV4:ISETPathConflict",
             remove_paths=("third_party/isetcam/sensor/sensorCompute.m",)),
    Scenario("missing_phase3_runner", True, "Octave:undefined-function",
             remove_paths=("matlab/run_phase3_tests.m",)),
    *SUITE_SCENARIOS,
    *(Scenario(name, mutation=mutation) for name, mutation in INVENTORY_MUTATIONS.items()),
    *(Scenario(name, True, "ALEV4:Phase3Prerequisite", "run_phase3_tests", mutation)
      for name, mutation in PREREQUISITE_MUTATIONS.items()),
    Scenario("late_assertion", expected_error="ALEV4:InjectedPhase4Failure",
             function="test_phase4_numerical_edges",
             mutation="error('ALEV4:InjectedPhase4Failure','Intentional last-suite assertion');"),
    Scenario("initial_report_write_failure", expected_error="ALEV4:ReportWrite",
             expected_status="passed", write_failure_at=1),
    Scenario("final_report_write_failure", True, "ALEV4:ReportWrite",
             expected_status="running", write_failure_at=2),
    Scenario("failure_report_write_failure", expected_error="ALEV4:ReportWrite",
             mutation="error('ALEV4:InjectedPhase4Failure','Failure before report refusal');",
             expected_status="running", write_failure_at=2),
    Scenario("process_failure_after_success", True, "ALEV4:InjectedProcessFailure",
             expected_status="passed", fail_after_return=True),
)


def write_fixture_function(matlab_dir: Path, name: str, mutation: str = "") -> None:
    directory = matlab_dir if name == "run_phase3_tests" else matlab_dir / "tests"
    body = PASSED_PHASE3 if name == "run_phase3_tests" else PASSED_SUITE
    (directory / f"{name}.m").write_text(
        f"function r={name}(varargin)\n{body}{mutation}\nend\n", encoding="utf-8")


def create_fixture(temporary: str, source_root: Path) -> tuple[Path, Path, Path]:
    fixture = Path(temporary) / "mini repository's"
    matlab_dir, output = fixture / "matlab", fixture / "output"
    for relative in ("matlab/tests", "matlab/+alev4", "matlab/examples", "output",
                     "third_party/isetcam/sensor", "third_party/isethdrsensor/scripts"):
        (fixture / relative).mkdir(parents=True, exist_ok=True)
    for relative in COPIED_SOURCES:
        source, destination = source_root / "matlab" / relative, matlab_dir / relative
        shutil.copyfile(source, destination)
        if destination.read_bytes() != source.read_bytes():
            raise RunnerFailureTestError("The fixture changed production runner/setup/provenance bytes.")
    for name in (*SUITES, "run_phase3_tests"):
        write_fixture_function(matlab_dir, name)
    # Unchanged production setup checks these temporary paths. These files
    # cannot compute an ISET baseline: executing any sentinel always fails.
    for name in ISET_PATH_SENTINELS:
        (fixture / "third_party/isetcam/sensor" / f"{name}.m").write_text(
            f"function varargout={name}(varargin)\n"
            "error('ALEV4:FixtureISETExecution','Path sentinel must never execute');\nend\n",
            encoding="utf-8")
    return fixture, matlab_dir, output


def run_fixture(octave: str, fixture: Path, matlab_dir: Path, output: Path,
                require_phase3: bool, fail_after_return: bool = False) -> subprocess.CompletedProcess:
    expression = "restoredefaultpath; " + f"addpath({matlab_string(matlab_dir)}); "
    for name in ("run_phase4_tests", "setup_project"):
        path = matlab_dir / f"{name}.m"
        if path.is_file():
            expression += f"assert(strcmp(which('{name}'), {matlab_string(path)})); "
    expression += (
        "try; "
        f"run_phase4_tests({matlab_string(output)},{'true' if require_phase3 else 'false'}); "
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
            report.get("phase") != 4 or report.get("schema_version") != "1.0" or
            report.get("calibrated_alev4") is not False):
        raise RunnerFailureTestError(f"{name} lacks actual runtime/schema evidence.")


def check_full_control(report: dict) -> None:
    check_report_identity(report, "full fixture control")
    if (report.get("status") != "passed" or report.get("phase4_passed") is not True or
            report.get("phase3_required") is not True):
        raise RunnerFailureTestError("The full fixture control did not report its required gates.")
    phase3 = report.get("phase3", {})
    phase2, phase1 = phase3.get("phase2", {}), phase3.get("phase2", {}).get("phase1", {})
    for number, prerequisite in ((3, phase3), (2, phase2), (1, phase1)):
        if (prerequisite.get("status") != "passed" or
                prerequisite.get(f"phase{number}_passed") is not True or
                prerequisite.get("fixture_only") is not True):
            raise RunnerFailureTestError(f"The fixture control omitted preserved Phase {number}.")
    if (phase3.get("phase2_required") is not True or phase2.get("phase1_required") is not True or
            phase3.get("iset_spatial", {}).get("fixture_only") is not True or
            phase1.get("iset", {}).get("fixture_only") is not True):
        raise RunnerFailureTestError("The fixture control omitted a required ISET/prerequisite marker.")
    for field in SUITES.values():
        suite = report.get(field, {})
        if (suite.get("status") != "passed" or suite.get("passed") is not True or
                suite.get("test_count") != 1 or suite.get("fixture_only") is not True):
            raise RunnerFailureTestError(f"The full fixture control did not execute {field}.")


def inject_report_write_refusal(matlab_dir: Path, report_path: Path, call_number: int) -> None:
    # Refuse exactly one production report open, including when run as root.
    # All other fopen operations, including metadata reads, remain native.
    (matlab_dir / "fopen.m").write_text(
        "function varargout=fopen(varargin)\npersistent opens=0;\n"
        f"if nargin>=2 && isequal(varargin{{1}},{matlab_string(report_path)}) && isequal(varargin{{2}},'wb')\n"
        f"opens=opens+1; if opens=={call_number}\n"
        "varargout{1}=-1; if nargout>1, varargout{2}='Injected write refusal'; end; return;\nend\nend\n"
        "[varargout{1:nargout}]=builtin('fopen',varargin{:});\nend\n", encoding="utf-8")


def verify_failure_paths(octave: str, source_root: Path = ROOT) -> dict:
    source_hashes = {name: hashlib.sha256((source_root / "matlab" / name).read_bytes()).hexdigest()
                     for name in COPIED_SOURCES}
    with tempfile.TemporaryDirectory(prefix="alev4-phase4-control-") as temporary:
        fixture, matlab_dir, output = create_fixture(temporary, source_root)
        completed = run_fixture(octave, fixture, matlab_dir, output, True)
        if completed.returncode:
            raise RunnerFailureTestError(f"Full fixture control failed: {completed.stderr[-2000:]}")
        prior_success = read_report(output / "phase4-validation.json")
        check_full_control(prior_success)
    prior_success["stale_success_marker"] = "must_disappear"
    results = []
    for scenario in SCENARIOS:
        with tempfile.TemporaryDirectory(prefix="alev4-phase4-failure-") as temporary:
            fixture, matlab_dir, output = create_fixture(temporary, source_root)
            for relative in scenario.remove_paths:
                path = fixture / relative
                if path.is_dir():
                    shutil.rmtree(path)
                else:
                    path.unlink()
            if scenario.mutation:
                write_fixture_function(matlab_dir, scenario.function, scenario.mutation)
            report_path = output / "phase4-validation.json"
            report_path.write_text(json.dumps(prior_success), encoding="utf-8")
            stale_bytes = report_path.read_bytes()
            if scenario.write_failure_at:
                inject_report_write_refusal(matlab_dir, report_path, scenario.write_failure_at)
            completed = run_fixture(octave, fixture, matlab_dir, output,
                                    scenario.require_phase3, scenario.fail_after_return)
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
            elif report.get("phase4_passed") is not False:
                raise RunnerFailureTestError(f"{scenario.name} incorrectly permits full acceptance.")
            if scenario.expected_status == "failed" and report.get("error", {}).get("identifier") != scenario.expected_error:
                raise RunnerFailureTestError(f"{scenario.name} failed without recording its actual error.")
            if scenario.expected_status == "core_only":
                phase3 = report.get("phase3", {})
                if (report.get("phase3_required") is not False or phase3.get("status") != "not_run" or
                        phase3.get("phase3_passed") is not False):
                    raise RunnerFailureTestError("Core-only execution incorrectly reports prerequisite completion.")
                if any(report.get(field, {}).get("passed") is not True for field in SUITES.values()):
                    raise RunnerFailureTestError("The core-only control did not finish all nine standalone suites.")
            results.append({
                "scenario": scenario.name, "status": "passed", "observed_error": scenario.expected_error,
                "process_exit": completed.returncode, "observed_report_status": report["status"],
                "observed_phase4_passed": report["phase4_passed"],
                "stale_success_removed": "stale_success_marker" not in report,
                "report_invalidation_possible": scenario.write_failure_at != 1,
                "current_process_failure_required": scenario.expected_error is not None,
                "runtime_version": report["runtime_version"],
            })
    for name, expected in source_hashes.items():
        if hashlib.sha256((source_root / "matlab" / name).read_bytes()).hexdigest() != expected:
            raise RunnerFailureTestError("Production source changed during the fixture controls.")
    return {"status": "passed", "test": "phase4_runner_failure_contract", "fixture_suites_only": True,
            "numerical_acceptance_executed": False, "iset_computation_executed": False,
            "positive_fixture_control_count": 1, "scenario_count": len(results),
            "nonzero_process_scenarios": sum(result["process_exit"] != 0 for result in results),
            "required_phase4_suites": list(SUITES.values()), "unchanged_copied_source_sha256": source_hashes,
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
