#!/usr/bin/env python3
"""Independently verify Phase 4 typed bundles and complete release evidence.

Only the Python standard library is used. The verifier reads the actual packed
bytes, preserves native classes and shapes, and reconstructs the declared
deterministic sensor arithmetic. It does not invoke MATLAB/Octave, reproduce a
PRNG stream, authenticate a source field, or infer measured sensor calibration.
Recorded random draws are checked for finite support and zero-noise constraints;
their distribution and process independence require separate numerical gates.

``verify_bundle(directory)`` accepts enabled exposure/spatial_exposure bundles.
``verify_outputs(root, expected_commit=None, compare_dir=None)`` also requires
the frozen 24-frame demo, complete Phase 1--4 numerical reports, and optionally
a byte-identical repeat whose files have disjoint filesystem identities.
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
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


phase3 = _prior("verify_phase3_artifacts")
phase2 = phase3.phase2
ArtifactError = phase2.ArtifactError
require, number, integer = phase2.require, phase2.number, phase2.integer
fields, arithmetic_close = phase3.fields, phase3.arithmetic_close
MAX_JSON, MAX_SAMPLES = 2_000_000, 100_000_000
FORMAT = "ALEV4-SYNTHETIC-STRUCTURED-NOISE"
DENSITY_UNITS = "photons m^-2 s^-1 nm^-1"
PROVENANCE_MEANING = ("Observed Git HEADs; an empty value means unavailable. "
    "Uncommitted edits, object existence and agreement with dependency gitlinks "
    "are not established by these metadata observations.")
GATES = ("config", "core", "noise", "rng", "sequence", "spatial",
         "artifact_io", "demo_contract", "numerical_edges")
NAMES = ("deterministic_prnu_offsets", "dark_short", "dark_long", "dark_noisy",
         "shared_row_dual", "path_column_dual", "mixed_dual", "spatial_crop_single",
         "single_exposure_zero", "single_exposure_mid", "single_exposure_high",
         "dual_exposure_zero", "dual_exposure_mid", "dual_exposure_high",
         "single_gain_low", "single_gain_high", "dual_gain_low", "dual_gain_high",
         "sequence_primary_001", "sequence_primary_002", "sequence_primary_003",
         "sequence_reset_001", "sequence_continue_002", "sequence_continue_003")
SEED_TAGS = {"photo": 1, "dark": 2, "shared_row": 10, "shared_column": 11,
    "shared_frame": 12, "single_row": 20, "single_column": 21, "single_frame": 22,
    "single_pixel": 23, "high_row": 30, "high_column": 31, "high_frame": 32,
    "high_pixel": 33, "low_row": 40, "low_column": 41, "low_frame": 42, "low_pixel": 43}
ORDER = ["spectral_integration", "prnu_response", "dark_expectation",
    "separate_photo_dark_sampling", "charge_sum", "physical_full_well",
    "shared_electronics", "path_electronics_and_pixel_read_noise", "gain_and_black",
    "round", "adc_clip"]
RESULT_UNITS = {"input_irradiance": DENSITY_UNITS, "expected_incident_photons": "photons",
    "charge": "electrons", "components": "electrons", "read_electrons": "electrons",
    "raw_dn": "DN", "exposure_s": "s", "dark_current_e_per_s": "electrons s^-1",
    "prnu": "dimensionless"}
PATH_NAMES = ("shared", "single", "high_gain", "low_gain")
NOISE_PATH_FIELDS = {"fixed_offset_e", "row_noise_e", "column_noise_e", "frame_noise_e"}
PATH_FIELDS = {"read_electrons", "raw_dn", "adc_low_clipped", "adc_high_clipped", "adc_usable"}
BASE_READOUT_FIELDS = {"expected_electrons", "expected_photoelectrons", "expected_dark_electrons",
    "collected_electrons", "charge_electrons", "full_well_saturated", "seed",
    "expected_incident_photons", "exposure_s", "input_units", "spectral_bin_convention",
    "reconstruction_valid"}
RESULT_FIELDS = {"format", "schema_version", "result_kind", "readout_mode", "configuration",
    "geometry", "noise_model", "input_irradiance", "baseline_expected_electrons", "active_maps",
    "components", "readout", "operation_order", "seeds", "seed_policy", "stream_scope", "runtime",
    "units", "parameter_classification", "temperature_condition", "synthetic", "calibrated_alev4"}
MODEL_FIELDS = {"schema_version", "enabled", "full_grid_size", "realization_id",
    "reference_temperature_K", "prnu", "dark_current_e_per_s", "dark_shot_noise",
    "shared", "single", "high_gain", "low_gain", "parameter_sources"}


class Array:
    """A packed numeric leaf in true C order, retaining its native class/shape."""
    __slots__ = ("class_name", "shape", "values", "units", "offset")

    def __init__(self, class_name, shape, values, units=None, offset=None):
        self.class_name, self.shape, self.values = class_name, tuple(shape), values
        self.units, self.offset = units, offset

    def __len__(self):
        return len(self.values)

    def __iter__(self):
        return iter(self.values)

    def __getitem__(self, item):
        return self.values[item]

    def __eq__(self, other):
        return isinstance(other, Array) and self.class_name == other.class_name \
            and self.shape == other.shape and self.values == other.values

    def __repr__(self):
        return f"Array({self.class_name!r}, {self.shape!r}, samples={len(self)})"


class Cell(list):
    """Cell entries are in MATLAB linear order; shape is kept separately."""
    def __init__(self, items, shape):
        super().__init__(items)
        self.shape = tuple(shape)

    def __eq__(self, other):
        return isinstance(other, Cell) and self.shape == other.shape and list.__eq__(self, other)


class Char(str):
    def __new__(cls, text, shape):
        result = str.__new__(cls, text)
        result.shape = tuple(shape)
        return result

    def __eq__(self, other):
        return str.__eq__(self, other) and (not isinstance(other, Char) or self.shape == other.shape)

    __hash__ = str.__hash__


def directory_path(path):
    try:
        supplied = os.fspath(path)
    except TypeError as exc:
        raise ArtifactError("Artifact directory must be a filesystem path") from exc
    require(isinstance(supplied, str) and supplied and not any(c in supplied for c in "\0\r\n"),
            "Artifact directory must be nonempty path text")
    parts = re.split(r"[\\/]", supplied)
    require(not any(part in (".", "..") for part in parts)
            and not any(not part for part in parts[1:]),
            "Dot segments and repeated/trailing directory separators are unsupported")
    path = Path(path)
    require(".." not in path.parts, "Parent-segment directory aliases are unsupported")
    for item in (path, *path.parents):
        try:
            mode = item.lstat().st_mode
        except OSError as exc:
            raise ArtifactError("Missing/unreadable artifact directory") from exc
        require(stat.S_ISDIR(mode), "Artifact directories and ancestors must not be symlinks")
    return path


def entry_snapshot(path, *, directory=False):
    """Bind the bytes checked to unchanged ordinary entries through validation."""
    try:
        info = Path(path).lstat()
    except OSError as exc:
        raise ArtifactError("Artifact disappeared during verification") from exc
    require(stat.S_ISDIR(info.st_mode) if directory else
            stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
            "Artifact entry type or link count changed")
    return (info.st_dev, info.st_ino, info.st_mode, info.st_nlink,
            info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def regular(path):
    try:
        info = Path(path).lstat()
    except OSError as exc:
        raise ArtifactError(f"Missing/unreadable artifact: {Path(path).name}") from exc
    require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
            f"Artifact must be a regular single-link non-symlink file: {Path(path).name}")
    return info.st_dev, info.st_ino


def bounded(path, maximum):
    path = Path(path)
    identity = regular(path)
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    with os.fdopen(descriptor, "rb") as handle:
        before = os.fstat(handle.fileno())
        require(stat.S_ISREG(before.st_mode) and before.st_nlink == 1
                and (before.st_dev, before.st_ino) == identity and before.st_size <= maximum,
                "Artifact identity, link count, or bound changed while opening")
        content = handle.read(maximum + 1)
        after = os.fstat(handle.fileno())
    require(len(content) <= maximum and len(content) == before.st_size
            and (before.st_size, before.st_mtime_ns, before.st_ctime_ns)
            == (after.st_size, after.st_mtime_ns, after.st_ctime_ns)
            and regular(path) == identity, "Artifact changed during bounded read")
    return content


def read_json(path):
    return phase3.read_json(path, bounded(path, MAX_JSON))


def wire_shape(value):
    require(isinstance(value, list) and len(value) in (2, 3), "Typed shape needs rank two or three")
    result = tuple(integer(item, "typed dimension", 0, MAX_SAMPLES) for item in value)
    require(len(result) != 3 or result[-1] != 1, "Trailing singleton dimension is noncanonical")
    require(math.prod(v for v in result if v) <= MAX_SAMPLES, "Typed shape exceeds sample bound")
    return result


def leaf_units(path, class_name):
    pieces = path.split(".")
    name, parent = pieces[-1], pieces[-2] if len(pieces) > 1 else ""
    if "spatial_provenance" in pieces:
        return "metadata"
    if class_name == "logical":
        return "logical"
    if name in ("input_irradiance", "optical_irradiance", "sampled_irradiance"):
        return DENSITY_UNITS
    if name == "expected_incident_photons":
        return "photons"
    if name == "dark_current_e_per_s":
        return "electrons s^-1"
    if name == "gain_dn_per_e":
        return "DN electron^-1"
    if name in ("raw_dn", "black_level_dn"):
        return "DN"
    if re.search(r"(electrons|_e)$", name):
        return "electrons"
    if name.endswith("_m"):
        return "m"
    if name.endswith("_nm"):
        return "nm"
    if name == "reference_temperature_K":
        return "K"
    if name == "exposure_s":
        return "s"
    if name == "seed" or parent == "seeds":
        return "seed"
    if name == "values" and parent in ("source_integral", "source_crop_integral", "target_integral"):
        return "photons s^-1 nm^-1"
    if name == "adc_bits":
        return "bits"
    if name in {"image_size", "full_grid_size", "active_roi", "source_image_size", "output_image_size",
                "origin_rc", "retained_row_indices", "retained_column_indices",
                "required_halo_top_bottom_left_right", "kernel_shape", "input_shape", "output_shape",
                "spectral_plane_count", "x_weight_nonzeros", "y_weight_nonzeros"}:
        return "index/count"
    return "dimensionless"


def decode_tree(tree, payload, content):
    offset = samples = nodes = 0

    def decode(node, path, depth):
        nonlocal offset, samples, nodes
        nodes += 1
        require(depth <= 24 and nodes <= 20_000, "Typed tree exceeds depth/node bound")
        require(isinstance(node, dict) and type(node.get("kind")) is str, "Malformed typed node")
        kind = node["kind"]
        if kind == "struct":
            fields(node, {"kind", "fields"}, "struct node")
            require(isinstance(node["fields"], dict) and len(node["fields"]) <= 256,
                    "Struct fields must be a bounded object")
            return {name: decode(child, path + "." + name, depth + 1)
                    for name, child in node["fields"].items()}
        if kind == "cell":
            fields(node, {"kind", "shape", "items"}, "cell node")
            shape = wire_shape(node["shape"])
            count = math.prod(shape)
            require(count <= 256 and isinstance(node["items"], dict), "Oversized or malformed cell")
            keys = [f"i{i:06d}" for i in range(1, count + 1)]
            require(list(node["items"]) == keys, "Cell keys must be contiguous and ordered")
            return Cell([decode(node["items"][key], path + "." + key, depth + 1) for key in keys], shape)
        if kind == "char":
            fields(node, {"kind", "shape", "value"}, "char node")
            shape = wire_shape(node["shape"])
            value = phase3.text_value(node["value"], "character text", nonempty=False)
            require(len(shape) == 2 and (not value or shape[0] == 1)
                    and bool(value) == bool(math.prod(shape)), "Character row/empty shape disagrees")
            return Char(value, shape)
        require(kind == "numeric", "Unknown typed node kind")
        fields(node, {"kind", "class", "shape", "offset", "byte_count", "units"}, "numeric node")
        class_name = node["class"]
        require(type(class_name) is str and class_name in ("double", "uint16", "logical"),
                "Unsupported numeric native class")
        shape = wire_shape(node["shape"])
        count = math.prod(shape)
        code, size = {"double": ("d", 8), "uint16": ("H", 2), "logical": ("B", 1)}[class_name]
        byte_count = count * size
        require(integer(node["offset"], "numeric offset", 0, 8 * MAX_SAMPLES) == offset
                and integer(node["byte_count"], "numeric byte count", 0, 8 * MAX_SAMPLES) == byte_count
                and offset + byte_count <= len(content) and samples + count <= payload["sample_count"],
                "Numeric intervals must exactly follow contiguous depth-first traversal")
        require(node["units"] == leaf_units(path, class_name), "Numeric leaf units disagree")
        values = array.array(code)
        require(values.itemsize == size, "Required packed numeric representation is unavailable")
        values.frombytes(content[offset:offset + byte_count])
        if sys.byteorder != "little" and size > 1:
            values.byteswap()
        require(all(math.isfinite(value) for value in values), "Nonfinite packed numeric sample")
        require(class_name != "logical" or all(value in (0, 1) for value in values),
                "Logical payload bytes must be exactly zero or one")
        decoded = Array(class_name, shape, values, node["units"], offset)
        offset += byte_count
        samples += count
        return decoded

    result = decode(tree, "result", 0)
    require(offset == payload["byte_count"] == len(content) and samples == payload["sample_count"],
            "The complete typed tree must consume every payload byte and sample")
    return result


def plain(value):
    """MATLAB JSON-compatible values for summary association and prior helpers."""
    if isinstance(value, Array):
        entries = [bool(v) if value.class_name == "logical" else v for v in value]
        if not entries:
            return []
        if value.shape == (1, 1):
            return entries[0]
        if len(value.shape) == 2:
            h, w = value.shape
            if h == 1 or w == 1:
                return entries
            return [entries[r * w:(r + 1) * w] for r in range(h)]
        h, w, k = value.shape
        return [[entries[(r * w + c) * k:(r * w + c + 1) * k]
                 for c in range(w)] for r in range(h)]
    if isinstance(value, dict):
        return {name: plain(child) for name, child in value.items()}
    if isinstance(value, Cell):
        return [plain(child) for child in value]
    return str(value) if isinstance(value, Char) else value


def canonical_shape(shape):
    shape = tuple(shape)
    return shape[:-1] if len(shape) == 3 and shape[-1] == 1 else shape


def numeric(value, shape, label, class_name="double", lower=None, normal=False):
    require(isinstance(value, Array) and value.class_name == class_name
            and value.shape == canonical_shape(shape), f"{label}: incorrect class or canonical shape")
    if lower is not None:
        require(all(v >= lower for v in value), f"{label}: sample is below its supported range")
    if normal:
        require(all(v == 0 or abs(v) >= sys.float_info.min for v in value),
                f"{label}: unsupported subnormal arithmetic")
    return value.values


def scalar(value, label, low=-math.inf, high=math.inf, integral=False):
    observed = numeric(value, (1, 1), label)[0]
    return integer(observed, label, low, high) if integral else number(observed, label, low, high)


def boolean(value, label, expected=None):
    observed = bool(numeric(value, (1, 1), label, "logical")[0])
    require(expected is None or observed is expected, f"{label}: logical flag disagrees")
    return observed


def text(value, label, expected=None, nonempty=True):
    require(isinstance(value, Char) and (value.shape[0] == 1 or not value), f"{label}: expected a character row")
    phase3.text_value(str(value), label, nonempty=nonempty)
    require(expected is None or value == expected, f"{label}: literal disagrees")
    return str(value)


def char_shapes(value, engine):
    if isinstance(value, Char):
        # Octave stores char data as UTF-8 bytes; MATLAB uses UTF-16 units.
        count = len(value.encode("utf-8")) if engine[0] == "GNU Octave" else len(value.encode("utf-16-le")) // 2
        require(math.prod(value.shape) == count, "Character native extent disagrees with declared runtime")
    elif isinstance(value, dict):
        for child in value.values():
            char_shapes(child, engine)
    elif isinstance(value, Cell):
        for child in value:
            char_shapes(child, engine)


def cell_text(value, label, expected=None, maximum=256):
    require(isinstance(value, Cell) and value.shape == (1, len(value)) and 1 <= len(value) <= maximum,
            f"{label}: expected a bounded character-cell row")
    observed = [text(item, label) for item in value]
    require(expected is None or observed == expected, f"{label}: cell values disagree")
    return observed


def sources(value, label):
    result = cell_text(value, label, maximum=32)
    require(len(set(result)) == len(result)
            and all(len(v) <= 128 and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", v) for v in result),
            f"{label}: invalid or duplicate source identifier")
    return {f"id{i:03d}": item for i, item in enumerate(result, 1)}


def exact_array(actual, expected, shape, label, class_name="double", normal=False):
    entries = numeric(actual, shape, label, class_name, normal=normal)
    require(len(entries) == len(expected) and all(a == b for a, b in zip(entries, expected)),
            f"{label}: independently reconstructed samples disagree")
    return entries


def close_array(actual, expected, shape, operations, label):
    entries = numeric(actual, shape, label)
    require(len(entries) == len(expected), f"{label}: sample count disagrees")
    for a, b in zip(entries, expected):
        arithmetic_close(a, b, operations, label)
    return entries


def checked(value, label):
    require(math.isfinite(value) and (value == 0 or abs(value) >= sys.float_info.min),
            f"{label}: unsupported nonfinite or subnormal arithmetic")
    return value


def product(left, right, label):
    result = checked(left * right, label)
    require(result != 0 or left == 0 or right == 0, f"{label}: erased nonzero product")
    return result


def numeric_count(value):
    if isinstance(value, Array):
        return len(value)
    if isinstance(value, dict):
        return sum(numeric_count(child) for child in value.values())
    if isinstance(value, Cell):
        return sum(numeric_count(child) for child in value)
    return 0


def configuration(value, mode):
    require(mode in ("single", "dual"), "Unknown readout mode")
    sensor = value if mode == "single" else value.get("sensor") if isinstance(value, dict) else None
    fields(sensor, phase2.SENSOR_FIELDS, "sensor configuration")
    text(sensor["schema_version"], "sensor schema", "1.0")
    numeric(sensor["image_size"], (1, 2), "sensor image size")
    wave = sensor["wavelength_nm"]
    require(isinstance(wave, Array), "Missing typed wavelength vector")
    bands = len(wave)
    numeric(wave, (bands, 1), "canonical wavelength column")
    numeric(sensor["bin_width_nm"], (bands, 1), "canonical spectral-width column")
    numeric(sensor["qe"], (bands, 3), "canonical spectral RGB QE")
    for name in ("pixel_pitch_m", "fill_factor", "full_well_e", "read_noise_e", "gain_dn_per_e",
                 "black_level_dn", "adc_bits"):
        scalar(sensor[name], name)
    text(sensor["cfa_pattern"], "sensor CFA")
    boolean(sensor["shot_noise"], "photo shot-noise switch")
    if mode == "dual":
        fields(value, {"schema_version", "sensor", "high_gain", "low_gain", "merge"}, "dual configuration")
        text(value["schema_version"], "dual schema", "2.0")
        for path in ("high_gain", "low_gain"):
            fields(value[path], phase2.PATH_FIELDS, path + " configuration")
            for name in phase2.PATH_FIELDS:
                scalar(value[path][name], path + "." + name)
        fields(value["merge"], {"start_e", "end_e"}, "merge configuration")
        for name in ("start_e", "end_e"):
            scalar(value["merge"][name], "merge " + name)
    return phase3.config(plain(value), mode)


def geometry(value, sensor):
    fields(value, phase3.GEOMETRY_FIELDS, "geometry")
    text(value["schema_version"], "geometry schema", "1.0")
    for name, count in (("full_grid_size", 2), ("active_roi", 4), ("origin_xy_m", 2)):
        numeric(value[name], (1, count), "geometry " + name)
    scalar(value["pixel_pitch_m"], "geometry pixel pitch")
    text(value["full_grid_cfa_pattern"], "geometry Bayer pattern")
    data = plain(value)
    data["parameter_sources"] = sources(value["parameter_sources"], "geometry sources")
    return phase3.geometry(data, sensor)


def noise_model(value, geom):
    fields(value, MODEL_FIELDS, "noise model")
    text(value["schema_version"], "noise model schema", "1.0")
    boolean(value["enabled"], "structured model enabled", True)
    boolean(value["dark_shot_noise"], "dark shot-noise switch")
    numeric(value["full_grid_size"], (1, 2), "noise full-grid dimensions")
    require(value["full_grid_size"] == geom["full_grid_size"], "Noise model/full geometry dimensions disagree")
    dims = tuple(int(v) for v in value["full_grid_size"])
    identity = text(value["realization_id"], "realization identifier")
    require(len(identity) <= 128 and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", identity),
            "Malformed realization identifier")
    require(scalar(value["reference_temperature_K"], "reference temperature", 0) > 0,
            "Reference temperature must be positive")
    sources(value["parameter_sources"], "noise model sources")
    for name in ("prnu", "dark_current_e_per_s"):
        _fixed_map(value[name], dims, name, 0)
    for name in PATH_NAMES:
        fields(value[name], NOISE_PATH_FIELDS, "noise model " + name)
        _fixed_map(value[name]["fixed_offset_e"], dims, name + " fixed offset")
        for term in ("row_noise_e", "column_noise_e", "frame_noise_e"):
            scalar(value[name][term], name + " " + term, 0)


def _fixed_map(value, dims, label, lower=None):
    require(isinstance(value, Array) and value.shape in ((1, 1), dims),
            f"{label}: fixed map must be scalar or exactly full-grid sized")
    return numeric(value, value.shape, label, lower=lower)


def active_maps(value, model, geom, dims):
    fields(value, {"prnu", "dark_current_e_per_s", *PATH_NAMES}, "active maps")
    row, col, height, width = [int(v) for v in geom["active_roi"]]
    full_width = int(geom["full_grid_size"][1])

    def crop(fixed):
        if fixed.shape == (1, 1):
            return [fixed[0]] * (height * width)
        return [fixed[(row - 1 + r) * full_width + col - 1 + c]
                for r in range(height) for c in range(width)]

    for name in ("prnu", "dark_current_e_per_s"):
        exact_array(value[name], crop(model[name]), dims, "active " + name)
    for name in PATH_NAMES:
        fields(value[name], NOISE_PATH_FIELDS, "active " + name)
        exact_array(value[name]["fixed_offset_e"], crop(model[name]["fixed_offset_e"]), dims,
                    "active " + name + " fixed map")
        for term in ("row_noise_e", "column_noise_e", "frame_noise_e"):
            scalar(value[name][term], "active " + name + " " + term)
            require(value[name][term] == model[name][term], "Active RMS must equal its full-grid declaration")


def spectral_reference(irradiance, sensor, exposure):
    height, width = sensor["image_size"]
    bands = len(sensor["wavelength_nm"])
    density = numeric(irradiance, (height, width, bands), "spectral irradiance", lower=0)
    if exposure == 0 or sensor["fill_factor"] == 0 or not any(density):
        return [0.0] * (height * width), [0.0] * (height * width)
    collection = exposure * sensor["pixel_pitch_m"] ** 2 * sensor["fill_factor"]
    require(math.isfinite(collection) and collection > 0, "Unsupported spectral collection arithmetic")
    expected, incident = [], []
    for index in range(height * width):
        row, col = divmod(index, width)
        channel = "RGB".index(sensor["cfa_pattern"][2 * (row % 2) + col % 2])
        values = density[index * bands:(index + 1) * bands]
        inc = phase3._sum((v * sensor["bin_width_nm"][k] for k, v in enumerate(values)),
                          "spectral incident sum") * collection
        photo = phase3._sum((v * (sensor["qe"][k][channel] * sensor["bin_width_nm"][k])
                             for k, v in enumerate(values)), "spectral electron sum") * collection
        checked(inc, "incident photons")
        checked(photo, "baseline electrons")
        require(inc != 0 or not any(values), "Positive incident support was erased")
        require(photo != 0 or not any(v > 0 and sensor["qe"][k][channel] > 0
                                    for k, v in enumerate(values)), "Positive photoelectron support was erased")
        expected.append(photo)
        incident.append(inc)
    return expected, incident


def sampled_charge(value, means, dims, shot, label):
    actual = numeric(value, dims, label, lower=0, normal=True)
    if shot:
        require(all(mu <= 1e9 for mu in means), f"{label}: Poisson mean exceeds supported bound")
        require(all(v == math.floor(v) and (mu > 0 or v == 0) for v, mu in zip(actual, means)),
                f"{label}: sampled Poisson support or zero-mean association disagrees")
    else:
        require(all(v == mu for v, mu in zip(actual, means)), f"{label}: disabled shot noise changed expectation")
    return actual


def electronics(component, maps, pixel_sigma, dims, label):
    fields(component, {"fixed_offset_e", "row_e", "column_e", "frame_e", "pixel_e", "total_e"},
           label + " electronic components")
    height, width = dims
    fixed = exact_array(component["fixed_offset_e"], maps["fixed_offset_e"], dims,
                        label + " fixed electronic component", normal=True)
    row = numeric(component["row_e"], (height, 1), label + " row component", normal=True)
    column = numeric(component["column_e"], (1, width), label + " column component", normal=True)
    frame = numeric(component["frame_e"], (1, 1), label + " frame component", normal=True)
    pixel = numeric(component["pixel_e"], dims, label + " pixel component", normal=True)
    for values, sigma in ((row, scalar(maps["row_noise_e"], label + " row RMS", 0)),
                          (column, scalar(maps["column_noise_e"], label + " column RMS", 0)),
                          (frame, scalar(maps["frame_noise_e"], label + " frame RMS", 0)),
                          (pixel, pixel_sigma)):
        checked(sigma, label + " electronic RMS")
        require(sigma != 0 or not any(values), label + ": zero RMS component has nonzero samples")
    total = []
    for index, offset in enumerate(fixed):
        r, c = divmod(index, width)
        combined = checked(offset + row[r], label + " fixed plus row")
        combined = checked(combined + column[c], label + " plus column")
        combined = checked(combined + frame[0], label + " plus frame")
        total.append(checked(combined + pixel[index], label + " plus pixel"))
    exact_array(component["total_e"], total, dims, label + " total electronics", normal=True)
    return total


def half_away(value):
    """Round without the inaccurate floor(abs(x)+.5) shortcut near 2**52."""
    fraction, whole = math.modf(abs(value))
    rounded = int(whole) + (fraction >= 0.5)
    return -rounded if value < 0 else rounded


def verify_path(path, signed, config, dims, label, structured=True, exact_read=True):
    actual = numeric(path["read_electrons"], dims, label + " signed readout", normal=structured)
    if exact_read:
        require(all(a == b for a, b in zip(actual, signed)), label + ": signed electronic assembly disagrees")
    raw = numeric(path["raw_dn"], dims, label + " RAW", "uint16")
    maximum = 2**config["adc_bits"] - 1
    codes, low, high, usable = [], [], [], []
    for v in actual:
        gain = product(v, config["gain_dn_per_e"], label + " DN gain") if structured else v * config["gain_dn_per_e"]
        analog = gain + config["black_level_dn"]
        require(math.isfinite(analog), label + ": nonfinite analog DN")
        if structured:
            checked(analog, label + " black-offset DN")
        rounded = half_away(analog)
        code = min(max(rounded, 0), maximum)
        codes.append(code)
        low.append(rounded < 0)
        high.append(rounded > maximum)
        usable.append(0 < code < maximum)
    require(all(a == b for a, b in zip(raw, codes)), label + ": half-away rounding/ADC clipping disagrees")
    exact_array(path["adc_low_clipped"], low, dims, label + " lower ADC mask", "logical")
    exact_array(path["adc_high_clipped"], high, dims, label + " upper ADC mask", "logical")
    if structured:
        exact_array(path["adc_usable"], usable, dims, label + " conservative ADC usability", "logical")
    return usable


def verify_merge(value, high, low, cfg, dims):
    fields(value, {"electrons", "weight_high", "valid", "high_usable", "low_usable"}, "observed-channel merge")
    reference = [phase2.merge_sample(h, l, cfg) for h, l in zip(high, low)]
    electrons, weights, high_ok, low_ok = [list(v) for v in zip(*reference)]
    close_array(value["electrons"], electrons, dims, 16, "observed merge electrons")
    observed = close_array(value["weight_high"], weights, dims, 12, "observed merge weights")
    require(all(0 <= a <= 1 and (b not in (0, 1) or a == b) for a, b in zip(observed, weights)),
            "Observed merge violates its exact endpoints or bounds")
    exact_array(value["high_usable"], high_ok, dims, "merged high usability", "logical")
    exact_array(value["low_usable"], low_ok, dims, "merged low usability", "logical")
    valid = [h or l for h, l in zip(high_ok, low_ok)]
    exact_array(value["valid"], valid, dims, "merged validity", "logical")
    return valid


def validate_result(result):
    require(isinstance(result, dict), "Structured result must be a scalar struct")
    kind = text(result.get("result_kind"), "result kind")
    require(kind in ("exposure", "spatial_exposure"), "Unsupported structured result kind")
    extras = {"spatial_baseline", "spatial_baseline_role", "spatial_operation_order"} if kind == "spatial_exposure" else set()
    fields(result, RESULT_FIELDS | extras, "complete structured result")
    text(result["format"], "result format", FORMAT)
    text(result["schema_version"], "result schema", "1.0")
    text(result["parameter_classification"], "parameter classification", "assumed")
    boolean(result["synthetic"], "synthetic result", True)
    boolean(result["calibrated_alev4"], "calibrated result", False)
    text(result["seed_policy"], "component seed policy",
         "component_seed = mod(frame_seed + tag, 2^32); locally saved/restored Twister")
    text(result["stream_scope"], "random stream scope", "same runtime/version; no cross-runtime stream identity claim")
    fields(result["runtime"], {"name", "version"}, "runtime")
    for key in ("name", "version"):
        text(result["runtime"][key], "runtime " + key)
    engine = phase3.runtime(plain(result["runtime"]))
    require(len(engine[1]) <= 256 and all(32 <= ord(c) <= 126 for c in engine[1]), "Malformed runtime version")
    char_shapes(result, engine)
    mode = text(result["readout_mode"], "readout mode")
    cfg, sensor = configuration(result["configuration"], mode)
    dims = tuple(sensor["image_size"])
    axes = geometry(result["geometry"], sensor)
    model = result["noise_model"]
    noise_model(model, result["geometry"])
    fixed_count = sum(numeric_count(result[name]) for name in ("noise_model", "configuration", "geometry"))
    require(fixed_count + math.prod(dims) * (64 + len(sensor["wavelength_nm"])) <= MAX_SAMPLES,
            "Structured retained-array reservation exceeds its supported bound")
    active_maps(result["active_maps"], model, result["geometry"], dims)
    fields(result["temperature_condition"], {"reference_temperature_K", "policy"}, "temperature condition")
    require(result["temperature_condition"]["reference_temperature_K"] == model["reference_temperature_K"],
            "Temperature condition does not retain model reference")
    text(result["temperature_condition"]["policy"], "temperature policy",
         "declared applicability only; no temperature law or extrapolation")
    cell_text(result["operation_order"], "operation order", ORDER + (["observed_channel_merge"] if mode == "dual" else []))
    fields(result["units"], RESULT_UNITS, "result unit declarations")
    for key, unit in RESULT_UNITS.items():
        text(result["units"][key], key + " units", unit)
    observed = result["readout"]
    fields(observed, BASE_READOUT_FIELDS | ({"high_gain", "low_gain", "merged"} if mode == "dual" else PATH_FIELDS),
           "structured readout")
    fields(result["components"], {"photo_electrons", "dark_electrons", "shared"}
           | ({"high_gain", "low_gain"} if mode == "dual" else {"single"}), "structured components")
    exposure = scalar(observed["exposure_s"], "exposure seconds", 0)
    seed = scalar(observed["seed"], "frame seed", 0, 2**32 - 1, True)
    fields(result["seeds"], {"frame", *SEED_TAGS}, "component seeds")
    for name, tag in {"frame": 0, **SEED_TAGS}.items():
        require(scalar(result["seeds"][name], name + " seed", 0, 2**32 - 1, True) == (seed + tag) % 2**32,
                "Explicit named seed schedule disagrees")
    text(observed["input_units"], "readout input units", DENSITY_UNITS)
    text(observed["spectral_bin_convention"], "spectral convention", "bin-average density times explicit width in nm")
    baseline, incident = spectral_reference(result["input_irradiance"], sensor, exposure)
    retained_baseline = close_array(result["baseline_expected_electrons"], baseline, dims,
                                    8 * len(sensor["wavelength_nm"]), "baseline spectral expectation")
    close_array(observed["expected_incident_photons"], incident, dims,
                8 * len(sensor["wavelength_nm"]), "incident photon expectation")
    for name in ("baseline_expected_electrons",):
        numeric(result[name], dims, name, normal=True)
    numeric(observed["expected_incident_photons"], dims, "incident photons", normal=True)
    maps, components = result["active_maps"], result["components"]
    photo_expected = [product(p, mu, "PRNU photo expectation") for p, mu in zip(maps["prnu"], retained_baseline)]
    dark_expected = [product(rate, exposure, "dark expectation") for rate in maps["dark_current_e_per_s"]]
    expected = [checked(p + d, "photo-plus-dark expectation") for p, d in zip(photo_expected, dark_expected)]
    exact_array(observed["expected_photoelectrons"], photo_expected, dims, "PRNU photo expectation")
    exact_array(observed["expected_dark_electrons"], dark_expected, dims, "dark expectation")
    exact_array(observed["expected_electrons"], expected, dims, "total expected electrons")
    photo = sampled_charge(components["photo_electrons"], photo_expected, dims, sensor["shot_noise"], "photo charge")
    dark = sampled_charge(components["dark_electrons"], dark_expected, dims,
                          boolean(model["dark_shot_noise"], "dark shot noise"), "dark charge")
    collected = [checked(p + d, "sampled charge sum") for p, d in zip(photo, dark)]
    stored = [min(v, sensor["full_well_e"]) for v in collected]
    saturated = [v >= sensor["full_well_e"] for v in collected]
    exact_array(observed["collected_electrons"], collected, dims, "sampled photo-plus-dark charge")
    exact_array(observed["charge_electrons"], stored, dims, "one shared physical well")
    exact_array(observed["full_well_saturated"], saturated, dims, "physical saturation", "logical")
    shared = electronics(components["shared"], maps["shared"], 0, dims, "shared")
    shared_read = [checked(s + e, "stored plus shared electronics") for s, e in zip(stored, shared)]
    paths = ("high_gain", "low_gain") if mode == "dual" else ("single",)
    for name in paths:
        path_cfg = cfg[name] if mode == "dual" else sensor
        total = electronics(components[name], maps[name], path_cfg["read_noise_e"], dims, name)
        signed = [checked(s + e, "path signed readout") for s, e in zip(shared_read, total)]
        path = observed[name] if mode == "dual" else observed
        if mode == "dual":
            fields(path, PATH_FIELDS, name + " readout")
        valid = verify_path(path, signed, path_cfg, dims, name)
    if mode == "dual":
        valid = verify_merge(observed["merged"], observed["high_gain"]["raw_dn"], observed["low_gain"]["raw_dn"], cfg, dims)
    exact_array(observed["reconstruction_valid"], [v and not s for v, s in zip(valid, saturated)],
                dims, "physical reconstruction validity", "logical")
    if kind == "spatial_exposure":
        verify_spatial(result, cfg, sensor, axes)
    return {"configuration": cfg, "sensor": sensor, "runtime": engine, "seed": seed, "exposure_s": exposure,
            "random_stream_reproduced": False, "general_format_checked": True,
            "deterministic_arithmetic_checked": True, "spatial_arithmetic_checked": kind == "spatial_exposure"}


def band_major(value):
    """Explicitly adapt typed C order to the earlier verifier's spectral planes."""
    h, w = value.shape[:2]
    bands = value.shape[2] if len(value.shape) == 3 else 1
    return [value[(r * w + c) * bands + band]
            for band in range(bands) for r in range(h) for c in range(w)]


