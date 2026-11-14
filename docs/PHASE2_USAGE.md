# Using the simultaneous dual-gain model

Phase 2 adds two electronic readouts of one collected-charge realization.
All defaults are illustrative. The model and its files remain synthetic and
uncalibrated; they do not establish proprietary ALEV4 behavior or ARRIRAW.
See the [numerical contract](PHASE2_DESIGN.md) and
[bundle format](PHASE2_ARTIFACTS.md) for the exact interfaces and assumptions.

## Requirements and complete acceptance commands

Use Git, Python 3.10 or newer, and GNU Octave with the image package for the
existing ISETCam prerequisite. The standalone numerical model does not need
a statistics package. Native MATLAB remains a separate execution target;
source compatibility alone is not a MATLAB validation pass.

From the repository root, initialize the pinned dependencies and run:

```bash
git submodule update --init --recursive --depth 1
python3 scripts/verify_submodules.py --require-checkout
python3 -m unittest discover -s scripts/tests -v
octave --no-gui --quiet --eval "addpath('matlab'); report=run_phase2_tests('outputs/phase2/validation',true); assert(report.phase2_passed);"
python3 scripts/test_phase2_runner_failure.py
octave --no-gui --quiet --eval "addpath('matlab'); setup_project(false); phase2_demo('outputs/phase2/demo');"
octave --no-gui --quiet --eval "addpath('matlab'); setup_project(false); phase2_demo('outputs/phase2/demo-repeat');"
python3 scripts/verify_phase2_artifacts.py outputs/phase2 --expected-commit "$(git rev-parse HEAD)" --compare-dir outputs/phase2/demo-repeat
python3 scripts/verify_submodules.py --require-checkout
```

The two demonstration invocations intentionally use separate processes and
distinct fresh directories with independent files. Comparing a directory with
itself, or using hardlinks to any primary artifact in the repeated set, is
rejected even when the filenames differ. Existing bundle or summary paths
are refused.
Choose a new output root for a subsequent acceptance run instead of replacing
unreviewed outputs. The numerical runner itself replaces its validation JSON
and invalidates any previous success before running new tests.

`run_phase2_tests` includes the complete Phase 1 numerical/ISETCam prerequisite
and preserves its nested report. The original Phase 1 workflow also continues
to run its separate RAW/demo/repeat gates. For local complete release acceptance,
run those [Phase 1 artifact commands](PHASE1_USAGE.md) as well; a Phase 2
numerical report alone does not claim that the Phase 1 demo was regenerated.

For a smaller numerical development check:

```matlab
addpath('matlab');
report = run_phase2_tests('outputs/phase2-core', false);
assert(strcmp(report.status, 'core_only'));
assert(~report.phase2_passed);
```

Skipping the earlier phase deliberately leaves full Phase 2 numerical
acceptance false. Missing dependencies, failed tests, and malformed artifacts
raise errors; they are never recorded as passing skips. Full independent
verification requires `phase1_required=true` and the passing nested Phase 1
report, with matching runtime and source provenance.

## Start from expected electrons

This entry point isolates readout behavior from spectral integration:

```matlab
addpath('matlab');
cfg = alev4.createDualGainSensor(struct('sensor', ...
    struct('image_size', [2 3], 'shot_noise', false), ...
    'high_gain', struct('read_noise_e', 0), ...
    'low_gain', struct('read_noise_e', 0)));
mu = [0 10 750; 12000 30000 40000];
result = alev4.applyDualGainNoise(mu, cfg, 123);
disp(result.high_gain.raw_dn);
disp(result.low_gain.raw_dn);
disp(result.merged.electrons);
disp(result.reconstruction_valid);
```

The 12000-electron highlight exceeds the high-gain ADC range and remains
recoverable through low gain. At 30000 and 40000 expected electrons the
common photodiode reaches full well; low gain can report a valid numeric
code but cannot restore the lost incident signal. `reconstruction_valid`
therefore excludes those pixels. The exact physical-saturation boundary is
stored charge greater than or equal to the configured well capacity.

For noisy simulation, enable `cfg.sensor.shot_noise` and set each path's
`read_noise_e`. Both readout arrays contain the same shot-noise realization,
with independent downstream Gaussian noise. An explicit seed reproduces
results within the same runtime/version and leaves the caller's RNG state
unchanged. Cross-runtime identical random streams are not promised.

