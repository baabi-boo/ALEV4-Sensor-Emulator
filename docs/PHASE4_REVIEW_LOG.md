# Phase 4 review and change log

**Final campaign record: ten completed waves and 60 actual delegated tasks,
2026-11-16 UTC.** Phase 4 structured noise, artifacts and acceptance machinery
are implemented. Candidate `ad036efe6bb6d298545055df37cc4b4681c3e8da` passed
complete clean local and CI acceptance: **20 gates, 400 numerical groups and
316 Python tests** per execution. This record consolidates retained reports;
its final reconciliation did not rerun numerical suites or artifact verifiers.

## Source and campaign status

- Entry source `5b61230f6b652d7d053910ea32e144bb9441774a` passed the preserved
  16-command Phase 3 aggregate in GNU Octave 9.4.0; see the retained
  [entry receipt](evidence/phase4-entry/acceptance.json). It retains its own
  source association and is not substituted for Phase 4 acceptance.
- Accepted candidate
  [`ad036efe6bb6d298545055df37cc4b4681c3e8da`](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/commit/ad036efe6bb6d298545055df37cc4b4681c3e8da),
  tree `34bf3899c4903a6283ae344076983f948fddfc19`, passed all 20 commands
  locally in Octave **9.4.0** and in CI in **8.4.0**. Both receipts record clean
  start/end, `development=false` and `release_accepted=true`.
  [Local receipt](evidence/phase4/local/acceptance.json),
  [CI receipt](evidence/phase4/ci/acceptance.json)
- All five candidate workflows completed successfully:
  [Phase 4](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43795168396),
  [Phase 3](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43795168215),
  [Phase 2](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43795168226),
  [Phase 1](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43795168212),
  and [integrity](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43795168180).
  The downloaded archive and actual independent verification are retained in
  the [evidence package](evidence/phase4/README.md).
- Pins remain ISETCam `3e0253421752eb72f2d1353327dffd0d433abdaf` and
  ISETHdrsensor `ee2dacceb456516de3ecefadd72955154cf3cabe`; both complete
  executions checked clean matching dependencies before and after their gates.
- The campaign completed **60 distinct delegated tasks**, six in each wave.
  The coordinator is additional; at most three workers ran concurrently.
  Every task has a retained report, linked below. Historical task reports
  preserve the evidence and limitations known at their own checkpoint.
- A later test-only decimal-diagnostic correction has focused 14-group Octave
  9.4.0 evidence. All 52 production files match the accepted candidate; all 40
  earlier production files match the entry source. Candidate receipts do not
  become acceptance of the later dirty worktree. Final publication and its
  final-head CI are separately scoped in the [completion record](PHASE4_COMPLETION.md)
  and [release index](evidence/phase4-release-record.json).

## Implemented mechanisms

The [design](PHASE4_DESIGN.md), [usage](PHASE4_USAGE.md),
[artifact contract](PHASE4_ARTIFACTS.md) and [source register](PHASE4_SOURCES.md)
define the supported behavior. Concrete entrypoints and evidence are:

