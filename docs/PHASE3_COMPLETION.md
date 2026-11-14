# Phase 3 implementation and acceptance record

**Status: implemented; exact-source release acceptance is pending.** This
record does not mark Phase 3 accepted until the required clean-commit local
execution, independent artifacts/repeats and observed CI results are retained.

## Implemented scope

All five slices of the [Phase 3 plan](PHASE3_PLAN.md) are implemented: physical
geometry and crop/CFA binding; conservative cell-average spatial sampling;
finite PSF filtering and physical-frequency OTF/MTF; a restricted genuine
nonuniform ISETCam adapter; and spatial exposure/bundle APIs for both existing
readout modes. The [usage guide](PHASE3_USAGE.md), [design](PHASE3_DESIGN.md),
[source register](PHASE3_SOURCES.md) and [artifact contract](PHASE3_ARTIFACTS.md)
describe the implemented behavior and supported boundaries.

The model remains independent, synthetic and uncalibrated. Published Open Gate
geometry does not establish actual ALEV4 QE, CFA origin, optical transfer,
noise parameters or complete die dimensions. Native MATLAB execution, measured
17-stop performance, genuine ARRIRAW and full-frame throughput are unverified.

## Evidence available during development

The pre-edit baseline passed its exact dependency checks, 47 Python tests and
complete Phase 2/Phase 1 numerical prerequisite; the original source and
runtime are retained in [phase3-baseline.json](evidence/phase3-baseline.json).
Subsequent focused tests and independent reviews are recorded in the
[delegated-task ledger](PHASE3_REVIEW_LOG.md). Early reports that identify an
ancestor HEAD also identify their dirty working-tree or source-file context;
they are not acceptance of uncommitted code on that ancestor.

A preliminary complete numerical run and the eight-fixture spatial demo/repeat
passed before the later review fixes. Those development outputs do not replace
the final gate. The current release command executes all preserved Phase 1/2
requirements together with Phase 3, checks actual source cleanliness and
dependency pins, records 16 external commands, and verifies distinct repeated
artifact sets. `--development` deliberately cannot mark a release accepted.

## Required final closure

1. Freeze a reviewable implementation commit and execute the complete command
   from that exact clean source with GNU Octave.
2. Retain numerical reports, Python and runner-failure results, independent
   artifact receipts, same-runtime repeat checks, source/dependency revisions
   and checksums without relabelling earlier executions.
3. Publish the authorized main-branch update and observe all four workflows.
4. Complete the requested 60 unique tasks in ten waves, retain their factual
   reports and final ledger, and update this record with measured results.

After this gate, the next implementation work is the persistent sensor
realization and structured-noise contract in the [Phase 4 plan](PHASE4_PLAN.md).
Real-camera calibration remains Phase 6.
