# Architecture and boundaries

The main repository is the **integration and independent sensor-model implementation layer**. It does not fork, rewrite, or vendor the full history of ISETCam or ISETHdrsensor. Phase 1 provides the accepted generic single-gain baseline; its [completion report](PHASE1_COMPLETION.md) records the historical tested revision. Phase 2 adds accepted simultaneous dual gain; its [completion report](PHASE2_COMPLETION.md) identifies the tested source and retained evidence.

Phase 3 places physical geometry, optional optical filtering, and conservative
spatial sampling ahead of those preserved readouts. Its implementation commit
`beedd8bfd1cea3c722409ef0f959fcec5420c5f2` is complete and acceptance-tested
in GNU Octave 9.4.0 locally and 8.4.0 in GitHub CI. All four candidate workflows
passed, and the downloaded CI archive was independently verified. The
[completion record](PHASE3_COMPLETION.md) retains that tested identity
separately from later documentation and evidence commits.
See the [usage guide](PHASE3_USAGE.md), [numerical contract](PHASE3_DESIGN.md),
and [validation gates](VALIDATION.md).

## Spatial front end and geometry binding

`createSensorGeometry` owns a separate versioned geometry schema: full-grid
size, one-based active ROI, square pitch and origin in metres, full-grid Bayer
pattern, and parameter source IDs. `sensorGrid` derives active pixel edges and
centres without allocating a full-frame coordinate mesh for a small crop.
Coordinates retain their full-grid location; crop offsets adjust Bayer parity.
Unsupported ranges, collapsed adjacent sites, and excessive relative edge
spacing error reject rather than changing the effective photosite footprint.

`bindSensorGeometry(readout, geometry, mode)` preserves the existing single-
and dual-gain schemas. Explicit `derive` mode copies the configuration and
changes only image size, pitch, and CFA pattern, inside `.sensor` for dual
gain. The default spatial-wrapper mode, `validate`, rejects conflicting
already-bound settings. Geometry does not add a second physical well or alter
either path's electronics.

`alexa35Geometry` is an opt-in Open Gate geometry profile. The published
4608-by-3164 photosites and 6.075 micrometre pitch are distinguished from the
caller-selected Bayer origin and assumed QE/PSF in the
[source register](PHASE3_SOURCES.md). This full grid describes the published
active area; it does not establish total die size, optical-black dimensions,
hardware crop origins, measured optical response, or calibration.

`simulateSpatialExposure` executes the following declared operations:

1. Validate cell-average spectral photon irradiance and physical cell edges.
   Input planes correspond exactly to the readout's wavelength bins. Point
   samples require an explicit reconstruction before entering this interface.
2. For `pre_psf` input, apply a shared or per-bin finite PSF to each spectral
   plane **before CFA selection**. Kernel origin, physical sampling, spectral
   association, and complete support are explicit. Only the valid-support
   crop survives; neither coefficients nor boundary support are silently
   renormalized. An omitted pre-PSF kernel resolves to an explicit identity.
   For `post_optics` input, preserve the input field and require `psf=[]`.
3. Compute rectangular-overlap averages over complete active photosite
   footprints. Separable sparse operators avoid a full source-by-target
   two-dimensional matrix. Coverage is mandatory, with no extrapolation,
   clamping, edge snapping, or renormalization of missing support. Identical
   and aligned grids have exact copy paths.
4. Pass the sampled **density** into the existing spectral integration and
   single- or dual-gain exposure API. Pixel area, fill factor, exposure, QE,
   and bin widths are applied once in spectral integration. Fill factor does
   not also shrink the spatial averaging footprint.

The geometry, PSF, and overlap helpers consume no random numbers. The wrapper
preserves caller RNG state on success and failure; full-grid identity cases
retain existing seeded readout results. An independently simulated smaller
noisy crop is not promised to equal a crop of a full-frame random realization.
Weighted operations reject unsupported subnormal arithmetic or erased positive
support; exact identity/copy paths retain representable values.

