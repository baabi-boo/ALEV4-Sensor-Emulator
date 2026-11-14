"""Corrupt independent artificial fixtures to exercise the Phase 2 evidence gate."""
import importlib.util
import json
import math
import os
from pathlib import Path
import shutil
import struct
import tempfile
import unittest

from phase2_fixture_support import make_outputs, write_json

SPEC = importlib.util.spec_from_file_location('phase2_artifacts',
    Path(__file__).resolve().parents[1] / 'verify_phase2_artifacts.py')
verifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verifier)


class Phase2ArtifactTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='phase2-format-test-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        make_outputs(self.root)
        self.report = self.root / 'validation/phase2-validation.json'
        self.summary = self.root / 'demo/phase2-demo-summary.json'
        self.meta = self.root / 'demo/shadow.json'

    def rejects_json(self, path, mutation):
        original = path.read_bytes()
        try:
            data = json.loads(original)
            mutation(data)
            write_json(path, data)
            with self.assertRaises(verifier.ArtifactError):
                verifier.verify_outputs(self.root)
        finally:
            path.write_bytes(original)

    def rejects_bytes(self, path, replacement):
        original = path.read_bytes()
        try:
            path.write_bytes(replacement(original))
            with self.assertRaises(verifier.ArtifactError):
                verifier.verify_outputs(self.root)
        finally:
            path.write_bytes(original)

    def test_complete_artificial_fixture_and_independent_numbers(self):
        receipt = verifier.verify_outputs(self.root, expected_commit='1'*40)
        self.assertEqual(receipt['artifact_count'], 31)
        self.assertEqual(receipt['numerical_test_groups'], 7)
        self.assertEqual(receipt['frames']['highlight']['mean_merged_electrons'], 12000)
        self.assertEqual(receipt['frames']['saturation']['reconstruction_valid_fraction'], 0)
        self.assertFalse(receipt['compared_demo_byte_identical'])

    def test_repeat_and_changed_bytes(self):
        repeat = self.root / 'repeat'
        shutil.copytree(self.root / 'demo', repeat)
        self.assertTrue(verifier.verify_outputs(self.root, repeat)['compared_demo_byte_identical'])
        with (repeat / 'phase2-demo-summary.json').open('ab') as handle:
            handle.write(b'\n')
        with self.assertRaisesRegex(verifier.ArtifactError, 'byte-identical'):
            verifier.verify_outputs(self.root, repeat)

    def test_same_directory_and_hardlinked_repeat_rejected(self):
        with self.assertRaises(verifier.ArtifactError):
            verifier.verify_outputs(self.root, self.root / 'demo')
        repeat = self.root / 'repeat'
        shutil.copytree(self.root / 'demo', repeat, copy_function=os.link)
        with self.assertRaisesRegex(verifier.ArtifactError, 'alias'):
            verifier.verify_outputs(self.root, repeat)

    def test_cross_filename_hardlinked_repeat_rejected(self):
        repeat = self.root / 'repeat'
        shutil.copytree(self.root / 'demo', repeat)
        target = repeat / 'dark.flags.u8'
        source = self.root / 'demo/shadow.flags.u8'
        self.assertEqual(target.read_bytes(), source.read_bytes())
        target.unlink()
        os.link(source, target)
        with self.assertRaisesRegex(verifier.ArtifactError, 'cross-filename aliases'):
            verifier.verify_outputs(self.root, repeat)

    def test_every_suite_required_and_individual_failures(self):
        for name in verifier.GATES:
            self.rejects_json(self.report, lambda d, n=name: d.pop(n))
            self.rejects_json(self.report, lambda d, n=name: d[n].update(passed=False))
        self.rejects_json(self.report, lambda d: d['core']['tests'][0].update(passed=False))
        self.rejects_json(self.report, lambda d: d['core'].update(test_count=2))
        self.rejects_json(self.report, lambda d: d.update(status='core_only', phase2_passed=False))

    def test_phase1_prerequisite_and_iset_required(self):
        for name in verifier.PHASE1_GATES:
            self.rejects_json(self.report, lambda d, n=name: d['phase1'].pop(n))
        self.rejects_json(self.report, lambda d: d['phase1'].update(phase1_passed=False))
        self.rejects_json(self.report, lambda d: d['phase1']['iset']['first_exposure'].update(max_relative_error=1))
        self.rejects_json(self.report, lambda d: d['phase1']['iset']['second_exposure'].update(relative_tolerance=1))

    def test_phase1_prerequisite_flag_must_be_literal_true(self):
        for value in (False, 'true', 'false', 1, None):
            self.rejects_json(self.report, lambda d, v=value: d.update(phase1_required=v))
        self.rejects_json(self.report, lambda d: d.pop('phase1_required'))

    def test_source_and_runtime_associations(self):
        with self.assertRaises(verifier.ArtifactError):
            verifier.verify_outputs(self.root, expected_commit='4'*40)
        self.rejects_json(self.meta, lambda d: d['provenance'].update(repository_head='4'*40))
        self.rejects_json(self.summary, lambda d: d['runtime'].update(version='different'))
        self.rejects_json(self.report, lambda d: d['phase1']['provenance'].update(isetcam_head='4'*40))

    def test_metadata_cannot_default_missing_parameters(self):
        for field in ('configuration', 'units', 'files', 'provenance', 'runtime'):
            self.rejects_json(self.meta, lambda d, f=field: d.pop(f))
        self.rejects_json(self.meta, lambda d: d['configuration']['high_gain'].pop('read_noise_e'))
        self.rejects_json(self.meta, lambda d: d['configuration']['sensor'].pop('shot_noise'))
        self.rejects_json(self.meta, lambda d: d['configuration']['sensor'].update(gain_dn_per_e=7))
        self.rejects_json(self.meta, lambda d: d['configuration']['merge'].update(end_e=2000))

    def test_config_requires_quantization_margin_and_usable_adc_codes(self):
        cfg = json.loads(self.meta.read_text())['configuration']
        cfg['low_gain']['black_level_dn'] = 64.6
        cfg['merge'].update(start_e=1000, end_e=1007)
        with self.assertRaisesRegex(verifier.ArtifactError, 'quantization margin'):
            verifier.config(cfg)
        # Fractional black itself remains supported with a completed handoff.
        cfg['merge'].update(start_e=600, end_e=900)
        self.assertEqual(verifier.config(cfg)['low_gain']['black_level_dn'], 64.6)
        # Without a two-bit minimum this nominally wider path has no nonrail code.
        cfg['low_gain'].update(adc_bits=1, black_level_dn=0, gain_dn_per_e=.0001)
        with self.assertRaisesRegex(verifier.ArtifactError, 'ADC bits'):
            verifier.config(cfg)

    def test_config_quantization_guard_uses_scale_relative_ulps(self):
        cfg = json.loads(self.meta.read_text())['configuration']
        high_rail = (4095-.5-64)/4
        half_step = .5/.1
        safe_end = high_rail-half_step-8*max(math.ulp(high_rail), math.ulp(half_step))
        cfg['merge'].update(start_e=1000, end_e=safe_end)
        self.assertEqual(verifier.config(cfg)['merge']['end_e'], safe_end)
        cfg['merge']['end_e'] = math.nextafter(safe_end, math.inf)
        with self.assertRaisesRegex(verifier.ArtifactError, 'quantization margin'):
            verifier.config(cfg)
        # Finite extreme scaling should not acquire an absolute one-electron epsilon.
        cfg = json.loads(self.meta.read_text())['configuration']
        cfg['high_gain']['gain_dn_per_e'] = 4e300
        cfg['low_gain']['gain_dn_per_e'] = 1e299
        cfg['merge'].update(start_e=6e-298, end_e=9e-298)
        self.assertEqual(verifier.config(cfg)['merge']['end_e'], 9e-298)

    def test_units_authenticity_and_layout(self):
        for field, value in [('synthetic', False), ('calibrated_alev4', True),
                             ('authentic_arriraw', True), ('byte_order', 'big-endian'),
                             ('array_order', 'column-major'), ('algorithm_version', 'phase1-baseline-v1')]:
            self.rejects_json(self.meta, lambda d, f=field, v=value: d.update({f: v}))
        self.rejects_json(self.meta, lambda d: d['units'].update(merged_electrons='DN'))

    def test_payload_lengths_adc_limits_and_merged_corruption(self):
        for suffix in ('.high.raw', '.low.raw', '.merged.f64', '.flags.u8'):
            path = self.root / ('demo/shadow'+suffix)
            self.rejects_bytes(path, lambda b: b[:-1])
            self.rejects_bytes(path, lambda b: b+b'\0')
        self.rejects_bytes(self.root / 'demo/shadow.high.raw', lambda b: b'\xff\xff'+b[2:])
        self.rejects_bytes(self.root / 'demo/shadow.merged.f64', lambda b: struct.pack('<d', 1234)+b[8:])
        self.rejects_bytes(self.root / 'demo/shadow.merged.f64', lambda b: struct.pack('<d', float('nan'))+b[8:])

    def test_flags_cannot_hide_rail_or_physical_saturation(self):
        self.rejects_bytes(self.root / 'demo/shadow.flags.u8', lambda b: bytes([b[0] ^ 32])+b[1:])
        self.rejects_bytes(self.root / 'demo/saturation.flags.u8', lambda b: bytes([b[0] | 128])+b[1:])
        self.rejects_bytes(self.root / 'demo/shadow.flags.u8', lambda b: bytes([b[0] | 4])+b[1:])

    def test_summary_is_recomputed_and_fixtures_fixed(self):
        self.rejects_json(self.summary, lambda d: d['frames'][1].update(mean_expected_electrons=999))
        self.rejects_json(self.summary, lambda d: d['frames'][1].update(mean_merged_electrons=999))
        self.rejects_json(self.summary, lambda d: d['frames'][0].update(name='shadow'))
        self.rejects_json(self.meta, lambda d: d.update(seed=999))
        self.rejects_json(self.meta, lambda d: d['configuration']['sensor'].update(qe=[.4, .4, .4]))

    def test_malformed_json_duplicates_nonfinite_and_booleans(self):
        self.rejects_bytes(self.meta, lambda b: b'\xff')
        self.rejects_bytes(self.meta, lambda b: b'{"synthetic":true,'+b[1:])
        self.rejects_bytes(self.meta, lambda b: b.replace(b'"exposure_s":0.01', b'"exposure_s":NaN'))
        self.rejects_json(self.meta, lambda d: d.update(seed=True))
        self.rejects_json(self.report, lambda d: d['core'].update(test_count=True))

    def test_unsafe_file_association_and_symlinks(self):
        for name in ('../shadow.high.raw', '/shadow.high.raw', 'other.high.raw', 'C:shadow.high.raw'):
            self.rejects_json(self.meta, lambda d, n=name: d['files'].update(high_raw=n))
        path = self.root / 'demo/shadow.high.raw'
        saved = self.root / 'saved.raw'
        path.rename(saved)
        path.symlink_to(saved)
        with self.assertRaises(verifier.ArtifactError):
            verifier.verify_outputs(self.root)

    def test_control_characters_rejected_even_for_existing_matching_files(self):
        for character in ('\0', '\t', '\n', '\r', '\x1f'):
            name = 'control'+character+'.raw'
            # POSIX permits many controls in filenames; the portable contract does not.
            if character != '\0':
                (self.root / name).write_bytes(b'fixture')
            with self.assertRaisesRegex(verifier.ArtifactError, 'Unsafe artifact filename'):
                verifier.safe_file(self.root, name, name)


if __name__ == '__main__':
    unittest.main()
