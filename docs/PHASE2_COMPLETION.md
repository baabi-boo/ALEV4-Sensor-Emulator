# Phase 2 completion and evidence record

**Release acceptance: PENDING.** The simultaneous dual-gain implementation
and its precommit numerical checks exist, but this document does not yet
identify an accepted release commit or passing release CI. Replace the pending
fields below only with results from the final source revision. The
[review ledger](PHASE2_REVIEW_LOG.md) remains the authority for actual delegated
work; the requested 60 agents and ten waves are not yet recorded as complete.

## Delivered scope

Phase 2 adds a generic, uncalibrated simultaneous dual-gain model. Spectral
integration produces one expected-charge image; one Poisson realization and
one physical full-well clipping operation feed two electronic paths. Each
path has its own input-referred Gaussian read noise, DN/electron gain, black
offset, ADC depth, and clipping diagnostics. Signed electronic readouts remain
available for testing.

The merger reconstructs floating-point electrons from recorded RAW alone.
Its low-channel-controlled crossfade includes a quantization margin before
the high channel reaches its upper rail. Observed rail usability, physical
well saturation, and reconstruction validity remain separate. A low-gain
highlight can survive high-ADC clipping; charge lost at physical full well
cannot be recovered.

A versioned five-file synthetic bundle contains both ADC planes, merged
float64 electrons, packed flags, and configuration/provenance metadata.
Native readback and an independent Python verifier inspect actual payloads,
recompute the merge, and reject contradictory evidence. The seven numerical
suites, separate failure harness, and dedicated CI retain the complete
Phase 1 numerical/ISETCam prerequisite. See [usage](PHASE2_USAGE.md),
[numerical design](PHASE2_DESIGN.md), and [artifact format](PHASE2_ARTIFACTS.md).

## Release identity and retained evidence

| Required release record | Current state |
| --- | --- |
| Tested implementation commit and immutable link | **PENDING** |
| Final `main` commit and relationship to tested implementation | **PENDING** |
| Passing Phase 2 workflow/run/job URL and runtime | **PENDING** |
| Passing preserved Phase 1 workflow/run URL | **PENDING** |
| Passing repository-integrity workflow/run URL | **PENDING** |
| Exact-source local acceptance and clean dependency checks | **PENDING** |
| Six-frame artifacts independently verified and repeated in fresh processes | **PENDING** |
| Completed 60-agent, ten-wave ledger | **PENDING** |

Retain the actual accepted records under these planned repository paths;
they are not existing release evidence merely because their names are listed:

| Planned retained record | Required content |
| --- | --- |
| `docs/evidence/phase2-validation.json` | Complete numerical report, nested Phase 1 prerequisite, runtime, source and dependency revisions |
| `docs/evidence/phase2-acceptance.json` | Independent artifact-verifier receipt, exact source identity, per-file SHA-256 values and distinct-process repeat result |
| `docs/evidence/phase2-demo-summary.json` | Actual six-frame summary matching the accepted files and runtime |
| `docs/evidence/phase2-runner-failures.json` | Executed failure scenarios and their current-process outcomes |

The full CI artifact should retain the corresponding RAW/float/flag payloads.
Its configured retention is 14 days; concise checked-in records provide the
durable audit trail. Keep reports' actual tested SHA when later documentation
commits follow the implementation; do not relabel old output as a new run.

## Observed precommit checks

The following are **local development results, not final release acceptance**.
They were read from `outputs/phase2-review/validation/phase2-validation.json`,
`outputs/phase2-python-final-precommit.log`, and
`outputs/phase2-runner-failures.json` in GNU Octave **9.4.0**. Those ignored
outputs are not durable repository evidence.

The numerical report says `status="passed"` and `phase2_passed=true`, but
its observed repository HEAD is the earlier baseline
`67ea052f767adf1e196ccba2b9af5665e67c1e4b` while Phase 2 changes were uncommitted.
That HEAD is **not an identified Phase 2 implementation revision**. The report
also predates the ongoing numeric-metadata precision repair; regenerate the
release evidence after that repair and the final source freeze.

