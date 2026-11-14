# Using the spatial geometry and optics layer

Phase 3 adds physical pixel geometry, conservative spatial averaging, an
explicit finite PSF/MTF model, and spatial bundles around the existing single-
and simultaneous dual-gain readouts. These interfaces are acceptance-tested at
source `beedd8bfd1cea3c722409ef0f959fcec5420c5f2`. The
[completion record](PHASE3_COMPLETION.md) retains the executed gates and evidence;
the complete gates below remain required for acceptance of a later source.
All examples are synthetic and uncalibrated.

The [design](PHASE3_DESIGN.md) defines the numerical model, the
[source register](PHASE3_SOURCES.md) distinguishes published geometry from
assumptions, and the [artifact contract](PHASE3_ARTIFACTS.md) defines files and
verification. Existing [Phase 1](PHASE1_USAGE.md) and
[Phase 2](PHASE2_USAGE.md) APIs and artifact formats remain available.

## Requirements

Run commands from the repository root. The standalone examples need MATLAB
or GNU Octave; full gates additionally need Git, Python 3.10 or newer, the
pinned ISETCam/ISETHdrsensor checkouts, and Octave's `image` package or MATLAB's
Image Processing Toolbox. A source-compatible MATLAB interface is not evidence
of an executed native MATLAB pass. Reproducibility is scoped to the recorded
runtime/version; identical random streams across MATLAB and Octave are not
promised.

```bash
git submodule update --init --recursive --depth 1
python3 scripts/verify_submodules.py --require-checkout
```

Use the appropriate executable in place of `octave`, or supply its path to the
acceptance runner's `--octave` option. `setup_project(false)` adds the standalone
core, examples, and tests; `setup_project(true)` also checks and enables the
pinned upstream paths. Missing required dependencies are errors.

## Coordinates, units, and collection

| Quantity | Meaning |
| --- | --- |
| `full_grid_size` | `[rows columns]` of the modeled full grid |
| `active_roi` | One-based `[first_row first_column height width]` inside that grid |
| `origin_xy_m` | `[x y]` of the full grid's outer upper-left corner, in metres |
| `pixel_pitch_m` | Positive square-pixel pitch in metres |
| `full_grid_cfa_pattern` | `RGGB`, `BGGR`, `GRBG`, or `GBRG`, anchored at full-grid `(1,1)` |
| `x_edges_m`, `y_edges_m` | Strictly increasing rectangular input-cell edges in metres |
| Input array | `[input_rows input_columns K]` cell-average photon irradiance, photons/(m² s nm) |
| Spectral configuration | `K` matching `wavelength_nm` centres, `bin_width_nm` widths, and effective R/G/B QE rows |
| Exposure and output | Seconds; expected/merged charge in electrons; recorded ADC values in DN |

X increases with columns and y with rows. Full-grid pixel `(r,c)` has centre
`[x0 + (c-0.5)*pitch, y0 + (r-0.5)*pitch]`. Cropping preserves the full-grid
Bayer parity: starting an `RGGB` grid at row 2, column 2 produces active
`BGGR`. The origin does not reset at a crop.

Spatial averaging integrates the piecewise-constant source over each complete
photosite footprint and returns an **average density**. The subsequent spectral
stage applies `pitch^2`, fill factor, exposure, QE, and spectral-bin widths
once. Do not multiply the input by pixel area or shrink the footprint by fill
factor. RGB values, display images, photon counts, and point samples are not
interchangeable with this input representation.

## Minimal single-gain exposure

This small crop uses one spectral bin and disables noise to make the expected
charge and ADC values directly checkable. An omitted PSF resolves to an explicit
identity PSF at the input-grid spacing.

