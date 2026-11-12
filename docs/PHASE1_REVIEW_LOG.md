# Phase 1 implementation and review ledger

This records distinct delegated tasks, not an invented count of concurrent
workers. At most three sub-agents ran alongside the integrating agent.
Source review and lint are not substitutes for executable acceptance evidence.
The runtime gate uses the actual pinned dependencies under GNU Octave; MATLAB
execution is not claimed unless separately recorded.

| Agent | Focus | Result |
| --- | --- | --- |
| 01 | Physical units and photon/electron contract | Rectangular bins, single electron Poisson draw, ordered readout specified |
| 02 | Pinned ISETCam API research | Identified rounded electron getter, continuous-voltage reference, grid and unit requirements |
| 03 | Statistical acceptance design | Finite-sample mean, variance, PMF and reproducibility tests specified |
| 04 | Sensor configuration and Bayer maps | Implemented strict generic sensor schema and four CFA patterns |
| 05 | Noise and readout | Implemented toolbox-free Poisson sampler and single-gain readout |
| 06 | Synthetic RAW I/O | Implemented row-major little-endian payload and validated manifest reader |
| 07 | ISETCam integration | Implemented genuine scene/optics/sensor comparison and tests |
| 08 | Core physics tests | Implemented analytical, statistical, clipping and invalid-input suites |
| 09 | RAW tests | Added independent byte-order oracle and malformed-file regressions |
| 10 | Demonstration | Implemented ten-frame full demo, metadata, previews and exposure brackets |
| 11 | Runtime/evidence review | Found stale success report and external ISET path conflict risks; fixed |
| 12 | Poisson algorithm review | Confirmed algorithm structure; requested boundary and mixed-mean tests |
| 13 | Readout physics review | Found extreme zero-signal arithmetic issue; requested signed-noise regressions |
| 14 | RAW validation review | Found exporter/reader metadata-size mismatch; requested bounded reads |
| 15 | Numerical endpoint fixes | Implemented zero-signal handling, explicit underflow rejection and tests |
| 16 | RAW size fixes | Enforced shared 2 MB UTF-8 limit, bounded reads and regressions |
| 17 | Poisson boundary tests | Tested mixed means, threshold probabilities, upper endpoint and zero-draw RNG |
| 18 | Dependency integrity | Implemented clean-checkout/pin checks and 15 offline Git-fixture tests |
| 19 | Source provenance | Shared bounded Git metadata reader, worktree support and tests |
| 20 | Independent artifact validation | Python RAW/PGM decoder, analytic expectations, repeat checks and tests |
| 21 | Documentation | Updated architecture, usage, validation and roadmap without premature pass claims |
| 22 | Configuration review | Found sparse-array, size-bound and global spectral-tolerance weaknesses |
| 23 | Configuration fixes | Dense normalization, 100 MP bound, local tolerances and regressions |
| 24 | Failure evidence test | Added isolated subprocess test that invalidates stale passing reports |
| 25 | Independent verifier review | Found missing new gates and same-directory repeat false pass |
| 26 | Spectral properties | Added independent spatial/spectral oracle, additivity and bin-splitting tests |
| 27 | Evidence gate fixes | Required added suites and rejected comparison-directory aliases |
| 28 | ISET scientific/state review | Confirmed uniform-field comparison scope; found session/preference side effects |
| 29 | Statistical review | Requested skew-sensitive Poisson discrimination and rigorous rare-bin bounds |
| 30 | Runtime portability review | Found sparse-input and UTF-8 reporting issues; checked Python 3.10 compatibility |
| 31 | ISET state restoration | Added success/failure restoration of session globals and preferences with regressions |
| 32 | Statistical hardening | Added third-moment Gaussian rejection and Bernstein PMF bounds |
| 33 | Input portability fixes | Normalized accepted sparse inputs, encoded reports as UTF-8 and added seven test groups |
| 34 | Usage audit | Found missing stale-report command and ambiguous retained-readout documentation |
| 35 | RAW contract audit | Independently decoded ten real artifacts; requested degenerate-shape regressions |

Further requested review tasks and final executable evidence are recorded as
they complete. A green intermediate run does not close the review effort.
