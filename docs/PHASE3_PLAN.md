# Phase 3 plan: explicit geometry and tested optics

**Status: planned, not implemented or accepted by this document.** Start this
phase after the identified Phase 2 release gates pass. The next deliverable is
a spatial sensor model that feeds the existing single- and simultaneous
dual-gain readouts without changing their charge/noise contracts. The
[roadmap](ROADMAP.md), [architecture](ARCHITECTURE.md), and
[Phase 2 design](PHASE2_DESIGN.md) remain the starting references.

This plan supplies no newly verified ARRI dimensions, pixel pitch, CFA curves,
or optical measurements. Obtain primary sources before adding a target-specific
preset. A documented assumption can support a generic experiment; it cannot be
silently relabelled as a measured ALEV4 parameter.

## Finite scope and entry conditions

Phase 3 covers a validated physical pixel grid, active cropping and Bayer
phase, a stated spatially invariant PSF model, conservative spatial sampling,
and a restricted nonuniform ISETCam comparison. Its output remains
sensor-plane spectral irradiance followed by the existing photon integration
and readout. PRNU/DSNU, dark current, row/column noise, rolling readout, color
transforms, real-camera fitting, and performance optimization retain their
later roadmap phases.

Before editing production code:

1. Read the accepted Phase 2 completion report and identify its source SHA,
   runtime, dependency pins, and remaining limitations.
2. Establish a source register for proposed geometry/CFA/optics parameters.
   Record document title, publisher, revision, page/section, exact source URL,
   retrieval date, units, capture mode, and whether each value is published,
   measured, derived, or assumed. Keep uncertainty and rounding separate from
   the nominal number; do not invent uncertainty when none is supplied.
3. Freeze the geometry and spatial-sampling contract below in a Phase 3 design
   document. Retain Phase 1/2 defaults and their existing artifact identities.
4. Run the established regression/dependency gates before the first numerical
   change. Preserve that baseline evidence; it is not Phase 3 acceptance.

## Slice 3A — geometry, coordinates, and crop identity

Implement this slice first. Proposed helper names below are design targets,
not existing APIs: `createSensorGeometry` and `sensorGrid`. Use a separate
geometry configuration rather than adding unrecognized fields to existing
Phase 1/2 sensor structs.

| Proposed field | Initial contract |
| --- | --- |
| `full_grid_size` | Positive integer `[rows columns]` for the modelled full photosite grid |
| `active_roi` | One-based `[first_row first_column height width]`, entirely inside that grid |
| `pixel_pitch_m` | Positive finite scalar for square pixels, matching the current collection-area model |
| `origin_xy_m` | Outer top-left full-grid corner; x increases with columns, y with rows |
| `full_grid_cfa_pattern` | One of the supported Bayer patterns, anchored at full-grid index `(1,1)` |
| `parameter_sources` | References to source-register records, including explicit assumed/derived labels |

Derive physical extent from pixel count and pitch. Keep an independently
published, potentially rounded active width/height as a source observation
with a consistency check, not a second unconstrained geometry input. If those
numbers disagree beyond their documented precision, report the disagreement;
do not silently change pitch or crop to make them fit.

For a full-grid column `c` and row `r`, pixel centers are
`x0 + (c-0.5)*pitch` and `y0 + (r-0.5)*pitch`. The active output has shape
`[height width]`. Its effective Bayer pattern must include the parity of both
crop offsets. Cropping one row or column changes that phase; it does not
restart the full-grid color pattern arbitrarily. Keep this image coordinate
system distinct from any future world/camera coordinate transform.

Define the geometry-to-readout binding explicitly: the active readout's
`image_size` is the ROI height/width, `pixel_pitch_m` equals the geometry pitch,
and `cfa_pattern` is the derived active Bayer pattern. Construct and validate
a separate readout configuration with those fields; preserve the caller's
configuration and all other spectral, collection, and electronic settings. If an
API also accepts an already bound readout, reject conflicting size, pitch, or
CFA values. A spatial footprint and a different collection-area pitch would
otherwise describe different pixels.

**Slice 3A acceptance:** independent center/edge calculations, full/active
extent consistency, odd and singleton grids, every crop-offset parity,
out-of-bounds/overflow rejection, and agreement between a crop of the full
Bayer map and a directly generated active Bayer map. Verify the derived
readout binding, rejection of conflicting bindings, and caller-configuration
immutability. An identity full-grid crop must reproduce current single/dual
expectations and RAW for the same inputs and seed. Anisotropic pixels and
subpixel aperture shapes are outside this first slice; accepting them would
require an explicit collection-area and aperture-contract extension.

