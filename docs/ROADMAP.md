# Development roadmap

**Phase 0 is established. Phase 1 is implemented; full acceptance is pending.** The first core/ISETCam test run passed in GNU Octave 8.4.0, but the expanded gates must pass together before Phase 1 is marked complete. No MATLAB runtime pass or ALEV4 calibration is claimed. A phase passes only when its evidence and tests exist; numbered targets are not completion claims.

| Phase | Goal | Acceptance evidence |
| --- | --- | --- |
| 0 | Reproducible repository with two pinned upstream submodules | `.gitmodules`, 160000 gitlinks, clean `main`, integrity check passing |
| 1 | Generic spectral Bayer sensor baseline | Known photon-to-electron conversion, shot-noise scaling, deterministic tests, scene-to-RAW demo |
| 2 | Independent dual-gain sensor paths | High- and low-gain synthetic readouts with gain, read-noise, saturation and merge continuity tests |
| 3 | ALEV4-inspired geometry and optics | Documented pixel grid and sensor dimensions, calibrated/assumed CFA spectral response, measured or stated PSF/MTF |
| 4 | Sensor noise and readout realism | PRNU/DSNU, row/column structure, dark-frame behaviour, clipping and exposure-index sweeps |
| 5 | RAW and ARRI-compatible post-capture color transforms | Labelled synthetic RAW, reproducible demosaic/color pipeline, numeric LogC4/AWG4 transform tests |
| 6 | Real-camera characterization | Controlled exposure brackets, Xyla chart, dark/flat frames, color charts and comparison metrics with uncertainties |
| 7 | Performance, reproducibility and public reports | Multi-frame benchmark, full example workflows, reported error bars and reproducible validation assets |

## Phase 1 completion gate

The implementation now contains the generic spectral sensor, retained photoelectron expectations, seeded noise/readout, synthetic RAW I/O, controlled fixtures, and an ISETCam uniform-scene comparison. Acceptance requires all of the following on an identified source revision:

1. Verify the declared upstream gitlinks and clean, initialized checkouts at those exact revisions.
2. Pass numerical conversion, exposure/QE/area scaling, Bayer phase, noise statistics, clipping, quantization, invalid-input, and RNG-isolation tests.
3. Pass RAW metadata/payload validation, independent byte-order round trips, and supported-limit tests.
4. Run the real ISETCam scene → optics → Bayer path and compare fractional-electron expectations; a skipped integration test is not a pass.
5. Generate all ten demonstration frames, with RAW/JSON pairs, labelled mosaic previews, and numerical summaries.
6. Repeat the demo in a fresh process and independently verify the artifacts, analytic exposure-bracket expectations, and identical same-runtime output files.
7. Retain reports identifying runtime, tested repository revision, dependency revisions, and test commands, then confirm dependencies were not modified by execution.

The core-only entrypoint intentionally reports `phase1_passed=false`. A runtime-installation probe, source lint, or an attractive preview cannot substitute for the full acceptance gate. See [usage](PHASE1_USAGE.md) and [validation](VALIDATION.md).

Once these gates pass, the next development phase is **Phase 2: independent simultaneous high-gain and low-gain paths**. The remaining phase goals and calibration requirements are unchanged.

## Calibration gate

An ALEV4-like simulator becomes *calibrated* only after independent comparisons against controlled ALEXA 35 material. Matching a marketing dynamic-range number or a LogC4 preview alone is **insufficient**.

ARRI's published reference stills/ARRIRAW are suitable for initial qualitative comparisons, but inferring unique sensor readout parameters requires controlled captures of the same scenes across exposure, illuminant, and temperature.
