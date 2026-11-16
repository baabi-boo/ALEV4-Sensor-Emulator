# Phase 4 development record

**Completed campaign: 60 actual delegated tasks in ten waves, 2026-11-16 UTC.**
Each wave contains six distinct workers, `a` through `f`, and six retained
reports. The coordinator is not included in the 60. Available concurrency was
three workers plus the coordinator, so six-task waves used rolling batches.
The final inventory contains exactly `w01_a.md` through `w10_f.md`, without
missing or duplicate assignments. Individual reports distinguish implementation,
executed checks, read-only review and historical intermediate findings.

## Accepted candidate and evidence scope

Candidate [`ad036efe6bb6d298545055df37cc4b4681c3e8da`](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/commit/ad036efe6bb6d298545055df37cc4b4681c3e8da),
tree `34bf3899c4903a6283ae344076983f948fddfc19`, passed complete Phase 4
acceptance in **GNU Octave 9.4.0 locally and 8.4.0 in CI**. Each clean execution
passed **20 command gates, 400 numerical groups and 316 Python tests**, with
all earlier phases preserved. The numerical counts are **111 Phase 4 + 135
Phase 3 + 62 Phase 2 + 92 Phase 1**, counted once per execution. Four phases'
separate-process demo/repeat pairs and independent artifact checks passed.
Both source and pinned dependencies were checked before and after execution.
[Local receipt](../../evidence/phase4/local/acceptance.json),
[CI receipt](../../evidence/phase4/ci/acceptance.json),
[completion record](../../PHASE4_COMPLETION.md)

All five candidate workflows completed successfully. The downloaded Phase 4
archive was independently verified, including actual execution of all four
artifact verifiers. The final retained package contains **87 files / 2,817,053
bytes**, including the unchanged **1,393,948-byte** CI ZIP and the later native
readback supplement. Manifest SHA-256:
`458abc5e8c8da88835d4986ee198d18572e629f12424b089d2ff6dbeb2ce4c59`.
[Evidence index](../../evidence/phase4-release-record.json),
[retention and recheck instructions](../../evidence/phase4/README.md),
[final retention audit](agent-reports/w09_e.md)

The subsequent source delta changes only two test-report diagnostics to exact
17-significant-digit decimal text, with serialization assertions inside their
existing groups. Its focused Octave 9.4.0 execution passed all **14 edge groups**;
production behavior, scientific predicates, tolerances and the 111-name inventory
are unchanged. This dirty-worktree evidence remains separate from the candidate's
complete clean passes. The final documentation/evidence commit and its final-head
CI result were unrecorded when this ledger was prepared; publication and observation
of those five workflows remain the coordinator's delivery step.
[Diagnostic correction](agent-reports/w08_f.md),
[final source audit](agent-reports/w10_d.md),
[final handoff audit](agent-reports/w10_e.md)

## Ten completed waves

All rows below are complete. Letters link to each worker's actual report;
ordinals count delegated tasks, not tests or extra test executions.

| Wave | Task ordinals | Completed scope | Six actual reports |
| --- | --- | --- | --- |
| 1 | 1–6 | Requirements, API/RNG, artifact design, runtime, primary sources and quantitative acceptance | [a](agent-reports/w01_a.md), [b](agent-reports/w01_b.md), [c](agent-reports/w01_c.md), [d](agent-reports/w01_d.md), [e](agent-reports/w01_e.md), [f](agent-reports/w01_f.md) |
| 2 | 7–12 | Fixed maps, structured exposure, spatial/sequence wrappers, core/noise suites and demos | [a](agent-reports/w02_a.md), [b](agent-reports/w02_b.md), [c](agent-reports/w02_c.md), [d](agent-reports/w02_d.md), [e](agent-reports/w02_e.md), [f](agent-reports/w02_f.md) |
| 3 | 13–18 | Native semantic validation, native/Python artifacts, runners and sequence/spatial suites | [a](agent-reports/w03_a.md), [b](agent-reports/w03_b.md), [c](agent-reports/w03_c.md), [d](agent-reports/w03_d.md), [e](agent-reports/w03_e.md), [f](agent-reports/w03_f.md) |
| 4 | 19–24 | Artifact/demo fault controls, allocation edges, executable usage and frozen report inventory | [a](agent-reports/w04_a.md), [b](agent-reports/w04_b.md), [c](agent-reports/w04_c.md), [d](agent-reports/w04_d.md), [e](agent-reports/w04_e.md), [f](agent-reports/w04_f.md) |
| 5 | 25–30 | Independent physics, streams, statistics, spatial, native lifecycle and Python semantics reviews | [a](agent-reports/w05_a.md), [b](agent-reports/w05_b.md), [c](agent-reports/w05_c.md), [d](agent-reports/w05_d.md), [e](agent-reports/w05_e.md), [f](agent-reports/w05_f.md) |
| 6 | 31–36 | Allocation correction, failure isolation, CI, serializer parity, preserved sources and source claims | [a](agent-reports/w06_a.md), [b](agent-reports/w06_b.md), [c](agent-reports/w06_c.md), [d](agent-reports/w06_d.md), [e](agent-reports/w06_e.md), [f](agent-reports/w06_f.md) |
| 7 | 37–42 | Navigation, architecture, acceptance matrix, review/completion records and Phase 5 plan | [a](agent-reports/w07_a.md), [b](agent-reports/w07_b.md), [c](agent-reports/w07_c.md), [d](agent-reports/w07_d.md), [e](agent-reports/w07_e.md), [f](agent-reports/w07_f.md) |
| 8 | 43–48 | Usability/diagnostics, candidate numerical audit, observed CI/archive, handoff and exact edge metrics | [a](agent-reports/w08_a.md), [b](agent-reports/w08_b.md), [c](agent-reports/w08_c.md), [d](agent-reports/w08_d.md), [e](agent-reports/w08_e.md), [f](agent-reports/w08_f.md) |
| 9 | 49–54 | Independent CI verification, runtime comparison, retention, native readback and resource audits | [a](agent-reports/w09_a.md), [b](agent-reports/w09_b.md), [c](agent-reports/w09_c.md), [d](agent-reports/w09_d.md), [e](agent-reports/w09_e.md), [f](agent-reports/w09_f.md) |
| 10 | 55–60 | Evidence index, completion/navigation reconciliation, source/handoff audits and final campaign ledger | [a](agent-reports/w10_a.md), [b](agent-reports/w10_b.md), [c](agent-reports/w10_c.md), [d](agent-reports/w10_d.md), [e](agent-reports/w10_e.md), [f](agent-reports/w10_f.md) |

