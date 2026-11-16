# Phase 5 plan: synthetic RAW development and explicit color domains

**Status: PLANNED / unimplemented.** This document adds no callable APIs or
Phase 5 acceptance claim. Phase 4 is implemented; its complete clean-source
release acceptance and CI are in progress. Start from its [design](PHASE4_DESIGN.md),
[usage](PHASE4_USAGE.md), [artifacts](PHASE4_ARTIFACTS.md), and
[development record](development/phase4/README.md).

The goal is a reproducible post-capture pipeline from existing synthetic Bayer
observations to camera RGB, an explicitly declared AWG4 mapping, and published
LogC4 encoding. Assumed QE/CFA responses plus a published transform do not
establish calibrated ARRI color. Sensor statistics remain in their original
electron/DN domains, independent of demosaic and preview rendering.

## First concrete work and entry evidence

After Phase 4 release evidence is retained, identify that accepted source SHA,
runtime, dependency pins, complete reports, fresh-process repeats and CI result.
On the selected clean starting revision, run
`python3 scripts/run_phase4_acceptance.py --output-root outputs/phase5-entry`
with a new output directory; retain its receipt and dependency checks. This is
entry evidence, not Phase 5 acceptance. Do not substitute a core-only run.

The first implementation unit is **5A: freeze sources, domain descriptors and
independent reference vectors** in proposed `PHASE5_DESIGN.md` and
`PHASE5_SOURCES.md`, before altering numerical behavior. Resolve the explicit
normalization/mask contracts below first. No new dependency, camera recording,
proprietary SDK or large RAW download is needed for these synthetic tests.

## Source register and freeze

Only the following primary ARRI material was retrieved for this plan, on
2026-11-16. Section/page numbers below are the document's printed numbering.

| Source ID | Retrieved source/version | Required use and limit |
| --- | --- | --- |
| S5-01 | [ARRI LogC4 — Logarithmic Color Space, Specification][arri-spec], dated **2025-01-23**, §§4.1.1–4.1.2, p.6 | Piecewise scene-linear encode/decode, Eqs.2–4; retain the specified rounded 117.45 constant. |
| S5-02 | Same specification, §§4.2–4.3, pp.7–8 | AWG4 primaries/D65 and published AWG4→XYZ / AWG4→ACES AP0 matrices, Eqs.5a/6a. |
| S5-03 | Same specification, Appendix A, p.9; Appendix B, p.10 | ARRI's CTL reference and rounded conversion vectors; these share the specification's authorship. |
| S5-04 | [ARRI LogC webpage][arri-logc], “From Log C to display,” undated page | Display conversion is a separate operation; this page does not define a camera-RGB calibration. |

[arri-spec]: https://www.arri.com/resource/blob/278790/f3318e8c9c65617d8c5ca3f8b3e32051/2023-05-arri-logc4-specification-data.pdf
[arri-logc]: https://www.arri.com/en/learn/camera-systems/image-science/log-c

The PDF filename says `2023-05`, but its cover/version history says 2025-01-23.
Text, equations, matrices, CTL and table contents were retrieved; this planning
work did not execute CTL or obtain a local PDF-byte checksum. In 5A, retain the
reviewed constants/vectors, exact URL/version/sections, retrieval date and their
checksums; only claim a PDF digest after hashing actual retrieved PDF bytes.
Review any replacement source explicitly instead of following a mutable URL
silently. Section 3 is informative hardware encoding; Section 4 supplies the
third-party software definition [S5-01].

## Unit 5A — freeze interfaces, units and provenance

The names below are **proposed**, not existing functions. Keep a separate
versioned color configuration; do not add fields to strict sensor, geometry or
structured-noise schemas. Use existing readers to validate their own formats.

| Proposed interface | Input → output contract |
| --- | --- |
| `normalizeSyntheticRaw(result, profile)` | Validated single/dual, direct/spatial result → signed camera-linear Bayer mosaic, geometry/CFA and separate masks. |
| `demosaicBayerLinear(mosaic, descriptor)` | Bayer mosaic → `H×W×3` linear camera RGB, support and propagated validity. |
| `cameraToAWG4(camera_rgb, profile)` | Explicit assumed mapping → linear AWG4; absence of a mapping leaves output in camera RGB. |
| `logC4Encode(linear)` / `logC4Decode(encoded)` | Signed relative scene-linear components ↔ floating LogC4-curve values, without exposure adjustment. |
| `exportColorBundle(result, directory)` / `readColorBundle(directory)` | New synthetic color identity and independently verifiable retained stages. |

