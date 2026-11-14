# Development roadmap

**Phase 0 is established. Phases 1 and 2 are complete and acceptance-tested.** Phase 2's simultaneous dual-gain implementation passed on source [`ab1c0bad7cbcf993d0b95980214d45f45f59028c`](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/commit/ab1c0bad7cbcf993d0b95980214d45f45f59028c) in GNU Octave 8.4.0 in GitHub CI and 9.4.0 locally. The [Phase 2 completion report](PHASE2_COMPLETION.md) and [retained evidence index](evidence/phase2-release-record.json) identify the accepted gates and passing workflows. The historical Phase 1 acceptance remains identified in its [completion report](PHASE1_COMPLETION.md). No native MATLAB runtime pass or ALEV4 calibration is claimed. Numbered future targets are not completion claims.

| Phase | Goal | Acceptance evidence |
| --- | --- | --- |
| 0 | Reproducible repository with two pinned upstream submodules | `.gitmodules`, 160000 gitlinks, clean `main`, integrity check passing |
| 1 | Generic spectral Bayer sensor baseline | Known photon-to-electron conversion, shot-noise scaling, deterministic tests, scene-to-RAW demo |
| 2 | Simultaneous high/low-gain readout of shared charge | Independent electronic noise, gain/clipping checks, guarded observable merge, synthetic bundles and repeatable artifacts |
| 3 | ALEV4-inspired geometry and optics | Documented pixel grid and sensor dimensions, calibrated/assumed CFA spectral response, measured or stated PSF/MTF |
| 4 | Sensor noise and readout realism | PRNU/DSNU, row/column structure, dark-frame behaviour, clipping and exposure-index sweeps |
| 5 | RAW and ARRI-compatible post-capture color transforms | Labelled synthetic RAW, reproducible demosaic/color pipeline, numeric LogC4/AWG4 transform tests |
| 6 | Real-camera characterization | Controlled exposure brackets, Xyla chart, dark/flat frames, color charts and comparison metrics with uncertainties |
| 7 | Performance, reproducibility and public reports | Multi-frame benchmark, full example workflows, reported error bars and reproducible validation assets |

## Preserved Phase 1 completion gate

Phase 1 supplies the generic spectral sensor, retained photoelectron expectations, seeded noise/readout, synthetic RAW I/O, controlled fixtures, and an ISETCam uniform-scene comparison. Its acceptance requires the following on an identified source revision:

1. Verify the declared upstream gitlinks and clean, initialized checkouts at those exact revisions.
2. Pass numerical conversion, exposure/QE/area scaling, Bayer phase, noise statistics, clipping, quantization, invalid-input, and RNG-isolation tests.
3. Pass RAW metadata/payload validation, independent byte-order round trips, and supported-limit tests.
4. Run the real ISETCam scene → optics → Bayer path and compare fractional-electron expectations; a skipped integration test is not a pass.
5. Generate all ten demonstration frames, with RAW/JSON pairs, labelled mosaic previews, and numerical summaries.
6. Repeat the demo in a fresh process and independently verify the artifacts, analytic exposure-bracket expectations, and identical same-runtime output files.
7. Retain reports identifying runtime, tested repository revision, dependency revisions, and test commands, then confirm dependencies were not modified by execution.

These gates passed for the recorded Phase 1 revision and remain regression requirements. The core-only entrypoint intentionally reports `phase1_passed=false`. See [Phase 1 usage](PHASE1_USAGE.md) and [validation](VALIDATION.md).

## Accepted Phase 2 implementation and release gate

The implementation now samples one shared photocharge array and physical well, branches into independently configured electronics, and reconstructs signed electrons from the two recorded ADC planes. It preserves Phase 1 APIs and uses the same spectral integration helper. The [numerical contract](PHASE2_DESIGN.md) defines gain/units, conservative rail validity, the low-channel transition policy, its quantization margin, and its noisy-estimator limitations.

The accepted source passed 62 Phase 2 numerical groups, all 92 Phase 1 regression groups, 47 Python tests, both phases' failure-reporting checks, and independent fresh-process artifact gates. These release requirements continue to apply when the implementation changes:

1. Preserve the complete Phase 1 numerical/ISETCam prerequisite and its separate artifact/repeat gates.
2. Verify shared sampled charge, independent path transfer functions, distinct ADC and physical saturation, and RNG restoration on success and failure.
3. Measure shared shot covariance, independent electronic noise, cancellation of shot noise in the path difference, and electronic noise added after physical well clipping. Use sample-size-based tolerances and meaningful wrong-model controls.
4. Verify noiseless upper-handoff continuity and quantization bounds, including fractional black offsets and the high-gain upper-rail boundary. Keep the documented lower-rail fallback limitation distinct from this guarantee. Merge decisions must use recorded channels, not hidden noiseless charge.
5. Reject malformed configuration, unsupported numerical ranges, corrupted bundles, ambiguous metadata, and inconsistent validity flags. Verify no-overwrite and owned failure cleanup behavior.
6. Execute the Phase 2 runner with the Phase 1 prerequisite required; stale success must not survive a failed rerun after report invalidation succeeds. A failed process cannot be replaced by an old report when initial storage fails.
7. Generate all six dual-gain demo bundles, independently decode and recompute their deterministic results, repeat in a fresh process, and compare distinct nonaliased artifact sets.
8. Retain the tested source/dependency revisions, runtime, commands, reports and artifact checksums; confirm clean pinned dependencies and the release CI result.

The Phase 2 core-only entrypoint deliberately reports `phase2_passed=false`. A passing numerical report alone does not replace the artifact and independent-repeat gates. The [usage guide](PHASE2_USAGE.md), [bundle contract](PHASE2_ARTIFACTS.md), and [review ledger](PHASE2_REVIEW_LOG.md) describe the accepted implementation and its verification work; the retained reports keep the source revision that actually produced them.

## Next: Phase 3 geometry and optics

The next development phase is **Phase 3: ALEV4-inspired geometry and optics**. Its Phase 2 acceptance prerequisite is now satisfied. Begin with the source register and Slice 3A in the [Phase 3 plan](PHASE3_PLAN.md): explicit pixel-grid coordinates, active cropping, CFA phase, and identity regressions. Identify the origin and confidence of every geometry, CFA, and optical parameter. Published dimensions, assumed spectral curves, fitted values, and controlled measurements must remain distinguishable.

Implement and test pixel-grid/CFA origin conventions, physical image extent and spatial sampling, followed by a documented PSF/MTF model and independently checked spatial integration. The current ISETCam adapter only validates a uniform field; nonuniform optical images require a separate resampling/integration contract. Retain both existing readout modes and their acceptance gates while adding this layer.

A physically plausible optical model is not automatically a calibrated ALEV4 model. Structured noise, color transforms, and real-camera fitting retain their later phases instead of being silently folded into geometry work.

## Calibration gate

An ALEV4-like simulator becomes *calibrated* only after independent comparisons against controlled ALEXA 35 material. Matching a marketing dynamic-range number or a LogC4 preview alone is **insufficient**.

ARRI's published reference stills/ARRIRAW are suitable for initial qualitative comparisons, but inferring unique sensor readout parameters requires controlled captures of the same scenes across exposure, illuminant, and temperature.