`opticalMtf` separately computes the complex discrete OTF and MTF at physical
frequencies in cycles/metre, respecting the declared kernel origin and Nyquist
bounds. Its optional continuous square-aperture sinc is an analytical
reference, not a second sampling operation or a measured camera response.

## Shared spectral integration

Both `simulateExposure` and `simulateDualGainExposure` call `alev4.integrateExposure` to calculate continuous incident-photon and photoelectron expectations. The core accepts sensor-plane irradiance in photons/(m² s nm), with bin-average densities integrated as `sum(density .* QE .* bin_width_nm)` and scaled by exposure, photosite area, and fill factor.

Effective RGB QE includes CFA transmission and excludes fill factor, which is applied once through collection area. `energyToPhotons` is an explicit separate conversion. Scene radiance, JPEG/sRGB values, and rendered images are not spectral-irradiance inputs. Four Bayer patterns, odd/nonsquare images, exact-zero collection, and explicit numeric overflow/underflow checks retain their Phase 1 behavior.

Continuous expectations, sampled photocharge, full-well-limited stored charge, signed electronic readouts, and quantized ADC values remain distinct outputs. This separation lets tests identify physical clipping, readout noise, and digital clipping independently.

## Preserved single-gain path

1. Integrate the spectral input into continuous expectations.
2. Sample photoelectrons once with a Poisson distribution, unless shot noise is disabled.
3. Clip accumulated charge at physical full well, then add signed Gaussian read noise.
4. Apply DN/electron gain and black-level offset, round, and clamp to the ADC range.
5. Retain intermediate arrays and optionally export the existing synthetic Bayer RAW format.

`createBaselineSensor`, `simulateExposure`, `applyNoise`, `exportSyntheticRaw`, and `readSyntheticRaw` retain the Phase 1 interface and artifact identity. The shared integration extraction does not turn a single-gain invocation into dual gain.

## Simultaneous dual-gain path

`createDualGainSensor` separates common spectral/charge configuration under `sensor` from electronics under `high_gain` and `low_gain`. Phase 1 electronic fields retained in `sensor` must remain canonical; nondefault values there reject instead of being silently ignored. Each Phase 2 path has its own gain, RMS read noise, black offset and 2–16-bit ADC. Neither has a separate photodiode well capacity.

`applyDualGainNoise` samples and clips charge **once**, then draws independent Gaussian electronic-noise arrays in a fixed high/low order. Both paths therefore share shot noise but retain independent downstream read noise. Read noise is added after physical clipping and may place a signed electronic readout above full well or below zero; clipping that readout back to the well would change its statistics.

`mergeDualGain` takes only the observed RAW planes and validated configuration. It subtracts each black offset, divides by its gain, and uses a smoothstep crossfade controlled by the low-gain reconstruction. The configuration requires the transition to end below physical full well and high-gain saturation, including half a low-gain quantization step and a numerical margin. This prevents a noiseless descending handoff at the high channel's upper rail when the transition readouts are usable. It does not guarantee global monotonicity across every rail-fallback change, bound every Gaussian noise excursion, or make the noisy transition an unbiased/optimal estimator.

Codes at either ADC rail are conservatively unusable because RAW cannot distinguish actual clipping from a value rounded exactly to that rail. If one path remains usable, it supplies the reconstruction. If both are unusable, a finite low-path estimate remains with `merged.valid=false`. Physical saturation is a separate simulator diagnostic: `reconstruction_valid = merged.valid & ~full_well_saturated`. A usable low-gain code cannot recover photons lost in a saturated photodiode.

With custom black offsets, a low-path fallback can step downward when a more precise high-path code first leaves the lower rail. This remains possible within the selected paths' quantization-error bounds. The validity masks describe available observations and known physical saturation, not exact charge, global monotonicity, or calibration; the numerical contract retains an explicit lower-rail example.

The [Phase 2 numerical contract](PHASE2_DESIGN.md) specifies equations, interfaces, numerical limits, and acceptance invariants. No proprietary ARRI readout topology or measured sensor parameters are inferred from this generic branching model.

