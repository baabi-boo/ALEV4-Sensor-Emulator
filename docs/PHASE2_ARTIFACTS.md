# Phase 2 synthetic bundle contract

This versioned format binds simultaneous readouts and their reconstruction.
It is **synthetic, uncalibrated, and not ARRIRAW**. Phase 1 RAW files and their
algorithm identifier remain unchanged.

## Files and public functions

`alev4.exportDualGainBundle(result, cfg, base_path)` exports a spectral result
from `simulateDualGainExposure`. `alev4.readDualGainBundle(base_path)` returns
`[decoded, metadata]` after validating the complete bundle. Use a fresh base
path; existing files are never overwritten. Concurrent writers to the same
base are unsupported. Preflight every destination, stage writes, publish the
manifest last, and clean up this invocation's incomplete files on failure.
The exporter and demo use the same existing-path guard, including dangling
symlinks when Octave `lstat` or MATLAB's JVM/Java NIO is available.

The extracted file stem must be nonempty and cannot be `.` or `..`, or contain
colon, backslash, or a directory separator. U+0000–U+001F control characters
are forbidden in the supplied base path. Parent directories retain the host
platform's path separators and valid Windows drive-prefix syntax. Apply these
rules when choosing the base; payload names are derived from it automatically.

| Suffix | Representation | Meaning |
| --- | --- | --- |
| `.high.raw` | Little-endian uint16, row-major | High-gain ADC DN |
| `.low.raw` | Little-endian uint16, row-major | Low-gain ADC DN |
| `.merged.f64` | Little-endian IEEE-754 float64, row-major | Signed reconstructed electrons |
| `.flags.u8` | uint8, row-major | Diagnostic/validity bitmask below |
| `.json` | UTF-8 JSON | Complete configuration, association, and provenance |

All planes have `configuration.sensor.image_size`. No header or padding is
present. Float values must be finite. Limits are 100 million pixels and two
million UTF-8 metadata bytes; these are format bounds, not memory guarantees.
Readers reject foreign payload names, length mismatches, invalid codes,
malformed metadata, and inconsistent merge or validity values. Payload names
must be exact basename-relative associations, preventing manifest-directed
path traversal. The native reader rejects symlinked manifest/payload files and
aliased payloads through `lstat` or JVM/Java NIO when either is available. Without
both facilities those file-identity checks are unavailable natively; the
independent Python acceptance verifier still requires regular, nonaliased files.
The JVM branches have not been executed in native MATLAB.

The flags use these fixed bits; adding them produces each byte:

| Bit value | Meaning |
| ---: | --- |
| 1 | Shared physical full well saturated |
| 2 | High path rounded below ADC minimum before clamping |
| 4 | High path rounded above ADC maximum before clamping |
| 8 | Low path rounded below ADC minimum before clamping |
| 16 | Low path rounded above ADC maximum before clamping |
| 32 | High RAW is strictly between ADC rails |
| 64 | Low RAW is strictly between ADC rails |
| 128 | At least one RAW path is usable and physical full well is not saturated |

`merged.valid` is the OR of high/low usability. Bit 128 is the stricter
`reconstruction_valid`. Physical and pre-clamp diagnostic bits are simulator
knowledge; observed RAW alone cannot determine them. Numeric in-range RAW can
still come from a saturated photodiode.

## Manifest

Required fields are `format='ALEV4-SYNTHETIC-DUAL-GAIN'`, `schema_version='1.0'`,
`algorithm_version='phase2-dual-gain-v1'`, `synthetic=true`,
`calibrated_alev4=false`, `authentic_arriraw=false`, `configuration` (the full
validated dual-gain configuration), `image_size`, `exposure_s`, `seed`,
`input_units='photons m^-2 s^-1 nm^-1'`, `array_order='row-major'`,
`byte_order='little-endian'`, `runtime` (`name`, `version`), and `provenance`
(the existing observed-source record). `files` maps `high_raw`, `low_raw`,
`merged_electrons`, and `flags` to their exact filenames. `units` maps those
same keys to `DN`, `DN`, `electrons`, and `bitmask`. `cfa_origin` is
`'top-left (1,1)'`; CFA pattern is in the sensor configuration.

