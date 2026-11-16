"""Independent, Python-only Phase 4 packed-artifact corruption controls.

All bundles are temporary handwritten fixtures. These tests need neither an
Octave executable nor ignored producer outputs, so earlier-phase CI can run
them before installing a numerical runtime. Repeat-layer tests mock only the
unrelated full-demo/report readers and exercise actual independent files.
"""
from contextlib import contextmanager
from copy import deepcopy
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import struct
import tempfile
import unittest
from unittest import mock

from phase4_fixture_support import (
    ACTIVE_DARK, ACTIVE_PRNU, ACTIVE_SHARED, BASELINE, CUBE, ENGINE, INCIDENT,
    SOURCE, Cells, Characters, make_result, make_spatial_result, numbers,
    refresh_hash, replace_samples, tree_node, write_bundle, write_json,
)


SPEC = importlib.util.spec_from_file_location(
    "phase4_artifacts", Path(__file__).resolve().parents[1] / "verify_phase4_artifacts.py")
verifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verifier)


def field(value, path):
    for key in path.split("."):
        value = value[key]
    return value


def assign(value, path, replacement):
    parent, _, key = path.rpartition(".")
    (field(value, parent) if parent else value)[key] = replacement


class FixtureCase(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="phase4-python-fixture-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.bundle = self.root / "bundle"
        self.result = make_result()
        write_bundle(self.bundle, self.result)

    @contextmanager
    def restore_bundle(self):
        paths = [self.bundle / "structured.json", self.bundle / "data.bin"]
        contents = [path.read_bytes() for path in paths]
        try:
            yield
        finally:
            for path, content in zip(paths, contents):
                path.write_bytes(content)

    def rejects_manifest(self, mutation, message):
        with self.restore_bundle():
            path = self.bundle / "structured.json"
            metadata = json.loads(path.read_bytes())
            mutation(metadata)
            write_json(path, metadata)
            with self.assertRaisesRegex(verifier.ArtifactError, message):
                verifier.verify_bundle(self.bundle)

    def rejects_result(self, mutation, message, *, result=None):
        with self.restore_bundle():
            modified = deepcopy(self.result if result is None else result)
            mutation(modified)
            write_bundle(self.bundle, modified)
            with self.assertRaisesRegex(verifier.ArtifactError, message):
                verifier.verify_bundle(self.bundle)

    def rejects_samples(self, path, values, message, *, rehash=True):
        with self.restore_bundle():
            replace_samples(self.bundle, path, values, rehash=rehash)
            with self.assertRaisesRegex(verifier.ArtifactError, message):
                verifier.verify_bundle(self.bundle)

    def rejects_json_bytes(self, content, message):
        with self.restore_bundle():
            (self.bundle / "structured.json").write_bytes(content)
            with self.assertRaisesRegex(verifier.ArtifactError, message):
                verifier.verify_bundle(self.bundle)


class Phase4IndependentAnswersTests(FixtureCase):
    def test_single_cube_maps_charge_and_adc_have_literal_answers(self):
        bundle = verifier.verify_bundle(self.bundle, expected_commit="1" * 40)
        result, readout = bundle["result"], bundle["result"]["readout"]
        self.assertEqual(list(result["input_irradiance"]), CUBE)
        self.assertEqual(result["input_irradiance"].shape, (2, 3, 2))
        self.assertEqual(result["input_irradiance"].class_name, "double")
        self.assertEqual(list(result["baseline_expected_electrons"]), [4.25, 5, 12.75, 10, 10, 15])
        self.assertEqual(list(readout["expected_incident_photons"]), [5, 10, 15, 20, 25, 30])
        self.assertEqual(list(result["active_maps"]["prnu"]), [1, .5, 2, 1.5, 0, 1])
        self.assertEqual(list(result["active_maps"]["dark_current_e_per_s"]), [0, 2, 4, 6, 8, 10])
        self.assertEqual(list(readout["expected_photoelectrons"]), [4.25, 2.5, 25.5, 15, 0, 15])
        self.assertEqual(list(readout["expected_dark_electrons"]), [0, 1, 2, 3, 4, 5])
        self.assertEqual(list(readout["expected_electrons"]), [4.25, 3.5, 27.5, 18, 4, 20])
        self.assertEqual(list(readout["charge_electrons"]), [4.25, 3.5, 20, 18, 4, 20])
        self.assertEqual(list(readout["read_electrons"]), [-5.5, 8.5, 21.25, 20.25, -3.75, 19.75])
        self.assertEqual(list(readout["raw_dn"]), [0, 20, 31, 31, 0, 31])
        self.assertEqual(list(readout["full_well_saturated"]), [0, 0, 1, 0, 0, 1])
        self.assertEqual(list(readout["adc_low_clipped"]), [1, 0, 0, 0, 1, 0])
        self.assertEqual(list(readout["adc_high_clipped"]), [0, 0, 1, 1, 0, 1])
        self.assertEqual(list(readout["reconstruction_valid"]), [0, 1, 0, 0, 0, 0])
        self.assertEqual(bundle["sensor"]["cfa_pattern"], "BGGR")
        self.assertEqual(bundle["runtime"], (ENGINE["name"], ENGINE["version"]))
        self.assertEqual(bundle["source"]["repository_head"], "1" * 40)
        self.assertEqual(len(bundle["files"]), 2)
        self.assertIs(bundle["general_format_checked"], True)
        self.assertIs(bundle["deterministic_arithmetic_checked"], True)
        self.assertIs(bundle["spatial_arithmetic_checked"], False)
        self.assertIs(bundle["random_stream_reproduced"], False)
        self.assertIs(bundle["input_source_authenticated"], False)

    def test_true_c_order_native_classes_shapes_offsets_and_little_endian_bytes(self):
        bundle = verifier.verify_bundle(self.bundle)
        content = (self.bundle / "data.bin").read_bytes()
        cube = bundle["result"]["input_irradiance"]
        self.assertEqual(content[cube.offset:cube.offset + 96], struct.pack("<12d", *CUBE))
        raw = bundle["result"]["readout"]["raw_dn"]
        self.assertEqual((raw.class_name, raw.shape, raw.units), ("uint16", (2, 3), "DN"))
        self.assertEqual(content[raw.offset:raw.offset + 12], b"\x00\x00\x14\x00\x1f\x00\x1f\x00\x00\x00\x1f\x00")
        sensor = bundle["result"]["configuration"]
        self.assertEqual(sensor["wavelength_nm"].shape, (2, 1))
        self.assertEqual(sensor["image_size"].shape, (1, 2))
        self.assertEqual(sensor["shot_noise"].class_name, "logical")
        self.assertEqual(sensor["pixel_pitch_m"].shape, (1, 1))
        self.assertEqual(bundle["result"]["operation_order"].shape, (1, 11))
        offsets, sample_counts = [], []

        def visit(node):
            if node["kind"] == "numeric":
                offsets.append((node["offset"], node["byte_count"]))
                sample_counts.append(math.prod(node["shape"]))
            elif node["kind"] in ("struct", "cell"):
                for child in node["fields" if node["kind"] == "struct" else "items"].values():
                    visit(child)
        visit(bundle["metadata"]["result"])
        cursor = 0
        for offset, size in offsets:
            self.assertEqual(offset, cursor)
            cursor += size
        self.assertEqual(cursor, len(content))
        self.assertEqual(sum(sample_counts), bundle["metadata"]["payload"]["sample_count"])

    def test_dual_shared_well_adc_recovery_and_observed_merge_have_literal_answers(self):
        write_bundle(self.bundle, make_result("dual"))
        bundle = verifier.verify_bundle(self.bundle)
        readout = bundle["result"]["readout"]
        self.assertEqual(list(readout["high_gain"]["raw_dn"]), [0, 43, 63, 63, 0, 63])
        self.assertEqual(list(readout["low_gain"]["raw_dn"]), [2, 16, 29, 28, 4, 27])
        self.assertEqual(list(readout["merged"]["electrons"]), [-6, 8.375, 21, 20, -4, 19])
        self.assertEqual(list(readout["merged"]["weight_high"]), [0, .5, 0, 0, 0, 0])
        self.assertEqual(list(readout["reconstruction_valid"]), [1, 1, 0, 1, 1, 0])
        # Pixel four is high-ADC clipped but physically unsaturated; its low
        # channel recovers a valid observed value. Pixels three/six lose well charge.
        self.assertEqual(list(readout["high_gain"]["adc_high_clipped"]), [0, 0, 1, 1, 0, 1])
        self.assertEqual(list(readout["full_well_saturated"]), [0, 0, 1, 0, 0, 1])

    def test_scalar_uniform_maps_retain_scalar_model_and_expanded_crop(self):
        write_bundle(self.bundle, make_result(scalar_maps=True))
        result = verifier.verify_bundle(self.bundle)["result"]
        for name in ("prnu", "dark_current_e_per_s"):
            self.assertEqual(result["noise_model"][name].shape, (1, 1))
            self.assertEqual(result["active_maps"][name].shape, (2, 3))
        self.assertEqual(list(result["active_maps"]["prnu"]), [1] * 6)
        self.assertEqual(list(result["active_maps"]["dark_current_e_per_s"]), [2] * 6)
        self.assertEqual(list(result["readout"]["expected_electrons"]), [5.25, 6, 13.75, 11, 11, 16])

    def test_zero_exposure_keeps_electronics_but_zeroes_charge(self):
        write_bundle(self.bundle, make_result(zero_exposure=True))
        readout = verifier.verify_bundle(self.bundle)["result"]["readout"]
        for name in ("expected_electrons", "expected_incident_photons", "collected_electrons", "charge_electrons"):
            self.assertEqual(list(readout[name]), [0] * 6)
        self.assertEqual(list(readout["raw_dn"]), [0, 13, 5, 7, 0, 2])

    def test_seed_wrap_uses_retained_binary64_named_schedule(self):
        seeds = verifier.verify_bundle(self.bundle)["result"]["seeds"]
        self.assertEqual(seeds["frame"][0], 4294967294)
        self.assertEqual(seeds["photo"][0], 4294967295)
        self.assertEqual(seeds["dark"][0], 0)
        self.assertEqual(seeds["low_pixel"][0], 41)
        self.assertEqual((seeds["dark"].class_name, seeds["dark"].units), ("double", "seed"))

    def test_alternative_finite_stochastic_realizations_are_accepted_without_stream_claim(self):
        for mode in ("single", "dual"):
            outputs = []
            for variant in (1, 2):
                with self.subTest(mode=mode, variant=variant):
                    write_bundle(self.bundle, make_result(mode, stochastic=variant))
                    bundle = verifier.verify_bundle(self.bundle)
                    outputs.append(list(bundle["result"]["components"]["photo_electrons"]))
                    self.assertIs(bundle["random_stream_reproduced"], False)
                    self.assertIs(bundle["deterministic_arithmetic_checked"], True)
            self.assertNotEqual(*outputs)

    def test_unused_full_map_values_and_signed_zero_remain_retained_data(self):
        modified = deepcopy(self.result)
        modified["noise_model"]["prnu"].values[0] = 7
        modified["noise_model"]["shared"]["fixed_offset_e"].values[0] = -0.0
        write_bundle(self.bundle, modified)
        result = verifier.verify_bundle(self.bundle)["result"]
        self.assertEqual(result["noise_model"]["prnu"][0], 7)
        self.assertEqual(list(result["active_maps"]["prnu"]), ACTIVE_PRNU)
        offset = result["noise_model"]["shared"]["fixed_offset_e"].offset
        self.assertEqual((self.bundle / "data.bin").read_bytes()[offset:offset + 8], b"\0\0\0\0\0\0\0\x80")

    def test_spatial_single_dual_and_pre_post_optics_have_literal_cube_answers(self):
        for mode in ("single", "dual"):
            for stage in ("pre_psf", "post_optics"):
                with self.subTest(mode=mode, stage=stage):
                    write_bundle(self.bundle, make_spatial_result(mode, stage=stage))
                    bundle = verifier.verify_bundle(self.bundle)
                    base = bundle["result"]["spatial_baseline"]
                    self.assertIs(bundle["spatial_arithmetic_checked"], True)
                    self.assertEqual(list(base["optical_irradiance"]), CUBE)
                    self.assertEqual(list(base["sampled_irradiance"]), CUBE)
                    self.assertEqual(list(base["readout"]["expected_electrons"]), BASELINE)
                    self.assertEqual(list(base["sampling_report"]["source_integral"]["values"]), [42, 84])
                    if stage == "pre_psf":
                        self.assertEqual(base["input_irradiance"].shape, (2, 4, 2))
                        self.assertEqual(base["psf"]["kernel"].shape, (1, 2, 2))
                        self.assertEqual(list(base["psf"]["kernel"]), [.5, .25, .5, .75])
                    else:
                        self.assertEqual(base["psf"].shape, (0, 0))
                    if mode == "single":
                        self.assertEqual(list(base["readout"]["raw_dn"]), [11, 13, 28, 23, 23, 31])

    def test_runtime_native_unicode_empty_shapes_and_metadata_units_are_preserved(self):
        for name, units in (("GNU Octave", 6), ("MATLAB", 3)):
            with self.subTest(runtime=name):
                result = make_spatial_result()
                result["runtime"]["name"] = name
                write_bundle(self.bundle, result)
                metadata = verifier.verify_bundle(self.bundle)["result"]["spatial_baseline"]["spatial_provenance"]
                self.assertEqual(metadata["unicode_label"], "μ😀")
                self.assertEqual(metadata["unicode_label"].shape, (1, units))
                self.assertEqual(metadata["empty_row"].shape, (1, 0))
                self.assertEqual(metadata["empty_char"].shape, (0, 0))
                self.assertEqual(metadata["informational_flag"].class_name, "logical")
                self.assertEqual(metadata["informational_flag"].units, "metadata")

    def test_spatial_provenance_supported_typed_values_remain_exact(self):
        result = make_spatial_result(stage="post_optics")
        tiny = float.fromhex("0x0.0000000000001p-1022")
        result["spatial_baseline"]["spatial_provenance"] = dict(
            scalar=-2.5, enabled=True, disabled=False,
            row=numbers([0.0, -0.0, tiny], (1, 3)),
            column=numbers([1, -2, 3], (3, 1)),
            matrix=numbers([1, 2, 3, 4, 5, 6], (2, 3)),
            empty00=numbers([], (0, 0)), empty10=numbers([], (1, 0)),
            empty01=numbers([], (0, 1)), empty20=numbers([], (2, 0)),
            text="metadata μ😀", empty_text=Characters("", (0, 0)),
            nested=dict(empty_struct={}, label="nested", scalar=42, flag=False))
        write_bundle(self.bundle, result)
        metadata = verifier.verify_bundle(self.bundle)["result"]["spatial_baseline"]["spatial_provenance"]
        for name, shape, values in (
                ("scalar", (1, 1), [-2.5]), ("row", (1, 3), [0.0, -0.0, tiny]),
                ("column", (3, 1), [1, -2, 3]), ("matrix", (2, 3), [1, 2, 3, 4, 5, 6]),
                ("empty00", (0, 0), []), ("empty10", (1, 0), []),
                ("empty01", (0, 1), []), ("empty20", (2, 0), [])):
            with self.subTest(name=name):
                self.assertEqual((metadata[name].class_name, metadata[name].shape, metadata[name].units),
                                 ("double", shape, "metadata"))
                self.assertEqual(list(metadata[name]), values)
        self.assertEqual(math.copysign(1, metadata["row"][1]), -1)
        for flag, value in ((metadata["enabled"], 1), (metadata["disabled"], 0),
                            (metadata["nested"]["flag"], 0)):
            self.assertEqual((flag.class_name, flag.shape, list(flag)), ("logical", (1, 1), [value]))
        self.assertEqual(metadata["text"], "metadata μ😀")
        self.assertEqual((metadata["empty_text"], metadata["empty_text"].shape), ("", (0, 0)))
        self.assertEqual(metadata["nested"]["empty_struct"], {})
        self.assertEqual(metadata["nested"]["label"], "nested")
        self.assertEqual(list(metadata["nested"]["scalar"]), [42])


class Phase4WireTests(FixtureCase):
    def test_json_duplicate_and_escaped_duplicate_keys_reject(self):
        original = (self.bundle / "structured.json").read_bytes()
        for fragment in (b'"format":"fake",', b'"f\\u006frmat":"fake",'):
            with self.subTest(fragment=fragment):
                self.rejects_json_bytes(b"{" + fragment + original[1:], "Duplicate JSON")
        self.rejects_json_bytes(original.replace(b'"kind":"numeric"', b'"kind":"numeric","kind":"numeric"', 1), "Duplicate JSON")

    def test_json_nonportable_keys_invalid_utf8_nul_and_surrogates_reject(self):
        original = (self.bundle / "structured.json").read_bytes()
        for prefix, message in ((b'{"bad-key":0,', "portable"), (b'{"for":0,', "portable"),
                                (b'{"x":"\xff",', "Invalid JSON")):
            with self.subTest(prefix=prefix):
                self.rejects_json_bytes(prefix + original[1:], message)
        for value, message in ((b'"\\u0000"', "invalid text"), (b'"\\ud800"', "invalid Unicode")):
            with self.subTest(value=value):
                self.rejects_json_bytes(original.replace(b'"value":"ARTIFICIAL-PYTHON-FIXTURE"',
                    b'"value":' + value, 1), message)

    def test_json_nonfinite_underflow_trailing_and_ambiguous_values_reject(self):
        original = (self.bundle / "structured.json").read_bytes()
        for token in (b"NaN", b"Infinity", b"1e9999", b"1e-9999", b"+1", b"01"):
            with self.subTest(token=token):
                self.rejects_json_bytes(b'{"extra":' + token + b"," + original[1:],
                                        "Nonfinite|underflow|Invalid JSON")
        self.rejects_json_bytes(original + b"{}", "Invalid JSON")

    def test_manifest_actual_size_bound_rejects_before_unbounded_parse(self):
        self.rejects_json_bytes(b" " * 2_000_001, "bound|Oversized")

    def test_exact_manifest_and_node_field_inventories_reject_unknowns(self):
        self.rejects_manifest(lambda m: m.update(extra=0), "manifest: incomplete or unknown fields")
        self.rejects_manifest(lambda m: m["payload"].update(extra=0), "payload descriptor: incomplete or unknown fields")
        for path in ("configuration", "configuration.image_size", "format", "operation_order"):
            with self.subTest(path=path):
                self.rejects_manifest(lambda m, p=path: tree_node(m, p).update(extra=0), "node: incomplete or unknown fields")

    def test_format_order_classification_and_authenticity_literals_are_strict(self):
        for key, value in (("format", "ALEV4-SYNTHETIC-RAW"), ("schema_version", 1),
                           ("wire_version", "typed-tree-v2"), ("byte_order", "big-endian"),
                           ("array_order", "plane-major"), ("parameter_classification", "measured"),
                           ("synthetic", 1), ("authentic_arriraw", 0), ("calibrated_alev4", 0)):
            with self.subTest(key=key):
                self.rejects_manifest(lambda m, k=key, v=value: m.update({k: v}), "format/order|flags")

    def test_payload_basename_and_hash_grammar_are_exact(self):
        for value in ("../data.bin", "./data.bin", "other.bin", ["data.bin"]):
            with self.subTest(name=value):
                self.rejects_manifest(lambda m, v=value: m["payload"].update(name=v), "filename/hash")
        for value in ("0" * 63, "G" * 64, "A" * 64, 0):
            with self.subTest(hash=value):
                self.rejects_manifest(lambda m, v=value: m["payload"].update(sha256=v), "filename/hash")

    def test_payload_count_json_kinds_and_integer_bounds_reject(self):
        for key in ("byte_count", "sample_count"):
            for value in (True, False, "1", [1], None, -1, .5, 800_000_001):
                with self.subTest(key=key, value=value):
                    self.rejects_manifest(lambda m, k=key, v=value: m["payload"].update({k: v}),
                                          "number|integer|range")

    def test_numeric_descriptor_json_kinds_reject(self):
        for key in ("offset", "byte_count"):
            for value in (True, "0", [0], None, -.5, .5):
                with self.subTest(key=key, value=value):
                    self.rejects_manifest(lambda m, k=key, v=value: tree_node(m, "configuration.image_size").update({k: v}),
                                          "number|integer|range")
        for dimension in (True, "2", None, [2], .5, -1):
            with self.subTest(dimension=dimension):
                self.rejects_manifest(lambda m, d=dimension: tree_node(m, "configuration.image_size").update(shape=[1, d]),
                                      "number|integer|range")

    def test_shape_rank_trailing_singleton_and_empty_positive_extent_bound_reject(self):
        for shape in ([2], [1, 1, 1, 2], [2, 3, 1], [0, 100_000_000, 100_000_000], [0, 100_000_001]):
            with self.subTest(shape=shape):
                self.rejects_manifest(lambda m, s=shape: tree_node(m, "input_irradiance").update(shape=s),
                                      "rank|singleton|bound|range")

    def test_native_semantic_shapes_are_not_interchangeable(self):
        for path, shape in (("configuration.wavelength_nm", (1, 2)),
                            ("configuration.image_size", (2, 1)),
                            ("input_irradiance", (3, 2, 2)),
                            ("components.shared.row_e", (1, 2)),
                            ("components.single.column_e", (3, 1))):
            with self.subTest(path=path):
                self.rejects_result(lambda r, p=path, s=shape: setattr(field(r, p), "shape", s), "shape")

    def test_native_semantic_classes_are_not_interchangeable(self):
        self.rejects_result(lambda r: setattr(r["readout"]["raw_dn"], "class_name", "double"), "RAW: incorrect class")
        self.rejects_result(lambda r: assign(r, "configuration.adc_bits", numbers([5], (1, 1), "uint16")), "adc_bits: incorrect class")
        self.rejects_result(lambda r: assign(r, "noise_model.enabled", 1), "enabled: incorrect class")
        for class_name in ("single", "uint8", "complex", True):
            with self.subTest(class_name=class_name):
                self.rejects_manifest(lambda m, c=class_name: tree_node(m, "configuration.image_size").update({"class": c}), "native class")

    def test_offsets_gaps_overlaps_wrong_segment_bytes_and_field_reordering_reject(self):
        for increment in (-8, 8):
            self.rejects_manifest(lambda m, n=increment: tree_node(m, "input_irradiance").update(
                offset=tree_node(m, "input_irradiance")["offset"] + n), "contiguous depth-first")
        self.rejects_manifest(lambda m: tree_node(m, "input_irradiance").update(byte_count=88), "contiguous depth-first")

        def reorder(metadata):
            value = tree_node(metadata, "configuration")["fields"]
            value["image_size"], value["wavelength_nm"] = value["wavelength_nm"], value["image_size"]
        self.rejects_manifest(reorder, "contiguous depth-first|units")

    def test_first_offset_must_start_at_zero(self):
        self.rejects_manifest(lambda m: tree_node(m, "configuration.image_size").update(offset=8), "contiguous depth-first")

    def test_numeric_unit_paths_reject_even_when_values_hash_and_class_match(self):
        for path in ("input_irradiance", "noise_model.dark_current_e_per_s", "readout.raw_dn",
                     "configuration.qe", "configuration.gain_dn_per_e", "readout.seed", "readout.full_well_saturated"):
            with self.subTest(path=path):
                self.rejects_manifest(lambda m, p=path: tree_node(m, p).update(units="incorrect"), "leaf units disagree")

    def test_cell_keys_order_kind_item_count_and_shape_reject(self):
        self.rejects_manifest(lambda m: tree_node(m, "operation_order")["items"].update(i999999={"kind": "char", "shape": [1, 1], "value": "x"}), "contiguous and ordered")
        self.rejects_manifest(lambda m: tree_node(m, "operation_order").update(items=dict(reversed(list(tree_node(m, "operation_order")["items"].items())))), "contiguous and ordered")
        self.rejects_manifest(lambda m: tree_node(m, "operation_order").update(shape=[11, 1]), "character-cell row")
        for value in (None, True, "foreign"):
            self.rejects_manifest(lambda m, v=value: tree_node(m, "format").update(kind=v), "Malformed typed|Unknown typed")

    def test_character_extent_value_kind_and_runtime_native_length_reject(self):
        for change in (dict(shape=[2, 3]), dict(shape=[1, 999]), dict(value=1), dict(value="")):
            with self.subTest(change=change):
                self.rejects_manifest(lambda m, c=change: tree_node(m, "format").update(c), "Character|character")
        result = make_spatial_result()
        write_bundle(self.bundle, result)
        self.rejects_manifest(lambda m: tree_node(m, "spatial_baseline.spatial_provenance.unicode_label").update(shape=[1, 3]), "native extent")

    def test_tree_depth_node_count_and_struct_field_limits_reject(self):
        spatial = make_spatial_result()
        value = "leaf"
        for _ in range(24):
            value = {"nested": value}
        self.rejects_result(lambda r: r["spatial_baseline"]["spatial_provenance"].update(deep=value), "depth/node|nesting", result=spatial)
        wide = {f"f{i:03d}": "x" for i in range(257)}
        self.rejects_result(lambda r: r["spatial_baseline"].update(spatial_provenance=wide), "256-field|bounded", result=spatial)
        many = {f"group{i:03d}": {f"f{j:03d}": "x" for j in range(80)} for i in range(250)}
        self.rejects_result(lambda r: r["spatial_baseline"].update(spatial_provenance=many), "depth/node", result=spatial)

    def test_numeric_nonfinite_and_noncanonical_logical_bytes_reject_after_rehash(self):
        for value in (math.nan, math.inf, -math.inf):
            with self.subTest(value=value):
                self.rejects_samples("input_irradiance", [value] + CUBE[1:], "Nonfinite packed")
        self.rejects_samples("noise_model.enabled", [2], "Logical payload bytes")

    def test_payload_actual_hash_and_truncated_length_reject(self):
        self.rejects_samples("input_irradiance", [9] + CUBE[1:], "SHA-256", rehash=False)
        with self.restore_bundle():
            path = self.bundle / "data.bin"
            path.write_bytes(path.read_bytes()[:-1])
            refresh_hash(self.bundle)
            with self.assertRaisesRegex(verifier.ArtifactError, "byte count"):
                verifier.verify_bundle(self.bundle)

    def test_trailing_payload_bytes_reject_even_after_rehash_and_count_refresh(self):
        with self.restore_bundle():
            path = self.bundle / "data.bin"
            path.write_bytes(path.read_bytes() + b"\0" * 8)
            refresh_hash(self.bundle, counts=True)
            with self.assertRaisesRegex(verifier.ArtifactError, "consume every payload"):
                verifier.verify_bundle(self.bundle)

    def test_total_sample_accounting_rejects_rehashed_under_and_overcounts(self):
        for difference in (-1, 1):
            with self.subTest(difference=difference):
                self.rejects_manifest(lambda m, d=difference: m["payload"].update(sample_count=m["payload"]["sample_count"] + d), "contiguous depth-first|consume every payload")

    def test_plane_major_spectral_permutation_is_not_true_c_order(self):
        plane_major = CUBE[::2] + CUBE[1::2]
        self.assertNotEqual(plane_major, CUBE)
        self.rejects_samples("input_irradiance", plane_major, "baseline spectral expectation")


class Phase4SemanticMutationTests(FixtureCase):
    def test_result_unknown_fields_and_disabled_or_sequence_kinds_reject(self):
        self.rejects_result(lambda r: r.update(foreign=True), "structured result: incomplete or unknown")
        self.rejects_result(lambda r: r["noise_model"].update(foreign=True), "noise model: incomplete or unknown")
        self.rejects_result(lambda r: r["readout"].update(foreign=True), "structured readout: incomplete or unknown")
        self.rejects_result(lambda r: r.update(result_kind="sequence"), "Unsupported structured result kind")
        self.rejects_result(lambda r: r["noise_model"].update(enabled=False), "enabled: logical flag")

    def test_source_heads_meaning_and_expected_commit_association_reject(self):
        for key in ("repository_head", "isetcam_head", "isethdrsensor_head"):
            for value in ("a" * 39, "A" * 40, 1, ["1" * 40]):
                with self.subTest(key=key, value=value):
                    self.rejects_manifest(lambda m, k=key, v=value: m["provenance"].update({k: v}), "malformed observed")
        self.rejects_manifest(lambda m: m["provenance"].update(meaning="Authenticated source"), "meaning")
        self.rejects_manifest(lambda m: m["provenance"].update(unknown="x"), "provenance: incomplete or unknown")
        for commit in ("2" * 40, "a" * 39, "A" * 40):
            with self.subTest(commit=commit), self.assertRaisesRegex(verifier.ArtifactError, "commit|SHA"):
                verifier.verify_bundle(self.bundle, expected_commit=commit)

    def test_unavailable_source_heads_remain_valid_observations_without_expected_commit(self):
        metadata = json.loads((self.bundle / "structured.json").read_bytes())
        for key in ("repository_head", "isetcam_head", "isethdrsensor_head"):
            metadata["provenance"][key] = ""
        write_json(self.bundle / "structured.json", metadata)
        self.assertEqual(verifier.verify_bundle(self.bundle)["source"], dict(repository_head="", isetcam_head="", isethdrsensor_head=""))
        with self.assertRaisesRegex(verifier.ArtifactError, "another commit"):
            verifier.verify_bundle(self.bundle, expected_commit="1" * 40)

    def test_runtime_name_version_and_exact_fields_reject(self):
        for key, value in (("name", "Python"), ("version", ""), ("version", "\n9.4"), ("version", "x" * 257)):
            with self.subTest(key=key, value=value):
                self.rejects_result(lambda r, k=key, v=value: r["runtime"].update({k: v}), "runtime|text")
        self.rejects_result(lambda r: r["runtime"].update(extra="x"), "runtime: incomplete or unknown")

    def test_geometry_roi_full_grid_and_crop_cfa_bindings_reject(self):
        self.rejects_samples("geometry.active_roi", [1, 1, 2, 3], "geometry/CFA parity")
        self.rejects_samples("geometry.active_roi", [3, 3, 2, 3], "outside the full grid")
        self.rejects_samples("noise_model.full_grid_size", [4, 3], "Noise model/full geometry")
        self.rejects_result(lambda r: r["configuration"].update(cfa_pattern="RGGB"), "geometry/CFA parity")

    def test_full_maps_active_crops_scalar_form_and_rms_association_reject(self):
        changed = deepcopy(self.result["noise_model"]["prnu"].values)
        changed[5] += .25
        self.rejects_samples("noise_model.prnu", changed, "active prnu")
        self.rejects_samples("active_maps.prnu", [2] + ACTIVE_PRNU[1:], "active prnu")
        self.rejects_samples("active_maps.dark_current_e_per_s", [1] + ACTIVE_DARK[1:], "active dark_current")
        self.rejects_samples("active_maps.shared.fixed_offset_e", [-9] + ACTIVE_SHARED[1:], "active shared fixed map")
        self.rejects_samples("active_maps.shared.row_noise_e", [1], "Active RMS")
        self.rejects_result(lambda r: assign(r, "noise_model.prnu", numbers([1] * 6)), "full-grid sized")

    def test_negative_prnu_dark_rate_and_rms_reject(self):
        for path in ("noise_model.prnu", "noise_model.dark_current_e_per_s"):
            with self.subTest(path=path):
                values = deepcopy(field(self.result, path).values)
                values[0] = -1
                self.rejects_samples(path, values, "below its supported range")
        self.rejects_samples("noise_model.shared.row_noise_e", [-1], "invalid numeric range")

    def test_baseline_incident_photo_dark_and_total_means_reject_rehashed_edits(self):
        for path, expected in (("baseline_expected_electrons", BASELINE),
                               ("readout.expected_incident_photons", INCIDENT),
                               ("readout.expected_photoelectrons", [4.25, 2.5, 25.5, 15, 0, 15]),
                               ("readout.expected_dark_electrons", [0, 1, 2, 3, 4, 5]),
                               ("readout.expected_electrons", [4.25, 3.5, 27.5, 18, 4, 20])):
            with self.subTest(path=path):
                self.rejects_samples(path, [expected[0] + 1] + expected[1:], "expectation|expected electrons")

    def test_disabled_shot_noise_requires_exact_photo_and_dark_expectations(self):
        self.rejects_samples("components.photo_electrons", [5, 2.5, 25.5, 15, 0, 15], "disabled shot noise changed expectation")
        self.rejects_samples("components.dark_electrons", [1, 1, 2, 3, 4, 5], "disabled shot noise changed expectation")

    def test_poisson_draw_support_integers_nonnegative_and_zero_mean_reject(self):
        write_bundle(self.bundle, make_result(stochastic=1))
        for path, values, message in (
                ("components.photo_electrons", [3.5, 4, 27, 17, 0, 18], "Poisson support"),
                ("components.photo_electrons", [3, 4, 27, 17, 1, 18], "zero-mean association"),
                ("components.dark_electrons", [1, 2, 1, 5, 2, 4], "zero-mean association"),
                ("components.dark_electrons", [0, -1, 1, 5, 2, 4], "below its supported range")):
            with self.subTest(path=path, values=values):
                self.rejects_samples(path, values, message)

    def test_collected_charge_well_and_physical_saturation_reject(self):
        self.rejects_samples("readout.collected_electrons", [4.25, 3.5, 26.5, 18, 4, 20], "sampled photo-plus-dark charge")
        self.rejects_samples("readout.charge_electrons", [4.25, 3.5, 27.5, 18, 4, 20], "one shared physical well")
        self.rejects_samples("readout.full_well_saturated", [0, 0, 1, 0, 0, 0], "physical saturation")

    def test_zero_rms_row_column_frame_and_pixel_components_reject(self):
        cases = (("shared.row_e", [1, 0]), ("shared.column_e", [0, 1, 0]),
                 ("shared.frame_e", [1]), ("shared.pixel_e", [1, 0, 0, 0, 0, 0]),
                 ("single.row_e", [1, 0]), ("single.column_e", [0, 1, 0]),
                 ("single.frame_e", [1]), ("single.pixel_e", [1, 0, 0, 0, 0, 0]))
        for suffix, values in cases:
            with self.subTest(component=suffix):
                self.rejects_samples("components." + suffix, values, "zero RMS component")

    def test_retained_fixed_components_electronic_totals_and_signed_assembly_reject(self):
        self.rejects_samples("components.shared.fixed_offset_e", [-9] + ACTIVE_SHARED[1:], "fixed electronic component")
        self.rejects_samples("components.shared.total_e", [-9] + ACTIVE_SHARED[1:], "total electronics")
        self.rejects_samples("components.single.total_e", [1] + [.25] * 5, "total electronics")
        self.rejects_samples("readout.read_electrons", [-4.5, 8.5, 21.25, 20.25, -3.75, 19.75], "signed electronic assembly")

    def test_subnormal_components_and_fractional_out_of_range_seeds_reject(self):
        self.rejects_samples("components.shared.row_e", [float.fromhex("0x0.0000000000001p-1022"), 0], "subnormal")
        for value in (-1, 2**32, 4294967295.5):
            with self.subTest(seed=value):
                self.rejects_samples("readout.seed", [value], "numeric range|integer")
        self.rejects_samples("seeds.low_pixel", [42], "named seed schedule")

    def test_raw_adc_masks_usable_and_physical_reconstruction_reject(self):
        for path, values, message in (("raw_dn", [0, 19, 31, 31, 0, 31], "rounding/ADC clipping"),
                                      ("adc_low_clipped", [0, 0, 0, 0, 1, 0], "lower ADC mask"),
                                      ("adc_high_clipped", [0, 0, 1, 0, 0, 1], "upper ADC mask"),
                                      ("adc_usable", [0, 1, 1, 0, 0, 0], "conservative ADC usability"),
                                      ("reconstruction_valid", [0, 1, 1, 0, 0, 0], "physical reconstruction validity")):
            with self.subTest(path=path):
                self.rejects_samples("readout." + path, values, message)

    def test_dual_path_component_independence_and_raw_assembly_reject(self):
        write_bundle(self.bundle, make_result("dual"))
        self.rejects_samples("components.high_gain.total_e", [.75] + [.5] * 5, "total electronics")
        self.rejects_samples("readout.low_gain.read_electrons", [-6, 8, 20.75, 20.75, -4.25, 19.25], "signed electronic assembly")
        self.rejects_samples("readout.high_gain.raw_dn", [0, 44, 63, 63, 0, 63], "rounding/ADC clipping")

    def test_merge_observed_electrons_weights_endpoints_and_masks_reject(self):
        write_bundle(self.bundle, make_result("dual"))
        cases = (("electrons", [-6, 8.5, 21, 20, -4, 19], "merge electrons"),
                 ("weight_high", [0, .6, 0, 0, 0, 0], "merge weights"),
                 ("weight_high", [1e-16, .5, 0, 0, 0, 0], "merge weights|zero or sign"),
                 ("high_usable", [1, 1, 0, 0, 0, 0], "merged high usability"),
                 ("low_usable", [0, 1, 1, 1, 1, 1], "merged low usability"),
                 ("valid", [0, 1, 1, 1, 1, 1], "merged validity"))
        for path, values, message in cases:
            with self.subTest(path=path, values=values):
                self.rejects_samples("readout.merged." + path, values, message)
        # Substituting inaccessible true stored charge must not pass as a merge.
        self.rejects_samples("readout.merged.electrons", [4.25, 3.5, 20, 18, 4, 20], "merge electrons")

    def test_operation_units_classification_and_temperature_associations_reject(self):
        self.rejects_result(lambda r: r["operation_order"].items.reverse(), "operation order: cell values")
        self.rejects_result(lambda r: r["units"].update(raw_dn="electrons"), "units: literal")
        self.rejects_result(lambda r: r.update(parameter_classification="measured"), "classification: literal")
        self.rejects_result(lambda r: r["temperature_condition"].update(reference_temperature_K=300), "Temperature condition")
        self.rejects_result(lambda r: r.update(seed_policy="unknown"), "seed policy: literal")

    def test_spatial_psf_optical_sampled_grid_and_diagnostics_reject(self):
        write_bundle(self.bundle, make_spatial_result())
        self.rejects_samples("spatial_baseline.psf.kernel", [.25, .25, .75, .75], "PSF convolution")
        self.rejects_samples("spatial_baseline.optical_irradiance", [9] + CUBE[1:], "PSF convolution")
        self.rejects_samples("spatial_baseline.sampled_irradiance", [9] + CUBE[1:], "sampled input differs")
        self.rejects_samples("spatial_baseline.optical_grid.x_edges_m", [.25, .75, 1.25, 1.75], "valid-support/origin crop")
        self.rejects_samples("spatial_baseline.sampling_report.source_integral.values", [43, 84], "source integral")
        self.rejects_samples("spatial_baseline.sampling_report.x_weight_nonzeros", [4], "weight count")
        self.rejects_samples("spatial_baseline.optical_report.retained_column_indices", [1, 3], "retained_column_indices")

    def test_spatial_baseline_legacy_charge_and_signed_history_reject(self):
        write_bundle(self.bundle, make_spatial_result())
        self.rejects_samples("spatial_baseline.readout.collected_electrons", [5.25] + BASELINE[1:], "disabled shot noise")
        self.rejects_samples("spatial_baseline.readout.read_electrons", [5.25] + BASELINE[1:], "signed electronic assembly")
        self.rejects_samples("spatial_baseline.readout.raw_dn", [12, 13, 28, 23, 23, 31], "rounding/ADC clipping")
        self.rejects_samples("spatial_baseline.readout.expected_electrons", [5.25] + BASELINE[1:], "unmodified spectral baseline")

    def test_post_optics_psf_marker_and_metadata_unit_precedence_reject(self):
        spatial = make_spatial_result(stage="post_optics")
        self.rejects_result(lambda r: r["spatial_baseline"].update(psf=numbers([], (1, 0))), "post-optics empty PSF", result=spatial)
        write_bundle(self.bundle, spatial)
        self.rejects_manifest(lambda m: tree_node(m, "spatial_baseline.spatial_provenance.informational_flag").update(units="logical"), "leaf units disagree")

    def test_spatial_provenance_cells_reject_at_any_depth(self):
        for value in (Cells(["opaque"], (1, 1)), Cells([], (0, 0)),
                      dict(nested=Cells([numbers([1], (1, 1))], (1, 1)))):
            with self.subTest(value=value):
                self.rejects_result(lambda r, v=value: r["spatial_baseline"]["spatial_provenance"].update(bad=v),
                                    "Unsupported spatial provenance value type", result=make_spatial_result())

    def test_spatial_provenance_uint16_values_reject(self):
        for values, shape in (([1], (1, 1)), ([1, 2, 3, 4], (2, 2)), ([], (1, 0))):
            with self.subTest(shape=shape):
                value = numbers(values, shape, "uint16")
                self.rejects_result(lambda r, v=value: r["spatial_baseline"]["spatial_provenance"].update(bad=v),
                                    "Spatial provenance requires double matrices", result=make_spatial_result())

    def test_spatial_provenance_nonscalar_logical_values_reject(self):
        for values, shape in (([0, 1], (1, 2)), ([0, 1], (2, 1)),
                              ([0, 1, 1, 0], (2, 2)), ([], (0, 0)), ([0, 1], (1, 1, 2))):
            with self.subTest(shape=shape):
                value = numbers(values, shape, "logical")
                self.rejects_result(lambda r, v=value: r["spatial_baseline"]["spatial_provenance"].update(bad=v),
                                    "Spatial provenance requires double matrices", result=make_spatial_result())

    def test_spatial_provenance_rank_three_doubles_reject(self):
        for values, shape in (([1, 2], (1, 1, 2)), ([], (0, 2, 3))):
            with self.subTest(shape=shape):
                value = numbers(values, shape)
                self.rejects_result(lambda r, v=value: r["spatial_baseline"]["spatial_provenance"].update(bad=v),
                                    "Spatial provenance requires double matrices", result=make_spatial_result())

    def test_spatial_provenance_noncanonical_empty_character_shapes_reject(self):
        for shape in ((1, 0), (0, 1), (0, 3), (3, 0)):
            with self.subTest(shape=shape):
                value = Characters("", shape)
                self.rejects_result(lambda r, v=value: r["spatial_baseline"]["spatial_provenance"].update(bad=v),
                                    "Spatial provenance has an unsupported character shape", result=make_spatial_result())

    def test_spatial_provenance_packed_values_can_exceed_plain_json_limit(self):
        # Native %.17g spells -pi as -3.1415926535897931 (19 bytes).
        # {"values":[...]} therefore occupies exactly 2,000,012 bytes.
        result = make_spatial_result(stage="post_optics")
        result["spatial_baseline"]["spatial_provenance"] = dict(
            values=numbers([-math.pi] * 100_000, (1, 100_000)))
        write_bundle(self.bundle, result)
        self.assertLess((self.bundle / "structured.json").stat().st_size, 30_000)
        self.assertLess((self.bundle / "data.bin").stat().st_size, 1_000_000)
        with self.assertRaisesRegex(verifier.ArtifactError, "Spatial provenance.*plain JSON byte limit"):
            verifier.verify_bundle(self.bundle)

    def test_spatial_provenance_actual_plain_json_byte_boundary(self):
        result = make_spatial_result(stage="post_optics")
        metadata = dict(values=numbers([-math.pi] * 99_999, (1, 99_999)))
        result["spatial_baseline"]["spatial_provenance"] = metadata
        # With the final b field these are 1,999,999 / 2,000,000 / 2,000,001 bytes.
        for label, expected in (("", 1_999_999), ("x", 2_000_000), ("xy", 2_000_001)):
            with self.subTest(plain_json_bytes=expected):
                metadata["b"] = label if label else Characters("", (0, 0))
                write_bundle(self.bundle, result)
                if expected <= 2_000_000:
                    bundle = verifier.verify_bundle(self.bundle)
                    observed = bundle["result"]["spatial_baseline"]["spatial_provenance"]
                    self.assertEqual(verifier.spatial_provenance(observed), expected)
                    self.assertIs(bundle["spatial_arithmetic_checked"], True)
                else:
                    with self.assertRaisesRegex(verifier.ArtifactError, "plain JSON byte limit"):
                        verifier.verify_bundle(self.bundle)


class Phase4SpatialProvenanceSizeTests(unittest.TestCase):
    def assert_counted_boundary(self, value, expected):
        # Tiny, independently counted text exercises both sides of the limit.
        with mock.patch.object(verifier, "MAX_JSON", expected):
            self.assertEqual(verifier.spatial_provenance(value), expected)
        with mock.patch.object(verifier, "MAX_JSON", expected - 1):
            with self.assertRaisesRegex(verifier.ArtifactError, "plain JSON byte limit"):
                verifier.spatial_provenance(value)

    def test_plain_json_scalar_vector_matrix_and_empty_shapes(self):
        for shape, values, encoded in (
                ((1, 1), [2.5], "2.5"), ((1, 3), [1, 2, 3], "[1,2,3]"),
                ((3, 1), [1, 2, 3], "[1,2,3]"),
                ((2, 3), [1, 2, 3, 4, 5, 6], "[[1,2,3],[4,5,6]]"),
                ((0, 0), [], "[]"), ((1, 0), [], "[]"),
                ((0, 1), [], "[]"), ((2, 0), [], "[]"), ((0, 3), [], "[]")):
            with self.subTest(shape=shape):
                self.assert_counted_boundary(dict(v=verifier.Array("double", shape, values)),
                                             len('{"v":' + encoded + '}'))
        self.assert_counted_boundary({}, 2)
        value = dict(a={}, b=dict(v=verifier.Array("logical", (1, 1), [1]),
                                 z=verifier.Array("logical", (1, 1), [0])),
                     c=verifier.Char("", (0, 0)))
        self.assert_counted_boundary(value, len('{"a":{},"b":{"v":true,"z":false},"c":""}'))

    def test_plain_json_binary64_tokens_keep_17_digits_and_signed_zero(self):
        for sample, token in (
                (0.0, "0"), (-0.0, "-0"), (.1, "0.10000000000000001"),
                (-math.pi, "-3.1415926535897931"),
                (float.fromhex("0x0.0000000000001p-1022"), "4.9406564584124654e-324"),
                (float.fromhex("0x1.0000000000000p-1022"), "2.2250738585072014e-308"),
                (float.fromhex("0x1.fffffffffffffp+1023"), "1.7976931348623157e+308"),
                (9007199254740991.0, "9007199254740991"),
                (9007199254740992.0, "9007199254740992"),
                (math.nextafter(1.0, 2.0), "1.0000000000000002"),
                (1e-4, "0.0001"), (1e-5, "1.0000000000000001e-05"),
                (1e16, "10000000000000000"), (1e17, "1e+17")):
            with self.subTest(token=token):
                self.assert_counted_boundary(dict(v=verifier.Array("double", (1, 1), [sample])),
                                             len('{"v":' + token + '}'))

    def test_plain_json_native_escaping_counts_utf8_bytes(self):
        # Measured Octave 9.4 escaping: five short controls; other C0 controls
        # use six bytes. Slash, DEL and Unicode stay unescaped UTF-8.
        controls = "".join(chr(code) for code in range(1, 32))
        cases = ((controls, 26 * 6 + 5 * 2), ('"\\/', 2 + 2 + 1),
                 ("\x7f\u0080\u07ff\u0800\uffff", 1 + 2 + 2 + 3 + 3),
                 ("μ😀\u2028\u2029", 2 + 4 + 3 + 3))
        for label, content_bytes in cases:
            with self.subTest(label=repr(label)):
                value = dict(s=verifier.Char(label, (1, len(label.encode("utf-8")))))
                self.assert_counted_boundary(value, content_bytes + 8)  # {"s":"..."}

    def test_plain_json_rejects_before_consuming_remaining_numeric_values(self):
        class GuardedValues:
            def __len__(self):
                return 3

            def __iter__(self):
                yield 1.0
                raise AssertionError("Oversized provenance consumed unnecessary numeric values")

        value = dict(v=verifier.Array("double", (1, 3), GuardedValues()))
        with mock.patch.object(verifier, "MAX_JSON", 10):
            with self.assertRaisesRegex(verifier.ArtifactError, "plain JSON byte limit"):
                verifier.spatial_provenance(value)


class Phase4FilesystemTests(FixtureCase):
    def test_missing_extra_files_and_extra_directories_reject(self):
        for filename in ("data.bin", "structured.json"):
            with self.subTest(missing=filename):
                target = self.bundle / filename
                content = target.read_bytes()
                target.unlink()
                try:
                    with self.assertRaisesRegex(verifier.ArtifactError, "exactly"):
                        verifier.verify_bundle(self.bundle)
                finally:
                    target.write_bytes(content)
        for directory in (False, True):
            extra = self.bundle / "foreign"
            extra.mkdir() if directory else extra.write_text("unrelated", encoding="utf-8")
            try:
                with self.assertRaisesRegex(verifier.ArtifactError, "exactly"):
                    verifier.verify_bundle(self.bundle)
            finally:
                extra.rmdir() if directory else extra.unlink()

    def test_symlink_manifest_payload_bundle_and_ancestor_reject(self):
        for filename in ("structured.json", "data.bin"):
            with self.subTest(filename=filename):
                target = self.bundle / filename
                saved = self.root / (filename + ".saved")
                target.rename(saved)
                target.symlink_to(saved)
                try:
                    with self.assertRaisesRegex(verifier.ArtifactError, "non-symlink"):
                        verifier.verify_bundle(self.bundle)
                finally:
                    target.unlink()
                    saved.rename(target)
        alias = self.root / "alias"
        alias.symlink_to(self.bundle, target_is_directory=True)
        with self.assertRaisesRegex(verifier.ArtifactError, "ancestors must not be symlinks"):
            verifier.verify_bundle(alias)
        parent_alias = self.root / "parent-alias"
        parent_alias.symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(verifier.ArtifactError, "ancestors must not be symlinks"):
            verifier.verify_bundle(parent_alias / "bundle")

    def test_hardlinked_manifest_payload_and_cross_filename_alias_reject(self):
        for filename in ("structured.json", "data.bin"):
            with self.subTest(filename=filename):
                alias = self.root / "hardlink"
                os.link(self.bundle / filename, alias)
                try:
                    with self.assertRaisesRegex(verifier.ArtifactError, "single-link"):
                        verifier.verify_bundle(self.bundle)
                finally:
                    alias.unlink()
        (self.bundle / "data.bin").unlink()
        os.link(self.bundle / "structured.json", self.bundle / "data.bin")
        with self.assertRaisesRegex(verifier.ArtifactError, "single-link|alias"):
            verifier.verify_bundle(self.bundle)

    def test_nonordinary_file_entry_rejects_without_reading_fifo(self):
        target = self.bundle / "data.bin"
        target.unlink()
        os.mkfifo(target)
        with self.assertRaisesRegex(verifier.ArtifactError, "regular single-link"):
            verifier.verify_bundle(self.bundle)

    def test_literal_dot_repeated_trailing_and_parent_path_aliases_reject(self):
        root, bundle = str(self.root), str(self.bundle)
        for path in (root + "/./bundle", root + "//bundle", bundle + "/", bundle + "/../bundle", "", b"bad"):
            with self.subTest(path=path), self.assertRaisesRegex(verifier.ArtifactError, "segments|separators|path text"):
                verifier.verify_bundle(path)
        # A Path has already normalized its dot segments; no impossible recovery
        # of discarded lexical information is required from the API.
        verifier.verify_bundle(Path(root + "/./bundle"))

    def test_file_replacement_during_semantic_validation_rejects_even_identical_bytes(self):
        original_validator = verifier.validate_result
        for filename in ("structured.json", "data.bin"):
            with self.subTest(filename=filename):
                def replace(result):
                    answer = original_validator(result)
                    target = self.bundle / filename
                    temporary = self.root / "replacement"
                    temporary.write_bytes(target.read_bytes())
                    os.replace(temporary, target)
                    return answer
                with mock.patch.object(verifier, "validate_result", side_effect=replace):
                    with self.assertRaisesRegex(verifier.ArtifactError, "identity or files changed"):
                        verifier.verify_bundle(self.bundle)

    def test_inplace_rewrite_during_semantic_validation_rejects(self):
        original_validator = verifier.validate_result
        for filename in ("structured.json", "data.bin"):
            with self.subTest(filename=filename), self.restore_bundle():
                def rewrite(result):
                    answer = original_validator(result)
                    target = self.bundle / filename
                    content = bytearray(target.read_bytes())
                    content[-1] ^= 1
                    target.write_bytes(content)
                    return answer
                with mock.patch.object(verifier, "validate_result", side_effect=rewrite):
                    with self.assertRaisesRegex(verifier.ArtifactError, "identity or files changed"):
                        verifier.verify_bundle(self.bundle)

    def test_added_entry_during_semantic_validation_rejects_and_preserves_foreign_file(self):
        original_validator = verifier.validate_result
        foreign = self.bundle / "foreign"

        def add_file(result):
            answer = original_validator(result)
            foreign.write_text("owned by another caller", encoding="utf-8")
            return answer
        with mock.patch.object(verifier, "validate_result", side_effect=add_file):
            with self.assertRaisesRegex(verifier.ArtifactError, "identity or files changed"):
                verifier.verify_bundle(self.bundle)
        self.assertEqual(foreign.read_text(encoding="utf-8"), "owned by another caller")


class Phase4RepeatLayerTests(unittest.TestCase):
    """Real file identity/hash gate, isolated from complete demo/report parsing."""
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="phase4-repeat-layer-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.demo, self.repeat = self.root / "demo", self.root / "repeat"
        self.demo.mkdir()
        self.repeat.mkdir()
        validation = self.root / "validation"
        validation.mkdir()
        write_json(validation / "phase4-validation.json", {"fixture_only": True})
        for directory in (self.demo, self.repeat):
            (directory / "a").write_bytes(b"first")
            (directory / "b").write_bytes(b"second")
        report = mock.patch.object(verifier, "check_numerical_report", return_value=(
            {k: v for k, v in SOURCE.items() if k != "meaning"},
            (ENGINE["name"], ENGINE["version"]), 9, 9, 7))
        demo = mock.patch.object(verifier, "verify_demo", side_effect=lambda path, *args:
                                 ([Path(path) / "a", Path(path) / "b"], {}))
        report.start()
        demo.start()
        self.addCleanup(report.stop)
        self.addCleanup(demo.stop)

    def test_distinct_byte_identical_repeat_files_pass_comparison_layer(self):
        result = verifier.verify_outputs(self.root, compare_dir=self.repeat)
        self.assertIs(result["compared_demo_byte_identical"], True)
        self.assertEqual(result["artifact_sha256"], dict(a=hashlib.sha256(b"first").hexdigest(),
                                                       b=hashlib.sha256(b"second").hexdigest()))

    def test_compare_same_resolved_directory_and_symlink_directory_reject(self):
        with self.assertRaisesRegex(verifier.ArtifactError, "distinct resolved directory"):
            verifier.verify_outputs(self.root, compare_dir=self.demo)
        alias = self.root / "alias"
        alias.symlink_to(self.demo, target_is_directory=True)
        with self.assertRaisesRegex(verifier.ArtifactError, "ancestors must not be symlinks"):
            verifier.verify_outputs(self.root, compare_dir=alias)

    def test_compare_same_name_and_cross_filename_hardlink_aliases_reject(self):
        for source_name in ("a", "b"):
            with self.subTest(source_name=source_name):
                target = self.repeat / "a"
                target.unlink()
                os.link(self.demo / source_name, target)
                try:
                    with self.assertRaisesRegex(verifier.ArtifactError, "single-link|aliases"):
                        verifier.verify_outputs(self.root, compare_dir=self.repeat)
                finally:
                    target.unlink()
                    target.write_bytes(b"first")

    def test_repeat_identity_set_detects_cross_filename_alias_without_nlink_assumption(self):
        real_regular = verifier.regular

        def remapped_identity(path):
            path = Path(path)
            return real_regular(self.demo / "b") if path == self.repeat / "a" else real_regular(path)
        # Simulates a filesystem alias not expressed as an ordinary hardlink;
        # the cross-set identity comparison remains an independent second guard.
        with mock.patch.object(verifier, "regular", side_effect=remapped_identity):
            with self.assertRaisesRegex(verifier.ArtifactError, "cross-filename aliases"):
                verifier.verify_outputs(self.root, compare_dir=self.repeat)

    def test_disjoint_repeat_with_changed_bytes_rejects(self):
        (self.repeat / "b").write_bytes(b"changed")
        with self.assertRaisesRegex(verifier.ArtifactError, "not byte-identical"):
            verifier.verify_outputs(self.root, compare_dir=self.repeat)


if __name__ == "__main__":
    unittest.main()