## Artifacts and independent verification

Phase 1 continues to export its uint16 RAW/JSON pair and optional grayscale Bayer preview. Phase 2 uses a separate [five-file bundle](PHASE2_ARTIFACTS.md): high/low uint16 DN, signed float64 merged electrons, packed diagnostic/validity flags, and a complete JSON manifest. All binary planes use explicit row-major little-endian representation.

The native bundle reader validates configuration and file association, reconstructs the merge from recorded channels, and checks flags. Export stages complete files, publishes the manifest last, refuses existing destinations, and removes only its own incomplete publication on failure. Concurrent writers to one base are unsupported. Python independently decodes the bytes, checks fixed demo expectations and summaries, validates report prerequisites, and rejects aliased repeat sets. Neither reader can reconstruct unobserved analog history from arbitrary RAW; simulator tests and controlled fixtures establish those separate properties.

Phase 3 adds an [outer spatial bundle](PHASE3_ARTIFACTS.md) containing original,
optical, and sampled float64 irradiance, expected electrons, optional PSF
coefficients, geometry, operation order, and the unchanged nested readout
payloads. Spatial cubes use plane-major, row-major, little-endian bytes.
`spatial.json` binds fixed file names, exact shapes, units, lengths and SHA-256
hashes. Native readback and an independent Python scalar verifier reconstruct
the declared convolution, overlap, spectral integration, and observable
readout associations; recomputing a hash cannot conceal a semantic mismatch.
Retained expected charge is verification data, never an input to the
observed-channel dual-gain merge.

The Phase 3 reader validates original JSON keys and strings, bounded grammar,
and original numeric tokens before constructing the spatial configuration.
It preserves scalar/vector/matrix wire kinds and binary64 physical coordinates
that a general native JSON decoder can round. The portable contract limits
ASCII keys to 63 characters, objects to 256 fields, and nesting to 64
object/array containers. It rejects ambiguous dimensions, duplicate keys,
invalid Unicode escapes, embedded NULs, unsupported values, symlinks and
aliased files. Coordinate decoding never relaxes physical coverage. The
existing Phase 1/2 wire formats and decoder allowances remain unchanged.

`exportSpatialBundle` validates the supplied retained result, creates a
uniquely owned staging directory beside a new target, verifies the complete
staged bundle, and publishes it after writing the manifest last. Existing
targets and ambiguous staging ownership reject. Failure cleanup removes only
this invocation's owned output. Concurrent writers to one target and universal
atomic no-clobber publication are outside the contract.

`run_phase3_tests` writes fresh incomplete evidence before execution and
requires nine Phase 3 suite gates plus the complete Phase 2/Phase 1
numerical/ISETCam prerequisites. Standalone execution reports `core_only` with
`phase3_passed=false`. A numerical pass is still distinct from complete release
acceptance. `scripts/run_phase3_acceptance.py` additionally runs Python and
failure-reporting tests, all three phases' fresh-process demos/repeats,
independent artifact verifiers, and dependency checks before and after
execution. It checks disjoint repeat file identities and clean unchanged
source, records commands/exits/hashes, and strips caller `GIT_*` overrides
from its own Git reads and child gates. `--development` runs the same gates
but always leaves `release_accepted=false`. Observed Git revisions alone do
not establish a clean or correctly pinned source tree.

## Dependency responsibilities

- `third_party/isetcam`: scene, optical-image, sensor, pixel, and imaging utilities. The retained uniform adapter and restricted spatial fixtures execute `sceneCreate`, `oiCompute`, and a noiseless Bayer `sensorCompute`; they do not supply an ARRI ALEV4 preset.
- `third_party/isethdrsensor`: linked HDR architecture research and test scenes, not executed by the current single/dual core. Its RGBW and multiple-exposure examples do not implement the specific simultaneous readout in this repository. Advanced examples may require external projects or datasets that are not bundled.
- `matlab/+alev4/`: independently testable geometry, PSF/MTF, conservative sampling, spectral integration, readout, merge, synthetic I/O, provenance observation, and ISETCam adapters. New project behavior belongs here rather than in modified submodules.
- `matlab/tests/` and `scripts/`: numerical acceptance, artifact corruption tests, independent scalar/file calculations, and dependency checks. Python verification does not implement a second production sensor simulator.

