# Phase 1 completion report

**Result: PASS — the generic, uncalibrated, single-gain spectral Bayer baseline is complete.**

The implementation and all required acceptance gates executed successfully in
GNU Octave 8.4.0. Sixty distinct delegated implementation/review tasks were
completed, with at most three sub-agents active alongside the integrating agent.
The [review ledger](PHASE1_REVIEW_LOG.md) records their actual contributions.

## Identified execution evidence

- Tested implementation commit: [`708517d9faabf2052b60ddb38a3497cd8879942f`](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/commit/708517d9faabf2052b60ddb38a3497cd8879942f).
- Full passing workflow: [run 43131574021](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43131574021), job `130896713454`.
- Runtime: GNU Octave **8.4.0**, Ubuntu 24.04 CI runner. Native MATLAB was **not** executed.
- ISETCam pin: `3e0253421752eb72f2d1353327dffd0d433abdaf`.
- ISETHdrsensor pin: `ee2dacceb456516de3ecefadd72955154cf3cabe` (integrity checked; not executed by Phase 1).

The release documentation and explanatory-comment updates follow this tested
implementation. The reports below deliberately retain the actual tested SHA;
they do not pretend to describe an unknown future revision. CI reruns on `main`
and on later implementation changes.

Durable, revision-controlled evidence:

- [Acceptance receipt and artifact checksums](evidence/phase1-acceptance.json).
- [Complete numerical validation report](evidence/phase1-validation.json).
- [Ten-frame demonstration summary](evidence/phase1-demo-summary.json).

These JSON records preserve the values from the actual CI artifacts, formatted
for readability. The complete downloadable CI artifact contains the numerical
report and ten RAW/JSON/PGM triplets plus their summary. Its configured retention
is 14 days; the checked-in records do not expire with that artifact.

## Executed acceptance inventory

| Numerical suite | Passed test groups |
| --- | ---: |
| Core physics, noise, readout and seed endpoints | 13 |
| Configuration edges | 4 |
| Independent spectral properties | 6 |
| Numeric input representations | 7 |
| Fixture geometry and input edges | 7 |
| Numerical range/zero-signal edges | 6 |
| Poisson distribution and sampler edges | 6 |
| Synthetic RAW I/O | 14 |
| Standalone demo contract | 5 |
| Git provenance | 9 |
| Genuine ISET integration and state isolation | 14 |
| **Total across 11 required suites** | **91** |

These are meaningful test groups containing multiple assertions and cases, not
91 individual assertions. Every suite is required by the report verifier.

The same workflow also passed:

- **29 Python unit tests:** 14 independent artifact-verifier tests and 15 dependency-integrity tests.
- The separate subprocess regression proving a failed rerun invalidates stale passing evidence after a successful initial report write.
- Ten full demonstration frames generated twice in **separate Octave processes**.
- Independent RAW decoding, metadata checks, analytical exposure-bracket calculations and preview scaling checks.
- **All 31 demo files byte-identical** between those two processes.
- Exact pinned, initialized, clean dependency checks before and after execution.

The integrating agent also downloaded the final artifact, confirmed its archive
SHA-256, and independently validated the primary artifact set. Repeat identity
is established by the separate-process CI check, not by comparing a folder with
itself or by the downloaded primary set alone.

## Selected measured results

| Check | Observed result |
| --- | --- |
| Independent analytical conversion | 16 incident photons and exactly 6 expected electrons |
| Read noise, configured standard deviation 3 electrons | Mean -0.0005143 electrons; variance 9.05130 electrons squared, target 9 |
| Poisson third moment at mean 10 | 9.69108, within the declared finite-sample bound |
| Deliberately incorrect rounded-Gaussian reference | Third moment -0.45472; correctly rejected as inconsistent with Poisson mean 10 |
| ISET fractional-electron comparison | Maximum relative error about 1.52754e-7; required tolerance 5e-5 |
| ISET and independent-core exposure doubling | Zero measured relative linearity error |

The Poisson checks include means 0.1, 1, 10 and 1000, mixed means around the
algorithm switch, and the supported 1e9-electron endpoint. Moment tests use
sample-size-aware tolerances; PMF checks use conservative Bernstein bounds.
Passing statistical checks is evidence, not a proof of exact finite arithmetic.

## Delivered behavior and limits

The working path is sensor-plane photon irradiance → expected photoelectrons →
one Poisson draw → full-well clipping → signed Gaussian read noise → gain/black
offset → quantization and ADC clipping → labelled synthetic Bayer RAW.

The project includes four CFA patterns, controlled fixtures, exposure brackets,
retained intermediate arrays, a real pinned ISETCam reference path, robust
synthetic RAW round trips, explicit seeds, state restoration and reproducible
numerical reports. The [usage guide](PHASE1_USAGE.md) provides exact commands.

This pass **does not** establish a calibrated ALEV4 sensor, 17-stop performance,
authentic ARRIRAW, calibrated color rendering, native MATLAB execution, or
arbitrary-scene ISET spatial resampling. Format size bounds are not large-frame
performance guarantees. File publication is not a two-file atomic transaction;
concurrent writers to the same output base are unsupported.

The next roadmap item is **Phase 2: independent simultaneous high-gain and
low-gain sensor paths with tested HDR merging**. It is not counted as completed
by Phase 1 or by merely linking ISETHdrsensor.
