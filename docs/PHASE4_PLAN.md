# Phase 4 plan: structured noise and readout realism

**Status: implemented; complete release acceptance pending.** The
[implementation design](PHASE4_DESIGN.md) and
[development record](development/phase4/README.md) describe the current APIs,
executed development checks and outstanding release work. This plan preserves
the [roadmap](ROADMAP.md) requirements for PRNU/DSNU, row/column structure,
dark-frame behavior, and clipping/exposure-index sweeps. The
[accepted Phase 3 record](PHASE3_COMPLETION.md) supplies the inherited contract;
the development record retains the executed entry-baseline evidence.

Phase 4 will extend the generic sensor model with explicit, reproducible noise
components. It will not establish calibrated ALEV4 parameters. Color transforms
remain Phase 5, controlled real-camera characterization and parameter fitting
remain Phase 6, and large-workload performance/reporting remain Phase 7.

## Entry evidence and preserved contracts

Before changing production behavior, identify the accepted Phase 3 source,
runtime, dependency revisions, numerical and artifact reports, fresh-process
repeat receipts, and observed CI result. Re-run the preserved baseline on the
selected starting revision and retain its exact commands and source state.
The [Phase 3 usage guide](PHASE3_USAGE.md) supplies the aggregate acceptance
command; a dirty development run must remain labelled as such.

Preserve the existing single- and simultaneous dual-gain APIs, default results,
and artifact identities when the new model is absent or disabled. Geometry
stays separate from readout schemas. A new configuration and versioned artifact
contract must explicitly identify added behavior instead of hiding extra
parameters in fields that existing constructors reject.

One exposure must still produce one common collected-charge realization and
one physical well before the two gain paths branch. Merging must continue to
use observed channels and their declared configuration. Retained expected
values and component maps are verification data, not a way to correct the
merge with inaccessible truth. Physical well saturation, signed electronic
readouts, ADC clipping, conservative rail validity, and reconstruction validity
must remain distinct.

## Parameter provenance before parameter realism

Add a source register for each new parameter or map. Record its name, units,
spatial/temporal support, model equation, source identifier, classification,
and applicable conditions. Classify evidence as published, derived, assumed,
or measured. Synthetic defaults must say **assumed** even when they look
plausible in a rendered image.

| Parameter family | Proposed units and interpretation | Required provenance detail |
| --- | --- | --- |
| PRNU | Dimensionless pixel response multiplier, with a declared nominal mean | Fixed map versus generated distribution; spectral/channel dependence; normalization policy |
| Dark current | Nonnegative electrons per pixel per second | Reference temperature, exposure applicability, rate map and any temperature law |
| Dark-current nonuniformity | Spatial variation of the dark-current rate | Fixed sensor realization; distinguish rate variation from electronic offsets |
| Electronic offset nonuniformity | Signed electrons in a named readout path, or explicitly specified DN after gain | Reference black level, placement relative to gain/ADC, and map generation |
| Row/column components | Electron RMS and any signed fixed offsets | Shared or path-specific placement; row/column axes; spatial covariance model |
| Temporal components | Electron RMS plus explicit temporal model parameters | Frame ordering, time interval, stationarity, correlation and initialization assumptions |

Define **DSNU** precisely in the new design: an exposure-dependent dark-current
map and an exposure-independent readout offset map must not share an ambiguous
number or be counted twice. Do not impose a temperature-doubling rule, hot-pixel
population, or noise spectrum without either a stated synthetic assumption or
an appropriately scoped source.

Measured imports, if supported, need dataset identity, lawful access, camera and
capture mode, temperature, exposure/EI settings, acquisition protocol, processing
method, and reported uncertainty or its explicit absence. A source label alone
does not prove measurement. Fitting an ALEV4 model and validating that fit
against held-out controlled captures belong to Phase 6.

## Slice 4A — configuration, component placement, and identity

Freeze the model and units before choosing API names. Proposed interfaces in
this plan are design work, not callable functions. Specify a disabled state
whose outputs and same-runtime RNG behavior exactly preserve Phases 1–3.
Unknown fields, negative rates, invalid covariance, inconsistent map shapes,
nonfinite values, and unsupported numeric ranges must reject.

Define full-grid sensor maps using Phase 3 coordinates, then select the active
ROI with unchanged Bayer parity. A given photosite must keep its fixed map
value when the caller changes crop. Avoid implying that a newly simulated
smaller noisy frame must equal a crop of a separately drawn full-frame noise
array; state any stronger coordinate-indexed noise guarantee explicitly.

Use separate, explicit identifiers or seeds for the persistent sensor
realization and each frame/temporal sequence. Creating a frame must not redraw
PRNU or fixed offsets. An opt-in component must not accidentally change other
components through an undocumented RNG-consumption dependency. Preserve caller
RNG state on success and failure, and record the generator/runtime contract.

**Acceptance:** disabled-model identity in single/dual and spatial wrappers;
full/cropped map identity for every ROI parity; immutable caller configuration;
seed/state isolation; strict configuration and numerical-range rejection.

## Slice 4B — PRNU and dark-charge generation

Start with explicit deterministic maps and small analytical examples before
adding distribution-based map generators. A minimal proposed model is

`mu_photo(r,c) = response_multiplier(r,c) * mu_baseline_photo(r,c)`

`mu_dark(r,c,t,T) = dark_rate_e_per_s(r,c,T) * exposure_s`

where `mu_baseline_photo` is the existing spectral expectation, including area,
fill factor, exposure, and QE exactly once. The initial PRNU model can be an
achromatic multiplier with nominal mean one; spectral response variation needs
its own stated model. Specify any bounds and normalization instead of silently
renormalizing a supplied map.

