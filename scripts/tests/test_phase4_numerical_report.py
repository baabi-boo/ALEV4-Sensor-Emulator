"""Python-only controls for complete Phase 4 numerical-report inventories.

The positive report is SYNTHETIC COMPOSED TEST DATA, never execution proof.
Its Phase 4 pass flags are handwritten; its unchanged Phase 1--3 prerequisite
is the versioned historical phase4-entry/phase3-validation.json. Neither that
composition nor a verifier pass establishes a Phase 4 run or release. No
Octave, MATLAB source, ignored output, or numerical-runtime installation is
needed. The CLI controls run copied Python verifiers with an empty PATH.
"""
from copy import deepcopy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/verify_phase4_artifacts.py"
SPEC = importlib.util.spec_from_file_location("phase4_report_verifier", SCRIPT)
verifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verifier)
HISTORICAL = json.loads(
    (ROOT / "docs/evidence/phase4-entry/phase3-validation.json").read_text(encoding="utf-8"))

# Handwritten positive fixture, independent of the verifier's constants. Keep
# every name here: using the production inventory to construct the fixture
# would let a deleted verifier requirement silently weaken these controls.
GROUPS = {
    "config": ("phase4_config", """
        defaults_partial_revalidation
        strict_schema_fields_and_structure
        strict_grid_and_full_grid_match
        nonnegative_maps_and_signed_offsets
        rms_and_temperature_ranges
        realization_and_source_identifiers
        numeric_representation_canonicalization
        all_bayer_roi_parity_map_identity
        constructor_map_rng_and_caller_isolation
    """.split()),
    "core": ("phase4_core", """
        independent_scalar_stage_oracle
        single_gain_transfer_and_signed_quantization
        dark_only_saturation_and_shared_well
        zero_exposure_fill_and_prnu
        fixed_offsets_after_well_and_gain_black_once
        fixed_map_crop_exposure_identity
        disabled_whole_result_identity
        distinct_adc_physical_and_reconstruction_masks
        raw_only_merge_transition_oracle
        arithmetic_failures_and_rng_restoration
        deterministic_wrong_model_controls
    """.split()),
    "noise": ("phase4_noise", """
        photo_dark_poisson_moments_and_independence
        independent_photo_dark_shot_policies
        shared_total_charge_covariance_and_path_variance_sums
        independent_pixel_noise_and_shot_cancellation
        independent_charge_and_reused_pixel_stream_controls
        row_covariance_counts_independent_rows
        column_covariance_counts_independent_columns
        wrong_spatial_axes_and_reused_path_stream_controls
        frame_shared_path_covariance_counts_independent_frames
        independent_frame_differences_and_disjoint_temporal_pairs
        mixed_components_sum_after_one_physical_charge
    """.split()),
    "rng": ("phase4_rng", """
        named_component_seed_schedule_and_wrap_boundaries
        accepted_and_rejected_seed_representations
        each_named_component_matches_independent_seeded_oracle
        added_component_toggles_isolate_all_other_draws
        photo_dark_switches_and_zero_support_isolate_streams
        fixed_maps_and_inactive_paths_are_rng_free
        public_success_paths_restore_rng_and_caller_values
        early_failures_restore_rng_and_caller_values
        post_draw_and_later_frame_failures_restore_rng
        same_runtime_whole_result_repeatability
    """.split()),
    "sequence": ("phase4_sequence", """
        exact_reset_start_absolute_and_gapped_continuation
        frame_seed_wrap_maximum_index_and_17_component_disjointness
        independent_frame_draws_and_fixed_map_persistence
        fixed_pattern_cancellation_from_signed_frame_differences
        ei_labels_leave_every_frame_unchanged
        exposure_vector_scales_photo_dark_not_fixed_offsets
        accepted_numeric_representations_are_canonical
        strict_sequence_options_and_absolute_index_rejection
        strict_exposure_and_ei_label_rejection
        caller_configuration_and_rng_survive_success_and_second_frame_failure
        retained_sequence_resource_bounds
        disabled_single_dual_frames_match_complete_legacy_results
    """.split()),
    "spatial": ("phase4_spatial", """
        disabled_single_dual_whole_result_identity_with_nontrivial_psf
        enabled_spatial_result_matches_core_on_sampled_input
        full_crop_fixed_maps_and_readouts_all_parities_and_cfas
        independent_multiband_optics_geometry_and_signed_noise_oracle
        wrong_cfa_blur_and_pre_well_electronics_controls
        post_optics_identity_nonuniform_sampling_and_duplicate_psf_rejection
        retained_spatial_baseline_is_unchanged_valid_legacy_context
        new_result_identity_exact_bundle_roundtrip_and_old_schema_rejection
        exact_coordinate_coverage_and_declared_psf_support
        strict_options_binding_and_rng_cleanup_after_legacy_baseline
    """.split()),
    "artifact_io": ("phase4_artifacts", """
        enabled_single_dual_core_and_spatial_exact_roundtrips
        singleton_scalar_full_grid_map_and_empty_metadata_shapes
        independent_asymmetric_2x3x4_c_order_little_endian_bytes
        strict_native_producer_validation_before_publication
        rehashed_maps_expectations_charge_and_well_semantic_corruptions
        rehashed_electronics_adc_and_observed_merge_corruptions
        complete_spatial_analog_and_report_history_corruptions
        strict_typed_fields_shapes_classes_and_role_units
        contiguous_offsets_lengths_totals_and_no_padding
        malformed_json_wire_kinds_duplicates_and_unicode_boundaries
        source_runtime_flags_and_unknown_metadata
        payload_hash_truncation_logical_and_nonfinite_bytes
        exact_inventory_missing_extra_symlink_hardlink_entries
        canonical_paths_symlink_ancestors_and_refuse_existing
        caller_rng_and_distinct_repeat_artifacts
        supported_stochastic_alternate_without_seed_replay
        staging_collision_and_ambiguous_creation_preserve_preexisting
        injected_midwrite_failure_owned_cleanup
        injected_publication_failure_foreign_and_replaced_identity
        injected_read_and_write_close_failure_propagation
    """.split()),
    "demo_contract": ("phase4_demo", """
        fixed_24_frame_inventory_generation_only_and_rng
        four_physical_exposure_and_electronic_gain_sweeps
        three_sequence_roles_seed_wrap_reset_continuation_ei
        independent_adc_well_merge_map_coverage
        explicit_units_assumed_provenance_and_runtime
        complete_24_bundle_export_exact_native_readbacks
        existing_output_stale_success_is_never_overwritten
        invalid_output_paths_and_symlink_ancestors_reject
        missing_exporter_or_reader_reject_before_creation
        incomplete_summary_until_every_export_and_readback
        injected_exporter_failure_cleans_only_owned_stage
        injected_reader_failure_and_mismatch_clean_owned_stage
        staging_collision_and_replacement_identity_preserve_sentinels
        publication_failure_race_identity_and_summary_cleanup
    """.split()),
    "numerical_edges": ("phase4_numerical_edges", """
        represented_seed_and_sequence_index_endpoints
        exact_zero_support_at_finite_extremes
        normal_boundary_and_signed_cancellation
        spectral_overflow_and_positive_support_underflow
        prnu_dark_and_total_charge_arithmetic
        poisson_limit_and_component_preflight
        electronic_rms_and_gain_numeric_limits
        late_stochastic_failure_restores_rng
        constructor_aggregate_maps_reject_before_densification
        core_combined_budget_rejects_before_expansion
        spatial_combined_budget_rejects_before_legacy_sampling
        spatial_retained_options_and_spectral_storage_are_bounded
        bounded_spatial_and_disabled_legacy_results
        sequence_retained_model_budget_and_failure_cleanup
    """.split()),
}
EXPECTED_COUNTS = (9, 11, 11, 10, 12, 10, 20, 14, 14)
LAYERS = ((), ("phase3",), ("phase3", "phase2"), ("phase3", "phase2", "phase1"))
NONTRUE = (False, 0, 1, 1.0, "true", "passed", None, [], {})