def spatial_grid(value, label):
    fields(value, phase3.GRID_FIELDS, label)
    for key, expected in (("schema_version", "1.0"), ("units", "m"), ("sample_semantics", "cell_average")):
        text(value[key], label + " " + key, expected)
    for key in ("x_edges_m", "y_edges_m"):
        require(isinstance(value[key], Array), label + ": missing typed edges")
        numeric(value[key], (1, len(value[key])), label + " " + key)
    return phase3.grid(plain(value), label)


def _literal_struct(actual, literals, label):
    for key, expected in literals.items():
        text(actual[key], label + "." + key, expected)


def _diagnostic(actual, data, heights, widths, bands, label):
    fields(actual, {"status", "values"}, label)
    h, w = len(heights), len(widths)
    totals, available = [], True
    for k in range(bands):
        terms = []
        for r in range(h):
            for c in range(w):
                area = heights[r] * widths[c]
                incident = data[(k * h + r) * w + c]
                term = incident * area
                if (not math.isfinite(area) or (heights[r] > 0 and widths[c] > 0 and area == 0)
                        or not math.isfinite(term) or (incident > 0 and area > 0 and term == 0)):
                    available = False
                terms.append(term)
        try:
            total = math.fsum(terms)
        except (ValueError, OverflowError):
            total = math.inf
        available &= math.isfinite(total)
        totals.append(total)
    if available:
        text(actual["status"], label + " availability", "available")
        close_array(actual["values"], totals, (1, bands), max(1, h * w * bands), label + " integral")
    else:
        text(actual["status"], label + " availability", "unavailable_numeric_range")
        numeric(actual["values"], (0, 0), label + " unavailable values")


