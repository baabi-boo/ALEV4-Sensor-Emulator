# Phase 3 synthetic spatial bundle contract

This is the design contract for `ALEV4-SYNTHETIC-SPATIAL`, schema `1.0`.
Implementation and release acceptance are recorded separately. It is a
higher-level bundle around the unchanged Phase 1 single-gain RAW pair or
[Phase 2 dual-gain bundle](PHASE2_ARTIFACTS.md). It is synthetic, uncalibrated,
and not ARRIRAW. Its retained noiseless arrays support verification; they must
never be used to improve the observed-channel dual-gain merge.

## API and in-memory result

`alev4.exportSpatialBundle(directory, spatial_result)` publishes one new bundle
directory. `alev4.readSpatialBundle(directory)` returns `[decoded, metadata]`
only after validating the complete manifest, files, and numerical association.
A missing or partial manifest is a failure, not an incomplete successful read.

The export input is the complete result of
`simulateSpatialExposure(input, grid, geometry, readout, exposure, seed, options)`.
Its required fields are:

| Field | Contract |
| --- | --- |
| `schema_version` | Character row `1.0` |
| `readout_mode` | `single` or `dual`; agrees with the complete readout schema |
| `input_stage` | `pre_psf` or `post_optics` |
| `input_irradiance`, `input_grid` | Original cell-average spectral density and canonical grid |
| `geometry`, `configuration` | Complete validated geometry and geometry-bound readout configuration |
| `psf` | Complete validated optical PSF for `pre_psf`; empty `[]` for `post_optics` |
| `optical_irradiance`, `optical_grid` | Supported post-PSF density/grid, or unchanged post-optics input |
| `sampled_irradiance` | Average density over the active photosite footprints |
| `readout` | Existing complete spectral single/dual exposure result |
| `operation_order` | Exact ordered list described below |
| `spatial_provenance` | Scalar informational struct; empty struct when absent |

The wrapper also retains `optical_report`, `sampling_report`, `synthetic=true`,
and `calibrated_alev4=false`. Reports are diagnostic context; the reader verifies
actual intermediate arrays independently instead of trusting their pass flags.

Before export, validate the configuration with geometry binding in `validate`
mode. Do not fill missing recorded settings from current defaults. The exporter
must verify that retained intermediate arrays belong to the supplied input,
geometry, PSF, and readout. A caller can mutate a MATLAB struct after simulation;
having the right field names is not sufficient evidence of consistency.

For `pre_psf`, an omitted user PSF has already resolved to an explicit identity
PSF with matching spatial sampling. Its operation order is exactly
`optical_psf`, `area_overlap_average`, `spectral_integration`, then
`single_gain_readout` or `dual_gain_readout`. For `post_optics`, omit only the
first operation and require `psf=[]`. This version rejects extra blur of an
already computed optical image. It does not silently run a second optical pass.

## Directory and binary layout

All names below are fixed basenames inside `directory`; manifests cannot
select paths, directories, alternate stems, or external files.

| File | Shape and representation | Units |
| --- | --- | --- |
| `input.f64` | `[input_rows input_columns K]`, float64 | photons m^-2 s^-1 nm^-1 |
| `optical.f64` | `[optical_rows optical_columns K]`, float64 | photons m^-2 s^-1 nm^-1 |
| `sampled.f64` | `[active_rows active_columns K]`, float64 | photons m^-2 s^-1 nm^-1 |
| `expected.f64` | `[active_rows active_columns]`, float64 | electrons |
| `psf.f64` | `[kernel_rows kernel_columns kernel_count]`, float64; pre-PSF only | unitless weights |
| `readout.raw` and `readout.json` | Unchanged Phase 1 pair; single mode only | Existing contract |
| `readout.high.raw`, `readout.low.raw`, `readout.merged.f64`, `readout.flags.u8`, `readout.json` | Unchanged Phase 2 bundle; dual mode only | Existing contract |
| `spatial.json` | UTF-8 manifest described below | Metadata |

Every float64 payload is IEEE-754, little-endian, headerless, and contains no
padding. Store each spectral plane completely before the next plane. Within a
plane, store one complete row before the next row. For one-based `(r,c,k)`, the
sample offset is `((k-1)*H + (r-1))*W + (c-1)`; multiply by eight for a byte
offset. `K=1`, one-row, one-column, and one-pixel cases retain their explicit
declared shapes even where MATLAB omits trailing singleton dimensions.

`kernel_count` is one for a shared PSF or exactly K for an explicitly associated
per-bin PSF. Its association must match the input wavelength bins in order;
there is no implicit interpolation. PSF coefficients are stored separately so
the manifest never depends on a JSON encoder's three-dimensional array order.
Each density, expected-electron, and kernel value must be finite and
nonnegative. Signed merged electrons remain governed by the existing Phase 2
contract and are not subject to this nonnegative requirement.