| Mechanism | Implementation and contract | Recorded evidence |
| --- | --- | --- |
| Persistent fixed maps | [createStructuredNoise](../matlab/+alev4/createStructuredNoise.m) and [structuredNoiseMaps](../matlab/+alev4/structuredNoiseMaps.m): separate schema, scalar uniforms or full grids, one-based crop/CFA identity, no normalization or map regeneration. | [2a](development/phase4/agent-reports/w02_a.md), [2d](development/phase4/agent-reports/w02_d.md), [5d](development/phase4/agent-reports/w05_d.md) |
| Charge and electronics | [simulateStructuredExposure](../matlab/+alev4/simulateStructuredExposure.m): spectral factors once, PRNU on photo expectation, dark rate times seconds, separate shot switches, one common well, signed shared/path electronics afterward, gain/black/ADC once. Dual merge uses recorded RAW/configuration only. | [2b](development/phase4/agent-reports/w02_b.md), [2d](development/phase4/agent-reports/w02_d.md), [5a](development/phase4/agent-reports/w05_a.md) |
| Streams and sequences | [structuredNoiseSeed](../matlab/+alev4/structuredNoiseSeed.m) isolates 17 named component streams; [simulateNoiseSequence](../matlab/+alev4/simulateNoiseSequence.m) uses absolute indices through `2^26`, stride 64, repeatable continuation and metadata-only EI. Caller RNG restores on success/failure. | [2e](development/phase4/agent-reports/w02_e.md), [3f](development/phase4/agent-reports/w03_f.md), [5b](development/phase4/agent-reports/w05_b.md) |
| Spatial and disabled compatibility | [simulateStructuredSpatialExposure](../matlab/+alev4/simulateStructuredSpatialExposure.m) preserves a complete valid legacy baseline as context and applies structured readout to sampled irradiance. Valid disabled direct/spatial calls return whole legacy results; disabled sequences retain legacy frames in their new envelope. | [2c](development/phase4/agent-reports/w02_c.md), [3f](development/phase4/agent-reports/w03_f.md), [5d](development/phase4/agent-reports/w05_d.md) |
| Typed artifacts | [exporter](../matlab/+alev4/exportStructuredBundle.m), [reader](../matlab/+alev4/readStructuredBundle.m) and [wire utility](../matlab/+alev4/structuredBundleUtil.m): distinct identity, `structured.json` plus `data.bin`, exact native classes/shapes/units, C row-major little-endian leaves and full retained spatial history. | [3b](development/phase4/agent-reports/w03_b.md), [4a](development/phase4/agent-reports/w04_a.md), [5e](development/phase4/agent-reports/w05_e.md) |
| Independent semantics and release machinery | [native validator](../matlab/+alev4/structuredValidateResult.m), [Python verifier](../scripts/verify_phase4_artifacts.py), [numerical runner](../matlab/run_phase4_tests.m) and [aggregate](../scripts/run_phase4_acceptance.py) check deterministic associations, complete inherited gates, actual exits, disjoint process repeats and source/dependency state. | [3a](development/phase4/agent-reports/w03_a.md), [3c](development/phase4/agent-reports/w03_c.md), [3d](development/phase4/agent-reports/w03_d.md), [3e](development/phase4/agent-reports/w03_e.md), [6c](development/phase4/agent-reports/w06_c.md) |

## Substantive issues found and corrected

These are observed defects or documented implementation corrections. Their
reported checks establish the stated cases, not an additional release pass.