def sampling_report(actual, base, sensor, source_axes, target_axes, data):
    literals = {"schema_version": "1.0", "method": "piecewise_constant_area_overlap",
                "input_units": DENSITY_UNITS, "output_units": DENSITY_UNITS,
                "sample_semantics": "cell_average", "coverage_policy": "require_full_footprint",
                "integral_units": "photons s^-1 nm^-1", "active_cfa_pattern": sensor["cfa_pattern"]}
    fields(actual, {*literals, "source_image_size", "output_image_size", "spectral_plane_count",
        "source_bounds_xy_m", "target_bounds_xy_m", "active_roi", "aligned_copy", "identity",
        "x_weight_nonzeros", "y_weight_nonzeros", "x_max_row_sum_error", "y_max_row_sum_error",
        "represented_pitch_relative_error", "source_integral", "source_crop_integral", "target_integral"},
        "sampling report")
    _literal_struct(actual, literals, "sampling report")
    sx, sy = source_axes
    tx, ty = target_axes
    bands = len(sensor["wavelength_nm"])
    exact_array(actual["source_image_size"], [len(sy) - 1, len(sx) - 1], (1, 2), "sampling source size")
    exact_array(actual["output_image_size"], sensor["image_size"], (1, 2), "sampling output size")
    require(scalar(actual["spectral_plane_count"], "sampling band count", 1, MAX_SAMPLES, True) == bands,
            "Sampling report spectral count disagrees")
    exact_array(actual["source_bounds_xy_m"], [sx[0], sy[0], sx[-1], sy[-1]], (2, 2), "sampling source bounds")
    exact_array(actual["target_bounds_xy_m"], [tx[0], ty[0], tx[-1], ty[-1]], (2, 2), "sampling target bounds")
    require(actual["active_roi"] == base["geometry"]["active_roi"], "Sampling report active ROI disagrees")

    def aligned(source, target):
        try:
            start = source.index(target[0])
        except ValueError:
            return False
        return source[start:start + len(target)] == target

    copied = aligned(sx, tx) and aligned(sy, ty)
    boolean(actual["aligned_copy"], "aligned sampling flag", copied)
    boolean(actual["identity"], "identity sampling flag", copied and sx == tx and sy == ty)
    for axis, source, target in (("x", sx, tx), ("y", sy, ty)):
        weights = phase3.axis_overlaps(source, target)
        nonzeros = len(target) - 1 if copied else sum(len(pieces) for pieces in weights)
        require(scalar(actual[axis + "_weight_nonzeros"], "sampling nonzero weight count", 1,
                       MAX_SAMPLES, True) == nonzeros, "Sampling weight count disagrees")
        # Native axis accumulation is sequential in increasing source order.
        error = 0.0 if copied else max(abs(sum(v for _, v in pieces) - 1) for pieces in weights)
        arithmetic_close(scalar(actual[axis + "_max_row_sum_error"], "sampling weight error", 0),
                         error, len(base["optical_irradiance"]), "sampling weight sum error")
    pitch = sensor["pixel_pitch_m"]
    error = max(abs((b - a) / pitch - 1) for axis in (tx, ty) for a, b in zip(axis, axis[1:]))
    require(scalar(actual["represented_pitch_relative_error"], "represented pitch error", 0) == error,
            "Represented pitch diagnostic disagrees")
    dx, dy = [b - a for a, b in zip(sx, sx[1:])], [b - a for a, b in zip(sy, sy[1:])]
    cdx = [max(0, min(b, tx[-1]) - max(a, tx[0])) for a, b in zip(sx, sx[1:])]
    cdy = [max(0, min(b, ty[-1]) - max(a, ty[0])) for a, b in zip(sy, sy[1:])]
    _diagnostic(actual["source_integral"], data["optical_irradiance"], dy, dx, bands, "source integral")
    _diagnostic(actual["source_crop_integral"], data["optical_irradiance"], cdy, cdx, bands, "source crop integral")
    _diagnostic(actual["target_integral"], data["sampled_irradiance"],
                [b - a for a, b in zip(ty, ty[1:])], [b - a for a, b in zip(tx, tx[1:])],
                bands, "target integral")