Limit each spatial float64 payload to 100 million samples and each manifest
to 2,000,000 UTF-8 bytes. Validate integer shapes and products by division
before allocating. Validate the exact expected byte length, including absence
of trailing bytes, and enforce bounds on the actual read, not only a preceding
file-size observation. These format limits are not practical full-frame memory
or throughput guarantees.

## Spatial manifest

The manifest identifies `format='ALEV4-SYNTHETIC-SPATIAL'`,
`schema_version='1.0'`, `algorithm_version='phase3-spatial-v1'`,
`synthetic=true`, `calibrated_alev4=false`, and `authentic_arriraw=false`.
It records the complete `geometry`, bound `configuration`, `readout_mode`,
`input_stage`, `input_grid`, `optical_grid`, `psf`, `operation_order`,
`spatial_provenance`, `exposure_s`, `seed`, `runtime`, `provenance`, and `files`.
The spectral bins and QE are those in the recorded single sensor or the dual
configuration's `sensor`; every spectral cube has exactly that bin count.

`runtime` contains the existing `name` and `version` fields. `provenance` uses
the existing observed Git HEAD record, including its limitation statement.
Geometry `parameter_sources` identifies records in
[PHASE3_SOURCES.md](PHASE3_SOURCES.md) at that source revision. Source IDs and
adapter descriptions are provenance claims, not substitutes for numerical
verification or proof of measurement. Release acceptance separately checks the
expected commit, dependency pins, and clean worktrees. Empty observed revisions
must not be invented; they cannot pass an exact-revision release gate.

The manifest's `psf` is `[]` for post-optics input. Otherwise it contains the
complete validated PSF configuration except `kernel`, whose values come from
`psf.f64` with the shape in its file descriptor. Its fields are
`schema_version='1.0'`, `origin_rc`, `spacing_yx_m`, `wavelength_nm`,
`boundary_policy='valid'`, and `parameter_sources`. The constructor requires
unit-sum coefficients without silently renormalizing them. The reader
reconstructs the production PSF struct from this metadata and the checked
coefficient bytes.

`files` is a scalar object with exact mode/stage-dependent keys. The spatial
keys are `input_irradiance`, `optical_irradiance`, `sampled_irradiance`,
`expected_electrons`, and, only for pre-PSF input, `psf`. Add
`readout_metadata` plus `raw` in single mode, or `readout_metadata`, `high_raw`,
`low_raw`, `merged_electrons`, and `flags` in dual mode. Each entry has exactly
`name`, `sha256`, `byte_count`, `sample_type`, `shape`, and `units`. SHA-256 is
64 lowercase hexadecimal characters computed over the actual complete file
bytes. The metadata entry has `sample_type='utf8'`, `shape=[]`, and
`units='metadata'`; binary entries identify their actual `float64`, `uint16`,
or `uint8` type and shape. Binary byte order and array order are fixed by this
format, with explicit top-level `byte_order='little-endian'` and
`array_order='plane-major-row-major'` labels.

The hashes bind spatial data, PSF coefficients, readout payloads, and the
nested readout manifest. A release receipt separately hashes `spatial.json`;
it cannot contain a digest of itself. These hashes detect corruption and
association mistakes. They are not a digital signature or authentication
scheme, and a hash match alone does not prove the physics is correct.

### Phase 3 wire conversion and numeric precision

Keep the Phase 1/2 JSON encoder unchanged. Before passing Phase 3 metadata to
`encodeBundleJson`, convert the known cell lists into scalar keyed objects:
geometry and PSF source IDs use contiguous `id001`, `id002`, ... keys, and
operation order uses contiguous `step001`, `step002`, ... keys. Decode them back into
ordered cells before production constructor calls. Empty, missing, duplicated,
gapped, or foreign list keys reject. Key enumeration order is not the ordering
contract; the numeric suffix is. An empty list is not a valid source list or
operation list. Unknown nested cell arrays in `spatial_provenance` reject
instead of receiving an undocumented conversion.

The remaining supported metadata values are scalar structs, finite double
scalars/vectors/matrices, scalar logicals, and character-row text. Object keys
use the frozen portable subset `[A-Za-z][A-Za-z0-9_]{0,62}` and exclude the
MATLAB/Octave keyword set recorded in both Phase 3 parsers. Each object has at
most 256 fields; nesting is limited to 64 object/array containers including the
outer object. These bounds do not depend on a host's current `namelengthmax`.
Embedded NULs and invalid Unicode surrogate escapes reject before a native
decoder can truncate or rewrite them. Ragged, mixed and higher-rank arrays are
outside this wire vocabulary.

Existing 17-significant-digit numeric serialization applies. Phase 3 validates
original strings/keys before the shared strict grammar check, then its separate
`spatialDecodeJson` parses original numeric lexemes with `str2double`. This
preserves binary64 coordinates that Octave's native JSON decoder can otherwise
shift by a few ULPs. For example, the serialized value of 7 times 6 micrometres
must return the same edge, not an adjacent floating-point number. No spatial
coverage tolerance or grid snapping conceals decoder drift. Existing Phase 1/2
decoders and their metadata comparison allowances remain unchanged.

