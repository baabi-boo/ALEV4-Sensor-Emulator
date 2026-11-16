"""Independent Phase 4 demo-summary, association and repeat controls.

The 24 analytical definitions below are handwritten from the documented demo
contract, not obtained from verifier.fixture_spec or native/ignored output.
Only verify_bundle is replaced by an explicitly artificial decoded-result
boundary. This isolates summary validation from wire-parser controls owned by
test_verify_phase4_artifacts. Every inventory, summary and repeat-identity test
uses real temporary files. No MATLAB/Octave, NumPy or subprocess is invoked.
These fixtures do not establish execution, PRNG origin or process independence.
"""
from contextlib import redirect_stderr, redirect_stdout
from copy import deepcopy
import importlib.util
import io
import json
import math
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest import mock

from phase4_fixture_support import ENGINE, SOURCE, TAGS


SPEC = importlib.util.spec_from_file_location(
    "phase4_demo_verifier", Path(__file__).resolve().parents[1] / "verify_phase4_artifacts.py")
verifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verifier)

NAMES = (
    "deterministic_prnu_offsets", "dark_short", "dark_long", "dark_noisy",
    "shared_row_dual", "path_column_dual", "mixed_dual", "spatial_crop_single",
    "single_exposure_zero", "single_exposure_mid", "single_exposure_high",
    "dual_exposure_zero", "dual_exposure_mid", "dual_exposure_high",
    "single_gain_low", "single_gain_high", "dual_gain_low", "dual_gain_high",
    "sequence_primary_001", "sequence_primary_002", "sequence_primary_003",
    "sequence_reset_001", "sequence_continue_002", "sequence_continue_003",
)
EI_POLICY = "metadata_only_no_exposure_or_gain_mapping"
PATHS = ("shared", "single", "high_gain", "low_gain")
SOURCES = ["ASSUMED-P4-" + name for name in
           ("PRNU", "DARK-RATE", "CHARGE", "OFFSET", "ROW", "COLUMN", "FRAME", "IDENTITY")]
UNITS = dict(input_irradiance="photons m^-2 s^-1 nm^-1", exposure_s="s",
             charge_and_offsets="electrons", noise_magnitude="RMS electrons",
             dark_current_e_per_s="electrons photosite^-1 s^-1", gain_dn_per_e="DN electron^-1",
             black_level_dn="DN", prnu="dimensionless", pixel_pitch_m="m", reference_temperature_K="K")
CHECKS = ("exact_frame_count", "unique_fixed_names", "single_lower_adc_clip", "single_upper_adc_clip",
          "single_physical_saturation", "dual_lower_adc_clips", "dual_high_clip_low_usable",
          "dual_merge_transition", "dual_physical_saturation", "dual_low_upper_clip_before_well",
          "fixed_maps_crop_identity", "sequence_seed_wrap", "sequence_reset_exact",
          "sequence_continuation_exact", "ei_labels_changed_without_physics")
OBSERVED_SOURCE = {name: SOURCE[name] for name in ("repository_head", "isetcam_head", "isethdrsensor_head")}
OBSERVED_ENGINE = ENGINE["name"], ENGINE["version"]


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")


def matrix(function):
    return [[function(row, column) for column in range(1, 9)] for row in range(1, 7)]


def array(values, shape=(6, 8), kind="double"):
    """Construct only the public decoded numeric value container."""
    return verifier.Array(kind, shape, list(values))


class DecodedCharacters(verifier.Char):
    """Keep independent fixture copies portable without changing production."""
    def __deepcopy__(self, memo):
        return type(self)(str(self), self.shape)


def characters(value):
    return DecodedCharacters(value, (1, len(value)))


def flatten(rows):
    return [value for row in rows for value in row]


def scalar_adc(values, gain, black, bits):
    maximum = 2**bits - 1
    rounded = [math.floor(value * gain + black + .5) if value * gain + black >= 0
               else math.ceil(value * gain + black - .5) for value in values]
    codes = [min(maximum, max(0, value)) for value in rounded]
    return dict(raw_dn=codes, adc_low_clipped=[value < 0 for value in rounded],
                adc_high_clipped=[value > maximum for value in rounded],
                adc_usable=[0 < value < maximum for value in codes])


def independent_counts(readout, mode):
    """Count retained flags locally; never call the verifier's coverage oracle."""
    value = dict(physical_saturation_pixels=sum(readout["full_well_saturated"]),
                 single_adc_low_clipped_pixels=0, single_adc_high_clipped_pixels=0,
                 high_adc_low_clipped_pixels=0, high_adc_high_clipped_pixels=0,
                 low_adc_low_clipped_pixels=0, low_adc_high_clipped_pixels=0,
                 high_clipped_low_usable_pixels=0, merge_transition_pixels=0,
                 low_high_clipped_before_well_pixels=0,
                 reconstruction_valid_pixels=sum(readout["reconstruction_valid"]))
    if mode == "single":
        value.update(single_adc_low_clipped_pixels=sum(readout["adc_low_clipped"]),
                     single_adc_high_clipped_pixels=sum(readout["adc_high_clipped"]))
    else:
        high, low, saturated = readout["high_gain"], readout["low_gain"], readout["full_well_saturated"]
        for short, branch in (("high", high), ("low", low)):
            for rail in ("low", "high"):
                value[f"{short}_adc_{rail}_clipped_pixels"] = sum(branch[f"adc_{rail}_clipped"])
        value["high_clipped_low_usable_pixels"] = sum(h and l and not s for h, l, s in
            zip(high["adc_high_clipped"], low["adc_usable"], saturated))
        value["low_high_clipped_before_well_pixels"] = sum(l and not s for l, s in
            zip(low["adc_high_clipped"], saturated))
        value["merge_transition_pixels"] = sum(0 < w < 1 for w in readout["merged"]["weight_high"])
    return value


