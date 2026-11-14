# Phase 3 completion and acceptance record

**Status: complete and acceptance-tested.** The identified implementation
passed complete local and CI acceptance, all four candidate workflows, and
independent verification of the downloaded CI archive and artifacts. Its
tested identity below remains distinct from later documentation and evidence
commits.

## Tested source and runtime

| Item | Recorded identity |
| --- | --- |
| Implementation commit | [`beedd8bfd1cea3c722409ef0f959fcec5420c5f2`](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/commit/beedd8bfd1cea3c722409ef0f959fcec5420c5f2) |
| Implementation tree | `4da5c68c7e6dbeb13f2e2e04179c2ea5535e390e` |
| Local runtime | GNU Octave 9.4.0 |
| CI runtime | GNU Octave 8.4.0 |
| ISETCam pin | `3e0253421752eb72f2d1353327dffd0d433abdaf` |
| ISETHdrsensor pin | `ee2dacceb456516de3ecefadd72955154cf3cabe` |
| Local execution | 2026-11-14, 04:40:14–04:44:32 UTC |

Local and CI acceptance ran from the identified clean implementation commit
with unchanged HEAD, clean source endpoints, and clean initialized dependencies
matching both gitlinks before and after execution. Both original aggregate
receipts record `status="passed"`, `release_accepted=true`, and
`development=false`; all 16 required external commands exited successfully
in each execution. Development pilots and earlier dirty-tree reports retain
their original provenance and are not substituted for these executions.
Subsequent documentation or evidence commits
do not relabel this candidate's reports as executions of a later SHA.

## Completed implementation

All five slices of the [Phase 3 plan](PHASE3_PLAN.md) are implemented.

| Slice | Implemented behavior and verification |
| --- | --- |
| 3A — physical geometry | Separate full-grid coordinates, one-based active crops, physical edges/centres, and crop-adjusted Bayer phase bind to either preserved readout. Analytical geometry and identity checks cover the sourced Open Gate profile and explicit assumptions. |
| 3B — conservative sampling | Rectangle-overlap averaging maps cell-average spectral photon irradiance onto complete photosite footprints. Independent scalar intersections, conservation, offsets, refinement, and exact-copy cases verify density and collection factors. |
| 3C — PSF and MTF | Shared or per-bin finite PSFs act before CFA selection with explicit sampling, origin, and valid-support crops. Independent convolution and complex Fourier references verify optical transfer; the continuous pixel-aperture reference remains separate. |
| 3D — restricted ISETCam comparison | Genuine pinned uniform, ramp, checker, and edge scene/optics/Bayer fixtures use declared bilinear reconstruction of native point samples, independent footprint integration, and refinement checks. Post-optics input receives no implicit second PSF. |
| 3E — integration and evidence | Spatial wrappers preserve single- and simultaneous dual-gain behavior. Versioned hashed bundles retain input, optical, sampled, expected-charge, and readout data, with strict native decoding, independent Python verification, eight fixtures, and fresh-process repeats. |

The [usage guide](PHASE3_USAGE.md), [numerical contract](PHASE3_DESIGN.md),
[source register](PHASE3_SOURCES.md), and [artifact specification](PHASE3_ARTIFACTS.md)
define the supported interfaces and boundaries. The spatial layer preserves
one shared sampled photocharge array and one physical full well before the
two electronic paths. Merging still uses observed channels and configuration.

## Measured acceptance

Both complete numerical runs passed **135 Phase 3 numerical groups** across all
nine required suites, the preserved **62 Phase 2 groups**, and **92 Phase 1
regression groups**, including the genuine earlier-phase ISET prerequisite.
These are named numerical groups; a group can contain several assertions and
is not a count of individual assertions. The separate Python runs each passed
**145 tests**.

| Phase 3 numerical suite | Passing groups |
| --- | ---: |
| Geometry | 12 |
| Geometry edges | 10 |
| Conservative sampling | 13 |
| Optics | 15 |
| Spatial/readout integration | 12 |
| Spatial artifact I/O | 28 |
| Numerical edges | 17 |
| Demo contract | 14 |
| Genuine spatial ISETCam comparison | 14 |
| **Total** | **135** |

Runner failure/control checks are a separate gate. Phase 3 passed **43
scenarios** in each execution: 42 required nonzero child-process outcomes and
one intentional core-only control. Each receipt explicitly says `fixture_suites_only=true`
and `numerical_acceptance_executed=false`. They verify rejection and status
handling rather than adding scientific or ISET passes. The five Phase 2
failure scenarios and preserved Phase 1 stale-success failure check also
passed.

The genuine spatial ISET suite executed all four supported fixtures. Local
maximum relative errors were below `1.22e-15` against independent reconstructed
footprint expectations and below `9.17e-6` against the native reference, within
the fixed `5e-12` and `5e-5` tolerances. Native sampling and source-cell
refinement, nonuniform controls, exposure scaling, and caller-state restoration
also passed. This is the declared restricted comparison; arbitrary ISET imports
and measured ARRI optics remain outside the validated scope.