## ISETCam adapter boundary

`alev4.isetBaseline(seed, exposure_s)` remains a deliberately small **uniform-field integration fixture**, not a general arbitrary-scene importer. It computes optics, checks spatial uniformity, imports actual generic effective QE/filter ordering, and maps the uniform irradiance onto a 16 × 16 sensor. It disables off-axis illumination loss and sensor vignetting for that comparison.

Independent expectations are compared with analog volts divided by conversion gain. ISETCam's convenience electron getter rounds values and is unsuitable for this fractional-electron reference. The relative-error tolerance permits upstream single-precision roundoff rather than an arbitrary visual match.

`alev4.isetSpatialFixture` adds genuine uniform, ramp, checker, and edge
scene/optics/Bayer comparisons on a restricted 16-by-16 full-fill geometry.
ISET's native optical output is already **post-optics point samples**.
`isetPointGrid` explicitly defines a piecewise-bilinear field over those
samples, retains every interior native knot in the cell partition, and
computes each cell average from its four reconstructed corners. It requires
complete point support and rejects extrapolation and unsupported numerical
ranges. Those cell averages enter `simulateSpatialExposure` as `post_optics`
with no second PSF.

Independent footprint integration, native sensor quadrature refinement and
source-cell refinement test that reconstruction. The chosen pitch and native
sample spacing keep ISET's extra Gaussian regridding prefilter at 1-by-1, so
the comparison has a stated spatial model. The adapter restores caller session,
preferences and RNG state. Missing-dependency tests restore their own temporary
path removals; an Octave image package loaded by the adapter remains loaded.
Missing required dependencies reject. These
fixtures do not establish arbitrary ISET optical-image imports, arbitrary
native sensor/pixel configurations, measured ALEV4 OLPF, or calibrated lens MTF.

## Design rules

1. Keep photons, electrons, seconds, spectral-bin widths, volts, and digital numbers explicit.
2. Distinguish published parameters from fitted, measured, and hypothetical values.
3. Preserve explicit seeds and caller RNG state on success and failure; record the runtime/version governing reproducibility.
4. Preserve shared shot charge and separate electronic noise in simultaneous readout. Merge only from observations available to a recorded-channel consumer.
5. Keep sensor physics separate from color encoding, display rendering, subjective texture, and artistic LUTs.
6. Avoid bit-perfect, sensor-identical, measured dynamic-range, or ARRIRAW claims without independent evidence.
7. Keep scientific submodules pinned to reviewed commits and implement project changes outside them.
8. Keep real-camera reference data in the excluded `data/raw/` tree or use reviewed external links; do not auto-commit copyrighted recordings.
9. Reject malformed configuration, ambiguous metadata, missing dependencies and failed assertions; do not report a successful fallback for a required gate.
10. Treat current process results, retained reports, clean source state, dependency integrity and independent artifacts as distinct parts of acceptance.

## Planned later layers and exclusions

The next development work is
[Phase 4 sensor noise and readout realism](PHASE4_PLAN.md): persistent sensor
realizations anchored to the full grid, PRNU/DSNU, and structured electronic
noise while preserving shared dual-gain charge. Its initial contract separates
exposure-dependent dark-current rates from exposure-independent electronic
offsets and keeps fixed maps stable through crops. Demosaic and color
characterization, AWG4/LogC4 encoding, controlled real-camera comparisons, and
performance reporting retain their later roadmap phases.

No firmware emulation, MIPI CSI-2 hardware emulation, camera UI, lens-mount mechanics, or ARRI camera control protocol is implemented here. None of the synthetic formats is an ARRIRAW encoder. Native MATLAB execution, calibrated ALEV4 equivalence, and practical full-frame performance remain unestablished until their own evidence exists.