| Case and classification | Concrete correction location | Evidence and observed result |
| --- | --- | --- |
| Identifier rejection: malformed `['x' char(233)]` reached Octave `regexp` and raised an unclassified invalid-UTF-8 error. Runtime validation defect. | `createStructuredNoise.m` / `requireIdentifier` rejects codes outside printable ASCII before regex evaluation. | [2d](development/phase4/agent-reports/w02_d.md): realization/source-ID regressions now receive `ALEV4:InvalidStructuredNoise`; configuration suite 9/9. |
| Represented seed bound: `single(4294967295)` represents `4294967296`, but mixed-class comparison admitted it; disabled spatial dispatch bypassed the corrected core check. Runtime validation defect. | `structuredNoiseSeed.m` and `simulateNoiseSequence.m` / `sequenceSeed` convert scalar representations to binary64 before range/integer comparison; direct/spatial wrappers validate before disabled dispatch. | [2e](development/phase4/agent-reports/w02_e.md): full strict RNG suite 10/10, including 98 invalid-seed calls; [5b](development/phase4/agent-reports/w05_b.md) independently probed represented endpoints and wrap. |
| Allocation checks occurred too late or omitted aggregate retention, including complete legacy plus structured spatial history. Resource-contract gap. | [structuredNumericSamples.m](../matlab/+alev4/structuredNumericSamples.m) counts represented values without conversion. Constructor inventory precedes scans; core `reserveRawSamples`, spatial `reserveSpatialSamples` and sequence `reserveRawSequence` precede the relevant conversion/sampling/index allocations. Spatial checks include both histories, provenance, repeated descriptors and validated bin count. | [2b](development/phase4/agent-reports/w02_b.md) reported the initial gap; [4d](development/phase4/agent-reports/w04_d.md) records 14 edge groups plus 42 affected regression groups passed. Sparse sentinels avoid large dense allocations. |
| Compact metadata was missing from core reservations: a singleton dual result with a 99,999,869-value PRNU descriptor would retain 100,000,011 values while both old checks admitted it. Resource-bound defect. | Core raw/canonical reservations and native/Python semantic predicates add **64 fixed metadata slots**; raw preflight also keeps 32 default slots. | [6a](development/phase4/agent-reports/w06_a.md): descriptor proof, tiny exact 144-value result, guarded sparse rejection and final 14/14 edge pass. [5f](development/phase4/agent-reports/w05_f.md) records the coordinated Python predicate update. No large dense counterexample was allocated. |
| Sparse test interlocks originally guarded `full` only; `isfinite` on sparse zeros can allocate a true entry for every represented element first. Test-safety correction. | [test_phase4_numerical_edges.m](../matlab/tests/test_phase4_numerical_edges.m) / `withFault` independently self-tests both `isfinite` and `full` sentinels before large-shape probes. | [6a](development/phase4/agent-reports/w06_a.md): a four-element probe established the scan behavior; final guarded 14/14 pass supersedes the earlier run, rather than adding another 14 groups. |
| Nested `onCleanup(@cleanupStage)` retained its shared workspace in Octave: short writes leaked an owned stage; throwing writes also leaked a handle. Runtime exporter defect. | `exportStructuredBundle.m` uses explicit catch cleanup, local `openOwned`, handle closure and identity-checked owned removal before rethrowing the original error. | [4a](development/phase4/agent-reports/w04_a.md): 20 groups/282 cases passed, including write/close/publication failures, exact RNG/handle restoration and preserved foreign/replaced sentinels. |
| Python normalized literal path aliases and lacked a final association check after semantic validation. Independent-verifier gaps. | `verify_phase4_artifacts.py` / `directory_path` checks supplied text before `Path`; `entry_snapshot`, `bounded` and `verify_bundle` bind identities/inventory through reads and final semantics. | [4b](development/phase4/agent-reports/w04_b.md): literal dot/repeated/trailing separators, byte-identical replacement, in-place rewrite and added foreign-file controls pass. An already-created `Path` has already normalized its text. |
| Count-matched truncated reports passed: a measured old-verifier control admitted one group per suite, nine total. Report-verification defect. | `verify_phase4_artifacts.py` / `NUMERICAL_SUITES`, `_numerical_suite` freeze all nine identities and **111 ordered names**, exact counts, statuses and literal true flags. | [4f](development/phase4/agent-reports/w04_f.md): same truncated report rejects; 31 report tests and 26 real verifier CLI subprocess controls passed. Synthetic positive reports prove validator behavior only. |
| The passing candidate's `realmin` edge diagnostic became JSON zero; native JSON numeric decoding also rounded the adjacent Poisson value to the limit. Diagnostic-fidelity defect, separate from passing numerical assertions. | `test_phase4_numerical_edges.m` emits both exact boundaries as 17-significant-digit decimal text and verifies serialized values within their existing groups; physics predicates and the 111-name inventory are unchanged. | [8f](development/phase4/agent-reports/w08_f.md): focused edge execution and encode/decode audit; original candidate receipts and Phase 1–3 report writers remain untouched. |
| Incomplete inherited ISET reports and receipt/source-identity edge cases needed stronger release handling. Runner corrections. | `run_phase4_tests.m` requires spatial ISET's complete passed inventory and legacy ISET's positive count. `run_phase4_acceptance.py` atomically replaces complete receipts, preserves nonrelease failure state and rejects explicitly empty expected SHAs. | [3d](development/phase4/agent-reports/w03_d.md): 163 listed scenarios = 162 intentional nonzero exits + one exit-zero `core_only_never_accepted`; one complete positive fixture control is separate. [Fresh count audit](development/phase4/agent-reports/w08_f.md). [3e](development/phase4/agent-reports/w03_e.md): 41 aggregate unittest methods passed; these are orchestration controls. |
| Python accepted retained spatial provenance cells although native legacy encoding rejects them. Typed metadata-contract defect; sensor arithmetic was unaffected. | `verify_phase4_artifacts.py` / `spatial_provenance` validates the typed legacy vocabulary, preserving double matrix shapes, scalar logicals and supported character extents; rejects cells, uint16, nonscalar logicals, rank-three doubles and unsupported empty characters. | [5f](development/phase4/agent-reports/w05_f.md): measured pre-fix acceptance and six added regressions; 73 artifact tests passed at that stage. |
| Packed provenance bypassed legacy plain-JSON size: 100,000 `-pi` values occupied small typed metadata but required 2,000,012 plain-JSON bytes; Python accepted while native rejected. Independent-verifier bound defect. | `spatial_provenance` counts 17-digit numeric tokens, matrix/vector syntax, punctuation, escapes and UTF-8 incrementally against **2,000,000 bytes**, independently of packed/manifest bounds. | [6d](development/phase4/agent-reports/w06_d.md): 79 artifact tests passed after six more controls; native Octave and Python agree at 1,999,999/2,000,000 accepted and 2,000,001 rejected. |

