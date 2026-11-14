# Phase 2 numerical contract

Phase 2 implements a **generic, uncalibrated simultaneous dual-gain Bayer
sensor model**. One exposure produces one collected-charge realization and
two electronic readouts. The model does not establish ARRI's proprietary
readout architecture, calibrated ALEV4 equivalence, measured 17-stop
performance, or ARRIRAW support. Phase 1 remains a supported single-gain API.

## Configuration and public entry points

`alev4.createDualGainSensor(overrides)` returns a validated scalar struct.
Passing an existing configuration through the constructor validates it again.
Unknown fields and nonscalar nested structs are errors. Nested overrides use
the named defaults for omitted fields; a wavelength-grid change still needs
matching explicit bin widths and QE, as in Phase 1.

| Field | Contract and illustrative default |
| --- | --- |
| `schema_version` | Character row `'2.0'` |
| `sensor` | Valid Phase 1 baseline configuration; one spectral response, CFA, image size, exposure-independent geometry, `shot_noise` switch, and common `full_well_e=30000` |
| `high_gain` | `gain_dn_per_e=4`, `read_noise_e=1`, `black_level_dn=64`, `adc_bits=12` |
| `low_gain` | `gain_dn_per_e=0.1`, `read_noise_e=5`, `black_level_dn=64`, `adc_bits=12` |
| `merge` | Scalar struct with `start_e=600` and `end_e=900` |

The `sensor` substructure retains the Phase 1 readout fields only for schema
compatibility: `read_noise_e=3`, `gain_dn_per_e=0.5`, `black_level_dn=64`, and
`adc_bits=16`. They do not control either Phase 2 path. Nondefault values in
these four shared fields are rejected to prevent an electronic parameter
from being accepted and silently ignored. Set readout values in `high_gain`
or `low_gain` instead. Neither path has a separate photodiode full-well value.

Both gains must be finite and positive, and the high gain must exceed the low
gain. Read noise is finite, nonnegative RMS electrons. Black levels lie in
the corresponding ADC range; Phase 2 path ADC depths are integers from 2
through 16. A one-bit path has no interior code after conservative rail
exclusion, so it cannot contribute to this merge. Phase 1's ADC range is
unchanged.
Reconstructed electron limits must be finite. The low path must have greater
positive electron headroom than the high path. The merge interval must satisfy
`0 <= start_e < end_e`, end below physical full well, and finish strictly below
the high path's last nonrail code center,
`(2^high_gain.adc_bits - 2 - high_gain.black_level_dn) / high_gain.gain_dn_per_e`.

The observed low-gain code controls the weight and can lag noiseless charge by
half its quantization step. The constructor therefore also requires:

```text
high_first_rail_e = (2^high_gain.adc_bits - 1 - 0.5 - high_gain.black_level_dn)
                    / high_gain.gain_dn_per_e
low_half_step_e = 0.5 / low_gain.gain_dn_per_e
safe_end_e = high_first_rail_e - low_half_step_e
safety_e = 8 * max(eps(high_first_rail_e), eps(low_half_step_e))
merge.end_e <= safe_end_e - safety_e
```

`safe_end_e` must be finite and positive. `eps` is the double-precision spacing
at the given value; the Python verifier uses the corresponding `math.ulp`.
The subtraction avoids an overflowing sum, and the scale-relative allowance
preserves very small valid electron scales. This guard finishes the noiseless
crossfade before high-gain upper-rail exclusion can force an abrupt change in
weight. Its continuity scope is the guarded upper transition with usable
readouts, not every change in rail-fallback selection.
It applies in addition to the physical-well and interior-code bounds above.
It is not a Gaussian-noise confidence margin: arbitrarily large electronic
noise can still reach a rail, and noisy transition selection can remain biased.

The production entry points are:

```matlab
cfg = alev4.createDualGainSensor(overrides);
result = alev4.applyDualGainNoise(expected_electrons, cfg, seed);
result = alev4.simulateDualGainExposure(photon_irradiance, cfg, exposure_s, seed);
merged = alev4.mergeDualGain(high_dn, low_dn, cfg);
```

`applyDualGainNoise` accepts a finite, real, nonnegative electron-expectation
matrix of `cfg.sensor.image_size`. The spectral entry point uses the same
integration helper as Phase 1: photon irradiance in photons/(m^2 s nm),
explicit bin-average spectral densities, effective RGB QE, pixel area, fill
factor, and seconds. It must preserve the existing zero-collection,
underflow, overflow, shape, and input-normalization rules.

