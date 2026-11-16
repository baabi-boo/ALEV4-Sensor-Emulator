# Phase 4 structured-noise design

Status: implementation contract; acceptance is not yet claimed.

This phase implements explicit synthetic fixed maps, separately seeded noise
components, independent temporal frames, and exposure/electronic-gain sweeps.
All parameter magnitudes are assumed. There is no measured ALEV4 calibration,
temperature law, random fixed-map generator, autoregressive process, rolling
shutter, or claim of measured flicker/1/f noise in this version.

## Interfaces and compatibility

- `createStructuredNoise(full_grid_size, overrides)` constructs or validates a
  separate versioned model. Existing sensor and geometry schemas stay intact.
- `structuredNoiseMaps(model, geometry)` selects fixed values using one-based
  full-grid ROI coordinates. Scalars mean explicitly uniform full-grid maps.
- `simulateStructuredExposure(input, readout, exposure_s, frame_seed, model,
  geometry)` validates geometry binding. Disabled models directly return the
  corresponding legacy single/dual result, without added fields or RNG draws.
- `simulateStructuredSpatialExposure(input, input_grid, geometry, readout,
  exposure_s, frame_seed, model, options)` delegates directly to the legacy
  spatial API when disabled. Enabled operation preserves its validated spatial
  baseline and applies structured readout to its sampled irradiance, with a new
  result identity. The retained baseline is verification context, not a second
  physical exposure contributing charge to the structured result.
- `simulateNoiseSequence(input, readout, exposures_s, sequence_seed, model,
  geometry, options)` uses explicit absolute frame indices and a documented
  seed schedule. Independent frames are the only temporal model. Resetting or
  continuing a sequence is a pure function of its identity and frame indices.
  EI is metadata only; physical exposure and electronic gains are explicit.

The enabled model has its own random-stream contract. Its shot/read realizations
need not equal legacy seeded realizations. A zero-valued added component must
not perturb the other enabled-model component streams. Disabled whole-result
identity is tested separately for single, dual, and spatial calls.

## Fixed configuration

The strict model fields are `schema_version`, `enabled`, `full_grid_size`,
`realization_id`, `reference_temperature_K`, `prnu`,
`dark_current_e_per_s`, `dark_shot_noise`, `shared`, `single`, `high_gain`,
`low_gain`, and `parameter_sources`. Defaults are enabled, unit PRNU, zero
dark rate and added electronic components, and an explicit assumed identity.

Each named electronic component contains `fixed_offset_e`, `row_noise_e`,
`column_noise_e`, and `frame_noise_e`. Fixed offsets are signed input-referred
electrons, scalar or full-grid matrices. The three noise magnitudes are
nonnegative RMS electrons. PRNU is a nonnegative achromatic response multiplier
with nominal reference one, never silently normalized; a supplied zero denotes
an unresponsive photosite. Dark-current rates are nonnegative electrons per
photosite per second. Temperature is only the declared applicability condition.

Supplied maps define the persistent realization; `realization_id` is a label,
not proof of map identity. Artifacts bind actual map bytes and active crops.
Model creation and ROI extraction consume no randomness and do not mutate caller
values. Unknown fields, malformed dimensions, nonfinite values, unsupported
arithmetic, negative rates/RMS, and mismatched full grids reject.

The constructor inventories the complete merged model before numeric scans or
sparse-to-dense conversion, rejecting more than 100 million represented
numeric/logical values even for disabled models. Sparse arrays count their full
represented size; repeated retained fields count separately regardless of
runtime storage sharing.

Before normalizing readout/model descriptors or expanding active maps, an
enabled direct exposure reserves 64 values per active pixel plus its spectral
input, model/configuration/geometry inventory, and 64 compact metadata values.
The fixed allowance covers retained seeds, scalar component values, exposure
and result flags even for a one-pixel ROI. Its raw preflight also reserves 32
values for missing model defaults; readout binding requires a complete readout.
The authoritative check uses canonical settings. Enabled spatial calls reserve
both the legacy baseline and structured result before sampling: descriptor inventories, four source-cube
counts, and `128 + 2*B` values per active pixel, where `B` is the configured
spectral-bin count. The raw check is repeated using validated configuration.
The descriptor allowance includes both configurations/geometries/input grids,
the complete model, PSF/options/provenance, and compact reports. Reservations
above 100 million values reject; these conservative checks cover diagnostics
and working arrays without guaranteeing peak memory or full-frame throughput.

