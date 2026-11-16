# Phase 4 structured-noise artifact contract

Status: implemented version 1.0 wire contract; complete release acceptance is
recorded separately. These are **synthetic, assumed, uncalibrated** research
artifacts. They are not genuine ARRIRAW, measured sensor calibration, or proof
of a particular random generator's output.

## Native interfaces and retained result

```matlab
files = alev4.exportStructuredBundle(result, directory);
[result, metadata] = alev4.readStructuredBundle(directory);
```

The exporter accepts a complete enabled `exposure` or `spatial_exposure`
result. The reader's first output is that complete result, with every field,
native class, array orientation, scalar-map representation, and field order
preserved. It adds no fields. The optional second output is the wire manifest.
Both operations call `structuredValidateResult`, preserve caller RNG state,
and neither regenerate nor replay random streams.

For spatial exposures, this includes the entire `spatial_baseline`: original,
optical and sampled irradiance; grids and PSF; optical and sampling reports;
legacy sampled/stored charge and signed analog readouts; RAW, merge results,
flags, metadata and provenance. That baseline remains verification context;
its charge is not added to the structured exposure. It is archived directly,
not reduced to the older spatial format's observable readout files.

Disabled legacy results and sequence envelopes are not accepted. Export each
enabled sequence frame separately; the Phase 4 demo summary records the
absolute frame indices, sequence identities, seed schedule and EI labels.

## Directory and manifest

A bundle contains exactly two ordinary, independently owned files:

| Filename | Content |
| --- | --- |
| `structured.json` | Strict UTF-8 JSON manifest, at most 2,000,000 bytes |
| `data.bin` | All numerical/logical leaves, concatenated without padding |

The manifest has exactly these fields. Object field order is retained.

| Field | Required value or type |
| --- | --- |
| `format` | `ALEV4-SYNTHETIC-STRUCTURED-NOISE` |
| `schema_version` | String `1.0` |
| `wire_version` | `typed-tree-v1` |
| `byte_order` | `little-endian` |
| `array_order` | `row-major` |
| `synthetic` | JSON `true` |
| `calibrated_alev4`, `authentic_arriraw` | JSON `false` |
| `parameter_classification` | `assumed` |
| `provenance` | Exact `sourceProvenance` object described below |
| `payload` | Exact payload descriptor described below |
| `result` | Typed root struct representing the complete native result |

`provenance` contains exactly `repository_head`, `isetcam_head`,
`isethdrsensor_head`, and `meaning`. Each head is empty text or a lowercase
40-digit hexadecimal SHA-1. The required meaning is:

> Observed Git HEADs; an empty value means unavailable. Uncommitted edits,
> object existence and agreement with dependency gitlinks are not established
> by these metadata observations.

These source observations identify associations only. They do not establish
clean source, executed acceptance, calibrated parameters or stream origin.
The original result's runtime name and version remain inside the typed tree.

`payload` contains exactly `name`, `byte_count`, `sample_count`, and `sha256`.
The name is always `data.bin`; paths or alternate filenames are forbidden.
The SHA-256 is 64 lowercase hexadecimal digits over every actual payload byte.
Counts are JSON number scalars containing exact nonnegative integers.
`sample_count` is the aggregate count of all numerical and logical values,
including configuration scalars, flags, full-grid maps and spatial history.
Its limit is 100,000,000; the byte limit is 800,000,000. Character data do not
contribute to the numerical count.

## Typed tree

Every node has exactly the fields listed for its `kind`; unknown fields and
unsupported kinds reject. Structs are scalar. The root has `kind="struct"`.

| Kind | Exact node fields | Meaning |
| --- | --- | --- |
| `struct` | `kind`, `fields` | `fields` is an object from original native field names to child nodes, in original order |
| `cell` | `kind`, `shape`, `items` | `items` is an object with consecutive ordered keys `i000001`, `i000002`, etc.; children follow MATLAB linear cell order |
| `char` | `kind`, `shape`, `value` | JSON string preserving a native character row or an empty character array |
| `numeric` | `kind`, `class`, `shape`, `offset`, `byte_count`, `units` | Numerical payload segment described below |

Each struct has at most 256 fields and each cell has at most 256 items. There
are at most 20,000 nodes, with native tree depth at most 24, counting the root
as depth zero. The existing strict JSON decoder additionally rejects duplicate
or nonportable keys, malformed/ambiguous JSON, NUL, invalid UTF-8 or Unicode
surrogates, excess nesting and unsupported JSON value forms.

`shape` is a JSON numeric vector containing the exact native `size`: two or
three integer dimensions, each from zero through 100,000,000. Three-dimensional
shapes cannot end in one, because MATLAB/Octave omit a trailing singleton
dimension. The product of positive dimensions cannot exceed 100,000,000,
even for empty arrays. `[1,1]` preserves a scalar; `[H,1]` and `[1,W]` preserve
column and row vectors. `[0,0]`, `[1,0]` and other supported empty sizes remain
distinct. Character shapes have exactly two dimensions; nonempty text has one
row. Numerical empty arrays consume zero bytes and still carry their shape,
class, offset and units.

Character extents use the generating runtime's native code units: GNU Octave
uses UTF-8 bytes and MATLAB uses UTF-16 code units. ASCII labels are portable.
An independent reader can use `result.runtime.name` when checking Unicode
extents. A native reader rejects a Unicode extent incompatible with its own
native character representation rather than silently changing the shape.

