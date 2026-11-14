#!/usr/bin/env python3
"""Independently validate Phase 2 reports and synthetic dual-gain bundles.

The verifier uses only the Python standard library. It decodes actual payload
bytes, reconstructs the merge from observed ADC planes, checks the fixed demo
fixtures against independent arithmetic, and optionally compares a second demo
from a distinct directory. It neither reproduces a runtime's random stream nor
establishes ALEV4 calibration or the unrecorded analog history of noisy samples.

Usage: python3 scripts/verify_phase2_artifacts.py outputs/phase2
       --expected-commit SHA --compare-dir outputs/phase2/demo-repeat
"""
from __future__ import annotations

import argparse
import array
import hashlib
import json
import math
import re
import sys
from pathlib import Path

MAX_JSON = 2_000_000
MAX_PIXELS = 100_000_000
SHA_FIELDS = ("repository_head", "isetcam_head", "isethdrsensor_head")
NAMES = ("dark", "shadow", "transition", "highlight", "saturation", "noisy")
GATES = ("core", "config_edges", "noise", "raw_io", "numerical_edges",
         "spectral_properties", "demo_contract")
PHASE1_GATES = ("core", "config_edges", "spectral_properties", "input_representation",
                "fixture_edges", "numerical_edges", "poisson_edges", "raw_io",
                "demo_contract", "provenance_tests", "iset")
PAYLOADS = {"high_raw": ".high.raw", "low_raw": ".low.raw",
            "merged_electrons": ".merged.f64", "flags": ".flags.u8"}
UNITS = {"high_raw": "DN", "low_raw": "DN", "merged_electrons": "electrons",
         "flags": "bitmask"}
SENSOR_FIELDS = {"schema_version", "image_size", "wavelength_nm", "bin_width_nm",
                 "qe", "pixel_pitch_m", "fill_factor", "full_well_e", "read_noise_e",
                 "gain_dn_per_e", "black_level_dn", "adc_bits", "cfa_pattern", "shot_noise"}
PATH_FIELDS = {"gain_dn_per_e", "read_noise_e", "black_level_dn", "adc_bits"}


class ArtifactError(ValueError):
    """Evidence does not satisfy the recorded Phase 2 artifact contract."""


def require(condition, message):
    if not condition:
        raise ArtifactError(message)


def number(value, label, lower=-math.inf, upper=math.inf):
    require(type(value) in (int, float), f"{label}: expected a number, not a boolean")
    try:
        result = float(value)
    except (OverflowError, ValueError) as exc:
        raise ArtifactError(f"{label}: numeric overflow") from exc
    require(math.isfinite(result) and lower <= result <= upper, f"{label}: invalid numeric range")
    return result


def integer(value, label, lower=0, upper=MAX_PIXELS):
    value = number(value, label, lower, upper)
    require(value.is_integer(), f"{label}: expected an integer")
    return int(value)


def close(value, expected, label, *, rel_tol=1e-10, abs_tol=1e-10):
    value = number(value, label)
    require(math.isclose(value, expected, rel_tol=rel_tol, abs_tol=abs_tol),
            f"{label}: independently calculated value disagrees")


def bounded(path, maximum):
    path = Path(path)
    require(not path.is_symlink() and path.is_file(), f"Missing or symlink artifact: {path.name}")
    with path.open("rb") as handle:
        content = handle.read(maximum + 1)
    require(len(content) <= maximum, f"Oversized artifact: {path.name}")
    return content


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"Duplicate JSON field: {key}")
        result[key] = value
    return result


def finite_json_float(text):
    value = float(text)
    require(math.isfinite(value), "Nonfinite JSON numeric value")
    return value


def reject_constant(text):
    raise ArtifactError(f"Nonfinite JSON constant: {text}")


def read_json(path):
    try:
        result = json.loads(bounded(path, MAX_JSON).decode("utf-8"),
                            object_pairs_hook=unique_pairs,
                            parse_float=finite_json_float,
                            parse_constant=reject_constant)
    except (UnicodeError, json.JSONDecodeError, RecursionError, ValueError) as exc:
        if isinstance(exc, ArtifactError):
            raise
        raise ArtifactError(f"Invalid JSON: {Path(path).name}") from exc
    require(isinstance(result, dict), f"JSON object required: {Path(path).name}")
    return result


