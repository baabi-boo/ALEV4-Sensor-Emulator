# ALEV4 Sensor Emulator

A research-oriented, **independent and unaffiliated** project working toward an ALEV4-inspired camera sensor model.

> **Phase 4 structured noise is implemented and its candidate passed complete local and CI acceptance.** The new opt-in model adds persistent PRNU and dark-current maps, shared/path electronics, independent frame sequences, and typed synthetic bundles. Start with the [Phase 4 usage guide](docs/PHASE4_USAGE.md), then see the [design](docs/PHASE4_DESIGN.md), [parameter source register](docs/PHASE4_SOURCES.md), and [artifact contract](docs/PHASE4_ARTIFACTS.md). All new parameter values and maps are assumed. There is **no calibrated ALEV4 model, demonstrated 17-stop performance, or genuine ARRIRAW encoder**. Native MATLAB execution remains unverified.

Candidate [`ad036efe6bb6d298545055df37cc4b4681c3e8da`](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/commit/ad036efe6bb6d298545055df37cc4b4681c3e8da) passed **all 20 acceptance commands, 400 numerical groups, and 316 Python tests** in GNU Octave **9.4.0 locally** and **8.4.0 in CI**, including all four phases' independently verified fresh-process demo/repeat pairs. All five candidate workflows passed; the downloaded CI archive was independently verified and is [retained with its receipts](docs/evidence/phase4/README.md). The [completion report](docs/PHASE4_COMPLETION.md) and [development record](docs/development/phase4/README.md) identify the exact tested source. A later test-only decimal-diagnostic correction has focused 14-group Octave 9.4.0 evidence; those candidate receipts do not claim full acceptance of subsequent edits. The accepted Phase 1–3 releases below remain historical evidence, and every earlier gate remains required by Phase 4.

## Accepted earlier phases

Phase 3 source [`beedd8bfd1cea3c722409ef0f959fcec5420c5f2`](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/commit/beedd8bfd1cea3c722409ef0f959fcec5420c5f2) passed all 16 acceptance commands in GNU Octave **9.4.0 locally** and **8.4.0 in GitHub CI**: **135 Phase 3 numerical groups across all nine required suites, 62 Phase 2 groups, 92 Phase 1 regression groups, and 145 Python tests** in each execution. Separate runner failure/control checks and independently verified fresh-process repeats passed for all three phases. All four candidate workflows passed, and the downloaded CI archive and its artifacts were independently verified. These results identify that implementation commit; later documentation and evidence commits do not change the recorded tested source.

Phase 2 remains complete and acceptance-tested at source [`ab1c0bad7cbcf993d0b95980214d45f45f59028c`](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/commit/ab1c0bad7cbcf993d0b95980214d45f45f59028c), in GNU Octave 8.4.0 in GitHub CI and 9.4.0 locally. That source passed **62 Phase 2 numerical groups, all 92 Phase 1 regression groups, and 47 Python tests**, plus failure checks and independently verified fresh-process demos. The [Phase 2 completion report](docs/PHASE2_COMPLETION.md) retains its historical evidence; all of those gates remain required by Phase 4.

Phase 1 remains complete and acceptance-tested in GNU Octave 8.4.0. Its historical acceptance covered 91 numerical test groups, 29 Python tests, failure reporting, genuine ISETCam integration, and repeated-process artifacts. Those results and their exact revision remain recorded in the [Phase 1 completion report](docs/PHASE1_COMPLETION.md); they do not establish acceptance of later source revisions.

## What Phase 4 adds

- A separate structured-noise model with supplied full-grid maps. Achromatic PRNU, dark-current rates in electrons per photosite per second, and signed fixed electronic offsets retain their photosite identity through one-based crops. A scalar map denotes a uniform full grid; labels and seeds do not generate fixed maps.
- PRNU applied to photoelectron expectation, plus exposure-dependent dark charge. Photo and dark shot noise have separate switches and named streams; their sampled charge enters one physical well shared by simultaneous gain paths.
- Shared and path-specific fixed offsets and Gaussian row, column, and frame components after the well, alongside the existing per-pixel read noise. Signed readouts, ADC clipping, physical saturation and reconstruction validity remain distinct. Dual-gain merging still uses recorded RAW channels and configuration only.
- Independent frame sequences with explicit absolute indices, deterministic reset/continuation in the recorded runtime, persistent fixed maps, and caller RNG restoration. **EI labels change metadata only**; exposure and electronic-gain sweeps use their explicit settings.
- Direct single/dual and spatial wrappers. A valid disabled model directly returns the corresponding legacy exposure result; disabled sequences retain legacy frames inside a new sequence envelope. Existing APIs and artifact identities remain available.
- Typed, hashed structured bundles retaining full maps, component draws, readouts and spatial history, with native round trips and independent Python semantic verification. Twenty-four small assumed demo fixtures and the complete acceptance runner passed on the recorded candidate while preserving every earlier gate.

