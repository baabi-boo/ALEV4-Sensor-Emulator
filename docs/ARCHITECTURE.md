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

Phase 4 is **implemented and its clean candidate `ad036ef` passed complete
acceptance in GNU Octave 9.4.0 locally and 8.4.0 in CI**: 20 command gates,
400 numerical groups and 316 Python tests per execution. All five candidate
workflows passed, and the downloaded CI archive was independently verified.
The [completion record](PHASE4_COMPLETION.md) and [retained evidence](evidence/phase4/README.md)
identify that source separately from the later test-only decimal-diagnostic
correction and its targeted 14-group check. The implementation adds persistent supplied sensor maps,
separately seeded structured-noise components, independent frame sequences,
and a distinct typed artifact format. The [design](PHASE4_DESIGN.md),
[usage guide](PHASE4_USAGE.md), and [development record](development/phase4/README.md)
separate implemented behavior from executed acceptance. All new parameter
values and maps are assumed, as recorded in the [source register](PHASE4_SOURCES.md).

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

## Structured noise and independent frames

[`createStructuredNoise`](../matlab/+alev4/createStructuredNoise.m) owns a
separate model schema. PRNU, dark-current rate and signed electronic offsets
are supplied scalar-uniform or full-grid maps. Actual map values define the
persistent realization; a `realization_id` is only a label. One-based ROI
selection preserves each photosite's fixed values and Bayer identity without
normalizing, regenerating or resizing maps. PRNU is an achromatic multiplier;
dark-current rates use electrons per photosite per second. The declared
temperature records applicability and applies no temperature-response law.

[`simulateStructuredExposure`](../matlab/+alev4/simulateStructuredExposure.m)
uses this order for an enabled model:

1. Integrate spectral irradiance into the baseline photoelectron expectation,
   applying area, fill factor, seconds, QE and bin widths once.
2. Multiply that expectation by active PRNU and independently form expected
   dark charge from active dark-current rate times exposure seconds.
3. Sample photocharge and dark charge with their separately controlled Poisson
   switches, or use the respective expectation when its switch is disabled.
4. Sum the two components and apply **one physical full-well limit**. Both gain
   paths receive this same stored photo-plus-dark charge array.
5. Add shared fixed/row/column/frame electronics after the well, then each
   path's fixed/row/column/frame components and per-pixel read noise. Row draws
   are constant across columns, column draws across rows, and frame draws
   across the active image. Signed read electrons are not clipped to the well.
6. Apply each path's gain and black offset, round and clamp to its ADC. Dual
   gain uses the unchanged `mergeDualGain` with **observed RAW and configuration
   only**. Retained maps, expectations and component draws never correct the
   merge; physical saturation, ADC clipping and rail usability remain separate.

Persistent maps consume no RNG draws. Enabled stochastic components use
separate named streams with `mod(frame_seed + tag, 2^32)` seeds; adding or
disabling one component does not shift another component's stream. This is a
declared synthetic stream policy, not a proof of ideal PRNG independence. A
valid disabled call returns the complete corresponding legacy result without
added wrapper fields or extra draws. Enabled realizations need not match
legacy streams. Public calls restore caller RNG state on success and failure;
repeatability is limited to the same runtime and version. The
[RNG suite](../matlab/tests/test_phase4_rng.m) tests these distinct contracts.

[`simulateStructuredSpatialExposure`](../matlab/+alev4/simulateStructuredSpatialExposure.m)
retains the complete valid legacy `spatial_baseline`, including its analog
history, as verification context. It feeds the baseline's sampled irradiance
to one structured exposure; the baseline contributes no additional charge.
Legacy spatial validity remains a precondition. Optics still precede CFA
selection, density sampling still precedes spectral integration, and
`post_optics` still forbids a second PSF. The wrapper retains a separate
`spatial_operation_order`; see its [integration tests](../matlab/tests/test_phase4_spatial.m).

[`simulateNoiseSequence`](../matlab/+alev4/simulateNoiseSequence.m) is a pure
function of the input, configuration, geometry, supplied model, sequence seed,
exposure seconds and absolute frame indices. Frame `i` uses
`mod(sequence_seed + 64*(i-1), 2^32)`, with indices from 1 through 2^26.
Reset and continuation reproduce the same absolute frames without hidden
mutable state. Component seeds do not overlap within that supported sequence;
different sequence identities can overlap. Fixed maps persist, while an
independently drawn noisy crop need not equal a crop of a larger random frame.
`ei_label` changes metadata only; exposure and electronic gains must change
explicitly. The only temporal model is independent frames, with no rolling
shutter, elapsed-time law or measured flicker/1/f claim. The
[sequence suite](../matlab/tests/test_phase4_sequence.m) checks these boundaries.