def optical_report(actual, psf, input_shape, output_shape):
    literals = {"schema_version": "1.0", "method": "discrete_spectral_convolution",
                "boundary_policy": "valid", "normalization_policy": "validated_unit_sum_no_renormalization",
                "input_units": DENSITY_UNITS, "output_units": DENSITY_UNITS}
    fields(actual, {*literals, "kernel_shape", "origin_rc", "spacing_yx_m", "retained_row_indices",
        "retained_column_indices", "required_halo_top_bottom_left_right", "input_shape", "output_shape",
        "synthetic", "calibrated_alev4"}, "optical report")
    _literal_struct(actual, literals, "optical report")
    boolean(actual["synthetic"], "optical report synthetic", True)
    boolean(actual["calibrated_alev4"], "optical report calibrated", False)
    kh, kw = psf["kernel"].shape[:2]
    kernels = psf["kernel"].shape[2] if len(psf["kernel"].shape) == 3 else 1
    oy, ox = psf["origin_rc"]
    first_y, first_x = kh - oy + 1, kw - ox + 1
    rows = [first_y, first_y + output_shape[0] - 1]
    cols = [first_x, first_x + output_shape[1] - 1]
    for key, expected in (("kernel_shape", [kh, kw, kernels]), ("retained_row_indices", rows),
                          ("retained_column_indices", cols), ("input_shape", input_shape),
                          ("output_shape", output_shape),
                          ("required_halo_top_bottom_left_right", [kh - oy, oy - 1, kw - ox, ox - 1])):
        exact_array(actual[key], expected, (1, len(expected)), "optical report " + key)
    require(actual["origin_rc"] == psf["origin_rc"] and actual["spacing_yx_m"] == psf["spacing_yx_m"],
            "Optical report PSF association disagrees")