```matlab
addpath('matlab');
setup_project(false);

geometry = alev4.createSensorGeometry(struct( ...
    'full_grid_size', [4 6], 'active_roi', [2 2 2 3], ...
    'pixel_pitch_m', 6e-6, 'origin_xy_m', [0 0], ...
    'full_grid_cfa_pattern', 'RGGB'));
pixels = alev4.sensorGrid(geometry);
grid = alev4.createSpatialGrid(struct( ...
    'x_edges_m', pixels.x_edges_m, 'y_edges_m', pixels.y_edges_m));

cfg = alev4.createBaselineSensor(struct( ...
    'wavelength_nm', 550, 'bin_width_nm', 20, 'qe', [0.5 0.5 0.5], ...
    'shot_noise', false, 'read_noise_e', 0));
cfg = alev4.bindSensorGeometry(cfg, geometry, 'derive');
input = 1e14 * ones(2, 3);              % photons/(m^2 s nm), K = 1
single_result = alev4.simulateSpatialExposure( ...
    input, grid, geometry, cfg, 0.01, 123);

assert(strcmp(cfg.cfa_pattern, 'BGGR'));
assert(isequal(size(single_result.readout.raw_dn), [2 3]));
assert(max(abs(single_result.readout.expected_electrons(:) - 288)) < 1e-10);
assert(all(single_result.readout.raw_dn(:) == 208));
```

Here the default fill factor is 0.8, gain is 0.5 DN/electron, and black offset
is 64 DN: `1e14 * 20 * 0.5 * (6e-6)^2 * 0.8 * 0.01 = 288` electrons,
followed by `round(288 * 0.5 + 64) = 208` DN.

`bindSensorGeometry(...,'derive')` copies a complete validated configuration
and sets only its active image size, pitch, and CFA. `'validate'` rejects any
conflict in those fields. The spatial wrapper defaults to validation; it never
silently repairs a conflicting binding. Its optional seventh argument accepts
only `input_stage`, `psf`, `binding_mode`, and `spatial_provenance`.

## Use the same spatial input with simultaneous dual gain

Continue from the preceding example. Put shared spectral and charge settings
under `sensor`, and readout settings under the two gain paths.

```matlab
shared = struct('wavelength_nm', 550, 'bin_width_nm', 20, ...
    'qe', [0.5 0.5 0.5], 'shot_noise', false);
dual_cfg = alev4.createDualGainSensor(struct('sensor', shared, ...
    'high_gain', struct('read_noise_e', 0), ...
    'low_gain', struct('read_noise_e', 0)));
dual_cfg = alev4.bindSensorGeometry(dual_cfg, geometry, 'derive');
dual_result = alev4.simulateSpatialExposure( ...
    input, grid, geometry, dual_cfg, 0.01, 123);

assert(isequal(dual_result.readout.expected_electrons, ...
    single_result.readout.expected_electrons));
disp(dual_result.readout.high_gain.raw_dn);
disp(dual_result.readout.low_gain.raw_dn);
disp(dual_result.readout.merged.electrons);
disp(dual_result.readout.reconstruction_valid);
```

The geometry binding is inside `dual_cfg.sensor`; the mode follows the readout
schema, so no separate mode flag is needed. For noisy runs enable
`sensor.shot_noise` and set each path's RMS `read_noise_e`. Both electronic paths
observe one sampled charge realization and one physical full well. The merge
uses recorded channels, and physical saturation remains distinct from ADC
clipping and channel validity. Do not pass the modified single-gain `cfg` above
as a dual `sensor`: its nondefault `read_noise_e` would be an ambiguous shared
electronic setting and is rejected. See the [Phase 2 contract](PHASE2_DESIGN.md).

## Add an explicit PSF and inspect its MTF

Optics acts on spectral planes before the CFA. A nontrivial kernel requires
an explicit one-based `origin_rc`, the coefficient representing zero
displacement. `spacing_yx_m` is `[row_spacing column_spacing]` in metres.
Weights must be finite, nonnegative, and already sum to one per plane.

This example adds one input cell of halo on each side of the active crop used
above. The 3-by-3 valid convolution leaves exactly its 2-by-3 supported field.

```matlab
p = geometry.pixel_pitch_m;
halo_grid = alev4.createSpatialGrid(struct( ...
    'x_edges_m', (0:5)*p, 'y_edges_m', (0:4)*p));
psf = alev4.createOpticalPsf(struct( ...
    'kernel', ([1; 2; 1] * [1 2 1])/16, ...
    'origin_rc', [2 2], 'spacing_yx_m', [p p]));
blurred = alev4.simulateSpatialExposure( ...
    1e14*ones(4, 5), halo_grid, geometry, cfg, 0.01, 123, ...
    struct('input_stage', 'pre_psf', 'psf', psf));
assert(isequal(size(blurred.optical_irradiance), [2 3]));

mtf = alev4.opticalMtf(psf, [0 1/(4*p) 1/(2*p)], 0, p);
assert(abs(mtf.optical_mtf(1, 2) - 0.5) < 1e-12);
disp(mtf.optical_mtf);                 % approximately [1 0.5 0]
```

