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
| 36 | Usage fixes | Aligned full acceptance commands and documented readout meaning and physical bounds |
| 37 | Degenerate RAW shapes | Added twelve round trips across three shapes and all four CFA patterns |
| 38 | RNG isolation audit | Confirmed guarded streams; requested noisy seed-boundary and demo-state tests |
| 39 | ISET state review | Independently checked session/preference restoration on success and late failure |
| 40 | Evidence verifier review | Found extreme upper-bin-edge mismatch and missing explicit new-gate regression |
| 41 | Seed boundary tests | Added noisy endpoint-seed repeatability and post-randomness failure restoration tests |
| 42 | Demo contract tests | Added nine-frame core-only inventory, RNG and no-overwrite byte-preservation tests |
| 43 | Verifier alignment | Matched spectral-edge validation and required every numerical gate independently |
| 44 | Physics acceptance review | Confirmed units and readout order; narrowed underflow documentation to actual guarantee |
| 45 | CI acceptance audit | Confirmed required runtime/dependencies, failure propagation and independent-process repeat |
| 46 | Provenance review | Confirmed Git layouts; requested size-bound regression and ref-name limitation documentation |
| 47 | Fixture review | Independently checked bracket means, saturation interpretation and all ten preview payloads |
| 48 | Runtime/resource scope | Checked Python 3.10 grammar, MATLAB lint and documented format versus memory limits |
| 49 | Provenance boundaries | Added exact/oversized 8 MiB metadata and unsupported-ref-name regressions |
| 50 | Fixture edge tests | Added seven groups covering degenerate geometry, amplitudes, checker orientation and invalid inputs |
| 51 | Public API error review | Confirmed shape/type/range rejection and documented finite-arithmetic behavior |
| 52 | Scientific claims review | Confirmed scope boundaries and refined the description of spatial sample variance |
| 53 | Acceptance inventory | Mapped all eleven required suites to 91 expected groups; independently ran 29 Python tests |
| 54 | Measured-statistics review | Recomputed bounds against actual CI aggregates, including Gaussian rejection and ISET error |
| 55 | Delivery diff review | Checked all changed files, relative links, ignored outputs and unchanged upstream dependencies |
| 56 | New regression review | Verified independent expectations, scoped cleanup and meaningful test-group counts |
| 57 | Roadmap traceability | Mapped all seven Phase 1 requirements to executable implementation and evidence |
| 58 | Ordinary file-failure review | Confirmed owned cleanup and preservation rules; qualified initial report-write failure boundary |
| 59 | Final CI evidence | Directly verified all steps, 91 numerical groups, 29 Python tests and identical repeated demo artifacts |
| 60 | Final release review | Independent GO for the tested generic baseline; compared executable files with the tested Git tree |

All 60 distinct delegated tasks are complete. Reviews found and drove actual
implementation and regression improvements; review count is not a quality
percentage or a substitute for runtime evidence. Final acceptance is recorded
in [PHASE1_COMPLETION.md](PHASE1_COMPLETION.md). The approval covers the generic
Phase 1 baseline, not calibrated ALEV4 equivalence or native MATLAB execution.