## Slice 3B — spectral spatial grid and conservative sampling

Add a separate input-grid descriptor with cell-edge coordinates or a uniform
origin/spacing/shape representation. State that each input cell contains a
**cell-average** photon-irradiance density in photons/(m² s nm), on the existing
explicit wavelength bins. Reject inconsistent extents, unordered edges,
nonfinite coordinates, and requests outside supported input coverage.

Implement a small, independently testable area-overlap sampler, provisionally
`resampleSensorIrradiance`. First support axis-aligned rectangular grids and
piecewise-constant source cells. Its output is average irradiance over each
full photosite footprint, still in the same density units. The existing
`integrateExposure` then applies pixel area, fill factor, QE, bin width, and
exposure **once**. Returning an area-integrated photon count to that function
would apply collection area twice and is a required negative test.

Use the current fill factor as a scalar collection factor. Do not additionally
shrink the spatial pixel aperture by that factor without a separately defined
aperture/microlens model. Apply CFA response after spatial optical sampling;
blurring an already mosaiced RGB/Bayer image would mix color-filter identities.

**Slice 3B acceptance:** constant-field preservation; exact hand-computed
overlap fractions; integer and noninteger grid-scale ratios; subpixel offsets;
cropped extents; linearity; nonnegative output; and conservation of the
area-weighted irradiance integral when source and destination cover the same
region. For crops, compare with the integral over that crop rather than the
whole source image. Refine source grids around a known discontinuity and retain
the convergence evidence. Tolerances must follow the stated approximation and
floating-point scale, not a visually chosen image similarity.

## Slice 3C — explicit PSF, boundaries, and MTF

Implement an opt-in `applyOpticalPsf` layer on the **pre-PSF spectral spatial
grid**, before photosite sampling and charge integration. Start with identity
and small stated synthetic kernels. A PSF is nonnegative, finite, has a
declared origin and spatial sampling, and is normalized to unit total weight.
Require one kernel shared across wavelengths or one explicitly associated
with every input spectral bin; never silently interpolate a missing kernel.

The initial discrete convolution requires a uniform spatial input grid whose
row/column spacing matches the kernel sampling. Reject nonuniform pre-PSF
grids or mismatched sampling unless the caller explicitly requests a separately
validated conservative remapping step and records it in the operation order.
Applying one array kernel directly across unequal physical cell widths would
not implement the stated spatially invariant PSF.

Use a declared input halo and retain only the region with complete kernel
support for the initial boundary policy. Record resulting grid/crop offsets.
Do not renormalize a truncated edge kernel to hide missing incident light.
Unit normalization preserves total energy on adequate support; it does not
guarantee conservation inside an arbitrary finite output crop. If later
boundary-extension policies are added, name and test them separately.

Report optical-kernel MTF separately from the combined optical-plus-pixel
response. Pixel averaging contributes its own spatial filtering. Frequency
axes must carry physical units, with sampling/Nyquist limits and kernel
truncation stated. A measured MTF cannot uniquely determine a PSF without
additional phase/model assumptions; do not infer a unique camera PSF from a
single magnitude curve.

**Slice 3C acceptance:**

- An impulse reproduces the normalized kernel at the documented origin;
  shifting the impulse shifts the result consistently.
- Identity PSF reproduces the preceding phase exactly, including no accidental
  extra area, exposure, QE, or fill-factor multiplication.
- Nonuniform grids and mismatched kernel/input sampling reject before filtering;
  any explicit remapping path retains its own conservation and identity checks.
- Flat-field preservation is checked on the fully supported region, with edge
  loss accounted for explicitly.
- Direct small-kernel spatial calculations and an independent DFT agree on
  DC response, phase/origin, and MTF. A useful stated synthetic oracle is the
  separable `[1/4 1/2 1/4]` kernel: its one-dimensional transfer is
  `1/2 + (1/2)*cos(2*pi*f*spacing)`.
- Sinusoidal and edge fixtures exercise the complete blur-plus-sampling
  operator below the declared sampling limit. Any continuous Gaussian
  approximation needs separate truncation/grid-refinement error bounds.

These checks establish the chosen mathematical model. They are not evidence
that the chosen kernel represents an ARRI lens, optical low-pass filter, or
real sensor aperture.

## Slice 3D — restricted nonuniform ISETCam adapter

