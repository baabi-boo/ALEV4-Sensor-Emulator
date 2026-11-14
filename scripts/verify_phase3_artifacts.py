#!/usr/bin/env python3
"""Independently verify Phase 3 spatial bundles and complete release evidence.

Only the Python standard library is used. ``verify_bundle(directory)`` checks
the general wire format and independently reconstructs convolution, rectangular
footprint averages, spectral charge, and observable readout constraints. It
does not reproduce MATLAB/Octave random streams or establish the origin of an
arbitrary supplied optical field. ``verify_outputs`` additionally requires the
eight fixed demo fixtures, complete numerical prerequisites, and pinned source
associations. A numerical report is evidence to validate, not proof that this
Python process ran MATLAB, ISETCam, or the reported numerical tests.

Arithmetic comparisons have no unit-sized absolute floor: their allowance is
64 times the relevant operation count times the reference ULP, capped by the
corresponding reference-relative bound. Exact zero/nonzero association is
mandatory. Altering the compared payload cannot increase its allowance.

Usage: python3 scripts/verify_phase3_artifacts.py outputs/phase3
       --expected-commit SHA --compare-dir outputs/phase3/demo-repeat
"""
from __future__ import annotations

import argparse
import array
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import stat
import sys


def _prior(name):
    """Load sibling verifiers also when this module is loaded by file path."""
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


phase1 = _prior("verify_phase1_artifacts")
phase2 = _prior("verify_phase2_artifacts")
ArtifactError = phase2.ArtifactError
require, number, integer = phase2.require, phase2.number, phase2.integer
MAX_JSON, MAX_SAMPLES = phase2.MAX_JSON, phase2.MAX_PIXELS
# Freeze the portable Phase 3 subset instead of inheriting host-dependent
# isvarname/namelengthmax behavior. These are the MATLAB and supported
# Octave (8/9) keywords; all object keys also require an ASCII letter first.
PORTABLE_KEYWORDS = frozenset({
    "__FILE__", "__LINE__", "break", "case", "catch", "classdef", "continue", "do",
    "else", "elseif", "end", "end_try_catch", "end_unwind_protect", "endarguments", "endclassdef",
    "endenumeration", "endevents", "endfor", "endfunction", "endif", "endmethods",
    "endparfor", "endproperties", "endspmd", "endswitch", "endwhile",
    "for", "function", "global", "if", "otherwise", "parfor",
    "persistent", "return", "spmd", "switch", "try", "until",
    "unwind_protect", "unwind_protect_cleanup", "while",
})
DENSITY_UNITS = "photons m^-2 s^-1 nm^-1"
NAMES = ("identity_single", "flat_binomial", "shifted_impulse", "edge",
         "sinusoid", "crop_cfa", "dual_spatial", "iset_checker")
GATES = ("geometry", "geometry_edges", "sampling", "optics", "integration",
         "spatial_io", "numerical_edges", "demo_contract", "iset_spatial")
PINNED_HEADS = {"isetcam_head": "3e0253421752eb72f2d1353327dffd0d433abdaf",
                "isethdrsensor_head": "ee2dacceb456516de3ecefadd72955154cf3cabe"}
MANIFEST_FIELDS = {"format", "schema_version", "algorithm_version", "synthetic",
                   "calibrated_alev4", "authentic_arriraw", "byte_order", "array_order",
                   "readout_mode", "input_stage", "geometry", "configuration", "input_grid",
                   "optical_grid", "psf", "operation_order", "spatial_provenance",
                   "exposure_s", "seed", "runtime", "provenance", "files"}
GEOMETRY_FIELDS = {"schema_version", "full_grid_size", "active_roi", "pixel_pitch_m",
                   "origin_xy_m", "full_grid_cfa_pattern", "parameter_sources"}
GRID_FIELDS = {"schema_version", "x_edges_m", "y_edges_m", "units", "sample_semantics"}
PSF_FIELDS = {"schema_version", "origin_rc", "spacing_yx_m", "wavelength_nm",
              "boundary_policy", "parameter_sources"}
DESCRIPTOR_FIELDS = {"name", "sha256", "byte_count", "sample_type", "shape", "units"}
SINGLE_FIELDS = {"format", "schema_version", "synthetic", "calibrated", "authentic_arriraw",
                 "description", "height", "width", "byte_count", "sample_type", "byte_order",
                 "layout", "units", "cfa_pattern", "cfa_origin", "exposure_s", "seed",
                 "sensor", "algorithm_version", "sampler_version", "runtime", "provenance"}
DUAL_FIELDS = {"format", "schema_version", "algorithm_version", "synthetic", "calibrated_alev4",
               "authentic_arriraw", "configuration", "image_size", "exposure_s", "seed",
               "input_units", "array_order", "byte_order", "cfa_origin", "files", "units",
               "runtime", "provenance"}


def fields(value, expected, label):
    require(isinstance(value, dict) and set(value) == set(expected),
            f"{label}: incomplete or unknown fields")


def text_value(value, label, *, nonempty=True):
    require(isinstance(value, str) and (not nonempty or bool(value.strip()))
            and "\0" not in value, f"{label}: invalid text")
    try:
        value.encode("utf-8")
    except UnicodeError as exc:
        raise ArtifactError(f"{label}: invalid Unicode text") from exc
    return value


def regular(path):
    try:
        info = Path(path).lstat()
    except OSError as exc:
        raise ArtifactError(f"Missing/unreadable artifact: {Path(path).name}") from exc
    require(stat.S_ISREG(info.st_mode), f"Artifact must be a regular non-symlink file: {Path(path).name}")
    return info.st_dev, info.st_ino


def directory_path(path):
    path = Path(path)
    try:
        mode = path.lstat().st_mode
    except OSError as exc:
        raise ArtifactError("Missing/unreadable bundle or demo directory") from exc
    require(stat.S_ISDIR(mode), "Bundle/demo directory must be a non-symlink directory")
    return path


def bounded(path, maximum):
    """Bound the actual read, and verify the opened descriptor's identity/type."""
    path = Path(path)
    identity = regular(path)
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    with os.fdopen(descriptor, "rb") as handle:
        info = os.fstat(handle.fileno())
        require(stat.S_ISREG(info.st_mode) and (info.st_dev, info.st_ino) == identity,
                "Artifact changed identity while opening")
        content = handle.read(maximum + 1)
    require(len(content) <= maximum, f"Oversized artifact: {path.name}")
    return content


def _finite_float(token):
    value = phase2.finite_json_float(token)
    # JSON's grammar permits an exponent that binary64 cannot represent.
    # Such a positive/negative token must not silently become exact zero.
    mantissa = re.split("[eE]", token)[0]
    require(value != 0 or not any(c in "123456789" for c in mantissa),
            "Nonzero JSON number underflowed to zero")
    return value


def _portable_pairs(pairs):
    result = phase2.unique_pairs(pairs)
    require(len(result) <= 256, "JSON object exceeds the 256-field bound")
    require(all(re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,62}", key)
                and key not in PORTABLE_KEYWORDS for key in result),
            "JSON keys must retain their exact portable field spelling")
    return result


def _container_depth(value, depth=0):
    """Count every JSON object/array, including the outer manifest object."""
    if isinstance(value, (dict, list)):
        require(depth < 64, "JSON nesting exceeds 64 containers")
        for child in value.values() if isinstance(value, dict) else value:
            _container_depth(child, depth + 1)


