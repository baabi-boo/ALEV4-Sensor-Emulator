# Phase 4 completion and acceptance record

**Phase 4's implementation candidate is complete and acceptance-tested.**
Candidate `ad036efe6bb6d298545055df37cc4b4681c3e8da` passed all **20 acceptance
commands**, **400 numerical groups** and **316 Python tests** in GNU Octave
**9.4.0 locally** and **8.4.0 in CI**. Both clean-source aggregates record
`status="passed"`, `release_accepted=true` and `development=false`. All five
candidate workflows succeeded; the downloaded CI artifact was independently
verified and retained. [Local receipt](evidence/phase4/local/acceptance.json),
[CI receipt](evidence/phase4/ci/acceptance.json),
[retention and recheck guide](evidence/phase4/README.md)

These results certify that exact candidate. A later **test-only boundary
diagnostic correction** has a separate focused 14-group Octave 9.4.0 pass;
its final clean-source publication and CI are not asserted by these historical
receipts. The [publication boundary](#candidate-ci-and-final-evidence-handoff)
below keeps the correction, retained evidence and final commit distinct.

## Candidate source and runtime

| Item | Recorded identity or state |
| --- | --- |
| Published implementation candidate | [`ad036efe6bb6d298545055df37cc4b4681c3e8da`](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/commit/ad036efe6bb6d298545055df37cc4b4681c3e8da), branch `master` |
| Candidate tree | `34bf3899c4903a6283ae344076983f948fddfc19` |
| Local numerical runtime | GNU Octave **9.4.0**, reported by the completed numerical gate |
| Local Python runtime | Python **3.12.14**, the executable recorded by the aggregate |
| Candidate CI numerical runtime | GNU Octave **8.4.0**, reported by the archived candidate numerical gate |
| ISETCam pin | `3e0253421752eb72f2d1353327dffd0d433abdaf` |
| ISETHdrsensor pin | `ee2dacceb456516de3ecefadd72955154cf3cabe` |
| Local execution start | `2026-11-16T02:57:33.148035+00:00` |
| Local execution finish | `2026-11-16T03:16:42.436683+00:00`; clean unchanged source and dependencies at completion |
| CI acceptance execution | `2026-11-16T03:00:28.044713+00:00` to `2026-11-16T03:13:29.154273+00:00` |
| Final documentation/evidence and diagnostic-correction revision | Not assigned in this evidence snapshot; its publication and CI must identify that later commit separately |

The local run used a separate clean checkout and the output root
`outputs/phase4-candidate-ad036ef`. Its completed receipt and logs were retained
without alteration. Later commits preserve the original tested SHA, tree,
commands and runtime; copying evidence does not make it an execution of the
commit that publishes the copies. Both dependency pins were checked before
and after each complete acceptance run.

The [clean entry acceptance](evidence/phase4-entry/acceptance.json) passed all
16 inherited commands at `5b61230f6b652d7d053910ea32e144bb9441774a` before
Phase 4 production changes. It and the [accepted Phase 3 release](PHASE3_COMPLETION.md)
retain their own source associations. The accepted candidate executed every
inherited gate again.

## Implemented outcome: slices 4A–4E

The [plan](PHASE4_PLAN.md), [design](PHASE4_DESIGN.md),
[usage guide](PHASE4_USAGE.md), [source register](PHASE4_SOURCES.md), and
[artifact contract](PHASE4_ARTIFACTS.md) define the supported implementation.

| Slice | Delivered contract |
| --- | --- |
| **4A — configuration, placement and identity** | Separate strict model; supplied scalar-uniform/full-grid maps; one-based crop identity and Bayer parity; isolated named component streams and caller RNG restoration. Valid disabled direct/spatial calls return complete legacy results; disabled sequences retain legacy frames in an explicit sequence envelope. |
| **4B — PRNU and dark charge** | Achromatic, unnormalized PRNU multiplies photoelectron expectation. Dark rate in electrons per photosite per second multiplies exposure. Separately controlled photo/dark draws add before **one physical well**, with the same stored charge in both gain paths. |
| **4C — fixed offsets and structured electronics** | Shared and path-specific signed fixed offsets and Gaussian row/column/frame components enter after the well, alongside existing pixel read noise. Gain and black offset apply once. Physical saturation, signed readout, ADC clipping, rail usability and reconstruction validity remain distinct. |
| **4D — independent frames and sweeps** | Persistent maps, absolute frame indices, documented seed schedule, reset/gapped continuation, explicit exposure/gain sweeps and metadata-only EI. Frames are independent under the declared model; there is no implicit temperature, elapsed-time or camera firmware policy. |
| **4E — artifacts and acceptance** | Distinct version 1.0 `ALEV4-SYNTHETIC-STRUCTURED-NOISE` bundles retain complete typed values, full maps, draws and spatial history. Native and independent Python readers reconstruct deterministic semantics. Twenty-four demo frames, strict report inventories, failure controls and the 20-command runner preserve all earlier gates. |

The unchanged dual-gain merge receives only observed high/low RAW and their
configuration. Retained expected charge, fixed maps and component draws never
correct that reconstruction using hidden simulation truth. The enabled spatial
wrapper retains a valid legacy baseline as verification context; its charge
does not contribute to the structured exposure. [Design](PHASE4_DESIGN.md)

## Executed acceptance and numerical inventory

The [requirements-to-evidence matrix](development/phase4/ACCEPTANCE_MATRIX.md)
maps each requirement to concrete suites, controls and receipts. Both complete
candidate runs passed all nine Phase 4 suites. Their frozen inventory is
**111 distinct numerical groups**:

| Required Phase 4 suite | Groups |
| --- | ---: |
| Configuration and fixed maps | 9 |
| Deterministic core | 11 |
| Noise statistics | 11 |
| RNG isolation | 10 |
| Independent sequences | 12 |
| Spatial integration | 10 |
| Native artifact I/O | 20 |
| Demo contract | 14 |
| Numerical edges and allocation guards | 14 |
| **Total** | **111** |

Both candidate runs also passed **135 Phase 3**, **62 Phase 2** and **92 Phase 1**
numerical groups, including the genuine spatial and legacy ISET prerequisites:
**400 groups total per execution**. Groups can contain multiple assertions; internal case
counts and repeated runs do not increase the distinct group inventory.
The independent verifier freezes every required suite identity and ordered
group name. [Inventory controls](development/phase4/agent-reports/w04_f.md)

All 20 commands exited zero in each aggregate:

| Aggregate gates | Recorded local and CI result |
| --- | --- |
| 1 — dependencies before | **Passed**, exit 0; both initialized dependencies clean and matching their pins |
| 2 — complete Python test discovery and execution | **Passed**, exit 0; **316 tests** in each run; local execution took 29.842 seconds |
| 3 — all Phase 4/3/2/1 numerical and ISET checks | **Passed**, exit 0; all 400 groups and required ISET checks; `phase4_passed=true` |
| 4–7 — all four runner-failure harnesses | **Passed**, exit 0 for each harness; intended failure scenarios retain their nonzero child exits |
| 8–16 — Phase 1/2/3 demos, fresh-process repeats and independent verifiers | **Passed**, exit 0; complete artifacts and nonaliased byte-identical repeats |
| 17–19 — Phase 4 demo, fresh-process repeat and independent verifier | **Passed**, exit 0; 24 frames and 49 files in each demo tree |
| 20 — dependencies after; final clean unchanged source and aggregate receipt | **Passed**, exit 0; exact pins, clean unchanged candidate, complete hash inventory and accepted aggregate |

The combined Python executions supersede the earlier discovery-only count.
The [local numerical report](evidence/phase4/local/phase4/validation/phase4-validation.json)
and [CI numerical report](evidence/phase4/ci/phase4/validation/phase4-validation.json)
separately establish native and ISET execution. Fixture controls remain separate:
the Phase 4 harness in each acceptance run
recorded 163 listed scenarios, comprising 162 intended nonzero exits and the
exit-zero `core_only_never_accepted` scenario, which retains `phase4_passed=false`.
One complete positive fixture control runs separately before that list
(`positive_fixture_control_count=1`). These artificial suites supply no
scientific numerical execution. [Failure controls](development/phase4/agent-reports/w03_d.md),
[fresh count audit](development/phase4/agent-reports/w08_f.md)

The statistical suite passed all **81** predeclared comparisons: 22 bounded-moment
and 59 Gaussian comparisons.
Its audited union-bound allocation is **0.008046875 < 0.01**, under the ideal
independent-draw model. Effective counts use independent pixels, rows, columns,
frames or disjoint pairs. Wrong-model controls detect independent path charge,
reused streams and wrong spatial axes with the same predeclared predicates.
These checks do not prove PRNG independence or detection of every weak temporal
correlation. [Independent statistical audit](development/phase4/agent-reports/w05_c.md)

## Verified artifacts and process repeats

The native demo suite executed **24 real exports and 24 exact native
readbacks**. Each complete candidate acceptance additionally generated a new
primary set and a separate-process repeat for every phase, then independently
verified both sets:

| Phase | Verified complete demo frames | Files in each primary/repeat tree |
| --- | ---: | ---: |
| 1 | 10 | 31 |
| 2 | 6 | 31 |
| 3 | 8 | 66 |
| 4 | **24** | **49**: 48 bundle files plus the summary |

Phase 4 fixtures cover fixed maps, dark exposures, electronics, spatial crops,
four physical exposure/gain sweeps and three sequence roles. Both aggregates'
repeat receipts establish separate commands, disjoint file identities including
cross-name aliases, and byte-identical corresponding files within each recorded
runtime/version. [Local repeats](evidence/phase4/local/acceptance.json),
[CI repeats](evidence/phase4/ci/acceptance.json)

After download, all four independent Python artifact verifiers ran again against
the actual CI archive bytes and its actual repeat sets. Every command exited
zero with empty stderr, and every verifier output was byte-identical to its
archived CI receipt. The audit also checked all **401 acceptance inventory
entries** and **402 archive files**. A separate probe successfully read four
selected CI 8.4.0 bundles with the native 9.4.0 reader. That limited wire-format
result does not establish cross-runtime random-stream replay or generation
identity. [Independent audit](evidence/phase4/independent/w09_a-ci-semantic-audit.json),
[selected native readbacks](evidence/phase4/independent/w09_d-native-readback.json)

The structured payload uses true C row-major little-endian order, distinct
from Phase 3's plane-major cube order. Verification checks actual bytes,
shape/type/units, full-map crop association, complete spatial history, charge,
electronics, ADCs and observed-channel merging, including rehashed semantic
corruptions. It cannot authenticate a plausible stochastic draw's claimed seed
or distribution. [Artifact specification](PHASE4_ARTIFACTS.md)

## Concrete defects found and corrected during development

| Reproduced issue | Correction and retained evidence |
| --- | --- |
| A single-precision seed represented as `2^32` escaped mixed-type upper-bound checks; disabled spatial dispatch bypassed validation. | Validate represented scalars in binary64 before range checks and before dispatch; regressions cover all new public wrappers. [Wave 2e](development/phase4/agent-reports/w02_e.md) |
| An Octave nested cleanup cycle left an owned stage and, on a throwing write, an open handle. | Explicit catch cleanup closes owned handles, preserves foreign/replaced identities and rethrows the original error. [Wave 4a](development/phase4/agent-reports/w04_a.md) |
| Self-consistent truncated numerical reports could omit most groups. | Freeze all nine identities and all 111 ordered group names; reject count-matched truncation. [Wave 4f](development/phase4/agent-reports/w04_f.md) |
| The candidate's passing smallest-normal assertions were followed by JSON encoding of the `realmin` diagnostic as zero; native JSON decoding also erased the adjacent Poisson-limit distinction. | Preserve both boundary diagnostics as 17-significant-digit decimal text and assert their exact serialized values inside the existing groups. The original candidate receipt remains unchanged; this corrects diagnostic fidelity without changing physics predicates or the 111-group inventory. [Wave 8f](development/phase4/agent-reports/w08_f.md) |
| A singleton dual exposure could exceed retained-value bounds because compact metadata was omitted. | Reserve 64 additional compact values; regress the exact count and reject sparse oversized requests before scans/densification. [Wave 6a](development/phase4/agent-reports/w06_a.md) |
| Python accepted spatial provenance types and plain-JSON sizes rejected by the preserved native contract. | Enforce the retained vocabulary and independently count the 2,000,000-byte plain-JSON bound, including exact boundary controls. [Wave 5f](development/phase4/agent-reports/w05_f.md), [Wave 6d](development/phase4/agent-reports/w06_d.md) |

The production corrections and strict report inventory are included in the
accepted candidate. The later decimal-text diagnostic correction is the sole
test-source change described separately below. All **52 production MATLAB
files**, including the 40 preserved earlier-phase files, match the accepted
candidate. [Preserved-source audit](development/phase4/agent-reports/w06_e.md),
[candidate production-file audit](development/phase4/agent-reports/w09_d.md)

## Candidate CI and final evidence handoff

All five candidate workflows completed successfully at the exact accepted
source. The [retained public workflow snapshot](evidence/phase4/ci-run/candidate_run_summary.json)
preserves the observed conclusions:

| Workflow | Candidate run | Observed state |
| --- | --- | --- |
| Repository integrity | [43795168180](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43795168180) | Success |
| Phase 1 validation | [43795168212](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43795168212) | Success |
| Phase 2 validation | [43795168226](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43795168226) | Success |
| Phase 3 geometry and optics | [43795168215](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43795168215) | Success |
| Phase 4 structured noise | [43795168396](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43795168396) | Success |

The [retained package](evidence/phase4/README.md) contains **87 files totaling
2,817,053 bytes**, including the original **1,393,948-byte** CI ZIP and readable
local/CI receipts, audit results and the later focused correction. The ZIP's
SHA-256 is `dd1ad67edb8fbc5e14050f97f89cd365eacc61d1972c662d3706ac781349b966`;
the [manifest](evidence/phase4/manifest.json) SHA-256 is
`458abc5e8c8da88835d4986ee198d18572e629f12424b089d2ff6dbeb2ce4c59`.
The original archive has 402 files totaling 18,400,875 expanded bytes. All
85 retained source copies are byte-identical to their originals; the independent
[retention audit](development/phase4/agent-reports/w09_e.md) verified the final
supplemented package without altering the original evidence.

After candidate acceptance, `test_phase4_numerical_edges.m` changed only the
serialization and assertions for two diagnostic values. The corrected file's
SHA-256 is `05568045ddbbb73c8fc95bc9ddbcb6b2fcff5fe068d6c676f2e946bae5e0948d`.
Its focused Octave 9.4.0 execution passed the same **14 numerical-edge groups**,
and an audit preserved the exact binary64 values of all 40 remaining numeric
edge metrics. The strings retain `2.2250738585072014e-308` and
`1000000000.0000001` exactly. Physics predicates, tolerances, production code
and the 111-group inventory did not change. This is **dirty-worktree focused
evidence**, not a full accepted run of the corrected source.
[Correction report](evidence/phase4/post-candidate/w08_f/numerical-edges.json),
[metric audit](evidence/phase4/post-candidate/w08_f/numeric-metric-audit.json)

At this evidence snapshot, the final documentation/evidence commit and its full
CI result remain to be published and observed. Its commit/run identities must
be reported separately; neither the candidate receipts nor this record assign
them in advance. The [development ledger](development/phase4/README.md) records
actual delegated tasks and their reports without treating a planned task as
completed. The original evidence remains a stable record of candidate acceptance.

## Remaining limits and next work

All new values and maps are **assumed**. This is an independent, synthetic,
uncalibrated research model: no measured ALEV4 noise, ARRI dynamic-range result,
EMVA compliance, genuine ARRIRAW support or proprietary calibration is claimed.
Native MATLAB execution remains **unverified**, including serializer parity.
Repeatability is scoped to the executed runtime/version; separate noisy crops
need not equal crops of a larger random frame. [Source register](PHASE4_SOURCES.md)

The temporal model uses independent frames; temperature is an applicability
label and EI is metadata only. The spatial baseline must remain valid even
where a zero-PRNU direct call can succeed.

Enabled structured direct exposure of a fully active **4608×3164** Open Gate
grid exceeds the current **100,000,000-value** sample guard: its 14,579,712
pixels require **933,101,568 reserved values at 64 per pixel alone**, before
spectral/model overhead. Geometry support and small coordinate-preserving
crops therefore do not establish supported full-frame structured execution.
This limit was deduced from the actual guard and scalar arithmetic without a
large allocation. [Resource audit](development/phase4/agent-reports/w09_f.md)

The complete local command took **1,149.432703 seconds**; its Linux child RSS
high-water mark was **156,808 KiB**, not simultaneous aggregate peak memory.
The CI job took **851 seconds**, leaving **1,549 seconds** against its 40-minute
timeout. These fixture-level acceptance measurements are neither per-frame
latency nor full-frame resource guarantees. [Timing and measurement scope](development/phase4/agent-reports/w09_f.md)

The next planned implementation is [Phase 5 demosaic and documented AWG4/LogC4
post-capture transforms](PHASE5_PLAN.md). It remains unimplemented. Controlled
camera characterization remains Phase 6 and performance measurement Phase 7.
[Roadmap](ROADMAP.md)