Simulation preflight bounds represented numeric/logical contents before map
expansion, spatial sampling or sequence continuation. These conservative
reservations and the separate artifact bounds are supported-size checks,
not full-frame memory or throughput measurements; see
[allocation limits](PHASE4_USAGE.md#supported-sizes-and-allocation-checks).

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

Phase 4's distinct [structured bundle](PHASE4_ARTIFACTS.md) contains exactly
`structured.json` and `data.bin`, identified as
`ALEV4-SYNTHETIC-STRUCTURED-NOISE` version 1.0 with `typed-tree-v1` wire
descriptors. It preserves every enabled exposure/spatial-exposure result
field, native class, shape, orientation, unit, scalar-map representation and
retained legacy spatial value. Sequence frames are exported individually;
disabled legacy results retain their earlier artifact interfaces.

All numeric/logical leaves use contiguous little-endian segments. Their
`double`, `uint16` or canonical logical-byte classes, offsets, lengths, shapes
and units are explicit, including scalars and empty arrays. **The last index
varies fastest** in a cube: true C row-major order, unlike Phase 3's plane-major
cube order. Actual maps and their crops are bound by the complete typed tree
and payload SHA-256. The format separately bounds manifest bytes, tree depth,
node counts and actual retained values; hashes alone establish no physics.

Native [semantic validation](../matlab/+alev4/structuredValidateResult.m) and
the [independent Python verifier](../scripts/verify_phase4_artifacts.py)
reconstruct map selection, spectral/photo/dark expectations, charge assembly,
one well, signed electronics, ADCs and observed-channel merging, including the
complete spatial baseline. They reject semantic changes even after a payload
is rehashed. They check stochastic support and zero-noise constraints, but
cannot authenticate the claimed seed or distribution of an internally
consistent random realization. Statistical and fresh-process repeat gates
supply separate evidence; none establishes calibration.

Structured export validates before mutation, writes into an owned sibling
stage, publishes the manifest last within that stage, and performs complete
native readback before publishing the directory. Existing targets, unsafe
paths, symlinks and hard-linked entries reject; failure cleanup removes only
owned files after identity checks. Concurrent writers and adversarial
filesystem replacement are outside the contract. The
[native artifact suite](../matlab/tests/test_phase4_artifacts.m) and
[Python corruption tests](../scripts/tests/test_verify_phase4_artifacts.py)
exercise byte order, typed semantics and publication failures independently.

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

[`run_phase4_tests`](../matlab/run_phase4_tests.m) requires all nine Phase 4
suites and the complete nested Phase 3/2/1 numerical/ISETCam prerequisites.
Standalone mode still runs the nine Phase 4 suites but reports `core_only`
with `phase4_passed=false`. The primary complete
[`run_phase4_acceptance.py`](../scripts/run_phase4_acceptance.py) preserves all
earlier gates and adds the fourth phase's failure controls, demo/repeat and
independent artifact verifier, for 20 command gates. All four primary/repeat
pairs require separate processes and disjoint file identities. Clean source,
unchanged HEAD and dependency pins are checked; `--development` always leaves
`release_accepted=false`. See the [full validation contract](VALIDATION.md#phase-4-structured-noise-acceptance-no-camera-required).

## Dependency responsibilities

- `third_party/isetcam`: scene, optical-image, sensor, pixel, and imaging utilities. The retained uniform adapter and restricted spatial fixtures execute `sceneCreate`, `oiCompute`, and a noiseless Bayer `sensorCompute`; they do not supply an ARRI ALEV4 preset.
- `third_party/isethdrsensor`: linked HDR architecture research and test scenes, not executed by the current single/dual core. Its RGBW and multiple-exposure examples do not implement the specific simultaneous readout in this repository. Advanced examples may require external projects or datasets that are not bundled.
- `matlab/+alev4/`: independently testable geometry, PSF/MTF, conservative sampling, spectral integration, structured maps/noise, independent sequences, readout, merge, synthetic I/O, provenance observation, and ISETCam adapters. New project behavior belongs here rather than in modified submodules.
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

The [Phase 5 plan](PHASE5_PLAN.md) defines the next, unimplemented layer:
observed-readout normalization, demosaic, an explicit assumed camera-color
mapping, and documented AWG4/LogC4 transforms. Controlled real-camera
comparisons remain Phase 6; full-frame performance and public reporting remain
Phase 7 in the [roadmap](ROADMAP.md). Enabled fully active Open Gate structured
direct exposure currently exceeds the retained-value guard; supported geometry
and coordinate-preserving crops do not make that full-frame operation available.
See the [allocation limits](PHASE4_USAGE.md#supported-sizes-and-allocation-checks). Temperature response,
camera EI policies, correlated temporal spectra and calibrated noise-map
generation are outside the implemented assumed Phase 4 model.

No firmware emulation, MIPI CSI-2 hardware emulation, camera UI, lens-mount mechanics, or ARRI camera control protocol is implemented here. None of the synthetic formats is an ARRIRAW encoder. Native MATLAB execution, calibrated ALEV4 equivalence, and practical full-frame performance remain unestablished until their own evidence exists.