def safe_file(directory, name, expected=None):
    require(isinstance(name, str) and name not in ("", ".", "..")
            and not any(character in name for character in ("/", "\\", ":"))
            and not any(ord(character) < 32 for character in name),
            "Unsafe artifact filename")
    if expected is not None:
        require(name == expected, "Artifact basename association disagrees")
    directory = Path(directory)
    path = directory / name
    require(not path.is_symlink(), "Symlink artifact is unsupported")
    require(path.resolve().parent == directory.resolve() and path.is_file(),
            f"Missing or escaped artifact: {name}")
    return path


def provenance(value):
    require(isinstance(value, dict), "Missing source provenance")
    for field in SHA_FIELDS:
        require(isinstance(value.get(field), str)
                and re.fullmatch(r"[0-9a-f]{40}", value[field]) is not None,
                f"Missing or malformed observed {field}")
    require(isinstance(value.get("meaning"), str) and value["meaning"].strip(),
            "Missing provenance meaning")
    return {field: value[field] for field in SHA_FIELDS}


def runtime(value):
    require(isinstance(value, dict) and value.get("name") in ("GNU Octave", "MATLAB"),
            "Missing or unknown runtime")
    require(isinstance(value.get("version"), str) and value["version"].strip(),
            "Missing runtime version")
    return value["name"], value["version"]


def shape(value):
    require(isinstance(value, list) and len(value) == 2, "Invalid image_size")
    result = [integer(item, "image dimension", 1) for item in value]
    require(result[0] * result[1] <= MAX_PIXELS, "Pixel limit exceeded")
    return result


def vector(value, label):
    values = value if isinstance(value, list) else [value]
    require(len(values) > 0, f"{label}: empty vector")
    return [number(item, label, 0) for item in values]


def sensor_config(value):
    require(isinstance(value, dict) and set(value) == SENSOR_FIELDS,
            "Incomplete or unknown shared sensor configuration fields")
    require(value["schema_version"] == "1.0", "Invalid shared sensor schema")
    dimensions = shape(value["image_size"])
    wave = vector(value["wavelength_nm"], "wavelength")
    widths = vector(value["bin_width_nm"], "spectral bin width")
    require(len(wave) == len(widths), "Spectral vector lengths disagree")
    previous_upper = None
    for index, (center, width) in enumerate(zip(wave, widths)):
        lower, upper = center - width / 2, center + width / 2
        require(center > 0 and width > 0 and lower > 0 and math.isfinite(upper),
                "Invalid spectral bin edges")
        if index:
            tolerance = 8 * max(math.ulp(previous_upper), math.ulp(lower))
            require(center > wave[index - 1] and previous_upper - lower <= tolerance,
                    "Unordered or overlapping spectral bins")
        previous_upper = upper
    qe = value["qe"]
    if len(wave) == 1 and isinstance(qe, list) and len(qe) == 3 and not isinstance(qe[0], list):
        qe = [qe]
    require(isinstance(qe, list) and len(qe) == len(wave), "QE spectral length disagrees")
    normalized_qe = []
    for row in qe:
        require(isinstance(row, list) and len(row) == 3, "QE requires RGB columns")
        normalized_qe.append([number(item, "QE", 0, 1) for item in row])
    pitch = number(value["pixel_pitch_m"], "pixel pitch", 0)
    require(0 < pitch * pitch < math.inf, "Unrepresentable pixel area")
    number(value["fill_factor"], "fill factor", 0, 1)
    require(number(value["full_well_e"], "full well", 0) > 0, "Full well must be positive")
    for field, canonical in (("read_noise_e", 3), ("gain_dn_per_e", 0.5),
                             ("black_level_dn", 64), ("adc_bits", 16)):
        require(number(value[field], f"shared {field}") == canonical,
                "Noncanonical shared electronics would be ambiguous")
    require(value["cfa_pattern"] in ("RGGB", "BGGR", "GRBG", "GBRG")
            and type(value["shot_noise"]) is bool, "Invalid CFA or shot-noise setting")
    return {**value, "image_size": dimensions, "wavelength_nm": wave,
            "bin_width_nm": widths, "qe": normalized_qe}