def synthetic_report():
    """Compose validator test data; this does not represent Phase 4 execution."""
    previous = deepcopy(HISTORICAL)
    report = {"schema_version": "1.0", "phase": 4, "status": "passed",
              "phase4_passed": True, "phase3_required": True, "calibrated_alev4": False,
              "runtime": previous["runtime"], "runtime_version": previous["runtime_version"],
              "provenance": deepcopy(previous["provenance"]), "phase3": previous}
    for name, (identity, groups) in GROUPS.items():
        report[name] = {"suite": identity, "status": "passed", "passed": True,
                        "test_count": len(groups), "tests": [
                            {"name": group, "status": "passed", "passed": True} for group in groups]}
    return report


def at(value, path):
    for key in path:
        value = value[key]
    return value


class Phase4NumericalReportTests(unittest.TestCase):
    def reject(self, mutate, message=""):
        report = synthetic_report()
        mutate(report)
        with self.assertRaisesRegex(verifier.ArtifactError, message):
            verifier.check_numerical_report(report)

    def test_positive_complete_synthetic_report_and_unchanged_historical_prerequisite(self):
        report = synthetic_report()
        original = deepcopy(report)
        expected = "5b61230f6b652d7d053910ea32e144bb9441774a"
        source, engine, groups, prior_groups, phase2_groups = verifier.check_numerical_report(report, expected)
        self.assertEqual(tuple(len(names) for _, names in GROUPS.values()), EXPECTED_COUNTS)
        self.assertEqual((groups, prior_groups, phase2_groups), (111, 135, 62))
        self.assertEqual(engine, ("GNU Octave", "9.4.0"))
        self.assertEqual(source, {"repository_head": expected,
            "isetcam_head": "3e0253421752eb72f2d1353327dffd0d433abdaf",
            "isethdrsensor_head": "ee2dacceb456516de3ecefadd72955154cf3cabe"})
        self.assertEqual(report, original)
        self.assertEqual(report["phase3"], HISTORICAL)

    def test_exact_integral_json_numbers_remain_valid(self):
        report = synthetic_report()
        report["phase"] = 4.0
        for name in GROUPS:
            report[name]["test_count"] = float(report[name]["test_count"])
        self.assertEqual(verifier.check_numerical_report(report)[2:], (111, 135, 62))

    def test_missing_or_malformed_required_suite_rejects_each_gate(self):
        for name in GROUPS:
            with self.subTest(name=name, mutation="omission"):
                self.reject(lambda r: r.pop(name), name)
            for value in (None, [], True, "passed", 1):
                with self.subTest(name=name, value=value):
                    self.reject(lambda r: r.__setitem__(name, value), name)

    def test_all_suite_fields_are_required(self):
        for name in GROUPS:
            for key in ("suite", "status", "passed", "test_count", "tests"):
                with self.subTest(name=name, key=key):
                    self.reject(lambda r: r[name].pop(key), name)

    def test_suite_identity_is_frozen_and_cannot_be_relabelled(self):
        for name, (identity, _) in GROUPS.items():
            for wrong in ("phase4_wrong", identity + " ", name, None, 4, [], {}):
                with self.subTest(name=name, identity=wrong):
                    self.reject(lambda r: r[name].__setitem__("suite", wrong), name)

    def test_equal_count_suites_cannot_be_swapped_or_renamed_to_match(self):
        for left, right in (("core", "noise"), ("rng", "spatial"), ("demo_contract", "numerical_edges")):
            for relabel in (False, True):
                def swap(report):
                    report[left], report[right] = report[right], report[left]
                    if relabel:
                        report[left]["suite"], report[right]["suite"] = GROUPS[left][0], GROUPS[right][0]
                with self.subTest(left=left, right=right, relabel=relabel):
                    self.reject(swap, left)

    def test_every_group_is_required_even_when_declared_count_is_decreased(self):
        for name, (_, groups) in GROUPS.items():
            for index in range(len(groups)):
                def omit(report):
                    report[name]["tests"].pop(index)
                    report[name]["test_count"] -= 1
                with self.subTest(name=name, missing=groups[index]):
                    self.reject(omit, "complete frozen test inventory/count")

    def test_count_matched_prefix_truncation_and_singleton_object_reject(self):
        for name in GROUPS:
            for singleton in (False, True):
                def truncate(report):
                    report[name]["test_count"] = 1
                    report[name]["tests"] = report[name]["tests"][0] if singleton else report[name]["tests"][:1]
                with self.subTest(name=name, singleton=singleton):
                    self.reject(truncate, "complete frozen test inventory/count")

    def test_missing_extra_and_invalid_inventory_containers_reject(self):
        for name in GROUPS:
            for kind in ("omit", "extra", "count_matched_extra"):
                def mutate(report):
                    suite = report[name]
                    if kind == "omit":
                        suite["tests"].pop()
                    else:
                        suite["tests"].append({"name": "invented_group", "status": "passed", "passed": True})
                        if kind == "count_matched_extra":
                            suite["test_count"] += 1
                with self.subTest(name=name, kind=kind):
                    self.reject(mutate, name)
            for value in (None, {}, "tests", 1, True):
                with self.subTest(name=name, value=value):
                    self.reject(lambda r: r[name].__setitem__("tests", value), name)

    def test_global_total_cannot_hide_different_suite_counts(self):
        report = synthetic_report()
        moved = report["config"]["tests"].pop()
        report["config"]["test_count"] -= 1
        report["core"]["tests"].append(moved)
        report["core"]["test_count"] += 1
        self.assertEqual(sum(report[name]["test_count"] for name in GROUPS), 111)
        with self.assertRaisesRegex(verifier.ArtifactError, "config: complete frozen"):
            verifier.check_numerical_report(report)

    def test_each_adjacent_group_order_is_required(self):
        for name, (_, groups) in GROUPS.items():
            for index in range(len(groups) - 1):
                def reorder(report):
                    tests = report[name]["tests"]
                    tests[index], tests[index + 1] = tests[index + 1], tests[index]
                with self.subTest(name=name, index=index):
                    self.reject(reorder, "frozen test names/order")

    def test_every_group_name_is_frozen(self):
        for name, (_, groups) in GROUPS.items():
            for index in range(len(groups)):
                with self.subTest(name=name, index=index):
                    self.reject(lambda r: r[name]["tests"][index].__setitem__("name", "invented_group"),
                                "frozen test names/order")

    def test_duplicate_names_cannot_replace_required_groups(self):
        for name in GROUPS:
            with self.subTest(name=name):
                self.reject(lambda r: r[name]["tests"][1].update(r[name]["tests"][0]),
                            "frozen test names/order")

    def test_counts_reject_boolean_fractional_nonfinite_and_wrong_types(self):
        for name in GROUPS:
            for value in (True, False, -1, 0, 1, 9.5, float("inf"), float("nan"), "9", None, [], {}):
                with self.subTest(name=name, value=value):
                    self.reject(lambda r: r[name].__setitem__("test_count", value), name)

    def test_suite_status_must_be_passed_including_skipped_and_core_only(self):
        for name in GROUPS:
            for status in ("skipped", "not_run", "running", "failed", "core_only", "Passed", "passed ", True, None):
                with self.subTest(name=name, status=status):
                    self.reject(lambda r: r[name].__setitem__("status", status), name)

    def test_suite_passed_flags_require_actual_true(self):
        for name in GROUPS:
            for value in NONTRUE:
                with self.subTest(name=name, value=value):
                    self.reject(lambda r: r[name].__setitem__("passed", value), name)

    def test_every_group_rejects_skipped_or_false_despite_passed_suite(self):
        for name, (_, groups) in GROUPS.items():
            for index in range(len(groups)):
                for key, value in (("status", "skipped"), ("passed", False)):
                    with self.subTest(name=name, index=index, key=key):
                        self.reject(lambda r: r[name]["tests"][index].__setitem__(key, value),
                                    "unpassed individual test group")

    def test_group_fields_types_status_and_truthiness_are_strict(self):
        for name in GROUPS:
            for key in ("name", "status", "passed"):
                with self.subTest(name=name, missing=key):
                    self.reject(lambda r: r[name]["tests"][0].pop(key), name)
            for value in NONTRUE:
                with self.subTest(name=name, passed=value):
                    self.reject(lambda r: r[name]["tests"][0].__setitem__("passed", value), name)
            for value in (None, [], "passed", True, 1):
                with self.subTest(name=name, group=value):
                    self.reject(lambda r: r[name]["tests"].__setitem__(0, value), name)
            for key, values in (("name", (None, "", " ", 1, True, [], {})),
                                ("status", (None, True, 1, "Passed", "failed", "passed "))):
                for value in values:
                    with self.subTest(name=name, key=key, value=value):
                        self.reject(lambda r: r[name]["tests"][0].__setitem__(key, value), name)

    def test_top_level_report_completeness_and_strict_flags(self):
        for value in (None, [], True, "passed", 4):
            with self.subTest(report=value), self.assertRaises(verifier.ArtifactError):
                verifier.check_numerical_report(value)
        for key, values in (("schema_version", (None, 1, "2.0")),
                            ("phase", (True, 3, 4.5, "4")),
                            ("status", (None, "skipped", "core_only", "failed", True)),
                            ("phase4_passed", NONTRUE), ("phase3_required", NONTRUE),
                            ("calibrated_alev4", (True, 0, "false", None))):
            for value in values:
                with self.subTest(key=key, value=value):
                    self.reject(lambda r: r.__setitem__(key, value))

    def test_all_earlier_reports_and_completion_flags_remain_required(self):
        for path, phase in zip(LAYERS[1:], (3, 2, 1)):
            for value in (None, [], {}, True):
                with self.subTest(path=path, report=value):
                    self.reject(lambda r: at(r, path[:-1]).__setitem__(path[-1], value))
            for key, values in (("status", ("skipped", "core_only", "failed", None)),
                                (f"phase{phase}_passed", NONTRUE),
                                ("calibrated_alev4", (True, 0, None)),
                                ("schema_version", (None, "2.0")), ("phase", (True, phase + 1))):
                for value in values:
                    with self.subTest(path=path, key=key, value=value):
                        self.reject(lambda r: at(r, path).__setitem__(key, value))
            if phase > 1:
                for value in NONTRUE:
                    with self.subTest(path=path, required=value):
                        self.reject(lambda r: at(r, path).__setitem__(f"phase{phase - 1}_required", value))

    def test_all_earlier_numerical_and_iset_gates_remain_required(self):
        for path in LAYERS[1:]:
            previous = at(synthetic_report(), path)
            gates = [key for key, value in previous.items() if isinstance(value, dict) and "test_count" in value]
            for name in gates:
                for kind in ("missing", "skipped", "zero_count"):
                    def mutate(report):
                        parent = at(report, path)
                        if kind == "missing":
                            parent.pop(name)
                        elif kind == "skipped":
                            parent[name]["status"] = "skipped"
                        else:
                            parent[name]["test_count"] = 0
                    with self.subTest(path=path, name=name, kind=kind):
                        self.reject(mutate)

    def test_genuine_iset_comparison_checks_are_not_bypassed(self):
        for name in ("first_exposure", "second_exposure"):
            for key, value in (("status", "skipped"), ("max_relative_error", 1), ("relative_tolerance", 1)):
                with self.subTest(name=name, key=key):
                    self.reject(lambda r: r["phase3"]["phase2"]["phase1"]["iset"][name].__setitem__(key, value))
        for name in ("uniform", "ramp", "checker", "edge"):
            with self.subTest(spatial=name):
                self.reject(lambda r: r["phase3"]["iset_spatial"]["metrics"]["fixtures"].pop(name))
        for key, value in (("synthetic", False), ("calibrated_alev4", True), ("native_matlab_executed", True)):
            with self.subTest(metric=key):
                self.reject(lambda r: r["phase3"]["iset_spatial"]["metrics"].__setitem__(key, value))

    def test_source_heads_required_well_formed_and_associated_at_all_phases(self):
        for path in LAYERS:
            for key in ("repository_head", "isetcam_head", "isethdrsensor_head"):
                for value in ("", "2" * 40, "A" * 40, "short", None, True):
                    with self.subTest(path=path, key=key, value=value):
                        self.reject(lambda r: at(r, path)["provenance"].__setitem__(key, value))
            for value in (None, {}, [], "source"):
                with self.subTest(path=path, provenance=value):
                    self.reject(lambda r: at(r, path).__setitem__("provenance", value))

    def test_even_consistently_forged_dependency_heads_reject_pins(self):
        for key in ("isetcam_head", "isethdrsensor_head"):
            def forge(report):
                for path in LAYERS:
                    at(report, path)["provenance"][key] = "2" * 40
                for fixture in report["phase3"]["iset_spatial"]["metrics"]["fixtures"].values():
                    fixture["provenance"][key] = "2" * 40
            with self.subTest(key=key):
                self.reject(forge, "frozen dependency pins")

    def test_expected_commit_must_be_full_lowercase_and_match(self):
        for expected in ("2" * 40, "A" * 40, "", "638c23d", True, [], {}):
            with self.subTest(expected=expected), self.assertRaises(verifier.ArtifactError):
                verifier.check_numerical_report(synthetic_report(), expected)

    def test_runtime_name_version_and_cross_phase_association_remain_required(self):
        for path in LAYERS:
            for key, values in (("runtime", ("Python", "MATLAB", "", None, 1)),
                                ("runtime_version", ("different-version", "", " ", None, 9.4))):
                for value in values:
                    with self.subTest(path=path, key=key, value=value):
                        self.reject(lambda r: at(r, path).__setitem__(key, value))


