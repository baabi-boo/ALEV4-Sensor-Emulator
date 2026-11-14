"""Artificial file-format fixtures; these are never simulation evidence."""
import json
import math
import struct

NAMES = ('dark', 'shadow', 'transition', 'highlight', 'saturation', 'noisy')


def write_json(path, value):
    path.write_text(json.dumps(value, separators=(',', ':')), encoding='utf-8')


def make_outputs(root):
    """Construct deterministic test bytes without calling verifier production code."""
    demo, validation = root / 'demo', root / 'validation'
    demo.mkdir(parents=True)
    validation.mkdir()
    source = dict(repository_head='1'*40, isetcam_head='2'*40,
                  isethdrsensor_head='3'*40, meaning='Artificial unit-test fixture')
    engine = dict(name='GNU Octave', version='9.4.0')
    frames = []
    for position, name in enumerate(NAMES):
        noisy = name == 'noisy'
        sensor = dict(schema_version='1.0', image_size=[17, 257], wavelength_nm=550,
                      bin_width_nm=10, qe=[.5, .5, .5], pixel_pitch_m=1e-6,
                      fill_factor=1, full_well_e=30000, read_noise_e=3,
                      gain_dn_per_e=.5, black_level_dn=64, adc_bits=16,
                      cfa_pattern='RGGB', shot_noise=noisy)
        cfg = dict(schema_version='2.0', sensor=sensor,
                   high_gain=dict(gain_dn_per_e=4, read_noise_e=1 if noisy else 0,
                                  black_level_dn=64, adc_bits=12),
                   low_gain=dict(gain_dn_per_e=.1, read_noise_e=5 if noisy else 0,
                                 black_level_dn=64, adc_bits=12),
                   merge=dict(start_e=600, end_e=900))
        expected, highs, lows, merged, flags = [], [], [], [], []
        for index in range(17 * 257):
            target = (400 + 4*(index % 257)) if name == 'transition' else {
                'dark': 0, 'shadow': 10, 'highlight': 12000,
                'saturation': 40000, 'noisy': 250}[name]
            expected.append(target)
            # Deliberate non-random variation for parser tests, not claimed noise evidence.
            charge = 240 + 20*(index % 2) if noisy else min(target, 30000)
            high_unclipped = math.floor(4*charge + 64 + .5)
            high = min(4095, high_unclipped)
            low = math.floor(charge/10 + 64 + .5)
            h, l = (high-64)/4, (low-64)*10
            t = min(1, max(0, (l-600)/300))
            weight = (1 - 3*t*t + 2*t*t*t) if high < 4095 else 0
            estimate = weight*h + (1-weight)*l
            flag = (1 if target >= 30000 else 0) | (4 if high_unclipped > 4095 else 0)
            flag |= (32 if 0 < high < 4095 else 0) | 64
            if target < 30000:
                flag |= 128
            highs.append(high); lows.append(low); merged.append(estimate); flags.append(flag)
        files = dict(high_raw=name+'.high.raw', low_raw=name+'.low.raw',
                     merged_electrons=name+'.merged.f64', flags=name+'.flags.u8')
        for key, code, values in [('high_raw', 'H', highs), ('low_raw', 'H', lows),
                                  ('merged_electrons', 'd', merged), ('flags', 'B', flags)]:
            (demo / files[key]).write_bytes(struct.pack('<'+str(len(values))+code, *values))
        metadata = dict(format='ALEV4-SYNTHETIC-DUAL-GAIN', schema_version='1.0',
                        algorithm_version='phase2-dual-gain-v1', synthetic=True,
                        calibrated_alev4=False, authentic_arriraw=False,
                        configuration=cfg, image_size=[17, 257], exposure_s=.01,
                        seed=201+position, input_units='photons m^-2 s^-1 nm^-1',
                        array_order='row-major', byte_order='little-endian', cfa_origin='top-left (1,1)',
                        files=files, units=dict(high_raw='DN', low_raw='DN',
                        merged_electrons='electrons', flags='bitmask'), runtime=engine, provenance=source)
        write_json(demo / (name+'.json'), metadata)
        count = len(flags)
        frames.append(dict(name=name, metadata_file=name+'.json', exposure_s=.01,
                           seed=201+position, mean_expected_electrons=sum(expected)/count,
                           mean_merged_electrons=math.fsum(merged)/count,
                           full_well_saturation_fraction=sum(bool(x & 1) for x in flags)/count,
                           high_adc_clipping_fraction=sum(bool(x & 6) for x in flags)/count,
                           low_adc_clipping_fraction=0,
                           reconstruction_valid_fraction=sum(bool(x & 128) for x in flags)/count))
    summary = dict(schema_version='1.0', phase=2, demo_complete=True, synthetic=True,
                   calibrated_alev4=False, authentic_arriraw=False, runtime=engine,
                   provenance=source, frame_count=6, frames=frames)
    write_json(demo / 'phase2-demo-summary.json', summary)
    phase1 = dict(schema_version='1.0', phase=1, status='passed', phase1_passed=True,
                  calibrated_alev4=False, runtime=engine['name'], runtime_version=engine['version'],
                  provenance=source)
    for key in ('core', 'config_edges', 'spectral_properties', 'input_representation',
                'fixture_edges', 'numerical_edges', 'poisson_edges', 'raw_io',
                'demo_contract', 'provenance_tests', 'iset'):
        phase1[key] = dict(status='passed', test_count=1)
    phase1['iset'].update(first_exposure=dict(status='passed', max_relative_error=1e-7,
                                           relative_tolerance=5e-5),
                         second_exposure=dict(status='passed', max_relative_error=1e-7,
                                              relative_tolerance=5e-5))
    report = dict(schema_version='1.0', phase=2, status='passed', phase2_passed=True,
                  phase1_required=True, calibrated_alev4=False, provenance=source,
                  runtime=engine['name'], runtime_version=engine['version'], phase1=phase1)
    for key in ('core', 'config_edges', 'noise', 'raw_io', 'numerical_edges',
                'spectral_properties', 'demo_contract'):
        report[key] = dict(status='passed', passed=True, test_count=1,
                           tests=[dict(name='artificial_fixture', status='passed', passed=True)])
    write_json(validation / 'phase2-validation.json', report)
    return report, summary