def path_config(value, label):
    require(isinstance(value, dict) and set(value) == PATH_FIELDS,
            f"Incomplete or unknown {label} configuration fields")
    gain = number(value["gain_dn_per_e"], f"{label} gain", 0)
    noise = number(value["read_noise_e"], f"{label} read noise", 0)
    bits = integer(value["adc_bits"], f"{label} ADC bits", 2, 16)
    black = number(value["black_level_dn"], f"{label} black level", 0, 2**bits - 1)
    require(gain > 0, f"{label}: gain must be positive")
    headroom = (2**bits - 1 - black) / gain
    interior = (2**bits - 2 - black) / gain
    minimum = -black / gain
    require(headroom > 0 and all(math.isfinite(item) for item in (headroom, interior, minimum)),
            f"{label}: invalid reconstruction limits")
    return {"gain_dn_per_e": gain, "read_noise_e": noise, "black_level_dn": black,
            "adc_bits": bits}, headroom, interior


def config(value):
    require(isinstance(value, dict) and set(value) == {
        "schema_version", "sensor", "high_gain", "low_gain", "merge"},
        "Incomplete or unknown dual-gain configuration fields")
    require(value["schema_version"] == "2.0", "Invalid dual-gain schema")
    sensor = sensor_config(value["sensor"])
    high, high_headroom, interior = path_config(value["high_gain"], "high gain")
    low, low_headroom, _ = path_config(value["low_gain"], "low gain")
    require(high["gain_dn_per_e"] > low["gain_dn_per_e"] and low_headroom > high_headroom,
            "Gain ordering or low-gain headroom is invalid")
    merge = value["merge"]
    require(isinstance(merge, dict) and set(merge) == {"start_e", "end_e"},
            "Incomplete or unknown merge fields")
    start = number(merge["start_e"], "merge start", 0)
    end = number(merge["end_e"], "merge end", 0)
    require(start < end < min(sensor["full_well_e"], interior),
            "Merge interval exceeds usable high-path or physical range")
    # The observed low channel may lag the true charge by half its ADC step.
    # Finish its crossfade before the high path can round to its upper rail.
    # Subtraction avoids overflowing an otherwise representable comparison.
    high_first_rail_e = (2**high["adc_bits"] - 1 - 0.5 - high["black_level_dn"]) / high["gain_dn_per_e"]
    low_half_step_e = 0.5 / low["gain_dn_per_e"]
    safe_limit = high_first_rail_e - low_half_step_e
    safety = 8 * max(math.ulp(high_first_rail_e), math.ulp(low_half_step_e))
    require(math.isfinite(safe_limit) and safe_limit > 0 and end <= safe_limit - safety,
            "Merge interval lacks low-path quantization margin before the high ADC rail")
    return {"schema_version": "2.0", "sensor": sensor, "high_gain": high,
            "low_gain": low, "merge": {"start_e": start, "end_e": end}}


def decode(path, kind, count):
    sizes = {"H": 2, "d": 8, "B": 1}
    content = bounded(path, count * sizes[kind])
    require(len(content) == count * sizes[kind], f"Truncated payload: {Path(path).name}")
    values = array.array(kind)
    require(values.itemsize == sizes[kind], "Required binary sample representation unavailable")
    values.frombytes(content)
    if sys.byteorder != "little" and sizes[kind] > 1:
        values.byteswap()
    return values