class Phase4NumericalReportCliTests(unittest.TestCase):
    """Actual CLI failures, using Python copies with no native source or PATH."""
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="phase4-report-only-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        scripts = self.root / "verifiers"
        scripts.mkdir()
        for phase in (1, 2, 3, 4):
            filename = f"verify_phase{phase}_artifacts.py"
            shutil.copyfile(ROOT / "scripts" / filename, scripts / filename)
        self.script = scripts / SCRIPT.name
        self.outputs = self.root / "outputs"
        (self.outputs / "validation").mkdir(parents=True)
        self.report = self.outputs / "validation/phase4-validation.json"

    def run_cli(self, report=None, *, text=None, expected=None):
        self.report.write_text(json.dumps(report) if text is None else text, encoding="utf-8")
        command = [sys.executable, str(self.script), str(self.outputs)]
        if expected is not None:
            command.extend(("--expected-commit", expected))
        result = subprocess.run(command, cwd=self.root, env={**os.environ, "PATH": ""},
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertIn("FAIL:", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        return result.stderr

    def test_complete_synthetic_report_still_requires_actual_demo_artifacts(self):
        error = self.run_cli(synthetic_report(), expected=HISTORICAL["provenance"]["repository_head"])
        self.assertIn("Missing/unreadable artifact directory", error)
        self.assertFalse((self.root / "matlab").exists())

    def test_count_matched_truncation_of_each_suite_fails_before_demo(self):
        for name in GROUPS:
            report = synthetic_report()
            report[name]["test_count"] = 1
            report[name]["tests"] = report[name]["tests"][:1]
            with self.subTest(name=name):
                self.assertIn(name + ": complete frozen test inventory/count", self.run_cli(report))

    def test_identity_rename_reorder_duplicate_and_skipped_groups_fail_before_demo(self):
        mutations = (
            (lambda r: r["config"].__setitem__("suite", "phase4_core"), "misidentified"),
            (lambda r: r["core"]["tests"][0].__setitem__("name", "invented"), "names/order"),
            (lambda r: r["noise"]["tests"].reverse(), "names/order"),
            (lambda r: r["rng"]["tests"][1].update(r["rng"]["tests"][0]), "names/order"),
            (lambda r: r["spatial"]["tests"][0].__setitem__("status", "skipped"), "unpassed"),
            (lambda r: r["sequence"]["tests"][0].__setitem__("passed", 1), "unpassed"),
        )
        for mutate, expected in mutations:
            report = synthetic_report()
            mutate(report)
            with self.subTest(expected=expected):
                self.assertIn(expected, self.run_cli(report))

    def test_prerequisite_source_runtime_and_requested_revision_fail_before_demo(self):
        mutations = (
            (lambda r: r["phase3"].__setitem__("phase2_required", False), "Phase 3 report"),
            (lambda r: r["phase3"]["phase2"]["phase1"]["iset"].__setitem__("status", "skipped"), "Phase 1 prerequisite"),
            (lambda r: r["provenance"].__setitem__("isetcam_head", "2" * 40), "frozen dependency pins"),
            (lambda r: r.__setitem__("runtime_version", "different-version"), "source/runtime differs"),
        )
        for mutate, expected in mutations:
            report = synthetic_report()
            mutate(report)
            with self.subTest(expected=expected):
                self.assertIn(expected, self.run_cli(report))
        self.assertIn("another commit", self.run_cli(synthetic_report(), expected="2" * 40))

    def test_strict_report_json_rejects_duplicates_nonfinite_and_truncation(self):
        original = json.dumps(synthetic_report())
        malformed = (original.replace('"phase": 4', '"phase": 4, "phase": 4', 1),
                     original.replace('"phase": 4', '"phase": NaN', 1), original[:-1], "[]", "null")
        for content in malformed:
            with self.subTest(content=content[:30]):
                self.run_cli(text=content)


if __name__ == "__main__":
    unittest.main()
