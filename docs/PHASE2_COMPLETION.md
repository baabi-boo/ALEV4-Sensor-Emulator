# Phase 2 completion and evidence record

**Phase 2 is implemented and acceptance-tested in GNU Octave 8.4.0 and
9.4.0.** The accepted source is
[`ab1c0bad7cbcf993d0b95980214d45f45f59028c`](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/commit/ab1c0bad7cbcf993d0b95980214d45f45f59028c).
All three required GitHub workflows passed on that revision. Original CI
reports and independent artifact receipts are retained below. This accepts
the generic simultaneous dual-gain model; it does not establish calibrated
ALEV4 hardware equivalence or native MATLAB execution.

The [review ledger](PHASE2_REVIEW_LOG.md) records actual delegated implementation
and review assignments. Agent accounting and final release review remain
separate from the executed scientific acceptance gates.

## Delivered scope

Spectral integration produces one expected-charge image. One Poisson
realization and one physical full-well clipping operation feed two electronic
paths, each with independent input-referred Gaussian read noise, DN/electron
gain, black offset, ADC depth and clipping diagnostics. Signed electronic
readouts remain available for testing. Phase 1 retains its single-gain API,
and both exposure APIs use the same spectral integration kernel.

The merger reconstructs floating-point electrons from recorded RAW alone.
Its low-channel-controlled crossfade includes a quantization margin before
the high channel reaches its upper rail. Observed rail usability, physical
well saturation and reconstruction validity remain separate. Low gain can
recover a highlight that clips the high ADC; it cannot recover charge lost
at physical full well.

A versioned five-file synthetic bundle contains high/low uint16 DN planes,
merged float64 electrons, packed flags and complete configuration/provenance
metadata. Native readback and an independent Python verifier inspect actual
payloads, recompute the merge and reject contradictory evidence. The release
also includes seven numerical suites, a failure-contract harness, six demo
fixtures and dedicated CI. See [usage](PHASE2_USAGE.md),
[numerical design](PHASE2_DESIGN.md) and [artifact format](PHASE2_ARTIFACTS.md).

## Accepted source and CI

| Record | Observed result |
| --- | --- |
| Implementation commit | [`ab1c0bad7cbcf993d0b95980214d45f45f59028c`](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/commit/ab1c0bad7cbcf993d0b95980214d45f45f59028c) |
| Implementation tree | `a2606b1bb3ab4b648fdf2695859de83750deb4f9` |
| Phase 2 CI | [Run 43548974466](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43548974466), [job 132306766229](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43548974466/job/132306766229): **success** |
| Preserved Phase 1 CI | [Run 43548974450](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43548974450), [job 132306766314](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43548974450/job/132306766314): **success** |
| Repository integrity | [Run 43548974435](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43548974435), [job 132306765916](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43548974435/job/132306765916): **success** |
| CI runtime | GNU Octave **8.4.0**, Ubuntu **24.04.5**; confirmed by original job logs |
| Local acceptance runtime | GNU Octave **9.4.0**, on the same committed source with a clean worktree |
| ISETCam pin | `3e0253421752eb72f2d1353327dffd0d433abdaf` |
| ISETHdrsensor pin | `ee2dacceb456516de3ecefadd72955154cf3cabe` |

The implementation was pushed to `main` at the identified SHA. This completion
record, retained evidence and final review ledger belong to a subsequent
documentation/evidence commit. Reports keep their actual tested implementation
SHA; they are not relabelled as execution of that later commit. Consult
[main](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/tree/main) and
[Actions](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions) for the
current branch and workflow state.

Local acceptance checked source cleanliness and exact initialized dependency
checkouts before and after execution. CI performed its own checkout and
dependency checks. These supplement the observed HEAD fields in simulation
metadata; a metadata SHA alone does not prove a clean source tree.

## Retained evidence

The four primary records are byte-for-byte copies of the accepted GitHub
Phase 2 artifact. Their source SHA and runtime remain unchanged.