def merge_sample(high_dn, low_dn, cfg):
    """Independent scalar implementation of the observable merge contract."""
    high, low = cfg["high_gain"], cfg["low_gain"]
    high_e = (high_dn - high["black_level_dn"]) / high["gain_dn_per_e"]
    low_e = (low_dn - low["black_level_dn"]) / low["gain_dn_per_e"]
    high_usable = 0 < high_dn < 2**high["adc_bits"] - 1
    low_usable = 0 < low_dn < 2**low["adc_bits"] - 1
    start, end = cfg["merge"]["start_e"], cfg["merge"]["end_e"]
    if low_e <= start:
        weight = 1.0
    elif low_e >= end:
        weight = 0.0
    else:
        fraction = (low_e - start) / (end - start)
        weight = 1 - fraction * fraction * (3 - 2 * fraction)
    if not high_usable:
        weight = 0.0
    elif not low_usable:
        weight = 1.0
    merged = weight * high_e + (1 - weight) * low_e
    require(math.isfinite(merged), "Nonfinite independently reconstructed merge")
    return merged, weight, high_usable, low_usable


def verify_bundle(base_path, source=None, engine=None):
    """Validate one bundle; return its decoded arrays, config, metadata and files."""
    base = Path(base_path)
    manifest_path = safe_file(base.parent, base.name + ".json")
    meta = read_json(manifest_path)
    labels = {"format": "ALEV4-SYNTHETIC-DUAL-GAIN", "schema_version": "1.0",
              "algorithm_version": "phase2-dual-gain-v1", "array_order": "row-major",
              "byte_order": "little-endian", "input_units": "photons m^-2 s^-1 nm^-1",
              "cfa_origin": "top-left (1,1)"}
    require(all(meta.get(key) == value for key, value in labels.items()),
            "Invalid bundle format, algorithm, layout, or units")
    require(meta.get("synthetic") is True and meta.get("calibrated_alev4") is False
            and meta.get("authentic_arriraw") is False, "Invalid bundle authenticity labels")
    cfg = config(meta.get("configuration"))
    require(shape(meta.get("image_size")) == cfg["sensor"]["image_size"], "Bundle dimensions disagree")
    count = math.prod(cfg["sensor"]["image_size"])
    number(meta.get("exposure_s"), "exposure", 0)
    integer(meta.get("seed"), "seed", 0, 2**32 - 1)
    observed_source, observed_engine = provenance(meta.get("provenance")), runtime(meta.get("runtime"))
    require(source is None or observed_source == source, "Bundle source revision mismatch")
    require(engine is None or observed_engine == engine, "Bundle runtime mismatch")
    files = meta.get("files")
    require(isinstance(files, dict) and set(files) == set(PAYLOADS), "Incomplete or unknown payload associations")
    require(meta.get("units") == UNITS, "Payload units disagree")
    paths = {key: safe_file(base.parent, files[key], base.name + suffix)
             for key, suffix in PAYLOADS.items()}
    identities = {(path.stat().st_dev, path.stat().st_ino) for path in paths.values()}
    require(len(identities) == len(PAYLOADS), "Aliased payload files are unsupported")
    high = decode(paths["high_raw"], "H", count)
    low = decode(paths["low_raw"], "H", count)
    merged = decode(paths["merged_electrons"], "d", count)
    flags = decode(paths["flags"], "B", count)
    high_max, low_max = (2**cfg[path]["adc_bits"] - 1 for path in ("high_gain", "low_gain"))
    require(all(value <= high_max for value in high) and all(value <= low_max for value in low),
            "RAW sample exceeds its ADC range")
    for high_dn, low_dn, estimate, flag in zip(high, low, merged, flags):
        expected, _, high_usable, low_usable = merge_sample(high_dn, low_dn, cfg)
        tolerance = 64 * math.ulp(max(1.0, abs(expected)))
        close(estimate, expected, "decoded merged electrons", rel_tol=0, abs_tol=tolerance)
        require(bool(flag & 32) == high_usable and bool(flag & 64) == low_usable,
                "Rail-derived usability flags disagree")
        require(bool(flag & 128) == ((high_usable or low_usable) and not bool(flag & 1)),
                "Physical/reconstruction validity flags disagree")
        require(not (flag & 2 and flag & 4) and not (flag & 8 and flag & 16),
                "A path cannot clip below and above the ADC simultaneously")
        require((not flag & 2 or high_dn == 0) and (not flag & 4 or high_dn == high_max)
                and (not flag & 8 or low_dn == 0) and (not flag & 16 or low_dn == low_max),
                "Pre-clamp diagnostic flags contradict observed ADC rails")
    return {"metadata": meta, "configuration": cfg, "high_raw": high, "low_raw": low,
            "merged_electrons": merged, "flags": flags,
            "files": [manifest_path, *paths.values()], "source": observed_source,
            "runtime": observed_engine}