### Numerical segments

Numerical nodes permit exactly these native classes:

| `class` | Wire encoding | Bytes per value |
| --- | --- | ---: |
| `double` | Finite IEEE 754 binary64, little-endian | 8 |
| `uint16` | Unsigned 16-bit integer, little-endian | 2 |
| `logical` | Byte equal to zero or one | 1 |

All scalars, including logical switches and seeds, use the payload rather than
JSON numerical values. This preserves binary64 bits, signed zero, scalar/map
form and native classes without JSON rounding. Nonfinite, complex and sparse
numerical arrays are unsupported.

Segments occur in depth-first traversal order, following the manifest's
original struct field order and the cell keys' linear order. The first
`offset` is zero. Each next offset is exactly the previous offset plus its
`byte_count`; empty leaves can share that boundary. The segment byte count
must equal the shape product times its class width. The final endpoint and
total sample count must equal the payload descriptor. Gaps, overlaps, padding,
unreferenced bytes and truncation reject.

Within each segment, **the last array index varies fastest**: true C row-major
order. A zero-based element `(r,c,k)` in an `H` by `W` by `K` cube has linear
index `(r*W+c)*K+k`. This differs from the Phase 3 format's plane-major row-major
cube order. Native writing reverses all dimensions before column-major linear
output; reading performs the inverse transformation. Rank-two RAW and all
other matrices follow ordinary rows, with columns varying fastest.

### Exact units and roles

Units follow the first matching rule below. The path consists of native field
names from `result`, with a cell key appended at each cell traversal. This
mapping is frozen in `structuredBundleUtil('units', path, class)`. Scientific
unknown fields reject separately in the strict result validator; arbitrary
portable spatial provenance remains informational metadata.

| Priority | Path/class condition | Exact `units` string |
| ---: | --- | --- |
| 1 | Any ancestor field is `spatial_provenance` | `metadata` |
| 2 | Class is `logical` | `logical` |
| 3 | Leaf is `input_irradiance`, `optical_irradiance`, or `sampled_irradiance` | `photons m^-2 s^-1 nm^-1` |
| 4 | Leaf is `expected_incident_photons` | `photons` |
| 5 | Leaf is `dark_current_e_per_s` | `electrons s^-1` |
| 6 | Leaf is `gain_dn_per_e` | `DN electron^-1` |
| 7 | Leaf is `raw_dn` or `black_level_dn` | `DN` |
| 8 | Leaf ends in `electrons` or `_e`, including `expected_photoelectrons` | `electrons` |
| 9 | Leaf ends in `_m` | `m` |
| 10 | Leaf ends in `_nm` | `nm` |
| 11 | Leaf is `reference_temperature_K` | `K` |
| 12 | Leaf is `exposure_s` | `s` |
| 13 | Leaf is `seed`, or its immediate parent is `seeds` | `seed` |
| 14 | Leaf is `values` under `source_integral`, `source_crop_integral`, or `target_integral` | `photons s^-1 nm^-1` |
| 15 | Leaf is `adc_bits` | `bits` |
| 16 | A dimension/index/count leaf listed below | `index/count` |
| 17 | Any other numerical leaf | `dimensionless` |

Rule 16's complete list is `image_size`, `full_grid_size`, `active_roi`,
`source_image_size`, `output_image_size`, `origin_rc`, `retained_row_indices`,
`retained_column_indices`, `required_halo_top_bottom_left_right`, `kernel_shape`,
`input_shape`, `output_shape`, `spectral_plane_count`, `x_weight_nonzeros`, and
`y_weight_nonzeros`. Rule 17 covers PRNU, effective QE, fill factor, PSF weights,
merge weights, relative/numerical errors and the empty post-optics PSF marker.

## Verification and publication

The reader validates exact directory contents, ordinary entry types, unique
single-link file identities, strict JSON kinds, all typed descriptors, payload
length and SHA-256, finite numerical data, canonical logical bytes and complete
result semantics. Shapes/classes/units are verified even for scalar metadata.
Source and payload identities are checked again after semantic validation.

The scientific validator reconstructs fixed-map crops, spectral expectations,
photo/dark expectations and sums, one physical well, retained electronic sums,
signed readouts, ADC rounding/clipping, validity and observed-channel merging.
It also checks the complete spatial baseline's deterministic optics/sampling
and retained legacy charge/readout consistency. Rehashing altered bytes cannot
legitimize inconsistent physics. It checks stochastic support and zero-noise
constraints, but does not prove that a finite, internally consistent random
realization came from its claimed seed or distribution; statistical and
fresh-process repeat gates provide separate evidence.

Both APIs reject dot segments, repeated/trailing separators, symbolic-link
ancestors, symlink entries, hard-linked files, missing/extra files and existing
export destinations. The parent directory must already exist. Identity checks
require Octave `lstat` or a JVM filesystem exposing file keys and `unix:nlink`;
unsupported identity facilities fail explicitly.

The exporter validates the result and bounded metadata before filesystem
mutation. It creates an owned sibling staging directory, writes `data.bin`,
writes the manifest last, and performs complete native readback. It refuses
an existing destination again before renaming the owned directory into place.
Cleanup checks recorded identities and removes only files created by that
invocation, never recursively deleting unknown or substituted content.
Concurrent writers or adversarial concurrent filesystem replacement are not
supported. Native MATLAB execution remains unverified until its gates run.