def independent_case(index):
    """Freeze small analytical configurations/maps without querying the SUT."""
    name = NAMES[index]
    crop, sequence, sweep = index == 7, index >= 18, 8 <= index <= 17
    dark = index in (1, 2, 3)
    mixed = index == 6 or sequence
    mode = "dual" if index in (4, 5, 6, 11, 12, 13, 16, 17) or sequence else "single"
    scale = {14: .25, 15: 2, 16: 1, 17: 4}.get(index, 1)
    exposure = {1: .02, 2: 2, 3: 2, 8: 0, 10: .1, 11: 0, 13: .1}.get(index, .02 if sequence else .01)
    seed = (4294967200, 4294967264, 32, 4294967200, 4294967264, 32)[index - 18] if sequence else \
        94100 if 8 <= index <= 10 else 94200 if 11 <= index <= 13 else \
        94300 if index in (14, 15) else 94400 if index in (16, 17) else 94001 + index
    shape = (4, 5) if crop else (6, 8)
    sensor = dict(schema_version="1.0", image_size=list(shape), wavelength_nm=550, bin_width_nm=10,
                  qe=[1, 1, 1], pixel_pitch_m=6e-6, fill_factor=1, full_well_e=3000,
                  shot_noise=mixed, cfa_pattern="BGGR" if crop else "RGGB", read_noise_e=.75 if index == 3 else 0,
                  gain_dn_per_e=scale, black_level_dn=32, adc_bits=10)
    if mode == "dual":
        sensor.update(read_noise_e=3, gain_dn_per_e=.5, black_level_dn=64, adc_bits=16)
        configuration = dict(schema_version="2.0", sensor=sensor,
            high_gain=dict(gain_dn_per_e=4 * scale, read_noise_e=.6 if mixed else 0, black_level_dn=64, adc_bits=12),
            low_gain=dict(gain_dn_per_e=.5 * scale, read_noise_e=1.2 if mixed else 0, black_level_dn=64, adc_bits=12),
            merge=dict(start_e=600 / scale, end_e=900 / scale))
    else:
        configuration = sensor
    geometry = dict(schema_version="1.0", full_grid_size=[6, 8], active_roi=[2, 2, 4, 5] if crop else [1, 1, 6, 8],
                    pixel_pitch_m=6e-6, origin_xy_m=[0, 0], full_grid_cfa_pattern="RGGB",
                    parameter_sources=["ASSUMED-GENERIC-GEOMETRY", "ASSUMED-CFA-ORIGIN"])
    model = dict(schema_version="1.0", enabled=True, full_grid_size=[6, 8],
                 realization_id="ASSUMED-P4-DEMO-MAPS-v1", reference_temperature_K=293.15,
                 prnu=1, dark_current_e_per_s=0, dark_shot_noise=False, parameter_sources=list(SOURCES))
    for path in PATHS:
        model[path] = dict(fixed_offset_e=0, row_noise_e=0, column_noise_e=0, frame_noise_e=0)
    if index in (0, 1, 2, 3, 6, 7) or sequence:
        model["prnu"] = matrix(lambda row, col: 1 + .01 * (row - 3.5) + .005 * (col - 4.5))
        for path, formula in (("shared", lambda row, col: 2 * (row - 3.5) + col - 4.5),
                              ("single", lambda row, col: .25 * (row - col)),
                              ("high_gain", lambda row, col: .5 * row - .25 * col),
                              ("low_gain", lambda row, col: -.25 * row + .5 * col)):
            model[path]["fixed_offset_e"] = matrix(formula)
    if dark or mixed:
        model.update(realization_id="ASSUMED-P4-DEMO-DARK-v1",
                     dark_current_e_per_s=matrix(lambda row, col: 2 + .5 * row + .25 * col))
    if index == 3:
        model["dark_shot_noise"] = True
        model["shared"]["row_noise_e"] = .5
        model["single"].update(column_noise_e=.25, frame_noise_e=.4)
    if index == 4:
        model["realization_id"] = "ASSUMED-P4-DEMO-SHARED-ROW-v1"
        model["shared"]["row_noise_e"] = 6
    if index == 5:
        model["realization_id"] = "ASSUMED-P4-DEMO-PATH-COLUMN-v1"
        model["high_gain"]["column_noise_e"], model["low_gain"]["column_noise_e"] = 4, 7
    if mixed:
        model.update(realization_id="ASSUMED-P4-DEMO-MIXED-v1", dark_shot_noise=True)
        for path, row, column, frame in (("shared", 1.5, .75, .5), ("high_gain", .8, 1.25, .3), ("low_gain", 1.1, 2, .4)):
            model[path].update(row_noise_e=row, column_noise_e=column, frame_noise_e=frame)
    if sweep:
        model["realization_id"] = "ASSUMED-P4-DEMO-SWEEP-v1"
        model["shared"]["fixed_offset_e"] = [[-256] + [0] * 7 for _ in range(6)]
    profile = [0, 4000, 12000, 24000, 40000, 70000, 120000, 220000]
    rate = matrix(lambda row, col: 0 if dark else 50000 if index in (4, 5)
                  else profile[col - 1] if sweep else 10000 + 250 * row + 500 * col)
    density = [[value / ((6e-6)**2 * 10) for value in row] for row in rate]
    coords = [(r, c) for r in range(1, 5) for c in range(1, 6)] if crop else \
             [(r, c) for r in range(6) for c in range(8)]

    def active(values):
        return [values[r][c] for r, c in coords] if isinstance(values, list) else [values] * len(coords)

    means = [rate[r][c] * exposure * p + d * exposure for (r, c), p, d in
             zip(coords, active(model["prnu"]), active(model["dark_current_e_per_s"]))]
    saturated = [value >= 3000 for value in means]
    stored = [min(value, 3000) for value in means]
    readout = dict(expected_electrons=array(means, shape), full_well_saturated=saturated)
    if mode == "single":
        signed = [v + a + b for v, a, b in zip(stored, active(model["shared"]["fixed_offset_e"]),
                                             active(model["single"]["fixed_offset_e"]))]
        readout.update(scalar_adc(signed, scale, 32, 10))
        readout["reconstruction_valid"] = [ok and not s for ok, s in zip(readout["adc_usable"], saturated)]
    else:
        for path in ("high_gain", "low_gain"):
            signed = [v + a + b for v, a, b in zip(stored, active(model["shared"]["fixed_offset_e"]),
                                                 active(model[path]["fixed_offset_e"]))]
            readout[path] = scalar_adc(signed, configuration[path]["gain_dn_per_e"], 64, 12)
        high, low = readout["high_gain"], readout["low_gain"]
        weights = []
        for hc, lc, hok, lok in zip(high["raw_dn"], low["raw_dn"], high["adc_usable"], low["adc_usable"]):
            low_e = (lc - 64) / (.5 * scale)
            progress = min(1, max(0, (low_e - 600 / scale) / (300 / scale)))
            weights.append(1 - progress**2 * (3 - 2 * progress) if hok and lok else 1 if hok else 0)
        readout["merged"] = dict(weight_high=weights)
        readout["reconstruction_valid"] = [(h or l) and not s for h, l, s in
                                           zip(high["adc_usable"], low["adc_usable"], saturated)]
    component_seeds = {"frame": seed, **{key: (seed + tag) % 2**32 for key, tag in TAGS.items()}}
    result = dict(configuration=configuration, geometry=geometry, noise_model=model, readout_mode=mode,
                  result_kind=characters("spatial_exposure" if crop else "exposure"), seeds=component_seeds,
                  input_irradiance=array([density[r][c] for r, c in coords], shape), readout=readout,
                  artificial_decoded_fixture=True)
    if crop:
        result["spatial_baseline"] = dict(input_irradiance=array(flatten(density)),
            input_grid=dict(schema_version="1.0", x_edges_m=[i * 6e-6 for i in range(9)],
                            y_edges_m=[i * 6e-6 for i in range(7)], units="m", sample_semantics="cell_average"),
            input_stage=characters("post_optics"), spatial_provenance={})
    sweep_id = ("single_exposure" if index <= 10 else "dual_exposure" if index <= 13 else
                "single_electronic_gain" if index <= 15 else "dual_electronic_gain") if sweep else ""
    sweep_index = (index - 8) % 3 + 1 if 8 <= index <= 13 else (index - 14) % 2 + 1 if sweep else 0
    role = ("primary" if index < 21 else "reset" if index == 21 else "continue") if sequence else ""
    category = "independent_frame_sequence" if sequence else "electronic_gain_sweep" if index >= 14 else \
        "exposure_sweep" if sweep else "spatial" if crop else "structured_dual" if index in (4, 5, 6) else \
        "dark" if dark else "fixed_maps"
    record = dict(name=name, bundle_dir=name, category=category, result_kind=str(result["result_kind"]), readout_mode=mode,
                  input_definition="zero_irradiance" if dark else "flat_50000_e_per_s" if index in (4, 5)
                  else "eight_column_photo_rate_e_per_s" if sweep else "affine_photo_rate_e_per_s",
                  image_size=list(shape), exposure_s=exposure, seed=seed, component_seeds=deepcopy(component_seeds),
                  configuration=deepcopy(configuration), geometry=deepcopy(geometry), noise_model=deepcopy(model),
                  sweep_id=sweep_id, sweep_index=sweep_index, electronic_gain_scale=scale,
                  sequence_id="ASSUMED-P4-DEMO-SEQUENCE-v1" if sequence else "", sequence_role=role,
                  sequence_seed=4294967200 if sequence else [],
                  absolute_frame_index=(1, 2, 3, 1, 2, 3)[index - 18] if sequence else [], frame_seed=seed,
                  ei_label=(800, 800, 800, 200, 1600, 3200)[index - 18] if sequence else [], ei_policy=EI_POLICY,
                  minimum_expected_e=min(means), maximum_expected_e=max(means), sum_expected_e=math.fsum(means),
                  coverage=independent_counts(readout, mode), synthetic=True, calibrated_alev4=False,
                  parameter_classification="assumed", export_complete=True, readback_verified=True)
    bundle = dict(result=result, sensor=sensor, source=deepcopy(OBSERVED_SOURCE), runtime=OBSERVED_ENGINE,
                  metadata={"provenance": deepcopy(SOURCE)}, seed=seed, exposure_s=exposure,
                  spatial_arithmetic_checked=crop)
    return record, bundle