def fixture_config(cfg, name):
    """Require the documented demo setup; defaults are never silently filled."""
    sensor = cfg["sensor"]
    require(sensor["image_size"] == [17, 257] and sensor["wavelength_nm"] == [550]
            and sensor["bin_width_nm"] == [10] and sensor["qe"] == [[0.5, 0.5, 0.5]]
            and sensor["pixel_pitch_m"] == 1e-6 and sensor["fill_factor"] == 1
            and sensor["full_well_e"] == 30000 and sensor["cfa_pattern"] == "RGGB",
            "Demo shared sensor configuration drift")
    require(sensor["shot_noise"] is (name == "noisy"), "Demo shot-noise configuration drift")
    require(cfg["high_gain"] == {"gain_dn_per_e": 4, "read_noise_e": 1 if name == "noisy" else 0,
                                  "black_level_dn": 64, "adc_bits": 12}
            and cfg["low_gain"] == {"gain_dn_per_e": 0.1, "read_noise_e": 5 if name == "noisy" else 0,
                                    "black_level_dn": 64, "adc_bits": 12}
            and cfg["merge"] == {"start_e": 600, "end_e": 900},
            "Demo electronic or merge configuration drift")


def fixture_expectation(name, index, width):
    if name == "transition":
        return 400.0 + 4 * (index % width)
    return {"dark": 0.0, "shadow": 10.0, "highlight": 12000.0,
            "saturation": 40000.0, "noisy": 250.0}[name]


def deterministic_codes(expected, cfg):
    stored = min(expected, cfg["sensor"]["full_well_e"])
    raw, flag = [], int(expected >= cfg["sensor"]["full_well_e"])
    for path, low_bit, high_bit in (("high_gain", 2, 4), ("low_gain", 8, 16)):
        electronics = cfg[path]
        # The fixed noiseless fixtures have nonnegative analog DN. MATLAB
        # rounds half away from zero; floor(x+0.5) is the positive case.
        analog = stored * electronics["gain_dn_per_e"] + electronics["black_level_dn"]
        rounded = math.floor(analog + 0.5)
        maximum = 2**electronics["adc_bits"] - 1
        flag |= low_bit if rounded < 0 else high_bit if rounded > maximum else 0
        raw.append(min(max(rounded, 0), maximum))
    _, _, high_usable, low_usable = merge_sample(*raw, cfg)
    flag |= (32 if high_usable else 0) | (64 if low_usable else 0)
    if (high_usable or low_usable) and not flag & 1:
        flag |= 128
    return raw[0], raw[1], flag


