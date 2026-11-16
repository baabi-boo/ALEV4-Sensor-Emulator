# Phase 4 development record

The requested campaign uses **60 actual delegated tasks in ten waves**. Six
agents belong to each wave; at most three workers run concurrently because the
coordinator occupies the fourth slot. Each report is retained in `agent-reports/`.
A planned assignment is not counted as executed or complete.

## Current checkpoint

- Entry: clean Phase 3 source `5b61230f6b652d7d053910ea32e144bb9441774a`
  passed all 16 aggregate acceptance commands in GNU Octave 9.4.0. Receipts:
  [`../../evidence/phase4-entry/`](../../evidence/phase4-entry/).
- Phase 4 design and sources are frozen in `docs/PHASE4_DESIGN.md` and
  `docs/PHASE4_SOURCES.md`. All new values/maps are assumed.
- The design/entry-evidence commit is published on `master` as
  `3106f42b8308899072744a898703795e71242636`.
- Wave 1 is complete: six actual architecture, API/RNG, artifact, runtime,
  provenance, and quantitative-acceptance tasks.
- Wave 2 is complete: six actual implementation/test tasks. Fixed maps,
  structured single/dual readout, spatial wrapping, independent sequences,
  41 numerical groups and 24 demo fixtures are implemented. The 41 groups
  passed Octave checks; demo export/readback awaits Wave 3. These checks do
  not establish complete Phase 4 acceptance.

## Wave scope

| Wave | Scope | Status |
| --- | --- | --- |
| 1 | Requirements, integration contracts, provenance, runtime, statistical design | Complete: six reports |
| 2 | Fixed maps, structured readout, wrappers, core/noise tests and demos | Complete: six reports |
| 3 | Independent artifacts, native validation, complete runners and sequence/spatial tests | In progress |
| 4 | Integration and semantic corruption/runner failure controls | Planned |
| 5 | Physics, RNG, geometry, artifact and provenance reviews | Planned |
| 6 | Boundary fixes, resource bounds and regression completion | Planned |
| 7 | Documentation and exact-source release preparation | Planned |
| 8 | Independent candidate review and complete acceptance | Planned |
| 9 | Remote CI and retained artifact verification | Planned |
| 10 | Final evidence, handoff and delivery audit | Planned |

Assignments may be refined as actual defects and missing gates are found.
Reports must state executed commands and limits, without invented passes.
Native MATLAB remains unverified; no real-camera calibration is claimed.