def independent_summary(records):
    sweeps = []
    for start, stop, name, variable in ((8, 11, "single_exposure", "physical_exposure_s"),
                                      (11, 14, "dual_exposure", "physical_exposure_s"),
                                      (14, 16, "single_electronic_gain", "electronic_gain_scale"),
                                      (16, 18, "dual_electronic_gain", "electronic_gain_scale")):
        frames = records[start:stop]
        item = dict(name=name, variable=variable, readout_mode=frames[0]["readout_mode"],
                    fixture_names=[f["name"] for f in frames], exposures_s=[f["exposure_s"] for f in frames],
                    frame_seeds=[f["seed"] for f in frames], electronic_gain_scales=[f["electronic_gain_scale"] for f in frames],
                    single_gain_dn_per_e=[], high_gain_dn_per_e=[], low_gain_dn_per_e=[],
                    merge_start_e=[], merge_end_e=[], ei_policy=EI_POLICY)
        if item["readout_mode"] == "single":
            item["single_gain_dn_per_e"] = [f["configuration"]["gain_dn_per_e"] for f in frames]
        else:
            for branch in ("high_gain", "low_gain"):
                item[branch + "_dn_per_e"] = [f["configuration"][branch]["gain_dn_per_e"] for f in frames]
            for point in ("start_e", "end_e"):
                item["merge_" + point] = [f["configuration"]["merge"][point] for f in frames]
        sweeps.append(item)
    sequences = []
    for start, stop, role in ((18, 21, "primary"), (21, 22, "reset"), (22, 24, "continue")):
        frames = records[start:stop]
        item = dict(sequence_id="ASSUMED-P4-DEMO-SEQUENCE-v1", role=role,
                    fixture_names=[f["name"] for f in frames],
                    matches_primary_names=[f"sequence_primary_{f['absolute_frame_index']:03d}" for f in frames],
                    sequence_seed=4294967200, frame_indices=[f["absolute_frame_index"] for f in frames],
                    frame_seeds=[f["seed"] for f in frames], exposures_s=[f["exposure_s"] for f in frames],
                    ei_label=[f["ei_label"] for f in frames], temporal_policy="independent_frames",
                    continuation_policy="pure_function_of_arguments_and_absolute_frame_indices", ei_policy=EI_POLICY,
                    seed_schedule=dict(stride=64, modulus=4294967296, minimum_frame_index=1,
                                       maximum_frame_index=67108864,
                                       expression="mod(sequence_seed + 64*(absolute_frame_index-1), 2^32)"),
                    rng_generator="twister", reproducibility="same_runtime_and_version_only")
        if role == "reset":
            for key in ("frame_indices", "frame_seeds", "exposures_s", "ei_label"):
                item[key] = item[key][0]
        sequences.append(item)
    return dict(schema_version="1.0", phase=4, fixture_set_id="ASSUMED-P4-DEMO-v1", frame_count=24,
                sweeps=sweeps, sequences=sequences, fixture_checks={name: True for name in CHECKS},
                generation_complete=True, demo_complete=True, export_readback_complete=True,
                synthetic=True, calibrated_alev4=False, authentic_arriraw=False, parameter_classification="assumed",
                reference_temperature_K=293.15, temperature_policy="declared applicability only; no temperature law",
                ei_policy=EI_POLICY, reproducibility="same_runtime_and_version_only", units=deepcopy(UNITS),
                runtime=deepcopy(ENGINE), provenance=deepcopy(SOURCE), frames=records, status="complete",
                exported_frame_count=24, verified_frame_count=24, calibrated=False, release_accepted=False,
                completion_scope="all_24_fixture_exports_and_native_readbacks")