Sample photocharge and dark charge according to the declared model and combine
them before the single physical full-well operation. If both are independent
Poisson sources, retain whether separate component draws or one draw of the
combined mean is used: they have the same ideal total distribution but different
recorded component histories and seeded streams. Both electronic paths must
observe the resulting shared charge. Turning photo shot noise off must not
silently decide the dark-current noise policy; expose and test that policy.

**Acceptance:** exact deterministic map/exposure scaling; zero exposure and
zero rate; dark mean/variance versus exposure; constant and heterogeneous maps;
repeatable fixed maps with varying frame noise; finite-sample Poisson checks;
shared dual-path covariance from total shot charge; physical saturation driven
by total stored charge; and a negative control that draws independent path
shot noise. No assumed dark rate is reported as measured sensor behavior.

## Slice 4C — fixed offsets and row/column structure

Add signed electronic offset maps after physical charge clipping and before
the declared gain/ADC stage. Treat existing black level separately so a fixed
offset does not get applied twice. Decide explicitly whether each component is
common to both gain paths or belongs to one path; do not infer that distinction
from an aesthetically plausible texture.

Introduce row and column terms individually, then combine them with per-pixel
read noise. Keep fixed spatial structure distinct from frame-varying row/column
draws. Specify distributions, RMS versus variance, and covariance. A frame-wide
offset may be a separate component if needed; it must not be hidden in an
independence assumption. Electronic noise remains signed and is not clipped back
to the physical well.

**Acceptance:** deterministic placement and gain-unit checks; zero-component
identity; row/column covariance inside and across groups; analytic variance sums
for independent terms; cross-path covariance for declared shared terms and
independence for path-specific terms; offsets near both ADC rails; quantized
dark-frame behavior; and controls for double-counted black levels or noise
mistakenly added before the physical well.

## Slice 4D — temporal behavior and exposure/EI sweeps

Begin with independent frames and add only a finite, documented temporal model
whose statistical expectations can be tested. If an autoregressive component
is introduced, specify coefficient bounds, timestep, stationary variance,
initial state, reset behavior, and sequence continuation. Independent frame
noise, temporally correlated read noise, and fixed sensor maps must have
different lifetimes and reproducibility rules. Do not label a short sequence
as measured flicker or `1/f` noise without the corresponding model and evidence.

Exposure sweeps change collected photo/dark expectations through explicit
seconds. Electronic-gain sweeps change declared path transfer functions and
their quantization/clipping behavior. Define what an **exposure index (EI)**
label means in this simulator before implementing EI sweeps; an EI label alone
must not silently change QE, photon exposure, physical well capacity, or noise.
If a synthetic EI policy alters exposure or gain, record that mapping and
revalidate the dual-gain merge interval for every configuration.

**Acceptance:** independent-frame mean/variance; temporal autocovariance with
sample-size-based tolerances; fixed-map cancellation in appropriate frame
differences; independent equal-variance difference noise of twice the single
frame variance; repeatable reset/continuation behavior; long/short exposure
dark behavior; and sweeps across high-path clipping, merge transitions, low-path
clipping, and physical saturation. Report censored or invalid observations and
the merge's existing limitations. Rolling shutter, motion timing, and camera
firmware behavior are outside this initial noise/readout scope.

## Slice 4E — artifacts, demonstrations, and release evidence

Design a versioned opt-in representation that retains the added configuration,
map/sequence identities, seeds, units, stage order, provenance classifications,
and any component arrays needed for independent checks. Preserve old readers'
meaning; do not emit new semantics with an unchanged old format identifier.
Document what can be recomputed from recorded data and what unobserved analog
history remains unverifiable.

Demonstrations should include deterministic PRNU/offset maps, several dark
exposures, fixed versus temporal row/column examples, a temporal sequence, and
single/dual clipping sweeps. Each figure or table must identify assumed
parameters, sample counts, units, and runtime. Keep sensor statistics separate
from future demosaic/display transforms.

Use independent analytical or scalar references for deterministic components,
finite-sample statistical bounds for stochastic components, and wrong-model
controls that prove the checks detect common mistakes. Predeclare tolerances
and aggregate false-failure allowances for many covariance/lag comparisons.
Do not choose thresholds after inspecting one convenient random seed.

Complete acceptance must require:

1. A clean identified source revision and clean pinned dependencies checked
   before and after execution.
2. Every preserved Phase 1–3 numerical, ISET, artifact, failure-reporting, and
   fresh-process repeat gate, with disabled-model identity evidence.
3. Every implemented Phase 4 slice's deterministic, statistical, invalid-input,
   coordinate, clipping, and RNG/state-isolation checks.
4. Independent artifact checks for actual bytes, hashes, shape/order, units,
   stage association, map identity, and observable reconstruction. Recomputed
   hashes must not let semantically corrupted data pass.
5. Separate-process demo/sequence repetition using distinct nonaliased files,
   compared within the same runtime/version; no cross-runtime stream identity
   claim without executed evidence.
6. Failure-path checks that invalidate stale success and reject partial reports,
   skipped required suites, failed commands, and missing dependencies.
7. Retained commands, runtime, source/dependency revisions, reports, statistical
   summaries, hashes, limits, and the observed release CI result. Native MATLAB
   remains unverified until its relevant gates actually execute.

The next concrete step is to finish the remaining implementation reviews and
execute the complete release gates on an identified clean source revision,
retaining local and CI evidence. The [design](PHASE4_DESIGN.md),
[source register](PHASE4_SOURCES.md) and
[development record](development/phase4/README.md) distinguish the implemented
contract from executed checks and pending acceptance. Plausible structured
noise by itself is not sensor calibration or evidence of measured ARRI dynamic
range.