The [source register](docs/PHASE4_SOURCES.md) distinguishes generic published noise theory from the project's assumed parameters. The temporal model uses independent frames; no temperature law, correlated flicker/1/f model, rolling shutter, camera EI policy or measured ALEV4 noise is implemented. Reproducibility is limited to the recorded runtime/version.

## The preserved Phase 3 spatial layer

- Explicit full-grid coordinates, one-based active crops, physical pixel centres and edges, and crop-adjusted Bayer phase. Geometry binds to either existing readout without changing its electronics.
- An opt-in ALEXA 35 Open Gate geometry profile using published 4608-by-3164 photosites and 6.075 micrometre pitch. The caller supplies the assumed Bayer origin; the profile does not establish total die size, measured QE or optical response.
- Conservative rectangle-overlap averaging of cell-average spectral photon irradiance, with complete footprint coverage and exact aligned-copy paths. Pixel area, fill factor, exposure, QE and bin width are applied once by the existing integration stage.
- Shared or per-bin finite optical PSFs with explicit sampling, origin and valid-support crop. Physical-frequency complex OTF/MTF is separate from an optional continuous pixel-aperture reference.
- A restricted real ISETCam uniform/ramp/checker/edge comparison. Native point samples receive a declared bilinear reconstruction, independent footprint integration and refinement checks; already computed optics receive no implicit second PSF.
- Eight spatial demo fixtures, versioned hashed input/optical/sample/readout bundles, strict native decoding, independent Python scalar verification, and a complete acceptance command preserving every earlier phase gate.

The [source register](docs/PHASE3_SOURCES.md) distinguishes published geometry from derived dimensions and assumed spectral/optical parameters. These results validate the declared mathematical model; real-camera characterization remains later work.

## The preserved Phase 2 readout

- **One exposure and one sampled photocharge array**, shared by two electronic paths after physical full-well clipping.
- Independent high/low read noises, gains in DN/electron, black offsets, and 2–16-bit ADCs, with retained signed readouts and separate clipping diagnostics.
- Electron-domain reconstruction from the observed RAW channels. A smoothstep transition uses low-gain observations, with a quantization margin that finishes the handoff before high gain reaches its upper rail.
- Separate masks for usable recorded channels, physical well saturation, and recoverable signal. Low gain can recover a high-ADC-clipped highlight; it cannot recover charge lost at physical full well.
- A versioned synthetic bundle containing both ADC planes, merged float64 electrons, flags, and complete configuration/provenance metadata.
- Six deterministic/noisy demonstration fixtures, statistical covariance and noise-order tests, independent Python decoding, failure checks, and fresh-process repeat verification.

The merge is a documented reconstruction policy, not a claim of optimal or unbiased fusion near its noisy transition. Default electronic and spectral parameters are illustrative, not measurements of an ARRI sensor.

## The preserved Phase 1 foundation

The single-gain API continues to provide explicit spectral-bin integration, effective RGB QE, pixel area and fill factor, four Bayer patterns, Poisson shot noise, signed Gaussian read noise, physical clipping, and 1–16-bit ADC quantization. It retains seeded same-runtime reproducibility with caller RNG restoration, labelled synthetic RAW I/O, controlled fixtures, and a headless ISETCam uniform-scene comparison.

Both readout paths use the same spectral integration helper, also used by the structured model. This is a sensor-physics foundation; camera rendering, calibrated optics, and hardware/firmware emulation remain separate work.

## Components

