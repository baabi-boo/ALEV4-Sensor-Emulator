#!/usr/bin/env python3
"""Independent stdlib validation of Phase 1 evidence, RAW and PGM artifacts.

Usage: python3 scripts/verify_phase1_artifacts.py outputs
       --expected-commit SHA --compare-dir outputs/demo-repeat
The comparison directory contains a second complete demo in a distinct resolved
directory. No byte differences are ignored. This verifies generic simulation
artifacts, not ALEV4 calibration.
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
BRACKETS = dict(zip(("exposure_025x", "exposure_050x", "exposure_100x", "exposure_200x", "exposure_400x"), (0.25, 0.5, 1.0, 2.0, 4.0)))
NAMES = {"black", "flat", "ramp", "checker", "iset_scene", *BRACKETS}
GATES = ("core", "config_edges", "spectral_properties", "input_representation", "numerical_edges",
         "poisson_edges", "raw_io", "demo_contract", "provenance_tests", "iset")


class ArtifactError(ValueError):
    """Artifacts violate the declared format or evidence contract."""


def require(ok, message):
    if not ok:
        raise ArtifactError(message)


def number(value, label, lower=0, upper=math.inf):
    require(type(value) in (int, float), f"{label}: expected number")
    try:
        value = float(value)
    except OverflowError as exc:
        raise ArtifactError(f"{label}: numeric overflow") from exc
    require(math.isfinite(value) and lower <= value <= upper, f"{label}: invalid range")
    return value


def integer(value, label, lower=0, upper=MAX_PIXELS):
    value = number(value, label, lower, upper)
    require(value.is_integer(), f"{label}: expected integer")
    return int(value)


def close(value, expected, label):
    require(math.isclose(number(value, label), expected, rel_tol=1e-10, abs_tol=1e-11), f"{label}: independent value mismatch")


def bounded(path, maximum):
    require(path.is_file(), f"Missing file: {path}")
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


def read_json(path):
    try:
        value = json.loads(bounded(path, MAX_JSON).decode("utf-8"), object_pairs_hook=unique_pairs,
                           parse_constant=lambda v: (_ for _ in ()).throw(ArtifactError(f"Nonfinite JSON: {v}")))
    except (UnicodeError, json.JSONDecodeError, RecursionError) as exc:
        raise ArtifactError(f"Invalid JSON: {path.name}") from exc
    require(isinstance(value, dict), f"JSON object required: {path.name}")
    return value


def safe_file(directory, name, extension):
    require(isinstance(name, str) and name and "\\" not in name and ":" not in name and "\0" not in name, "Unsafe artifact filename")
    require(not name.startswith("/") and all(p not in ("", ".", "..") for p in name.split("/")), "Artifact path traversal")
    path = directory
    for component in name.split("/"):
        path /= component
        require(not path.is_symlink(), "Symlink artifact is unsupported")
    require(path.suffix == extension and path.resolve().is_relative_to(directory.resolve()), "Invalid artifact path/extension")
    require(path.is_file(), f"Missing artifact: {name}")
    return path


def provenance(value):
    require(isinstance(value, dict), "Missing source provenance")
    for key in SHA_FIELDS:
        require(isinstance(value.get(key), str) and re.fullmatch(r"[0-9a-f]{40}", value[key]), f"Missing/invalid observed {key}")
    require(isinstance(value.get("meaning"), str) and value["meaning"].strip(), "Missing provenance meaning")
    return {key: value[key] for key in SHA_FIELDS}


def runtime(value):
    require(isinstance(value, dict) and value.get("name") in ("GNU Octave", "MATLAB"), "Missing/unknown runtime")
    require(isinstance(value.get("version"), str) and value["version"].strip(), "Missing runtime version")
    return value["name"], value["version"]


def config(value):
    require(isinstance(value, dict) and value.get("schema_version") == "1.0", "Invalid sensor configuration")
    required = {"schema_version", "image_size", "wavelength_nm", "bin_width_nm", "qe", "pixel_pitch_m", "fill_factor", "full_well_e", "read_noise_e", "gain_dn_per_e", "black_level_dn", "adc_bits", "cfa_pattern", "shot_noise"}
    require(set(value) == required, "Incomplete/unknown sensor configuration fields")
    shape = value["image_size"]
    require(isinstance(shape, list) and len(shape) == 2, "Invalid image_size")
    height, width = [integer(v, "dimension", 1) for v in shape]
    require(height * width <= MAX_PIXELS, "Pixel limit exceeded")
    bins = value["bin_width_nm"] if isinstance(value["bin_width_nm"], list) else [value["bin_width_nm"]]
    wave = value["wavelength_nm"] if isinstance(value["wavelength_nm"], list) else [value["wavelength_nm"]]
    require(len(wave) == len(bins) and len(wave) > 0, "Spectral shape mismatch")
    previous_upper = None
    for i, (w, b) in enumerate(zip(wave, bins)):
        w, b = number(w, "wavelength"), number(b, "bin width")
        lower, upper = w-b/2, w+b/2
        require(b > 0 and 0 < lower and math.isfinite(lower) and math.isfinite(upper), "Invalid spectral bins")
        if i:
            tolerance = 8*max(math.ulp(previous_upper), math.ulp(lower))
            require(w > wave[i-1] and previous_upper-lower <= tolerance, "Unordered/overlapping spectral bins")
        previous_upper = upper
    qe = value["qe"]
    if len(wave) == 1 and isinstance(qe, list) and len(qe) == 3 and not isinstance(qe[0], list):
        qe = [qe]
    require(isinstance(qe, list) and len(qe) == len(wave), "QE spectrum mismatch")
    for row in qe:
        require(isinstance(row, list) and len(row) == 3, "QE needs RGB columns")
        for v in row:
            number(v, "QE", 0, 1)
    pitch = number(value["pixel_pitch_m"], "pixel pitch")
    require(0 < pitch*pitch < math.inf, "Invalid pixel area")
    number(value["fill_factor"], "fill factor", 0, 1)
    require(number(value["full_well_e"], "full well") > 0 and number(value["gain_dn_per_e"], "gain") > 0, "Invalid fullwell/gain")
    number(value["read_noise_e"], "read noise")
    bits = integer(value["adc_bits"], "ADC bits", 1, 16)
    number(value["black_level_dn"], "black level", 0, 2**bits-1)
    require(value["cfa_pattern"] in ("RGGB", "BGGR", "GRBG", "GBRG") and type(value["shot_noise"]) is bool, "Invalid CFA/noise setting")
    return {**value, "image_size": [height, width], "qe": qe, "wavelength_nm": wave, "bin_width_nm": bins}


def check_iset(value):
    require(isinstance(value, dict) and value.get("status") == "passed", "ISET gate missing or not passed")
    error = number(value.get("max_relative_error"), "ISET relative error")
    limit = number(value.get("relative_tolerance"), "ISET tolerance", 0, 5e-5)
    require(0 < limit and error <= limit, "ISET numerical tolerance failed")


def expected_mean(cfg, density, exposure):
    height, width = cfg["image_size"]
    rows, cols = ((height+1)//2, height//2), ((width+1)//2, width//2)
    spectral = [math.fsum(q[c]*b for q, b in zip(cfg["qe"], cfg["bin_width_nm"])) for c in range(3)]
    weighted = math.fsum(rows[r]*cols[c]*spectral["RGB".index(cfg["cfa_pattern"][2*r+c])] for r in range(2) for c in range(2)) / (height*width)
    return exposure * cfg["pixel_pitch_m"]**2 * cfg["fill_factor"] * density * weighted


def preview(path, values, shape, maximum):
    data = bounded(path, len(values)+4096)
    # The writer emits the fixed P5 header below, followed by row-major bytes.
    header = f"P5\n# Synthetic Bayer mosaic; linear ADC scaling, no demosaic\n{shape[1]} {shape[0]}\n255\n".encode()
    require(data.startswith(header), "PGM header/dimensions disagree")
    require(data[len(header):] == bytes(math.floor(255*v/maximum+0.5) for v in values), "PGM pixels disagree with RAW scaling/order")


def verify_demo(directory, source, engine):
    summary_path = safe_file(directory, "phase1-demo-summary.json", ".json")
    summary = read_json(summary_path)
    require(summary.get("schema_version") == "1.0" and summary.get("demo_complete") is True, "Demo incomplete/unsupported")
    require(summary.get("synthetic") is True and summary.get("calibrated_alev4") is False and summary.get("authentic_arriraw") is False, "Invalid demo authenticity labels")
    require(provenance(summary.get("provenance")) == source and runtime(summary.get("runtime")) == engine, "Demo source/runtime mismatch")
    check_iset(summary.get("iset_integration"))
    base_cfg = config(summary.get("sensor"))
    density = number(summary.get("photon_density_per_m2_s_nm"), "density")
    exposure = number(summary.get("reference_exposure_s"), "reference exposure")
    require(density > 0 and exposure > 0 and summary.get("exposure_multipliers") == list(BRACKETS.values()), "Invalid exposure bracket")
    frames = summary.get("frames")
    require(isinstance(frames, list) and len(frames) == 10 and summary.get("frame_count") == 10, "Ten complete demo frames required")
    require(all(isinstance(f, dict) and isinstance(f.get("name"), str) for f in frames), "Invalid frame records")
    require({f["name"] for f in frames} == NAMES, "Missing/duplicate/unknown frames")
    files, means = [summary_path], {}
    for frame in frames:
        name = frame["name"]
        paths = [safe_file(directory, frame.get(key), ext) for key, ext in (("raw_file", ".raw"), ("metadata_file", ".json"), ("preview_file", ".pgm"))]
        require(all(p.name == name+ext for p, ext in zip(paths, (".raw", ".json", ".pgm"))), "Frame filenames disagree")
        files.extend(paths)
        meta = read_json(paths[1])
        labels = {"format": "ALEV4-SYNTHETIC-RAW", "schema_version": "1.0", "sample_type": "uint16", "byte_order": "little-endian", "layout": "row-major", "units": "DN", "algorithm_version": "phase1-baseline-v1", "sampler_version": "Poisson-Knuth-PTRS-v1"}
        require(all(meta.get(k) == v for k, v in labels.items()), "Invalid RAW storage/algorithm labels")
        require(meta.get("synthetic") is True and meta.get("calibrated") is False and meta.get("authentic_arriraw") is False, "Invalid RAW authenticity labels")
        cfg = config(meta.get("sensor")); height, width = cfg["image_size"]
        require(integer(meta.get("height"), "height", 1) == height and integer(meta.get("width"), "width", 1) == width and frame.get("image_size") == cfg["image_size"], "RAW dimensions disagree")
        require(meta.get("cfa_origin") == [1, 1] and meta.get("cfa_pattern") == cfg["cfa_pattern"], "CFA metadata mismatch")
        count = height*width
        require(integer(meta.get("byte_count"), "byte_count", 2, 2*MAX_PIXELS) == 2*count, "Wrong RAW byte_count")
        data = bounded(paths[0], 2*count)
        require(len(data) == 2*count, "Truncated RAW")
        values = array.array("H"); require(values.itemsize == 2, "uint16 unavailable"); values.frombytes(data)
        if sys.byteorder != "little": values.byteswap()
        maximum = 2**integer(cfg["adc_bits"], "ADC bits", 1, 16)-1
        require(all(v <= maximum for v in values), "RAW samples exceed ADC range")
        require(provenance(meta.get("provenance")) == source and runtime(meta.get("runtime")) == engine, "RAW source/runtime mismatch")
        close(frame.get("mean_raw_dn"), math.fsum(values)/count, "decoded RAW mean")
        close(frame.get("exposure_s"), number(meta.get("exposure_s"), "exposure"), "frame exposure")
        require(integer(frame.get("seed"), "frame seed", 0, 2**32-1) == integer(meta.get("seed"), "seed", 0, 2**32-1) and frame.get("raw_roundtrip_exact") is True, "Frame seed/roundtrip mismatch")
        for field in ("mean_expected_electrons", "mean_collected_electrons", "collected_variance_e2", "shot_residual_variance_e2"): number(frame.get(field), field)
        for field in ("full_well_saturation_fraction", "adc_low_clipping_fraction", "adc_high_clipping_fraction"): number(frame.get(field), field, 0, 1)
        preview(paths[2], values, cfg["image_size"], maximum)
        kind = "exposure_bracket" if name in BRACKETS else "iset_scene_to_raw" if name == "iset_scene" else "fixture"
        require(frame.get("kind") == kind, "Frame kind mismatch")
        if name != "iset_scene": require(cfg == base_cfg, "Generic frame configuration drift")
        if name in BRACKETS or name == "flat":
            expected_exposure = exposure*BRACKETS.get(name, 1)
            close(frame["exposure_s"], expected_exposure, "bracket exposure")
            means[name] = expected_mean(cfg, density, expected_exposure)
            close(frame["mean_expected_electrons"], means[name], "analytic photon/electron mean")
        if name == "black": require(frame["mean_expected_electrons"] == 0, "Black photon signal is not zero")
    require(len({p.resolve() for p in files}) == 31, "Artifact aliases detected")
    return files, means


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def verify_outputs(output_root, compare_dir=None, expected_commit=None):
    root = Path(output_root)
    report = read_json(root / "validation" / "phase1-validation.json")
    require(report.get("schema_version") == "1.0" and integer(report.get("phase"), "phase", 1, 1) == 1 and report.get("status") == "passed" and report.get("phase1_passed") is True, "Full Phase 1 pass report required")
    require(report.get("calibrated_alev4") is False, "Report must not claim ALEV4 calibration")
    for name in GATES:
        gate = report.get(name)
        require(isinstance(gate, dict) and (gate.get("passed") is True or gate.get("status") == "passed"), f"Missing/failed gate {name}")
        require(gate.get("passed", True) is True and gate.get("status", "passed") == "passed", f"Conflicting gate status {name}")
        integer(gate.get("test_count"), "gate test count", 1)
    check_iset(report["iset"].get("first_exposure")); check_iset(report["iset"].get("second_exposure"))
    source = provenance(report.get("provenance"))
    if expected_commit is not None:
        require(isinstance(expected_commit, str) and re.fullmatch(r"[0-9a-f]{40}", expected_commit), "Expected commit needs full lowercase SHA")
        require(source["repository_head"] == expected_commit, "Evidence belongs to another commit")
    engine = runtime({"name": report.get("runtime"), "version": report.get("runtime_version")})
    files, means = verify_demo(root / "demo", source, engine)
    if compare_dir is not None:
        comparison = Path(compare_dir)
        require(comparison.resolve() != (root / "demo").resolve(),
                "Comparison must use a distinct demo directory, not the same directory or an alias")
        other, _ = verify_demo(comparison, source, engine)
        counterpart = {p.name: p for p in other}
        require(all(digest(p) == digest(counterpart[p.name]) for p in files), "Repeated demo is not byte-identical")
    return {"status": "passed", "frame_count": 10, "artifact_count": len(files), "source": source,
            "analytical_flat_means_e": means, "compared_demo_byte_identical": compare_dir is not None,
            "calibrated_alev4": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output_root", type=Path, nargs="?", default=Path("outputs"))
    parser.add_argument("--compare-dir", type=Path)
    parser.add_argument("--expected-commit")
    args = parser.parse_args()
    try:
        result = verify_outputs(args.output_root, args.compare_dir, args.expected_commit)
    except (ArtifactError, OSError, TypeError, KeyError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
