# ALEV4 Sensor Emulator

A research-oriented, **independent and unaffiliated** project working toward an ALEV4-inspired camera sensor model.

> **Phase 3 is implemented; exact-source release verification is in progress.** The spatial layer adds physical geometry, conservative sampling, explicit PSF/MTF, and a restricted nonuniform ISETCam comparison ahead of the preserved single- and dual-gain readouts. See the [usage guide](docs/PHASE3_USAGE.md), [numerical contract](docs/PHASE3_DESIGN.md), and [parameter source register](docs/PHASE3_SOURCES.md). There is **no calibrated ALEV4 model, demonstrated 17-stop performance, or genuine ARRIRAW encoder**. Native MATLAB execution remains unverified.

Phase 2 remains complete and acceptance-tested at source [`ab1c0bad7cbcf993d0b95980214d45f45f59028c`](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/commit/ab1c0bad7cbcf993d0b95980214d45f45f59028c), in GNU Octave 8.4.0 in GitHub CI and 9.4.0 locally. That source passed **62 Phase 2 numerical groups, all 92 Phase 1 regression groups, and 47 Python tests**, plus failure checks and independently verified fresh-process demos. The [Phase 2 completion report](docs/PHASE2_COMPLETION.md) retains its historical evidence; all of those gates remain required by Phase 3.

Phase 1 remains complete and acceptance-tested in GNU Octave 8.4.0. Its historical acceptance covered 91 numerical test groups, 29 Python tests, failure reporting, genuine ISETCam integration, and repeated-process artifacts. Those results and their exact revision remain recorded in the [Phase 1 completion report](docs/PHASE1_COMPLETION.md); they are not substituted for Phase 2 release evidence.

## What Phase 3 adds

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

Both phases use the same spectral integration helper. This is a sensor-physics foundation; camera rendering, calibrated optics, and hardware/firmware emulation remain separate work.

## Components

| Component | Location | Role |
| --- | --- | --- |
| Standalone numerical core | `matlab/+alev4/` | Geometry, optics, spatial/spectral integration, single/dual readout, observable merge, and synthetic I/O |
| ISETCam | `third_party/isetcam` | Pinned scene/optics/Bayer reference for the retained uniform baseline and restricted nonuniform fixtures |
| ISETHdrsensor | `third_party/isethdrsensor` | Pinned HDR research dependency; not executed by the current single/dual core |
| Numerical and file tests | `matlab/tests/`, `scripts/tests/` | Analytical physics, statistical noise, error handling, provenance, and corruption checks |
| Acceptance workflows | `.github/workflows/` | Phase 3 with preserved Phase 1/2 gates, separate earlier-phase workflows, and repository integrity |

The upstream projects remain separately maintained Git submodules. The simultaneous dual-gain model is implemented in this repository; linking ISETHdrsensor's RGBW/multi-capture research does not supply ARRI's proprietary readout architecture.

## Quick start

Use Git, Python 3.10 or newer, and GNU Octave with the `image` package for the complete ISETCam prerequisite. The standalone core does not require the ISET toolboxes or a statistics package. CI currently installs Octave, `octave-image`, and `octave-statistics`; the custom Poisson sampler does not call `poissrnd`.

```bash
git clone https://github.com/baabi-boo/ALEV4-Sensor-Emulator.git
cd ALEV4-Sensor-Emulator
git submodule update --init --recursive --depth 1
python3 scripts/verify_submodules.py --require-checkout
python3 scripts/run_phase3_acceptance.py --output-root outputs/phase3-acceptance
```

The acceptance command requires a clean checkout and a new output directory. It executes all numerical suites, Python and runner-failure tests, all three phases' demos and fresh-process repeats, independent artifact verification, and dependency checks before and after execution. It records the exact source revision, commands, exit statuses and file hashes. For an edited working tree, `--development` runs the same gates but deliberately leaves `release_accepted=false`.

The [Phase 3 usage guide](docs/PHASE3_USAGE.md) includes small single/dual examples, the PSF and ISET interfaces, and individual numerical/demo/verifier commands. Use fresh demo directories on subsequent runs. Core-only numerical or seven-frame demo execution remains visibly incomplete. All Phase 1/2 entrypoints and their [Phase 1](docs/PHASE1_USAGE.md)/[Phase 2](docs/PHASE2_USAGE.md) usage guides remain available.

For MATLAB, use the same `.m` entrypoints after `addpath('matlab')`. The ISETCam integration path requires the Image Processing Toolbox. These interfaces are documented for verification; native MATLAB has not been executed as part of the retained acceptance evidence.

## Synthetic artifact contracts

| Output | Files and units | Contract |
| --- | --- | --- |
| Phase 1 single gain | Row-major, little-endian uint16 DN plus JSON; optional grayscale Bayer preview | `ALEV4-SYNTHETIC-RAW`; [Phase 1 usage](docs/PHASE1_USAGE.md) |
| Phase 2 simultaneous dual gain | Two uint16 DN planes, signed float64 electrons, diagnostic/validity flags, and JSON | `ALEV4-SYNTHETIC-DUAL-GAIN`; [bundle specification](docs/PHASE2_ARTIFACTS.md) |
| Phase 3 spatial exposure | Float64 input, optical, sampled and expected-charge planes; optional PSF; preserved single/dual payloads; hashed manifest | `ALEV4-SYNTHETIC-SPATIAL`; [spatial specification](docs/PHASE3_ARTIFACTS.md) |

All formats identify configuration, exposure, seed, units, runtime, and observed Git revisions. None is ARRIRAW or DNG. Readout limits are 100 million pixels and 2,000,000 UTF-8 metadata bytes; spatial cubes are limited to 100 million numeric samples. These bounds are not full-frame memory or throughput guarantees. The dual-gain reader checks the merge against recorded channels, and the spatial readers independently reconstruct the declared deterministic operations. Source labels are provenance associations, not cryptographic proof of execution.

## Next development phase

After the Phase 3 release gate, the next development phase is **Phase 4: sensor noise and readout realism**. The [Phase 4 plan](docs/PHASE4_PLAN.md) starts with an explicit persistent sensor-realization contract for PRNU/DSNU and exposure-dependent dark signal, followed by row/column and temporal electronic structure. It requires zero-effect identity, known statistical covariances, fixed-pattern versus temporal separation, and preservation of the one-shared-charge dual-gain contract.

Phases 5–7 retain demosaic and AWG4/LogC4 transforms, controlled real-camera characterization, and performance/reporting. Published geometry is sourced; actual ALEV4 spectral, optical and noise behaviour remains uncalibrated. LogC4 is a post-capture encoding; a plausible preview or a matching dynamic-range number does not establish sensor equivalence.

## Documentation

- [Phase 3 usage and acceptance commands](docs/PHASE3_USAGE.md)
- [Phase 3 numerical contract](docs/PHASE3_DESIGN.md), [source register](docs/PHASE3_SOURCES.md), and [spatial bundle format](docs/PHASE3_ARTIFACTS.md)
- [Phase 4 implementation plan](docs/PHASE4_PLAN.md)
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