`files` and `units` must contain exactly their four named keys. Runtime names
are `GNU Octave` or `MATLAB`, with a nonempty version. The configuration must
contain its complete declared fields; a reader cannot fill missing recorded
parameters from current defaults. Phase 2 ADC/merge configuration obeys the
quantization-margin constraints in the [numerical contract](PHASE2_DESIGN.md).

The native reader checks original JSON object keys before `jsondecode` can
normalize or discard them. Keys, after decoding legitimate JSON escapes, must
retain portable ASCII identifier spelling and satisfy the native identifier
length rules. Duplicate keys within one object reject, including aliases made
with escape sequences; the same key in different objects is valid. A name such
as `gain-dn-per-e` cannot become the accepted `gain_dn_per_e` silently. The
native scan bounds nesting to 64 containers and fields to 256 per object;
native decoding then validates the complete JSON grammar. Nonfinite numeric
metadata reject. Whitespace and legitimate JSON escapes remain supported.

Finite manifest numbers use 17 significant decimal digits, preserving the
original binary64 value in correctly rounded JSON readers. Native parsers can
introduce a small rounding error, so the writer verifies decoding before any
file is staged: zero and integers within `flintmax` remain exact; other values
must retain their sign/nonzero state and stay within four ULPs at their own
magnitude. A unit-scale tolerance is deliberately not used for metadata,
because that could hide a tiny positive value becoming zero. The decoded
configuration is revalidated and its RAW-only reconstruction must satisfy the
reader's payload tolerance and validity rules. Unsupported precision fails
before publication. This precision-safe encoder is also used by the Phase 1
RAW manifest writer; demo-summary and numerical-report serializers are unchanged.

The manifest binds the two paths by their common base, configuration,
exposure, seed and provenance. This is not a cryptographic authenticity scheme.
The reader reconstructs merge weights from both RAW planes, verifies exported
merged electrons against the reconstructed value `E` with absolute tolerance
`64 * eps(max(1, abs(E)))`, checks rail-derived flags, and rejects diagnostic
flags that contradict corresponding rail codes. Python uses the same
64-ULP allowance with `math.ulp`; altered payload magnitude cannot widen it.
It cannot prove unobserved analog history from RAW; controlled fixtures and
numerical acceptance establish those separate simulator properties.

## Six-frame demonstration

`phase2_demo(output_dir)` emits six bundles and `phase2-demo-summary.json`.
All use a 17-by-257 image, 550 nm single bin of width 10 nm, RGB QE 0.5,
pixel pitch 1e-6 m, fill factor 1, exposure 0.01 s, and default dual electronics.
For these settings, electron expectation is irradiance times 5e-14. Irradiance
is set from the explicit target map. Deterministic frames disable shot noise
and both read noises; the noisy frame enables shot noise and RMS read noises
1 and 5 electrons. Seeds are respectively 201 through 206.

| Name | Target electrons | Purpose |
| --- | --- | --- |
| `dark` | 0 | Black offsets, zero signal |
| `shadow` | 10 | High-gain shadow reconstruction |
| `transition` | Column ramp `400 + 4*(column-1)` | Both merge boundaries and high-gain clipping |
| `highlight` | 12000 | Low-gain highlight recovery |
| `saturation` | 40000 | Physical 30000-electron well limit |
| `noisy` | 250 | Shared shot signal and independent read noise |

The summary records schema `1.0`, phase `2`, completion/synthetic/calibration
flags, runtime, provenance, `frame_count=6`, and `frames`. Each frame records
`name`, `metadata_file`, `exposure_s`, `seed`, `mean_expected_electrons`,
`mean_merged_electrons`, `full_well_saturation_fraction`,
`high_adc_clipping_fraction`, `low_adc_clipping_fraction`, and
`reconstruction_valid_fraction`. The independent Python verifier derives the
fixed fixture maps, checks actual bytes and configuration, calculates expected
noiseless RAW and reconstruction, and checks these summaries. It verifies
fresh-process repeat identity and expected source revision when requested.
The repeated directory must resolve separately, and the complete primary and
repeat sets must have disjoint file identities. A hardlink to a primary file
under a different name cannot establish an independent repeated result.

Retain SHA-256 hashes in the phase acceptance receipt. Generated large arrays
belong in ignored outputs/CI artifacts; concise acceptance, validation, and demo
JSON records are retained under `docs/evidence` after successful execution.