| Component | Location | Role |
| --- | --- | --- |
| Standalone numerical core | `matlab/+alev4/` | Geometry, optics, spatial/spectral integration, single/dual and structured readout, independent sequences, observable merge, and synthetic I/O |
| ISETCam | `third_party/isetcam` | Pinned scene/optics/Bayer reference for the retained uniform baseline and restricted nonuniform fixtures |
| ISETHdrsensor | `third_party/isethdrsensor` | Pinned HDR research dependency; not executed by the current single/dual core |
| Numerical and file tests | `matlab/tests/`, `scripts/tests/` | Analytical physics, statistical noise, error handling, provenance, and corruption checks |
| Acceptance workflows | `.github/workflows/` | Phase 4 with preserved Phase 1–3 gates, separate earlier-phase workflows, and repository integrity; all five passed on the recorded candidate |

The upstream projects remain separately maintained Git submodules. The simultaneous dual-gain model is implemented in this repository; linking ISETHdrsensor's RGBW/multi-capture research does not supply ARRI's proprietary readout architecture.

## Quick start

Use Git, Python 3.10 or newer, and GNU Octave with the `image` package for the complete ISETCam prerequisite. The standalone core does not require the ISET toolboxes or a statistics package. CI currently installs Octave, `octave-image`, and `octave-statistics`; the custom Poisson sampler does not call `poissrnd`.

`main` is the canonical development branch and contains the accepted Phase 1–4
implementation and evidence. Select it explicitly:

```bash
git clone --branch main https://github.com/baabi-boo/ALEV4-Sensor-Emulator.git
cd ALEV4-Sensor-Emulator
git submodule update --init --recursive --depth 1
python3 scripts/verify_submodules.py --require-checkout
python3 scripts/run_phase4_acceptance.py --output-root outputs/phase4-acceptance
```

The acceptance command requires a clean checkout and a new output directory. Its 20 command gates execute all nine Phase 4 numerical suites and the complete Phase 1–3 numerical/ISET prerequisites, Python and runner-failure tests, all four phases' demos and fresh-process repeats, independent artifact verification, and dependency checks before and after execution. It records the exact source revision, commands, exit statuses and file hashes. For an edited working tree, `--development` runs the same gates but deliberately leaves `release_accepted=false`.

The [Phase 4 usage guide](docs/PHASE4_USAGE.md) is the primary guide for small direct/spatial examples, fixed-map crops, dual electronics, sequences, disabled compatibility, bundles, and individual numerical/demo/verifier commands. Use fresh demo directories on subsequent runs. Core-only Phase 4 execution deliberately leaves `phase4_passed=false`; a numerical pass alone is not complete release acceptance. All earlier entrypoints and their [Phase 1](docs/PHASE1_USAGE.md), [Phase 2](docs/PHASE2_USAGE.md), and [Phase 3](docs/PHASE3_USAGE.md) guides remain available, including the preserved PSF and ISET interfaces.

For MATLAB, use the same `.m` entrypoints after `addpath('matlab')`. The ISETCam integration path requires the Image Processing Toolbox. These interfaces are documented for verification; native MATLAB has not been executed as part of the retained acceptance evidence.

## Synthetic artifact contracts

| Output | Files and units | Contract |
| --- | --- | --- |
| Phase 1 single gain | Row-major, little-endian uint16 DN plus JSON; optional grayscale Bayer preview | `ALEV4-SYNTHETIC-RAW`; [Phase 1 usage](docs/PHASE1_USAGE.md) |
| Phase 2 simultaneous dual gain | Two uint16 DN planes, signed float64 electrons, diagnostic/validity flags, and JSON | `ALEV4-SYNTHETIC-DUAL-GAIN`; [bundle specification](docs/PHASE2_ARTIFACTS.md) |
| Phase 3 spatial exposure | Float64 input, optical, sampled and expected-charge planes; optional PSF; preserved single/dual payloads; hashed manifest | `ALEV4-SYNTHETIC-SPATIAL`; [spatial specification](docs/PHASE3_ARTIFACTS.md) |
| Phase 4 structured exposure | `structured.json` typed manifest and little-endian `data.bin`; retained double/uint16/logical values, exact shapes/units, fixed maps, components, and complete spatial history | `ALEV4-SYNTHETIC-STRUCTURED-NOISE`; [structured specification](docs/PHASE4_ARTIFACTS.md) |

