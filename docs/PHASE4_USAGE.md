# Phase 4 usage: structured noise and readout

This guide describes the implemented synthetic model. Clean candidate
`ad036efe6bb6d298545055df37cc4b4681c3e8da` passed all 20 acceptance gates,
400 numerical groups and 316 Python tests in GNU Octave 9.4.0 locally and
8.4.0 in CI, with independently verified demo/repeat pairs and CI artifacts.
The [completion report](PHASE4_COMPLETION.md), [retained evidence](evidence/phase4/README.md)
and [development record](development/phase4/README.md) identify those executions
and distinguish the later test-only decimal-diagnostic correction
(14 focused groups in Octave 9.4.0). A successful example alone is not complete
phase acceptance. All new parameter values and maps are assumed. Native MATLAB
execution remains unverified.

## Runtime and complete verification

Use Git, Python 3.10 or newer, and GNU Octave with the image package. Initialize
the two pinned submodules for the complete inherited ISET requirements:

```bash
git clone --branch master https://github.com/baabi-boo/ALEV4-Sensor-Emulator.git
cd ALEV4-Sensor-Emulator
git submodule update --init --recursive --depth 1
python3 scripts/verify_submodules.py --require-checkout
python3 scripts/run_phase4_acceptance.py --output-root outputs/phase4-acceptance
```

The aggregate command requires a clean identified source revision and a new
output directory. It runs all nine Phase 4 numerical suites, the complete
Phase 3/2/1 numerical and ISET prerequisites, Python tests, all four runner
failure controls, four demos and separate-process repeats, independent artifact
verification, and dependency checks before and after execution. There are 20
command gates. Missing suites, runtimes or dependencies fail.

Use `--development` for an edited checkout. It executes the same gates but
always leaves `release_accepted=false`. `--expected-commit` accepts the exact
full current SHA; it does not accept branch names, abbreviated hashes or an
explicit empty value. `--octave` selects a numerical executable. Receipts bind
the source tree, commands, exits, repeat identities and artifact hashes.

## A small deterministic example

Run these MATLAB-language snippets in order from the repository root; later
snippets reuse the earlier variables. `setup_project(false)` enables the
standalone APIs used here. The corresponding native MATLAB execution remains
unverified.

```matlab
addpath('matlab');
setup_project(false);

g = alev4.createSensorGeometry(struct('full_grid_size',[4 6]));
c = alev4.createBaselineSensor(struct('shot_noise',false,'read_noise_e',0));
c = alev4.bindSensorGeometry(c,g,'derive');
n = alev4.createStructuredNoise([4 6],struct( ...
    'realization_id','ASSUMED-EXAMPLE-01', ...
    'prnu',reshape(1+(0:23)/200,4,6), ...
    'dark_current_e_per_s',12,'dark_shot_noise',false, ...
    'shared',struct('fixed_offset_e',-1), ...
    'single',struct('fixed_offset_e',0.5)));

dark = zeros(4,6,numel(c.wavelength_nm));
r = alev4.simulateStructuredExposure(dark,c,0.25,42,n,g);
assert(all(r.readout.expected_dark_electrons(:)==3));
assert(all(r.readout.charge_electrons(:)==3));
assert(all(r.readout.read_electrons(:)==2.5));
assert(all(r.readout.raw_dn(:)==65));

light = 1e12*ones(4,6,numel(c.wavelength_nm));
lit = alev4.simulateStructuredExposure(light,c,0.25,42,n,g);
```

Dark rate is in electrons per photosite per second, so this example collects
three dark electrons before electronic offsets. The signed shared and single
path offsets are added after the well. The default 0.5 DN/electron gain and
64 DN black level give `round(0.5*2.5 + 64) = 65` DN. PRNU affects photocharge,
not dark-current charge. `light` is spectral bin-average photon irradiance in
photons/(m² s nm), with one plane per configured wavelength bin; it is not RGB,
scene radiance or an already integrated photon count. The readout integrates
the configured bin widths, QE, photosite area, fill factor and exposure once.

Unspecified structured settings default to enabled, unit PRNU, zero dark rate
and zero added electronic components. Dark shot noise defaults to enabled;
photo shot noise and existing per-pixel read noise come from the readout
configuration. `reference_temperature_K` defaults to 293.15 K and records
applicability only; changing it does not apply a temperature-response law.
These defaults and the example's maps are assumed, uncalibrated parameters.

## Fixed maps and cropped geometry