The coordinator launched the full clean acceptance and managed publication;
a report that audited its receipts is not counted as another numerical run.
Historical reports retain their original checkpoints, including pending CI or
an earlier 86-file retention snapshot. The final acceptance and 87-file package
are reconciled by Waves 9–10 without rewriting those historical observations.
The [review log](../../PHASE4_REVIEW_LOG.md) preserves concrete defects, fixes
and the development checks that led to the accepted candidate.

## Published implementation checkpoints

| Checkpoint | Source and purpose |
| --- | --- |
| Entry | `5b61230f6b652d7d053910ea32e144bb9441774a`: complete 16-command Phase 3 baseline in Octave 9.4.0; [entry evidence](../../evidence/phase4-entry/) |
| Design | `3106f42b8308899072744a898703795e71242636`: structured-noise contract and entry evidence |
| Physics | `3a08553a4d2ee0a88a4fada2f70f04bdce77a2ca`: maps, shared photo/dark charge, electronics and reproducible sequences |
| Artifacts | `638c23d34788fdfcf390f370c0e7e31ed9f71a87`: typed bundles, independent verification and complete acceptance orchestration |
| Accepted candidate | `ad036efe6bb6d298545055df37cc4b4681c3e8da`: fault/edge coverage, allocation/report bounds and all five master workflows |

ISETCam remains pinned at `3e0253421752eb72f2d1353327dffd0d433abdaf` and
ISETHdrsensor at `ee2dacceb456516de3ecefadd72955154cf3cabe`. All **40 pre-existing
MATLAB production files** remain unchanged from entry. All **52 current MATLAB
production files**, 23 script/test-support files and five workflows match the
accepted candidate at the final source audit. [Wave 10d](agent-reports/w10_d.md)

## Count conventions and limits

Phase 4 runner controls have **163 listed scenarios**: 162 intended nonzero
exits plus one exit-zero `core_only_never_accepted` scenario. **One separate
complete positive fixture control** precedes that list. These artificial
orchestration checks do not add numerical groups or execute real ISET physics.
The nine Phase 4 suites retain 111 groups; 282 native artifact cases and 121
demo cases are internal case counts, not extra groups. The statistical suite's
22 non-Gaussian and 59 Gaussian comparisons retain their declared bounds;
repeated runs do not multiply the inventory.
[Count audit](agent-reports/w08_f.md), [CI audit](agent-reports/w09_a.md)

All new maps and parameter values remain **assumed and uncalibrated**. Native
MATLAB remains unverified. Repeatability is runtime/version scoped; four
selected CI 8.4-to-local 9.4 native readbacks establish the stated wire-read
cases, not general cross-runtime generation or PRNG equivalence.
[Source register](../../PHASE4_SOURCES.md), [native readback](agent-reports/w09_d.md)

A fully active **4608×3164** enabled structured direct exposure exceeds the
**100,000,000-value** guard: its 64-values-per-pixel reservation alone requires
**933,101,568 values**. Geometry support and tested crops therefore do not
establish full-frame structured execution. Acceptance timing and child RSS are
fixture measurements, not FPS or aggregate peak-memory guarantees.
[Usage limits](../../PHASE4_USAGE.md#supported-sizes-and-allocation-checks),
[resource audit](agent-reports/w09_f.md)

[Phase 5 demosaic and AWG4/LogC4 work](../../PHASE5_PLAN.md) remains planned
and unimplemented. Measured camera characterization and performance work remain
later phases. No calibrated ALEV4 equivalence, measured dynamic range or genuine
ARRIRAW support follows from this campaign.
