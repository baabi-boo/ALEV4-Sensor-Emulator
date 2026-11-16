# Development roadmap

**Phase 4 is implemented and candidate `ad036efe6bb6d298545055df37cc4b4681c3e8da` passed complete clean-source acceptance locally and in CI.** Each execution passed 20 command gates, 400 numerical groups and 316 Python tests, in GNU Octave 9.4.0 locally and 8.4.0 in CI. All five candidate workflows passed, and the downloaded CI archive was independently verified. Start with the [completion report](PHASE4_COMPLETION.md), [retained evidence](evidence/phase4/README.md), [usage guide](PHASE4_USAGE.md), [design](PHASE4_DESIGN.md), [parameter sources](PHASE4_SOURCES.md), and [typed artifact contract](PHASE4_ARTIFACTS.md). The [development record](development/phase4/README.md) separates clean candidate acceptance from later targeted checks. All new parameter values and maps are assumed; no ALEV4 calibration, measured ARRI dynamic range, genuine ARRIRAW output or native MATLAB runtime pass is claimed.

Phase 0 is established. Phases 1, 2, and 3 remain complete and acceptance-tested at their recorded historical source revisions. The Phase 3 [completion record](PHASE3_COMPLETION.md), [usage](PHASE3_USAGE.md), [design](PHASE3_DESIGN.md), [parameter sources](PHASE3_SOURCES.md), and [artifact contract](PHASE3_ARTIFACTS.md) describe its spatial layer and executed evidence. Historical accepted Phase 2 source [`ab1c0bad7cbcf993d0b95980214d45f45f59028c`](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/commit/ab1c0bad7cbcf993d0b95980214d45f45f59028c) passed in GNU Octave 8.4.0 in GitHub CI and 9.4.0 locally; its [completion report](PHASE2_COMPLETION.md) and [evidence](evidence/phase2-release-record.json) remain preserved. These earlier results do not establish Phase 4 release acceptance. Every earlier gate remains required, and future targets are not completion claims.

| Phase | Goal | State and acceptance evidence |
| --- | --- | --- |
| 0 | Reproducible repository with two pinned upstream submodules | Established: `.gitmodules`, 160000 gitlinks, historical clean `main` checkpoint and passing integrity check |
| 1 | Generic spectral Bayer sensor baseline | Accepted historical source: known photon-to-electron conversion, shot-noise scaling, deterministic tests, scene-to-RAW demo |
| 2 | Simultaneous high/low-gain readout of shared charge | Accepted historical source: independent electronics, gain/clipping checks, observable merge, synthetic bundles and repeats |
| 3 | ALEV4-inspired geometry and optics | Accepted historical source: sourced Open Gate geometry, crop/CFA binding, conservative sampling, PSF/MTF, restricted ISET comparison and spatial artifacts |
| 4 | Structured sensor noise and readout | Accepted candidate `ad036ef`: 20 gates, 400 numerical groups and 316 Python tests locally/CI; PRNU, dark/offset maps, shared/path electronics, sequences and typed bundles |
| 5 | Demosaic and documented AWG4/LogC4 post-capture transforms | Planned, not implemented; [detailed plan](PHASE5_PLAN.md) defines a reproducible color pipeline and independent numerical/artifact gates |
| 6 | Real-camera characterization | Planned: controlled exposure brackets, Xyla chart, dark/flat frames, color charts and comparison metrics with uncertainties |
| 7 | Performance, reproducibility and public reports | Planned: multi-frame benchmark, full example workflows, error bars and reproducible validation assets |

