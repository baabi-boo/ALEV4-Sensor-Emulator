# Phase 3 geometry and optics contract

This design freezes the Phase 3 interfaces before numerical implementation.
Acceptance status is recorded separately in the completion report. The starting
revision is `620b72e1fd9f0d63637c9a96d536113fc6f87d75`. Before numerical edits,
strict dependency checks, all 47 Python tests and the complete Phase 2/Phase 1
numerical prerequisite passed locally with GNU Octave 9.4.0. The starting
revision's three GitHub workflows also passed. Baseline execution is retained
under `outputs/baseline` during development and does not establish Phase 3.

## Geometry and readout binding (Slice 3A)

`createSensorGeometry(overrides)` is a separate versioned schema with
`full_grid_size` [rows columns], one-based `active_roi` [row column height width],
square `pixel_pitch_m`, `origin_xy_m` [x y], `full_grid_cfa_pattern`, and
`parameter_sources` (source-register IDs). Generic defaults remain small and
assumed. `alexa35Geometry` is an opt-in geometry-only profile using published
Open Gate dimensions/pitch; source and assumption labels remain distinct.

`sensorGrid(geometry)` returns active edges/centres and physical extents. X
increases with columns and y with rows. Column c has centre x0+(c-0.5)p;
row r has centre y0+(r-0.5)p. ROI offsets preserve both parities of the full
Bayer tile. No full-frame coordinate mesh or Bayer allocation is needed to
describe a small crop. Reject invalid ROI, unsupported numeric ranges, overflow,
and coordinates where floating-point arithmetic collapses adjacent sites.
The maximum admitted relative edge-spacing error is 1e-6; coordinate ULPs
must also be below this fraction of pitch. This numerical support limit
prevents large translated origins from changing the effective footprint
while charge integration still uses nominal pitch squared.

`bindSensorGeometry(readout,geometry,mode)` supports explicit `derive` and
`validate` modes. Derive copies the validated single/dual configuration and
changes only image size, pitch, and CFA pattern (inside `.sensor` for dual).
Validate rejects conflicts. Neither modifies caller data or existing schemas.
Noise identity is required for a full-grid identity operation with unchanged
shape and seed; independently simulated smaller noisy crops need not equal
crops of full-frame random arrays.

## Spatial irradiance and overlap (Slice 3B)

`createSpatialGrid` describes strictly increasing finite x/y cell edges in
metres. Input H-by-W-by-K values are cell-average spectral photon irradiance,
in photons/(m2 s nm), never RGB values or photon counts. Wavelength bins come
from the readout and must match K exactly.

`resampleSensorIrradiance(irradiance,grid,geometry)` computes rectangular
area-overlap averages over complete active photosite footprints. Per-axis
weights are overlap length divided by target width. Two separable sparse
operators avoid a full source-by-target 2D matrix. Input coverage is mandatory;
no extrapolation, edge clamping, or undocumented renormalization is allowed.
Identical edge grids use an exact identity path.

Weighted sampling and nonidentity convolution reject positive subnormal input
or output values and positive support erased to zero. Their reduced precision
can otherwise cause large relative errors even in a constant field. Exact
identity/aligned-copy paths preserve representable subnormal data unchanged.

The output remains density. Existing spectral integration applies p squared,
fill factor, exposure, QE, and spectral width once. The footprint is not also
shrunk by fill factor. Area-weighted integral conservation applies to the same
physical region; a crop is compared with that crop's source integral.

## Synthetic optical PSF and MTF (Slice 3C)

`createOpticalPsf` validates finite nonnegative, normalized discrete weights,
an explicit kernel `origin_rc`, physical `spacing_yx_m`, and shared/per-bin
spectral association. Unit mass is admitted within
`32 * coefficient_count * eps(1)`; supplied weights are never silently
renormalized. DC/flat-field comparisons include that admitted mass error and
summation roundoff. `applyOpticalPsf(irradiance,grid,psf)` filters pre-PSF
spectral planes before the CFA and retains only complete kernel support.
Its returned grid tracks the origin-dependent supported crop. The input must
be uniformly sampled and match PSF spacing; nonuniform cells must be rejected.
An identity kernel is an exact no-op. No boundary kernel is renormalized.

For kernel h indexed relative to its origin, output at (r,c) is
sum h(i,j)*input(r-(i-origin_r),c-(j-origin_c)). The retained original indices
run from kernel_size-origin+1 through input_size-origin+1. This supports even
and asymmetric kernels without hiding convolution/correlation reversal.

`opticalMtf` reports a direct discrete Fourier transform using frequencies in
cycles/metre and the declared origin. Optical magnitude is separate from the
ideal continuous square-aperture sinc factor; the latter is an analytical
reference, not a claim that every discretized sampler has that exact response.
Declare Nyquist bounds, kernel support, finite truncation, and assumptions.
The binomial kernel [1/4 1/2 1/4] provides an independent cosine oracle.

## Integration and ISETCam (Slices 3D/3E)

`simulateSpatialExposure` validates a geometry-bound readout, an explicitly
pre-PSF or post-optics input, performs the declared operations, and calls the
unchanged single/dual exposure API. Deterministic spatial helpers consume no
random numbers. The wrapper preserves caller RNG state, including failures.
Already computed ISET optical images are post-optics and must not receive an
implicit second PSF. The restricted adapter must state its sample semantics,
reconstruction approximation, physical extent, generic QE, and convergence
evidence, and fail when required dependencies or supported fixtures are absent.

`isetPointGrid` defines a piecewise bilinear reconstruction of native optical
point samples. Every interior native knot must appear among the output cell
edges, so each cell average is the exact mean of its four reconstructed
corners. No extrapolation is supported. Normalization, interpolation and
averaging reject ranges that lose relative precision or erase positive support.
An interior edge must retain positive normal fractions to both enclosing
knots without rounding to an endpoint; extreme coordinates outside this
representation are explicitly unsupported. Exact constant fields can still
preserve representable subnormal values through the scale-normalized path.

Phase 3 uses a new higher-level `ALEV4-SYNTHETIC-SPATIAL` versioned manifest.
It binds input samples/edges, geometry, source records, PSF samples, operation
order, spectral mapping, output samples and existing readout payloads through
hashes and strict metadata. Phase 1 and Phase 2 binary contracts remain intact.
Independent Python verification checks bytes and small scalar spatial oracles,
not only producer success flags. Fresh-process repeats must be distinct paths.

## Acceptance boundaries

Implement Slice 3A with independent tests and review its passing result before
introducing the resampler/PSF. Later gates cover exact overlaps, conservation,
noninteger ratios, offset/crop cases, impulse/edge/sinusoidal fixtures, DFT
agreement, restricted nonuniform ISET comparison and refinement, invalid inputs,
RNG restoration, strict artifacts, and failure-report invalidation. Retain all
Phase 1/2 numerical, artifact, and repeat gates and clean pinned dependencies.
An isolated core pass never constitutes full Phase 3 acceptance.

The source register is [PHASE3_SOURCES.md](PHASE3_SOURCES.md). This remains an
uncalibrated independent model. Native MATLAB, actual ARRI QE/OLPF/readout,
physical calibration, and full-frame throughput are not established by these
small synthetic numerical experiments.
