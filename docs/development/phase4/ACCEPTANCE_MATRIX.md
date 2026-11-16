# Phase 4 requirements-to-evidence matrix

**Candidate release status: ACCEPTED.** This index maps the [plan](../../PHASE4_PLAN.md)
to the [design](../../PHASE4_DESIGN.md), [artifact contract](../../PHASE4_ARTIFACTS.md)
and [usage gates](../../PHASE4_USAGE.md). The [local][local] and [CI][ci]
receipts each identify clean source
`ad036efe6bb6d298545055df37cc4b4681c3e8da`, Git tree
`34bf3899c4903a6283ae344076983f948fddfc19`, and **20/20 zero-exit commands**,
`development=false`, `release_accepted=true`. All seven release conditions below
are closed for this candidate. Local Octave **9.4.0** and CI **8.4.0** each
executed **400 numerical groups** and **316 Python tests**; all five candidate
workflows succeeded. The downloaded archive was independently verified and
[retained](../../evidence/phase4/README.md).

Historical development checks below retain their original changing-worktree
scope. A later test-only decimal-text diagnostic correction has a focused
14-group Octave 9.4.0 pass; it does not alter physics predicates or the group
inventory. Its final clean-source publication/CI is separate from candidate
acceptance. [Correction and publication boundary](../../PHASE4_COMPLETION.md#candidate-ci-and-final-evidence-handoff)

## Implementation slices

| Slice and requirement | Concrete implementation | Required test groups / gate | Evidence type |
| --- | --- | --- | --- |
| **4A — configuration, placement, identity** | [`createStructuredNoise`](../../../matlab/+alev4/createStructuredNoise.m), [`structuredNoiseMaps`](../../../matlab/+alev4/structuredNoiseMaps.m), [`structuredNoiseSeed`](../../../matlab/+alev4/structuredNoiseSeed.m), direct/spatial wrappers | `config`: strict schema, all Bayer/ROI parity map identity; `rng`: named-stream oracles, toggles, success/early/late failure restoration; `core`/`spatial`/`sequence`: disabled whole-result identity; `numerical_edges`: represented endpoints and allocation guards. Gate 3. | Exact equality, independent seeded oracles, invalid-input and preallocation sentinels; source inspection is supplementary. |
| **4B — PRNU and dark charge** | [`simulateStructuredExposure`](../../../matlab/+alev4/simulateStructuredExposure.m) | `core`: independent scalar stages, dark-only shared well, zero exposure/fill/PRNU, fixed-map crop identity; `noise`: Poisson moments, independent shot policies, shared-charge covariance; `numerical_edges`: PRNU/dark arithmetic and separate Poisson preflight. Gate 3. | Analytical charge/ADC references and finite-sample mean/variance/covariance bounds; independent-path shot-charge wrong-model controls. |
| **4C — fixed offsets and row/column structure** | Same direct API; retained shared/path electronics and unchanged [`mergeDualGain`](../../../matlab/+alev4/mergeDualGain.m) | `core`: offsets after well, gain/black once, distinct masks, RAW-only merge; `noise`: row/column/frame covariance and variance sums, reused-path/wrong-axis controls; `spatial`: multiband oracle and pre-well-electronics control. Gate 3. | Exact stage/unit/rail checks and statistical comparisons using independent rows, columns or frames, not repeated pixels. |
| **4D — temporal behavior and exposure/EI sweeps** | [`simulateNoiseSequence`](../../../matlab/+alev4/simulateNoiseSequence.m), [`phase4Fixtures`](../../../matlab/+alev4/phase4Fixtures.m) | `sequence`: reset/gapped continuation, index/seed wrap, persistent maps, cancellation, metadata-only EI, exposure scaling, bounds/cleanup; `noise`: frame differences and disjoint temporal pairs; `demo_contract`: four physical exposure/gain sweeps and three sequence roles. Gates 3, 17–19. | Exact absolute-index replay and fixed-map checks; predeclared temporal/difference bounds; actual exported clipping/merge/saturation coverage. |
| **4E — artifacts, demonstrations, release evidence** | [`exportStructuredBundle`](../../../matlab/+alev4/exportStructuredBundle.m), [`readStructuredBundle`](../../../matlab/+alev4/readStructuredBundle.m), [`structuredValidateResult`](../../../matlab/+alev4/structuredValidateResult.m), [`phase4_demo`](../../../matlab/examples/phase4_demo.m), [Python verifier][verifier], [aggregate runner][runner] | `artifact_io`: exact roundtrips, asymmetric C-order bytes, rehashed semantic corruptions, ownership/failure controls; `demo_contract`: all 24 exports/readbacks, stale/partial/fault controls; frozen numerical report checks. Gates 1–20. | Native and independent actual-file checks, analytical reconstruction, subprocess exits, nonaliased fresh-process repeats, source/dependency receipts and observed CI. |

## Suite inventory and historical development evidence

All nine required suites passed both complete candidate runs, totalling
**111 distinct Phase 4 groups**. Earlier focused development checks remain
linked below. The independent verifier freezes their
identities, counts and ordered names; neither a count alone nor a producer's
success flag establishes completeness. This table intentionally omits the full
111-name inventory, which is retained in [`NUMERICAL_SUITES`][verifier].

| Required numerical suite | Groups | Recorded development evidence |
| --- | ---: | --- |
| [`test_phase4_config`](../../../matlab/tests/test_phase4_config.m) | 9 | [Initial exact/invalid/crop checks](agent-reports/w02_d.md); [affected regression rerun](agent-reports/w04_d.md). |
| [`test_phase4_core`](../../../matlab/tests/test_phase4_core.m) | 11 | [Scalar and wrong-model oracles](agent-reports/w02_d.md); [affected regression rerun](agent-reports/w04_d.md). |
| [`test_phase4_noise`](../../../matlab/tests/test_phase4_noise.m) | 11 | [Executed statistical checks](agent-reports/w02_e.md); [independent bound audit](agent-reports/w05_c.md), which did not rerun the suite. |
| [`test_phase4_rng`](../../../matlab/tests/test_phase4_rng.m) | 10 | [Component oracles, toggles and restoration](agent-reports/w02_e.md). |
| [`test_phase4_sequence`](../../../matlab/tests/test_phase4_sequence.m) | 12 | [Sequence execution](agent-reports/w03_f.md); [affected regression rerun](agent-reports/w04_d.md). |
| [`test_phase4_spatial`](../../../matlab/tests/test_phase4_spatial.m) | 10 | [Spatial oracles](agent-reports/w03_f.md); [baseline-validity regression and rerun](agent-reports/w05_d.md). |
| [`test_phase4_artifacts`](../../../matlab/tests/test_phase4_artifacts.m) | 20 | [282 native integrity/fault cases](agent-reports/w04_a.md). |
| [`test_phase4_demo`](../../../matlab/tests/test_phase4_demo.m) | 14 | [121 native demo/fault cases](agent-reports/w04_c.md), including one actual 24-frame export/readback run. |
| [`test_phase4_numerical_edges`](../../../matlab/tests/test_phase4_numerical_edges.m) | 14 | [Allocation-bound/interlock rerun](agent-reports/w06_a.md); [exact boundary diagnostic serialization correction](agent-reports/w08_f.md). |

The 282 artifact cases and 121 demo cases are internal to those groups, not
additional numerical groups. Later focused reruns do not multiply the inventory.

| Evidence class | What has actually been recorded | What remains distinct |
| --- | --- | --- |
| **Wrong-model statistical controls** | [Noise execution](agent-reports/w02_e.md) rejects independent path charge, reused pixel/path/frame streams and wrong spatial axes with the frozen predicates. [Audit](agent-reports/w05_c.md) reconciles 22 non-Gaussian and 59 Gaussian comparisons, allocated false-failure bound 0.008046875 under the ideal independent-draw model. | These comparisons are inside the 11 noise groups. Deterministic wrong-model controls are separate; neither establishes ideal PRNG independence, calibration or detection of every weak temporal correlation. |
| **Python test execution versus inventory** | Gate 2 in both [local][local] and [CI][ci] acceptance executed the complete **316-test** discovery suite successfully. Both full logs are retained; local execution took 29.842 seconds. | This supersedes the earlier 304-test combined execution and the later discovery-only 316 count. Python fixtures remain separate from the native/ISET execution in gate 3. |
| **Actual demo exports/readbacks** | The native demo suite executed all **24** real exports and 24 exact native readbacks. Candidate gates 17–19 also generated and independently verified a primary and separate-process repeat, each containing 48 bundle files plus one summary: **49 files**. | Artificial summary/orchestration controls and copied-repeat fixtures do not supply repeat evidence. The actual command, identity and byte-comparison receipts are retained in both [aggregates][local] and the [downloaded archive audit][audit]. |
| **Runner failure controls** | Both candidate runs completed all four harnesses. Phase 4 retains **163 fixture-only scenarios**: 162 intended nonzero exits and one exit-zero `core_only_never_accepted` scenario whose full-acceptance flag remains false. **One separate complete positive fixture control** precedes that list. [Count audit](agent-reports/w08_f.md), [CI semantic audit][audit] | These execute reporting/error paths with artificial suites, not sensor physics or real ISET. Harness exit zero is the expected outcome after checking intended child failures; it does not turn those child failures into numerical passes. |
| **Preserved Phase 3/2/1 and ISET** | The candidate actually reran all inherited numerical/ISET checks: **135 + 62 + 92 groups**, plus all earlier artifact, failure and fresh-process repeat gates. [Local][local] and [CI][ci] receipts record their zero exits. All 40 earlier native production files and both dependency pins remain unchanged. [Source audit](agent-reports/w06_e.md) | The [entry receipt](../../evidence/phase4-entry/acceptance.json) and [Phase 3 historical CI](../../PHASE3_COMPLETION.md) retain their own source identities. Neither was substituted for candidate execution. |
| **Exact source and CI** | Clean start/end, exact candidate/tree/pins, both 20-command runs, hosted Octave 8.4.0 and all five successful workflow conclusions are retained. The independent audit reran all four byte/semantic verifiers against the downloaded archive and its repeats; all exited zero. [Retained evidence](../../evidence/phase4/README.md), [audit][audit] | These certify the candidate, not later edits. The diagnostic-only correction has focused dirty-worktree evidence; final publication/full CI remains separately scoped in the [completion record](../../PHASE4_COMPLETION.md). |

## Seven release conditions

Gate numbers refer to the frozen [aggregate command sequence][runner]:
1 dependencies before; 2 Python; 3 all native numerical/ISET; 4–7 runner failure
harnesses; 8–10 Phase 1 demo/repeat/verifier; 11–13 Phase 2; 14–16 Phase 3;
17–19 Phase 4; 20 dependencies after. All required commands must execute and
exit zero; `--development` always remains nonrelease.

For every row, the linked [local][local] and [CI][ci] aggregates preserve exact
commands, zero exits, source/dependency identities, repeat checks and the complete
file inventory. The [independent downloaded-evidence audit][audit] checks the
CI archive against those claims; the [retention audit](agent-reports/w09_e.md)
checks the final 87-file package. These executed receipts, not the earlier
development reports alone, close the conditions for the identified candidate.

| Plan condition | Concrete gate / report | Evidence required to close it | Status |
| --- | --- | --- | --- |
| **1. Clean identified source and pinned dependencies** | Runner preflight/final checks; gates **1, 20**; [`verify_submodules.py`](../../../scripts/verify_submodules.py); root `acceptance.json` | Full source SHA/tree, unchanged HEAD, clean start/end including recursive index flags; both clean dependency HEADs/origins matching gitlinks before and after. Observed artifact Git metadata alone is insufficient. | **CLOSED** — [local][local], [CI][ci] |
| **2. Every preserved Phase 1–3 gate and disabled identity** | Gate **3**: [`run_phase4_tests`](../../../matlab/run_phase4_tests.m) → Phase 3 → Phase 2 → Phase 1, real spatial/legacy ISET; gates **4–6, 8–16**; nested and copied phase reports | Complete inherited requirement/pass flags and inventories, source/runtime agreement, disabled direct/spatial/sequence identity groups, earlier artifact/failure results and three independent repeat sets. | **CLOSED** — [local numerical][local-numerical], [CI numerical][ci-numerical], [archive audit][audit] |
| **3. Every implemented Phase 4 check** | Gates **2, 3**; `phase4/validation/phase4-validation.json`; [frozen report verifier][verifier] | All nine suites and exactly 111 ordered groups, full metrics/sample counts/targets/tolerances, no skips; actual combined 316-test Python pass; invalid-input/crop/clipping/RNG/resource results. | **CLOSED** — [local][local], [CI][ci], [numerical report][ci-numerical] |
| **4. Independent actual bytes and semantics** | Gates **10, 13, 16, 19**; `phaseN/validation/phaseN-acceptance.json`; native `artifact_io` and Python corruption tests | Exact inventory, hashes, lengths, shape/type/C-order/units, full-map crop association, complete spatial baseline, charge/electronics/ADC/observed-merge reconstruction; rehashed semantic corruption rejection. | **CLOSED** — [local][local], [CI][ci], four independently rerun verifiers in [audit][audit] |
| **5. Separate-process repetition** | Gates **8–9, 11–12, 14–15, 17–18**, followed by each verifier; `repeat_identity_checks` | Separate commands with distinct regular trees, disjoint device/inode identities across all names, matching same-runtime/version source and byte-identical files; Phase 4 has 24 frames/49 files per tree and verified reset/continuation metadata. | **CLOSED** — all four repeat checks in [local][local], [CI][ci] and [audit][audit] |
| **6. Truthful failure handling** | Gates **4–7**; four `phaseN-runner-failures.json` reports; Python acceptance/report controls | Actual harness counts/exits; rejection of missing/skipped/partial suites, missing prerequisites, stale success, command/storage failures and aliases; gate failure must keep aggregate release acceptance false. | **CLOSED** — [local][local], [CI][ci], exact control-count reconciliation in [audit][audit] |
| **7. Retained execution and observed release CI** | All **20** gates; root receipt/logs/hash inventory; [Phase 4 workflow](../../../.github/workflows/phase4-tests.yml) and inherited workflows | Exact argv/exits, runtime, source/dependency associations, statistics, hashes, limits and repeat receipts; CI run URL/ID, workflow SHA/conclusion, artifact identity/digest and independent downloaded-evidence audit. | **CLOSED** — [evidence and archive](../../evidence/phase4/README.md), [successful workflow snapshot](../../evidence/phase4/ci-run/candidate_run_summary.json), [audit][audit] |

## Tested limits that remain part of acceptance

- **Assumed maps:** actual supplied full-grid/scalar values define each fixed
  realization; labels and seeds do not establish map identity or measured ALEV4
  calibration. PRNU is achromatic and unnormalized; temperature records applicability.
- **Independent temporal model and EI labels:** no correlated/flicker model,
  elapsed-time or firmware EI behavior is implemented. EI changes metadata only.
  Repeatability is scoped to the executed runtime/version; separate noisy crops
  need not equal full-frame random crops.
- **Spatial baseline validity:** the enabled wrapper retains a real legacy
  baseline as verification context and requires that baseline to be numerically
  valid, even where a zero-PRNU direct structured call could succeed. The
  [regression](agent-reports/w05_d.md) checks both gain modes and RNG restoration.
- **Stochastic origin unauthenticated:** readers verify retained support,
  zero-noise constraints and deterministic assembly, not that a plausible draw
  came from its claimed seed/distribution. Statistics and process repeats are
  separate evidence; neither is camera calibration.
- **Portable metadata and native MATLAB:** supported provenance vocabulary,
  exact shapes and the independent 2,000,000-byte plain-JSON bound are checked
  in Python and GNU Octave 9.4.0. [Serializer parity evidence](agent-reports/w06_d.md)
  does not establish native MATLAB execution or MATLAB Unicode/serializer parity.
- **Sample bounds:** 100 million represented numeric/logical values and bounded
  wire bytes/preallocation reservations reject oversized requests. [Allocation
  audit](agent-reports/w06_a.md) establishes count/guard properties, not peak
  memory or practical full-frame throughput guarantees. Enabled structured direct
  exposure of fully active **4608×3164** Open Gate exceeds this guard: **933,101,568
  reserved values at 64 per pixel alone**, before spectral/model overhead. Small
  coordinate-preserving crops do not establish full-frame structured execution.
  The [resource audit](agent-reports/w09_f.md) derives this from the predicate
  without a large allocation; performance work remains Phase 7.

## Retained receipt fields

The [evidence package](../../evidence/phase4/README.md) retains these receipt
fields for the accepted candidate and the full original CI archive. Historical
development evidence and the later focused correction keep their original scope;
neither the package nor this matrix assigns an unknown final publication SHA.

| Receipt | Minimum fields / accompanying evidence |
| --- | --- |
| Root `acceptance.json` | `source_revision`, `source_tree`, `source_clean_at_start`, `source_clean_at_end`, `development=false`, `status`, `release_accepted`, start/end UTC; 20 `commands` with `label`, exact `argv`, `exit_code`, stdout/stderr paths; four `repeat_identity_checks`; complete `files` byte/SHA-256 inventory. |
| Numerical and dependency reports | Runtime name/version and package versions; exact repository/ISETCam/ISETHdrsensor revisions; all nested prerequisite flags/inventories; 111 Phase 4 groups and their metrics; actual Python count; both dependency-check outputs. |
| Failure and artifact reports | Actual scenario counts and intended exits for each phase; 24-frame/49-file Phase 4 counts; source/runtime agreement; `compared_demo_byte_identical=true`; distinct repeat identities, artifact/report hashes and deterministic verification results. |
| CI and archive audit | Exact tested SHA, workflow/run URL and ID, observed status/conclusion and runtime, archive name/ID/size/digest; safe extraction/inventory/hash checks and independent reruns of all four verifiers against downloaded bytes. Native MATLAB remains explicitly unverified. |

[verifier]: ../../../scripts/verify_phase4_artifacts.py
[runner]: ../../../scripts/run_phase4_acceptance.py
[local]: ../../evidence/phase4/local/acceptance.json
[ci]: ../../evidence/phase4/ci/acceptance.json
[local-numerical]: ../../evidence/phase4/local/phase4/validation/phase4-validation.json
[ci-numerical]: ../../evidence/phase4/ci/phase4/validation/phase4-validation.json
[audit]: ../../evidence/phase4/independent/w09_a-ci-semantic-audit.json
