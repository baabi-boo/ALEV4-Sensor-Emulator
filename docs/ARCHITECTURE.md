# Architecture and boundaries

The main repository is the **integration and independent sensor-model implementation layer**. It does not fork, rewrite, or vendor the full history of ISETCam or ISETHdrsensor. Phase 1 provides the accepted generic single-gain baseline; its [completion report](PHASE1_COMPLETION.md) records the historical tested revision. Phase 2 adds simultaneous dual gain; its release status is recorded in the [README](../README.md), and its [completion report](PHASE2_COMPLETION.md) identifies the final evidence and outcome.

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

`run_phase2_tests` writes fresh incomplete evidence before execution, requires every numerical suite to report an explicit pass, and includes the complete Phase 1 numerical/ISETCam prerequisite for a full numerical pass. Its standalone mode remains incomplete. Separate workflow gates cover failure reporting, fresh-process demo repetition, independent artifacts, and clean dependencies. Observed Git revisions alone do not establish a clean or correctly pinned source tree.

## Dependency responsibilities

- `third_party/isetcam`: scene, optical-image, sensor, pixel, and imaging utilities. The retained adapter executes `sceneCreate`, `oiCompute`, and a noiseless Bayer `sensorCompute`; it does not supply an ARRI ALEV4 preset.
- `third_party/isethdrsensor`: linked HDR architecture research and test scenes, not executed by the current single/dual core. Its RGBW and multiple-exposure examples do not implement the specific simultaneous readout in this repository. Advanced examples may require external projects or datasets that are not bundled.
- `matlab/+alev4/`: independently testable spectral integration, readout, merge, synthetic I/O, provenance observation, and ISETCam adapter. New project behavior belongs here rather than in modified submodules.
- `matlab/tests/` and `scripts/`: numerical acceptance, artifact corruption tests, independent scalar/file calculations, and dependency checks. Python verification does not implement a second production sensor simulator.

## ISETCam adapter boundary

`alev4.isetBaseline(seed, exposure_s)` remains a deliberately small **uniform-field integration fixture**, not a general arbitrary-scene importer. It computes optics, checks spatial uniformity, imports actual generic effective QE/filter ordering, and maps the uniform irradiance onto a 16 × 16 sensor. It disables off-axis illumination loss and sensor vignetting for that comparison.

Independent expectations are compared with analog volts divided by conversion gain. ISETCam's convenience electron getter rounds values and is unsuitable for this fractional-electron reference. The relative-error tolerance permits upstream single-precision roundoff rather than an arbitrary visual match.

Nonuniform optical images require separately validated resampling and spatial integration. That geometry/optics layer is the next phase after dual-gain acceptance; the current adapter does not establish an ALEV4 optical low-pass filter or calibrated lens/MTF model.

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

After Phase 2 acceptance, Phase 3 adds documented sensor geometry, CFA assumptions, spatial sampling, and stated or measured PSF/MTF behavior. Structured noise/readout realism, demosaic and color characterization, AWG4/LogC4 encoding, controlled real-camera comparisons, and performance reporting retain their later roadmap phases.

No firmware emulation, MIPI CSI-2 hardware emulation, camera UI, lens-mount mechanics, or ARRI camera control protocol is implemented here. Neither synthetic format is an ARRIRAW encoder. Native MATLAB execution, calibrated ALEV4 equivalence, and practical full-frame performance remain unestablished until their own evidence exists.
