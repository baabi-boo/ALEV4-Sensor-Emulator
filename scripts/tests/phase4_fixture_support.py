"""Small, artificial Phase 4 wire fixtures, independent of every producer.

These are parser/semantic test data, never native execution or PRNG evidence.
The 2-by-3-by-2 cube, its spectral answers, and full-grid map crops are written
down here. Only downstream scalar arithmetic and the documented typed encoder
are shared by tests. No verifier, MATLAB/Octave, ignored output or third-party
Python package is imported. Source labels and runtime associations are fake.
"""
from copy import deepcopy
from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path
import struct


FORMAT = "ALEV4-SYNTHETIC-STRUCTURED-NOISE"
DENSITY = "photons m^-2 s^-1 nm^-1"
MEANING = ("Observed Git HEADs; an empty value means unavailable. "
           "Uncommitted edits, object existence and agreement with dependency gitlinks "
           "are not established by these metadata observations.")
SOURCE = dict(repository_head="1" * 40,
              isetcam_head="3e0253421752eb72f2d1353327dffd0d433abdaf",
              isethdrsensor_head="ee2dacceb456516de3ecefadd72955154cf3cabe",
              meaning=MEANING)
ENGINE = dict(name="GNU Octave", version="0.0-artificial-Python-fixture")
PATHS = ("shared", "single", "high_gain", "low_gain")
TAGS = {"photo": 1, "dark": 2, "shared_row": 10, "shared_column": 11,
        "shared_frame": 12, "single_row": 20, "single_column": 21,
        "single_frame": 22, "single_pixel": 23, "high_row": 30,
        "high_column": 31, "high_frame": 32, "high_pixel": 33,
        "low_row": 40, "low_column": 41, "low_frame": 42, "low_pixel": 43}
ORDER = ["spectral_integration", "prnu_response", "dark_expectation",
         "separate_photo_dark_sampling", "charge_sum", "physical_full_well",
         "shared_electronics", "path_electronics_and_pixel_read_noise",
         "gain_and_black", "round", "adc_clip"]
RESULT_UNITS = dict(input_irradiance=DENSITY, expected_incident_photons="photons",
                    charge="electrons", components="electrons", read_electrons="electrons",
                    raw_dn="DN", exposure_s="s", dark_current_e_per_s="electrons s^-1",
                    prnu="dimensionless")
CUBE = [8, 16, 16, 32, 24, 48, 32, 64, 40, 80, 48, 96]
# QE rows [1,.5,.25] and [.25,.5,1], widths [2,4], BGGR, collection 1/16.
BASELINE = [4.25, 5, 12.75, 10, 10, 15]
INCIDENT = [5, 10, 15, 20, 25, 30]
PRNU = [1, 1.25, 1.5, 1.75, 2, 1, .5, 2, 3, 1.5, 0, 1]
DARK = [0, 2, 4, 6, 8, 0, 2, 4, 10, 6, 8, 10]
SHARED = [-1, -2, -3, -4, -5, -10, 4.75, 1, -6, 2, -8, -.5]
ACTIVE_PRNU = [1, .5, 2, 1.5, 0, 1]
ACTIVE_DARK = [0, 2, 4, 6, 8, 10]
ACTIVE_SHARED = [-10, 4.75, 1, 2, -8, -.5]


@dataclass
class Numeric:
    values: list
    shape: tuple
    class_name: str = "double"


@dataclass
class Cells:
    items: list
    shape: tuple


@dataclass
class Characters:
    value: str
    shape: tuple


def numbers(values, shape=(2, 3), class_name="double"):
    return Numeric(list(values), tuple(shape), class_name)


def cell_row(items):
    return Cells(list(items), (1, len(items)))


def vector(values):
    return numbers(values, (1, len(values)))


def _path(gain, black, bits, noise=0):
    return dict(gain_dn_per_e=gain, read_noise_e=noise,
                black_level_dn=black, adc_bits=bits)