class DemoFilesMixin:
    """Actual summaries/entry identities with the wire decoder explicitly stubbed."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="phase4-demo-contract-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.demo = self.root / "demo"
        self.demo.mkdir()
        records, self.bundles = [], {}
        for index, name in enumerate(NAMES):
            record, bundle = independent_case(index)
            records.append(record)
            self.bundles[name] = bundle
            directory = self.demo / name
            directory.mkdir()
            for filename in ("structured.json", "data.bin"):
                (directory / filename).write_bytes(f"ARTIFICIAL DECODE BOUNDARY ONLY {name} {filename}\n".encode())
        self.summary = independent_summary(records)
        self.manifest = self.demo / "phase4-demo-summary.json"
        write_json(self.manifest, self.summary)
        self.decoded_names = []
        patcher = mock.patch.object(verifier, "verify_bundle", side_effect=self.decoded_bundle)
        self.decoder = patcher.start()
        self.addCleanup(patcher.stop)

    def decoded_bundle(self, directory, expected_commit=None):
        """Only decode/physics is replaced. All summary/identity code stays real."""
        self.decoded_names.append(directory.name)
        result = deepcopy(self.bundles[directory.name])
        result["files"] = [directory / "structured.json", directory / "data.bin"]
        return result

    def rejects_summary(self, mutation, message=None):
        changed = deepcopy(self.summary)
        mutation(changed)
        write_json(self.manifest, changed)
        try:
            if message:
                with self.assertRaisesRegex(verifier.ArtifactError, message):
                    verifier.verify_demo(self.demo)
            else:
                with self.assertRaises(verifier.ArtifactError):
                    verifier.verify_demo(self.demo)
        finally:
            write_json(self.manifest, self.summary)


class Phase4DemoSummaryTests(DemoFilesMixin, unittest.TestCase):
    def test_handwritten_24_frame_four_sweep_three_sequence_control(self):
        files, metrics = verifier.verify_demo(self.demo, OBSERVED_SOURCE, OBSERVED_ENGINE)
        self.assertEqual(self.decoded_names, list(NAMES))
        self.assertEqual(tuple(metrics), NAMES)
        self.assertEqual(len(files), 49)
        self.assertEqual(len({os.stat(path).st_ino for path in files}), 49)
        self.assertEqual(len(self.summary["sweeps"]), 4)
        self.assertEqual([s["role"] for s in self.summary["sequences"]], ["primary", "reset", "continue"])
        self.assertEqual([metrics[name]["seed"] for name in NAMES[18:21]], [4294967200, 4294967264, 32])
        self.assertEqual(metrics[NAMES[8]]["coverage"]["single_adc_low_clipped_pixels"], 6)
        self.assertGreater(metrics[NAMES[12]]["coverage"]["merge_transition_pixels"], 0)
        self.assertGreater(metrics[NAMES[17]]["coverage"]["low_high_clipped_before_well_pixels"], 0)

    def test_completion_flags_counts_and_calibration_cannot_be_forged(self):
        changes = {"frame_count": [23, 25, True, "24"], "exported_frame_count": [0, 23, True],
                   "verified_frame_count": [0, 23, True], "status": ["in_progress", "failed", "passed"],
                   "generation_complete": [False, 1], "demo_complete": [False, 1],
                   "export_readback_complete": [False, 1], "synthetic": [False, 1],
                   "calibrated": [True, 0], "release_accepted": [True, 0],
                   "calibrated_alev4": [True, 0], "authentic_arriraw": [True, 0]}
        for key, values in changes.items():
            for value in values:
                with self.subTest(key=key, value=value):
                    self.rejects_summary(lambda s, key=key, value=value: s.__setitem__(key, value))

    def test_missing_unknown_summary_fields_and_frozen_inventory_reject(self):
        controls = [lambda s: s.pop("fixture_checks"), lambda s: s.__setitem__("extra", True),
                    lambda s: s["frames"].pop(), lambda s: s["frames"].append(deepcopy(s["frames"][0])),
                    lambda s: s["frames"].reverse(), lambda s: s["frames"][0].__setitem__("name", NAMES[1]),
                    lambda s: s["frames"][0].__setitem__("bundle_dir", "../outside"),
                    lambda s: s["frames"][0].pop("coverage"),
                    lambda s: s["frames"][0].__setitem__("extra", 1)]
        for index, mutation in enumerate(controls):
            with self.subTest(index=index):
                self.rejects_summary(mutation)

    def test_each_frame_requires_export_and_readback_success(self):
        for index in range(24):
            for key in ("export_complete", "readback_verified"):
                for value in (False, 1):
                    with self.subTest(index=index, key=key, value=value):
                        self.rejects_summary(lambda s, i=index, key=key, value=value:
                                             s["frames"][i].__setitem__(key, value))

    def test_fixed_summary_seed_exposure_mode_and_sweep_index_associations(self):
        changes = ((0, "seed", 94002), (0, "frame_seed", 94002), (0, "exposure_s", .02),
                   (0, "readout_mode", "dual"), (0, "result_kind", "spatial_exposure"),
                   (7, "image_size", [6, 8]), (8, "sweep_id", "dual_exposure"), (9, "sweep_index", 3),
                   (14, "electronic_gain_scale", 2), (19, "absolute_frame_index", 1),
                   (21, "sequence_seed", 1), (22, "sequence_role", "reset"), (23, "ei_label", 800))
        for index, key, value in changes:
            with self.subTest(index=index, key=key):
                self.rejects_summary(lambda s, i=index, key=key, value=value:
                                     s["frames"][i].__setitem__(key, value))
        self.rejects_summary(lambda s: s["frames"][0]["component_seeds"].__setitem__("photo", 94003))

    def test_all_four_sweep_records_bind_order_values_gains_and_merge(self):
        self.rejects_summary(lambda s: s["sweeps"].pop())
        self.rejects_summary(lambda s: s["sweeps"].reverse())
        for index in range(4):
            for key in ("fixture_names", "exposures_s", "frame_seeds", "electronic_gain_scales"):
                with self.subTest(index=index, key=key):
                    self.rejects_summary(lambda s, i=index, key=key: s["sweeps"][i][key].pop())
        for index, key, value in ((0, "variable", "electronic_gain_scale"), (1, "high_gain_dn_per_e", [1, 1, 1]),
                                  (2, "single_gain_dn_per_e", [.5, 2]), (3, "low_gain_dn_per_e", [.5, 1]),
                                  (3, "merge_start_e", [600, 600]), (3, "merge_end_e", [900, 900]),
                                  (0, "ei_policy", "gain_mapping")):
            with self.subTest(index=index, key=key):
                self.rejects_summary(lambda s, i=index, key=key, value=value: s["sweeps"][i].__setitem__(key, value))

    def test_sequence_schedule_indices_ei_and_complete_result_identity(self):
        self.rejects_summary(lambda s: s["sequences"].pop())
        self.rejects_summary(lambda s: s["sequences"].reverse())
        for index in range(3):
            for key, value in (("sequence_seed", 0), ("role", "unknown"), ("ei_policy", "electronic_gain"),
                               ("temporal_policy", "correlated_frames"), ("rng_generator", "unspecified")):
                with self.subTest(index=index, key=key):
                    self.rejects_summary(lambda s, i=index, key=key, value=value: s["sequences"][i].__setitem__(key, value))
        for key, value in (("stride", 1), ("modulus", 2**31), ("maximum_frame_index", 2**26 + 1),
                           ("minimum_frame_index", 0), ("expression", "seed+index")):
            self.rejects_summary(lambda s, key=key, value=value: s["sequences"][0]["seed_schedule"].__setitem__(key, value))
        self.rejects_summary(lambda s: s["sequences"][0].__setitem__("frame_seeds", [4294967200, 4294967264, 0]))
        self.rejects_summary(lambda s: s["sequences"][1].__setitem__("frame_indices", [1]))
        self.rejects_summary(lambda s: s["sequences"][2].__setitem__("matches_primary_names", list(NAMES[18:20])))
        self.rejects_summary(lambda s: s["sequences"][2].__setitem__("ei_label", [800, 800]))
        self.bundles[NAMES[22]]["result"]["retained_component_changed"] = True
        with self.assertRaisesRegex(verifier.ArtifactError, "complete matching frame physics"):
            verifier.verify_demo(self.demo)

    def test_configuration_geometry_and_map_values_not_labels_bind_results(self):
        controls = [lambda s: s["frames"][0]["configuration"].__setitem__("full_well_e", 3001),
                    lambda s: s["frames"][0]["configuration"].__setitem__("gain_dn_per_e", 2),
                    lambda s: s["frames"][7]["geometry"].__setitem__("active_roi", [1, 1, 4, 5]),
                    lambda s: s["frames"][0]["noise_model"]["prnu"][0].__setitem__(0, 1),
                    lambda s: s["frames"][1]["noise_model"]["dark_current_e_per_s"][0].__setitem__(0, 0),
                    lambda s: s["frames"][0]["noise_model"]["shared"]["fixed_offset_e"][0].__setitem__(0, 0),
                    lambda s: s["frames"][0]["noise_model"].__setitem__("realization_id", "same-map-label")]
        for index, mutation in enumerate(controls):
            with self.subTest(index=index):
                self.rejects_summary(mutation)
        # A matching forged summary and decoded map cannot evade the separate
        # analytical fixture definition just by retaining the map's label.
        for key in ("configuration", "geometry", "noise_model"):
            with self.subTest(also_decoded=key):
                original = deepcopy(self.bundles[NAMES[0]])
                changed = deepcopy(self.summary)
                target = "full_well_e" if key == "configuration" else "pixel_pitch_m" if key == "geometry" else "reference_temperature_K"
                self.bundles[NAMES[0]]["result"][key][target] += 1
                changed["frames"][0][key][target] += 1
                write_json(self.manifest, changed)
                with self.assertRaisesRegex(verifier.ArtifactError, "analytical"):
                    verifier.verify_demo(self.demo)
                self.bundles[NAMES[0]] = original
                write_json(self.manifest, self.summary)

    def test_coverage_counts_moments_and_claimed_coverage_flags_recomputed(self):
        for index, key in ((8, "single_adc_low_clipped_pixels"), (9, "single_adc_high_clipped_pixels"),
                           (10, "physical_saturation_pixels"), (11, "high_adc_low_clipped_pixels"),
                           (11, "low_adc_low_clipped_pixels"), (12, "high_clipped_low_usable_pixels"),
                           (12, "merge_transition_pixels"), (17, "low_high_clipped_before_well_pixels")):
            self.rejects_summary(lambda s, i=index, key=key: s["frames"][i]["coverage"].__setitem__(key, 0))
        for key in ("minimum_expected_e", "maximum_expected_e", "sum_expected_e"):
            self.rejects_summary(lambda s, key=key: s["frames"][0].__setitem__(key, s["frames"][0][key] + 1))
        for key in CHECKS:
            self.rejects_summary(lambda s, key=key: s["fixture_checks"].__setitem__(key, False))
            self.rejects_summary(lambda s, key=key: s["fixture_checks"].__setitem__(key, 1))
        self.bundles[NAMES[8]]["result"]["readout"]["adc_low_clipped"] = [False] * 48
        changed = deepcopy(self.summary)
        changed["frames"][8]["coverage"]["single_adc_low_clipped_pixels"] = 0
        write_json(self.manifest, changed)
        with self.assertRaisesRegex(verifier.ArtifactError, "coverage/equality"):
            verifier.verify_demo(self.demo)

    def test_units_assumptions_runtime_and_source_associations_reject_changes(self):
        for key in UNITS:
            self.rejects_summary(lambda s, key=key: s["units"].__setitem__(key, "unspecified"))
        for key, value in (("parameter_classification", "measured"), ("reference_temperature_K", 300),
                           ("ei_policy", "physical_gain_mapping"), ("reproducibility", "cross_runtime"),
                           ("temperature_policy", "temperature_law"), ("completion_scope", "generation_only")):
            self.rejects_summary(lambda s, key=key, value=value: s.__setitem__(key, value))
        for key in ("repository_head", "isetcam_head", "isethdrsensor_head"):
            self.rejects_summary(lambda s, key=key: s["provenance"].__setitem__(key, "2" * 40))
            self.rejects_summary(lambda s, key=key: s["provenance"].__setitem__(key, ""))
        self.rejects_summary(lambda s: s["provenance"].__setitem__("meaning", "proof of clean source"))
        self.rejects_summary(lambda s: s["runtime"].__setitem__("version", "different-runtime"))
        with self.assertRaisesRegex(verifier.ArtifactError, "numerical evidence"):
            verifier.verify_demo(self.demo, {**OBSERVED_SOURCE, "repository_head": "2" * 40}, OBSERVED_ENGINE)
        with self.assertRaisesRegex(verifier.ArtifactError, "numerical evidence"):
            verifier.verify_demo(self.demo, OBSERVED_SOURCE, (ENGINE["name"], "different-runtime"))

    def test_each_decoded_bundle_must_match_summary_source_and_runtime(self):
        for key in ("source", "runtime", "metadata"):
            saved = deepcopy(self.bundles[NAMES[23]])
            if key == "source":
                self.bundles[NAMES[23]][key]["repository_head"] = "2" * 40
            elif key == "runtime":
                self.bundles[NAMES[23]][key] = (ENGINE["name"], "other")
            else:
                self.bundles[NAMES[23]][key]["provenance"]["meaning"] = "forged association"
            with self.subTest(key=key), self.assertRaisesRegex(verifier.ArtifactError, "source/runtime association"):
                verifier.verify_demo(self.demo)
            self.bundles[NAMES[23]] = saved

    def test_missing_extra_symlink_and_hardlinked_actual_entries_reject(self):
        extra = self.demo / "extra"
        extra.write_bytes(b"extra actual file")
        with self.assertRaisesRegex(verifier.ArtifactError, "missing/extra"):
            verifier.verify_demo(self.demo)
        extra.unlink()
        target = self.demo / NAMES[-1] / "data.bin"
        saved = target.read_bytes()
        target.unlink()
        with self.assertRaisesRegex(verifier.ArtifactError, "Missing/unreadable"):
            verifier.verify_demo(self.demo)
        source = self.demo / NAMES[0] / "structured.json"
        target.symlink_to(source)
        with self.assertRaisesRegex(verifier.ArtifactError, "single-link non-symlink"):
            verifier.verify_demo(self.demo)
        target.unlink()
        os.link(source, target)
        with self.assertRaisesRegex(verifier.ArtifactError, "single-link non-symlink"):
            verifier.verify_demo(self.demo)
        target.unlink()
        target.write_bytes(saved)
        files, _ = verifier.verify_demo(self.demo)
        self.assertEqual(len(files), 49)

    def test_strict_summary_json_rejects_duplicates_nonfinite_truncation_and_wrong_types(self):
        original = self.manifest.read_text(encoding="utf-8")
        malformed = (original.replace('"phase":4', '"phase":4,"phase":4', 1),
                     original.replace('"frame_count":24', '"frame_count":NaN', 1),
                     original[:-4], "[]", "null", "1", "true")
        for text in malformed:
            with self.subTest(text=text[:40]):
                self.manifest.write_text(text, encoding="utf-8")
                with self.assertRaises(verifier.ArtifactError):
                    verifier.verify_demo(self.demo)
        self.manifest.write_text(original, encoding="utf-8")


class Phase4DemoOutputAssociationTests(DemoFilesMixin, unittest.TestCase):
    """Report boundary is artificial; verification, hashing and repeat I/O are real."""

    def setUp(self):
        super().setUp()
        validation = self.root / "validation"
        validation.mkdir()
        self.report = validation / "phase4-validation.json"
        write_json(self.report, {"artificial_report_boundary": True})
        self.report_result = (deepcopy(OBSERVED_SOURCE), OBSERVED_ENGINE, 401, 135, 62)
        patcher = mock.patch.object(verifier, "check_numerical_report", return_value=self.report_result)
        self.report_check = patcher.start()
        self.addCleanup(patcher.stop)

    def repeat(self):
        repeat = self.root / "demo-repeat"
        shutil.copytree(self.demo, repeat)
        return repeat

    def test_real_distinct_repeat_files_hash_and_association_control(self):
        repeat = self.repeat()
        result = verifier.verify_outputs(self.root, SOURCE["repository_head"], repeat)
        self.report_check.assert_called_once_with({"artificial_report_boundary": True}, SOURCE["repository_head"])
        self.assertEqual(result["artifact_count"], 49)
        self.assertEqual(len(result["artifact_sha256"]), 49)
        self.assertEqual(result["numerical_test_groups"], 401)
        self.assertIs(result["compared_demo_byte_identical"], True)
        self.assertEqual(self.decoded_names, list(NAMES) * 2)
        self.assertIs(result["input_source_authenticated"], False)
        self.assertIs(result["random_stream_reproduced"], False)
        for limitation in ("numerical execution", "source cleanliness", "process independence", "PRNG origin"):
            self.assertIn(limitation, result["verification_boundary"])

    def test_same_resolved_symlink_and_dot_alias_repeat_directories_reject(self):
        with self.assertRaisesRegex(verifier.ArtifactError, "distinct resolved"):
            verifier.verify_outputs(self.root, compare_dir=self.demo)
        linked = self.root / "linked-repeat"
        linked.symlink_to(self.demo, target_is_directory=True)
        with self.assertRaisesRegex(verifier.ArtifactError, "symlinks"):
            verifier.verify_outputs(self.root, compare_dir=linked)
        with self.assertRaisesRegex(verifier.ArtifactError, "Dot segments"):
            verifier.verify_outputs(self.root, compare_dir=str(self.root) + "/./demo")

    def test_real_same_name_and_cross_filename_hardlink_repeats_reject(self):
        repeat = self.repeat()
        for relative in (Path(NAMES[0]) / "data.bin", Path(NAMES[5]) / "structured.json"):
            target = repeat / relative
            saved = target.read_bytes()
            target.unlink()
            os.link(self.demo / NAMES[0] / "data.bin", target)
            self.assertEqual(os.stat(target).st_ino, os.stat(self.demo / NAMES[0] / "data.bin").st_ino)
            with self.subTest(relative=relative), self.assertRaisesRegex(verifier.ArtifactError, "single-link"):
                verifier.verify_outputs(self.root, compare_dir=repeat)
            target.unlink()
            target.write_bytes(saved)

    def test_distinct_repeat_with_changed_actual_bytes_rejects(self):
        repeat = self.repeat()
        target = repeat / NAMES[0] / "data.bin"
        target.write_bytes(target.read_bytes() + b"changed actual repeated bytes")
        with self.assertRaisesRegex(verifier.ArtifactError, "byte-identical"):
            verifier.verify_outputs(self.root, compare_dir=repeat)

    def test_report_source_and_runtime_bind_both_primary_and_repeat(self):
        self.report_check.return_value = ({**OBSERVED_SOURCE, "repository_head": "2" * 40}, OBSERVED_ENGINE, 401, 135, 62)
        with self.assertRaisesRegex(verifier.ArtifactError, "numerical evidence"):
            verifier.verify_outputs(self.root)
        self.report_check.return_value = (OBSERVED_SOURCE, (ENGINE["name"], "another-runtime"), 401, 135, 62)
        with self.assertRaisesRegex(verifier.ArtifactError, "numerical evidence"):
            verifier.verify_outputs(self.root)
        self.report_check.return_value = self.report_result
        repeat = self.repeat()
        summary = deepcopy(self.summary)
        summary["runtime"]["version"] = "another-runtime"
        write_json(repeat / "phase4-demo-summary.json", summary)
        with self.assertRaisesRegex(verifier.ArtifactError, "numerical evidence"):
            verifier.verify_outputs(self.root, compare_dir=repeat)

    def test_failed_report_gate_prevents_any_demo_inspection_and_cli_success(self):
        self.report_check.side_effect = verifier.ArtifactError("injected failed numerical report gate")
        output, errors = io.StringIO(), io.StringIO()
        with redirect_stdout(output), redirect_stderr(errors):
            code = verifier.main([str(self.root)])
        self.assertEqual(code, 1)
        self.assertEqual(output.getvalue(), "")
        self.assertIn("FAIL: injected failed numerical report gate", errors.getvalue())
        self.decoder.assert_not_called()

    def test_demo_failure_main_exit_cannot_be_replaced_by_stale_passed_json(self):
        stale = self.root / "prior-success.json"
        stale.write_text('{"status":"passed","release_accepted":true}\n', encoding="utf-8")
        before = stale.read_bytes()
        self.summary["verified_frame_count"] = 23
        write_json(self.manifest, self.summary)
        output, errors = io.StringIO(), io.StringIO()
        with redirect_stdout(output), redirect_stderr(errors):
            code = verifier.main([str(self.root)])
        self.assertEqual(code, 1)
        self.assertEqual(output.getvalue(), "")
        self.assertIn("FAIL:", errors.getvalue())
        self.assertEqual(stale.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