Every PRNU, dark-rate and fixed-offset map is either a scalar denoting a
uniform full grid or an explicit full-grid matrix. The model never silently
normalizes, regenerates or resizes a map. Changing the active crop keeps a
photosite's fixed value and the geometry's Bayer parity:

```matlab
gc = alev4.createSensorGeometry(struct('full_grid_size',[4 6], ...
    'active_roi',[2 2 2 3]));
cc = alev4.bindSensorGeometry(c,gc,'derive');
maps = alev4.structuredNoiseMaps(n,gc);
assert(isequal(maps.prnu,n.prnu(2:3,2:4)));
crop = alev4.simulateStructuredExposure( ...
    1e12*ones(2,3,numel(cc.wavelength_nm)),cc,0.25,42,n,gc);
```

The direct exposure API expects already sampled irradiance for the active
photosites and validates the readout's geometry binding. A separately drawn
random crop is not promised to equal a crop of a larger random frame.

For optical filtering and conservative resampling, use the spatial wrapper:

```matlab
grid = alev4.createSpatialGrid(struct( ...
    'x_edges_m',(0:6)*g.pixel_pitch_m, ...
    'y_edges_m',(0:4)*g.pixel_pitch_m));
spatial = alev4.simulateStructuredSpatialExposure(light,grid,g,c, ...
    0.25,42,n,struct('input_stage','post_optics'));
```

Spatial options retain Phase 3 semantics. `post_optics` forbids a second PSF.
The default `pre_psf` mode uses an identity PSF when none is supplied; a supplied
kernel requires declared sampling, origin, spectral association and complete
support. The enabled result
retains an intact legacy `spatial_baseline` for verification and applies
structured readout to the sampled irradiance. That baseline contributes no
charge to the structured exposure. Its legacy numerical validity is also a
precondition; see the [spatial usage guide](PHASE3_USAGE.md).

## Simultaneous dual gain and structured electronics

```matlab
d = alev4.bindSensorGeometry(alev4.createDualGainSensor(),g,'derive');
nd = alev4.createStructuredNoise([4 6],struct( ...
    'dark_current_e_per_s',12, ...
    'shared',struct('row_noise_e',1,'frame_noise_e',0.5), ...
    'high_gain',struct('fixed_offset_e',0.25,'column_noise_e',0.75), ...
    'low_gain',struct('fixed_offset_e',-0.25,'column_noise_e',0.5)));
dual = alev4.simulateStructuredExposure(light,d,0.25,42,nd,g);
```

`shared`, `single`, `high_gain` and `low_gain` each have `fixed_offset_e`,
`row_noise_e`, `column_noise_e` and `frame_noise_e`. Offsets are signed electrons;
noise magnitudes are nonnegative RMS electrons. Existing per-pixel read noise
comes from the readout configuration. A row draw is constant across columns,
a column draw across rows, and a frame draw across the active image.

Photo and dark shot-noise switches are independent. Their sampled charges add
before one physical full well, shared by both gain paths. Shared electronics
also enter both paths; path electronics remain separate. The merge uses only
the recorded high/low RAW and configuration. It does not remove retained fixed
maps or component noise using simulated truth.

### Interpreting enabled-result diagnostics

The paths below are relative to the enabled result. `P` means `readout` for
single gain, or `readout.high_gain` / `readout.low_gain` for dual gain. Its
matching electronic component is `components.single`, `components.high_gain`
or `components.low_gain`, respectively. The common `readout` fields remain
outside the gain paths in dual mode.