Exact zero/integer handling and rejection of a nonzero value changing sign or
becoming zero remain required. Native input vector orientations are
canonicalized during export. Original JSON kinds remain available during
schema validation: a numeric scalar field cannot be supplied as `[value]`, and
an explicit shape vector cannot be wrapped in extra matrix/array dimensions.
Single-bin QE receives its explicit supported row/matrix handling; a JSON
round trip must not change grid shapes, kernel association, or the sensor's
interpretation. Reject duplicate JSON
keys before decoding can erase them, nonfinite numbers, unsupported fields,
and malformed grammar. Use the existing bounded strict JSON scanner for the
spatial manifest and for the nested readout manifest, including the legacy
single-gain case, before invoking its existing reader.

The serializer emits the bounded canonical numeric spellings used by the
tests. Noncanonical exponent spellings outside the shared native decoder's
lexical range, such as `0e9999`, can reject even when their mathematical value
is zero. This limitation never changes a value or relaxes spatial coverage.

## Required checks on read and export

1. Validate regular, distinct files and the exact expected file inventory.
   Reject symlinks, including a symlink bundle directory, and aliased payloads.
   Native file-identity support must be explicit; independent Python acceptance
   always checks regular files and device/inode identity. Fixed names do not
   make a symlink to outside data acceptable.
2. Check actual lengths and SHA-256 before interpreting payloads. Validate
   strict metadata, complete configurations, source-list syntax, scalar types,
   units, stage/order, physical coordinates, spectral counts, and geometry/CFA
   binding. Reject attempts to supply booleans as numeric dimensions.
3. Recompute the valid-support PSF from input data when present, including
   asymmetric/even-kernel origin offsets. Post-optics optical data/grid must
   equal input data/grid. Verify actual optical payloads and their coverage.
4. Recompute rectangular overlap averages from the optical field. The result
   remains density; no collection-area or fill-factor scaling belongs here.
   Compare actual sampled bytes against these values using a documented
   floating-point accumulation allowance based on the expected magnitude and
   operation count. Tolerances must not be widened by an altered payload.
5. Independently calculate expected charge from sampled irradiance, CFA QE,
   bin widths, exposure, square pitch, and fill factor exactly once. Check
   `expected.f64`; use scale-aware tolerances so a tiny nonzero cannot pass as
   zero under an arbitrary unit-sized absolute tolerance.
6. Validate the unchanged nested readout bundle and require its configuration,
   image shape, exposure, seed, runtime, and provenance to agree with the
   higher manifest. For deterministic fixtures independently compute physical
   clipping, ADC rounding, and observed-channel merge. For noisy fixtures,
   verify observable constraints and seeded same-runtime repeat artifacts;
   metadata alone cannot prove an unrecorded random stream or analog history.

Readers need not regenerate noise to establish readout-format validity. If
native replay is used as an extra same-runtime check, it must restore caller
RNG and must not imply MATLAB/Octave cross-runtime bit identity. Python's
independent verifier uses scalar overlap, convolution, and spectral arithmetic
on retained small fixtures, rather than trusting producer success flags or
calling the production numerical routines.

For general noisy bundles, the recorded-channel checks establish merge, rail
and flag consistency. They do not solve latent shared-charge feasibility or
likelihood for every partially stochastic configuration. The fixed fixtures,
noise-model numerical tests and same-runtime repeats provide separate evidence;
none is relabelled as complete reconstruction of arbitrary hidden history.

## Publication and failure behavior

The requested parent directory must already exist. Refuse any existing target
entry, including an empty directory, file, symlink, or dangling symlink. Create
a uniquely owned staging directory beside the destination; write and close all
spatial files and the existing readout bundle there, compute byte hashes, and
write `spatial.json` last. Verify the staged bundle before publication.
An existing staging candidate is refused. A directory-creation call that
reports an existing/ambiguous result does not establish ownership: it must not
enable writes into that path or install recursive cleanup for it.

Recheck absence of the target immediately before moving the complete staging
directory into place. This reduces exposure to partial publication, but does
not promise atomic no-clobber semantics on every MATLAB/Octave filesystem.
Concurrent writers to the same target are unsupported. Do not allow a generic
directory move to nest a staging directory inside a newly existing target.
On failure remove only this invocation's staging directory or an explicitly
owned incomplete publication; never remove a preexisting target. Report
write, close, rename, validation, and cleanup failures truthfully.

Fresh-process demos must use separate output directories with disjoint file
identities. Compare their complete inventories and bytes, not merely summary
statistics. Retain receipt hashes, numerical reports, commands, runtime,
source/dependency revisions, and failure-test results in the Phase 3 evidence.
Required corruption tests include modified data with a recomputed hash (to
exercise semantic checks), wrong crop/CFA, missing PSF halo, wrong spectral
order, altered operation stage, truncated/extra bytes, aliases, and malformed
JSON. No producer completion flag substitutes for these gates.
