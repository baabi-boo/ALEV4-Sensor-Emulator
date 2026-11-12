# Phase 1 numerical contract

This phase implements a **generic, uncalibrated, single-gain Bayer CMOS model**.
It does not establish ALEV4 equivalence, 17-stop performance, or ARRIRAW support.

## Units and spectral integration

The core input is sensor-plane spectral photon irradiance, an H-by-W-by-K
array in photons/(m^2 s nm). Samples represent bin-average densities; positive
bin widths in nm are explicit. The wavelength grid is increasing and bins do
not overlap. The integration is a rectangular-bin sum, consistent with the
pinned ISETCam implementation; it is not an implicit trapezoidal integral.

For each photosite, expected electrons are:

`exposure_s * pixel_pitch_m^2 * fill_factor * sum(irradiance .* effective_QE .* bin_width_nm)`

Effective QE includes CFA transmission but excludes fill factor. Both are
applied exactly once. Scene radiance is NOT accepted as irradiance: the ISETCam
adapter first computes an optical image. `energyToPhotons` separately converts
W/(m^2 nm) using photon energy h*c/lambda with exact SI constants.

## Readout order

1. Calculate continuous, unclipped photon/electron expectations.
2. Draw one Poisson photoelectron realization (or disable shot noise).
3. Clip accumulated charge at physical full well.
4. Add zero-mean Gaussian read noise in electrons, preserving negative values.
5. Apply gain in DN/electron and black-level offset in DN.
6. Round to nearest integer, then clamp to the ADC range.

Physical full-well saturation and digital under/over-range clipping have
separate masks. RAW is uint16 for ADC depths 1 through 16; unused high bits
remain zero. The model has no PRNU, DSNU, dark current, blooming, rolling
shutter, nonlinear response, or dual-gain merge in Phase 1.

## Determinism

Every simulated exposure takes an explicit integer seed. Calls preserve the
caller's random-number-generator state, including on errors. Equal inputs and
seed reproduce output within a supported runtime/version. Cross-runtime
bit-identical random streams are not promised. Poisson sampling uses an exact
rejection/inversion family rather than a rounded Gaussian approximation.

## Artifacts and provenance

Synthetic RAW uses row-major, little-endian uint16 pixels plus a JSON manifest.
The manifest records shape, CFA and top-left origin, gain/black/ADC/full-well
settings, complete spectral configuration, exposure, seed, runtime, and observed
repository/dependency revisions. Files are explicitly synthetic and uncalibrated.
An independent reader validates metadata, length, and sample bounds.

## Required execution gates

- Analytical photon/electron conversion, units, CFA phase, and exposure linearity.
- Seeded Poisson mean, variance, low-count probabilities, and independent pixels.
- Read-noise statistics before ADC clipping, full-well and quantization boundaries.
- RNG state isolation, invalid input rejection, and RAW/metadata round trips.
- Headless ISETCam spectral scene -> optical image -> Bayer sensor integration,
  compared with continuous fractional-electron expectations.
- Black/flat/ramp and exposure-bracket demo artifacts with numerical reports.

Core-only success does not replace the ISETCam integration gate. Missing or
skipped runtime execution must be reported as unverified, never a pass.