| Field or path | Units | Meaning |
| --- | --- | --- |
| `baseline_expected_electrons` | electrons | Spectrally integrated photo expectation before PRNU, dark charge, sampling or clipping. |
| `active_maps.prnu` | dimensionless | Fixed photo-response multiplier at the active photosites. |
| `active_maps.dark_current_e_per_s` | electrons/s | Fixed dark-current rate at the active photosites. |
| `readout.expected_photoelectrons` | electrons | `baseline_expected_electrons .* active_maps.prnu`. |
| `readout.expected_dark_electrons` | electrons | `active_maps.dark_current_e_per_s * readout.exposure_s`. |
| `readout.expected_electrons` | electrons | `expected_photoelectrons + expected_dark_electrons`: total expected photo **plus dark** charge; the legacy expectation is photo-only. |
| `components.photo_electrons`, `components.dark_electrons` | electrons | Separately sampled charges; each equals its expectation when its shot-noise switch is off. |
| `readout.collected_electrons` | electrons | Sum of the photo and dark components before the physical well. |
| `readout.charge_electrons` | electrons | Stored charge: collected charge capped at the configured physical `full_well_e`. |
| `components.shared` and the matching path component | electrons | Retained `fixed_offset_e`, `row_e`, `column_e`, `frame_e`, `pixel_e` and their sum `total_e`; shared `pixel_e` is zero. |
| `P.read_electrons` | electrons | Signed stored charge plus shared and path electronics; no second full-well clipping. |
| `P.raw_dn` | DN (`uint16`) | Gain and black level applied to signed readout, then rounded and clamped to the ADC range. |
| `readout.full_well_saturated` | logical | Collected charge is **at or above** physical full well, before electronics. |
| `P.adc_low_clipped`, `P.adc_high_clipped` | logical | Rounded code is strictly below zero or above the maximum ADC code, respectively, before clamping. |
| `P.adc_usable` | logical | Recorded RAW is strictly between the ADC rails. A code exactly on either rail is unusable even without clipping. |
| `readout.merged.valid` | logical | Dual gain only: at least one recorded path is ADC-usable. |
| `readout.reconstruction_valid` | logical | ADC/merge usability with known physical full-well saturation excluded. |

For each path, `read_electrons = (charge_electrons + shared.total_e) +
path_component.total_e`. Let `q = round(read_electrons * gain_dn_per_e +
black_level_dn)` and `M = 2^adc_bits - 1`, using that path's configuration.
Then RAW is `uint16(min(max(q,0),M))`, clipping tests are `q < 0` and `q > M`,
and usability is `raw_dn > 0 & double(raw_dn) < M`. Single-gain
`reconstruction_valid` is
`readout.adc_usable & ~readout.full_well_saturated`; dual gain uses
`readout.merged.valid & ~readout.full_well_saturated`. If neither dual path is
usable, the merge retains a finite low-path estimate with `merged.valid=false`.
These definitions follow the [structured readout](../matlab/+alev4/simulateStructuredExposure.m)
and [RAW-only merge](../matlab/+alev4/mergeDualGain.m).

Retained component arrays are verification diagnostics, not corrections used
by the merge. PRNU is a declared phenomenological response multiplier, so even
`expected_photoelectrons` may exceed `expected_incident_photons`; total expected
charge also includes dark current. The earlier merge's limitations near noisy
transitions and rail fallback still apply.

## Independent frames, reset, continuation and EI

```matlab
seq = alev4.simulateNoiseSequence(light,d,[0.1 0.1 0.1],123,nd,g, ...
    struct('ei_label',800));
tail = alev4.simulateNoiseSequence(light,d,[0.1 0.1],123,nd,g, ...
    struct('start_frame',2,'ei_label',[400 1600]));
assert(isequal(seq.frames{2},tail.frames{1}));
assert(isequal(seq.frames{3},tail.frames{2}));
```

Exposure vectors contain one explicit number of seconds per frame. Use either
`start_frame` or a strictly increasing `frame_indices` vector; gaps are allowed.
Absolute indices range from 1 through 2²⁶. Resetting or continuing the same
arguments and absolute indices reproduces the same frames in the same runtime
and version. Supplied maps remain fixed.

Frame `i` uses `mod(sequence_seed+64*(i-1),2^32)`. The distinct named component
tags are documented in the [design](PHASE4_DESIGN.md). This schedule prevents
component-seed overlap within a supported sequence; it does not prove ideal
PRNG independence or cross-runtime identity. Caller RNG state is restored.

`ei_label` is absent (`[]`), a positive scalar, or one positive value per frame.
It changes metadata only. Change exposure seconds or explicit electronic gains
to run physical sweeps, and revalidate the dual configuration after gain changes.
No camera EI policy, temperature law, correlated temporal spectrum or rolling
shutter is inferred from these labels and indices.

## Disabled compatibility and bundles

A valid disabled model directly returns the corresponding legacy result, with
no wrapper fields or extra RNG draws. The wrapper still validates the model,
full-grid identity, geometry binding and supported seed:

```matlab
off = n; off.enabled = false;
old = alev4.simulateExposure(light,c,0.25,42);
disabled = alev4.simulateStructuredExposure(light,c,0.25,42,off,g);
assert(isequal(old,disabled));
```

For enabled single exposure, RAW is `result.readout.raw_dn`; for disabled
single exposure it is `result.raw_dn`. Direct dual-exposure RAW is likewise
under `result.readout.high_gain.raw_dn` and `result.readout.low_gain.raw_dn`
when enabled, or `result.high_gain.raw_dn` and `result.low_gain.raw_dn` when
disabled. A disabled spatial call returns the complete legacy spatial result,
which already has its own `readout` field. Disabled sequences contain legacy
frames inside their explicit sequence envelope, with
`structured_noise_enabled=false`. New bundle export accepts enabled exposure
or spatial-exposure results; export sequence frames individually.

