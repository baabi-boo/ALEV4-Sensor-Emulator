"""Independent Python-only corruption tests for the Phase 3 evidence gate.

All files are temporary handwritten/analytic fixtures, never native simulator
output or claimed numerical evidence. These tests must run before Octave is
installed in the preserved Phase 1/2 CI jobs.
"""
from contextlib import redirect_stderr, redirect_stdout
from copy import deepcopy
import hashlib
import importlib.util
import io
import json
import math
import os
from pathlib import Path
import shutil
import struct
import tempfile
import unittest

from phase3_fixture_support import (
    DEMO_NAMES, PHASE1_GATES, PHASE2_GATES, PHASE3_GATES, SOURCE,
    make_identity_bundle, make_numerical_report, make_outputs,
    make_overlap_bundle, make_psf_bundle, write_json,
)


SPEC = importlib.util.spec_from_file_location(
    "phase3_artifacts", Path(__file__).resolve().parents[1] / "verify_phase3_artifacts.py")
verifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verifier)


def refresh_descriptor(directory, key, *, length=False):
    """Refresh a corrupted file's hash so its semantic check must actually run."""
    manifest = directory / "spatial.json"
    meta = json.loads(manifest.read_bytes())
    record = meta["files"][key]
    content = (directory / record["name"]).read_bytes()
    record["sha256"] = hashlib.sha256(content).hexdigest()
    if length:
        record["byte_count"] = len(content)
    write_json(manifest, meta)


class BundleMutationMixin:
    def rejects_metadata(self, mutation, message, *, directory=None, nested=False):
        directory = self.bundle if directory is None else directory
        manifest = directory / "spatial.json"
        target = directory / "readout.json" if nested else manifest
        saved_manifest, saved_target = manifest.read_bytes(), target.read_bytes()
        try:
            meta = json.loads(saved_target)
            mutation(meta)
            write_json(target, meta)
            if nested:
                refresh_descriptor(directory, "readout_metadata", length=True)
            with self.assertRaisesRegex(verifier.ArtifactError, message):
                verifier.verify_bundle(directory)
        finally:
            target.write_bytes(saved_target)
            manifest.write_bytes(saved_manifest)

    def rejects_payload(self, key, replacement, message, *, directory=None,
                        rehash=True, length=False):
        directory = self.bundle if directory is None else directory
        manifest = directory / "spatial.json"
        saved_manifest = manifest.read_bytes()
        meta = json.loads(saved_manifest)
        target = directory / meta["files"][key]["name"]
        original = target.read_bytes()
        try:
            target.write_bytes(replacement(original))
            if rehash:
                refresh_descriptor(directory, key, length=length)
            with self.assertRaisesRegex(verifier.ArtifactError, message):
                verifier.verify_bundle(directory)
        finally:
            target.write_bytes(original)
            manifest.write_bytes(saved_manifest)


