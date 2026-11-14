# Validation gates and evidence

## Current evidence boundary

Phase 1's **historical acceptance in GNU Octave 8.4.0** passed 91 numerical groups across 11 suites, 29 Python tests, the stale-report failure regression, genuine ISETCam integration, independent artifact validation and byte-identical repeated-process demos. The [Phase 1 completion report](PHASE1_COMPLETION.md) identifies that exact tested revision and preserves its original evidence.

Phase 2 is **complete and acceptance-tested** on source
[`ab1c0bad7cbcf993d0b95980214d45f45f59028c`](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/commit/ab1c0bad7cbcf993d0b95980214d45f45f59028c),
in GNU Octave **8.4.0 in GitHub CI** and **9.4.0 locally**. That revision passed
62 Phase 2 numerical groups, all 92 current Phase 1 regression groups, and
47 Python tests. Five Phase 2 failure scenarios and the preserved Phase 1
failure check passed. Both phases' independently verified demonstrations were
byte-identical across fresh processes: six Phase 2 frames and ten Phase 1
frames, with 31 files in each demonstration. All three release workflows
passed on the tested source.

The [Phase 2 completion report](PHASE2_COMPLETION.md) and
[retained evidence index](evidence/phase2-release-record.json) identify the
commands, inventories, runtime, source/dependency revisions, checksums, and CI
results. Those Phase 1 regressions supplement its historical acceptance;
the older 91-group/29-test results are not relabelled as Phase 2 evidence.
Native MATLAB execution and calibrated ALEV4 equivalence remain unverified.
Source lint is useful but is not runtime evidence.

**Phase 3 is complete and acceptance-tested.** The tested implementation is
[`beedd8bfd1cea3c722409ef0f959fcec5420c5f2`](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/commit/beedd8bfd1cea3c722409ef0f959fcec5420c5f2).
Both GNU Octave 9.4.0 locally and 8.4.0 in GitHub CI passed all 16 acceptance
commands, including 135 Phase 3 numerical groups across all nine required
suites, the preserved 62 Phase 2 groups and 92 Phase 1 regression groups, and
145 Python tests in each execution. Numerical group counts describe named
groups that may contain several assertions. All four candidate workflows
passed, and the downloaded CI archive passed independent verification.

The 43 Phase 3 runner failure/control scenarios are separate from scientific
acceptance. They passed alongside the five Phase 2 scenarios and preserved
Phase 1 failure check. Complete fresh-process demos and independent artifact
checks passed for all three phases, with 31, 31, and 66 files in each respective
primary/repeat set. Each pair had distinct file identities and byte-identical
contents. The [completion record](PHASE3_COMPLETION.md) and
[release evidence index](evidence/phase3-release-record.json) retain the measured
source/runtime associations. Later documentation and evidence commits do not
relabel these results as executions of a newer SHA.

The [usage guide](PHASE3_USAGE.md) and [design contract](PHASE3_DESIGN.md)
describe the spatial model. Earlier development pilots and dirty-tree reports
remain distinct from the final execution. Phase 3 preserves every earlier
phase's numerical, artifact, failure-reporting, and fresh-process repeat gate.

## Scientific targets