def verify_demo(directory, source=None, engine=None):
    """Return (validated files, per-frame metrics) for the complete fixed demo."""
    directory = Path(directory)
    summary_path = safe_file(directory, "phase2-demo-summary.json")
    summary = read_json(summary_path)
    require(summary.get("schema_version") == "1.0" and integer(summary.get("phase"), "phase", 2, 2) == 2
            and summary.get("demo_complete") is True, "Phase 2 demo is incomplete or unsupported")
    require(summary.get("synthetic") is True and summary.get("calibrated_alev4") is False
            and summary.get("authentic_arriraw") is False, "Invalid demo authenticity labels")
    observed_source, observed_engine = provenance(summary.get("provenance")), runtime(summary.get("runtime"))
    require(source is None or observed_source == source, "Demo source revision mismatch")
    require(engine is None or observed_engine == engine, "Demo runtime mismatch")
    source, engine = observed_source, observed_engine
    frames = summary.get("frames")
    require(isinstance(frames, list) and len(frames) == 6
            and integer(summary.get("frame_count"), "frame count", 6, 6) == 6,
            "Six complete demo frames are required")
    require(all(isinstance(frame, dict) and isinstance(frame.get("name"), str) for frame in frames),
            "Invalid demo frame record")
    require({frame["name"] for frame in frames} == set(NAMES), "Missing, duplicate or unknown demo frame")
    files, metrics = [summary_path], {}
    for frame in frames:
        name = frame["name"]
        safe_file(directory, frame.get("metadata_file"), name + ".json")
        bundle = verify_bundle(directory / name, source, engine)
        cfg, meta = bundle["configuration"], bundle["metadata"]
        fixture_config(cfg, name)
        close(meta["exposure_s"], 0.01, "fixture exposure", rel_tol=0, abs_tol=0)
        close(frame.get("exposure_s"), meta["exposure_s"], "summary exposure", rel_tol=0, abs_tol=0)
        expected_seed = 201 + NAMES.index(name)
        require(integer(meta["seed"], "fixture seed", 0, 2**32 - 1) == expected_seed
                and integer(frame.get("seed"), "summary seed", 0, 2**32 - 1) == expected_seed,
                "Fixture seed association disagrees")
        count = len(bundle["high_raw"])
        width = cfg["sensor"]["image_size"][1]
        expected = [fixture_expectation(name, index, width) for index in range(count)]
        if name != "noisy":
            for index, mean in enumerate(expected):
                high, low, flag = deterministic_codes(mean, cfg)
                require(bundle["high_raw"][index] == high and bundle["low_raw"][index] == low,
                        f"{name}: analytical fixture DN disagrees")
                require(bundle["flags"][index] == flag, f"{name}: analytical fixture diagnostics disagree")
        else:
            # This cannot establish a particular Poisson realization. Numerical
            # covariance/distribution suites establish that separate property.
            require(len(set(bundle["high_raw"])) > 1 and len(set(bundle["low_raw"])) > 1,
                    "The enabled noisy fixture contains no observed variation")
        flags = bundle["flags"]
        values = {
            "mean_expected_electrons": math.fsum(expected) / count,
            "mean_merged_electrons": math.fsum(bundle["merged_electrons"]) / count,
            "full_well_saturation_fraction": sum(bool(flag & 1) for flag in flags) / count,
            "high_adc_clipping_fraction": sum(bool(flag & 6) for flag in flags) / count,
            "low_adc_clipping_fraction": sum(bool(flag & 24) for flag in flags) / count,
            "reconstruction_valid_fraction": sum(bool(flag & 128) for flag in flags) / count,
        }
        for field, value in values.items():
            close(frame.get(field), value, f"{name} {field}")
        metrics[name] = values
        files.extend(bundle["files"])
    identities = {(path.stat().st_dev, path.stat().st_ino) for path in files}
    require(len(files) == 31 and len(identities) == 31, "Artifact files are missing or aliased")
    return files, metrics


def check_phase1(report, source, engine):
    require(isinstance(report, dict) and report.get("schema_version") == "1.0"
            and integer(report.get("phase"), "Phase 1 phase", 1, 1) == 1
            and report.get("status") == "passed" and report.get("phase1_passed") is True,
            "Full executed Phase 1 prerequisite is required")
    require(report.get("calibrated_alev4") is False, "Phase 1 prerequisite claims calibration")
    require(provenance(report.get("provenance")) == source
            and runtime({"name": report.get("runtime"), "version": report.get("runtime_version")}) == engine,
            "Phase 1 prerequisite source/runtime differs")
    for name in PHASE1_GATES:
        gate = report.get(name)
        require(isinstance(gate, dict) and (gate.get("passed") is True or gate.get("status") == "passed")
                and gate.get("passed", True) is True and gate.get("status", "passed") == "passed",
                f"Missing or failed Phase 1 prerequisite gate: {name}")
        integer(gate.get("test_count"), f"Phase 1 {name} test count", 1)
    for name in ("first_exposure", "second_exposure"):
        check = report["iset"].get(name)
        require(isinstance(check, dict) and check.get("status") == "passed", "Missing genuine ISET comparison")
        error = number(check.get("max_relative_error"), "ISET relative error", 0)
        tolerance = number(check.get("relative_tolerance"), "ISET tolerance", 0, 5e-5)
        require(tolerance > 0 and error <= tolerance, "ISET comparison exceeds tolerance")


