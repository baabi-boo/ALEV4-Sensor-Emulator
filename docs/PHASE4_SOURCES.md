# Phase 4 parameter source register

Phase 4 is an independent synthetic noise model. **All new numerical parameter
values and supplied maps are assumed**, including neutral defaults. A published
equation does not make an illustrative parameter an ALEV4 measurement. This
register supplies no ARRI noise calibration, proprietary readout topology,
measured dynamic range, or EMVA compliance claim. Retrieved 2026-11-15
(America/Halifax).

## Published terminology and generic theory

**Record `EMVA1288-LINEAR-4`** — European Machine Vision Association,
*EMVA Standard 1288, Release 4.0 Linear*, 16 June 2021.

Source: <https://www.emva.org/wp-content/uploads/EMVA1288Linear_4.0Release.pdf>

Sections 2.4 and 3.1 describe Poisson photoelectron and thermally generated
electron counts: their variance equals their mean; the dark-current contribution
to the mean scales with exposure. Section 4 distinguishes sensitivity variation
(PRNU), spatial dark-signal variation (DSNU), and dark-current variation (DCNU).
It explicitly excludes DCNU characterization from that release. Section 3.2
does not assume a universal temperature law for modern CMOS sensors. The
standard's measurement procedures do not supply any parameter values for this
project. [EMVA1288-LINEAR-4, §§2.4, 3.1–3.2, 4]

The project therefore keeps an exposure-dependent **dark-current rate map**
separate from an exposure-independent **electronic offset map**. It does not
use one ambiguous DSNU number for both. A simulated dark-frame spatial spread
depends on exposure, temperature conditions, readout path, and clipping; it
must not be labelled an EMVA-measured DSNU value.

## Explicit model assumptions

The names below identify parameter families and provenance records. The usage
and design documents define the exact callable API and serialized fields.

| Record | Quantity, units, and support | Assumed model and applicable conditions |
| --- | --- | --- |
| `ASSUMED-P4-PRNU` | Response multiplier, dimensionless; fixed photosite map on the full grid | Achromatic multiplication of the existing integrated photoelectron expectation. Nominal neutral value is one. Supplied values are not silently recentered or normalized; their actual mean need not be one. No measured spectral or channel dependence is implied. |
| `ASSUMED-P4-DARK-RATE` | Dark-current rate, electrons per pixel per second; nonnegative fixed full-grid map | Expected dark charge is rate times exposure seconds. Spatial variation is called dark-current nonuniformity here. The map is valid only under its declared fixed reference-temperature conditions; no extrapolation law is supplied. |
| `ASSUMED-P4-CHARGE` | Collected photocharge and dark charge, electrons per pixel per frame | Separate, independently seeded Poisson draws when the respective noise switch is enabled; otherwise the corresponding expectation is retained. Their sum reaches one physical well, shared by simultaneous gain paths. The two shot-noise switches have separate meanings. |
| `ASSUMED-P4-OFFSET` | Fixed electronic offsets, signed electrons; shared or explicitly named path maps on the full grid | Added after physical well clipping and before path gain and ADC conversion. They are not accumulated dark charge and do not replace the existing black level in DN. A fixed map remains fixed between frames. |
| `ASSUMED-P4-ROW` | Temporal row-component standard deviation, electron RMS; one scalar draw per active row per frame and configured shared/path component | Zero-mean Gaussian draws, constant across columns within a row. Different rows are independent in the declared model. An RMS setting is a standard deviation, not a variance. |
| `ASSUMED-P4-COLUMN` | Temporal column-component standard deviation, electron RMS; one scalar draw per active column per frame and configured shared/path component | Zero-mean Gaussian draws, constant across rows within a column. Different columns are independent in the declared model. |
| `ASSUMED-P4-FRAME` | Temporal frame-component standard deviation, electron RMS; one draw per frame and configured shared/path component | Zero-mean Gaussian common offset across the active frame. Its covariance is explicit; it is not hidden inside independent per-pixel read noise. |
| `ASSUMED-P4-TEMPORAL` | Frame index and declared ordering; dimensionless index | Independent frames with persistent fixed maps. This is neither an autoregressive process nor a measured flicker or 1/f model. No rolling-shutter or motion timing is inferred from frame order. |
| `ASSUMED-P4-EI-LABEL` | Exposure-index label, dimensionless metadata | A label alone changes no photon exposure, QE, full well, gain, black level, or noise. Exposure and electronic-gain sweeps change their explicit physical/configuration fields. The label is not a camera EI-response calibration. |
| `ASSUMED-P4-IDENTITY` | Sensor-realization identifier and frame/sequence seeds; identifiers and dimensionless integers | Supplied full-grid maps define the persistent realization. Frame seeds control temporal draws without regenerating maps. Reproducibility is restricted to the recorded runtime/version. Identifiers associate evidence; they do not prove measurement. |

Existing effective QE, fill factor, full well, gain, black level and per-pixel
read-noise settings retain their earlier source classifications. Phase 3
geometry provenance remains separate. A published active grid does not make
any noise map measured. Persistent maps are indexed by one-based full-grid
coordinates, then cropped; separately simulated random frames at different
sizes need not match pixel for pixel.

## Derived expectations for verification

These equations are consequences of the **assumed project model**, used as
analytical checks. They are not measurements or a claim that a real camera
obeys every independence assumption. Let `m` be the existing baseline
photoelectron expectation, `p` the supplied response multiplier, `d` the dark
rate, and `t` exposure seconds:

```text
mu_photo = p * m
mu_dark  = d * t
collected = photo_draw + dark_draw
stored = min(collected, full_well)
read_path = stored + fixed_shared + fixed_path
            + temporal_shared + temporal_path + pixel_read_noise
analog_DN = gain_DN_per_e * read_path + black_level_DN
```

The shot-variance term is `mu_photo` only when photo shot noise is enabled,
plus `mu_dark` only when dark shot noise is enabled. Before physical or ADC
clipping, independent electronic component variances add. For one path, two
different pixels share a row variance when they have the same row, a column
variance when they have the same column, and a frame variance for every pair.
Shared components also contribute cross-path covariance; path-specific
components do not. Both gain paths observe the same shot-charge realization.

At equal settings, independent frame differences cancel the fixed-map mean
pattern and have twice the single-frame temporal variance. Changing exposure
also changes the dark-current mean pattern, so the same cancellation argument
does not apply unchanged. Full-well clipping, ADC rails, quantization, and
observed-channel merging change these simple pre-clipping moments and must be
reported separately. The retained component arrays are verification data;
they must not correct a merge using hidden simulation truth.

## Conditions for any later measured record

No measured-map import or fitting claim follows from attaching a source label.
A later measured record needs dataset identity and access rights, camera and
capture mode, temperature conditions and measurement location, exposure and
EI/gain settings, acquisition protocol, raw versus processed status, fitting
method, and uncertainty or its explicit absence. A held-out comparison is
required for a calibration claim. Controlled camera characterization remains
Phase 6; no such evidence is supplied by the synthetic Phase 4 fixtures.