The only boundary policy is `'valid'`: retain complete declared support,
including zero-valued border coefficients. For kernel size `[Kh Kw]` and
origin `[or oc]`, the required halo in input cells is
`[Kh-or, or-1, Kw-oc, oc-1]` for top, bottom, left, right. Even or asymmetric
kernels therefore need not have symmetric halos. The returned optical grid
tracks that support; every active footprint must remain fully covered.

PSF filtering requires uniform input cells matching its spacing. Conservative
sampling alone accepts nonuniform rectangular cells. To use an already
computed optical field, pass `struct('input_stage','post_optics')`; a nonempty
`psf` then raises an error. This also provides the explicit path for a
nonuniform post-optics grid. There is no extrapolation, edge clamping, grid
snapping, or renormalization of missing support.

An empty PSF `wavelength_nm` shares one kernel across all bins. A spectral
kernel bank must identify every input wavelength exactly and in order; no
spectral interpolation is implied. `opticalMtf(psf,fx,fy,pitch)` uses cycles per
metre within the PSF's x/y Nyquist bounds and returns arrays ordered
`[numel(fy) numel(fx) kernel_count]`. The optional pitch adds an ideal continuous
square-aperture sinc reference. It does not apply another spatial average or
establish the measured transfer of the discrete sampler.

## Published geometry and restricted ISETCam fixtures

`alev4.alexa35Geometry('RGGB')` creates a geometry-only Open Gate profile with
3164 rows, 4608 columns, and 6.075 micrometre nominal pitch. `'RGGB'` is an
explicit model choice for CFA origin. The optional second argument is an
experimental one-based ROI, for example
`alev4.alexa35Geometry('RGGB',[2 2 16 24])`. The profile does not supply measured
QE, PSF, electronics, hardware crop origins, optical-black dimensions, or total
die dimensions. The published and derived values are documented in the
[source register](PHASE3_SOURCES.md). Use small crops for initial experiments;
format size limits are not full-frame memory or throughput guarantees.

For a genuine pinned-ISETCam scene → optics → Bayer comparison:

```matlab
setup_project(true);
[iset_result, iset_cfg, iset_report] = ...
    alev4.isetSpatialFixture('checker', 83, 0.001);
assert(iset_report.passed);
assert(strcmp(iset_result.input_stage, 'post_optics'));
assert(isempty(iset_result.psf));
```

Supported fixture names are `'uniform'`, `'ramp'`, `'checker'`, and `'edge'`.
The adapter uses 16-by-16 square full-fill pixels and native sampling that does
not trigger an extra ISET Gaussian prefilter. It explicitly reconstructs ISET
optical **point samples** with a piecewise-bilinear field, converts that field
to cell averages, and compares fractional electrons and refinement behavior.
`isetPointGrid(points,x_samples,y_samples,x_edges,y_edges)` exposes that
conversion: retain every interior native knot in the cell edges and stay
inside native point support. Arbitrary optical-image import and measured ARRI
optics are outside this fixture's contract.

## Export and read a spatial bundle

Continue with the single/dual results above. The parent directory must exist;
each bundle destination must be new. Choose fresh paths when repeating this
example because existing files or directories are deliberately refused.

```matlab
bundle_parent = 'outputs/phase3-usage-bundles';
if ~isfolder(bundle_parent), mkdir(bundle_parent); end
alev4.exportSpatialBundle(fullfile(bundle_parent, 'single'), single_result);
alev4.exportSpatialBundle(fullfile(bundle_parent, 'dual'), dual_result);
[decoded, metadata] = ...
    alev4.readSpatialBundle(fullfile(bundle_parent, 'single'));
assert(isequal(decoded.readout.raw_dn, single_result.readout.raw_dn));
assert(strcmp(metadata.format, 'ALEV4-SYNTHETIC-SPATIAL'));
```

The bundle retains original/optical/sampled irradiance, expected electrons,
geometry, spectral settings, PSF coefficients when applicable, and unchanged
Phase 1 or Phase 2 readout payloads. `spatial.json` associates them through
SHA-256, shape, units, and operation order. Float64 spatial arrays use
little-endian, plane-major/row-major storage. Use the native spatial reader
instead of decoding the manifest and rounding coordinates yourself: Phase 3's
numeric-token decoder preserves the serialized physical edges.

