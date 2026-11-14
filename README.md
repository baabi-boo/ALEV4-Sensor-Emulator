# ALEV4 Sensor Emulator

A research-oriented, **independent and unaffiliated** project working toward an ALEV4-inspired camera sensor model.

> **Phase 2 status: complete and acceptance-tested.** The simultaneous high- and low-gain implementation passed in GNU Octave **8.4.0 in GitHub CI** and **9.4.0 locally** at source commit [`ab1c0bad7cbcf993d0b95980214d45f45f59028c`](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/commit/ab1c0bad7cbcf993d0b95980214d45f45f59028c). The [completion report](docs/PHASE2_COMPLETION.md) and [retained evidence index](docs/evidence/phase2-release-record.json) identify the commands, results, artifacts, and passing workflows. There is **no calibrated ALEV4 model, demonstrated 17-stop performance, or genuine ARRIRAW encoder**. Native MATLAB execution remains unverified.

The accepted source passed **62 Phase 2 numerical groups, all 92 Phase 1 regression groups, and 47 Python tests**, together with failure-reporting checks and independently verified, byte-identical fresh-process demos for both phases. Phase 2, Phase 1, and repository-integrity workflows all passed on that revision.

Phase 1 remains complete and acceptance-tested in GNU Octave 8.4.0. Its historical acceptance covered 91 numerical test groups, 29 Python tests, failure reporting, genuine ISETCam integration, and repeated-process artifacts. Those results and their exact revision remain recorded in the [Phase 1 completion report](docs/PHASE1_COMPLETION.md); they are not substituted for Phase 2 release evidence.

## What Phase 2 adds

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
| Standalone numerical core | `matlab/+alev4/` | Shared spectral integration, single/dual readout, observable merge, and synthetic I/O |
| ISETCam | `third_party/isetcam` | Pinned scene/optics/Bayer reference used by the retained `alev4.isetBaseline` gate |
| ISETHdrsensor | `third_party/isethdrsensor` | Pinned HDR research dependency; not executed by the current single/dual core |
| Numerical and file tests | `matlab/tests/`, `scripts/tests/` | Analytical physics, statistical noise, error handling, provenance, and corruption checks |
| Acceptance workflows | `.github/workflows/` | Separate Phase 1 and Phase 2 gates plus repository integrity |

The upstream projects remain separately maintained Git submodules. The simultaneous dual-gain model is implemented in this repository; linking ISETHdrsensor's RGBW/multi-capture research does not supply ARRI's proprietary readout architecture.

## Quick start

Use Git, Python 3.10 or newer, and GNU Octave with the `image` package for the complete ISETCam prerequisite. The standalone core does not require the ISET toolboxes or a statistics package. CI currently installs Octave, `octave-image`, and `octave-statistics`; the custom Poisson sampler does not call `poissrnd`.

```bash
git clone https://github.com/baabi-boo/ALEV4-Sensor-Emulator.git
cd ALEV4-Sensor-Emulator
git submodule update --init --recursive --depth 1
python3 scripts/verify_submodules.py --require-checkout
python3 -m unittest discover -s scripts/tests -v
octave --no-gui --quiet --eval "addpath('matlab'); report=run_phase2_tests('outputs/phase2/validation',true); assert(report.phase2_passed);"
octave --no-gui --quiet --eval "addpath('matlab'); setup_project(false); phase2_demo('outputs/phase2/demo');"
```

The Phase 2 runner executes its numerical suites and the complete Phase 1 numerical/ISETCam prerequisite. **Full release acceptance also requires** failure-path checks, independent artifact verification, repetition in a fresh process, and the retained Phase 1 artifact gates. Follow the exact commands in [Phase 2 usage](docs/PHASE2_USAGE.md) and [Phase 1 usage](docs/PHASE1_USAGE.md).

Use fresh demo directories on subsequent runs: existing outputs are deliberately not overwritten. A core-only invocation reports `phase2_passed=false`; it is a development check, not complete acceptance. The existing `run_phase1_tests` and `phase1_demo` entrypoints remain available.

For MATLAB, use the same `.m` entrypoints after `addpath('matlab')`. The ISETCam integration path requires the Image Processing Toolbox. These interfaces are documented for verification; native MATLAB has not been executed as part of the retained acceptance evidence.

## Synthetic artifact contracts

| Output | Files and units | Contract |
| --- | --- | --- |
| Phase 1 single gain | Row-major, little-endian uint16 DN plus JSON; optional grayscale Bayer preview | `ALEV4-SYNTHETIC-RAW`; [Phase 1 usage](docs/PHASE1_USAGE.md) |
| Phase 2 simultaneous dual gain | Two uint16 DN planes, signed float64 electrons, diagnostic/validity flags, and JSON | `ALEV4-SYNTHETIC-DUAL-GAIN`; [bundle specification](docs/PHASE2_ARTIFACTS.md) |

Both formats identify configuration, exposure, seed, units, runtime, and observed Git revisions. Neither is ARRIRAW or DNG. Format limits are 100 million pixels and 2,000,000 UTF-8 metadata bytes; these limits are not large-frame memory or throughput guarantees. The dual-gain reader checks the merge against recorded channels, and Python independently checks bytes, fixed fixtures, and evidence associations.

## Next development phase

The next development phase is **Phase 3: ALEV4-inspired geometry and optics**. Start with the source register and the pixel-grid, active-crop, and CFA-parity contract in [Slice 3A of the Phase 3 plan](docs/PHASE3_PLAN.md). Later slices add conservative spatial sampling, a stated PSF/MTF model, a restricted nonuniform ISETCam comparison, and spatial provenance. The current uniform-field ISETCam adapter is not a general nonuniform-scene importer or a calibrated optical model.

Phases 4–7 retain structured noise/readout realism, demosaic and AWG4/LogC4 transforms, controlled real-camera characterization, and performance/reporting. Published sensor geometry and exposure latitude remain research targets rather than properties established by these generic models. LogC4 is a post-capture encoding; a plausible preview or a matching dynamic-range number does not establish sensor equivalence.

## Documentation

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