## One charge realization, two electronic paths

For expected electrons `mu`, common full well `F`, and path `i`:

```text
Q = Poisson(mu)                 or Q = mu when shot noise is disabled
S = min(Q, F)
R_i = S + read_noise_e_i * Z_i
A_i = gain_dn_per_e_i * R_i + black_level_dn_i
D_i = clip(round(A_i), 0, 2^adc_bits_i - 1)
```

`Z_high` and `Z_low` are independent standard-normal arrays. `Q` and `S` are
shared. Calling the single-gain simulator twice would create two exposures
or incorrectly correlate their electronic noise, so it is not the Phase 2
implementation. Signed read electrons are retained; clipping negative noise
before black-level addition would bias dark frames.

The result retains `expected_electrons`, `collected_electrons`,
`charge_electrons`, `full_well_saturated`, and `seed` once. Each of
`result.high_gain` and `result.low_gain` retains `read_electrons`, `raw_dn`,
`adc_low_clipped`, and `adc_high_clipped`. RAW is `uint16`; electron arrays
are dense doubles. `result.merged` is the output of the public RAW-only merge.
`result.reconstruction_valid` equals
`result.merged.valid & ~result.full_well_saturated`, combining the observable
readout validity with the simulator's known physical-saturation diagnostic.
The spectral entry point also retains incident-photon expectation, exposure,
and input-unit information, using the established Phase 1 conventions.

Physical saturation means `Q >= F`. Diagnostic ADC clipping masks refer to
rounded codes outside the ADC range, before clamping. A code exactly at a
rail is therefore distinct from an observed rounded overflow. Neither
high-gain electronic clipping nor a saturated physical well is silently
relabelled as recovered scene information.

## Merge using observable data

`mergeDualGain` accepts matching real, finite, integer-valued RAW matrices
within each configured ADC range. It reconstructs signed electron estimates:

```text
E_high = (double(high_dn) - high_gain.black_level_dn) / high_gain.gain_dn_per_e
E_low  = (double(low_dn)  - low_gain.black_level_dn)  / low_gain.gain_dn_per_e
t = clip((E_low - merge.start_e) / (merge.end_e - merge.start_e), 0, 1)
w_high = 1 - t^2 * (3 - 2*t)
E_merged = w_high * E_high + (1 - w_high) * E_low
```

The weight uses the observed low-gain reconstruction, never expected charge,
stored charge, or an inaccessible noise-free scene. This crossfade is a
documented reconstruction policy, not a claim of statistically optimal fusion.
The low-path observation used to select the weight can introduce selection
bias in noisy transition samples; acceptance does not claim an unbiased
transition estimator.

RAW alone cannot distinguish a genuinely clipped sample from one that rounded
exactly to a rail. The merge conservatively regards codes `0` and `ADC_max`
as unusable. If only high gain is usable, its weight is one. If only low gain
is usable, its weight is zero. If both are unusable, the result keeps a finite
low-gain estimate with `valid=false` and `weight_high=0`; callers must consult
the validity mask rather than interpret that estimate as recovered charge.

Conservative fallback does not guarantee global monotonicity for every valid
black-offset configuration. For example, with noiseless default gains, high
black level `0` DN, and low black level `0.51` DN, charges just below `0.125`
electrons produce high code `0` and low code `1`. Only low gain is usable, so
the estimate is `(1 - 0.51)/0.1 = 4.9` electrons. At `0.125` electrons, high
gain rounds to code `1`, becomes usable, and supplies `1/4 = 0.25` electrons.
That downward step remains within each selected path's half-step quantization
bound; it is outside the guarded upper crossfade. A true validity bit identifies
an available nonrail observation, not an exact, globally monotonic, or calibrated
estimate. Noisy rail selection also remains outside the noiseless guarantee.

The merge result contains `electrons`, `weight_high`, `valid`, `high_usable`,
and `low_usable`. `valid` means at least one recorded path is away from both
rails. It does **not** establish that the common photodiode avoided full-well
saturation. The simulator retains the physical saturation mask separately;
artifacts must retain this distinction. Merged electrons remain signed and
floating point, with no display normalization or new sensor ADC quantization.

## Reproducibility and numerical limits