## Independent artifacts and fresh-process repeats

All three phases generated complete primary and repeated demonstrations in
separate processes in each runtime. Independent artifact verifiers checked
actual bytes, metadata, configuration, expected or observable readout behavior, and source
associations. Primary and repeat file identities were disjoint, including
cross-filename aliases, and corresponding files were byte-identical within
the recorded runtime.

| Phase | Complete fixtures | Files in each primary/repeat set |
| --- | ---: | ---: |
| 1 | 10 | 31 |
| 2 | 6 | 31 |
| 3 | 8 | 66 |

The Phase 3 set includes the noisy simultaneous-dual fixture and the genuine
ISET checker fixture. All eight outer manifests and their nested payloads were
checked. Independent audits of the local output and downloaded CI archive
matched every byte count and SHA-256 in each aggregate receipt: 293 listed
files, plus the receipt itself, with no missing or extra files. Same-runtime
repeats establish the recorded reproducibility contract; no cross-runtime
random-stream identity is claimed.

## CI and retained evidence

All four workflows on the implementation commit completed successfully. The
independent audit of the downloaded Phase 3 archive verified its published
digest and size, safe regular-file membership, complete receipt inventory,
exact commands, source/runtime/dependency associations, and repeat sets.
Separately, all three Python artifact verifiers passed against the downloaded
bytes in fresh processes; their resulting receipts were byte-identical to the
original CI verifier receipts. These checks validate file contents and scalar
reconstruction. They do not rerun native ISET, authenticate scientific inputs,
or reproduce unrecorded random streams.

| Workflow | Observed candidate run |
| --- | --- |
| Phase 3 geometry and optics | [43558156924](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43558156924) |
| Phase 1 validation | [43558156897](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43558156897) |
| Phase 2 validation | [43558156994](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43558156994) |
| Repository integrity | [43558156929](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43558156929) |

The retained evidence is organized around the original reports and their source,
runtime, commands, checksums, CI run, and archive audit:

- [Release evidence index](evidence/phase3-release-record.json).
- [Observed CI summary](evidence/phase3-ci-summary.json).
- [Independent CI artifact audit](evidence/phase3-ci-artifact-audit.json).
- Original selected execution records in [local evidence](evidence/phase3-local/)
  and [CI evidence](evidence/phase3-ci/).
- [Independent checks of downloaded CI artifacts](evidence/phase3-ci-recheck/).

The durable selection retains 44 original records from the local execution
and 44 from CI. Large logs use byte-preserving gzip storage; the index records
the original and stored byte lengths and SHA-256 values, and verified
decompression reproduces the original bytes. Reports are not rewritten to
adopt the retention path or a newer commit. Full CI artifact retention is 14 days under the
[workflow](../.github/workflows/phase3-tests.yml); the concise reports, logs,
inventories, and hashes retained in Git remain available afterward. The
downloaded full archive has 294 members; durable selection does not claim to
retain every binary demo payload in Git.

The historical [Phase 1](PHASE1_COMPLETION.md) and [Phase 2](PHASE2_COMPLETION.md)
completion records keep their original source identities and counts. The
Phase 3 regressions supplement those records without replacing them.

## Implementation and review campaign

The [delegated-task ledger](PHASE3_REVIEW_LOG.md) records actual implementation,
independent scientific/artifact review, release observation, and documentation
work. All **60 distinct delegated tasks completed in ten waves of six**.
The archived reports, machine-readable index, and final ledger validation
record their actual contributions and byte identities. Task counts are
coordination evidence, not a numerical test or a substitute for acceptance.

The [pre-edit baseline](evidence/phase3-baseline.json) remains separately
identified. It passed the then-current dependency, Python, Phase 2, and Phase 1
checks before Phase 3 production edits and is not relabelled as this release.

## Remaining limits and next work

This remains an independent, synthetic, uncalibrated research model. Published
Open Gate geometry does not establish total die dimensions, hardware crop
origins, measured CFA/QE, optical transfer, or actual ALEV4 noise parameters.
Native MATLAB has not run the retained gates. Measured 17-stop performance,
genuine ARRIRAW encoding, arbitrary ISET optical-image import, and practical
full-frame memory or throughput are unestablished.

The next implementation phase is [Phase 4: sensor noise and readout realism](PHASE4_PLAN.md).
First define a persistent full-grid sensor realization whose fixed PRNU and
offset maps retain their values through crops. Keep exposure-dependent
dark-current rates distinct from exposure-independent electronic offsets,
with explicit units and placement relative to physical clipping and gain.
Then add structured and temporal electronics while preserving zero-effect
identity, caller RNG state, and the one-shared-charge dual-gain contract.
Controlled real-camera characterization and calibration remain Phase 6.