Phases 1–4 are consolidated on the canonical `main` branch. The
[usage guide](PHASE4_USAGE.md#runtime-and-complete-verification) selects
`main` explicitly and documents the complete acceptance command.

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

## Accepted Phase 3 implementation and release gate

Implementation commit
[`beedd8bfd1cea3c722409ef0f959fcec5420c5f2`](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/commit/beedd8bfd1cea3c722409ef0f959fcec5420c5f2)
passed 135 Phase 3 numerical groups across all nine suites, the preserved
62 Phase 2 groups and 92 Phase 1 regression groups, and 145 Python tests
in both GNU Octave 9.4.0 locally and 8.4.0 in GitHub CI. All 16 acceptance
commands, runner failure/control checks, and independent fresh-process artifact
repeats passed in each execution. All four candidate workflows passed, and the
downloaded CI archive was independently verified. The
[completion record](PHASE3_COMPLETION.md) and
[release evidence index](evidence/phase3-release-record.json) keep this source
identity distinct from later documentation and evidence commits.

The ordered [Phase 3 plan](PHASE3_PLAN.md) has been implemented: explicit
geometry and crop parity, conservative cell-average spatial sampling, finite
PSF filtering and physical-frequency MTF, a restricted nonuniform ISETCam
adapter, and both preserved readouts behind a spatial wrapper. Published Open
Gate counts/pitch are traceable; Bayer origin, QE and optical kernels remain
explicit assumptions. ISET optical point samples receive declared bilinear
reconstruction with independent footprint integration and refinement evidence.

The complete acceptance command requires all of the following on one identified
clean source revision:

1. Every Phase 3 numerical group, genuine ISET uniform/ramp/checker/edge
   comparison, and the complete Phase 2/Phase 1 prerequisites.
2. Native malformed-artifact and runner-failure checks, independent Python
   fixtures and verifiers, and truthful failure/incomplete status handling.
3. Eight complete spatial demo bundles, including noisy simultaneous dual
   gain, with independently reconstructed optics, overlap, expected electrons,
   observable readout checks and file hashes.
4. Fresh-process byte-identical repeats for all three phases, with distinct
   nonaliased artifact sets and their unchanged earlier-phase contracts.
5. Clean pinned dependencies before and after execution, source cleanliness,
   exact commands/runtime/checksums, and observed release CI evidence.

Core-only numerical execution and seven-frame demos remain incomplete. The
source geometry does not establish measured optical response, calibration,
complete die dimensions, arbitrary ISET imports, or full-frame throughput.

## Accepted Phase 4 candidate and preserved release gate

The separate opt-in model preserves the earlier sensor/geometry schemas and
entrypoints. Supplied full-grid PRNU, dark-current rate and fixed electronic
offset maps persist through one-based crops; scalar maps mean uniform values.
The map values define a realization, independently of its label or frame seed.

Achromatic PRNU multiplies photoelectron expectation. Dark rate times exposure
seconds gives a separate dark-charge expectation, with its own shot-noise
switch and stream. Photo and dark draws enter one physical well. Shared and
path-specific fixed offsets plus Gaussian row, column and frame components
enter after the well, alongside each path's existing per-pixel read noise.
Dual-gain reconstruction uses the recorded channels and configuration only.

Independent frames use explicit absolute indices and a documented seed
schedule, with reset/continuation and caller RNG restoration. Fixed maps stay
constant. EI labels affect metadata only; physical exposure and electronic
gains remain explicit. Valid disabled direct/spatial calls return the complete
legacy result; disabled sequences retain legacy frames in their new envelope.
There is no temperature law, correlated flicker/1/f process, rolling shutter,
random fixed-map generator or calibrated camera EI policy in this version.

The distinct structured bundle preserves every retained value, type, shape,
unit, full-grid map and spatial history. Its packed payload uses true C
row-major order. Native and independent Python readers verify bytes and
deterministic semantics, including the observable merge; hashes and source
labels do not authenticate stochastic draws. See the [artifact contract](PHASE4_ARTIFACTS.md)
and [source register](PHASE4_SOURCES.md) for exact boundaries.

The clean candidate passed all nine Phase 4 suites with 111 groups, plus
135 Phase 3, 62 Phase 2 and 92 Phase 1 groups: **400 groups in each execution**.
Both complete receipts include 316 Python tests, all failure controls, all four
fresh-process demo/repeat pairs and clean dependency checks. These observed
results satisfy the following [Phase 4 release requirements](PHASE4_PLAN.md),
which remain mandatory when the implementation changes:

1. One identified clean source revision and clean pinned dependencies before
   and after execution.
2. All nine Phase 4 suites, covering deterministic/statistical physics,
   invalid inputs, RNG isolation, crops, sequences, numerical/resource limits,
   artifacts and demonstrations, plus every Phase 1–3 numerical/ISET gate.
3. Python tests and all four phases' runner-failure controls, with failed or
   incomplete results remaining visibly nonrelease.
4. All four phases' complete demos and distinct fresh-process repeats, with
   independent byte, shape/type/unit, semantic and repeat-identity checks.
5. Retained commands, runtime/version, source/dependency revisions, exits,
   reports and hashes, together with observed CI and verified CI artifacts.

`scripts/run_phase4_acceptance.py` implements the 20-command aggregate gate.
Edited-checkout `--development` runs always leave `release_accepted=false`;
core-only numerical runs leave `phase4_passed=false`. The retained clean
receipts identify `ad036ef`; the later test-only decimal-diagnostic correction
has focused 14-group Octave 9.4.0 evidence, without relabelling those earlier
receipts as a newer execution. Supported sample limits do not establish
peak-memory behavior or throughput. In particular, enabled fully active
4608×3164 structured direct exposure exceeds the current 100-million-value
guard; use the documented [small crops and limits](PHASE4_USAGE.md#supported-sizes-and-allocation-checks).
Native MATLAB remains unverified until its relevant gates execute.

## Next: Phase 5 post-capture color

Phase 5 is planned and **not implemented**. The [detailed Phase 5 plan](PHASE5_PLAN.md)
defines source/domain checks, normalization from observed readouts and masks,
a reproducible Bayer demosaic, an explicitly assumed camera-color mapping,
and published AWG4/LogC4 post-capture transforms with independent numerical
and artifact checks. Sensor noise and readout physics remain separate.
Controlled real-camera characterization remains Phase 6, and performance
measurement and public reporting remain Phase 7. A rendered preview or LogC4
encoding does not establish sensor identity or calibration.

## Calibration gate

An ALEV4-like simulator becomes *calibrated* only after independent comparisons against controlled ALEXA 35 material. Matching a marketing dynamic-range number or a LogC4 preview alone is **insufficient**.

ARRI's published reference stills/ARRIRAW are suitable for initial qualitative comparisons, but inferring unique sensor readout parameters requires controlled captures of the same scenes across exposure, illuminant, and temperature.
