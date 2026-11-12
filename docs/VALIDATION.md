# Validation plan

## Current evidence boundary

Phase 1 is **implemented; full acceptance is pending**. The first core numerical and ISETCam integration tests passed in GNU Octave 8.4.0. This does not yet establish a pass for the expanded RAW, provenance, edge-case, artifact, and repeated-process workflow. MATLAB execution has not been verified. Source lint is useful but is not runtime evidence.

## Scientific targets

Use ARRI's official public specifications as **reference claims**, not as already validated simulation properties. ALEXA 35: 4608 × 3164 Bayer photosites and advertised 17 stops of exposure latitude. ARRI describes simultaneous dual-gain readout; it does not publish a complete device-level noise/electronics model for reproduction.

## Phase 1 synthetic acceptance (no camera required)

| Gate | Evidence required |
| --- | --- |
| Physical units | Independent analytical photon/electron calculation; explicit nm-bin integration; energy-to-photon SI conversion |
| Linearity and CFA | Exposure, irradiance, area, fill factor, and QE scaling before clipping; all supported Bayer phases and odd/nonsquare geometry |
| Shot noise | Nonnegative integer counts, finite-sample mean/variance checks, low-count probabilities, mixed means, threshold and upper-limit cases |
| Electronic readout | Signed zero-mean Gaussian read noise; full-well before read-noise addition; gain/black offset; quantization and separate ADC clipping masks |
| Reproducibility | Fixed seeds, restored caller RNG state on success/error, repeated-process artifact comparison in the same runtime |
| Input and file validation | Invalid physical/configuration data, malformed/mismatched metadata, manifest-size limits, exact payload length, ADC bounds, and no-overwrite behavior |
| ISET integration | Actual pinned scene/optics/Bayer execution, uniform-field validity, continuous analog electron comparison, exposure doubling, and non-clipped output |
| Artifact independence | Python decoder checks RAW bytes/metadata, analytic bracket expectations, safe references, and repeated files independently of MATLAB I/O |
| Source identity | Recorded runtime/revisions and clean dependency checkouts matching committed gitlinks before and after execution |

Poisson moment tests use fixed seeds and sample-size-aware seven-standard-error bounds. Probability checks use conservative Bernstein bounds with a per-check significance parameter of `1e-12`, including rare bins where a normal approximation is inappropriate. The principal test uses 100,000 samples at each of 0.1, 1, 10, and 1000 expected electrons; edge tests cover mixed means, the sampling threshold, and the supported upper endpoint. A third-central-moment check near the threshold distinguishes Poisson skewness from a rounded Gaussian substitute. Statistical consistency is evidence for the implementation, not proof of exact arithmetic or ALEV4 behavior.

The ISET fixture's comparison tolerance is `5e-5` relative to the peak reference magnitude (with a unit floor), accommodating upstream single-precision operations. Its controlled uniform scene avoids conflating spectral integration with nonuniform spatial regridding. It is not validation of arbitrary optical scenes.

Run the full commands in [PHASE1_USAGE.md](PHASE1_USAGE.md). `run_phase1_tests(..., false)` deliberately leaves `phase1_passed=false`; missing dependencies or skipped ISET work cannot become a full pass. The runner invalidates an earlier success report before executing new tests and writes a failed status if a test raises an error.

## Tests reserved for later phases

- Independent high/low-gain ADC saturation and HDR merge continuity/SNR.
- Dark current, PRNU/DSNU, row/column correlations, temperature and exposure-index effects.
- Demosaic/color characterization and neutral/color-chart expectations.
- AWG4/LogC4 numeric reference vectors and encoding/decoding roundtrips, separate from sensor physics.
- Calibrated optical response, motion/timing behavior, and measured-camera comparisons.

## Controlled-camera experiments needed

| Capture | Characterizes |
| --- | --- |
| Multiple dark frames at several temperatures, exposure times and EIs | Bias, temporal read noise, DSNU, hot pixels and structure |
| Uniform flat fields across exposure levels | Linearity, saturation, PRNU, gain-switch transition, clipping |
| Bracketed calibrated Xyla/dynamic-range target | Exposure latitude under an explicitly defined SNR criterion |
| Spectral lamps / ColorChecker under D65, tungsten and mixed lighting | Spectral/color response and metamerism |
| Slanted edge, Siemens star, point-source tests | OLPF/MTF, sharpness, aliasing, flare |
| Motion and LED timing tests | Rolling readout and timing behaviour |

## Reports and interpretation

Phase 1 produces `phase1-validation.json`, per-frame synthetic RAW manifests, and `phase1-demo-summary.json`. Reports distinguish pre-clipping expectations from noisy charge and RAW DN. A spatial/CFA variance in a demo is not a temporal photon-transfer measurement. Grayscale previews use a fixed ADC-scale mapping and are not demosaiced/color-rendered images.

Observed Git HEADs do not prove a clean worktree or object identity by themselves. The strict dependency script and a clean CI checkout provide the corresponding execution evidence. Unknown provenance is labelled unavailable, not replaced by guessed revisions. Reproducibility applies to the recorded runtime/version; matching random streams across MATLAB and Octave is not promised.

Future real-camera validation reports must additionally include camera model/firmware, mode, frame rate, EI, shutter, temperature/lighting, lens and aperture, chart, exposure calibration, RAW processing version, numerical metric, uncertainty, and simulator commit SHA.

**Do not claim 1:1 sensor equivalence, 17 real stops, or authentic ARRIRAW without passing measurements.**

Useful sources:

- [ARRI ALEV sensors](https://www.arri.com/en/learn/arri-camera-technology/alev-sensors)
- [ARRI sample footage and reference images](https://www.arri.com/en/learn/camera-systems/camera-sample-footage-reference-image)
- [ARRIRAW FAQ](https://www.arri.com/en/learn/camera-systems/pre-postproduction/file-formats-data-handling/arriraw-faq)
