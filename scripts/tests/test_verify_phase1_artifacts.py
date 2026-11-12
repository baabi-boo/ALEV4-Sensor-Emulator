"""Artificial format fixtures, not actual simulation evidence."""
import importlib.util
import json
import math
import os
import shutil
import struct
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("artifact_verifier", Path(__file__).resolve().parents[1] / "verify_phase1_artifacts.py")
verifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verifier)


def write_json(path, value):
    path.write_text(json.dumps(value, separators=(",", ":")), encoding="utf-8")


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="phase1-format-test-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        (self.root / "demo").mkdir()
        (self.root / "validation").mkdir()
        self.report = self.root / "validation" / "phase1-validation.json"
        self.summary = self.root / "demo" / "phase1-demo-summary.json"
        source = dict(repository_head="1"*40, isetcam_head="2"*40, isethdrsensor_head="3"*40, meaning="Artificial unit fixture")
        engine = dict(name="GNU Octave", version="8.4.0")
        cfg = dict(schema_version="1.0", image_size=[2, 4], wavelength_nm=[500, 600], bin_width_nm=[10, 20],
                   qe=[[.2, .4, .6], [.2, .4, .6]], pixel_pitch_m=5e-6, fill_factor=1, full_well_e=1000,
                   read_noise_e=3, gain_dn_per_e=1, black_level_dn=64, adc_bits=12, cfa_pattern="RGGB", shot_noise=True)
        iset = dict(status="passed", max_relative_error=1e-7, relative_tolerance=5e-5)
        report = dict(schema_version="1.0", phase=1, status="passed", phase1_passed=True, calibrated_alev4=False,
                      runtime="GNU Octave", runtime_version="8.4.0", provenance=source)
        report.update({name: dict(status="passed", test_count=1) for name in verifier.GATES})
        report["iset"].update(first_exposure=iset, second_exposure=iset)
        write_json(self.report, report)
        frames = []
        for index, name in enumerate(sorted(verifier.NAMES)):
            exposure = .01*verifier.BRACKETS.get(name, 1)
            # Independent hand result: area25e-12 * flux1e12 * bandwidth30 * BayerQE .4 = 300 e-/s.
            expected = 0 if name == "black" else 300*exposure
            values = list(range(64, 72))
            kind = "exposure_bracket" if name in verifier.BRACKETS else "iset_scene_to_raw" if name == "iset_scene" else "fixture"
            frame = dict(name=name, kind=kind, raw_file=name+".raw", metadata_file=name+".json", preview_file=name+".pgm",
                         image_size=[2, 4], exposure_s=exposure, seed=index, mean_expected_electrons=expected,
                         mean_collected_electrons=expected, collected_variance_e2=1, shot_residual_variance_e2=1,
                         mean_raw_dn=67.5, full_well_saturation_fraction=0, adc_low_clipping_fraction=0,
                         adc_high_clipping_fraction=0, raw_roundtrip_exact=True)
            meta = dict(format="ALEV4-SYNTHETIC-RAW", schema_version="1.0", sample_type="uint16", byte_order="little-endian",
                        layout="row-major", units="DN", algorithm_version="phase1-baseline-v1", sampler_version="Poisson-Knuth-PTRS-v1",
                        synthetic=True, calibrated=False, authentic_arriraw=False, height=2, width=4, byte_count=16,
                        sensor=cfg, cfa_origin=[1, 1], cfa_pattern="RGGB", exposure_s=exposure, seed=index, runtime=engine, provenance=source)
            (self.root / "demo" / frame["raw_file"]).write_bytes(struct.pack("<8H", *values))
            write_json(self.root / "demo" / frame["metadata_file"], meta)
            header = b"P5\n# Synthetic Bayer mosaic; linear ADC scaling, no demosaic\n4 2\n255\n"
            (self.root / "demo" / frame["preview_file"]).write_bytes(header+bytes(math.floor(255*v/4095+.5) for v in values))
            frames.append(frame)
        write_json(self.summary, dict(schema_version="1.0", demo_complete=True, synthetic=True, calibrated_alev4=False,
                   authentic_arriraw=False, provenance=source, runtime=engine, iset_integration=iset, sensor=cfg,
                   photon_density_per_m2_s_nm=1e12, reference_exposure_s=.01,
                   exposure_multipliers=list(verifier.BRACKETS.values()), frame_count=10, frames=frames))

    def mutate(self, path, callback):
        value = json.loads(path.read_text())
        callback(value)
        write_json(path, value)

    def rejects(self):
        with self.assertRaises(verifier.ArtifactError):
            verifier.verify_outputs(self.root)

    def test_good_and_independent_formula(self):
        result = verifier.verify_outputs(self.root, expected_commit="1"*40)
        self.assertEqual(result["artifact_count"], 31)
        self.assertAlmostEqual(result["analytical_flat_means_e"]["flat"], 3)
        self.assertAlmostEqual(result["analytical_flat_means_e"]["exposure_400x"], 12)

    def test_exact_repeat(self):
        repeat = self.root / "repeat"
        shutil.copytree(self.root / "demo", repeat)
        self.assertTrue(verifier.verify_outputs(self.root, repeat)["compared_demo_byte_identical"])
        self.mutate(repeat / "phase1-demo-summary.json", lambda v: v.update(description="different bytes"))
        with self.assertRaisesRegex(verifier.ArtifactError, "byte-identical"):
            verifier.verify_outputs(self.root, repeat)

    def test_repeat_cannot_compare_same_directory_or_alias(self):
        demo = self.root / "demo"
        alias = self.root / "demo-alias"
        alias.symlink_to(demo, target_is_directory=True)
        comparisons = (demo, demo / ".", demo / ".." / "demo",
                       Path(os.path.relpath(demo)), alias)
        for comparison in comparisons:
            with self.subTest(comparison=str(comparison)):
                with self.assertRaisesRegex(verifier.ArtifactError, "distinct demo directory"):
                    verifier.verify_outputs(self.root, comparison)

    def test_failed_or_missing_gate(self):
        original = self.report.read_bytes()
        for change in (lambda v: v.update(phase1_passed=False), lambda v: v.pop("raw_io"), lambda v: v["core"].update(passed=False)):
            self.report.write_bytes(original)
            self.mutate(self.report, change)
            self.rejects()

    def test_configuration_and_spectral_gates_are_required(self):
        original = self.report.read_bytes()
        for gate in ("config_edges", "spectral_properties"):
            self.assertIn(gate, verifier.GATES)
            for failure in ("missing", "passed_false", "status_failed"):
                with self.subTest(gate=gate, failure=failure):
                    self.report.write_bytes(original)
                    value = json.loads(original)
                    if failure == "missing":
                        value.pop(gate)
                    elif failure == "passed_false":
                        value[gate]["passed"] = False
                    else:
                        value[gate]["status"] = "failed"
                    write_json(self.report, value)
                    with self.assertRaisesRegex(verifier.ArtifactError, gate):
                        verifier.verify_outputs(self.root)

    def test_source_mismatch(self):
        with self.assertRaises(verifier.ArtifactError):
            verifier.verify_outputs(self.root, expected_commit="4"*40)
        self.mutate(self.root / "demo" / "black.json", lambda v: v["provenance"].update(isetcam_head=""))
        self.rejects()

    def test_traversal(self):
        original = self.summary.read_bytes()
        for name in ("../outside.raw", "/tmp/outside.raw", "C:\\outside.raw", "nested/../../outside.raw"):
            self.summary.write_bytes(original)
            self.mutate(self.summary, lambda v: v["frames"][0].update(raw_file=name))
            self.rejects()

    def test_symlink(self):
        raw = self.root / "demo" / "black.raw"
        target = self.root / "outside.raw"
        raw.rename(target)
        raw.symlink_to(target)
        self.rejects()

    def test_raw_size_and_range(self):
        path = self.root / "demo" / "black.raw"
        original = path.read_bytes()
        for content in (original[:-1], original+b"x", b"\xff\xff"+original[2:]):
            path.write_bytes(content)
            self.rejects()

    def test_preview(self):
        path = self.root / "demo" / "black.pgm"
        path.write_bytes(path.read_bytes()[:-1]+b"\xff")
        self.rejects()

    def test_analytic_mean_not_trusted(self):
        self.mutate(self.summary, lambda v: next(f for f in v["frames"] if f["name"] == "flat").update(mean_expected_electrons=4))
        self.rejects()

    def test_format_and_config(self):
        path = self.root / "demo" / "black.json"
        original = path.read_bytes()
        for change in (lambda v: v.update(synthetic=False), lambda v: v.update(cfa_origin=[0, 0]), lambda v: v.update(byte_order="big-endian"),
                       lambda v: v["sensor"].update(qe=[[2, 0, 0], [2, 0, 0]]), lambda v: v.update(height=True)):
            path.write_bytes(original)
            self.mutate(path, change)
            self.rejects()

    def test_invalid_json(self):
        for content in ('{"status":"passed","status":"failed"}', '{"x":NaN}'):
            self.report.write_text(content)
            self.rejects()


if __name__ == "__main__":
    unittest.main()