def _electronic(fixed, *, shared=False, stochastic=0):
    """Hand-chosen draws; finite support does not assert a random generator."""
    row = [-.5, .5] if shared else [.25, -.75]
    column = [.25, -.25, .5] if shared else [0, .25, -.25]
    frame = .125 if shared else .5
    pixel = [0] * 6 if shared else [.125, -.25, .375, -.5, .625, -.75]
    if not stochastic:
        row, column, frame, pixel = [0, 0], [0, 0, 0], 0, [0] * 6
    elif stochastic == 2:
        row, column, frame = [-v for v in row], [-v for v in column], -frame
        pixel = [-v for v in pixel]
    total = [(((v + row[i // 3]) + column[i % 3]) + frame) + pixel[i]
             for i, v in enumerate(fixed)]
    return dict(fixed_offset_e=numbers(fixed), row_e=numbers(row, (2, 1)),
                column_e=vector(column), frame_e=frame, pixel_e=numbers(pixel),
                total_e=numbers(total))


def _adc(values, cfg, *, legacy=False):
    maximum = 2 ** cfg["adc_bits"] - 1
    # All fixtures stay below 2**10. This elementary tie rule is independent
    # of the verifier's high-magnitude-safe implementation.
    analog = [v * cfg["gain_dn_per_e"] + cfg["black_level_dn"] for v in values]
    rounded = [math.floor(v + .5) if v >= 0 else math.ceil(v - .5) for v in analog]
    codes = [min(max(v, 0), maximum) for v in rounded]
    result = dict(read_electrons=numbers(values), raw_dn=numbers(codes, class_name="uint16"),
                  adc_low_clipped=numbers([v < 0 for v in rounded], class_name="logical"),
                  adc_high_clipped=numbers([v > maximum for v in rounded], class_name="logical"))
    if not legacy:
        result["adc_usable"] = numbers([0 < v < maximum for v in codes], class_name="logical")
    return result


def _merge(high, low, cfg):
    """Documented observed-channel smoothstep, with no expectations/maps."""
    values, weights, high_ok, low_ok = [], [], [], []
    for h, l in zip(high, low):
        hp, lp = cfg["high_gain"], cfg["low_gain"]
        hok, lok = 0 < h < 2 ** hp["adc_bits"] - 1, 0 < l < 2 ** lp["adc_bits"] - 1
        he = (h - hp["black_level_dn"]) / hp["gain_dn_per_e"]
        le = (l - lp["black_level_dn"]) / lp["gain_dn_per_e"]
        t = min(1, max(0, (le - cfg["merge"]["start_e"]) /
                       (cfg["merge"]["end_e"] - cfg["merge"]["start_e"])))
        weight = 1 - t * t * (3 - 2 * t) if hok and lok else 1 if hok else 0
        values.append(weight * he + (1 - weight) * le)
        weights.append(weight)
        high_ok.append(hok)
        low_ok.append(lok)
    return dict(electrons=numbers(values), weight_high=numbers(weights),
                valid=numbers([a or b for a, b in zip(high_ok, low_ok)], class_name="logical"),
                high_usable=numbers(high_ok, class_name="logical"),
                low_usable=numbers(low_ok, class_name="logical"))


def make_result(mode="single", *, stochastic=0, scalar_maps=False, zero_exposure=False):
    """Assemble a complete enabled exposure from the independent small oracle."""
    sensor = dict(schema_version="1.0", image_size=vector([2, 3]),
                  wavelength_nm=numbers([500, 600], (2, 1)),
                  bin_width_nm=numbers([2, 4], (2, 1)),
                  qe=numbers([1, .5, .25, .25, .5, 1]), pixel_pitch_m=.5,
                  fill_factor=.5, full_well_e=20, read_noise_e=1 if stochastic else 0,
                  gain_dn_per_e=2, black_level_dn=2.5, adc_bits=5,
                  cfa_pattern="BGGR", shot_noise=bool(stochastic))
    cfg = sensor
    if mode == "dual":
        sensor.update(read_noise_e=3, gain_dn_per_e=.5, black_level_dn=64, adc_bits=16)
        cfg = dict(schema_version="2.0", sensor=sensor,
                   high_gain=_path(4, 8, 6, int(bool(stochastic))),
                   low_gain=_path(1, 8, 8, int(bool(stochastic))),
                   merge=dict(start_e=4, end_e=12))
    geom = dict(schema_version="1.0", full_grid_size=vector([3, 4]),
                active_roi=vector([2, 2, 2, 3]), pixel_pitch_m=.5,
                origin_xy_m=vector([0, 0]), full_grid_cfa_pattern="RGGB",
                parameter_sources=cell_row(["ARTIFICIAL-FIXTURE-GEOMETRY"]))
    active_prnu, active_dark, active_shared = ACTIVE_PRNU, ACTIVE_DARK, ACTIVE_SHARED
    if scalar_maps:
        active_prnu, active_dark, active_shared = [1] * 6, [2] * 6, [.5] * 6
    model = dict(schema_version="1.0", enabled=True, full_grid_size=vector([3, 4]),
                 realization_id="ARTIFICIAL-PYTHON-FIXTURE", reference_temperature_K=293.15,
                 prnu=1 if scalar_maps else numbers(PRNU, (3, 4)),
                 dark_current_e_per_s=2 if scalar_maps else numbers(DARK, (3, 4)),
                 dark_shot_noise=bool(stochastic))
    offsets = dict(shared=active_shared, single=[.25] * 6,
                   high_gain=[.5] * 6, low_gain=[-.25] * 6)
    for name in PATHS:
        fixed = (.5 if scalar_maps else numbers(SHARED, (3, 4))) if name == "shared" else offsets[name][0]
        model[name] = dict(fixed_offset_e=fixed, row_noise_e=int(bool(stochastic)),
                           column_noise_e=int(bool(stochastic)), frame_noise_e=int(bool(stochastic)))
    model["parameter_sources"] = cell_row(["ARTIFICIAL-ASSUMED-NOISE"])
    maps = dict(prnu=numbers(active_prnu), dark_current_e_per_s=numbers(active_dark))
    for name in PATHS:
        maps[name] = dict(deepcopy(model[name]), fixed_offset_e=numbers(offsets[name]))
    baseline, incident = ([0] * 6, [0] * 6) if zero_exposure else (BASELINE, INCIDENT)
    exposure = 0 if zero_exposure else .5
    photo = [a * b for a, b in zip(baseline, active_prnu)]
    dark = [v * exposure for v in active_dark]
    photo_draw, dark_draw = photo, dark
    if stochastic and not scalar_maps and not zero_exposure:
        photo_draw = [3, 4, 27, 17, 0, 18] if stochastic == 1 else [7, 2, 24, 12, 0, 16]
        dark_draw = [0, 2, 1, 5, 2, 4] if stochastic == 1 else [0, 0, 3, 1, 6, 5]
    components = dict(photo_electrons=numbers(photo_draw), dark_electrons=numbers(dark_draw),
                      shared=_electronic(offsets["shared"], shared=True, stochastic=stochastic))
    paths = ("single",) if mode == "single" else ("high_gain", "low_gain")
    for name in paths:
        components[name] = _electronic(offsets[name], stochastic=stochastic)
    collected = [a + b for a, b in zip(photo_draw, dark_draw)]
    stored, saturated = [min(v, 20) for v in collected], [v >= 20 for v in collected]
    readout = dict(expected_electrons=numbers([a + b for a, b in zip(photo, dark)]),
                   expected_photoelectrons=numbers(photo), expected_dark_electrons=numbers(dark),
                   collected_electrons=numbers(collected), charge_electrons=numbers(stored),
                   full_well_saturated=numbers(saturated, class_name="logical"), seed=2**32 - 2,
                   expected_incident_photons=numbers(incident), exposure_s=exposure,
                   input_units=DENSITY, spectral_bin_convention="bin-average density times explicit width in nm")
    shared = components["shared"]["total_e"].values
    for name in paths:
        signed = [(s + x) + y for s, x, y in zip(stored, shared, components[name]["total_e"].values)]
        path = _adc(signed, sensor if mode == "single" else cfg[name])
        if mode == "single":
            readout.update(path)
            valid = path["adc_usable"].values
        else:
            readout[name] = path
    if mode == "dual":
        readout["merged"] = _merge(readout["high_gain"]["raw_dn"].values,
                                   readout["low_gain"]["raw_dn"].values, cfg)
        valid = readout["merged"]["valid"].values
    readout["reconstruction_valid"] = numbers([v and not s for v, s in zip(valid, saturated)], class_name="logical")
    return dict(format=FORMAT, schema_version="1.0", result_kind="exposure", readout_mode=mode,
                configuration=cfg, geometry=geom, noise_model=model,
                input_irradiance=numbers(CUBE, (2, 3, 2)), baseline_expected_electrons=numbers(baseline),
                active_maps=maps, components=components, readout=readout,
                operation_order=cell_row(ORDER + (["observed_channel_merge"] if mode == "dual" else [])),
                seeds={name: (2**32 - 2 + tag) % 2**32 for name, tag in {"frame": 0, **TAGS}.items()},
                seed_policy="component_seed = mod(frame_seed + tag, 2^32); locally saved/restored Twister",
                stream_scope="same runtime/version; no cross-runtime stream identity claim",
                runtime=deepcopy(ENGINE), units=deepcopy(RESULT_UNITS), parameter_classification="assumed",
                temperature_condition=dict(reference_temperature_K=293.15,
                    policy="declared applicability only; no temperature law or extrapolation"),
                synthetic=True, calibrated_alev4=False)


def _grid(x, y):
    return dict(schema_version="1.0", x_edges_m=vector(x), y_edges_m=vector(y),
                units="m", sample_semantics="cell_average")


def make_spatial_result(mode="single", *, stage="pre_psf"):
    result = make_result(mode)
    cfg = result["configuration"]
    sensor = cfg if mode == "single" else cfg["sensor"]
    legacy = {name: deepcopy(result["readout"][name]) for name in
              ("seed", "expected_incident_photons", "exposure_s", "input_units", "spectral_bin_convention")}
    legacy.update(expected_electrons=numbers(BASELINE), collected_electrons=numbers(BASELINE),
                  charge_electrons=numbers(BASELINE), full_well_saturated=numbers([False] * 6, class_name="logical"))
    if mode == "single":
        legacy.update(_adc(BASELINE, cfg, legacy=True))
    else:
        for name in ("high_gain", "low_gain"):
            legacy[name] = _adc(BASELINE, cfg[name], legacy=True)
        legacy["merged"] = _merge(legacy["high_gain"]["raw_dn"].values, legacy["low_gain"]["raw_dn"].values, cfg)
        legacy["reconstruction_valid"] = deepcopy(legacy["merged"]["valid"])
    optical_grid = _grid([.5, 1, 1.5, 2], [.5, 1, 1.5])
    sampling = dict(schema_version="1.0", method="piecewise_constant_area_overlap",
                    input_units=DENSITY, output_units=DENSITY, sample_semantics="cell_average",
                    coverage_policy="require_full_footprint", integral_units="photons s^-1 nm^-1",
                    active_cfa_pattern="BGGR", source_image_size=vector([2, 3]),
                    output_image_size=vector([2, 3]), spectral_plane_count=2,
                    source_bounds_xy_m=numbers([.5, .5, 2, 1.5], (2, 2)),
                    target_bounds_xy_m=numbers([.5, .5, 2, 1.5], (2, 2)),
                    active_roi=vector([2, 2, 2, 3]), aligned_copy=True, identity=True,
                    x_weight_nonzeros=3, y_weight_nonzeros=2, x_max_row_sum_error=0,
                    y_max_row_sum_error=0, represented_pitch_relative_error=0)
    for name in ("source_integral", "source_crop_integral", "target_integral"):
        sampling[name] = dict(status="available", values=vector([42, 84]))
    base = dict(schema_version="1.0", readout_mode=mode, input_stage=stage,
                input_irradiance=numbers(CUBE, (2, 3, 2)), input_grid=deepcopy(optical_grid),
                geometry=deepcopy(result["geometry"]), configuration=deepcopy(cfg),
                psf=numbers([], (0, 0)), optical_irradiance=numbers(CUBE, (2, 3, 2)),
                optical_grid=optical_grid, sampled_irradiance=numbers(CUBE, (2, 3, 2)),
                readout=legacy, spatial_provenance=dict(fixture="Artificial Python-only fixture",
                    unicode_label="μ😀", empty_row=numbers([], (1, 0)),
                    empty_char=Characters("", (0, 0)), informational_flag=True),
                optical_report=dict(operation="none", reason="input_already_post_optics"),
                sampling_report=sampling, synthetic=True, calibrated_alev4=False)
    order = ["area_overlap_average", "spectral_integration", mode + "_gain_readout"]
    if stage == "pre_psf":
        # Adjacent means in band 1; .25*right+.75*left in band 2.
        source = [4, 12, 12, 28, 20, 44, 28, 60, 28, 60, 36, 76, 44, 92, 52, 108]
        base.update(input_irradiance=numbers(source, (2, 4, 2)),
                    input_grid=_grid([0, .5, 1, 1.5, 2], [.5, 1, 1.5]),
                    psf=dict(schema_version="1.0", kernel=numbers([.5, .25, .5, .75], (1, 2, 2)),
                             origin_rc=vector([1, 1]), spacing_yx_m=vector([.5, .5]),
                             wavelength_nm=numbers([500, 600], (2, 1)), boundary_policy="valid",
                             parameter_sources=cell_row(["ARTIFICIAL-PSF"])) )
        base["optical_report"] = dict(schema_version="1.0", method="discrete_spectral_convolution",
            boundary_policy="valid", normalization_policy="validated_unit_sum_no_renormalization",
            input_units=DENSITY, output_units=DENSITY, kernel_shape=vector([1, 2, 2]),
            origin_rc=vector([1, 1]), spacing_yx_m=vector([.5, .5]),
            retained_row_indices=vector([1, 2]), retained_column_indices=vector([2, 4]),
            required_halo_top_bottom_left_right=vector([0, 0, 1, 0]),
            input_shape=vector([2, 4, 2]), output_shape=vector([2, 3, 2]),
            synthetic=True, calibrated_alev4=False)
        order.insert(0, "optical_psf")
    base["operation_order"] = cell_row(order)
    result.update(result_kind="spatial_exposure", spatial_baseline=base,
                  spatial_baseline_role="verification_context_only",
                  spatial_operation_order=cell_row(order[:-2] + result["operation_order"].items))
    return result


def units(path, class_name):
    """Independent transcription of the published wire-unit precedence table."""
    leaf, parent = path[-1], path[-2] if len(path) > 1 else ""
    exact = {"input_irradiance": DENSITY, "optical_irradiance": DENSITY,
             "sampled_irradiance": DENSITY, "expected_incident_photons": "photons",
             "dark_current_e_per_s": "electrons s^-1", "gain_dn_per_e": "DN electron^-1",
             "raw_dn": "DN", "black_level_dn": "DN", "reference_temperature_K": "K",
             "exposure_s": "s", "adc_bits": "bits"}
    indexes = ("image_size", "full_grid_size", "active_roi", "source_image_size", "output_image_size",
               "origin_rc", "retained_row_indices", "retained_column_indices",
               "required_halo_top_bottom_left_right", "kernel_shape", "input_shape", "output_shape",
               "spectral_plane_count", "x_weight_nonzeros", "y_weight_nonzeros")
    if "spatial_provenance" in path:
        return "metadata"
    if class_name == "logical":
        return "logical"
    if leaf in exact:
        return exact[leaf]
    if leaf.endswith(("electrons", "_e")):
        return "electrons"
    if leaf.endswith("_m"):
        return "m"
    if leaf.endswith("_nm"):
        return "nm"
    if leaf == "seed" or parent == "seeds":
        return "seed"
    if leaf == "values" and parent in ("source_integral", "source_crop_integral", "target_integral"):
        return "photons s^-1 nm^-1"
    return "index/count" if leaf in indexes else "dimensionless"


def encode_result(result):
    payload = bytearray()
    sample_count = 0
    engine = result["runtime"]["name"]

    def encode(value, path):
        nonlocal sample_count
        if isinstance(value, dict):
            return dict(kind="struct", fields={k: encode(v, (*path, k)) for k, v in value.items()})
        if isinstance(value, Cells):
            return dict(kind="cell", shape=list(value.shape), items={
                f"i{i:06d}": encode(v, (*path, f"i{i:06d}")) for i, v in enumerate(value.items, 1)})
        if isinstance(value, (str, Characters)):
            if isinstance(value, Characters):
                return dict(kind="char", shape=list(value.shape), value=value.value)
            count = len(value.encode("utf-8")) if engine == "GNU Octave" else len(value.encode("utf-16-le")) // 2
            return dict(kind="char", shape=[1, count], value=value)
        if type(value) in (bool, int, float):
            value = numbers([value], (1, 1), "logical" if type(value) is bool else "double")
        if not isinstance(value, Numeric):
            raise TypeError(type(value))
        code = {"double": "d", "uint16": "H", "logical": "B"}[value.class_name]
        blob = struct.pack("<" + str(len(value.values)) + code, *value.values)
        descriptor = dict(kind="numeric", **{"class": value.class_name}, shape=list(value.shape),
                          offset=len(payload), byte_count=len(blob), units=units(path, value.class_name))
        payload.extend(blob)
        sample_count += len(value.values)
        return descriptor

    tree = encode(result, ("result",))
    return tree, bytes(payload), sample_count


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


def write_bundle(directory, result=None, **kwargs):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    result = make_result(**kwargs) if result is None else result
    tree, content, count = encode_result(result)
    metadata = dict(format=FORMAT, schema_version="1.0", wire_version="typed-tree-v1",
                    byte_order="little-endian", array_order="row-major", synthetic=True,
                    calibrated_alev4=False, authentic_arriraw=False,
                    parameter_classification="assumed", provenance=deepcopy(SOURCE),
                    payload=dict(name="data.bin", byte_count=len(content), sample_count=count,
                                 sha256=hashlib.sha256(content).hexdigest()), result=tree)
    (directory / "data.bin").write_bytes(content)
    write_json(directory / "structured.json", metadata)
    return metadata


def tree_node(metadata, path):
    value = metadata["result"]
    for name in path.split("."):
        value = value["items" if value["kind"] == "cell" else "fields"][name]
    return value


def refresh_hash(directory, *, counts=False):
    directory = Path(directory)
    metadata = json.loads((directory / "structured.json").read_text(encoding="utf-8"))
    content = (directory / "data.bin").read_bytes()
    metadata["payload"]["sha256"] = hashlib.sha256(content).hexdigest()
    if counts:
        metadata["payload"]["byte_count"] = len(content)
    write_json(directory / "structured.json", metadata)


def replace_samples(directory, path, values, *, rehash=True):
    """Alter only packed bytes, retaining all descriptors for corruption tests."""
    directory = Path(directory)
    metadata = json.loads((directory / "structured.json").read_text(encoding="utf-8"))
    node = tree_node(metadata, path)
    code = {"double": "d", "uint16": "H", "logical": "B"}[node["class"]]
    blob = struct.pack("<" + str(len(values)) + code, *values)
    if len(blob) != node["byte_count"]:
        raise ValueError("Mutation must retain the segment byte count")
    content = bytearray((directory / "data.bin").read_bytes())
    content[node["offset"]:node["offset"] + len(blob)] = blob
    (directory / "data.bin").write_bytes(content)
    if rehash:
        refresh_hash(directory)
