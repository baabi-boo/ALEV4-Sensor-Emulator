# Phase 3 retained evidence

The accepted implementation is **beedd8bfd1cea3c722409ef0f959fcec5420c5f2**,
tree **4da5c68c7e6dbeb13f2e2e04179c2ea5535e390e**. The
[release catalog](phase3-release-record.json) records its complete local and CI
acceptance, exact child command arguments, runtimes, dependency pins and
retained file hashes. Later documentation/evidence commits do not change
the source identity of these executions.

| Evidence | Local acceptance | Candidate CI acceptance |
| --- | --- | --- |
| Numerical runtime | GNU Octave 9.4.0 | GNU Octave 8.4.0 |
| Required commands | 16, all zero exits | 16, all zero exits |
| Python tests | 145 | 145 |
| Numerical groups, Phases 3 / 2 / 1 | 135 / 62 / 92 | 135 / 62 / 92 |
| Primary/repeat files, Phases 1 / 2 / 3 | 31 / 31 / 66 | 31 / 31 / 66 |
| Selected original records | 44 | 44 |

Numerical groups are named groups, not individual assertion counts.
Runner failure/control checks are separately recorded.

## Original and derived evidence

The [local](phase3-local/acceptance.json) and [CI](phase3-ci/acceptance.json)
selections each retain 39 identity files and five large logs using lossless
gzip. Every catalog entry records stored and original lengths and SHA-256.
Decompression reproduces the original bytes. Reports retain their original
source IDs and paths. The logs preserve the observed Octave short-circuit
and ISETCam load-path warnings.

The [CI API summary](phase3-ci-summary.json) is explicitly derived. Its four
successful workflows comprise four jobs, 28 required authored steps and 40
total API steps. Raw API and full job-log inputs were hashed in scratch and
are explicitly classified as unversioned observation inputs.

The [archive audit](phase3-ci-artifact-audit.json) verifies artifact
**14099350761**, run **43558156924**: **1,046,280 bytes**, **294 members**,
SHA-256 **660e1bfe5811b1f707405022059c9c217621b6fdb692801d9606bd24318159be**.
The original aggregate receipt inventories 293 files and excludes itself.

The [separate recheck](phase3-ci-recheck/recheck-run.json) records three
successful Python verifier executions against the downloaded bytes using
frozen candidate scripts. Their retained stdout receipts match the original
CI receipts byte for byte. These checks do not rerun the Octave/ISET
processes or reconstruct random history.

## Retention and scope

The workflow retains the full CI artifact for **14 days**, with recorded
expiry **2026-11-28T04:48:25Z**. The versioned selection preserves reports,
command logs and complete receipt inventories, but not all binary demo
payloads or raw API/job-log inputs.

The catalog hashes 88 original acceptance records and six supporting
records. It has no self-hash. The [review ledger](../PHASE3_REVIEW_LOG.md)
remains a path reference whose task completion count is finalized separately.

Native MATLAB, cross-runtime random-stream identity, calibration, measured
17-stop performance, genuine ARRIRAW, arbitrary ISET imports and practical
full-frame performance remain unestablished.