def legacy_readout(actual, result, cfg, sensor):
    mode = result["readout_mode"]
    dims = tuple(sensor["image_size"])
    names = BASE_READOUT_FIELDS - {"expected_photoelectrons", "expected_dark_electrons", "reconstruction_valid"}
    fields(actual, names | ({"high_gain", "low_gain", "merged", "reconstruction_valid"} if mode == "dual"
                           else PATH_FIELDS - {"adc_usable"}), "complete legacy spatial readout")
    for key in ("seed", "exposure_s", "expected_incident_photons", "input_units", "spectral_bin_convention"):
        require(actual[key] == result["readout"][key], "Legacy readout association differs from structured exposure")
    require(actual["expected_electrons"] == result["baseline_expected_electrons"],
            "Legacy readout must retain the unmodified spectral baseline expectation")
    collected = sampled_charge(actual["collected_electrons"], actual["expected_electrons"], dims,
                               sensor["shot_noise"], "legacy photo charge")
    stored = [min(v, sensor["full_well_e"]) for v in collected]
    saturated = [v >= sensor["full_well_e"] for v in collected]
    exact_array(actual["charge_electrons"], stored, dims, "legacy physical well")
    exact_array(actual["full_well_saturated"], saturated, dims, "legacy physical saturation", "logical")
    for name in (("high_gain", "low_gain") if mode == "dual" else ("single",)):
        path = actual[name] if mode == "dual" else actual
        path_cfg = cfg[name] if mode == "dual" else sensor
        if mode == "dual":
            fields(path, PATH_FIELDS - {"adc_usable"}, "legacy " + name + " path")
        verify_path(path, stored, path_cfg, dims, "legacy " + name, structured=False,
                    exact_read=path_cfg["read_noise_e"] == 0)
    if mode == "dual":
        valid = verify_merge(actual["merged"], actual["high_gain"]["raw_dn"], actual["low_gain"]["raw_dn"], cfg, dims)
        exact_array(actual["reconstruction_valid"], [v and not s for v, s in zip(valid, saturated)], dims,
                    "legacy reconstruction validity", "logical")


def verify_spatial(result, cfg, sensor, target_axes):
    base = result["spatial_baseline"]
    fields(base, {"schema_version", "readout_mode", "input_stage", "input_irradiance", "input_grid",
        "geometry", "configuration", "psf", "optical_irradiance", "optical_grid", "sampled_irradiance",
        "readout", "operation_order", "spatial_provenance", "optical_report", "sampling_report",
        "synthetic", "calibrated_alev4"}, "complete legacy spatial baseline")
    text(base["schema_version"], "spatial schema", "1.0")
    text(base["readout_mode"], "spatial mode", str(result["readout_mode"]))
    text(result["spatial_baseline_role"], "spatial baseline role", "verification_context_only")
    boolean(base["synthetic"], "spatial synthetic", True)
    boolean(base["calibrated_alev4"], "spatial calibrated", False)
    require(base["geometry"] == result["geometry"] and base["configuration"] == result["configuration"],
            "Spatial baseline geometry/readout binding disagrees")
    stage = text(base["input_stage"], "spatial input stage")
    require(stage in ("pre_psf", "post_optics"), "Unknown spatial input stage")
    input_axes, optical_axes = spatial_grid(base["input_grid"], "input grid"), spatial_grid(base["optical_grid"], "optical grid")
    bands = len(sensor["wavelength_nm"])
    ishape = (len(input_axes[1]) - 1, len(input_axes[0]) - 1, bands)
    oshape = (len(optical_axes[1]) - 1, len(optical_axes[0]) - 1, bands)
    numeric(base["input_irradiance"], ishape, "spatial source irradiance", lower=0)
    numeric(base["optical_irradiance"], oshape, "spatial optical irradiance", lower=0)
    require(base["sampled_irradiance"] == result["input_irradiance"], "Spatial sampled input differs from integrated density")
    require(isinstance(base["spatial_provenance"], dict), "Spatial provenance must be a scalar metadata struct")
    data = {name: band_major(base[name]) for name in ("input_irradiance", "optical_irradiance", "sampled_irradiance")}
    meta = {"input_stage": stage, "input_grid": plain(base["input_grid"]),
            "optical_grid": plain(base["optical_grid"]), "files": {}}
    if stage == "post_optics":
        numeric(base["psf"], (0, 0), "post-optics empty PSF")
        meta["psf"] = []
        fields(base["optical_report"], {"operation", "reason"}, "post-optics report")
        _literal_struct(base["optical_report"], {"operation": "none", "reason": "input_already_post_optics"}, "optical report")
        order = ["area_overlap_average", "spectral_integration", str(result["readout_mode"]) + "_gain_readout"]
    else:
        psf = base["psf"]
        fields(psf, phase3.PSF_FIELDS | {"kernel"}, "canonical spatial PSF")
        for key, expected in (("schema_version", "1.0"), ("boundary_policy", "valid")):
            text(psf[key], "PSF " + key, expected)
        numeric(psf["origin_rc"], (1, 2), "PSF origin")
        numeric(psf["spacing_yx_m"], (1, 2), "PSF spacing")
        kernel = psf["kernel"]
        require(isinstance(kernel, Array) and len(kernel) > 0, "Missing PSF kernel")
        numeric(kernel, kernel.shape, "PSF kernel", lower=0)
        kernels = kernel.shape[2] if len(kernel.shape) == 3 else 1
        numeric(psf["wavelength_nm"], (len(psf["wavelength_nm"]), 1) if len(psf["wavelength_nm"]) else (0, 0),
                "PSF wavelength column")
        meta["psf"] = {key: plain(value) for key, value in psf.items() if key != "kernel"}
        meta["psf"]["parameter_sources"] = sources(psf["parameter_sources"], "PSF sources")
        meta["files"]["psf"] = {"shape": [*kernel.shape[:2], kernels]}
        data["psf"] = band_major(kernel)
        optical_report(base["optical_report"], psf, ishape, oshape)
        order = ["optical_psf", "area_overlap_average", "spectral_integration", str(result["readout_mode"]) + "_gain_readout"]
    cell_text(base["operation_order"], "legacy spatial operation order", order)
    cell_text(result["spatial_operation_order"], "structured spatial operation order", order[:-2] + list(result["operation_order"]))
    phase3.verify_optical(meta, data, input_axes, optical_axes, sensor["wavelength_nm"])
    phase3.verify_sampled(data, optical_axes, target_axes, bands)
    sampling_report(base["sampling_report"], base, sensor, optical_axes, target_axes, data)
    legacy_readout(base["readout"], result, cfg, sensor)


