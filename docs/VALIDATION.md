# Validation plan

## Scientific targets

Use ARRI's official public specifications as **reference claims**, not as already validated simulation properties. ALEXA 35: 4608 × 3164 Bayer photosites and advertised 17 stops of exposure latitude. ARRI describes simultaneous dual-gain readout; it does not publish a complete device-level noise/electronics model for reproduction.

## Synthetic unit tests (no camera required)

- Photon/electron linearity; non-negative rates and well capacity.
- Shot-noise variance follows the Poisson model at specified mean levels.
- Dark/read noise behaves sensibly over exposure and gain changes.
- Two ADC gain branches independently saturate at the intended thresholds.
- HDR merge has no jumps at the transition and avoids unexpectedly reduced SNR.
- CFA sampling/demosaic reproduce correct monochrome chart and neutral patch expectations.
- Deterministic per-pixel seeded tests and recorded units.
- LogC4 encoding/decoding roundtrips (against published equations and reference vectors), independent of sensor physics.

## Controlled-camera experiments needed

| Capture | Characterizes |
| --- | --- |
| Multiple dark frames at several temperatures, exposure times and EIs | Bias, temporal read noise, DSNU, hot pixels and structure |
| Uniform flat fields across exposure levels | Linearity, saturation, PRNU, gain-switch transition, clipping |
| Bracketed calibrated Xyla/dynamic-range target | Exposure latitude under an explicitly defined SNR criterion |
| Spectral lamps / ColorChecker under D65, tungsten and mixed lighting | Spectral/color response and metamerism |
| Slanted edge, Siemens star, point-source tests | OLPF/MTF, sharpness, aliasing, flare |
| Motion and LED timing tests | Rolling readout and timing behaviour |

## Reports

Each future validation report must include: camera model/firmware, mode, frame rate, EI, shutter, temperature/lighting, lens and aperture, test chart, exposure calibration, RAW processing version, numerical metric, uncertainty, and simulator commit SHA.

**Do not claim 1:1 sensor equivalence, 17 real stops, or authentic ARRIRAW without passing measurements.**

Useful sources:
- https://www.arri.com/en/learn/arri-camera-technology/alev-sensors
- https://www.arri.com/en/learn/camera-systems/camera-sample-footage-reference-image
- https://www.arri.com/en/learn/camera-systems/pre-postproduction/file-formats-data-handling/arriraw-faq