Each simulation requires an integer seed in `[0, 2^32-1]`. It saves and restores
the caller's RNG state on return and on errors. Draw both Gaussian arrays in
a fixed order even when one configured standard deviation is zero, so turning
one electronic-noise term off does not shift the other's random realization.
Equal inputs and seeds reproduce outputs within the recorded runtime/version;
MATLAB and Octave are not promised identical streams.

The existing Poisson-mean limit, spectral range checks, and 100-million-pixel
configuration limit remain applicable. These are correctness bounds rather
than memory or throughput promises. Nonfinite intermediate readouts or
reconstructions are explicit errors.

## Deterministic demonstrations and independent artifacts

Use small, documented fixtures spanning the full signal path. A mono-spectral
fixture with equal channel QE can set an analytically known electron map for
every Bayer position; report the irradiance, QE, bin width, collection area,
and exposure needed to derive that map independently.

| Fixture | Target expectation and purpose |
| --- | --- |
| Dark | Zero charge; separate noiseless and seeded read-noise behavior |
| Shadow flat | 10 electrons; high-gain quantization and low-signal selection |
| Transition ramp | Dense sweep through 600 and 900 electrons, extending to both sides |
| Highlight flat | 12000 electrons; high ADC clips while low gain remains useful |
| Physical saturation | 40000 expected electrons; common charge clips to 30000 electrons |
| Noisy flat | Fixed moderate expectation, explicit seed, shared shot noise and independent read noise |

With the default gains, a noiseless 100-electron sample gives high 464 DN and
low 74 DN. A 12000-electron sample gives high 4095 DN after clipping and low
1264 DN. A noiseless 40000-electron expectation stores 30000 electrons and
gives low 3064 DN: a numerically usable low code does not undo physical loss.

Both readout paths use the versioned [Phase 2 bundle](PHASE2_ARTIFACTS.md)
with their actual path parameters. This preserves Phase 1's RAW algorithm
identifier unchanged. Merged electrons use a separately labelled float64
payload; they must not masquerade as a single-gain ADC frame. Retain a shared
exposure identity, both configurations, merge settings, validity and
physical-saturation information, units, runtime, and source/dependency
provenance. Every artifact states its synthetic,
uncalibrated status. An independent Python verifier decodes bytes and
recomputes deterministic fixture and merge expectations rather than trusting
reported success booleans. Fresh-process repeated runs must produce identical
artifacts within one runtime/version.

## Required acceptance evidence

1. Preserve all Phase 1 numerical, RAW, ISETCam, artifact, and dependency gates.
2. Verify shared collected/stored charge and independent analytic per-path
   transfer functions, including rounding boundaries and distinct ADC depths.
3. Measure independent read-noise residuals and shared shot covariance away
   from saturation. In particular, the variance of `R_high-R_low` must match
   `sigma_high^2 + sigma_low^2`, while covariance of the path readings reflects
   the shared shot charge. Statistical tolerances depend on sample count.
4. Verify high-only clipping, low clipping, both-path loss, signed dark output,
   and common physical full-well saturation as separate cases. Electronic
   noise is added after well clipping and must retain excursions on either
   side of a saturated stored-charge value.
5. Check dense noise-free merge ramps through the guarded upper transition,
   fallback behavior, weights in `[0,1]`, endpoint behavior, and reconstruction
   error bounded by
   `w_high/(2*gain_high) + (1-w_high)/(2*gain_low)` for usable paths, allowing
   floating-point tolerance. Retain the lower-rail counterexample above rather
   than claiming global monotonicity across all fallback changes. Quantized
   data cannot be continuously smooth.
6. Reject malformed configuration, incompatible shapes, nonfinite values,
   noninteger RAW, invalid seeds, and unrepresentable arithmetic. Test RNG
   isolation on successful and deliberately failed execution.
7. Execute a separate Phase 2 runner that invalidates stale success before
   work and writes failure evidence before rethrowing an error. Missing
   runtime or skipped prerequisites must never become a phase pass.
8. Decode and independently verify all demo outputs; test artifact corruption,
   repeat in a fresh process, record the tested revision/runtime, and confirm
   pinned dependency checkouts remain clean. Complete evidence requires the
   explicit `phase1_required=true` flag and the passing nested prerequisite;
   repeated artifact sets must have disjoint file identities as well as
   identical bytes, including files with different names.

Geometry/optics, structured noise and dark-current characterization, color
transforms, real-camera calibration, and performance reporting retain their
later roadmap phases. A Phase 2 completion claim requires executed evidence
for this finite scope.