Record channel order, array order, units, source stage, ROI/CFA phase, input
identity, reference-electron scale, mapping coefficients, white-balance policy,
color domain, transform source IDs and parameter classification. EI stays
metadata-only. Exposure seconds, electronic gain and reference scale never
change implicitly. Freeze finite numeric ranges, allocation bounds and failure
behavior before implementation; preflight retained input and `H×W×3` working
arrays. Deterministic processing consumes no RNG and preserves caller state.

**Acceptance:** reject missing/ambiguous domains, unknown fields, inconsistent
geometry/CFA, malformed masks, nonfinite values and unsupported ranges; verify
caller immutability, no RNG consumption, and unchanged earlier APIs, results
and artifact contracts.

## Unit 5B — observed RAW normalization and CFA-compatible demosaic

For single gain, reconstruct `e = (double(raw_dn)-black_level_dn)/gain_dn_per_e`.
For dual gain, recompute the existing `mergeDualGain` from both recorded planes
and configuration; do not replace its estimator. Enabled Phase 4 observations
live under `result.readout`; use explicit adapters for legacy direct/spatial
layouts and the existing readers. A structured spatial result's retained
`spatial_baseline` is verification history, not the selected noisy observation.

Define `camera_linear = e/reference_e`, where `reference_e` is a declared
positive finite electrons-per-unit scalar. It is an assumed normalization,
not inferred from full well, ADC maximum, brightest pixel, EI or image average.
Subtract the configured DN black offset exactly once. Do not subtract retained
dark expectations, PRNU maps, noise draws or noiseless charge as a correction.
Retain negative and over-range reconstructions, both path rails, ADC-clipping
flags, physical-well saturation and reconstruction-validity masks separately.
Derive conservative rail usability from recorded codes; analog simulation truth
must not turn a rail code into a usable observation.
When physical saturation evidence is unavailable, record unknown, not false.

Begin with deterministic bilinear Bayer interpolation and fixed local kernels.
Preserve observed samples in their own channels. Support all four existing
Bayer patterns and crop-adjusted parity. Freeze a parity-preserving reflection
about edge sample centers; require at least two rows and columns initially.
Record the boundary policy and support footprint. Any contributing invalid
sample makes that output channel invalid; never drop it and renormalize the
remaining weights. Keep finite fallback values distinguishable by their masks.
No denoising, sharpening, defect repair or automatic white balance is included.

**Acceptance:** independent scalar interpolation on color-coded mosaics,
constant/channel-isolated fields, impulses, ramps and edges; all CFA/crop
parities, odd/nonsquare sizes, 2×2 boundaries and explicit singleton rejection.
Check fractional black offsets, zero/negative signals, both ADC rails, dual
handoffs and both-invalid fallbacks; invalidity must spread only through the
declared support. Mutating inaccessible simulation truth must not alter output
values. Crop/full-image interior agreement requires equivalent source support.

## Unit 5C — camera RGB, assumed mapping and published AWG4 matrices

Camera RGB from the toy spectral response is not AWG4. Require an explicit
profile with matrix direction, channel order, coefficient precision, any
diagonal white-balance gains, illuminant/reference-white assumptions and source
classification. In the initial pipeline, the mapping is **assumed**; even an
identity matrix must be labeled an assumption. Measured fitting, validation
and uncertainty estimates belong to Phase 6. Without a profile, stop the color
pipeline at camera RGB and retain that domain label.

Apply any declared white-balance operation and camera→AWG4 matrix once, in the
frozen order, using signed floating values. Separately support analytical AWG4
test vectors that bypass the sensor and its unknown color characterization.
Propagate channel validity through every nonzero matrix coefficient; component
curve transforms carry masks unchanged.

| Matrix contract from S5-02 | Required numerical evidence |
| --- | --- |
| Linear AWG4→CIE XYZ D65, Eq.5a | Full published precision; basis-vector columns; neutral/D65 and independent primary-derived checks. |
| Linear AWG4→ACES AP0, Eq.6a | Full published precision; its included CAT02 adaptation applied once; Appendix B checks. |
| Inverses when needed | Label as derived inverses, not separately published coefficients; test both multiplication orders. |

