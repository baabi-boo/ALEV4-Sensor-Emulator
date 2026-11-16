# Phase 4 usage: structured noise and readout

This guide describes the implemented synthetic model. Complete release
acceptance is pending; the [development record](development/phase4/README.md)
tracks executed checks and source associations. A successful example is not
complete phase acceptance. All new parameter values and maps are assumed.
Native MATLAB execution remains unverified.

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

Inspect `components`, `active_maps` and `readout` to separate expected charge,
collected charge, stored charge, signed readouts, ADC clipping, conservative
rail usability and reconstruction validity. The earlier merge's limitations
near noisy transitions and rail fallback still apply.

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
are supported-size checks, not peak-memory or throughput guarantees. Use small
fixtures or crops; a supported full-grid geometry does not establish practical
full-frame simulation. Performance measurements and calibrated camera
characterization remain later work.