Readers verify bytes and recompute spatial/spectral associations. Hashes detect
corruption and association errors; they do not authenticate measurements or
recover unrecorded noisy analog history. The format is synthetic and is not
ARRIRAW. See the [full artifact specification](PHASE3_ARTIFACTS.md).

## Development checks, complete demos, and acceptance

These command groups have different scopes. Use fresh demo and acceptance
directories for each run. The numerical runner rewrites its validation report
and first invalidates any prior successful status; inspect the current command's
exit status as well as its report.

### Standalone development checks

```bash
octave --no-gui --quiet --eval "addpath('matlab'); r=run_phase3_tests('outputs/phase3-core',false); assert(strcmp(r.status,'core_only')); assert(~r.phase3_passed);"
octave --no-gui --quiet --eval "addpath('matlab'); setup_project(false); s=phase3_demo('outputs/phase3-core-demo',false); assert(~s.demo_complete); assert(s.frame_count==7);"
```

Core-only numerical execution excludes the required Phase 2/Phase 1 and
nonuniform ISET gates, so `phase3_passed` stays false. The seven-fixture demo
omits `iset_checker` and records `demo_complete=false`. Neither is accepted by
the complete Phase 3 artifact verifier as release evidence.

### Full numerical and Phase 3 artifact checks

```bash
python3 -m unittest discover -s scripts/tests -v
octave --no-gui --quiet --eval "addpath('matlab'); r=run_phase3_tests('outputs/phase3/validation',true); assert(r.phase3_passed);"
python3 scripts/test_phase3_runner_failure.py --octave octave
octave --no-gui --quiet --eval "addpath('matlab'); setup_project(true); s=phase3_demo('outputs/phase3/demo',true); assert(s.demo_complete); assert(s.frame_count==8);"
octave --no-gui --quiet --eval "addpath('matlab'); setup_project(true); s=phase3_demo('outputs/phase3/demo-repeat',true); assert(s.demo_complete); assert(s.frame_count==8);"
python3 scripts/verify_phase3_artifacts.py outputs/phase3 --expected-commit "$(git rev-parse HEAD)" --compare-dir outputs/phase3/demo-repeat
```

The full numerical runner includes Phase 3 ISET fixtures and the complete
Phase 2/Phase 1 numerical prerequisites. The eight demo bundles are
`identity_single`, `flat_binomial`, `shifted_impulse`, `edge`, `sinusoid`,
`crop_cfa`, `dual_spatial`, and `iset_checker`.

The Python CLI expects a root containing `validation/phase3-validation.json`
and the complete `demo/` tree. It independently checks scalar convolution,
overlap, spectral integration, deterministic or observable readout behavior,
hashes, and evidence associations. `--compare-dir` additionally requires
distinct, nonaliased files with byte-identical contents. Separate Octave
invocations provide the fresh-process repetition. Python does not rerun ISET
or establish source cleanliness from an observed commit field.

### One command for all preserved release gates

From a clean, committed source checkout with the required dependencies:

```bash
python3 scripts/run_phase3_acceptance.py --octave octave --output-root outputs/phase3-release --expected-commit "$(git rev-parse HEAD)"
```

This runs dependency checks before and after execution, Python tests, complete
numerical gates, all three phases' runner-failure checks, and separate-process
demo/repeat plus independent artifact checks for **Phases 1, 2, and 3**. It
records commands, exit statuses, logs, reports, and hashes under the selected
output root, with the aggregate result in `acceptance.json`. The output root
must not already exist. The expected commit must match the checkout; release
mode also requires a clean worktree at the beginning and end and an unchanged
HEAD. Retain the resulting evidence and observed CI outcome for a release
claim; these instructions themselves establish no pass.

To exercise the same gates while implementation changes are uncommitted:

```bash
python3 scripts/run_phase3_acceptance.py --octave octave --output-root outputs/phase3-development --expected-commit "$(git rev-parse HEAD)" --development
```

`--development` permits a dirty source worktree but skips no scientific,
dependency, artifact, or repeat gate. A successful run records
`status='development_passed'` and `release_accepted=false`. Its observed HEAD
does not identify the uncommitted file contents, and even a clean development
run is not promoted to release acceptance. Missing gates or failed commands
still fail the run. Native MATLAB execution and real-camera calibration remain
separate, unestablished claims.