| Record | Content |
| --- | --- |
| [phase2-validation.json](evidence/phase2-validation.json) | Complete numerical report, nested Phase 1 prerequisite, runtime, source and dependency revisions |
| [phase2-acceptance.json](evidence/phase2-acceptance.json) | Independent artifact receipt, 31 file hashes, analytical fixture checks and fresh-process byte comparison |
| [phase2-demo-summary.json](evidence/phase2-demo-summary.json) | Actual six-frame summary matching the accepted artifacts |
| [phase2-runner-failures.json](evidence/phase2-runner-failures.json) | Five executed failure scenarios and their current-process outcomes |
| [phase2-release-record.json](evidence/phase2-release-record.json) | Source/CI associations, reproduction commands and retained-file SHA-256 catalog |
| [phase2-ci-summary.json](evidence/phase2-ci-summary.json) | Observed workflow/job conclusions and runtime; the release record links original log excerpts |
| [phase2-ci-artifact-audit.json](evidence/phase2-ci-artifact-audit.json) | Downloaded-artifact hash audit and bounded comparison with local acceptance |
| [Local numerical report](evidence/phase2-local-validation.json), [acceptance](evidence/phase2-local-acceptance.json) and [source record](evidence/phase2-local-source-record.json) | Separate GNU Octave 9.4.0 execution, source cleanliness and strict dependency results |
| [Preserved Phase 1 acceptance](evidence/phase2-preserved-phase1-acceptance.json) and [artifact integrity](evidence/phase2-preserved-phase1-artifact-integrity.json) | Ten-frame local demo, independent verification, hashes and disjoint fresh-process file identities |

The downloaded Phase 2 artifact, ID `14095597020`, was 44,446 bytes. Its
SHA-256 matched GitHub's recorded digest:

```text
e87fa6f1744de357c26e77b2d93c9b8820c0ec5a77c998dbd50d1d3c396a654e
```

The full CI artifact contains RAW/float/flag payloads and has a configured
retention of 14 days. Checked-in records provide the durable audit trail.
The [downloaded-artifact recheck](evidence/phase2-ci-downloaded-artifact-recheck.json)
independently validated primary bytes. The archive excludes the repeat
directory, so this recheck does not claim another repeat execution; that
evidence is the original CI acceptance receipt and passing fresh-process step.

## Executed acceptance results

Both CI and local numerical reports passed the same seven Phase 2 suites:

| Phase 2 suite | Passed test groups |
| --- | ---: |
| Core transfer, shared charge, merge and RNG invariants | 9 |
| Configuration and recorded-RAW input validation | 7 |
| Noise statistics, negative controls and saturated readout order | 8 |
| Synthetic bundle I/O, corruption, publication and parser boundaries | 16 |
| Numerical limits, normalization and error-path isolation | 8 |
| Spectral properties and Phase 1 parity | 7 |
| Demonstration contract and preflight behavior | 7 |
| **Phase 2 total** | **62** |

These are test groups containing multiple assertions and cases. The same
invocation passed all **92 Phase 1 groups**, including **14 ISETCam integration
groups** and **15 RAW I/O groups**. The numerical result records
`phase2_passed=true`, `phase1_required=true` and `status="passed"`.
All **47 Python tests** passed in CI and locally; the
[local Python transcript](evidence/phase2-local-python-tests.txt) is retained.
Historical Phase 1 evidence remains unchanged and is distinct from these
new regression runs on the Phase 2 source.

Phase 2 generated six bundles plus one summary: **31 files per process**.
The independent verifier checked row-major/little-endian bytes, reconstructed
electrons, flags, metadata, source/runtime associations and analytical demo
expectations. Separate fresh-process runs were byte-identical within each
runtime, with disjoint primary/repeat file identities. The preserved Phase 1
workflow also passed its separate ten-frame, 31-file demo/repeat gate; local
GNU Octave 9.4.0 repeated and independently checked that gate as well.

Selected deterministic Phase 2 fixtures illustrate the physical boundary:

| Fixture | Expected mean | Reconstructed mean | Reconstruction valid |
| --- | ---: | ---: | ---: |
| Dark | 0 e | 0 e | 100% |
| Shadow | 10 e | 10 e | 100% |
| Transition | 912 e | 912 e | 100% |
| Highlight | 12,000 e | 12,000 e | 100% |
| Physical saturation | 40,000 e | 30,000 e | 0% |

The highlight clips every high-gain ADC sample while low gain remains usable.
The saturation fixture reaches the shared 30,000-electron well and correctly
marks every reconstruction invalid, despite usable low-path codes. The sixth,
noisy 250-electron fixture produced a mean of **250.199588 e** in these runs;
it is checked statistically and through recorded readouts.

The downloaded CI and local binary demo planes happened to match for these
fixtures, while their JSON runtime metadata differed. This observation does
not establish a general cross-runtime RNG or byte-identity guarantee.

## Statistical and numerical evidence

The following values come from the accepted CI numerical report:

| Measurement | Observed result | Reference / acceptance context |
| --- | ---: | --- |
| High-path read-noise variance | 0.99842 e² | 1 ± 0.02734 e² |
| Low-path read-noise variance | 24.98432 e² | 25 ± 0.68360 e² |
| Independent read-noise cross-covariance | 0.01626 e² | 0 ± 0.09667 e² |
| Shared high/low shot covariance | 250.29343 e² | 250 ± 7.01875 e² |
| Variance of high minus low | 25.95021 e² | 26 ± 0.71094 e²; shared shot charge cancels |
| Default upper-transition ramp | 5 e maximum error; no descending step | 12,001 samples; error within the convex quantization bound |
| Fractional-black upper-transition regression | 5 e maximum error; no descending step | 10,001 samples; unsafe near-rail interval rejects |
| Saturated-well low read-noise variance | 25.14217 e² | 25 ± 1.36721 e² after physical clipping |
| Deliberately post-noise-clipped low variance | 8.65363 e² | Incorrect processing order rejected |
| Nonuniform spectral scalar-oracle maximum error | 1.42109 × 10⁻¹⁴ e | 16 configurations |
| ISETCam fractional-electron maximum relative error | 1.52754 × 10⁻⁷ | Required tolerance 5 × 10⁻⁵; exposure-linearity errors both zero |

The main noise measurements use 131,072 samples and analytical
seven-standard-error bounds. The saturated-readout test uses 32,768 samples.
Independent exposure pairing and reused electronic-noise draws are rejected
by separate negative controls. These checks support the stated generic model;
they do not measure a physical camera's performance.

## Failure handling and review corrections

The Phase 2 failure harness passed five isolated subprocess cases: missing
prerequisites, an injected later assertion, malformed suite inventory,
duplicate test-group names and initial report-write refusal. Each injected
failure exited unsuccessfully. The first four replaced stale success with a
failed report. In the fifth, storage refusal prevented invalidation and the
old bytes remained unchanged; the required nonzero **current process** outcome
governs acceptance. The preserved Phase 1 missing-prerequisite harness also
passed; its [local receipt](evidence/phase2-preserved-phase1-runner-failures.json)
is retained. An old successful JSON file cannot substitute for a failed run.

Review corrections include the low-path quantization margin at the upper
handoff, rejection of one-bit paths without usable interior codes, portable
bundle stems, original JSON key/duplicate validation, exact payload
associations, matching merge tolerances, explicit prerequisite flags and
disjoint repeated-artifact identities. Runner inventories reject duplicate
names, and saturation tests protect noise addition after physical well
clipping. The lower-rail fallback counterexample is documented and covered
without extending the upper-handoff guarantee beyond its tested scope.

The accepted source also fixes tiny-number metadata loss. Both synthetic RAW
exporters emit finite binary64 values using 17 significant digits, validate
native decoding before publication and revalidate the decoded configuration.
Exact zero and integers within `flintmax` must remain exact; other numeric
values must remain within four ULPs at their own magnitude, with no nonzero
value becoming zero or changing sign. The dual exporter additionally checks
that decoded metadata reproduces its merge within the reader's separate
64-ULP payload tolerance. Tiny exposure/QE, extreme scales, unsupported
metadata, bounded size and injected precision failure are covered by the
accepted RAW regressions. This repair concerns RAW metadata; it does not
replace demonstration-summary or numerical-report serializers.

The accepted program arguments, output paths and runtime-qualified reproduction
commands are recorded in the [release record](evidence/phase2-release-record.json),
with entrypoints in [Phase 2 usage](PHASE2_USAGE.md) and the preserved
[Phase 1 usage](PHASE1_USAGE.md). A core-only run is still an incomplete gate.

## Limits and next phase

Native MATLAB execution, calibrated ALEV4 equivalence, measured 17-stop
performance, genuine ARRIRAW encoding, calibrated color and practical
full-frame performance remain unverified. Defaults are illustrative. Merge
weights selected from noisy low-gain data can introduce selection bias; the
method is not claimed to be statistically optimal. Custom black offsets can
produce a downward step when lower-rail fallback switches between quantizers,
while remaining within the selected-path quantization bounds. Validity does
not promise exact recovery or global monotonicity. Concurrent writers to one
bundle base are unsupported.

The next roadmap item is **Phase 3: geometry and optics**. Begin with the
bounded geometry/crop/CFA identity slice in the [Phase 3 plan](PHASE3_PLAN.md).
Create a primary-source parameter register, distinguish published, measured,
derived and assumed values, and preserve the accepted Phase 1/2 contracts.
Spatial resampling and explicit PSF/MTF behavior follow that foundation.
Structured noise, color transforms and controlled real-camera calibration
remain later phases.