Disabled direct/spatial calls retain legacy readout limits after ordinary model
validation. Sequences preflight descriptors and a retained-frame lower bound
before allocating index vectors or frames, then inventory the first complete
frame to bound the entire sequence before producing the remaining frames.
Enabled and disabled sequences both limit aggregate retained numeric/logical
contents to 100 million values. Bundles independently count their actual stored
values; passing a bundle-size bound does not bypass simulation reservations.

## Stage order and retained values

1. The existing integration calculates baseline photoelectron expectation
   `mu0`, applying area, fill factor, exposure, QE and spectral widths once.
2. Expected photocharge is `mu_photo = active_prnu .* mu0`. Expected dark
   charge is `mu_dark = active_dark_rate .* exposure_s`.
3. Photocharge is Poisson sampled when the existing sensor's `shot_noise` is
   true. Dark charge is separately Poisson sampled when `dark_shot_noise` is
   true. Otherwise each component equals its expectation. Named streams isolate
   these choices from each other and from electronic components.
4. Add photo and dark charge, then clip once at the physical full well. Both
   electronic paths observe this identical stored-charge array.
5. Add signed shared fixed, row, column and frame components after the well;
   add the corresponding path's components and existing per-pixel read noise.
   One row draw is shared across columns, one column draw across rows, and one
   frame draw across the whole frame. Gaussian components are mutually separate
   except where the model explicitly declares a shared component.
6. Apply each path's existing DN/electron gain and black offset exactly once,
   round, and clip at the ADC. Never clip signed read electrons to the well.
7. For dual gain, call the unchanged observed-channel merge with RAW and
   configuration only. Retain physical saturation and reconstruction validity
   separately from ADC clipping and conservative rail validity.

The enabled result retains its canonical configuration/geometry/model, input,
baseline expectation, active maps, component draws, signed readouts, RAW,
operation order, seeds, units, and synthetic/uncalibrated classification.
Expected or component arrays support verification; they never correct the merge.

## Temporal and statistical contract

Fixed maps persist across frames and crops. Stochastic crop/full-frame values
are not promised to match. A sequence records absolute frame indices, each
frame seed, exposure seconds, EI labels, and its independent-frame policy.
Continuation reproduces the same absolute indices without hidden mutable state.
There is no elapsed-time dependence or camera firmware EI policy.

The fixed stream schedule is `component_seed = mod(frame_seed + tag, 2^32)`:
photo 1, dark 2, shared row/column/frame 10/11/12, single
row/column/frame/pixel 20/21/22/23, high 30/31/32/33 and low 40/41/42/43.
Each component resets a local saved/restored Twister state. Sequence frame
`i` uses `mod(sequence_seed + 64*(i-1), 2^32)` for absolute indices
1 through 2^26. This packs distinct component seeds without overlap within
one supported sequence; adjacent seed values are a synthetic PRNG policy,
not a claim of mathematical or cross-runtime independence. Different sequence
identities may overlap streams. Fixed maps have no random seed because they
are explicitly supplied. All accepted seeds are integers 0 through 2^32-1.

Tests predeclare finite-sample tolerances for Poisson moments, same-row and
same-column covariance, shared versus path-specific covariance, independent
frame differences and temporal autocovariance. Wrong-model controls must exceed
the same bounds. Fixed-pattern cancellation, zero endpoints, both ADC rails,
merge transitions and physical saturation have independent analytical checks.

## Artifact and release contract

Enabled results use `ALEV4-SYNTHETIC-STRUCTURED-NOISE`, version 1.0, with a
separate exporter/reader and independent Python verifier. Legacy artifact
identifiers and validators remain unchanged. Fixed full-grid maps, retained
components and outputs use bounded, row-major little-endian payloads with strict
shape/type/unit descriptors and hashes. Verification reconstructs map cropping,
expectations, charge assembly, physical clipping, signed electronics, ADC and
observed-channel merge; recomputing a hash cannot legitimize altered semantics.

Complete release acceptance requires clean exact source and dependency pins;
all preserved Phase 1–3 gates; Phase 4 deterministic/statistical/invalid-input,
RNG/crop/sequence checks; independent file and corruption checks; separate-process
demos and repeat comparisons; runner failure controls; and observed CI results.
Development runs remain visibly nonrelease. Native MATLAB is unverified until
its relevant gates actually execute. The source register and final completion
record will distinguish implemented, executed, and deferred behavior.