class Phase3BundleTests(BundleMutationMixin, unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="phase3-bundle-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.bundle = self.root / "overlap"
        make_overlap_bundle(self.bundle)

    def test_single_overlap_crop_qe_area_and_bytes_have_handwritten_answers(self):
        bundle = verifier.verify_bundle(self.bundle, expected_commit="1" * 40)
        self.assertEqual(list(bundle["sampled_irradiance"]), [30, 35, 60, 70])
        self.assertEqual(list(bundle["expected_electrons"]), [56.25, 48.125])
        self.assertEqual(bundle["sensor"]["cfa_pattern"], "BGGR")
        # First pixel clips at physical well=50; second has an exact .5-DN
        # tie after gain/black. Neither answer is inferred from verifier code.
        self.assertEqual(list(bundle["raw"]), [100, 97])
        self.assertEqual((self.bundle / "readout.raw").read_bytes(), b"\x64\x00\x61\x00")
        self.assertEqual((self.bundle / "sampled.f64").read_bytes(),
                         struct.pack("<4d", 30, 35, 60, 70))
        self.assertEqual(bundle["metadata"]["files"]["input_irradiance"]["shape"], [2, 3, 2])
        self.assertEqual(len(bundle["files"]), 7)
        self.assertIs(bundle["general_format_checked"], True)
        self.assertIs(bundle["spatial_physics_checked"], True)
        self.assertIs(bundle["deterministic_readout_checked"], True)
        for flag in ("demo_fixture_checked", "random_stream_reproduced", "input_source_authenticated"):
            self.assertIs(bundle[flag], False)

    def test_dual_overlap_has_independent_physical_and_adc_flags(self):
        directory = self.root / "dual"
        make_overlap_bundle(directory, mode="dual")
        bundle = verifier.verify_bundle(directory)
        self.assertEqual(list(bundle["expected_electrons"]), [56.25, 48.125])
        self.assertEqual(list(bundle["high_raw"]), [255, 255])
        self.assertEqual(list(bundle["low_raw"]), [102, 98])
        self.assertEqual(list(bundle["merged_electrons"]), [50.25, 48.25])
        # Physical saturation (bit 0) differs despite both high ADCs clipping.
        self.assertEqual(list(bundle["flags"]), [69, 196])
        self.assertEqual((directory / "readout.flags.u8").read_bytes(), b"\x45\xc4")
        self.assertEqual(len(bundle["files"]), 10)

    def test_even_asymmetric_per_bin_psf_and_crop_have_literal_answers(self):
        for mode in ("single", "dual"):
            with self.subTest(mode=mode):
                directory = self.root / ("psf-" + mode)
                make_psf_bundle(directory, mode=mode)
                bundle = verifier.verify_bundle(directory)
                self.assertEqual(list(bundle["optical_irradiance"]),
                                 [13.125, 26.25, 210, 420, 0, 0, 0, 4])
                self.assertEqual(list(bundle["sampled_irradiance"]),
                                 [13.125, 26.25, 210, 420, 0, 0, 0, 4])
                self.assertEqual(list(bundle["expected_electrons"]),
                                 [4.921875, 6.5625, 52.5, 54])
                self.assertEqual(bundle["metadata"]["optical_grid"]["y_edges_m"], [1, 2, 3])
                self.assertEqual(bundle["metadata"]["files"]["psf"]["shape"], [2, 3, 2])
                if mode == "single":
                    self.assertEqual(list(bundle["raw"]), [10, 13, 100, 100])

    def test_shared_psf_reuses_the_same_kernel_for_each_bin(self):
        directory = self.root / "shared"
        make_psf_bundle(directory, shared=True)
        bundle = verifier.verify_bundle(directory)
        self.assertEqual(list(bundle["optical_irradiance"]),
                         [13.125, 26.25, 210, 420, 2, 2, 2, 1])
        self.assertEqual(list(bundle["expected_electrons"]),
                         [6.421875, 7.6875, 53.625, 52.875])
        self.assertEqual(list(bundle["raw"]), [13, 16, 100, 100])

    def test_single_bin_one_pixel_identity_retains_explicit_cube_rank(self):
        for mode in ("single", "dual"):
            for stage in ("pre_psf", "post_optics"):
                with self.subTest(mode=mode, stage=stage):
                    directory = self.root / (mode + stage)
                    make_identity_bundle(directory, mode=mode, stage=stage)
                    bundle = verifier.verify_bundle(directory)
                    self.assertEqual(bundle["metadata"]["files"]["sampled_irradiance"]["shape"], [1, 1, 1])
                    self.assertEqual(bundle["sensor"]["qe"], [[1, 1, 1]])
                    self.assertEqual(list(bundle["expected_electrons"]), [1])
                    self.assertIs(bundle["deterministic_readout_checked"], True)

    def test_tiny_and_minimum_subnormal_identity_are_not_rounded_to_zero(self):
        for index, value in enumerate((1e-280, math.ulp(0.0))):
            for stage in ("pre_psf", "post_optics"):
                with self.subTest(value=value, stage=stage):
                    directory = self.root / f"tiny-{index}-{stage}"
                    make_identity_bundle(directory, values=(value,), stage=stage)
                    bundle = verifier.verify_bundle(directory)
                    for key in ("input_irradiance", "optical_irradiance", "sampled_irradiance", "expected_electrons"):
                        self.assertEqual(list(bundle[key]), [value])
                    for key, message in (("sampled_irradiance", "exact copy"),
                                         ("expected_electrons", "exact zero")):
                        self.rejects_payload(key, lambda _: struct.pack("<d", 0), message,
                                             directory=directory)

    def test_dual_merge_uses_observed_codes_and_conservative_rail_validity(self):
        directory = self.root / "handoff"
        make_identity_bundle(directory, values=(0, 15.125, 31.5, 31.625, 60), mode="dual")
        bundle = verifier.verify_bundle(directory)
        self.assertEqual(list(bundle["high_raw"]), [2, 123, 254, 255, 255])
        self.assertEqual(list(bundle["low_raw"]), [2, 32, 65, 65, 102])
        self.assertEqual(list(bundle["flags"]), [224, 224, 224, 192, 69])
        self.assertEqual(bundle["merged_electrons"][0], 0)
        self.assertAlmostEqual(bundle["merged_electrons"][1], 15.19218359375, places=12)
        self.assertEqual(list(bundle["merged_electrons"])[2:], [31.75, 31.75, 50.25])
        self.rejects_payload("merged_electrons",
                             lambda b: b[:8] + struct.pack("<d", 15.125) + b[16:],
                             "observable dual merge", directory=directory)

    def test_stale_hash_detects_payload_corruption_before_interpretation(self):
        self.rejects_payload("sampled_irradiance", lambda b: bytes([b[0] ^ 1]) + b[1:],
                             "SHA-256 mismatch", rehash=False)
        self.rejects_payload("readout_metadata", lambda b: b.replace(b"Artificial", b"artificial", 1),
                             "SHA-256 mismatch", rehash=False)

    def test_rehashed_overlap_and_expected_values_are_recomputed(self):
        self.rejects_payload("sampled_irradiance", lambda b: struct.pack("<d", 31) + b[8:],
                             "rectangular overlap average")
        self.rejects_payload("expected_electrons", lambda b: struct.pack("<d", 56.5) + b[8:],
                             "spectral expected electrons")
        # A huge altered observation cannot widen its own tolerance.
        self.rejects_payload("expected_electrons", lambda b: struct.pack("<d", 1e300) + b[8:],
                             "spectral expected electrons")

    def test_post_optics_requires_exact_input_and_grid_identity(self):
        self.rejects_payload("optical_irradiance", lambda b: struct.pack("<d", 11) + b[8:],
                             "Post-optics input must be unchanged")
        self.rejects_metadata(lambda m: m["optical_grid"]["x_edges_m"].__setitem__(1, 1.25),
                              "Post-optics input must be unchanged")

    def test_rehashed_nonidentity_psf_output_cannot_hide_wrong_convolution(self):
        directory = self.root / "psf"
        make_psf_bundle(directory)
        self.rejects_payload("optical_irradiance", lambda b: struct.pack("<d", 13.25) + b[8:],
                             "PSF convolution", directory=directory)
        # Reversing the asymmetric first kernel is still normalized. Its
        # refreshed hash therefore reaches the independent convolution check.
        self.rejects_payload("psf", lambda b: struct.pack("<6d", .125, .25, .125, .25, .25, 0) + b[48:],
                             "PSF convolution", directory=directory)
        self.rejects_payload("psf", lambda b: struct.pack("<d", .1) + b[8:],
                             "not already normalized", directory=directory)

    def test_rehashed_nonfinite_or_negative_spatial_values_reject(self):
        for key in ("input_irradiance", "optical_irradiance", "sampled_irradiance", "expected_electrons"):
            for value in (-1, math.inf, math.nan):
                with self.subTest(key=key, value=value):
                    self.rejects_payload(key, lambda b, v=value: struct.pack("<d", v) + b[8:],
                                         "nonfinite or negative sample")

    def test_deterministic_readout_rejects_unclipped_or_wrong_rounding_codes(self):
        for codes in ((113, 97), (100, 96)):
            with self.subTest(codes=codes):
                self.rejects_payload("raw", lambda _, v=codes: struct.pack("<2H", *v),
                                     "physical clipping/ADC rounding")
        self.rejects_payload("raw", lambda _: b"\xff\xff\x61\x00", "ADC range")

    def test_dual_diagnostics_cannot_hide_saturation_or_fabricate_clipping(self):
        directory = self.root / "dual"
        make_overlap_bundle(directory, mode="dual")
        self.rejects_payload("flags", lambda b: bytes([b[0] ^ 1]) + b[1:],
                             "validity flags|physical-saturation", directory=directory)
        self.rejects_payload("flags", lambda b: bytes([b[0] | 128]) + b[1:],
                             "validity flags", directory=directory)
        self.rejects_payload("flags", lambda b: bytes([b[0] | 16]) + b[1:],
                             "clipping diagnostics", directory=directory)
        # Clearing the high clipping diagnostic leaves observable rail flags
        # consistent, but the deterministic analog calculation must reject it.
        self.rejects_payload("flags", lambda b: bytes([b[0] & ~4]) + b[1:],
                             "Deterministic dual", directory=directory)

    def test_nested_readout_associations_are_checked_after_hash_refresh(self):
        mutations = (
            (lambda m: m.update(seed=24), "exposure/seed"),
            (lambda m: m.update(exposure_s=.25), "exposure/seed"),
            (lambda m: m["runtime"].update(version="different"), "runtime/provenance"),
            (lambda m: m["provenance"].update(repository_head="2" * 40), "runtime/provenance"),
            (lambda m: m["sensor"].update(fill_factor=.25), "complete configuration"),
            (lambda m: m.update(cfa_pattern="RGGB"), "shape/CFA/length"),
            (lambda m: m.update(height=2), "shape/CFA/length"),
            (lambda m: m.update(units="electrons"), "single format"),
        )
        for mutation, message in mutations:
            with self.subTest(message=message):
                self.rejects_metadata(mutation, message, nested=True)

    def test_nested_single_and_dual_manifests_reject_unknown_fields(self):
        self.rejects_metadata(lambda m: m.update(ignored_setting=True), "unknown fields", nested=True)
        directory = self.root / "dual"
        make_overlap_bundle(directory, mode="dual")
        self.rejects_metadata(lambda m: m.update(ignored_setting=True), "unknown fields",
                              directory=directory, nested=True)
        self.rejects_metadata(lambda m: m["files"].update(high_raw="elsewhere.high.raw"),
                              "file associations", directory=directory, nested=True)

    def test_malformed_json_is_rejected_in_both_manifests(self):
        manifest = self.bundle / "spatial.json"
        original = manifest.read_bytes()
        for content in (b"\xff", b"{} trailing", b"[]", b'{"format":}', b"\xef\xbb\xbf{}"):
            with self.subTest(content=content):
                try:
                    manifest.write_bytes(content)
                    with self.assertRaisesRegex(verifier.ArtifactError, "JSON"):
                        verifier.verify_bundle(self.bundle)
                finally:
                    manifest.write_bytes(original)
                self.rejects_payload("readout_metadata", lambda _, c=content: c,
                                     "JSON|byte count", length=True)

    def test_duplicate_keys_including_escaped_spellings_are_not_erased(self):
        manifest = self.bundle / "spatial.json"
        original = manifest.read_bytes()
        for prefix in (b'{"synthetic":true,', b'{"syntheti\\u0063":true,'):
            try:
                manifest.write_bytes(prefix + original[1:])
                with self.assertRaisesRegex(verifier.ArtifactError, "Duplicate JSON field"):
                    verifier.verify_bundle(self.bundle)
            finally:
                manifest.write_bytes(original)
        self.rejects_payload("readout_metadata", lambda b: b'{"sensor":{},' + b[1:],
                             "Duplicate JSON field", length=True)

    def test_json_nonfinite_and_nonzero_underflow_lexemes_reject(self):
        manifest = self.bundle / "spatial.json"
        original = manifest.read_bytes()
        for token in (b"NaN", b"Infinity", b"1e400", b"1e-4000", b"-1e-4000"):
            with self.subTest(token=token):
                try:
                    content = original.replace(b'"exposure_s":0.5', b'"exposure_s":' + token)
                    self.assertNotEqual(content, original)
                    manifest.write_bytes(content)
                    with self.assertRaisesRegex(verifier.ArtifactError, "Nonfinite|underflowed"):
                        verifier.verify_bundle(self.bundle)
                finally:
                    manifest.write_bytes(original)
        self.rejects_payload("readout_metadata",
                             lambda b: b.replace(b'"exposure_s":0.5', b'"exposure_s":1e-4000'),
                             "underflowed", length=True)

    def test_actual_json_read_and_metadata_declared_length_are_bounded(self):
        manifest = self.bundle / "spatial.json"
        original = manifest.read_bytes()
        try:
            manifest.write_bytes(original + b" " * (verifier.MAX_JSON - len(original) + 1))
            with self.assertRaisesRegex(verifier.ArtifactError, "Oversized artifact"):
                verifier.verify_bundle(self.bundle)
        finally:
            manifest.write_bytes(original)
        self.rejects_metadata(lambda m: m["files"]["readout_metadata"].update(byte_count=2_000_001),
                              "manifest byte count")

    def test_booleans_cannot_stand_in_for_numeric_spatial_fields(self):
        mutations = (
            lambda m: m.update(exposure_s=True),
            lambda m: m.update(seed=False),
            lambda m: m["configuration"].update(fill_factor=True),
            lambda m: m["geometry"]["active_roi"].__setitem__(0, True),
            lambda m: m["geometry"]["full_grid_size"].__setitem__(0, True),
            lambda m: m["geometry"]["origin_xy_m"].__setitem__(0, False),
            lambda m: m["input_grid"]["x_edges_m"].__setitem__(0, False),
            lambda m: m["files"]["sampled_irradiance"]["shape"].__setitem__(0, True),
            lambda m: m["files"]["expected_electrons"].update(byte_count=True),
        )
        for index, mutation in enumerate(mutations):
            with self.subTest(field=index):
                self.rejects_metadata(mutation, "boolean|expected number")
        self.rejects_metadata(lambda m: m.update(seed=True), "boolean", nested=True)

    def test_payload_rank_product_and_integer_limits_precede_allocation(self):
        for dimensions in ([1, 2], [1, 2, 2, 1], [1, 2.5, 2], [0, 2, 2],
                           [10001, 10000, 1], [1, 1, 100_000_001], [1, 1, 2 ** 2048]):
            with self.subTest(dimensions=dimensions):
                self.rejects_metadata(lambda m, d=dimensions: m["files"]["sampled_irradiance"].update(shape=d),
                                      "rank|integer|range|limit|overflow")
        self.rejects_metadata(lambda m: m["configuration"].update(image_size=[10001, 10000]),
                              "Pixel limit")
        for seed in (-1, .5, 2 ** 32):
            self.rejects_metadata(lambda m, s=seed: m.update(seed=s), "seed")

    def test_complete_schema_is_required_without_defaults_or_foreign_fields(self):
        mutations = (
            lambda m: m.pop("geometry"),
            lambda m: m.update(unrecorded_transform="blur"),
            lambda m: m["configuration"].pop("fill_factor"),
            lambda m: m["configuration"].update(optional_noise=0),
            lambda m: m["geometry"].update(active_sensor="different"),
            lambda m: m["input_grid"].update(interpolation="nearest"),
            lambda m: m["runtime"].update(host="extra"),
            lambda m: m["provenance"].update(clean=True),
            lambda m: m["files"]["expected_electrons"].update(offset=8),
        )
        for index, mutation in enumerate(mutations):
            with self.subTest(field=index):
                self.rejects_metadata(mutation, "unknown|incomplete|Incomplete")

    def test_spectral_bins_qe_and_explicit_cube_association_are_validated(self):
        cases = (
            (dict(wavelength_nm=[600, 500]), "Unordered"),
            (dict(wavelength_nm=[500, 501]), "overlapping"),
            (dict(bin_width_nm=[2]), "Spectral shape"),
            (dict(qe=[[.5, .5, .5]]), "QE spectrum"),
            (dict(qe=[[.25, .5, 2], [.5, .75, 1]]), "QE"),
            (dict(wavelength_nm=[500], bin_width_nm=[2], qe=[.25, .5, .75]), "shape association"),
        )
        for change, message in cases:
            with self.subTest(change=change):
                self.rejects_metadata(lambda m, c=change: m["configuration"].update(c), message)

    def test_geometry_binding_rejects_wrong_cfa_size_pitch_and_roi(self):
        for field, value in (("cfa_pattern", "RGGB"), ("image_size", [2, 1]), ("pixel_pitch_m", 2)):
            self.rejects_metadata(lambda m, f=field, v=value: m["configuration"].update({f: v}),
                                  "bound to geometry/CFA")
        self.rejects_metadata(lambda m: m["geometry"].update(active_roi=[3, 4, 1, 2]),
                              "ROI extends outside")
        self.rejects_metadata(lambda m: m["geometry"].update(active_roi=[1, 2, 1, 2]),
                              "bound to geometry/CFA")
        self.rejects_metadata(lambda m: m["geometry"].update(origin_xy_m=[1e20, 0]),
                              "cannot resolve")

    def test_one_ulp_support_gap_is_not_snapped_or_renormalized(self):
        directory = self.root / "identity"
        make_identity_bundle(directory, stage="post_optics")

        def shift_left(meta):
            for name in ("input_grid", "optical_grid"):
                meta[name]["x_edges_m"][0] = math.nextafter(0.0, math.inf)

        self.rejects_metadata(shift_left, "cover every complete photosite", directory=directory)

    def test_grid_requires_finite_increasing_cell_average_metres(self):
        cases = (
            (lambda m: m["input_grid"].update(sample_semantics="point_samples"), "semantics"),
            (lambda m: m["input_grid"].update(units="mm"), "units"),
            (lambda m: m["input_grid"].update(x_edges_m=[0, 1.5, 1.5, 4]), "increasing"),
            (lambda m: m["input_grid"].update(y_edges_m=[0]), "edge vector"),
        )
        for mutation, message in cases:
            self.rejects_metadata(mutation, message)

    def test_psf_sampling_origin_boundary_and_spectral_order_are_explicit(self):
        directory = self.root / "psf"
        make_psf_bundle(directory)
        cases = (
            (dict(origin_rc=[2, 2]), "origin crop"),
            (dict(origin_rc=[1.5, 2]), "identify a coefficient"),
            (dict(origin_rc=[0, 2]), "identify a coefficient"),
            (dict(origin_rc=[True, 2]), "boolean"),
            (dict(spacing_yx_m=[.5, 1]), "match its spacing"),
            (dict(boundary_policy="same"), "boundary policy"),
            (dict(wavelength_nm=[600, 500]), "spectral association"),
            (dict(wavelength_nm=[]), "shared PSF"),
        )
        for change, message in cases:
            with self.subTest(change=change):
                self.rejects_metadata(lambda m, c=change: m["psf"].update(c), message, directory=directory)
        self.rejects_metadata(lambda m: m["input_grid"]["x_edges_m"].__setitem__(1, .75),
                              "uniform", directory=directory)

    def test_missing_psf_halo_cannot_be_renormalized_to_cover_the_sensor(self):
        directory = self.root / "missing-halo"
        make_psf_bundle(directory)
        manifest = directory / "spatial.json"
        meta = json.loads(manifest.read_bytes())
        meta["input_grid"]["y_edges_m"] = [0, 1, 2]
        meta["optical_grid"]["y_edges_m"] = [1, 2]
        # Remove the final source row in each plane and its unsupported final
        # optical row. These remaining optical values are still the correct
        # valid convolution; only complete photosite coverage is now missing.
        changes = (
            ("input_irradiance", [2, 4, 2], (0, 8, 12, 20)),
            ("optical_irradiance", [1, 2, 2], (0, 2, 4, 6)),
        )
        for key, dimensions, (a, b, c, d) in changes:
            record = meta["files"][key]
            path = directory / record["name"]
            original = path.read_bytes()
            content = original[8 * a:8 * b] + original[8 * c:8 * d]
            path.write_bytes(content)
            record.update(shape=dimensions, byte_count=len(content),
                          sha256=hashlib.sha256(content).hexdigest())
        write_json(manifest, meta)
        with self.assertRaisesRegex(verifier.ArtifactError, "cover every complete photosite footprint"):
            verifier.verify_bundle(directory)

    def test_weighted_sampling_and_psf_reject_subnormal_support(self):
        tiny = struct.pack("<d", math.ulp(0.0))
        # Preserve post-optics equality to reach the overlap restriction.
        originals = {name: (self.bundle / name).read_bytes()
                     for name in ("spatial.json", "input.f64", "optical.f64")}
        try:
            for key, name in (("input_irradiance", "input.f64"), ("optical_irradiance", "optical.f64")):
                (self.bundle / name).write_bytes(tiny + originals[name][8:])
                refresh_descriptor(self.bundle, key)
            with self.assertRaisesRegex(verifier.ArtifactError, "Weighted sampling.*subnormal"):
                verifier.verify_bundle(self.bundle)
        finally:
            for name, content in originals.items():
                (self.bundle / name).write_bytes(content)
        directory = self.root / "psf"
        make_psf_bundle(directory)
        self.rejects_payload("input_irradiance", lambda b: tiny + b[8:],
                             "Weighted PSF.*subnormal", directory=directory)

    def test_operation_order_and_stage_cannot_imply_a_second_optical_pass(self):
        self.rejects_metadata(lambda m: m.update(psf={}), "must not carry a PSF")
        self.rejects_metadata(lambda m: m["operation_order"].update(step001="spectral_integration", step002="area_overlap_average"),
                              "stage/order")
        self.rejects_metadata(lambda m: m.update(input_stage="pre_psf"), "stage/order")
        self.rejects_metadata(lambda m: m["operation_order"].update(step004="optical_psf"), "stage/order")

    def test_keyed_lists_reject_gaps_foreign_keys_duplicates_and_empty_values(self):
        lists = ({}, {"id002": "A"}, {"id001": "A", "foreign": "B"},
                 {"id001": "A", "id002": "A"}, {"id001": ""}, {"id001": "../A"})
        for value in lists:
            with self.subTest(value=value):
                self.rejects_metadata(lambda m, v=value: m["geometry"].update(parameter_sources=v),
                                      "geometry sources")
        self.rejects_metadata(lambda m: m["operation_order"].pop("step002"), "operation order")
        # Key enumeration order does not define numerical order.
        meta = json.loads((self.bundle / "spatial.json").read_bytes())
        meta["operation_order"] = dict(reversed(list(meta["operation_order"].items())))
        write_json(self.bundle / "spatial.json", meta)
        verifier.verify_bundle(self.bundle)

    def test_informational_metadata_rejects_undocumented_cell_lists(self):
        for value in (None, ["A", "B"], [{"source": "A"}], [[1], [2, 3]], [True, False],
                      [1, [2]], [[1], True], [[]], [[], []], [[[]]]):
            with self.subTest(value=value):
                self.rejects_metadata(lambda m, v=value: m.update(spatial_provenance={"untyped": v}),
                                      "Unsupported")
        meta = json.loads((self.bundle / "spatial.json").read_bytes())
        meta["spatial_provenance"] = {"empty": [], "column": [[1], [2]]}
        write_json(self.bundle / "spatial.json", meta)
        verifier.verify_bundle(self.bundle)

    def test_informational_keys_require_portable_identifiers(self):
        for key in ("bad-key", "1field", "_field", "field space", "caf\u00e9", "for", "spmd",
                    "endfor", "endarguments", "endspmd", "do", "a" * 64, "field\n", "\0", "\ud800"):
            with self.subTest(key=key):
                self.rejects_metadata(lambda m, k=key: m.update(spatial_provenance={k: 1}),
                                      "portable field spelling")
        # The bound is inclusive, underscores/digits after the first letter
        # are allowed, and keyword matching must remain case-sensitive.
        meta = json.loads((self.bundle / "spatial.json").read_bytes())
        meta["spatial_provenance"] = {
            "a" * 63: 1, "A0_": 2, "For": 3, "for_": 4,
            "enumeration": 5, "events": 6, "methods": 7, "properties": 8,
        }
        write_json(self.bundle / "spatial.json", meta)
        verifier.verify_bundle(self.bundle)

    def test_informational_object_field_count_has_native_boundary(self):
        meta = json.loads((self.bundle / "spatial.json").read_bytes())
        meta["spatial_provenance"] = {f"field{i:03d}": i for i in range(256)}
        write_json(self.bundle / "spatial.json", meta)
        verifier.verify_bundle(self.bundle)
        self.rejects_metadata(lambda m: m["spatial_provenance"].update(field256=256),
                              "256-field bound")

    def test_json_depth_counts_every_object_and_array(self):
        for leaf, leaf_depth in ((0, 0), ([1, 2], 1), ([[1, 2], [3, 4]], 2)):
            with self.subTest(leaf_depth=leaf_depth):
                info = leaf
                # One outer manifest + these dictionaries + the terminal
                # numeric vector/matrix containers is exactly 64.
                for _ in range(63 - leaf_depth):
                    info = {"child": info}
                meta = json.loads((self.bundle / "spatial.json").read_bytes())
                meta["spatial_provenance"] = info
                write_json(self.bundle / "spatial.json", meta)
                verifier.verify_bundle(self.bundle)
                self.rejects_metadata(lambda m, v=info: m.update(spatial_provenance={"child": v}),
                                      "nesting exceeds 64 containers")

    def test_nested_readout_uses_same_portable_key_rules(self):
        self.rejects_metadata(lambda m: m.update({"bad-key": 1}),
                              "portable field spelling", nested=True)

    def test_descriptor_names_types_units_and_hash_syntax_are_fixed(self):
        for name in ("../outside.f64", "/tmp/outside.f64", "alternate.f64", "C:input.f64"):
            self.rejects_metadata(lambda m, n=name: m["files"]["input_irradiance"].update(name=n),
                                  "basename/type/units")
        for change, message in ((dict(sample_type="float32"), "basename/type/units"),
                                 (dict(units="photons"), "basename/type/units"),
                                 (dict(sha256="A" * 64), "invalid SHA-256"),
                                 (dict(byte_count=1), "byte count")):
            self.rejects_metadata(lambda m, c=change: m["files"]["input_irradiance"].update(c), message)
        self.rejects_metadata(lambda m: m["files"]["readout_metadata"].update(shape=[1]), "shape=\\[\\]")

    def test_exact_inventory_rejects_missing_extra_and_mode_conflicting_files(self):
        self.rejects_metadata(lambda m: m["files"].pop("expected_electrons"), "file associations")
        self.rejects_metadata(lambda m: m["files"].update(high_raw=m["files"]["raw"]), "file associations")
        extra = self.bundle / "unlisted.bin"
        extra.write_bytes(b"unlisted")
        with self.assertRaisesRegex(verifier.ArtifactError, "missing or extra"):
            verifier.verify_bundle(self.bundle)
        extra.unlink()
        missing = self.bundle / "readout.raw"
        saved = missing.read_bytes()
        missing.unlink()
        with self.assertRaisesRegex(verifier.ArtifactError, "missing or extra"):
            verifier.verify_bundle(self.bundle)
        missing.write_bytes(saved)

    def test_payload_lengths_reject_truncation_and_trailing_bytes_even_when_rehashed(self):
        for key in ("input_irradiance", "optical_irradiance", "sampled_irradiance", "expected_electrons", "raw"):
            for kind, mutate in (("truncated", lambda b: b[:-1]), ("trailing", lambda b: b + b"\0")):
                with self.subTest(key=key, kind=kind):
                    self.rejects_payload(key, mutate, "truncated payload|Oversized artifact")
        directory = self.root / "dual"
        make_overlap_bundle(directory, mode="dual")
        for key in ("high_raw", "low_raw", "merged_electrons", "flags"):
            self.rejects_payload(key, lambda b: b + b"\0", "Oversized artifact", directory=directory)
        self.rejects_payload("readout_metadata", lambda b: b + b" ", "Oversized artifact")

    def test_big_endian_bytes_cannot_masquerade_as_little_endian_data(self):
        self.rejects_payload("sampled_irradiance", lambda _: struct.pack(">4d", 30, 35, 60, 70),
                             "Subnormal weighted sampled output|rectangular overlap average")
        self.rejects_payload("raw", lambda _: struct.pack(">2H", 100, 97), "ADC range")

    def test_symlink_payload_manifest_and_bundle_directories_reject(self):
        for name in ("input.f64", "spatial.json"):
            with self.subTest(name=name):
                target = self.bundle / name
                saved = self.root / ("saved-" + name)
                target.rename(saved)
                target.symlink_to(saved)
                try:
                    with self.assertRaisesRegex(verifier.ArtifactError, "regular non-symlink"):
                        verifier.verify_bundle(self.bundle)
                finally:
                    target.unlink()
                    saved.rename(target)
        alias = self.root / "bundle-alias"
        alias.symlink_to(self.bundle, target_is_directory=True)
        with self.assertRaisesRegex(verifier.ArtifactError, "non-symlink directory"):
            verifier.verify_bundle(alias)

    def test_identical_but_hardlinked_payloads_are_not_distinct_artifacts(self):
        target = self.bundle / "optical.f64"
        target.unlink()
        os.link(self.bundle / "input.f64", target)
        # Bytes and both SHA-256s are intentionally still correct.
        with self.assertRaisesRegex(verifier.ArtifactError, "alias each other"):
            verifier.verify_bundle(self.bundle)

    def test_nonregular_payload_is_rejected_without_opening_a_fifo(self):
        target = self.bundle / "sampled.f64"
        target.unlink()
        os.mkfifo(target)
        with self.assertRaisesRegex(verifier.ArtifactError, "regular non-symlink"):
            verifier.verify_bundle(self.bundle)

    def test_authenticity_flags_are_literal_booleans(self):
        for field, value in (("synthetic", 1), ("calibrated_alev4", 0), ("authentic_arriraw", 0)):
            self.rejects_metadata(lambda m, f=field, v=value: m.update({f: v}), "authenticity labels")
        self.rejects_metadata(lambda m: m.update(synthetic=1), "authenticity labels", nested=True)

    def test_unavailable_provenance_is_not_invented_or_accepted_as_expected_revision(self):
        for name in ("spatial.json", "readout.json"):
            path = self.bundle / name
            meta = json.loads(path.read_bytes())
            for key in ("repository_head", "isetcam_head", "isethdrsensor_head"):
                meta["provenance"][key] = ""
            write_json(path, meta)
        refresh_descriptor(self.bundle, "readout_metadata", length=True)
        bundle = verifier.verify_bundle(self.bundle)
        self.assertEqual(bundle["source"]["repository_head"], "")
        with self.assertRaisesRegex(verifier.ArtifactError, "another commit"):
            verifier.verify_bundle(self.bundle, expected_commit="1" * 40)
        with self.assertRaisesRegex(verifier.ArtifactError, "full lowercase SHA"):
            verifier.verify_bundle(self.bundle, expected_commit="1" * 7)

    def test_noisy_bundle_does_not_claim_to_reproduce_unrecorded_noise(self):
        for name, key in (("spatial.json", "configuration"), ("readout.json", "sensor")):
            path = self.bundle / name
            meta = json.loads(path.read_bytes())
            meta[key]["shot_noise"] = True
            write_json(path, meta)
        refresh_descriptor(self.bundle, "readout_metadata", length=True)
        bundle = verifier.verify_bundle(self.bundle)
        self.assertIs(bundle["deterministic_readout_checked"], False)
        self.assertIs(bundle["random_stream_reproduced"], False)


class Phase3NumericalReportTests(unittest.TestCase):
    def setUp(self):
        self.report = make_numerical_report()

    def rejects(self, mutation, message):
        report = deepcopy(self.report)
        mutation(report)
        with self.assertRaisesRegex(verifier.ArtifactError, message):
            verifier.check_numerical_report(report, expected_commit="1" * 40)

    def test_artificial_complete_snapshot_retains_both_prerequisites(self):
        source, engine, groups, previous_groups, checker = verifier.check_numerical_report(
            self.report, expected_commit="1" * 40)
        self.assertEqual(source["repository_head"], "1" * 40)
        self.assertEqual(engine, ("GNU Octave", "9.4.0-artificial-fixture"))
        self.assertEqual((groups, previous_groups), (9, 7))
        self.assertEqual(checker, [[100] * 16 for _ in range(16)])
        self.assertEqual(set(verifier.GATES), set(PHASE3_GATES))
        # MATLAB's scalar struct encoding is supported without weakening count.
        self.report["geometry"]["tests"] = self.report["geometry"]["tests"][0]
        self.assertEqual(verifier.check_numerical_report(self.report)[2], 9)

    def test_false_core_only_and_truthy_numerical_flags_are_not_full_passes(self):
        for change in (dict(phase3_passed=False), dict(status="core_only"),
                       dict(status="failed"), dict(phase3_passed=1),
                       dict(phase2_required=1), dict(phase2_required=False),
                       dict(calibrated_alev4=0), dict(phase=True)):
            with self.subTest(change=change):
                self.rejects(lambda r, c=change: r.update(c), "Phase 3|phase")
        self.rejects(lambda r: r.pop("phase2_required"), "Phase 3")

    def test_every_phase3_suite_must_be_present_and_explicitly_passed(self):
        for name in PHASE3_GATES:
            for change in ("missing", "false", "numeric_true", "failed"):
                with self.subTest(name=name, change=change):
                    def mutate(report, n=name, c=change):
                        if c == "missing":
                            report.pop(n)
                        else:
                            report[n].update({"status": "failed"} if c == "failed" else
                                             {"passed": 1 if c == "numeric_true" else False})
                    self.rejects(mutate, name)

    def test_suite_counts_and_individual_test_flags_are_not_trusted(self):
        for value in (0, 2, True, 1.5):
            self.rejects(lambda r, v=value: r["geometry"].update(test_count=v), "geometry")
        for change in (dict(passed=False), dict(passed=1), dict(status="failed"), dict(name=" ")):
            self.rejects(lambda r, c=change: r["geometry"]["tests"][0].update(c), "geometry")
        self.rejects(lambda r: r["geometry"].update(test_count=2, tests=r["geometry"]["tests"] * 2),
                     "duplicate test group")

    def test_phase2_and_phase1_prerequisites_cannot_be_skipped_or_core_only(self):
        self.rejects(lambda r: r.pop("phase2"), "Phase 2 prerequisite")
        self.rejects(lambda r: r["phase2"].pop("phase1"), "Phase 1 prerequisite")
        for change in (dict(phase2_passed=False), dict(status="core_only"),
                       dict(phase1_required=False), dict(phase1_required=1), dict(phase2_passed=1)):
            self.rejects(lambda r, c=change: r["phase2"].update(c), "Phase 2 prerequisite")
        for change in (dict(phase1_passed=False), dict(status="failed"), dict(phase1_passed=1)):
            self.rejects(lambda r, c=change: r["phase2"]["phase1"].update(c), "Phase 1 prerequisite")

    def test_all_preserved_phase2_and_phase1_suites_are_required(self):
        for name in PHASE2_GATES:
            with self.subTest(phase=2, name=name):
                self.rejects(lambda r, n=name: r["phase2"].pop(n), name)
        for name in PHASE1_GATES:
            with self.subTest(phase=1, name=name):
                self.rejects(lambda r, n=name: r["phase2"]["phase1"].pop(n), name)
        for name in ("first_exposure", "second_exposure"):
            self.rejects(lambda r, n=name: r["phase2"]["phase1"]["iset"].pop(n), "genuine ISET")
        self.rejects(lambda r: r["phase2"]["phase1"]["iset"]["second_exposure"].update(relative_tolerance=.1),
                     "ISET tolerance")

    def test_source_revision_frozen_pins_and_prerequisite_runtime_must_agree(self):
        self.rejects(lambda r: r["provenance"].update(repository_head="2" * 40), "another commit")
        self.rejects(lambda r: r["provenance"].update(isetcam_head="2" * 40), "frozen dependency pins")
        self.rejects(lambda r: r["provenance"].update(repository_head=""), "observed repository_head")
        self.rejects(lambda r: r["phase2"]["provenance"].update(repository_head="2" * 40), "Phase 2.*differs")
        self.rejects(lambda r: r["phase2"]["phase1"].update(runtime_version="different"), "Phase 1.*differs")
        with self.assertRaisesRegex(verifier.ArtifactError, "full lowercase SHA"):
            verifier.check_numerical_report(self.report, expected_commit="F" * 40)

    def test_iset_requires_four_fixtures_and_typed_execution_flags(self):
        fixtures = lambda r: r["iset_spatial"]["metrics"]["fixtures"]
        for name in ("uniform", "ramp", "checker", "edge"):
            self.rejects(lambda r, n=name: fixtures(r).pop(n), "required genuine ISET fixtures")
        for field, value in (("synthetic", 1), ("calibrated_alev4", 0),
                             ("native_matlab_executed", 0), ("native_matlab_executed", True)):
            self.rejects(lambda r, f=field, v=value: r["iset_spatial"]["metrics"].update({f: v}),
                         "execution/runtime labels")
        self.rejects(lambda r: fixtures(r)["checker"].update(extra_psf_applied=0), "metadata/provenance")
        self.rejects(lambda r: fixtures(r)["checker"]["provenance"].update(repository_head="2" * 40),
                     "metadata/provenance")

    def test_iset_retained_matrices_recompute_error_instead_of_trusting_report(self):
        fixture = lambda r: r["iset_spatial"]["metrics"]["fixtures"]["checker"]
        self.rejects(lambda r: fixture(r)["native_expected_electrons"][0].__setitem__(0, 100.001),
                     "reported native error disagrees")
        self.rejects(lambda r: fixture(r)["native_expected_electrons"][0].__setitem__(0, 101),
                     "native quadrature exceeds")
        self.rejects(lambda r: fixture(r).update(reference_expected_electrons=[[100] * 16]),
                     "wrong matrix shape")
        self.rejects(lambda r: fixture(r)["reference_expected_electrons"][0].__setitem__(0, True), "boolean")
        self.rejects(lambda r: fixture(r)["reference_expected_electrons"][0].__setitem__(0, 0), "illuminated")
        self.rejects(lambda r: fixture(r).update(project_relative_error=1e-6), "project integration")
        self.rejects(lambda r: fixture(r).update(native_relative_error=1e-6), "reported native error")

    def test_refinement_sequences_require_numeric_counts_and_measured_convergence(self):
        fixture = lambda r: r["iset_spatial"]["metrics"]["fixtures"]["checker"]
        for key in ("native_samples_per_axis", "source_refinement_factors"):
            with self.subTest(key=key):
                self.rejects(lambda r, k=key: fixture(r)[k].__setitem__(0, True), "boolean|refinement")
                self.rejects(lambda r, k=key: fixture(r)[k].__setitem__(-1, 100), "refinement sequences")
        self.rejects(lambda r: fixture(r).update(native_relative_errors=[0, 0, 0, 0]),
                     "coarse controls/refinement")
        self.rejects(lambda r: fixture(r).update(source_refinement_relative_errors=[.02] * 5),
                     "coarse controls/refinement")
        self.rejects(lambda r: fixture(r).update(native_relative_errors=[.02, -.001, .0002, 0]),
                     "Negative ISET refinement")
        self.rejects(lambda r: fixture(r).update(native_spacing_yx_m=[1e-6, 1e-6]), "hidden prefilter")

    def test_uniform_and_nonuniform_iset_controls_cannot_be_swapped(self):
        self.rejects(lambda r: r["iset_spatial"]["metrics"]["fixtures"]["uniform"].update(oi_spatial_variation=.2),
                     "uniform/nonuniform control")
        self.rejects(lambda r: r["iset_spatial"]["metrics"]["fixtures"]["edge"].update(oi_spatial_variation=0),
                     "uniform/nonuniform control")


class Phase3ReleaseEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temporary = tempfile.TemporaryDirectory(prefix="phase3-evidence-source-")
        cls.addClassCleanup(temporary.cleanup)
        cls.fixture = Path(temporary.name) / "artificial"
        make_outputs(cls.fixture)

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="phase3-evidence-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "output"
        shutil.copytree(self.fixture, self.root)
        self.demo = self.root / "demo"
        self.report = self.root / "validation/phase3-validation.json"
        self.summary = self.demo / "phase3-demo-summary.json"

    def rejects_json(self, path, mutation, message):
        original = path.read_bytes()
        try:
            value = json.loads(original)
            mutation(value)
            write_json(path, value)
            with self.assertRaisesRegex(verifier.ArtifactError, message):
                verifier.verify_outputs(self.root, expected_commit="1" * 40)
        finally:
            path.write_bytes(original)

    def test_complete_artificial_receipt_hashes_all_bytes_and_states_its_boundary(self):
        result = verifier.verify_outputs(self.root, expected_commit="1" * 40)
        self.assertEqual((result["frame_count"], result["artifact_count"]), (8, 66))
        self.assertEqual((result["numerical_test_groups"], result["phase2_numerical_test_groups"]), (9, 7))
        self.assertEqual(set(result["frames"]), set(DEMO_NAMES))
        self.assertEqual(len(result["artifact_sha256"]), 66)
        for name, digest in result["artifact_sha256"].items():
            self.assertEqual(digest, hashlib.sha256((self.demo / name).read_bytes()).hexdigest())
        self.assertEqual(result["numerical_report_sha256"], hashlib.sha256(self.report.read_bytes()).hexdigest())
        for flag in ("compared_demo_byte_identical", "input_source_authenticated",
                     "random_stream_reproduced", "iset_native_source_recomputed_in_python", "calibrated_alev4"):
            self.assertIs(result[flag], False)
        for flag in ("phase2_and_phase1_prerequisites_checked", "iset_numerical_evidence_checked",
                     "general_format_checked", "demo_fixtures_checked"):
            self.assertIs(result[flag], True)
        self.assertIs(result["frames"]["dual_spatial"]["deterministic_readout_checked"], False)
        self.assertIs(result["frames"]["iset_checker"]["iset_numerical_reference_checked"], True)

    def test_iset_demo_cannot_hide_nonportable_informational_keys(self):
        self.rejects_json(self.demo / "iset_checker" / "spatial.json",
                          lambda m: m["spatial_provenance"].update({"bad-key": 1}),
                          "portable field spelling")

    def test_distinct_byte_identical_repeat_passes(self):
        repeat = self.root / "repeat"
        shutil.copytree(self.demo, repeat)
        result = verifier.verify_outputs(self.root, repeat, expected_commit="1" * 40)
        self.assertIs(result["compared_demo_byte_identical"], True)
        # Exact byte repetition is stronger than re-parsed semantic equality.
        with (repeat / "phase3-demo-summary.json").open("ab") as handle:
            handle.write(b"\n")
        with self.assertRaisesRegex(verifier.ArtifactError, "not byte-identical"):
            verifier.verify_outputs(self.root, repeat)

    def test_repeat_cannot_be_same_resolved_directory_or_symlink(self):
        for path in (self.demo, self.demo / ".", self.demo / ".." / "demo"):
            with self.subTest(path=str(path)):
                with self.assertRaisesRegex(verifier.ArtifactError, "distinct resolved demo"):
                    verifier.verify_outputs(self.root, path)
        alias = self.root / "repeat-link"
        alias.symlink_to(self.demo, target_is_directory=True)
        with self.assertRaisesRegex(verifier.ArtifactError, "non-symlink directory"):
            verifier.verify_outputs(self.root, alias)

    def test_hardlinked_repeat_is_not_an_independent_artifact_set(self):
        repeat = self.root / "repeat"
        shutil.copytree(self.demo, repeat, copy_function=os.link)
        with self.assertRaisesRegex(verifier.ArtifactError, "Repeated demo aliases"):
            verifier.verify_outputs(self.root, repeat)

    def test_cross_filename_alias_is_rejected_even_with_equal_legal_bytes(self):
        repeat = self.root / "repeat"
        shutil.copytree(self.demo, repeat)
        alias = repeat / "identity_single/optical.f64"
        alias.unlink()
        os.link(self.demo / "identity_single/input.f64", alias)
        with self.assertRaisesRegex(verifier.ArtifactError, "cross-filename aliases"):
            verifier.verify_outputs(self.root, repeat)

    def test_cross_bundle_alias_is_rejected_after_individual_bundles_pass(self):
        # Both analytic fixtures have precisely the same 3x3 PSF bytes.
        source = self.demo / "flat_binomial/psf.f64"
        target = self.demo / "edge/psf.f64"
        self.assertEqual(source.read_bytes(), target.read_bytes())
        target.unlink()
        os.link(source, target)
        verifier.verify_bundle(self.demo / "flat_binomial")
        verifier.verify_bundle(self.demo / "edge")
        with self.assertRaisesRegex(verifier.ArtifactError, "aliased across bundles"):
            verifier.verify_outputs(self.root)

    def test_repeat_completion_false_cannot_be_claimed_as_a_success(self):
        repeat = self.root / "repeat"
        shutil.copytree(self.demo, repeat)
        path = repeat / "phase3-demo-summary.json"
        summary = json.loads(path.read_bytes())
        summary["demo_complete"] = False
        write_json(path, summary)
        with self.assertRaisesRegex(verifier.ArtifactError, "Complete eight-fixture"):
            verifier.verify_outputs(self.root, repeat)

    def test_demo_summary_statistics_are_recomputed(self):
        for key in ("minimum_expected_e", "maximum_expected_e", "sum_expected_e"):
            self.rejects_json(self.summary,
                              lambda s, k=key: s["frames"][0].update({k: s["frames"][0][k] + 1}), key)
        self.rejects_json(self.summary, lambda s: s["frames"][0].update(seed=999), "seed/exposure")
        self.rejects_json(self.summary, lambda s: s["frames"][0].update(image_size=[8, 6]), "summary association")

    def test_demo_requires_complete_fixed_inventory_and_typed_flags(self):
        for change in (dict(demo_complete=1), dict(iset_included=False),
                       dict(synthetic=1), dict(calibrated_alev4=0)):
            self.rejects_json(self.summary, lambda s, c=change: s.update(c), "Complete eight-fixture")
        self.rejects_json(self.summary, lambda s: s.update(frame_count=True), "boolean")
        self.rejects_json(self.summary, lambda s: s["frames"].reverse(), "inventory/order")
        self.rejects_json(self.summary, lambda s: s["frames"][0].update(name="unrecorded"), "inventory/order")
        (self.demo / "unexpected.txt").write_text("extra", encoding="utf-8")
        with self.assertRaisesRegex(verifier.ArtifactError, "missing or extra entries"):
            verifier.verify_outputs(self.root)

    def test_failed_core_only_or_missing_prerequisite_report_blocks_release(self):
        self.rejects_json(self.report, lambda r: r.update(status="core_only", phase3_passed=False), "Phase 3")
        self.rejects_json(self.report, lambda r: r.pop("phase2"), "Phase 2 prerequisite")
        self.rejects_json(self.report, lambda r: r["phase2"].pop("phase1"), "Phase 1 prerequisite")
        self.rejects_json(self.report, lambda r: r["spatial_io"].update(passed=False), "spatial_io")

    def test_changed_sha_and_report_demo_source_association_fail_release(self):
        with self.assertRaisesRegex(verifier.ArtifactError, "another commit"):
            verifier.verify_outputs(self.root, expected_commit="2" * 40)
        self.rejects_json(self.summary, lambda s: s["provenance"].update(repository_head="2" * 40),
                          "source/runtime differs")
        self.rejects_json(self.report, lambda r: r["provenance"].update(isethdrsensor_head="2" * 40),
                          "frozen dependency pins")

    def test_numerical_report_checksum_identifies_exact_report_bytes(self):
        before = verifier.verify_outputs(self.root)
        with self.report.open("ab") as handle:
            handle.write(b"\n")
        after = verifier.verify_outputs(self.root)
        self.assertNotEqual(before["numerical_report_sha256"], after["numerical_report_sha256"])
        self.assertEqual(after["numerical_report_sha256"], hashlib.sha256(self.report.read_bytes()).hexdigest())
        self.assertEqual(before["artifact_sha256"], after["artifact_sha256"])

    def test_iset_demo_must_agree_with_retained_numerical_reference(self):
        # Change native and reference matrices together so their reported native
        # error stays genuinely zero. Only the demo/reference association fails.
        def mutate(report):
            fixture = report["iset_spatial"]["metrics"]["fixtures"]["checker"]
            for field in ("reference_expected_electrons", "native_expected_electrons"):
                fixture[field][0][0] += 1
        self.rejects_json(self.report, mutate, "numerical scalar bilinear reference")

    def test_cli_returns_only_successful_receipt_and_reports_failed_gate(self):
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            status = verifier.main([str(self.root), "--expected-commit", SOURCE["repository_head"]])
        self.assertEqual(status, 0)
        self.assertEqual(stderr.getvalue(), "")
        receipt = json.loads(stdout.getvalue())
        self.assertEqual(receipt["artifact_count"], 66)
        self.assertIs(receipt["compared_demo_byte_identical"], False)
        report = json.loads(self.report.read_bytes())
        report["phase3_passed"] = False
        write_json(self.report, report)
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            status = verifier.main([str(self.root)])
        self.assertEqual(status, 1)
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("FAIL:", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