def verify_bundle(directory, expected_commit=None):
    """Return decoded ``result`` plus metadata, scalar config, runtime and files.

    Numeric result leaves are :class:`Array`; ``.shape``, ``.class_name`` and
    C-order ``.values`` remain available to independent callers and tests.
    Cell/Char nodes similarly retain ``.shape``. ``plain(result)`` is useful
    when comparing canonical configuration to the ordinary JSON demo summary.
    """
    directory = directory_path(directory)
    require({path.name for path in directory.iterdir()} == {"structured.json", "data.bin"},
            "Structured bundle must contain exactly structured.json and data.bin")
    paths = [directory / "structured.json", directory / "data.bin"]
    require(len({regular(path) for path in paths}) == 2, "Structured files alias one another")
    directory_before = entry_snapshot(directory, directory=True)
    files_before = [entry_snapshot(path) for path in paths]
    manifest = read_json(paths[0])
    fields(manifest, {"format", "schema_version", "wire_version", "byte_order", "array_order", "synthetic",
        "calibrated_alev4", "authentic_arriraw", "parameter_classification", "provenance", "payload", "result"},
        "structured manifest")
    literals = {"format": FORMAT, "schema_version": "1.0", "wire_version": "typed-tree-v1",
                "byte_order": "little-endian", "array_order": "row-major", "parameter_classification": "assumed"}
    require(all(type(manifest[key]) is str and manifest[key] == value for key, value in literals.items()),
            "Structured manifest format/order/classification disagrees")
    require(manifest["synthetic"] is True and manifest["calibrated_alev4"] is False
            and manifest["authentic_arriraw"] is False, "Manifest synthetic/authenticity flags disagree")
    source = phase3.provenance(manifest["provenance"])
    require(manifest["provenance"]["meaning"] == PROVENANCE_MEANING, "Provenance meaning statement disagrees")
    phase3.expected_revision(source, expected_commit)
    payload = manifest["payload"]
    fields(payload, {"name", "byte_count", "sample_count", "sha256"}, "structured payload descriptor")
    require(payload["name"] == "data.bin" and isinstance(payload["sha256"], str)
            and re.fullmatch(r"[0-9a-f]{64}", payload["sha256"]), "Payload filename/hash is malformed")
    count = integer(payload["byte_count"], "payload byte count", 0, 8 * MAX_SAMPLES)
    integer(payload["sample_count"], "payload sample count", 0, MAX_SAMPLES)
    content = bounded(paths[1], count)
    require(len(content) == count and hashlib.sha256(content).hexdigest() == payload["sha256"],
            "Payload byte count or complete SHA-256 disagrees")
    result = decode_tree(manifest["result"], payload, content)
    validated = validate_result(result)
    directory_path(directory)
    require({path.name for path in directory.iterdir()} == {"structured.json", "data.bin"}
            and entry_snapshot(directory, directory=True) == directory_before
            and [entry_snapshot(path) for path in paths] == files_before,
            "Bundle identity or files changed during semantic validation")
    return {**validated, "metadata": manifest, "result": result, "source": source, "files": paths,
            "input_source_authenticated": False}


EI_POLICY = "metadata_only_no_exposure_or_gain_mapping"
NOISE_SOURCES = ["ASSUMED-P4-" + part for part in
                 ("PRNU", "DARK-RATE", "CHARGE", "OFFSET", "ROW", "COLUMN", "FRAME", "IDENTITY")]
DEMO_UNITS = {"input_irradiance": DENSITY_UNITS, "exposure_s": "s", "charge_and_offsets": "electrons",
    "noise_magnitude": "RMS electrons", "dark_current_e_per_s": "electrons photosite^-1 s^-1",
    "gain_dn_per_e": "DN electron^-1", "black_level_dn": "DN", "prnu": "dimensionless",
    "pixel_pitch_m": "m", "reference_temperature_K": "K"}
SUMMARY_FIELDS = {"schema_version", "phase", "fixture_set_id", "frame_count", "sweeps", "sequences",
    "fixture_checks", "generation_complete", "demo_complete", "export_readback_complete", "synthetic",
    "calibrated_alev4", "authentic_arriraw", "parameter_classification", "reference_temperature_K",
    "temperature_policy", "ei_policy", "reproducibility", "units", "runtime", "provenance", "frames",
    "status", "exported_frame_count", "verified_frame_count", "calibrated", "release_accepted", "completion_scope"}
FRAME_FIELDS = {"name", "bundle_dir", "category", "result_kind", "readout_mode", "input_definition",
    "image_size", "exposure_s", "seed", "component_seeds", "configuration", "geometry", "noise_model",
    "sweep_id", "sweep_index", "electronic_gain_scale", "sequence_id", "sequence_role", "sequence_seed",
    "absolute_frame_index", "frame_seed", "ei_label", "ei_policy", "minimum_expected_e", "maximum_expected_e",
    "sum_expected_e", "coverage", "synthetic", "calibrated_alev4", "parameter_classification",
    "export_complete", "readback_verified"}


def same_plain(actual, expected, label):
    """Exact structural equality without Python's True == 1 type loophole."""
    if isinstance(expected, dict):
        fields(actual, expected, label)
        for key, value in expected.items():
            same_plain(actual[key], value, label + "." + key)
    elif isinstance(expected, list):
        require(isinstance(actual, list) and len(actual) == len(expected), label + ": list shape disagrees")
        for a, b in zip(actual, expected):
            same_plain(a, b, label)
    elif type(expected) is bool:
        require(actual is expected, label + ": boolean declaration disagrees")
    elif type(expected) in (int, float):
        require(number(actual, label) == expected, label + ": numerical association disagrees")
    else:
        require(type(actual) is str and actual == expected, label + ": text association disagrees")


def _matrix_formula(function):
    return [[function(r, c) for c in range(1, 9)] for r in range(1, 7)]


def fixture_spec(name):
    """The documented analytical fixture definition, independent of payloads."""
    require(name in NAMES, "Unknown Phase 4 fixed fixture")
    index = NAMES.index(name)
    crop = name == "spatial_crop_single"
    sequence = index >= 18
    sweep = 8 <= index < 18
    mixed = name == "mixed_dual" or sequence
    mode = "dual" if name in ("shared_row_dual", "path_column_dual", "mixed_dual") or name.startswith("dual_") or sequence else "single"
    sensor = {"schema_version": "1.0", "image_size": [4, 5] if crop else [6, 8], "wavelength_nm": 550,
        "bin_width_nm": 10, "qe": [1, 1, 1], "pixel_pitch_m": 6e-6, "fill_factor": 1, "full_well_e": 3000,
        "read_noise_e": .75 if name == "dark_noisy" else 0, "gain_dn_per_e": 1, "black_level_dn": 32,
        "adc_bits": 10, "cfa_pattern": "BGGR" if crop else "RGGB", "shot_noise": mixed}
    scales = {"single_gain_low": .25, "single_gain_high": 2, "dual_gain_low": 1, "dual_gain_high": 4}
    scale = scales.get(name, 1)
    if mode == "dual":
        sensor.update(read_noise_e=3, gain_dn_per_e=.5, black_level_dn=64, adc_bits=16)
        config = {"schema_version": "2.0", "sensor": sensor,
            "high_gain": {"gain_dn_per_e": 4 * scale, "read_noise_e": .6 if mixed else 0,
                          "black_level_dn": 64, "adc_bits": 12},
            "low_gain": {"gain_dn_per_e": .5 * scale, "read_noise_e": 1.2 if mixed else 0,
                         "black_level_dn": 64, "adc_bits": 12},
            "merge": {"start_e": 600 / scale, "end_e": 900 / scale}}
    else:
        sensor["gain_dn_per_e"] *= scale
        config = sensor
    geom = {"schema_version": "1.0", "full_grid_size": [6, 8], "active_roi": [2, 2, 4, 5] if crop else [1, 1, 6, 8],
        "pixel_pitch_m": 6e-6, "origin_xy_m": [0, 0], "full_grid_cfa_pattern": "RGGB",
        "parameter_sources": ["ASSUMED-GENERIC-GEOMETRY", "ASSUMED-CFA-ORIGIN"]}
    model = {"schema_version": "1.0", "enabled": True, "full_grid_size": [6, 8],
        "realization_id": "ASSUMED-P4-DEMO-MAPS-v1", "reference_temperature_K": 293.15,
        "prnu": 1, "dark_current_e_per_s": 0, "dark_shot_noise": False,
        **{path: {"fixed_offset_e": 0, "row_noise_e": 0, "column_noise_e": 0, "frame_noise_e": 0} for path in PATH_NAMES},
        "parameter_sources": NOISE_SOURCES}
    fixed = name in ("deterministic_prnu_offsets", "dark_short", "dark_long", "dark_noisy", "spatial_crop_single") or mixed
    if fixed:
        model["prnu"] = _matrix_formula(lambda r, c: 1 + .01 * (r - 3.5) + .005 * (c - 4.5))
        for path, formula in (("shared", lambda r, c: 2 * (r - 3.5) + (c - 4.5)),
                              ("single", lambda r, c: .25 * (r - c)),
                              ("high_gain", lambda r, c: .5 * r - .25 * c),
                              ("low_gain", lambda r, c: -.25 * r + .5 * c)):
            model[path]["fixed_offset_e"] = _matrix_formula(formula)
    if name.startswith("dark_") or mixed:
        model["realization_id"] = "ASSUMED-P4-DEMO-DARK-v1"
        model["dark_current_e_per_s"] = _matrix_formula(lambda r, c: 2 + .5 * r + .25 * c)
    if name == "dark_noisy":
        model["dark_shot_noise"] = True
        model["shared"]["row_noise_e"] = .5
        model["single"].update(column_noise_e=.25, frame_noise_e=.4)
    if name == "shared_row_dual":
        model["realization_id"] = "ASSUMED-P4-DEMO-SHARED-ROW-v1"
        model["shared"]["row_noise_e"] = 6
    if name == "path_column_dual":
        model["realization_id"] = "ASSUMED-P4-DEMO-PATH-COLUMN-v1"
        model["high_gain"]["column_noise_e"], model["low_gain"]["column_noise_e"] = 4, 7
    if mixed:
        model["realization_id"] = "ASSUMED-P4-DEMO-MIXED-v1"
        model["dark_shot_noise"] = True
        for path, terms in (("shared", (1.5, .75, .5)), ("high_gain", (.8, 1.25, .3)), ("low_gain", (1.1, 2, .4))):
            model[path].update(zip(("row_noise_e", "column_noise_e", "frame_noise_e"), terms))
    if sweep:
        model["realization_id"] = "ASSUMED-P4-DEMO-SWEEP-v1"
        model["shared"]["fixed_offset_e"] = _matrix_formula(lambda r, c: -256 if c == 1 else 0)
    rate_profile = (0, 4000, 12000, 24000, 40000, 70000, 120000, 220000)
    if name.startswith("dark_"):
        rate = lambda r, c: 0
        definition = "zero_irradiance"
    elif name in ("shared_row_dual", "path_column_dual"):
        rate = lambda r, c: 50000
        definition = "flat_50000_e_per_s"
    elif sweep:
        rate = lambda r, c: rate_profile[c - 1]
        definition = "eight_column_photo_rate_e_per_s"
    else:
        rate = lambda r, c: 10000 + 250 * r + 500 * c
        definition = "affine_photo_rate_e_per_s"
    density = _matrix_formula(lambda r, c: rate(r, c) / ((6e-6)**2 * 10))
    exposure = .01
    seed = 94001 + index
    category = "fixed_maps" if index == 0 else "dark" if 1 <= index <= 3 else "structured_dual" if 4 <= index <= 6 else "spatial"
    if name == "dark_short":
        exposure = .02
    elif name in ("dark_long", "dark_noisy"):
        exposure = 2
    sweep_id, sweep_index = "", 0
    sequence_role, sequence_index, sequence_seed, ei = "", [], [], []
    if 8 <= index < 14:
        exposure = (0, .01, .1)[(index - 8) % 3]
        seed = 94100 if mode == "single" else 94200
        category, sweep_id, sweep_index = "exposure_sweep", mode + "_exposure", (index - 8) % 3 + 1
    elif 14 <= index < 18:
        seed = 94300 if mode == "single" else 94400
        category, sweep_id, sweep_index = "electronic_gain_sweep", mode + "_electronic_gain", (index - 14) % 2 + 1
    elif sequence:
        sequence_role = "primary" if index < 21 else "reset" if index == 21 else "continue"
        sequence_index = (1, 2, 3, 1, 2, 3)[index - 18]
        sequence_seed, ei = 4294967200, (800, 800, 800, 200, 1600, 3200)[index - 18]
        seed = (sequence_seed + 64 * (sequence_index - 1)) % 2**32
        exposure, category = .02, "independent_frame_sequence"
    return {"configuration": config, "geometry": geom, "noise_model": model, "density": density,
        "category": category, "input_definition": definition, "exposure_s": exposure, "seed": seed,
        "mode": mode, "sweep_id": sweep_id, "sweep_index": sweep_index, "scale": scale,
        "sequence_role": sequence_role, "absolute_frame_index": sequence_index,
        "sequence_seed": sequence_seed, "ei_label": ei}


