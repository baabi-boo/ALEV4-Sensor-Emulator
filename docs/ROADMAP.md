# Development roadmap

These phases describe proposed work. **Only Phase 0 repository setup is being established now.** A phase passes only when its evidence and tests exist; numbered targets are not completion claims.

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

## Immediately next: Phase 1

1. Add a minimal MATLAB entrypoint generating a known spectral scene and an ISETCam Bayer sensor.
2. Expose raw photoelectron expectations before image processing.
3. Create white/black and exposure-bracket fixtures with fixed seeds.
4. Assert that shot-noise variance tracks mean photoelectrons and that saturating pixels clip predictably.
5. Write the generated frame as a **synthetic** mosaic, with units and sensor metadata.
6. Record the exact MATLAB / dependency versions and test commands.

## Calibration gate

An ALEV4-like simulator becomes *calibrated* only after independent comparisons against controlled ALEXA 35 material. Matching a marketing dynamic-range number or a LogC4 preview alone is **insufficient**.

ARRI's published reference stills/ARRIRAW are suitable for initial qualitative comparisons, but inferring unique sensor readout parameters requires controlled captures of the same scenes across exposure, illuminant, and temperature.
