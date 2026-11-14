# Validation plan

## Current evidence boundary

Phase 1 is **complete and acceptance-tested in GNU Octave 8.4.0**. The full workflow passed 91 numerical groups across 11 suites, 29 Python tests, the stale-report failure regression, genuine ISETCam integration, independent artifact validation and byte-identical repeated-process demos. The [completion report](PHASE1_COMPLETION.md) identifies the exact tested revision and preserves numerical evidence. Native MATLAB execution has not been verified. Source lint is useful but is not runtime evidence.

Phase 2's simultaneous dual-gain implementation and acceptance gates are in
place; **release acceptance is in progress**. Passing development checks do not
identify a future release revision. Final test inventories, commands, runtime,
source revision, CI results and retained receipts belong in the
[Phase 2 completion report](PHASE2_COMPLETION.md). Phase 1's recorded acceptance
remains historical evidence, and its gates must also pass on the Phase 2
release source. No native MATLAB or calibrated ALEV4 pass is implied.

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

Run the full commands in [PHASE1_USAGE.md](PHASE1_USAGE.md). `run_phase1_tests(..., false)` deliberately leaves `phase1_passed=false`; missing dependencies or skipped ISET work cannot become a full pass. After its initial invalidation write succeeds, the runner cannot preserve the earlier success report when a numerical/setup test fails. Storage failures themselves produce a failed invocation; always check the current process/job result as well as any report file.

## Phase 2 synthetic acceptance (no camera required)

The [Phase 2 numerical contract](PHASE2_DESIGN.md) adds two electronic paths
after a single sampled and full-well-limited charge array. The seven required
suites are separate report gates; a missing suite, malformed inventory,
duplicate group name, or unsuccessful assertion prevents numerical acceptance.

| Report gate | Executed suite | Evidence required |
| --- | --- | --- |
| `core` | [test_phase2_core.m](../matlab/tests/test_phase2_core.m) | Independent transfer functions; one shared charge realization; separate ADC/full-well saturation; RAW-only rail fallback; default and fractional-black merge ramps; reproducibility and fixed Gaussian draw order |
| `config_edges` | [test_phase2_config.m](../matlab/tests/test_phase2_config.m) | Strict nested configuration; canonical shared fields; usable ADC depths; gain/headroom ordering; exact merge-margin boundaries; malformed and supported RAW representations |
| `noise` | [test_phase2_noise.m](../matlab/tests/test_phase2_noise.m) | Read-noise moments and independence; shared shot covariance; difference-noise variance; signed dark readout; quantized shadow moments; noisy highlights; electronic noise after well clipping; incorrect-model negative controls |
| `raw_io` | [test_phase2_raw.m](../matlab/tests/test_phase2_raw.m) | Independent byte-order/float oracles; complete metadata and original JSON keys; payload/flag corruption; portable file associations; no-overwrite, alias and symlink behavior; staged-publication failure cleanup |
| `numerical_edges` | [test_phase2_numerical_edges.m](../matlab/tests/test_phase2_numerical_edges.m) | Seed/Poisson limits; zero collection versus underflow/overflow; supported numeric representations; both readout overflow paths; extreme finite merge endpoints; RNG restoration on failure |
| `spectral_properties` | [test_phase2_spectral.m](../matlab/tests/test_phase2_spectral.m) | Nonuniform scalar spectral oracle; all Bayer phases and singleton/odd geometries; Phase 1 parity; physical scaling; bin refinement; explicit energy conversion; input/RNG isolation |
| `demo_contract` | [test_phase2_demo.m](../matlab/tests/test_phase2_demo.m) | Exact six-frame configuration and seeds; readback-derived summaries; physical validity; finite noisy output; reserved-path preflight; unrelated-file preservation; same-process determinism |

### Noise and quantized handoff

For a constant unsaturated expectation `mu`, independent downstream read
noises with RMS values `sigma_high` and `sigma_low` must satisfy
`cov(R_high, R_low) = mu` and
`var(R_high - R_low) = sigma_high^2 + sigma_low^2`. The first property tests the
shared Poisson realization; the second tests cancellation of that shared
signal. Residual tests subtract stored charge and independently check the
electronic means, variances and cross-covariance. Tolerances derive from sample
counts and the stated moments, using conservative seven-standard-error bounds.
Wrong exposure pairing and reused Gaussian draws must fail the corresponding
statistics even when their marginal noise levels look plausible.

At deterministic physical saturation, stored charge remains exactly at full
well while signed electronic readout fluctuates on both sides of that value.
The saturated-readout test checks those residual moments and rejects a
deliberately incorrect clamp applied after read noise. Physical saturation
continues to exclude reconstruction validity; a finite low-gain code cannot
recover the lost incident signal.

Noiseless handoff tests require nondecreasing reconstruction and a convex
per-path quantization-error bound. They include a fractional low-path black
level near high-gain rail exclusion. Configuration validation reserves half a
low-gain quantization step plus its documented floating-point margin before the
high channel becomes unusable. Shadow-noise expectations use actual Gaussian
rounding-bin probabilities rather than assuming uniform quantization error.
These checks do not establish an optimal or unbiased noisy transition
estimator; the observed low-channel weighting can introduce selection bias.

### Bundle and independent artifact gates

The [Phase 2 bundle contract](PHASE2_ARTIFACTS.md) records both ADC planes,
signed float64 merged electrons, diagnostic/validity flags and a complete
manifest. Native readback and
[verify_phase2_artifacts.py](../scripts/verify_phase2_artifacts.py) independently
check bytes, dimensions, units, configuration, observed-code reconstruction and
flag consistency. Tests reject duplicate or normalized JSON keys, missing
recorded parameters, changed payloads, unsafe associations and contradictory
validity. The native file-identity checks depend on `lstat` or JVM facilities;
the Python verifier remains mandatory for complete artifact acceptance.