## Fixture corrections and reviews with no reproduced defect

Fixture corrections remain distinct from runtime fixes. Wave 2d corrected native
arity identifiers and cell-valued malformed-struct construction. Wave 3a supplied
a missing PSF origin in its probe. Wave 3f corrected scalar cell options, a fixture
that did not reach its asserted well boundary, a wavelength-error expectation and
suite-report serialization. Wave 4c corrected a parser helper name and uint8
row/column comparison before its final full pass. The reports preserve the
original assertion intent. Wave 2e's temporary diagnostic omitted a
known seed failure only while its fix was pending; its subsequent complete strict
run, rather than that diagnostic, supplies the recorded pass.

[Wave 5a](development/phase4/agent-reports/w05_a.md) and
[5b](development/phase4/agent-reports/w05_b.md) found no further reproduced
physics/stream defect and executed focused independent probes.
[5c](development/phase4/agent-reports/w05_c.md) recomputed statistical bounds and
effective sample counts without rerunning the native suite.
[5d](development/phase4/agent-reports/w05_d.md) added a regression for the existing
valid-legacy-baseline precondition, rather than changing spatial behavior.
[5e](development/phase4/agent-reports/w05_e.md),
[6b](development/phase4/agent-reports/w06_b.md) and
[6c](development/phase4/agent-reports/w06_c.md) reviewed native lifecycle,
failure isolation and CI orchestration within their stated scopes.
[6e](development/phase4/agent-reports/w06_e.md) verified all 40 earlier MATLAB
production files and both pins unchanged at its checkpoint, and ran the dependency
check. [6f](development/phase4/agent-reports/w06_f.md) rechecked primary sources
and assumption/calibration language. These scoped reviews do not establish a
new scientific-suite, clean-source or CI execution.

## Recorded verification evidence

### Complete candidate executions