All formats identify configuration, exposure, seed, units, runtime, and observed Git revisions. None is ARRIRAW or DNG. Earlier readout limits are 100 million pixels and 2,000,000 UTF-8 metadata bytes; spatial cubes are limited to 100 million numeric samples. Phase 4 bounds total retained numeric/logical values and makes conservative allocation checks; see its [usage limits](docs/PHASE4_USAGE.md#supported-sizes-and-allocation-checks). These bounds are not full-frame memory or throughput guarantees.

The Phase 4 payload uses true C row-major order, distinct from Phase 3's plane-major cube order. Readers verify actual bytes and reconstruct deterministic map, charge, electronics, ADC and observed-channel merge semantics; hashes alone cannot validate changed physics. Source labels and seeds associate provenance but do not authenticate stochastic draws or prove execution.

## Next development phase

The [Phase 4 completion report](docs/PHASE4_COMPLETION.md) records the accepted candidate and the scope of the later reporting correction. Its [retained local and CI evidence](docs/evidence/phase4/README.md) preserves original source identities and checksums; a later revision must be assessed from its own execution evidence.

The next implementation phase is **Phase 5: demosaic and documented AWG4/LogC4 post-capture transforms**. It is **planned, not implemented**; the [Phase 5 plan](docs/PHASE5_PLAN.md) defines source/domain checks, observed-readout normalization, demosaic, explicit assumed camera-color mapping, published transforms, and independent numerical/artifact gates. Controlled real-camera characterization remains Phase 6, and performance/reporting remains Phase 7. Published geometry is sourced; actual ALEV4 spectral, optical and noise behaviour remains uncalibrated. LogC4 is a post-capture encoding; a plausible preview or a matching dynamic-range number does not establish sensor equivalence.

## Documentation

- [Phase 4 completion report](docs/PHASE4_COMPLETION.md) and [retained acceptance evidence](docs/evidence/phase4/README.md)
- [Phase 4 usage and acceptance commands](docs/PHASE4_USAGE.md)
- [Phase 4 numerical contract](docs/PHASE4_DESIGN.md), [source register](docs/PHASE4_SOURCES.md), and [typed bundle format](docs/PHASE4_ARTIFACTS.md)
- [Phase 4 development evidence and agent reports](docs/development/phase4/README.md)
- [Phase 4 implementation and release plan](docs/PHASE4_PLAN.md)
- [Phase 5 post-capture color plan](docs/PHASE5_PLAN.md) (not implemented)
- [Phase 3 completion record and retained evidence](docs/PHASE3_COMPLETION.md)
- [Phase 3 implementation and review ledger](docs/PHASE3_REVIEW_LOG.md)
- [Phase 3 usage and acceptance commands](docs/PHASE3_USAGE.md)
- [Phase 3 numerical contract](docs/PHASE3_DESIGN.md), [source register](docs/PHASE3_SOURCES.md), and [spatial bundle format](docs/PHASE3_ARTIFACTS.md)
- [Phase 2 completion report and evidence](docs/PHASE2_COMPLETION.md)
- [Phase 2 usage and acceptance commands](docs/PHASE2_USAGE.md)
- [Phase 2 numerical contract](docs/PHASE2_DESIGN.md) and [bundle format](docs/PHASE2_ARTIFACTS.md)
- [Phase 2 implementation and review ledger](docs/PHASE2_REVIEW_LOG.md)
- [Phase 1 completion report](docs/PHASE1_COMPLETION.md), [review ledger](docs/PHASE1_REVIEW_LOG.md), [usage](docs/PHASE1_USAGE.md), and [numerical contract](docs/PHASE1_DESIGN.md)
- [Architecture and scope](docs/ARCHITECTURE.md)
- [Development roadmap](docs/ROADMAP.md)
- [Phase 3 implementation plan](docs/PHASE3_PLAN.md) and [validation plan](docs/VALIDATION.md)
- [Future-agent working rules](AGENTS.md)

## Source material and attribution

- [ISETCam](https://github.com/ISET/isetcam) and [ISETHdrsensor](https://github.com/ISET/isethdrsensor)
- [ARRI ALEV sensors](https://www.arri.com/en/learn/arri-camera-technology/alev-sensors)
- [ARRI ALEXA 35 specifications](https://www.arri.com/en/camera-systems/cameras/alexa-35)
- [ARRI reference images and footage](https://www.arri.com/en/learn/camera-systems/camera-sample-footage-reference-image)
- [ARRI Log C documentation](https://www.arri.com/en/learn/camera-systems/image-science/log-c)

This project is **not affiliated with, endorsed by, or sponsored by ARRI**. ARRI and ALEXA are trademarks of their respective owner. Third-party submodule code remains subject to its own licenses. No ARRI firmware, proprietary calibration tables, or copyrighted footage is distributed here.