Freeze column-vector multiplication and its array implementation explicitly.
Use separate scalar matrix references, basis/negative/over-range vectors and
transpose/wrong-channel/double-adaptation controls. Preserve signed out-of-gamut
values. An invertible matrix or a plausible preview establishes neither a
camera spectral match nor color-chart accuracy.

## Unit 5D — independent piecewise LogC4 verification

Implement the Section 4 functions [S5-01/S5-03] in the existing MATLAB-language
layer and an independently written scalar Python oracle for acceptance.
Freeze `a=(2^18-16)/117.45`, `b=(1023-95)/1023`, `c=95/1023`;
derive `s` and `t` from Eqs.2b/2c. Encode uses a linear branch below `t` and
the logarithmic branch at/above `t`; decode uses a linear branch below zero
and the exponential branch at/above zero. Preserve signed values and do not
clamp either domain to `[0,1]`. The scene-linear curve is EI-independent.

Verify encoding and decoding separately against equations/CTL-derived scalar
references and Appendix B vectors; round-trip agreement alone is insufficient.
Predeclare absolute/relative tolerances from binary64 error and the source
table's decimal precision. Test `t` and zero exactly, representable neighbors
on both sides, continuity, local slopes, monotonicity, scene black, 0.18,
negative values, values above one and declared safe numeric extremes.
Exercise both round-trip directions over fixed signed/log-spaced fixtures.
Reject NaN/Inf, complex data and overflow rather than silently clipping.

Test wrong thresholds, omitted linear branches, constants, base-10 logarithms,
EI multiplication, negative clamping and matrix-before-decoding mistakes.
Applying the curve to camera RGB is only a curve test, not an AWG4/LogC4 color
space claim. Floating outputs are primary; packed integer/legal-range output
needs its own explicit quantization contract and is deferred initially.

## Unit 5E — artifacts, previews and complete acceptance

Freeze a new `ALEV4-SYNTHETIC-COLOR` versioned contract before serialization.
Preserve original bundles unchanged and bind source payload/manifest hashes.
Retain normalization, demosaic, camera RGB, assumed mapping, linear AWG4 and
LogC4 values with exact shapes, channels, units/domains, masks, source versions,
coefficients, operation order and source/runtime/dependency identities.
Specify binary64/logical little-endian payloads, explicit C row-major order,
bounded metadata/sample counts, no-overwrite publication and owned cleanup.
An independent reader must recompute deterministic stages from actual bytes
and the declared profile/reference constants; repairing a hash must not hide
inconsistent values, masks or domain labels.

Use small synthetic dark/flat/ramp/edge/color-patch fixtures, all Bayer phases,
cropped structured frames, clipping cases and analytical AWG4 vectors. Export
display previews separately with explicit exposure, target display conversion,
tone/clip policy and invalid-pixel visualization. Any preview transform is a
declared visualization assumption; preview pixels never supply sensor noise,
dynamic-range, color-calibration or acceptance statistics [S5-04].

Complete acceptance requires one identified clean source revision and:

1. Every preserved Phase 1–4 numerical/ISET, artifact, failure-reporting and
   separate-process demo/repeat gate, including all nine Phase 4 suites.
2. All 5A–5D deterministic, domain/mask, boundary and invalid-input checks;
   independent references and meaningful wrong-model controls.
3. Byte/order/type/shape/unit/domain validation and semantic corruption tests,
   including masks, matrix provenance, source binding and unsafe publication.
4. Separate-process repeats with distinct nonaliased files in each recorded
   runtime; preserve earlier seeded streams and unchanged legacy artifacts.
5. Stale-success invalidation and explicit failure for missing dependencies,
   skipped required gates, partial reports or failed commands. Development and
   core-only execution must remain visibly incomplete.
6. Clean pinned dependencies before/after; exact commands, exits, source SHA,
   runtime, fixture/reference hashes, error metrics and observed local/CI
   evidence. Native MATLAB remains unverified until MATLAB runs these gates.

## Scope retained for later work

Phase 6 owns controlled camera/dark/flat/chart acquisitions, measured spectral
response, camera→AWG4 fitting and held-out uncertainty-aware comparisons.
Phase 7 owns full-frame performance and broader reporting. Advanced demosaic,
noise-aware repair, camera look matching, hardware encoding, proprietary
REVEAL reconstruction, real ARRIRAW containers and camera EI policy are outside
this first Phase 5 implementation. No camera assets or new dependencies are
introduced by this plan; no transform test is evidence of calibrated ARRI color.