| Retained execution | Runtime | Zero-exit commands | Numerical groups | Python tests | Source and result |
| --- | --- | ---: | ---: | ---: | --- |
| [Local](evidence/phase4/local/acceptance.json) | GNU Octave 9.4.0 | 20/20 | 400 | 316 | Clean candidate at both ends; accepted |
| [CI](evidence/phase4/ci/acceptance.json) | GNU Octave 8.4.0 | 20/20 | 400 | 316 | Same clean candidate at both ends; accepted |

Each numerical total is **111 Phase 4 + 135 Phase 3 + 62 Phase 2 + 92 Phase 1**.
All four phases' demos and fresh-process repeats passed independent verification;
Phase 1/2/3/4 have **10/6/8/24 frames** and **31/31/66/49 files** per set.
Phase 4 runner controls contain **163 listed scenarios**—162 intended nonzero
exits plus one exit-zero `core_only_never_accepted`—and **one separate full
positive fixture control**. Those controls use artificial suites and do not
add numerical groups. [Independent CI audit](development/phase4/agent-reports/w09_a.md),
[runtime comparison](development/phase4/agent-reports/w09_b.md)

All **81 statistical comparisons** meet their retained bounds: 22 non-Gaussian
and 59 Gaussian comparisons allocate a union bound of **0.008046875**, below
0.01 under the declared draw assumptions. This scoped evidence is not a proof
of ideal PRNG independence or camera calibration. The [acceptance matrix](development/phase4/ACCEPTANCE_MATRIX.md)
closes all seven candidate release conditions against actual receipts.

The final retained package contains **87 files / 2,817,053 bytes**. Its unchanged
CI ZIP is **1,393,948 bytes**, contains 402 files / 18,400,875 expanded bytes,
and includes the full original CI output. Manifest SHA-256:
`458abc5e8c8da88835d4986ee198d18572e629f12424b089d2ff6dbeb2ce4c59`.
All four independent artifact verifiers passed on that archive; four selected
native 8.4-to-9.4 readbacks passed within their stated scope. The initial native
probe's harness error remains in its receipt. [Retention audit](development/phase4/agent-reports/w09_e.md),
[native readback](development/phase4/agent-reports/w09_d.md),
[final evidence index](evidence/phase4-release-record.json)


### Development executions leading to acceptance

The following historical GNU Octave **9.4.0 development executions** supplied
focused evidence before the complete candidate passes. Repeated runs do not
increase the number of distinct groups. Both accepted candidate executions
subsequently regenerated all nine suites together with the inherited gates.

| Required suite | Groups | Recorded executed evidence |
| --- | ---: | --- |
| `test_phase4_config` | 9 | [2d](development/phase4/agent-reports/w02_d.md); repeated in [4d](development/phase4/agent-reports/w04_d.md) |
| `test_phase4_core` | 11 | [2d](development/phase4/agent-reports/w02_d.md); repeated in [4d](development/phase4/agent-reports/w04_d.md) |
| `test_phase4_noise` | 11 | [2e](development/phase4/agent-reports/w02_e.md): 22 non-Gaussian and 59 Gaussian comparisons with frozen bounds |
| `test_phase4_rng` | 10 | [2e](development/phase4/agent-reports/w02_e.md): complete strict run after seed correction |
| `test_phase4_sequence` | 12 | [3f](development/phase4/agent-reports/w03_f.md); repeated in [4d](development/phase4/agent-reports/w04_d.md) |
| `test_phase4_spatial` | 10 | [3f](development/phase4/agent-reports/w03_f.md); final added-baseline regression pass in [5d](development/phase4/agent-reports/w05_d.md) |
| `test_phase4_artifacts` | 20 | [4a](development/phase4/agent-reports/w04_a.md): 282 cases and 763 exact numeric-leaf checks in five primary round trips |
| `test_phase4_demo` | 14 | [4c](development/phase4/agent-reports/w04_c.md): 121 cases; one real 24-frame export with 24 exact readbacks |
| `test_phase4_numerical_edges` | 14 | [4d](development/phase4/agent-reports/w04_d.md); final overhead/sentinel corrections passed in [6a](development/phase4/agent-reports/w06_a.md) |
| **Total: nine suites** | **111** | **Included in both complete clean candidate passes; links record earlier development checks** |