```matlab
example_parent = fullfile(pwd,'outputs');
if ~isfolder(example_parent), mkdir(example_parent); end
bundle_directory = tempname(example_parent);
files = alev4.exportStructuredBundle(dual,bundle_directory);
[restored,metadata] = alev4.readStructuredBundle(files.directory);
assert(isequal(dual,restored));
disp(files.directory);
```

`tempname` supplies a fresh bundle destination without creating it; the exporter
creates that directory. Use an existing ordinary parent. The two-file
format preserves all retained values, classes, shapes, units and spatial
history. Its independent verifier reconstructs deterministic semantics from
actual bytes. It cannot authenticate a plausible stochastic draw's origin.
See the [artifact contract](PHASE4_ARTIFACTS.md) for bounds and ownership rules.
The command-line verifier below expects the complete Phase 4 report/demo tree.
For an individual bundle, Python callers can import `verify_bundle` from
`scripts/verify_phase4_artifacts.py` after adding `scripts` to the module path.

## Demonstrations and individual commands

`alev4.phase4Fixtures()` returns the 24 small assumed fixtures without writing files.
They cover deterministic PRNU/offsets, dark exposures, structured electronics,
spatial crops, four exposure/gain sweeps, and reset/continuation with changed EI
labels. `phase4_demo` exports and checks every frame before reporting completion.

```bash
octave --no-gui --quiet --eval "addpath('matlab'); r=run_phase4_tests('outputs/phase4/validation',true); assert(r.phase4_passed);"
python3 scripts/test_phase4_runner_failure.py
octave --no-gui --quiet --eval "addpath('matlab'); setup_project(false); phase4_demo('outputs/phase4/demo');"
octave --no-gui --quiet --eval "addpath('matlab'); setup_project(false); phase4_demo('outputs/phase4/demo-repeat');"
python3 scripts/verify_phase4_artifacts.py outputs/phase4 --compare-dir outputs/phase4/demo-repeat
```

Passing `false` to `run_phase4_tests` runs the nine standalone suites but leaves
`phase4_passed=false` and `status=core_only`. This is not release acceptance.

## Supported sizes and allocation checks

Phase 4 uses a 100,000,000 numeric/logical-value limit, including configuration,
flags, maps and retained diagnostics. The model constructor inventories all
represented values before expanding sparse maps, including for a disabled
model. A sparse matrix counts by its represented dimensions, not just its
nonzero entries. Repeated retained fields count separately even if the runtime
can share their physical storage.

Enabled direct exposures reserve the spectral input plus a conservative
64 values per active photosite, 64 compact metadata values, and the
model/configuration/geometry inventory before map expansion. The raw descriptor
check also reserves 32 values for missing model defaults. Enabled spatial calls
additionally reserve the entire legacy baseline, source and sampled cubes, PSF,
metadata and working arrays
before running the legacy sampler. Sequence descriptor checks reject an
obviously excessive request before creating frames; a complete first-frame
inventory then bounds all retained frames before the remaining frames run.
Disabled direct/spatial readout retains its legacy allocation behavior after
model validation; disabled sequences still have the sequence aggregate limit.

Bundles separately count every actual retained numeric/logical value and allow
at most 800,000,000 payload bytes. The conservative simulation reservation can
reject a request even when its eventual bundle would be smaller. These bounds
are supported-size checks, not peak-memory or throughput guarantees.

The Open Gate geometry profile supports a 4608×3164 full grid and crops within
it, but **enabled direct structured exposure of the fully active grid exceeds
the current guard**. Its 14,579,712 photosites require 933,101,568 reserved values
at 64 per photosite alone, before spectral input, maps or metadata; this already
exceeds the 100,000,000-value cap in
[`simulateStructuredExposure`](../matlab/+alev4/simulateStructuredExposure.m).
This follows from the guard and scalar arithmetic; no full-frame input was
allocated for that check. Use small fixtures or coordinate-preserving crops.
The [resource audit](development/phase4/agent-reports/w09_f.md) reports measured
acceptance costs and their limits. Full-frame execution/performance work remains
Phase 7, while calibrated camera characterization remains Phase 6; neither is
established by this geometry profile or by the small-fixture acceptance runs.