def verify_fixture(bundle, name):
    spec = fixture_spec(name)
    result = bundle["result"]
    for key in ("configuration", "geometry", "noise_model"):
        same_plain(plain(result[key]), spec[key], name + " analytical " + key)
    require(bundle["seed"] == spec["seed"] and bundle["exposure_s"] == spec["exposure_s"]
            and result["readout_mode"] == spec["mode"], name + ": fixed seed/exposure/mode disagrees")
    crop = name == "spatial_crop_single"
    text(result["result_kind"], name + " result kind", "spatial_exposure" if crop else "exposure")
    expected = [v for row in spec["density"] for v in row]
    if crop:
        exact_array(result["spatial_baseline"]["input_irradiance"], expected, (6, 8), name + " analytical spatial input")
        same_plain(plain(result["spatial_baseline"]["input_grid"]), {"schema_version": "1.0",
            "x_edges_m": [i * 6e-6 for i in range(9)], "y_edges_m": [i * 6e-6 for i in range(7)],
            "units": "m", "sample_semantics": "cell_average"}, name + " analytical grid")
        text(result["spatial_baseline"]["input_stage"], name + " input stage", "post_optics")
        fields(result["spatial_baseline"]["spatial_provenance"], set(), name + " spatial provenance")
        expected = [spec["density"][r][c] for r in range(1, 5) for c in range(1, 6)]
    exact_array(result["input_irradiance"], expected, (4, 5) if crop else (6, 8), name + " analytical input density")
    return spec


def coverage(result):
    readout = result["readout"]
    counts = {"physical_saturation_pixels": sum(readout["full_well_saturated"]),
        "single_adc_low_clipped_pixels": 0, "single_adc_high_clipped_pixels": 0,
        "high_adc_low_clipped_pixels": 0, "high_adc_high_clipped_pixels": 0,
        "low_adc_low_clipped_pixels": 0, "low_adc_high_clipped_pixels": 0,
        "high_clipped_low_usable_pixels": 0, "merge_transition_pixels": 0,
        "low_high_clipped_before_well_pixels": 0, "reconstruction_valid_pixels": sum(readout["reconstruction_valid"])}
    if result["readout_mode"] == "single":
        counts["single_adc_low_clipped_pixels"] = sum(readout["adc_low_clipped"])
        counts["single_adc_high_clipped_pixels"] = sum(readout["adc_high_clipped"])
    else:
        for short, name in (("high", "high_gain"), ("low", "low_gain")):
            for side in ("low", "high"):
                counts[short + "_adc_" + side + "_clipped_pixels"] = sum(readout[name]["adc_" + side + "_clipped"])
        counts["high_clipped_low_usable_pixels"] = sum(bool(h and l and not s) for h, l, s in zip(
            readout["high_gain"]["adc_high_clipped"], readout["low_gain"]["adc_usable"], readout["full_well_saturated"]))
        counts["merge_transition_pixels"] = sum(0 < v < 1 for v in readout["merged"]["weight_high"])
        counts["low_high_clipped_before_well_pixels"] = sum(bool(l and not s) for l, s in zip(
            readout["low_gain"]["adc_high_clipped"], readout["full_well_saturated"]))
    return counts


def verify_sweeps(actual, specs):
    require(isinstance(actual, list) and len(actual) == 4, "Exactly four exposure/electronic-gain sweeps are required")
    for observed, (name, names) in zip(actual, (("single_exposure", NAMES[8:11]), ("dual_exposure", NAMES[11:14]),
            ("single_electronic_gain", NAMES[14:16]), ("dual_electronic_gain", NAMES[16:18]))):
        mode = specs[names[0]]["mode"]
        expected = {"name": name, "variable": "physical_exposure_s" if "exposure" in name else "electronic_gain_scale",
            "readout_mode": mode, "fixture_names": list(names), "exposures_s": [specs[n]["exposure_s"] for n in names],
            "frame_seeds": [specs[n]["seed"] for n in names], "electronic_gain_scales": [specs[n]["scale"] for n in names],
            "single_gain_dn_per_e": [], "high_gain_dn_per_e": [], "low_gain_dn_per_e": [],
            "merge_start_e": [], "merge_end_e": [], "ei_policy": EI_POLICY}
        if mode == "single":
            expected["single_gain_dn_per_e"] = [specs[n]["configuration"]["gain_dn_per_e"] for n in names]
        else:
            for path in ("high_gain", "low_gain"):
                expected[path + "_dn_per_e"] = [specs[n]["configuration"][path]["gain_dn_per_e"] for n in names]
            for key in ("start_e", "end_e"):
                expected["merge_" + key] = [specs[n]["configuration"]["merge"][key] for n in names]
        same_plain(observed, expected, name + " sweep")


def verify_sequences(actual, specs, bundles):
    require(isinstance(actual, list) and len(actual) == 3, "Exactly primary/reset/continuation sequence records are required")
    for observed, role, names in zip(actual, ("primary", "reset", "continue"), (NAMES[18:21], NAMES[21:22], NAMES[22:24])):
        indices = [specs[n]["absolute_frame_index"] for n in names]
        primary = [f"sequence_primary_{i:03d}" for i in indices]
        expected = {"sequence_id": "ASSUMED-P4-DEMO-SEQUENCE-v1", "role": role,
            "fixture_names": list(names), "matches_primary_names": primary, "sequence_seed": 4294967200,
            "frame_indices": indices, "frame_seeds": [specs[n]["seed"] for n in names],
            "exposures_s": [specs[n]["exposure_s"] for n in names], "ei_label": [specs[n]["ei_label"] for n in names],
            "temporal_policy": "independent_frames", "continuation_policy": "pure_function_of_arguments_and_absolute_frame_indices",
            "ei_policy": EI_POLICY, "seed_schedule": {"stride": 64, "modulus": 4294967296,
                "minimum_frame_index": 1, "maximum_frame_index": 67108864,
                "expression": "mod(sequence_seed + 64*(absolute_frame_index-1), 2^32)"},
            "rng_generator": "twister", "reproducibility": "same_runtime_and_version_only"}
        if len(names) == 1:
            for key in ("frame_indices", "frame_seeds", "exposures_s", "ei_label"):
                expected[key] = expected[key][0]
        same_plain(observed, expected, role + " sequence metadata")
        for name, original in zip(names, primary):
            require(bundles[name]["result"] == bundles[original]["result"],
                    "Sequence reset/continuation or EI label changed the complete matching frame physics")