| Phase 2 suite | Passed test groups in this precommit report |
| --- | ---: |
| Core transfer, shared charge, merge and RNG invariants | 9 |
| Configuration and recorded-RAW input validation | 7 |
| Noise statistics, negative controls and saturated readout order | 8 |
| Synthetic bundle I/O, corruption, publication and parser boundaries | 14 |
| Numerical limits, normalization and error-path isolation | 8 |
| Spectral properties and Phase 1 parity | 7 |
| Demonstration contract and preflight behavior | 7 |
| **Phase 2 total** | **60** |

These are test groups containing multiple assertions and cases, not a count
of individual assertions. The same numerical invocation passed all **91
Phase 1 groups**, including genuine pinned ISETCam integration. The Python
log records **47 tests passed**. These counts are a snapshot and must be
reconciled with the final report after remaining fixes.

The separate failure harness passed five isolated subprocess cases:

1. Missing prerequisites.
2. An injected later assertion.
3. A malformed suite inventory.
4. Duplicate test-group names.
5. Initial report-write refusal.

The first four replace stale success with a failed report and a nonzero
process exit. In the fifth, storage refusal prevents invalidation and the old
bytes remain unchanged; the required nonzero **current process** outcome
governs acceptance. An old JSON success must never substitute for that exit.

## Selected measured precommit results

| Measurement | Observed result | Reference / acceptance context |
| --- | ---: | --- |
| High-path read-noise variance | 0.99842 e² | 1 e² configured |
| Low-path read-noise variance | 24.98432 e² | 25 e² configured |
| Independent read-noise cross-covariance | 0.01626 e² | 0 ± 0.09667 e² |
| Shared high/low shot covariance | 250.29343 e² | 250 ± 7.01875 e² |
| Variance of high minus low | 25.95021 e² | 26 ± 0.71094 e²; shared shot charge cancels |
| Default upper-transition ramp | 5 e maximum error; no descending step | 12,001 samples; error within the convex quantization bound |
| Fractional-black upper-transition regression | 5 e maximum error; no descending step | 10,001 samples; unsafe near-rail interval rejects |
| Saturated-well low read-noise variance | 25.14217 e² | 25 ± 1.36721 e² after physical clipping |
| Deliberately post-noise-clipped low variance | 8.65363 e² | Incorrect processing order correctly rejected |
| ISETCam fractional-electron maximum relative error | 1.52754 × 10⁻⁷ | Required tolerance 5 × 10⁻⁵ |

The main noise measurements use 131,072 samples and analytical
seven-standard-error bounds. The saturated-readout test uses 32,768 samples.
Incorrect exposure pairing and reused electronic-noise draws are rejected
by separate negative controls. These finite-sample checks support the generic
model; they do not measure a physical camera's performance.

## Review corrections and remaining release work

Implemented review corrections include the low-quantization margin at the
upper handoff, rejection of one-bit paths with no usable interior codes,
portable bundle stems, original JSON key/duplicate validation, exact payload
associations, matching merge tolerances, explicit prerequisite flags, and
disjoint primary/repeated artifact identities. Runner inventories reject
duplicate names, and saturation tests protect noise addition after physical
well clipping. The lower-rail fallback counterexample is documented instead
of extending the upper-handoff guarantee beyond its tested scope.

Before changing this document to a release pass, finish and verify numeric
metadata fidelity, freeze the implementation, run the full acceptance
commands on that exact revision, retain receipts and reports, observe the
required GitHub workflow outcomes, and reconcile the completed agent ledger.
The [validation plan](VALIDATION.md) defines the complete gate, including the
separate preserved Phase 1 artifact checks.

## Limits and next phase

No native MATLAB execution, calibrated ALEV4 equivalence, measured 17-stop
performance, genuine ARRIRAW encoding, or calibrated color pipeline is
established here. Default parameters are illustrative. Merge weights selected
from noisy low-gain data can introduce selection bias; the method is not
claimed to be statistically optimal. Custom black offsets can also produce
a downward step when lower-rail fallback switches between quantizers, while
remaining within the selected-path quantization bounds. Validity does not
promise exact recovery or global monotonicity.

After Phase 2 release acceptance, the next roadmap item is **Phase 3:
geometry and optics**. Begin with the bounded geometry/crop/CFA identity
slice in the [Phase 3 plan](PHASE3_PLAN.md), establish primary-source parameter
provenance, and preserve all Phase 1/2 contracts. Structured noise, color
transforms, and controlled real-camera calibration remain later phases.