def digest(path):
    result = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def verify_outputs(output_root, compare_dir=None, expected_commit=None):
    root = Path(output_root)
    report = read_json(root / "validation" / "phase2-validation.json")
    require(report.get("schema_version") == "1.0" and integer(report.get("phase"), "phase", 2, 2) == 2
            and report.get("status") == "passed" and report.get("phase2_passed") is True,
            "Full Phase 2 pass report is required")
    require(report.get("calibrated_alev4") is False, "Report must not claim ALEV4 calibration")
    require(report.get("phase1_required") is True,
            "Full Phase 2 evidence must require the Phase 1 prerequisite")
    source = provenance(report.get("provenance"))
    engine = runtime({"name": report.get("runtime"), "version": report.get("runtime_version")})
    if expected_commit is not None:
        require(isinstance(expected_commit, str) and re.fullmatch(r"[0-9a-f]{40}", expected_commit) is not None,
                "Expected commit requires a full lowercase SHA")
        require(source["repository_head"] == expected_commit, "Evidence belongs to another commit")
    check_phase1(report.get("phase1"), source, engine)
    groups = 0
    for name in GATES:
        gate = report.get(name)
        require(isinstance(gate, dict) and gate.get("status") == "passed" and gate.get("passed") is True,
                f"Missing or failed Phase 2 gate: {name}")
        count = integer(gate.get("test_count"), f"{name} test count", 1)
        tests = gate.get("tests")
        if isinstance(tests, dict) and count == 1:
            tests = [tests]  # MATLAB encodes a one-element struct array as an object.
        require(isinstance(tests, list) and len(tests) == count, f"{name}: test inventory/count disagree")
        require(all(isinstance(test, dict) and isinstance(test.get("name"), str) and test["name"].strip()
                    and test.get("status") == "passed" and test.get("passed") is True for test in tests),
                f"{name}: missing or failed individual test group")
        require(len({test["name"] for test in tests}) == count, f"{name}: duplicate test group names")
        groups += count
    files, metrics = verify_demo(root / "demo", source, engine)
    hashes = {path.name: digest(path) for path in files}
    if compare_dir is not None:
        comparison = Path(compare_dir)
        require(comparison.resolve() != (root / "demo").resolve(),
                "Comparison must use a distinct resolved demo directory")
        other, _ = verify_demo(comparison, source, engine)
        primary_identities = {(path.stat().st_dev, path.stat().st_ino) for path in files}
        repeat_identities = {(path.stat().st_dev, path.stat().st_ino) for path in other}
        require(primary_identities.isdisjoint(repeat_identities),
                "Comparison artifacts alias primary files, including cross-filename aliases")
        counterparts = {path.name: path for path in other}
        for path in files:
            counterpart = counterparts[path.name]
            require(hashes[path.name] == digest(counterpart), "Repeated demo is not byte-identical")
    return {"status": "passed", "phase": 2, "frame_count": 6, "artifact_count": len(files),
            "numerical_test_groups": groups, "source": source,
            "runtime": {"name": engine[0], "version": engine[1]},
            "frames": metrics, "artifact_sha256": hashes,
            "compared_demo_byte_identical": compare_dir is not None, "calibrated_alev4": False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output_root", type=Path, nargs="?", default=Path("outputs/phase2"))
    parser.add_argument("--compare-dir", type=Path)
    parser.add_argument("--expected-commit")
    args = parser.parse_args(argv)
    try:
        result = verify_outputs(args.output_root, args.compare_dir, args.expected_commit)
    except (ArtifactError, OSError, TypeError, KeyError, OverflowError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