Preserve `alev4.isetBaseline` and its accepted uniform-field gate. Add a new
adapter with an explicitly narrower supported-input contract before attempting
arbitrary-scene imports. Start with controlled nonuniform scenes whose optical
image extent, cell convention, spectrum, and orientation can be inspected at
the pinned ISETCam revision.

An ISETCam optical image produced by `oiCompute` has already undergone its
configured optics. Feed that result into the spatial sampler without silently
applying the new standalone PSF again. Record whether an input is pre-PSF or
post-optics and the operations actually applied. An extra experimental blur
requires an explicit option and separate provenance.

Establish ISETCam's spatial sample semantics from pinned source/documentation
and controlled fixtures. If its values are point samples, define and validate
the conversion to the Phase 3 cell-average convention; do not relabel them
without an approximation model. Compare continuous expected electrons before
noise/rounding and retain fractional-electron references, as Phase 1 does.

**Slice 3D acceptance:** a uniform scene still matches the original gate;
nonuniform ramps/checkers and a controlled edge agree after matched physical
extent, CFA origin, optics settings, and sampling. Show spatial refinement
convergence and separate disagreements caused by optics, sampling, and spectral
response. A missing dependency or unsupported scene is an explicit failure or
documented unsupported request, never a successful fallback to a flat field.

## Slice 3E — integration, artifacts, and release evidence

Provide an opt-in spatial-exposure wrapper that validates geometry, performs
the declared optics and sampling, and then calls the existing single- or
dual-gain path. Both paths must receive the same expected-electron map; dual
gain still samples photocharge exactly once. Preserve caller RNG state and
do not consume random numbers in deterministic geometry/optics helpers.

Version the Phase 3 spatial provenance explicitly. Do not silently redefine
Phase 1 RAW or Phase 2 bundle fields. A higher-level manifest may bind existing
readout payloads to geometry, input-grid and input-data hashes, source-register
records, PSF samples/hash, normalization, boundary/crop policy, operation order,
spectral-bin mapping, runtime, and exact source/dependency revisions. State the
chosen versioning arrangement before implementing the writer/reader.

Retain small identity, shifted-impulse, flat, edge, sinusoidal, crop/CFA, and
nonuniform-ISET fixtures. Independently verify actual spatial data and output
bytes; a manifest claiming conservation is not its proof. Repeat deterministic
artifacts in fresh processes and preserve checksums plus concise numerical
reports. Keep large external captures in excluded data directories with
documented access and licensing, not automatically in Git.

Complete Phase 3 only when all slices' required gates run on an identified
revision, full Phase 1/2 regressions and artifact/repeat checks pass, scientific
dependency pins remain clean, and release CI/evidence is retained. Native
MATLAB remains unverified unless MATLAB itself executes the gates. Numerical
format bounds do not establish practical full-frame memory or throughput.

## External evidence and remaining uncertainty

| Needed evidence | What it enables | If unavailable |
| --- | --- | --- |
| Primary sensor/capture-mode geometry documentation | Sourced target-specific grid/active-area profile and derived consistency checks | Keep the profile generic or explicitly assumed; leave target-specific geometry unverified |
| CFA/effective QE measurements with wavelength, normalization, and uncertainty | Measured spectral response independent of spatial optics | Retain labelled assumed curves; do not call them fitted or measured |
| Controlled PSF/MTF measurements with wavelength, field position, focus, aperture, and method | Comparison with a stated optical model under matched conditions | Publish synthetic-kernel results and their assumptions only |
| Known scene/illumination and documented spatial reference data | End-to-end spatial/spectral comparison beyond synthetic fixtures | Keep the restricted synthetic/ISET comparison scope explicit |

The first slice can start without proprietary camera data. Source uncertainty
does not prevent testing coordinate arithmetic or conservation, but it limits
the hardware claim. Controlled real-camera characterization and parameter
fitting remain Phase 6, and neither a plausible image nor a matching MTF at
one condition establishes complete sensor equivalence.

## First assignment for the next agent

Read the accepted release evidence, create the parameter source register and
Phase 3 geometry design, then implement only Slice 3A with independent grid,
crop, CFA-parity, and identity-regression tests. Record which proposed fields
were accepted, which sources were actually read, and which assumptions remain.
Do not change existing default readouts or implement PSF/resampling until the
geometry contract and its tests are reviewable. Continue through the ordered
slices after that foundation passes, updating the handoff and evidence at each
completed boundary.
