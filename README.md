# ALEV4 Sensor Emulator

A research-oriented, **independent and unaffiliated** project working toward an ALEV4-inspired camera sensor model.

> **Phase 1 status: complete and acceptance-tested in GNU Octave 8.4.0.** All 91 numerical test groups, 29 Python tests, failure-reporting checks, genuine ISETCam integration and repeated-process artifact checks passed. See the [completion report](docs/PHASE1_COMPLETION.md) for the exact tested revision and retained evidence. There is **no calibrated ALEV4 model, demonstrated 17-stop performance, or genuine ARRIRAW encoder**. Native MATLAB execution has not yet been verified.

## What Phase 1 implements

- Spectral photon irradiance integrated into continuous photoelectron expectations, with explicit wavelength-bin widths, effective RGB quantum efficiency, pixel area, and fill factor.
- Four Bayer patterns, including odd-sized and nonsquare images.
- Poisson shot noise, Gaussian read noise, physical full-well clipping, gain/black level, and 1–16-bit ADC quantization.
- Seeded reproducibility within one runtime/version, with caller RNG-state restoration.
- Labelled synthetic RAW export/import and strict metadata/payload checks.
- Black, flat, ramp, checker, and exposure-bracket fixtures; a headless ISETCam uniform-scene integration check; numerical reports and grayscale Bayer-mosaic previews.

Default parameters are illustrative, not measurements of an ARRI sensor. This is the physics foundation for later work, not a camera-look LUT or a hardware/firmware emulator.

## Components

| Component | Location | Role |
| --- | --- | --- |
| Standalone numerical core | `matlab/+alev4/` | Generic sensor integration, noise, readout, and synthetic RAW I/O |
| ISETCam | `third_party/isetcam` | Pinned upstream scene/optics/Bayer reference used by `alev4.isetBaseline` |
| ISETHdrsensor | `third_party/isethdrsensor` | Pinned HDR research dependency; not executed by the Phase 1 baseline |
| Acceptance tests | `matlab/tests/`, `scripts/tests/` | Physics, file-format, provenance, and independent artifact checks |

The upstream projects remain separately maintained Git submodules. ISETHdrsensor's RGBW/multi-capture research is **not** an implementation of ARRI's simultaneous dual-gain readout. Phase 2 must implement and test that separate model.

## Quick start

Use Git, Python 3.10 or newer, and GNU Octave with the `image` package for the full ISETCam gate. The standalone core does not require the ISET toolboxes or a statistics package. The CI workflow currently installs Octave, `octave-image`, and `octave-statistics`; the custom Poisson sampler does not call `poissrnd`.

```bash
git clone https://github.com/baabi-boo/ALEV4-Sensor-Emulator.git
cd ALEV4-Sensor-Emulator
git submodule update --init --recursive --depth 1
python3 scripts/verify_submodules.py --require-checkout
python3 -m unittest discover -s scripts/tests -v
octave --no-gui --quiet --eval "addpath('matlab'); report=run_phase1_tests('outputs/validation',true); assert(report.phase1_passed);"
octave --no-gui --quiet --eval "addpath('matlab'); setup_project(true); phase1_demo('outputs/demo',true);"
```

Use a **fresh demo directory** on subsequent runs: existing RAW, JSON, or preview files are deliberately not overwritten. Full acceptance also requires the independent Python artifact and repeated-process checks described in [Phase 1 usage](docs/PHASE1_USAGE.md). A successful core-only run is not a full Phase 1 pass.

For MATLAB, use the same `.m` entrypoints after `addpath('matlab')`. ISETCam's integration path requires the Image Processing Toolbox. These MATLAB commands are documented for use and verification; they are not evidence that MATLAB execution has already passed.

## Synthetic RAW contract

Each frame is a headerless, **row-major, little-endian `uint16`** `.raw` payload plus a JSON manifest. The format is `ALEV4-SYNTHETIC-RAW`, not ARRIRAW or DNG. The manifest records sensor configuration, exposure, seed, units, CFA origin, runtime, and observed Git revisions. Limits are 100 million pixels and 2,000,000 UTF-8 manifest bytes. The previews are grayscale Bayer mosaics, not demosaiced or color-calibrated images.

## Remaining engineering targets

Phases 2–7 cover independent dual-gain paths, ALEV4-inspired geometry/optics, structured noise/readout effects, calibrated demosaic and AWG4/LogC4 transforms, real-camera characterization, and performance/reporting. The public 4608 × 3164 geometry and 17-stop exposure-latitude claim are research targets, not properties established by Phase 1.

LogC4 is a post-capture encoding, **not** a replacement for sensor physics. Neither a plausible preview nor matching a published dynamic-range number establishes sensor equivalence.

## Documentation

- [Phase 1 completion report and evidence](docs/PHASE1_COMPLETION.md)
- [60-agent implementation and review ledger](docs/PHASE1_REVIEW_LOG.md)
- [Phase 1 usage and artifact format](docs/PHASE1_USAGE.md)
- [Numerical contract](docs/PHASE1_DESIGN.md)
- [Architecture and scope](docs/ARCHITECTURE.md)
- [Development roadmap](docs/ROADMAP.md)
- [Validation plan](docs/VALIDATION.md)

## Source material and attribution

- [ISETCam](https://github.com/ISET/isetcam) and [ISETHdrsensor](https://github.com/ISET/isethdrsensor)
- [ARRI ALEV sensors](https://www.arri.com/en/learn/arri-camera-technology/alev-sensors)
- [ARRI ALEXA 35 specifications](https://www.arri.com/en/camera-systems/cameras/alexa-35)
- [ARRI reference images and footage](https://www.arri.com/en/learn/camera-systems/camera-sample-footage-reference-image)
- [ARRI Log C documentation](https://www.arri.com/en/learn/camera-systems/image-science/log-c)

This project is **not affiliated with, endorsed by, or sponsored by ARRI**. ARRI and ALEXA are trademarks of their respective owner. Third-party submodule code remains subject to its own licenses. No ARRI firmware, proprietary calibration tables, or copyrighted footage is distributed here.