Use 2–16 bits for either Phase 2 ADC. Configure a merge interval below both
physical full well and high-gain saturation, allowing the extra half-low-gain
quantization step specified in the [numerical contract](PHASE2_DESIGN.md).
`createDualGainSensor` validates this margin automatically. For example, with
the otherwise default electronics and low black level `64.6`, an interval
`1000..1007` electrons rejects because the recorded low channel can still be
inside the blend when high gain reaches its rail. These limits protect the
noiseless handoff; they do not promise unbiased or unclipped noisy samples.

## Start from a spectral irradiance image

The input is sensor-plane photon irradiance, not a JPEG, scene radiance, or
display RGB image. Each spectral sample is a bin-average density in
photons/(m² s nm). This small one-bin example has an analytically known
12000-electron expectation:

```matlab
cfg = alev4.createDualGainSensor(struct('sensor', struct( ...
    'image_size', [4 8], 'wavelength_nm', 550, 'bin_width_nm', 10, ...
    'qe', [0.5 0.5 0.5], 'pixel_pitch_m', 1e-6, 'fill_factor', 1, ...
    'shot_noise', false), ...
    'high_gain', struct('read_noise_e', 0), ...
    'low_gain', struct('read_noise_e', 0)));
exposure_s = 0.01;
irradiance = (12000 / 5e-14) * ones(4, 8);
result = alev4.simulateDualGainExposure(irradiance, cfg, exposure_s, 123);
```

The factor `5e-14` is exposure × pixel area × fill factor × QE × bin width.
Multiple spectral bins and all four Bayer phases use the same integration
helper as Phase 1. Electronic parameters belong under `high_gain` and
`low_gain`; misplaced nondefault electronic settings under `sensor` reject.

## Export, read, and merge recorded channels

The bundle exporter requires a complete spectral simulation result, including
exposure and input units. Expected-electron-only results are useful numerical
inputs but do not carry this spectral provenance. Choose a portable file stem
without colon or backslash; the supplied base path must contain no
U+0000–U+001F control characters. Ordinary parent-directory separators and a
platform-valid Windows drive prefix remain path syntax.

```matlab
mkdir('outputs/my-dual-frame');
base = fullfile('outputs', 'my-dual-frame', 'highlight');
files = alev4.exportDualGainBundle(result, cfg, base);
[decoded, metadata] = alev4.readDualGainBundle(base);
merged = alev4.mergeDualGain(decoded.high_gain.raw_dn, ...
    decoded.low_gain.raw_dn, metadata.configuration);
assert(isequal(merged.electrons, decoded.merged.electrons));
```

Each bundle contains two row-major little-endian uint16 ADC planes, signed
float64 merged electrons, diagnostic/validity flags, and a JSON manifest.
The reader checks configuration, byte counts, ADC ranges, flags, and the
merge reconstructed independently from recorded channels. It rejects original
JSON keys that would be normalized or duplicated, including escaped-key
duplicates. File-identity checks use Octave `lstat` or MATLAB's JVM when
available; native MATLAB execution remains unverified. The independent Python
verifier is required for complete artifact acceptance. No demosaic, white
balance, display rendering, or LogC encoding is applied.

`merged.valid` means at least one recorded code is away from both ADC rails.
`reconstruction_valid` additionally excludes the simulator's known physical
well saturation. A RAW-only merge cannot infer that physical history. When
both channels are at rails, a finite low-path estimate remains for portable
storage, accompanied by `valid=false`; applications must consult this mask.

The quantization margin protects the noiseless handoff at the high channel's
**upper rail**. It does not guarantee a monotonic estimate across every lower
ADC rail fallback change. With a high black offset of `0` DN and low black offset
of `0.51` DN, for example, a coarse low-path estimate can fall from `4.9` to
`0.25` electrons when the high code first leaves zero. Both selected estimates
remain within their respective half-step quantization uncertainty, and the
validity mask remains true because a nonrail observation is available. Treat
validity as availability of a usable recorded channel, not exact recovery or
camera calibration; see the [merge contract](PHASE2_DESIGN.md).

## What the demonstration establishes

The six fixed frames cover dark, shadow, transition, highlight, full-well
saturation, and a noisy flat field. Python decodes the actual files, computes
the deterministic fixture expectations, reconstructs merge weights and
electrons, checks the summary, and compares repeated output bytes. Numerical
tests separately measure shared shot covariance and independent read noise.

The model does not claim optimal statistical fusion: its documented smoothstep
weight depends on the observed low-gain channel and can introduce selection
bias near the transition. Structured fixed-pattern noise, rolling readout,
calibrated optics, color processing, and real-camera characterization remain
later phases.
