# ALEV4 Sensor Emulator

A research-oriented, **independent and unaffiliated** project to model the image-formation and sensor-readout characteristics of the ARRI ALEXA 35's ALEV 4 CMOS sensor.

> **Project status: repository/bootstrap only.** The two research dependencies are linked below, but there is **no calibrated ALEV4 implementation, no demonstrated 17-stop simulation, and no genuine ARRIRAW encoder** in this repository yet. All ALEV4-specific behaviour must be implemented and validated.

## Architecture

| Component | Location | Source | Role |
| --- | --- | --- | --- |
| ISETCam | `third_party/isetcam` | [ISET/isetcam](https://github.com/ISET/isetcam) | Scene/optical image, spectral irradiance, Bayer photosites, sensor noise |
| ISETHdrsensor | `third_party/isethdrsensor` | [ISET/isethdrsensor](https://github.com/ISET/isethdrsensor) | HDR imaging research, datasets, and evaluation experiments |
| ALEV4 implementation | `matlab/` | This repository | Future sensor architecture, calibrated parameters, reference tests |

Both upstream projects are **Git submodules**, pinned to exact commits rather than copied, modified, or merged into the main repository's Git history. They remain separately maintained.

**Important:** ISETHdrsensor primarily investigates RGBW and multi-capture HDR designs. It is *not* an implementation of ARRI's simultaneous dual-gain architecture. An ALEV4-specific dual-gain model must be written here.

## Clone and set up

Requirements: Git, MATLAB compatible with the upstream toolboxes; optional Python dependencies and additional ISET repositories for advanced upstream examples.

```bash
git clone https://github.com/baabi-boo/ALEV4-Sensor-Emulator.git
cd ALEV4-Sensor-Emulator
git submodule update --init --recursive --depth 1
python3 scripts/verify_submodules.py
```

Run in MATLAB from the repository root:

```matlab
paths = setup_project;
```

The bootstrap file lives at `matlab/setup_project.m`. Add it to the MATLAB path first (`addpath('matlab')`) if not already using MATLAB's Current Folder path. The function prepares the upstream toolboxes but **does not instantiate an ALEV4 sensor**.

To fetch newer upstream versions intentionally:

```bash
git submodule update --remote --init third_party/isetcam third_party/isethdrsensor
git diff --submodule
# Run integration checks and review release notes before committing the new pins.
git add third_party/isetcam third_party/isethdrsensor
git commit -m "chore: update scientific dependency pins"
```

## Engineering targets (not implemented yet)

- **ALEV4 reference geometry:** Super 35 Bayer CMOS sensor; 4608 × 3164 photosites.
- **Exposure latitude:** reproduce and independently measure the ARRI-reported 17 stops, with test conditions and a defined signal-to-noise criterion.
- **Sensor physics:** spectral quantum efficiency, pixel geometry, photon shot noise, dark current, PRNU/DSNU, correlated electronics noise, ADC effects, full-well and clipping.
- **Readout:** model the simultaneous high/low gain paths and their merge; do not substitute an unrelated multi-exposure HDR algorithm.
- **Optics:** optical low-pass filter, lens MTF/PSF, flare, spatial aliasing, rolling readout where measurable.
- **Output:** an explicitly labelled **synthetic RAW Bayer** representation, then separately calibrated demosaic, color matrices, ARRI Wide Gamut 4 / LogC4 transforms.
- **Validation:** compare controlled synthetic and measured targets using both numerical metrics and documented uncertainty.

LogC4 is an encoding/processing stage, **not** a replacement for sensor physics. Synthetic RAW files must not be presented as authentic ARRIRAW captures.

## Documentation

- [Architecture and scope](docs/ARCHITECTURE.md)
- [Development roadmap](docs/ROADMAP.md)
- [Validation plan](docs/VALIDATION.md)

## Source material and attribution

- [ARRI ALEV sensors](https://www.arri.com/en/learn/arri-camera-technology/alev-sensors)
- [ARRI ALEXA 35 specifications](https://www.arri.com/en/camera-systems/cameras/alexa-35)
- [ARRI reference images and footage](https://www.arri.com/en/learn/camera-systems/camera-sample-footage-reference-image)
- [ARRI Log C documentation](https://www.arri.com/en/learn/camera-systems/image-science/log-c)

This project is **not affiliated with, endorsed by, or sponsored by ARRI**. ARRI and ALEXA are trademarks of their respective owner. Third-party submodule code remains subject to its own licenses. No ARRI firmware, proprietary calibration tables, or copyrighted footage is distributed with this repository.
