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
  passed Octave checks.
- Wave 3 is complete: six actual artifact, verification, runner and
  sequence/spatial tasks. The real demo exports and restores all 24 frames;
  native and independent Python checks reject 30 corrupted bundles. The
  additional sequence/spatial suites bring completed numerical coverage to
  63 groups. Runner controls cover 163 scenarios, and 41 aggregate-runner
  Python tests pass. Published checkpoint:
  `638c23d34788fdfcf390f370c0e7e31ed9f71a87`.
- Wave 4 is complete: six actual artifact/demo, edge/resource, usage and
  strict-report tasks. All nine Phase 4 numerical suites have passed
  individually (111 groups); artifact and demo suites cover 282 and 121
  cases respectively. The four new Python test modules pass 159 tests.
  Fault injection exposed and fixed an Octave cleanup cycle in the native
  exporter. Early descriptor reservations now reject oversized allocations,
  and report verification rejects count-matched truncated suite inventories.
  All seven usage examples and their nine assertions executed successfully.
- Wave 5 is complete: six actual physics, random-stream, statistical,
  spatial, native-I/O and Python-verifier reviews. A retained-baseline
  validity regression and strict typed informational-metadata checks were
  added. The statistical bounds and full-domain seed schedule were checked
  independently.
- Wave 6 is complete: six actual allocation, failure-isolation, CI,
  serializer-bound, preserved-source and primary-source reviews. The core
  reservation now includes compact result metadata; sparse failure probes
  interlock both finite scans and densification. Python and native Octave
  checks agree at the 2,000,000-byte informational JSON boundary. All 40
  pre-existing MATLAB production files and both dependency pins remain
  unchanged. Twelve additional Python regressions accompany the reviews.
- Wave 7 prepares navigation, architecture, validation and release records.
  Full clean Phase 4 acceptance and CI remain pending; the checks above
  are development evidence.

## Wave scope

| Wave | Scope | Status |
| --- | --- | --- |
| 1 | Requirements, integration contracts, provenance, runtime, statistical design | Complete: six reports |
| 2 | Fixed maps, structured readout, wrappers, core/noise tests and demos | Complete: six reports |
| 3 | Independent artifacts, native validation, complete runners and sequence/spatial tests | Complete: six reports |
| 4 | Integration and semantic corruption/runner failure controls | Complete: six reports |
| 5 | Physics, RNG, geometry, artifact and provenance reviews | Complete: six reports |
| 6 | Boundary fixes, resource bounds and regression completion | Complete: six reports |
| 7 | Documentation and exact-source release preparation | In progress |
| 8 | Independent candidate review and complete acceptance | Planned |
| 9 | Remote CI and retained artifact verification | Planned |
| 10 | Final evidence, handoff and delivery audit | Planned |

Assignments may be refined as actual defects and missing gates are found.
Reports must state executed commands and limits, without invented passes.
Native MATLAB remains unverified; no real-camera calibration is claimed.