Use ARRI's official public specifications as **reference claims**, not as already
validated simulation properties. The [ALEXA 35 technical data](https://www.arri.com/en/cine-systems/cine-cameras/legacy-cine-cameras/alexa-35)
identifies 4608 × 3164 maximum Bayer photosites and advertises 17 stops of
exposure latitude. ARRI's [ALEV architecture description](https://www.arri.com/en/learn/arri-camera-technology/alev-sensors)
describes simultaneous readout paths with different amplification. The referenced
public specifications do not provide a complete calibrated noise/electronics
model for reproducing this sensor.

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
| `raw_io` | [test_phase2_raw.m](../matlab/tests/test_phase2_raw.m) | Independent byte-order/float oracles; complete metadata and original JSON keys; tiny/extreme-scale numeric fidelity and prepublication precision rejection; payload/flag corruption; portable file associations; no-overwrite, alias and symlink behavior; staged-publication failure cleanup |
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

Noiseless tests of the guarded high-gain upper handoff require nondecreasing
reconstruction and a convex per-path quantization-error bound. They include a
fractional low-path black level near high-gain rail exclusion. Configuration
validation reserves half a low-gain quantization step plus its documented
floating-point margin before the high channel becomes unusable. This is not
a global monotonicity guarantee: a separate custom-black-offset regression
retains the documented downward step when lower-rail fallback changes paths.
Shadow-noise expectations use actual Gaussian rounding-bin probabilities
rather than assuming uniform quantization error. These checks do not establish
an optimal or unbiased noisy transition estimator; the observed low-channel
weighting can introduce selection bias.

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

Metadata regressions cover tiny positive and extreme-scale values, numeric
round-trip guards, and rejection before files are published when precision
cannot be preserved. The [bundle contract](PHASE2_ARTIFACTS.md) specifies
17-significant-digit emission and the native decoder's own-magnitude
four-ULP guard, including exact zero and integers within `flintmax` and rejection
of sign changes or nonzero values becoming zero. This metadata guard is
separate from the reader's 64-ULP merged-payload comparison.

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

## Phase 3 spatial acceptance (no camera required)

The [Phase 3 numerical runner](../matlab/run_phase3_tests.m) requires nine
separate suite gates. Every suite must report `status='passed'`, scalar logical
`passed=true`, a positive integer `test_count`, and the matching inventory of
uniquely named passing groups. Missing suites, malformed inventories, duplicate
group names, nonlogical pass flags, failed assertions, and skipped required
work prevent a numerical pass. Full execution also requires the nested
Phase 2 report with `phase1_required=true` and the complete passing Phase 1
ISETCam prerequisite.

| Report gate | Executed suite | Evidence required |
| --- | --- | --- |
| `geometry` | [test_phase3_geometry.m](../matlab/tests/test_phase3_geometry.m) | Hand-calculated physical edges/centres; all full-grid Bayer patterns and crop parities; singleton/odd/boundary ROIs; published geometry versus assumptions; unchanged single/dual readout settings and seeded identity |
| `geometry_edges` | [test_phase3_geometry_edges.m](../matlab/tests/test_phase3_geometry_edges.m) | Canonical numeric representations; bounded descriptors without large allocation; strict source IDs and complete readout binding; conflicting size/pitch/CFA rejection; output limits before optics; no RNG consumption |
| `sampling` | [test_phase3_sampling.m](../matlab/tests/test_phase3_sampling.m) | Independent scalar rectangle intersections; integral conservation over the same physical region; noninteger ratios, offsets, crops and refinement; strict complete coverage; exact copy paths; area/fill/exposure factors applied once |
| `optics` | [test_phase3_optics.m](../matlab/tests/test_phase3_optics.m) | Independent finite convolution for even/asymmetric origins; valid-support physical crops; impulse orientation and support; spectral association; complex DFT and binomial cosine oracles; separate continuous aperture reference; flat/edge/sinusoid behavior before CFA |
| `integration` | [test_phase3_integration.m](../matlab/tests/test_phase3_integration.m) | Scalar optics-to-overlap-to-charge-to-ADC oracle; preserved seeded single/dual identity and shared charge; explicit binding and operation order; rejected second PSF for post-optics data; crop CFA, spectral mapping and collection exactly once |
| `spatial_io` | [test_phase3_artifacts.m](../matlab/tests/test_phase3_artifacts.m) | Independent binary order and SHA-256; strict numeric-token/kind retention; exact coordinates and tiny values; corruption despite recomputed hashes; complete nested associations; regular nonaliased files; no overwrite and owned staging/publication cleanup |
| `numerical_edges` | [test_phase3_numerical_edges.m](../matlab/tests/test_phase3_numerical_edges.m) | Translated-coordinate precision, physical area limits, supported weighted versus exact-copy subnormal behavior, overlap/point-reconstruction underflow, binary64 tokens, extreme MTF/aperture scales, and RNG restoration on early/late failures |
| `demo_contract` | [test_phase3_demo.m](../matlab/tests/test_phase3_demo.m) | Fixed core fixture names/settings; decoded byte-derived summaries; analytical spatial/readout expectations; noisy observable constraints; same-process repeat; no overwrite; missing ISET refuses full completion; caller state restoration |
| `iset_spatial` | [test_phase3_iset.m](../matlab/tests/test_phase3_iset.m) | Genuine pinned uniform/ramp/checker/edge scene → optics → Bayer execution; bilinear point reconstruction and independent footprint integrals; native and source-cell refinement; no second optics; exposure scaling, explicit missing-dependency failures, and caller session/preferences/RNG restoration |

`run_phase3_tests(..., false)` deliberately omits `iset_spatial` and the
Phase 2/Phase 1 prerequisite, reports `core_only`, and leaves
`phase3_passed=false`. The eight standalone suites cannot substitute for the
ninth gate. A successful full numerical report likewise does not regenerate
the three phases' separate release demos or establish their file independence.

### Spatial mathematics and restricted ISET comparison

Input is cell-average spectral photon irradiance on explicit physical edges.
The independent overlap oracle computes intersections of individual source
rectangles and complete target footprints; it does not reuse the production
sparse matrices. Conservation compares integrals over the same physical
region. A crop is checked against its own source integral. The sampled output
remains density, with pitch squared, fill factor, exposure, QE and bin widths
applied once by the preserved spectral integrator. Missing support is an
error, not permission to extrapolate, snap coordinates or renormalize weights.

Optical tests filter spectral planes before CFA selection and distinguish
convolution from correlation through asymmetric kernels and explicit origin
offsets. The reported complex OTF is compared with an independent direct DFT;
the `[1/4 1/2 1/4]` kernel supplies a separate cosine oracle. The ideal
continuous square-aperture sinc is an optional reference, not a second blur
or an assumed exact transfer function for every discrete sampler. Unsupported
numerical ranges fail explicitly instead of erasing small positive support.

The real ISET fixture uses a declared 16-by-16 full-fill geometry and native
sampling that leaves the upstream extra Gaussian regridding prefilter at
1-by-1. Native optical output is **post-optics point samples**.
`isetPointGrid` defines a piecewise-bilinear reconstruction, requires every
interior native knot among the cell edges, and converts each cell to its
four-corner average without extrapolation. Independent footprint integrals,
native quadrature refinement, source-cell refinement and deliberately coarse
controls test that approximation. Converted cell averages enter the wrapper
as `post_optics` with `psf=[]`. This evidence covers the four declared
fixtures and their stated model, not arbitrary ISET imports or measured ARRI
optics. The [source register](PHASE3_SOURCES.md) identifies the pinned upstream
functions and separates published geometry from assumptions.

### Spatial wire format and independent artifacts

The [spatial bundle contract](PHASE3_ARTIFACTS.md) retains original, optical,
sampled and expected-charge arrays, optional PSF coefficients, and the
unchanged Phase 1/2 readout payloads. Native and Python readers check exact
inventory, regular distinct files, lengths, hashes, plane-major/row-major
little-endian bytes, shapes, units, complete configuration, source lists,
operation order and nested metadata associations. They recompute convolution,
overlap and expected electrons. Corruption tests update hashes as well as data
to ensure a valid digest cannot conceal an invalid physical association.

The metadata vocabulary is deliberately bounded: ASCII object keys match
`[A-Za-z][A-Za-z0-9_]{0,62}` with the frozen MATLAB/Octave keyword exclusions,
so the limit is **63 characters** independent of host `namelengthmax`.
Each object has at most **256 fields**, and nesting admits at most **64
object/array containers**, including the outer object. Manifests are bounded
at 2,000,000 UTF-8 bytes and spatial payloads at 100 million numeric samples.
These are format limits, not full-frame memory or throughput guarantees.

`spatialDecodeJson` validates original strings and keys, applies bounded strict
grammar/duplicate checks, and parses original numeric lexemes using
`str2double`. Its retained native kind metadata distinguishes numeric scalars,
vectors and matrices: `[value]` cannot satisfy a scalar schema, and an extra
array wrapper cannot silently change a declared shape. Explicit single-bin
QE handling remains supported. Tests cover exact 17-digit binary64 coordinate
round trips, signed zero, tiny values and underflow, duplicate/normalized or
nonportable keys, booleans as dimensions, malformed Unicode/surrogates,
embedded NULs, and unsupported ragged/mixed arrays. No relaxed coverage
tolerance or edge snapping hides decoder rounding. Phase 1/2 encoders and
their existing precision allowances remain unchanged; their nested manifests
also undergo strict grammar checks before the existing readout reader runs.

The Python verifier uses independent scalar arithmetic on decoded bytes.
For deterministic fixtures it reconstructs charge, clipping, ADC rounding and
observable dual-gain merge; for noisy fixtures it checks observable readout
and flag constraints plus same-runtime repeated artifacts. Neither hashes nor
metadata establish arbitrary unrecorded analog history or a latent noise
realization. Numerical noise tests and the preserved earlier-phase covariance
gates supply that separate model evidence.

The complete demo has eight bundles: `identity_single`, `flat_binomial`,
`shifted_impulse`, `edge`, `sinusoid`, `crop_cfa`, `dual_spatial`, and
`iset_checker`. Core-only generation has seven fixtures and explicitly records
`demo_complete=false`. The full verifier rejects that incomplete set. A
same-process test repeat is useful regression evidence, but release acceptance
requires separate processes and independent file identities.

### Failure and incomplete-result gates

[test_phase3_runner_failure.py](../scripts/test_phase3_runner_failure.py)
executes the real runner in owned temporary repositories with small control
suites. It tests missing prerequisites, missing/false/skipped ISET work,
malformed suite inventories, invalid pass flags, duplicate groups, failed
Phase 2/Phase 1 prerequisites, injected assertions, and core-only status.
These fixture suites establish runner control flow, not scientific or ISET
acceptance. Phase 1 and Phase 2 subprocess failure checks remain required.

The runner invalidates stale success before setup. Failures after successful
invalidation must leave a fresh failed report. Initial write refusal can leave
old bytes on disk, final write refusal can leave incomplete evidence, and an
error after the runner returns can coexist with a passing numerical report.
The **current process exit and complete gate results govern acceptance** in
all cases; an older or locally passing report cannot rescue a failed command.

### Complete release CLI and its 16 external commands

Use a clean committed checkout, initialized clean pinned dependencies, Git,
Python 3.10 or newer, and GNU Octave with its `image` package. From the
repository root, choose an output directory that does not already exist:

```bash
python3 scripts/run_phase3_acceptance.py --octave octave --output-root outputs/phase3-release --expected-commit "$(git rev-parse HEAD)"
```

The [acceptance orchestrator](../scripts/run_phase3_acceptance.py) executes
these **16 external commands in order**. In this inventory, `R` denotes the
selected output root and `S` the observed source commit. Each Octave expression
uses `octave --no-gui --quiet --eval "addpath('matlab'); EXPRESSION"`; Python
commands use the interpreter that launched the orchestrator. This is an
inventory of the complete CLI, not a replacement for its internal checks and
report copying.

| Order | Recorded command label | CLI or Octave expression |
| --- | --- | --- |
| 1 | `dependencies-before` | `python3 scripts/verify_submodules.py --require-checkout` |
| 2 | `python-tests` | `python3 -m unittest discover -s scripts/tests -v` |
| 3 | `all-numerical-gates` | `r=run_phase3_tests('R/phase3/validation',true); assert(r.phase3_passed);` |
| 4 | `phase1-runner-failures` | `python3 scripts/test_runner_failure.py --octave octave` |
| 5 | `phase2-runner-failures` | `python3 scripts/test_phase2_runner_failure.py --octave octave` |
| 6 | `phase3-runner-failures` | `python3 scripts/test_phase3_runner_failure.py --octave octave` |
| 7 | `phase1-demo` | `setup_project(true); phase1_demo('R/phase1/demo');` |
| 8 | `phase1-demo-repeat` | `setup_project(true); phase1_demo('R/phase1/demo-repeat');` |
| 9 | `phase1-artifact-verification` | `python3 scripts/verify_phase1_artifacts.py R/phase1 --expected-commit S --compare-dir R/phase1/demo-repeat` |
| 10 | `phase2-demo` | `setup_project(true); phase2_demo('R/phase2/demo');` |
| 11 | `phase2-demo-repeat` | `setup_project(true); phase2_demo('R/phase2/demo-repeat');` |
| 12 | `phase2-artifact-verification` | `python3 scripts/verify_phase2_artifacts.py R/phase2 --expected-commit S --compare-dir R/phase2/demo-repeat` |
| 13 | `phase3-demo` | `setup_project(true); phase3_demo('R/phase3/demo');` |
| 14 | `phase3-demo-repeat` | `setup_project(true); phase3_demo('R/phase3/demo-repeat');` |
| 15 | `phase3-artifact-verification` | `python3 scripts/verify_phase3_artifacts.py R/phase3 --expected-commit S --compare-dir R/phase3/demo-repeat` |
| 16 | `dependencies-after` | `python3 scripts/verify_submodules.py --require-checkout` |

Each primary/repeat demo runs in a separate numerical process. Before each
artifact verifier, the orchestrator checks that the phase and demo directories
are regular non-symlink directories, every artifact is a regular file, and
primary/repeat device/inode identity sets are disjoint, including cross-name
hardlinks. Those checks apply to **all three phases**, independently of any
individual verifier's legacy behavior. Verifiers then require complete
matching inventories and byte-identical repeated contents, without normalizing
or ignoring differences. Nested Phase 1/2 numerical reports are copied into
their respective verifier roots with their original source/runtime identity.

The orchestrator removes caller `GIT_*` environment overrides from both its
own Git reads and every child gate, so alternate worktrees, indexes or Git
configuration cannot redirect the evidence source. It confirms the actual
repository root, expected commit, unchanged HEAD, source cleanliness at both
ends, and pinned clean dependencies before and after execution. Source
cleanliness also rejects `assume-unchanged` and `skip-worktree` flags in the
root and initialized recursive submodule indexes, including gitlinks; ordinary
Git status alone can conceal changed tracked bytes with those flags. It records
each command, exit status and output, internal repeat-identity checks, reports,
runtime/source/dependency associations, and hashes in `acceptance.json` and
the selected output tree. The
[Phase 3 CI workflow](../.github/workflows/phase3-tests.yml) invokes this same
CLI; the workflow definition itself establishes no observed CI pass.

For edited source, append `--development` and use a new output root. It runs
the same scientific, dependency, artifact and repeat gates, but a successful
run records `status='development_passed'` and `release_accepted=false` even
if the source happened to be clean. A dirty tree's HEAD is not a content
identity for uncommitted changes. Release mode requires every command and
internal check to pass on one identified clean source revision; retain that
receipt and the actual CI outcome before claiming release acceptance. A later
change requires evidence on the changed source.

## Tests reserved for later phases

- Measured ALEV4 optical response and calibration beyond Phase 3's published
  geometry, assumed finite PSFs, and restricted nonuniform ISET fixtures.
- Dark current, PRNU/DSNU, row/column correlations, temperature and exposure-index effects.
- Demosaic/color characterization and neutral/color-chart expectations.
- AWG4/LogC4 numeric reference vectors and encoding/decoding roundtrips, separate from sensor physics.
- Motion/timing behavior and measured-camera gain, noise, transition/SNR and
  exposure-latitude comparisons under controlled conditions.

The next implementation work follows the
[Phase 4 sensor noise and readout plan](PHASE4_PLAN.md). Its persistent sensor
realizations, PRNU/DSNU and dark-signal model must preserve zero-effect
identity, crop coordinates, and the shared-charge simultaneous readout while
adding independent statistical evidence for the new effects. The initial
contract must distinguish exposure-dependent dark-current rates from
exposure-independent electronic offsets and retain fixed-map values in
full-grid coordinates through crops.

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

Phase 3 adds `phase3-validation.json` with nine suite inventories and the nested
Phase 2/Phase 1 prerequisites, `phase3-demo-summary.json`, and the hashed
spatial bundles. Complete acceptance also retains the three phases' separate
artifact receipts, failure-test reports, fresh-process repeat identity checks,
all external command exits, and aggregate `acceptance.json`. A successful
development receipt remains distinct from release acceptance. Retained
noiseless spatial arrays support checking the declared operations; they do not
grant an observed-channel merge access to hidden charge or calibrate the model.

Observed Git HEADs do not prove a clean worktree or object identity by themselves. The strict dependency script and a clean CI checkout provide the corresponding execution evidence. Unknown provenance is labelled unavailable, not replaced by guessed revisions. Reproducibility applies to the recorded runtime/version; matching random streams across MATLAB and Octave is not promised.

Future real-camera validation reports must additionally include camera model/firmware, mode, frame rate, EI, shutter, temperature/lighting, lens and aperture, chart, exposure calibration, RAW processing version, numerical metric, uncertainty, and simulator commit SHA.

**Do not claim 1:1 sensor equivalence, 17 real stops, or authentic ARRIRAW without passing measurements.**

Useful sources:

- [ARRI ALEV sensors](https://www.arri.com/en/learn/arri-camera-technology/alev-sensors)
- [ARRI sample footage and reference images](https://www.arri.com/en/learn/camera-systems/camera-sample-footage-reference-image)
- [ARRIRAW FAQ](https://www.arri.com/en/learn/camera-systems/pre-postproduction/file-formats-data-handling/arriraw-faq)