Other recorded evidence is separately scoped: native/Python agreement on 24 demo
bundles and 30 corruptions ([3b](development/phase4/agent-reports/w03_b.md),
[3c](development/phase4/agent-reports/w03_c.md)); Python 3.12.14 artifact tests
79 ([6d](development/phase4/agent-reports/w06_d.md)), demo tests 20
([4c](development/phase4/agent-reports/w04_c.md)), report tests 31
([4f](development/phase4/agent-reports/w04_f.md)), and aggregate tests 41
([3e](development/phase4/agent-reports/w03_e.md)); seven usage blocks and all
nine assertions plus an independent bundle check
([4e](development/phase4/agent-reports/w04_e.md)). These counts describe their
reported executions, not one newly executed combined run. Artificial fixture
controls do not establish numerical execution, genuine ISET work or clean source.

## Ten completed waves

Each row identifies six actual completed tasks. The [campaign ledger](development/phase4/README.md)
records their ordinal ranges and publication checkpoints.

| Wave | Completed contribution | Six actual report links |
| --- | --- | --- |
| 1 | Six completed tasks: requirements, API/RNG, artifact design, runtime, primary sources and quantitative acceptance | [a](development/phase4/agent-reports/w01_a.md), [b](development/phase4/agent-reports/w01_b.md), [c](development/phase4/agent-reports/w01_c.md), [d](development/phase4/agent-reports/w01_d.md), [e](development/phase4/agent-reports/w01_e.md), [f](development/phase4/agent-reports/w01_f.md) |
| 2 | Six completed tasks: fixed maps, structured exposure, spatial/sequence wrappers, core/noise suites and demos | [a](development/phase4/agent-reports/w02_a.md), [b](development/phase4/agent-reports/w02_b.md), [c](development/phase4/agent-reports/w02_c.md), [d](development/phase4/agent-reports/w02_d.md), [e](development/phase4/agent-reports/w02_e.md), [f](development/phase4/agent-reports/w02_f.md) |
| 3 | Six completed tasks: native semantic validation, native/Python artifacts, runners and sequence/spatial suites | [a](development/phase4/agent-reports/w03_a.md), [b](development/phase4/agent-reports/w03_b.md), [c](development/phase4/agent-reports/w03_c.md), [d](development/phase4/agent-reports/w03_d.md), [e](development/phase4/agent-reports/w03_e.md), [f](development/phase4/agent-reports/w03_f.md) |
| 4 | Six completed tasks: artifact/demo fault controls, allocation edges, executable usage and frozen report inventory | [a](development/phase4/agent-reports/w04_a.md), [b](development/phase4/agent-reports/w04_b.md), [c](development/phase4/agent-reports/w04_c.md), [d](development/phase4/agent-reports/w04_d.md), [e](development/phase4/agent-reports/w04_e.md), [f](development/phase4/agent-reports/w04_f.md) |
| 5 | Six completed tasks: independent physics, streams, statistics, spatial, native lifecycle and Python semantics reviews | [a](development/phase4/agent-reports/w05_a.md), [b](development/phase4/agent-reports/w05_b.md), [c](development/phase4/agent-reports/w05_c.md), [d](development/phase4/agent-reports/w05_d.md), [e](development/phase4/agent-reports/w05_e.md), [f](development/phase4/agent-reports/w05_f.md) |
| 6 | Six completed tasks: allocation correction, failure isolation, CI, serializer parity, preserved sources and source claims | [a](development/phase4/agent-reports/w06_a.md), [b](development/phase4/agent-reports/w06_b.md), [c](development/phase4/agent-reports/w06_c.md), [d](development/phase4/agent-reports/w06_d.md), [e](development/phase4/agent-reports/w06_e.md), [f](development/phase4/agent-reports/w06_f.md) |
| 7 | Six completed tasks: navigation, architecture, acceptance matrix, review/completion records and Phase 5 plan | [a](development/phase4/agent-reports/w07_a.md), [b](development/phase4/agent-reports/w07_b.md), [c](development/phase4/agent-reports/w07_c.md), [d](development/phase4/agent-reports/w07_d.md), [e](development/phase4/agent-reports/w07_e.md), [f](development/phase4/agent-reports/w07_f.md) |
| 8 | Six completed tasks: usability/diagnostics, candidate numerical audit, observed CI/archive, handoff and exact edge metrics | [a](development/phase4/agent-reports/w08_a.md), [b](development/phase4/agent-reports/w08_b.md), [c](development/phase4/agent-reports/w08_c.md), [d](development/phase4/agent-reports/w08_d.md), [e](development/phase4/agent-reports/w08_e.md), [f](development/phase4/agent-reports/w08_f.md) |
| 9 | Six completed tasks: independent CI verification, runtime comparison, retention, native readback and resource audits | [a](development/phase4/agent-reports/w09_a.md), [b](development/phase4/agent-reports/w09_b.md), [c](development/phase4/agent-reports/w09_c.md), [d](development/phase4/agent-reports/w09_d.md), [e](development/phase4/agent-reports/w09_e.md), [f](development/phase4/agent-reports/w09_f.md) |
| 10 | Six completed tasks: evidence index, completion/navigation reconciliation, source/handoff audits and final campaign ledger | [a](development/phase4/agent-reports/w10_a.md), [b](development/phase4/agent-reports/w10_b.md), [c](development/phase4/agent-reports/w10_c.md), [d](development/phase4/agent-reports/w10_d.md), [e](development/phase4/agent-reports/w10_e.md), [f](development/phase4/agent-reports/w10_f.md) |