The Python verifier derives deterministic demo expectations independently and
recomputes reported metrics from decoded bytes. It does not reproduce a
runtime's Poisson stream or infer unrecorded analog history from noisy RAW.
Artificial Python fixtures test the verifier's acceptance/rejection behavior;
they are not simulation evidence. Likewise, the demo suite's same-process
repeat is distinct from release acceptance's fresh-process comparison.

### Failure-reporting gate

[test_phase2_runner_failure.py](../scripts/test_phase2_runner_failure.py) copies
the production runner into owned temporary repositories and executes these
failure cases in separate Octave processes:

| Scenario | Required result |
| --- | --- |
| Missing scientific prerequisite | Nonzero exit with `ALEV4:MissingSubmodules`; stale success replaced by a fresh failed report |
| Injected later assertion | Nonzero exit with the intended assertion; stale success replaced |
| Malformed suite inventory | `ALEV4:Phase2SuiteFailed`; stale success replaced |
| Duplicate group names | `ALEV4:Phase2SuiteFailed`; stale success replaced |
| Initial report-write refusal | `ALEV4:ReportWrite` and nonzero exit; old bytes may remain because invalidation was impossible |

The last case deliberately verifies that the current process failure governs
acceptance. An old JSON file cannot rescue a failed run. The existing Phase 1
failure regression remains required as well.

### Complete release acceptance

Use the exact commands in [PHASE2_USAGE.md](PHASE2_USAGE.md), together with the
preserved Phase 1 artifact commands. A complete release requires all of these:

1. Identify the actual tested commit and execute from its clean source
   checkout. Verify initialized, clean dependency checkouts against the
   committed gitlinks before and after numerical work with
   `python3 scripts/verify_submodules.py --require-checkout`.
2. Pass all Python verifier/integrity tests and the full
   `run_phase2_tests(output_dir, true)` invocation. Its report must explicitly
   set `phase1_required=true`, include all seven passing Phase 2 suites with
   matching unique group inventories, and include the complete passing Phase 1
   numerical/ISETCam report with matching runtime and source provenance.
3. Pass both phases' failure-reporting subprocess checks. Check current
   process and job exits as well as report contents.
4. Generate each phase's demonstration in a fresh directory, then repeat it
   in another fresh process and directory using the same runtime/version.
   Run both independent artifact verifiers with the actual expected commit.
   Phase 2's entire primary and repeated file-identity sets must be disjoint,
   including cross-filename hardlinks, and corresponding file bytes must match.
5. Retain the numerical report, demo summary, artifact hashes, commands,
   runtime/dependency revisions and observed CI result for that tested source.
   A later code change requires relevant gates on the changed revision; an
   ancestor's passing badge is not evidence for untested code.

`run_phase2_tests(..., false)` deliberately reports `core_only` and
`phase2_passed=false`. Its full numerical pass includes the Phase 1 numerical
prerequisite, but it does not itself regenerate either phase's separate demo
artifacts. The existing Phase 1 and repository-integrity workflows are preserved;
Phase 2's dedicated workflow adds its own execution and artifact checks. A runtime
installation, source review, partial report or unsupported skip cannot replace
the complete release gate.

## Tests reserved for later phases

- ALEV4-inspired geometry and calibrated optical response, including explicit
  spatial sampling, PSF/MTF and nonuniform scene validation.
- Dark current, PRNU/DSNU, row/column correlations, temperature and exposure-index effects.
- Demosaic/color characterization and neutral/color-chart expectations.
- AWG4/LogC4 numeric reference vectors and encoding/decoding roundtrips, separate from sensor physics.
- Motion/timing behavior and measured-camera gain, noise, transition/SNR and
  exposure-latitude comparisons under controlled conditions.

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

Phase 2 adds `phase2-validation.json` with its nested Phase 1 prerequisite,
`phase2-demo-summary.json`, and versioned dual-readout bundles. Its acceptance
receipt records hashes and independently calculated metrics. Merged electrons
are not another ADC plane, rail usability is not proof of an unsaturated
photodiode, and finite invalid estimates must not be interpreted without their
masks. Final execution counts and measured values are recorded with their
tested revision in the [Phase 2 completion report](PHASE2_COMPLETION.md), not
inferred from this validation plan.

Observed Git HEADs do not prove a clean worktree or object identity by themselves. The strict dependency script and a clean CI checkout provide the corresponding execution evidence. Unknown provenance is labelled unavailable, not replaced by guessed revisions. Reproducibility applies to the recorded runtime/version; matching random streams across MATLAB and Octave is not promised.

Future real-camera validation reports must additionally include camera model/firmware, mode, frame rate, EI, shutter, temperature/lighting, lens and aperture, chart, exposure calibration, RAW processing version, numerical metric, uncertainty, and simulator commit SHA.

**Do not claim 1:1 sensor equivalence, 17 real stops, or authentic ARRIRAW without passing measurements.**

Useful sources:

- [ARRI ALEV sensors](https://www.arri.com/en/learn/arri-camera-technology/alev-sensors)
- [ARRI sample footage and reference images](https://www.arri.com/en/learn/camera-systems/camera-sample-footage-reference-image)
- [ARRIRAW FAQ](https://www.arri.com/en/learn/camera-systems/pre-postproduction/file-formats-data-handling/arriraw-faq)