def verify_demo(directory, source=None, engine=None):
    directory = directory_path(directory)
    summary_path = directory / "phase4-demo-summary.json"
    summary = read_json(summary_path)
    fields(summary, SUMMARY_FIELDS, "Phase 4 demo summary")
    declarations = {"schema_version": "1.0", "phase": 4, "fixture_set_id": "ASSUMED-P4-DEMO-v1",
        "frame_count": 24, "generation_complete": True, "demo_complete": True, "export_readback_complete": True,
        "synthetic": True, "calibrated_alev4": False, "authentic_arriraw": False, "parameter_classification": "assumed",
        "reference_temperature_K": 293.15, "temperature_policy": "declared applicability only; no temperature law",
        "ei_policy": EI_POLICY, "reproducibility": "same_runtime_and_version_only", "units": DEMO_UNITS,
        "status": "complete", "exported_frame_count": 24, "verified_frame_count": 24, "calibrated": False,
        "release_accepted": False, "completion_scope": "all_24_fixture_exports_and_native_readbacks"}
    for key, value in declarations.items():
        same_plain(summary[key], value, "demo " + key)
    observed_source = phase3.provenance(summary["provenance"], complete=True)
    require(summary["provenance"]["meaning"] == PROVENANCE_MEANING, "Demo provenance meaning disagrees")
    observed_engine = phase3.runtime(summary["runtime"])
    require((source is None or observed_source == source) and (engine is None or observed_engine == engine),
            "Demo source/runtime differs from numerical evidence")
    source, engine = observed_source, observed_engine
    records = summary["frames"]
    require(isinstance(records, list) and len(records) == 24 and all(isinstance(item, dict) for item in records)
            and [item.get("name") for item in records] == list(NAMES), "Frozen 24-frame inventory/order disagrees")
    require({p.name for p in directory.iterdir()} == {"phase4-demo-summary.json", *NAMES}, "Demo has missing/extra entries")
    files, metrics, bundles, specs = [summary_path], {}, {}, {}
    for record, name in zip(records, NAMES):
        fields(record, FRAME_FIELDS, name + " summary record")
        bundle = verify_bundle(directory / name)
        require(bundle["source"] == source and bundle["runtime"] == engine
                and bundle["metadata"]["provenance"] == summary["provenance"], name + ": source/runtime association differs")
        spec = verify_fixture(bundle, name)
        bundles[name], specs[name] = bundle, spec
        result, values = bundle["result"], bundle["result"]["readout"]["expected_electrons"]
        recorded = {"name": name, "bundle_dir": name, "category": spec["category"],
            "result_kind": str(result["result_kind"]), "readout_mode": spec["mode"],
            "input_definition": spec["input_definition"], "image_size": bundle["sensor"]["image_size"],
            "exposure_s": spec["exposure_s"], "seed": spec["seed"], "component_seeds": plain(result["seeds"]),
            "configuration": plain(result["configuration"]), "geometry": plain(result["geometry"]),
            "noise_model": plain(result["noise_model"]), "sweep_id": spec["sweep_id"],
            "sweep_index": spec["sweep_index"], "electronic_gain_scale": spec["scale"],
            "sequence_id": "ASSUMED-P4-DEMO-SEQUENCE-v1" if spec["sequence_role"] else "",
            "sequence_role": spec["sequence_role"], "sequence_seed": spec["sequence_seed"],
            "absolute_frame_index": spec["absolute_frame_index"], "frame_seed": spec["seed"], "ei_label": spec["ei_label"],
            "ei_policy": EI_POLICY, "coverage": coverage(result), "synthetic": True, "calibrated_alev4": False,
            "parameter_classification": "assumed", "export_complete": True, "readback_verified": True}
        for key, expected in recorded.items():
            same_plain(record[key], expected, name + " summary " + key)
        calculations = {"minimum_expected_e": min(values), "maximum_expected_e": max(values),
                        "sum_expected_e": math.fsum(values)}
        for key, expected in calculations.items():
            arithmetic_close(record[key], expected, len(values) if key.startswith("sum") else 1, name + " " + key)
        metrics[name] = {**calculations, "coverage": recorded["coverage"], "seed": spec["seed"],
            "exposure_s": spec["exposure_s"], "readout_mode": spec["mode"], "demo_fixture_checked": True,
            "spatial_arithmetic_checked": bundle["spatial_arithmetic_checked"]}
        files.extend(bundle["files"])
    verify_sweeps(summary["sweeps"], specs)
    verify_sequences(summary["sequences"], specs, bundles)
    counts = {name: metrics[name]["coverage"] for name in NAMES}
    actual_checks = {"exact_frame_count": len(bundles) == 24, "unique_fixed_names": len(set(bundles)) == 24,
        "single_lower_adc_clip": counts[NAMES[8]]["single_adc_low_clipped_pixels"] > 0,
        "single_upper_adc_clip": counts[NAMES[9]]["single_adc_high_clipped_pixels"] > 0,
        "single_physical_saturation": counts[NAMES[10]]["physical_saturation_pixels"] > 0,
        "dual_lower_adc_clips": counts[NAMES[11]]["high_adc_low_clipped_pixels"] > 0 and counts[NAMES[11]]["low_adc_low_clipped_pixels"] > 0,
        "dual_high_clip_low_usable": counts[NAMES[12]]["high_clipped_low_usable_pixels"] > 0,
        "dual_merge_transition": counts[NAMES[12]]["merge_transition_pixels"] > 0,
        "dual_physical_saturation": counts[NAMES[13]]["physical_saturation_pixels"] > 0,
        "dual_low_upper_clip_before_well": counts[NAMES[17]]["low_high_clipped_before_well_pixels"] > 0,
        "fixed_maps_crop_identity": bundles[NAMES[0]]["result"]["noise_model"] == bundles[NAMES[7]]["result"]["noise_model"],
        "sequence_seed_wrap": [bundles[n]["seed"] for n in NAMES[18:21]] == [4294967200, 4294967264, 32],
        "sequence_reset_exact": bundles[NAMES[18]]["result"] == bundles[NAMES[21]]["result"],
        "sequence_continuation_exact": bundles[NAMES[19]]["result"] == bundles[NAMES[22]]["result"]
            and bundles[NAMES[20]]["result"] == bundles[NAMES[23]]["result"],
        "ei_labels_changed_without_physics": all(specs[a]["ei_label"] != specs[b]["ei_label"]
            and bundles[a]["result"] == bundles[b]["result"] for a, b in zip(NAMES[18:21], NAMES[21:24]))}
    require(all(actual_checks.values()), "Independently calculated demo coverage/equality requirement failed")
    same_plain(summary["fixture_checks"], actual_checks, "independent demo coverage checks")
    require(len(files) == 49 and len({regular(path) for path in files}) == 49,
            "Demo files are missing or aliased across bundles")
    return files, metrics


def check_numerical_report(report, expected_commit=None):
    require(isinstance(report, dict) and report.get("schema_version") == "1.0"
            and integer(report.get("phase"), "numerical phase", 4, 4) == 4 and report.get("status") == "passed"
            and report.get("phase4_passed") is True and report.get("phase3_required") is True
            and report.get("calibrated_alev4") is False,
            "Complete executed Phase 4 numerical evidence requiring Phase 3/2/1 is required")
    source = phase3.provenance(report.get("provenance"), complete=True)
    engine = phase3.runtime({"name": report.get("runtime"), "version": report.get("runtime_version")})
    phase3.expected_revision(source, expected_commit)
    require(all(source[key] == value for key, value in phase3.PINNED_HEADS.items()),
            "Phase 4 numerical report does not identify the frozen dependency pins")
    groups = sum(phase3._suite(report, name) for name in GATES)
    previous = report.get("phase3")
    require(isinstance(previous, dict), "Complete Phase 3 numerical prerequisite is missing")
    previous_source, previous_engine, previous_groups, phase2_groups, _ = phase3.check_numerical_report(previous, expected_commit)
    require(source == previous_source and engine == previous_engine, "Earlier phase numerical source/runtime differs")
    return source, engine, groups, previous_groups, phase2_groups


def digest(path):
    return hashlib.sha256(bounded(path, 8 * MAX_SAMPLES)).hexdigest()


def verify_outputs(output_root, expected_commit=None, compare_dir=None):
    root = directory_path(output_root)
    validation = directory_path(root / "validation")
    report_path = validation / "phase4-validation.json"
    source, engine, groups, phase3_groups, phase2_groups = check_numerical_report(read_json(report_path), expected_commit)
    demo = root / "demo"
    files, metrics = verify_demo(demo, source, engine)
    hashes = {path.relative_to(demo).as_posix(): digest(path) for path in files}
    if compare_dir is not None:
        comparison = directory_path(compare_dir)
        require(comparison.resolve() != demo.resolve(), "Comparison requires a distinct resolved directory")
        other, _ = verify_demo(comparison, source, engine)
        require({regular(path) for path in files}.isdisjoint({regular(path) for path in other}),
                "Repeated demo aliases primary artifacts, including cross-filename aliases")
        counterparts = {path.relative_to(comparison).as_posix(): path for path in other}
        require(set(counterparts) == set(hashes), "Repeated demo artifact inventory differs")
        require(all(digest(counterparts[name]) == value for name, value in hashes.items()),
                "Fresh-directory repeat is not byte-identical")
    return {"status": "passed", "phase": 4, "frame_count": 24, "artifact_count": 49,
        "numerical_test_groups": groups, "phase3_numerical_test_groups": phase3_groups,
        "phase2_numerical_test_groups": phase2_groups, "phase3_phase2_phase1_prerequisites_checked": True,
        "source": source, "runtime": {"name": engine[0], "version": engine[1]}, "frames": metrics,
        "artifact_sha256": hashes, "numerical_report_sha256": digest(report_path),
        "compared_demo_byte_identical": compare_dir is not None, "general_format_checked": True,
        "deterministic_arithmetic_checked": True, "demo_fixtures_checked": True,
        "sweeps_and_sequence_metadata_checked": True, "input_source_authenticated": False,
        "random_stream_reproduced": False, "calibrated_alev4": False,
        "verification_boundary": "Typed bytes, fixed-map crops, spectral/spatial arithmetic, recorded component assembly, "
            "single physical well, signed electronics, ADC and observed-channel merge independently checked. "
            "Recorded random draws have finite/support/zero-noise checks only; Python does not authenticate PRNG origin, "
            "random distribution, numerical execution, source cleanliness, or process independence."}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output_root", type=Path, nargs="?", default=Path("outputs/phase4"))
    parser.add_argument("--expected-commit")
    parser.add_argument("--compare-dir", type=Path)
    args = parser.parse_args(argv)
    try:
        result = verify_outputs(args.output_root, args.expected_commit, args.compare_dir)
    except (ArtifactError, OSError, TypeError, KeyError, OverflowError, RecursionError, ValueError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