## Publication boundary and remaining limits

The final task inventory is closed at **60 reports / ten waves**. This snapshot
precedes publication of the final documentation/evidence and decimal-diagnostic
correction. Its final commit and five workflow outcomes are not assigned here;
the coordinator must publish to `master` and observe that exact head's CI.
Original candidate receipts remain immutable and are not relabelled as a run
of subsequent edits. The later correction passed **14 focused edge groups** in
a dirty Octave 9.4.0 worktree, preserved all 40 remaining numeric edge metrics,
and changed no production/scientific predicate or frozen group name.
[Wave 8f](development/phase4/agent-reports/w08_f.md),
[final source audit](development/phase4/agent-reports/w10_d.md),
[handoff audit](development/phase4/agent-reports/w10_e.md)

Native MATLAB and its JVM/serializer paths remain unverified. Enabled structured
direct exposure on a fully active **4608×3164** grid exceeds the current
**100,000,000-value** guard: 64 values per photosite alone reserve
**933,101,568 values**, before other overhead. This is a static guard deduction;
no full-frame execution was performed. Small-fixture acceptance time and child
RSS are not FPS or simultaneous aggregate peak-memory measurements.
[Resource audit](development/phase4/agent-reports/w09_f.md)

Random-stream repeatability remains runtime/version scoped; distinct seeds and
statistical checks do not prove ideal independence or authenticate PRNG origin.
The four selected cross-runtime reads do not guarantee generation equivalence.
Independently drawn noisy crops need not equal full-frame crops. Spatial
execution retains its valid legacy-baseline precondition. Concurrent writers,
adversarial filesystem replacement and crash-durable publication remain outside
the supported contract. All new maps/parameters remain assumed: no temperature
law, correlated temporal/flicker model, calibrated ALEV4 equivalence, measured
dynamic range or genuine ARRIRAW claim follows from this phase.

The [Phase 5 post-capture color plan](PHASE5_PLAN.md) remains unimplemented;
measured camera characterization and performance work remain later phases.