def read_json(path, content=None):
    if content is None:
        content = bounded(path, MAX_JSON)
    require(len(content) <= MAX_JSON, "Oversized JSON artifact")
    try:
        result = json.loads(content.decode("utf-8"), object_pairs_hook=_portable_pairs,
                            parse_float=_finite_float, parse_constant=phase2.reject_constant)
    except (UnicodeError, json.JSONDecodeError, RecursionError, ValueError) as exc:
        if isinstance(exc, ArtifactError):
            raise
        raise ArtifactError(f"Invalid JSON: {Path(path).name}") from exc
    require(isinstance(result, dict), "A scalar JSON object is required")
    _container_depth(result)
    return result


def vector(value, count, label, *, positive=False):
    require(isinstance(value, list) and len(value) == count, f"{label}: wrong vector shape")
    result = [number(item, label) for item in value]
    require(not positive or all(item > 0 for item in result), f"{label}: values must be positive")
    return result


def shape(value, rank, label="payload shape", maximum=MAX_SAMPLES):
    require(isinstance(value, list) and len(value) == rank, f"{label}: wrong explicit rank")
    result, count = [], 1
    for item in value:
        size = integer(item, label, 1, maximum)
        require(size <= maximum // count, f"{label}: sample limit exceeded")
        count *= size
        result.append(size)
    return result


def keyed_list(value, prefix, label, maximum=32):
    require(isinstance(value, dict) and 1 <= len(value) <= maximum,
            f"{label}: nonempty keyed list required")
    keys = [f"{prefix}{i:03d}" for i in range(1, len(value) + 1)]
    require(set(value) == set(keys), f"{label}: missing, gapped, or foreign list keys")
    result = [text_value(value[key], label) for key in keys]
    require(len(set(result)) == len(result), f"{label}: duplicated list entries")
    if prefix == "id":
        require(all(len(item) <= 128 and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", item)
                    for item in result), f"{label}: invalid source ID")
    return result


def informational(value):
    """Accept the native scalar-struct/text/logical/numeric-matrix vocabulary."""
    if isinstance(value, dict):
        for key, child in value.items():
            text_value(key, "informational field")
            informational(child)
    elif isinstance(value, str):
        text_value(value, "informational text", nonempty=False)
    elif type(value) is bool:
        return
    elif type(value) in (int, float):
        number(value, "informational number")
    elif isinstance(value, list):
        if not value:
            return
        if all(type(item) in (int, float) for item in value):
            for item in value:
                number(item, "informational vector")
        else:
            require(all(isinstance(row, list) and bool(row) and len(row) == len(value[0])
                        and all(type(item) in (int, float) for item in row) for row in value),
                    "Unsupported nested cell/list metadata")
            for row in value:
                for item in row:
                    number(item, "informational matrix")
    else:
        raise ArtifactError("Unsupported informational metadata value")


def provenance(value, *, complete=False):
    fields(value, {*phase2.SHA_FIELDS, "meaning"}, "provenance")
    text_value(value["meaning"], "provenance limitation statement")
    for key in phase2.SHA_FIELDS:
        observed = value[key]
        require(isinstance(observed, str) and
                (not complete and observed == "" or re.fullmatch(r"[0-9a-f]{40}", observed)),
                f"Missing or malformed observed {key}")
    return {key: value[key] for key in phase2.SHA_FIELDS}


def runtime(value):
    fields(value, {"name", "version"}, "runtime")
    text_value(value["version"], "runtime version")
    return phase2.runtime(value)


def expected_revision(source, expected_commit):
    if expected_commit is not None:
        require(isinstance(expected_commit, str) and re.fullmatch(r"[0-9a-f]{40}", expected_commit),
                "Expected commit requires a full lowercase SHA")
        require(source["repository_head"] == expected_commit, "Evidence belongs to another commit")


def arithmetic_close(actual, expected, operations, label):
    actual = number(actual, label)
    require(math.isfinite(expected), f"{label}: reference arithmetic is nonfinite")
    require((actual == 0) == (expected == 0) and (actual >= 0) == (expected >= 0),
            f"{label}: exact zero or sign association disagrees")
    if expected == 0:
        return
    factor = 64 * max(1, operations)
    tolerance = min(factor * math.ulp(abs(expected)),
                    (factor * sys.float_info.epsilon) * abs(expected))
    require(abs(actual - expected) <= tolerance,
            f"{label}: independently calculated value disagrees")


def config(value, mode):
    try:
        result = phase1.config(value) if mode == "single" else phase2.config(value)
    except phase1.ArtifactError as exc:
        raise ArtifactError(str(exc)) from exc
    sensor = result if mode == "single" else result["sensor"]
    number(sensor["read_noise_e"], "read noise", 0)
    # Recheck products by division even for the legacy configuration parser.
    shape(sensor["image_size"], 2, "sensor image size")
    return result, sensor


def geometry(value, sensor):
    fields(value, GEOMETRY_FIELDS, "geometry")
    require(value["schema_version"] == "1.0", "Unsupported geometry schema")
    dims = shape(value["full_grid_size"], 2, "full geometry size")
    require(isinstance(value["active_roi"], list) and len(value["active_roi"]) == 4,
            "Geometry ROI must have four entries")
    row, col, height, width = [integer(x, "ROI", 1) for x in value["active_roi"]]
    require(row <= dims[0] and col <= dims[1] and height <= dims[0] - row + 1
            and width <= dims[1] - col + 1, "ROI extends outside the full grid")
    pitch = number(value["pixel_pitch_m"], "geometry pitch", 0)
    require(0 < pitch * pitch < math.inf, "Unrepresentable geometry pixel area")
    origin = vector(value["origin_xy_m"], 2, "geometry origin")
    for start, size in zip(origin, reversed(dims)):
        far = start + size * pitch
        ulp = max(math.ulp(abs(start)), math.ulp(abs(far))) if math.isfinite(far) else math.inf
        require(math.isfinite(far) and far > start and pitch > 4 * ulp and ulp / pitch <= 1e-6,
                "Geometry coordinates cannot resolve pixel footprints")
    pattern = value["full_grid_cfa_pattern"]
    require(pattern in ("RGGB", "BGGR", "GRBG", "GBRG"), "Invalid full-grid CFA")
    keyed_list(value["parameter_sources"], "id", "geometry sources")
    active = "".join(pattern[2 * ((row - 1 + r) % 2) + ((col - 1 + c) % 2)]
                     for r in range(2) for c in range(2))
    require(sensor["image_size"] == [height, width] and sensor["pixel_pitch_m"] == pitch
            and sensor["cfa_pattern"] == active, "Readout is not bound to geometry/CFA parity")
    axes = []
    for start, first, count in ((origin[0], col - 1, width), (origin[1], row - 1, height)):
        edges = [start + i * pitch for i in range(first, first + count + 1)]
        centers = [start + (i + 0.5) * pitch for i in range(first, first + count)]
        require(all(a < center < b and abs((b - a) / pitch - 1) <= 1e-6
                    for a, b, center in zip(edges, edges[1:], centers)),
                "Unrepresentable geometry edges or centers")
        axes.append(edges)
    return axes[0], axes[1]


def grid(value, label):
    fields(value, GRID_FIELDS, label)
    require(value["schema_version"] == "1.0" and value["units"] == "m"
            and value["sample_semantics"] == "cell_average", f"{label}: schema/units/semantics disagree")
    axes, widths = [], []
    for key in ("x_edges_m", "y_edges_m"):
        entries = value[key]
        require(isinstance(entries, list) and 2 <= len(entries) <= MAX_SAMPLES + 1,
                f"{label}: invalid edge vector")
        edges = [number(item, key) for item in entries]
        deltas = [b - a for a, b in zip(edges, edges[1:])]
        require(all(math.isfinite(d) and d > 0 for d in deltas)
                and math.isfinite(edges[-1] - edges[0]), f"{label}: invalid increasing edges")
        axes.append(edges)
        widths.append(deltas)
    shape([len(axes[1]) - 1, len(axes[0]) - 1], 2, label)
    require(min(widths[0]) * min(widths[1]) > 0
            and math.isfinite(max(widths[0]) * max(widths[1])), f"{label}: unrepresentable cell areas")
    return axes[0], axes[1]


def _decode(content, kind):
    code, size = {"float64": ("d", 8), "uint16": ("H", 2), "uint8": ("B", 1)}[kind]
    values = array.array(code)
    require(values.itemsize == size, "Required binary sample representation is unavailable")
    values.frombytes(content)
    if sys.byteorder != "little" and size > 1:
        values.byteswap()
    return values


def _file(directory, record, basename, sample_type, dimensions, units):
    fields(record, DESCRIPTOR_FIELDS, basename + " descriptor")
    require(record["name"] == basename and record["sample_type"] == sample_type
            and record["units"] == units, f"{basename}: basename/type/units disagree")
    require(isinstance(record["sha256"], str) and re.fullmatch(r"[0-9a-f]{64}", record["sha256"]),
            f"{basename}: invalid SHA-256")
    if sample_type == "utf8":
        require(record["shape"] == [], "Metadata descriptor must have shape=[]")
        count = integer(record["byte_count"], "manifest byte count", 2, MAX_JSON)
    else:
        declared = shape(record["shape"], len(dimensions), basename)
        require(declared == dimensions, f"{basename}: shape association disagrees")
        count = math.prod(dimensions) * {"float64": 8, "uint16": 2, "uint8": 1}[sample_type]
        require(integer(record["byte_count"], "payload byte count", 1, 8 * MAX_SAMPLES) == count,
                f"{basename}: byte count disagrees")
    path = directory / basename
    content = bounded(path, count)
    require(len(content) == count, f"{basename}: truncated payload")
    require(hashlib.sha256(content).hexdigest() == record["sha256"], f"{basename}: SHA-256 mismatch")
    values = read_json(path, content) if sample_type == "utf8" else _decode(content, sample_type)
    if sample_type == "float64" and basename != "readout.merged.f64":
        require(all(math.isfinite(item) and item >= 0 for item in values),
                f"{basename}: nonfinite or negative sample")
    return path, values


def _sum(terms, label):
    try:
        value = math.fsum(terms)
    except (ValueError, OverflowError) as exc:
        raise ArtifactError(f"{label}: unsupported arithmetic range") from exc
    require(math.isfinite(value), f"{label}: nonfinite reference")
    return value


def verify_optical(meta, data, input_axes, optical_axes, bands):
    source, optical = data["input_irradiance"], data["optical_irradiance"]
    if meta["input_stage"] == "post_optics":
        require(meta["psf"] == [] and meta["optical_grid"] == meta["input_grid"]
                and optical == source, "Post-optics input must be unchanged without a PSF")
        return
    psf = meta["psf"]
    fields(psf, PSF_FIELDS, "PSF")
    require(psf["schema_version"] == "1.0" and psf["boundary_policy"] == "valid",
            "Unsupported PSF schema/boundary policy")
    keyed_list(psf["parameter_sources"], "id", "PSF sources")
    kh, kw, kernels = shape(meta["files"]["psf"]["shape"], 3, "PSF shape", 1_000_000)
    require(kh <= 63 and kw <= 63, "PSF exceeds declared support limits")
    origin = vector(psf["origin_rc"], 2, "PSF origin")
    require(all(v.is_integer() and 1 <= v <= size for v, size in zip(origin, (kh, kw))),
            "PSF origin must identify a coefficient")
    origin = [int(v) for v in origin]
    spacing = vector(psf["spacing_yx_m"], 2, "PSF spacing", positive=True)
    require(all(math.isfinite(0.5 / step) and math.isfinite((size - 1) * step)
                for step, size in zip(spacing, (kh, kw))), "Unrepresentable PSF sampling")
    wave = psf["wavelength_nm"]
    if wave == []:
        require(kernels == 1, "A shared PSF must have one kernel")
    else:
        wave = phase2.vector(wave, "PSF wavelengths")
        require(wave == bands and kernels == len(bands), "PSF spectral association/order disagrees")
    weights = data["psf"]
    for k in range(kernels):
        mass = _sum(weights[k * kh * kw:(k + 1) * kh * kw], "PSF normalization")
        require(abs(mass - 1) <= 32 * kh * kw * sys.float_info.epsilon,
                "PSF coefficients are not already normalized")
    for edges, step in zip(reversed(input_axes), spacing):
        tolerance = 8 * max(math.ulp(abs(v)) for v in edges) + 32 * math.ulp(step)
        require(tolerance < step / 1024 and all(abs(b - a - step) <= tolerance
                    for a, b in zip(edges, edges[1:])), "PSF grid must be uniform and match its spacing")
    width, height = len(input_axes[0]) - 1, len(input_axes[1]) - 1
    require(kh <= height and kw <= width, "Input lacks complete PSF support")
    oh, ow = height - kh + 1, width - kw + 1
    first_y, first_x = kh - origin[0], kw - origin[1]
    require(optical_axes[0] == input_axes[0][first_x:first_x + ow + 1]
            and optical_axes[1] == input_axes[1][first_y:first_y + oh + 1],
            "PSF valid-support/origin crop disagrees")
    if kh == kw == 1 and all(weight == 1 for weight in weights):
        require(optical == source, "Identity PSF must copy its input exactly")
        return
    require(all(v == 0 or v >= sys.float_info.min for v in source),
            "Weighted PSF cannot accept positive subnormal input")
    for band in range(len(bands)):
        base = (band if wave != [] else 0) * kh * kw
        for r in range(oh):
            for c in range(ow):
                terms, positive = [], False
                for i in range(kh):
                    for j in range(kw):
                        weight = weights[base + i * kw + j]
                        incident = source[(band * height + r + kh - 1 - i) * width + c + kw - 1 - j]
                        positive |= weight > 0 and incident > 0
                        terms.append(weight * incident)
                expected = _sum(terms, "PSF convolution")
                require(not positive or expected >= sys.float_info.min,
                        "Weighted PSF erased positive support or produced a subnormal")
                actual = optical[(band * oh + r) * ow + c]
                require(actual == 0 or actual >= sys.float_info.min, "Subnormal weighted PSF output")
                arithmetic_close(actual, expected, kh * kw, "PSF convolution")


def axis_overlaps(source, target):
    require(source[0] <= target[0] and source[-1] >= target[-1],
            "Optical support does not cover every complete photosite footprint")
    result, current = [], 0
    for left, right in zip(target, target[1:]):
        while current + 1 < len(source) and source[current + 1] <= left:
            current += 1
        pieces, i = [], current
        while i + 1 < len(source) and source[i] < right:
            overlap = min(right, source[i + 1]) - max(left, source[i])
            if overlap > 0:
                weight = overlap / (right - left)
                require(math.isfinite(weight) and weight > 0, "Unrepresentable positive overlap")
                pieces.append((i, weight))
            i += 1
        require(pieces and abs(_sum((weight for _, weight in pieces), "overlap weights") - 1)
                <= 64 * len(pieces) * sys.float_info.epsilon, "Incomplete footprint overlap weights")
        result.append(pieces)
    return result


def verify_sampled(data, optical_axes, target_axes, bands):
    sx, sy = optical_axes
    tx, ty = target_axes
    wx, wy = axis_overlaps(sx, tx), axis_overlaps(sy, ty)
    width, height, tw, th = len(sx) - 1, len(sy) - 1, len(tx) - 1, len(ty) - 1
    source, sampled = data["optical_irradiance"], data["sampled_irradiance"]
    def aligned_axis(source_edges, target_edges):
        try:
            start = source_edges.index(target_edges[0])
        except ValueError:
            return False
        return source_edges[start:start + len(target_edges)] == target_edges
    aligned = aligned_axis(sx, tx) and aligned_axis(sy, ty)
    if not aligned:
        require(all(v == 0 or v >= sys.float_info.min for v in source),
                "Weighted sampling cannot accept positive subnormal input")
    for band in range(bands):
        for r, rows in enumerate(wy):
            for c, cols in enumerate(wx):
                actual = sampled[(band * th + r) * tw + c]
                if aligned:
                    expected = source[(band * height + rows[0][0]) * width + cols[0][0]]
                    require(actual == expected, "Aligned footprint sampling must be an exact copy")
                    continue
                terms, positive = [], False
                for row, yw in rows:
                    for col, xw in cols:
                        incident = source[(band * height + row) * width + col]
                        positive |= incident > 0
                        terms.append((incident * yw) * xw)
                expected = _sum(terms, "rectangular overlap average")
                require(not positive or expected >= sys.float_info.min,
                        "Weighted sampling erased positive support or produced a subnormal")
                require(actual == 0 or actual >= sys.float_info.min, "Subnormal weighted sampled output")
                arithmetic_close(actual, expected, len(rows) + len(cols) + 2,
                                 "rectangular overlap average")


def verify_electrons(data, sensor, exposure):
    sampled, expected = data["sampled_irradiance"], data["expected_electrons"]
    height, width = sensor["image_size"]
    pixels, bands = height * width, len(sensor["wavelength_nm"])
    if exposure == 0 or sensor["fill_factor"] == 0 or not any(sampled):
        require(not any(expected), "Exact zero collection must yield zero expected electrons")
        return
    collection = exposure * sensor["pixel_pitch_m"] ** 2 * sensor["fill_factor"]
    require(math.isfinite(collection) and collection > 0, "Unsupported collection-factor arithmetic")
    for index in range(pixels):
        row, col = divmod(index, width)
        channel = "RGB".index(sensor["cfa_pattern"][2 * (row % 2) + col % 2])
        incident = _sum((sampled[k * pixels + index] * sensor["bin_width_nm"][k]
                         for k in range(bands)), "spectral incident photons") * collection
        require(math.isfinite(incident), "Integrated incident photons overflow")
        terms = [sampled[k * pixels + index] * (sensor["qe"][k][channel] * sensor["bin_width_nm"][k])
                 for k in range(bands)]
        reference = _sum(terms, "spectral photocharge") * collection
        positive = any(sampled[k * pixels + index] > 0 and sensor["qe"][k][channel] > 0
                       for k in range(bands))
        require(not positive or reference > 0, "Positive spectral charge underflowed to zero")
        arithmetic_close(expected[index], reference, 8 * bands, "spectral expected electrons")
        require(not sensor["shot_noise"] or reference <= 1e9, "Poisson expectation exceeds supported range")


def verify_readout(meta, data, cfg, sensor, source, engine):
    nested = data["readout_metadata"]
    mode = meta["readout_mode"]
    fields(nested, SINGLE_FIELDS if mode == "single" else DUAL_FIELDS, "nested readout manifest")
    require(runtime(nested["runtime"]) == engine and nested["runtime"] == meta["runtime"]
            and provenance(nested["provenance"]) == source
            and nested["provenance"] == meta["provenance"], "Nested runtime/provenance association disagrees")
    require(number(nested["exposure_s"], "nested exposure", 0) == meta["exposure_s"]
            and integer(nested["seed"], "nested seed", 0, 2**32 - 1) == meta["seed"],
            "Nested exposure/seed association disagrees")
    nested_cfg, _ = config(nested["sensor" if mode == "single" else "configuration"], mode)
    require(nested_cfg == cfg, "Nested complete configuration disagrees")
    require(nested["synthetic"] is True and nested["authentic_arriraw"] is False
            and nested["calibrated" if mode == "single" else "calibrated_alev4"] is False,
            "Nested readout authenticity labels disagree")
    if mode == "single":
        labels = {"format": "ALEV4-SYNTHETIC-RAW", "schema_version": "1.0",
                  "algorithm_version": "phase1-baseline-v1", "sampler_version": "Poisson-Knuth-PTRS-v1",
                  "sample_type": "uint16", "byte_order": "little-endian", "layout": "row-major", "units": "DN"}
        require(all(nested[key] == value for key, value in labels.items()), "Invalid nested single format")
        text_value(nested["description"], "single-gain description")
        require([integer(nested["height"], "height", 1), integer(nested["width"], "width", 1)]
                == sensor["image_size"] and nested["cfa_pattern"] == sensor["cfa_pattern"]
                and shape(nested["cfa_origin"], 2, "CFA origin") == [1, 1]
                and integer(nested["byte_count"], "RAW byte count", 2, 2 * MAX_SAMPLES)
                == 2 * math.prod(sensor["image_size"]), "Nested RAW shape/CFA/length disagrees")
        maximum = 2**sensor["adc_bits"] - 1
        require(all(value <= maximum for value in data["raw"]), "RAW exceeds its ADC range")
        if not sensor["shot_noise"] and sensor["read_noise_e"] == 0:
            for actual, expected in zip(data["raw"], data["expected_electrons"]):
                analog = min(expected, sensor["full_well_e"]) * sensor["gain_dn_per_e"] + sensor["black_level_dn"]
                require(math.isfinite(analog), "Deterministic readout overflow")
                require(actual == min(max(math.floor(analog + 0.5), 0), maximum),
                        "Deterministic single readout disagrees with physical clipping/ADC rounding")
    else:
        labels = {"format": "ALEV4-SYNTHETIC-DUAL-GAIN", "schema_version": "1.0",
                  "algorithm_version": "phase2-dual-gain-v1", "array_order": "row-major",
                  "byte_order": "little-endian", "input_units": DENSITY_UNITS,
                  "cfa_origin": "top-left (1,1)"}
        require(all(nested[key] == value for key, value in labels.items()), "Invalid nested dual format")
        require(shape(nested["image_size"], 2) == sensor["image_size"]
                and nested["units"] == phase2.UNITS
                and nested["files"] == {key: "readout" + suffix for key, suffix in phase2.PAYLOADS.items()},
                "Nested dual shape/units/file associations disagree")
        hmax, lmax = (2**cfg[key]["adc_bits"] - 1 for key in ("high_gain", "low_gain"))
        deterministic = not sensor["shot_noise"] and cfg["high_gain"]["read_noise_e"] == 0 \
            and cfg["low_gain"]["read_noise_e"] == 0
        for i, (high, low, merged, flag) in enumerate(zip(data["high_raw"], data["low_raw"],
                                                         data["merged_electrons"], data["flags"])):
            require(high <= hmax and low <= lmax, "Dual RAW exceeds configured ADC range")
            expected, _, hu, lu = phase2.merge_sample(high, low, cfg)
            # Preserve the unchanged Phase 2 signed-merge tolerance exactly.
            phase2.close(merged, expected, "observable dual merge", rel_tol=0,
                         abs_tol=64 * math.ulp(max(1.0, abs(expected))))
            require(bool(flag & 32) == hu and bool(flag & 64) == lu
                    and bool(flag & 128) == ((hu or lu) and not bool(flag & 1)), "Dual validity flags disagree")
            require(not (flag & 2 and flag & 4) and not (flag & 8 and flag & 16)
                    and (not flag & 2 or high == 0) and (not flag & 4 or high == hmax)
                    and (not flag & 8 or low == 0) and (not flag & 16 or low == lmax),
                    "Dual clipping diagnostics contradict observed rails")
            if not sensor["shot_noise"]:
                require(bool(flag & 1) == (data["expected_electrons"][i] >= sensor["full_well_e"]),
                        "Deterministic physical-saturation flag disagrees")
            if deterministic:
                expected_high, expected_low, expected_flag = phase2.deterministic_codes(data["expected_electrons"][i], cfg)
                require((high, low, flag) == (expected_high, expected_low, expected_flag),
                        "Deterministic dual readout/diagnostics disagree")
    return not sensor["shot_noise"] and (sensor["read_noise_e"] == 0 if mode == "single" else
                                         cfg["high_gain"]["read_noise_e"] == cfg["low_gain"]["read_noise_e"] == 0)


def verify_bundle(directory, expected_commit=None):
    """Validate a general bundle; return decoded arrays and honest check scope.

    No demo-specific dimensions or irradiance are assumed here. Empty observed
    revisions are permitted by the general format; an exact revision request
    cannot be satisfied by an empty repository revision. Complete release
    evidence additionally requires all observed SHAs and frozen dependency pins.
    """
    directory = directory_path(directory)
    manifest_path = directory / "spatial.json"
    meta = read_json(manifest_path)
    fields(meta, MANIFEST_FIELDS, "spatial manifest")
    labels = {"format": "ALEV4-SYNTHETIC-SPATIAL", "schema_version": "1.0",
              "algorithm_version": "phase3-spatial-v1", "byte_order": "little-endian",
              "array_order": "plane-major-row-major"}
    require(all(meta[key] == value for key, value in labels.items()), "Invalid spatial format/layout labels")
    require(meta["synthetic"] is True and meta["calibrated_alev4"] is False
            and meta["authentic_arriraw"] is False, "Invalid spatial authenticity labels")
    mode, stage = meta["readout_mode"], meta["input_stage"]
    require(mode in ("single", "dual") and stage in ("pre_psf", "post_optics"), "Unsupported readout mode/input stage")
    cfg, sensor = config(meta["configuration"], mode)
    target_axes = geometry(meta["geometry"], sensor)
    input_axes, optical_axes = grid(meta["input_grid"], "input grid"), grid(meta["optical_grid"], "optical grid")
    order = (["optical_psf"] if stage == "pre_psf" else []) + \
        ["area_overlap_average", "spectral_integration", mode + "_gain_readout"]
    require(keyed_list(meta["operation_order"], "step", "operation order", 4) == order,
            "Spatial operation stage/order disagrees")
    require(isinstance(meta["spatial_provenance"], dict), "Spatial provenance must be a scalar object")
    informational(meta["spatial_provenance"])
    exposure = number(meta["exposure_s"], "exposure", 0)
    integer(meta["seed"], "seed", 0, 2**32 - 1)
    source, engine = provenance(meta["provenance"]), runtime(meta["runtime"])
    expected_revision(source, expected_commit)
    bands, image = len(sensor["wavelength_nm"]), sensor["image_size"]
    expected_files = {
        "input_irradiance": ("input.f64", "float64", [len(input_axes[1])-1, len(input_axes[0])-1, bands], DENSITY_UNITS),
        "optical_irradiance": ("optical.f64", "float64", [len(optical_axes[1])-1, len(optical_axes[0])-1, bands], DENSITY_UNITS),
        "sampled_irradiance": ("sampled.f64", "float64", [*image, bands], DENSITY_UNITS),
        "expected_electrons": ("expected.f64", "float64", image, "electrons"),
        "readout_metadata": ("readout.json", "utf8", [], "metadata"),
    }
    records = meta["files"]
    require(isinstance(records, dict), "File descriptors must be a scalar object")
    if stage == "pre_psf":
        require(isinstance(records.get("psf"), dict), "Missing PSF descriptor")
        psf_shape = shape(records["psf"].get("shape"), 3, "PSF shape", 1_000_000)
        expected_files["psf"] = ("psf.f64", "float64", psf_shape, "unitless weights")
    else:
        require(meta["psf"] == [], "Post-optics stage must not carry a PSF")
    if mode == "single":
        expected_files["raw"] = ("readout.raw", "uint16", image, "DN")
    else:
        for key, suffix in phase2.PAYLOADS.items():
            kind = "uint16" if key.endswith("raw") else "float64" if key == "merged_electrons" else "uint8"
            expected_files[key] = ("readout" + suffix, kind, image, phase2.UNITS[key])
    fields(records, expected_files, "spatial file associations")
    require({path.name for path in directory.iterdir()} ==
            {"spatial.json", *(specification[0] for specification in expected_files.values())},
            "Spatial directory has missing or extra entries")
    files, data = [manifest_path], {}
    for key, specification in expected_files.items():
        path, data[key] = _file(directory, records[key], *specification)
        files.append(path)
    require(len({regular(path) for path in files}) == len(files), "Spatial artifacts alias each other")
    verify_optical(meta, data, input_axes, optical_axes, sensor["wavelength_nm"])
    verify_sampled(data, optical_axes, target_axes, bands)
    verify_electrons(data, sensor, exposure)
    deterministic = verify_readout(meta, data, cfg, sensor, source, engine)
    return {"metadata": meta, "configuration": cfg, "sensor": sensor, "files": files,
            "source": source, "runtime": engine, **data,
            "general_format_checked": True, "spatial_physics_checked": True,
            "deterministic_readout_checked": deterministic, "demo_fixture_checked": False,
            "random_stream_reproduced": False, "input_source_authenticated": False}


def _fixture_geometry(bundle, name):
    geometry = bundle["metadata"]["geometry"]
    full = [7, 9] if name == "shifted_impulse" else [8, 10] if name == "crop_cfa" else [6, 8]
    roi = [2, 2, 5, 7] if name == "crop_cfa" else [1, 1, *full]
    require(geometry == {"schema_version": "1.0", "full_grid_size": full, "active_roi": roi,
                         "pixel_pitch_m": 6e-6, "origin_xy_m": [0, 0],
                         "full_grid_cfa_pattern": "RGGB",
                         "parameter_sources": {"id001": "ASSUMED-GENERIC-GEOMETRY",
                                               "id002": "ASSUMED-CFA-ORIGIN"}},
            f"{name}: fixed geometry/source configuration drift")
    return full, roi


def fixture_config(bundle, name):
    """Bind the seven analytic fixtures to their complete documented settings."""
    full, roi = _fixture_geometry(bundle, name)
    cfg, sensor, meta = bundle["configuration"], bundle["sensor"], bundle["metadata"]
    dual = name == "dual_spatial"
    sensor_expected = {"schema_version": "1.0", "image_size": roi[2:], "wavelength_nm": [500, 600],
                       "bin_width_nm": [20, 20], "qe": [[.1, .8, .2], [.7, .2, .05]],
                       "pixel_pitch_m": 6e-6, "fill_factor": .8, "full_well_e": 30000,
                       "read_noise_e": 3 if dual else 0, "gain_dn_per_e": .5,
                       "black_level_dn": 64, "adc_bits": 16,
                       "cfa_pattern": "BGGR" if name == "crop_cfa" else "RGGB", "shot_noise": dual}
    require(sensor == sensor_expected, f"{name}: fixed spectral/readout settings drift")
    if dual:
        require(cfg == {"schema_version": "2.0", "sensor": sensor_expected,
                        "high_gain": {"gain_dn_per_e": 4, "read_noise_e": 1, "black_level_dn": 64, "adc_bits": 12},
                        "low_gain": {"gain_dn_per_e": .1, "read_noise_e": 5, "black_level_dn": 64, "adc_bits": 12},
                        "merge": {"start_e": 600, "end_e": 900}}, "Dual demo electronics/merge drift")
    require(meta["readout_mode"] == ("dual" if dual else "single")
            and meta["input_stage"] == ("post_optics" if name == "crop_cfa" else "pre_psf")
            and meta["spatial_provenance"] == {}, f"{name}: fixed stage/mode/provenance drift")
    return full, roi


def verify_analytic_fixture(bundle, name):
    full, roi = fixture_config(bundle, name)
    meta, p, base = bundle["metadata"], 6e-6, 1e14
    step = p / 2 if name == "sinusoid" else p
    halo = [1, 0, 1, 1] if name == "shifted_impulse" else \
        [1, 1, 1, 1] if name in ("flat_binomial", "edge", "sinusoid", "dual_spatial") else [0, 0, 0, 0]
    factor = 2 if name == "sinusoid" else 1
    xe = [i * step for i in range(-halo[2], full[1] * factor + halo[3] + 1)]
    ye = [i * step for i in range(-halo[0], full[0] * factor + halo[1] + 1)]
    require(meta["input_grid"]["x_edges_m"] == xe and meta["input_grid"]["y_edges_m"] == ye,
            f"{name}: fixed input physical grid/PSF halo drift")
    if name != "crop_cfa":
        kernel = [1] if name == "identity_single" else [0, .25, .25, .125, .25, .125] \
            if name == "shifted_impulse" else [.0625, .125, .0625, .125, .25, .125, .0625, .125, .0625]
        kernel_shape = [1, 1, 1] if name == "identity_single" else [2, 3, 1] if name == "shifted_impulse" else [3, 3, 1]
        origin = [1, 1] if name == "identity_single" else [1, 2] if name == "shifted_impulse" else [2, 2]
        require(list(bundle["psf"]) == kernel and meta["files"]["psf"]["shape"] == kernel_shape
                and meta["psf"] == {"schema_version": "1.0", "origin_rc": origin,
                                     "spacing_yx_m": [step, step], "wavelength_nm": [],
                                     "boundary_policy": "valid",
                                     "parameter_sources": {"id001": "ASSUMED-DISCRETE-PSF"}},
                f"{name}: fixed PSF weights/origin/spectral association drift")
    ih, iw = len(ye) - 1, len(xe) - 1
    frequency = 1 / (8 * p)
    for band, multiplier in enumerate((1, .6)):
        for r in range(ih):
            y = (ye[r] + ye[r + 1]) / 2
            for c in range(iw):
                x = (xe[c] + xe[c + 1]) / 2
                if name == "flat_binomial":
                    field = base
                elif name == "shifted_impulse":
                    field = base * 20 if (r, c) == (3, 4) else 0
                elif name == "edge":
                    field = base * (.2 + .8 * (x >= 4 * p))
                elif name == "sinusoid":
                    z = frequency * step
                    field = base * (1 + .4 * math.sin(2 * math.pi * frequency * x)
                                    * math.sin(math.pi * z) / (math.pi * z))
                elif name == "dual_spatial":
                    field = base * (2 + 25 * x / (full[1] * p))
                else:
                    field = base * (.25 + x / (full[1] * p) + .5 * y / (full[0] * p))
                arithmetic_close(bundle["input_irradiance"][(band * ih + r) * iw + c],
                                 multiplier * field, 24, f"{name}: analytic source density")
        # A second, closed-form footprint oracle avoids merely accepting a
        # producer-defined input. It checks the asymmetric impulse direction,
        # binomial edge transition, affine preservation, and sinusoidal MTF.
        height, width = roi[2:]
        for r in range(height):
            y = (roi[0] + r - .5) * p
            for c in range(width):
                x = (roi[1] + c - .5) * p
                if name == "flat_binomial":
                    field = base
                elif name == "shifted_impulse":
                    i, j = r - 2, c - 2
                    field = base * 20 * ([0, .25, .25, .125, .25, .125][i * 3 + j]
                                        if 0 <= i < 2 and 0 <= j < 3 else 0)
                elif name == "edge":
                    field = base * [.2, .2, .2, .4, .8, 1, 1, 1][c]
                elif name == "sinusoid":
                    z = frequency * p
                    optical_mtf = math.cos(math.pi * frequency * step) ** 2
                    aperture = math.sin(math.pi * z) / (math.pi * z)
                    field = base * (1 + .4 * optical_mtf * aperture * math.sin(2 * math.pi * frequency * x))
                elif name == "dual_spatial":
                    field = base * (2 + 25 * x / (full[1] * p))
                else:
                    field = base * (.25 + x / (full[1] * p) + .5 * y / (full[0] * p))
                arithmetic_close(bundle["sampled_irradiance"][(band * height + r) * width + c],
                                 multiplier * field, 32, f"{name}: analytic sampled density")
    if name == "dual_spatial":
        require(len(set(bundle["high_raw"])) > 1 and len(set(bundle["low_raw"])) > 1,
                "Noisy dual fixture lacks observed channel variation")
        # This checks a deliberately loose, simultaneous tail bound, not a
        # particular random realization. Poisson Bernstein plus the Gaussian
        # tail bound and half an ADC step cover each low-path observation.
        # The union-bound failure budget across this 48-pixel fixture is 1e-12.
        t = math.log(4 * len(bundle["expected_electrons"]) / 1e-12)
        path = bundle["configuration"]["low_gain"]
        for code, mean in zip(bundle["low_raw"], bundle["expected_electrons"]):
            observation = (code - path["black_level_dn"]) / path["gain_dn_per_e"]
            bound = math.sqrt(2 * mean * t) + 2 * t / 3 + math.sqrt(2 * t) * path["read_noise_e"] \
                + .5 / path["gain_dn_per_e"]
            require(abs(observation - mean) <= bound,
                    "Noisy dual fixture violates its Poisson/read-noise observation bound")


def verify_iset_fixture(bundle, reference=None):
    """Check the restricted adapter contract; do not authenticate source claims."""
    meta, sensor = bundle["metadata"], bundle["sensor"]
    require(meta["readout_mode"] == "single" and meta["input_stage"] == "post_optics"
            and sensor["image_size"] == [16, 16] and sensor["wavelength_nm"] == list(range(400, 701, 10))
            and sensor["bin_width_nm"] == [10] * 31 and sensor["pixel_pitch_m"] == 5e-6
            and sensor["fill_factor"] == 1 and sensor["full_well_e"] == 1e8
            and sensor["read_noise_e"] == 0 and sensor["gain_dn_per_e"] == 1
            and sensor["black_level_dn"] == 64 and sensor["adc_bits"] == 16
            and sensor["cfa_pattern"] == "RGGB" and sensor["shot_noise"] is False,
            "ISET checker sensor/stage contract drift")
    require(meta["geometry"] == {"schema_version": "1.0", "full_grid_size": [16, 16],
                                  "active_roi": [1, 1, 16, 16], "pixel_pitch_m": 5e-6,
                                  "origin_xy_m": [-40e-6, -40e-6], "full_grid_cfa_pattern": "RGGB",
                                  "parameter_sources": {"id001": "ISET-PINNED-SPATIAL"}},
            "ISET checker geometry/source contract drift")
    info = meta["spatial_provenance"]
    labels = {"adapter": "restricted_iset_spatial_fixture", "fixture_kind": "checker",
              "input_native_semantics": "point_samples", "reconstruction": "bilinear_between_native_optical_points",
              "cell_conversion": "four_corner_mean_with_optical_knots_and_sensor_edges",
              "oi_padding": "mean", "offaxis_method": "skip", "reference_source": "ISET-PINNED-SPATIAL",
              "native_point_units": DENSITY_UNITS}
    require(all(info.get(key) == value for key, value in labels.items())
            and info.get("optics_already_applied") is True and info.get("extra_psf_applied") is False
            and number(info.get("scene_hfov_degrees"), "ISET field of view") == 3,
            "ISET point-to-cell provenance contract drift")
    require(shape(info.get("native_point_size"), 3, "ISET native point shape") == [40, 40, 31],
            "ISET native point fixture shape drift")
    spacing = vector(info.get("native_point_spacing_yx_m"), 2, "ISET native spacing", positive=True)
    require(all(step >= sensor["pixel_pitch_m"] for step in spacing), "ISET fixture would require an undeclared prefilter")
    bounds = info.get("native_point_bounds_xy_m")
    require(isinstance(bounds, list) and len(bounds) == 2, "ISET native bounds are missing")
    bounds = [vector(row, 2, "ISET native bounds") for row in bounds]
    for axis in range(2):
        require(bounds[0][axis] <= -40e-6 and bounds[1][axis] >= 40e-6, "ISET native support misses the sensor")
        arithmetic_close(bounds[1][axis] - bounds[0][axis], 39 * spacing[1 - axis], 8,
                         "ISET native physical extent")
    height, width, bands = meta["files"]["input_irradiance"]["shape"]
    require(height == width == 28 and bands == 31, "ISET exact knot/footprint partition shape drift")
    planes = [bundle["input_irradiance"][k * height * width:(k + 1) * height * width] for k in range(bands)]
    require(all(max(plane) > 0 for plane in planes)
            and any((max(plane) - min(plane)) / max(plane) > .05 for plane in planes),
            "ISET checker is not a nonuniform optical field")
    require(all(0 < value < 65535 - 64 for value in bundle["expected_electrons"]),
            "ISET checker must have positive unsaturated expected charge")
    if reference is not None:
        flat = _matrix(reference, [16, 16], "ISET checker reference")
        scale = max(flat)
        error = max(abs(a - b) for a, b in zip(bundle["expected_electrons"], flat)) / scale
        require(error <= 5e-12, "ISET demo disagrees with the numerical scalar bilinear reference")


def verify_demo(directory, source=None, engine=None, iset_reference=None):
    """Return (all verified demo files, fixed-fixture metrics)."""
    directory = directory_path(directory)
    summary_path = directory / "phase3-demo-summary.json"
    summary = read_json(summary_path)
    fields(summary, {"schema_version", "phase", "synthetic", "calibrated_alev4", "demo_complete",
                     "iset_included", "frame_count", "frames", "runtime", "provenance"}, "Phase 3 summary")
    require(summary["schema_version"] == "1.0" and integer(summary["phase"], "phase", 3, 3) == 3
            and summary["demo_complete"] is True and summary["iset_included"] is True
            and summary["synthetic"] is True and summary["calibrated_alev4"] is False,
            "Complete eight-fixture Phase 3 demo including ISET is required")
    observed_source, observed_engine = provenance(summary["provenance"], complete=True), runtime(summary["runtime"])
    require((source is None or observed_source == source) and (engine is None or observed_engine == engine),
            "Demo source/runtime differs from numerical evidence")
    source, engine = observed_source, observed_engine
    frames = summary["frames"]
    require(isinstance(frames, list) and len(frames) == integer(summary["frame_count"], "frame count", 8, 8)
            and all(isinstance(frame, dict) for frame in frames)
            and [frame.get("name") for frame in frames] == list(NAMES), "Fixed eight-fixture inventory/order disagrees")
    require({path.name for path in directory.iterdir()} == {"phase3-demo-summary.json", *NAMES},
            "Demo has missing or extra entries")
    files, metrics = [summary_path], {}
    for index, frame in enumerate(frames):
        fields(frame, {"name", "readout_mode", "input_stage", "image_size", "seed", "exposure_s",
                       "minimum_expected_e", "maximum_expected_e", "sum_expected_e"}, "demo frame")
        name = frame["name"]
        bundle = verify_bundle(directory / name)
        meta = bundle["metadata"]
        require(bundle["source"] == source and bundle["runtime"] == engine
                and meta["provenance"] == summary["provenance"], f"{name}: source/runtime association disagrees")
        seed, exposure = 8301 + index, .001 if name == "iset_checker" else .01
        require(integer(frame["seed"], "summary seed", 0, 2**32 - 1) == meta["seed"] == seed
                and number(frame["exposure_s"], "summary exposure", 0) == meta["exposure_s"] == exposure,
                f"{name}: fixed seed/exposure association disagrees")
        require(frame["readout_mode"] == meta["readout_mode"] and frame["input_stage"] == meta["input_stage"]
                and shape(frame["image_size"], 2) == bundle["sensor"]["image_size"], f"{name}: summary association disagrees")
        if name == "iset_checker":
            verify_iset_fixture(bundle, iset_reference)
        else:
            verify_analytic_fixture(bundle, name)
        values = bundle["expected_electrons"]
        calculated = {"minimum_expected_e": min(values), "maximum_expected_e": max(values),
                      "sum_expected_e": _sum(values, "demo expected-electron sum")}
        for key, value in calculated.items():
            arithmetic_close(frame[key], value, len(values) if key.startswith("sum") else 1, f"{name}: {key}")
        metrics[name] = {**calculated, "readout_mode": meta["readout_mode"], "input_stage": meta["input_stage"],
                         "seed": seed, "exposure_s": exposure, "general_format_checked": True,
                         "demo_fixture_checked": True, "deterministic_readout_checked": bundle["deterministic_readout_checked"],
                         "analytic_input_oracle_checked": name != "iset_checker",
                         "iset_numerical_reference_checked": name == "iset_checker" and iset_reference is not None}
        files.extend(bundle["files"])
    require(len(files) == 66 and len({regular(path) for path in files}) == 66,
            "Demo files are missing or aliased across bundles")
    return files, metrics


def _suite(report, name):
    gate = report.get(name)
    require(isinstance(gate, dict) and gate.get("status") == "passed" and gate.get("passed") is True,
            f"Missing or failed numerical suite: {name}")
    count = integer(gate.get("test_count"), name + " test count", 1)
    tests = gate.get("tests")
    if isinstance(tests, dict) and count == 1:
        tests = [tests]
    require(isinstance(tests, list) and len(tests) == count, f"{name}: test inventory/count disagrees")
    require(all(isinstance(test, dict) and isinstance(test.get("name"), str) and test["name"].strip()
                and test.get("status") == "passed" and test.get("passed") is True for test in tests),
            f"{name}: missing or unpassed individual test group")
    require(len({test["name"] for test in tests}) == count, f"{name}: duplicate test group names")
    return count


def _matrix(value, dimensions, label):
    height, width = dimensions
    require(isinstance(value, list) and len(value) == height
            and all(isinstance(row, list) and len(row) == width for row in value), f"{label}: wrong matrix shape")
    return [number(item, label, 0) for row in value for item in row]


def check_iset_report(gate, source, engine):
    metrics = gate.get("metrics")
    require(isinstance(metrics, dict) and metrics.get("synthetic") is True
            and metrics.get("calibrated_alev4") is False
            and metrics.get("native_matlab_executed") is (engine[0] == "MATLAB"),
            "ISET suite execution/runtime labels disagree")
    fixtures = metrics.get("fixtures")
    fields(fixtures, {"uniform", "ramp", "checker", "edge"}, "required genuine ISET fixtures")
    for name, fixture in fixtures.items():
        require(isinstance(fixture, dict) and fixture.get("fixture_kind") == name
                and shape(fixture.get("image_size"), 2) == [16, 16]
                and fixture.get("input_stage") == "post_optics" and fixture.get("extra_psf_applied") is False
                and provenance(fixture.get("provenance"), complete=True) == source,
                f"ISET {name}: fixture metadata/provenance disagrees")
        reference = _matrix(fixture.get("reference_expected_electrons"), [16, 16], "ISET scalar reference")
        native = _matrix(fixture.get("native_expected_electrons"), [16, 16], "ISET native reference")
        require(min(reference) > 0, "ISET scalar reference must be illuminated")
        error = max(abs(a - b) for a, b in zip(native, reference)) / max(reference)
        require(error <= 5e-5, f"ISET {name}: native quadrature exceeds the fixed numerical limit")
        # Numerical reports use the unchanged native JSON encoder. A few
        # ULPs in serialized native/reference arrays propagate into the small
        # difference, so bound that propagation from the retained arrays.
        # The reported error value does not set or widen this allowance.
        metadata_error_bound = 8 * max(math.ulp(v) for v in native + reference) / max(reference) \
            + 64 * math.ulp(error)
        observed = number(fixture.get("native_relative_error"), "ISET reported native error", 0)
        require(abs(observed - error) <= metadata_error_bound,
                f"ISET {name}: reported native error disagrees with retained matrices")
        require(number(fixture.get("project_relative_error"), "ISET project error", 0) <= 5e-12,
                "ISET project integration exceeds its fixed tolerance")
        for key, expected in (("native_samples_per_axis", [1, 3, 9, 27]),
                              ("source_refinement_factors", [1, 2, 4, 8, 16])):
            sequence = fixture.get(key)
            require(isinstance(sequence, list) and len(sequence) == len(expected),
                    "ISET refinement sequences disagree")
            require([integer(value, key, 1, 100) for value in sequence] == expected,
                    "ISET refinement sequences disagree")
        native_errors = vector(fixture.get("native_relative_errors"), 4, "ISET native errors")
        source_errors = vector(fixture.get("source_refinement_relative_errors"), 5, "ISET source errors")
        require(all(value >= 0 for value in native_errors + source_errors), "Negative ISET refinement error")
        require(abs(native_errors[-1] - error) <= metadata_error_bound,
                "ISET final native error disagrees with retained matrices")
        variation = number(fixture.get("oi_spatial_variation"), "ISET optical spatial variation", 0)
        require(variation < 2e-5 if name == "uniform" else variation > .05,
                f"ISET {name}: uniform/nonuniform control failed")
        spacing = vector(fixture.get("native_spacing_yx_m"), 2, "ISET report spacing", positive=True)
        require(all(step >= 5e-6 for step in spacing), "ISET comparison requires a hidden prefilter")
        if name in ("checker", "edge"):
            require(native_errors[0] > .01 and source_errors[0] > .01
                    and native_errors[-1] < native_errors[0] / 10
                    and source_errors[-1] < source_errors[0] / 10,
                    f"ISET {name}: coarse controls/refinement convergence failed")
    return fixtures["checker"]["reference_expected_electrons"]


def check_numerical_report(report, expected_commit=None):
    require(report.get("schema_version") == "1.0" and integer(report.get("phase"), "phase", 3, 3) == 3
            and report.get("status") == "passed" and report.get("phase3_passed") is True
            and report.get("calibrated_alev4") is False and report.get("phase2_required") is True,
            "Full executed Phase 3 report requiring Phase 2/1 is required")
    source = provenance(report.get("provenance"), complete=True)
    engine = runtime({"name": report.get("runtime"), "version": report.get("runtime_version")})
    expected_revision(source, expected_commit)
    require(all(source[key] == value for key, value in PINNED_HEADS.items()),
            "Numerical evidence does not identify the frozen dependency pins")
    groups = sum(_suite(report, name) for name in GATES)
    previous = report.get("phase2")
    require(isinstance(previous, dict) and previous.get("schema_version") == "1.0"
            and integer(previous.get("phase"), "Phase 2 phase", 2, 2) == 2
            and previous.get("status") == "passed" and previous.get("phase2_passed") is True
            and previous.get("phase1_required") is True and previous.get("calibrated_alev4") is False,
            "Full executed Phase 2 prerequisite is required")
    require(provenance(previous.get("provenance"), complete=True) == source
            and runtime({"name": previous.get("runtime"), "version": previous.get("runtime_version")}) == engine,
            "Phase 2 prerequisite source/runtime differs")
    previous_groups = sum(_suite(previous, name) for name in phase2.GATES)
    phase2.check_phase1(previous.get("phase1"), source, engine)
    checker = check_iset_report(report["iset_spatial"], source, engine)
    return source, engine, groups, previous_groups, checker


def digest(path):
    return phase2.digest(path)


def verify_outputs(output_root, compare_dir=None, expected_commit=None):
    root = directory_path(output_root)
    validation = directory_path(root / "validation")
    report_path = validation / "phase3-validation.json"
    report = read_json(report_path)
    source, engine, groups, previous_groups, checker = check_numerical_report(report, expected_commit)
    demo = root / "demo"
    files, metrics = verify_demo(demo, source, engine, checker)
    hashes = {path.relative_to(demo).as_posix(): digest(path) for path in files}
    if compare_dir is not None:
        comparison = directory_path(compare_dir)
        require(comparison.resolve() != demo.resolve(), "Comparison must use a distinct resolved demo directory")
        other, _ = verify_demo(comparison, source, engine, checker)
        require({regular(path) for path in files}.isdisjoint({regular(path) for path in other}),
                "Repeated demo aliases primary artifacts, including cross-filename aliases")
        counterparts = {path.relative_to(comparison).as_posix(): path for path in other}
        require(set(counterparts) == set(hashes), "Repeated demo inventory differs")
        require(all(digest(counterparts[name]) == value for name, value in hashes.items()),
                "Repeated demo is not byte-identical")
    return {"status": "passed", "phase": 3, "frame_count": 8, "artifact_count": len(files),
            "numerical_test_groups": groups, "phase2_numerical_test_groups": previous_groups,
            "phase2_and_phase1_prerequisites_checked": True, "iset_numerical_evidence_checked": True,
            "source": source, "runtime": {"name": engine[0], "version": engine[1]},
            "frames": metrics, "artifact_sha256": hashes, "numerical_report_sha256": digest(report_path),
            "compared_demo_byte_identical": compare_dir is not None,
            "general_format_checked": True, "demo_fixtures_checked": True,
            "input_source_authenticated": False, "random_stream_reproduced": False,
            "iset_native_source_recomputed_in_python": False, "calibrated_alev4": False,
            "verification_boundary": "Spatial/spectral arithmetic and deterministic or observable readout checked; "
                "ISET source and numerical execution are retained evidence, not independently rerun by Python. "
                "Dependency worktree cleanliness and process independence require their separate acceptance gates."}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output_root", type=Path, nargs="?", default=Path("outputs/phase3"))
    parser.add_argument("--compare-dir", type=Path)
    parser.add_argument("--expected-commit")
    args = parser.parse_args(argv)
    try:
        result = verify_outputs(args.output_root, args.compare_dir, args.expected_commit)
    except (ArtifactError, OSError, TypeError, KeyError, OverflowError, RecursionError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
