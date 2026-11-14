"""Artificial Phase 3 parser fixtures; never numerical-execution evidence.

Only the Python standard library is used, and no production verifier or native
simulator is called. The small fixtures have handwritten spatial/electron
answers. The complete demo uses analytic cell averages to exercise the release
receipt and repeat gate without requiring Octave or retained generated output.
The ISET-shaped artifacts and reports are deliberately fabricated format data;
they do not establish that ISETCam or any numerical suite executed.
"""
from copy import deepcopy
import hashlib
import math
import struct

from phase2_fixture_support import write_json


DENSITY = "photons m^-2 s^-1 nm^-1"
SOURCE = {
    "repository_head": "1" * 40,
    "isetcam_head": "3e0253421752eb72f2d1353327dffd0d433abdaf",
    "isethdrsensor_head": "ee2dacceb456516de3ecefadd72955154cf3cabe",
    "meaning": "Artificial Python unit-test fixture, not execution evidence",
}
ENGINE = {"name": "GNU Octave", "version": "9.4.0-artificial-fixture"}
DEMO_NAMES = ("identity_single", "flat_binomial", "shifted_impulse", "edge",
              "sinusoid", "crop_cfa", "dual_spatial", "iset_checker")
PHASE3_GATES = ("geometry", "geometry_edges", "sampling", "optics",
                "integration", "spatial_io", "numerical_edges",
                "demo_contract", "iset_spatial")
PHASE2_GATES = ("core", "config_edges", "noise", "raw_io", "numerical_edges",
                "spectral_properties", "demo_contract")
PHASE1_GATES = ("core", "config_edges", "spectral_properties",
                "input_representation", "fixture_edges", "numerical_edges",
                "poisson_edges", "raw_io", "demo_contract", "provenance_tests",
                "iset")


def grid(x_edges, y_edges):
    return dict(schema_version="1.0", x_edges_m=list(x_edges),
                y_edges_m=list(y_edges), units="m", sample_semantics="cell_average")


def geometry(full=(3, 4), roi=(2, 2, 1, 2), pitch=1, origin=(0, 0),
             sources=("ARTIFICIAL-GEOMETRY",)):
    return dict(schema_version="1.0", full_grid_size=list(full),
                active_roi=list(roi), pixel_pitch_m=pitch,
                origin_xy_m=list(origin), full_grid_cfa_pattern="RGGB",
                parameter_sources={f"id{i:03d}": value
                                   for i, value in enumerate(sources, 1)})


def small_sensor(image=(1, 2), pattern="BGGR"):
    return dict(schema_version="1.0", image_size=list(image),
                wavelength_nm=[500, 600], bin_width_nm=[2, 3],
                qe=[[.25, .5, .75], [.5, .75, 1]], pixel_pitch_m=1,
                fill_factor=.5, full_well_e=50, read_noise_e=0,
                gain_dn_per_e=2, black_level_dn=.25, adc_bits=8,
                cfa_pattern=pattern, shot_noise=False)


def dual_config(sensor, *, demo=False):
    sensor = deepcopy(sensor)
    sensor.update(read_noise_e=3, gain_dn_per_e=.5,
                  black_level_dn=64, adc_bits=16)
    if demo:
        return dict(schema_version="2.0", sensor=sensor,
                    high_gain=dict(gain_dn_per_e=4, read_noise_e=1,
                                   black_level_dn=64, adc_bits=12),
                    low_gain=dict(gain_dn_per_e=.1, read_noise_e=5,
                                  black_level_dn=64, adc_bits=12),
                    merge=dict(start_e=600, end_e=900))
    return dict(schema_version="2.0", sensor=sensor,
                high_gain=dict(gain_dn_per_e=8, read_noise_e=0,
                               black_level_dn=2, adc_bits=8),
                low_gain=dict(gain_dn_per_e=2, read_noise_e=0,
                              black_level_dn=1.5, adc_bits=10),
                merge=dict(start_e=10, end_e=20))


def _readout_arrays(expected, configuration, mode):
    """Independent scalar electronics for writing fixtures, not a pass oracle.

    Tests assert literal RAW/flag/merge values for the small configurations.
    The demo's nominal noisy path intentionally has no random draw: a parser
    cannot authenticate an unrecorded random stream, and does not claim to.
    """
    if mode == "single":
        cfg = configuration
        maximum = 2 ** cfg["adc_bits"] - 1
        return {"raw": [min(max(math.floor(min(e, cfg["full_well_e"])
                                          * cfg["gain_dn_per_e"]
                                          + cfg["black_level_dn"] + .5), 0), maximum)
                        for e in expected]}
    cfg = configuration
    high, low, merged, flags = [], [], [], []
    for e in expected:
        charge = min(e, cfg["sensor"]["full_well_e"])
        physical = e >= cfg["sensor"]["full_well_e"]
        codes, estimates, usable = [], [], []
        flag = int(physical)
        for index, label in enumerate(("high_gain", "low_gain")):
            path = cfg[label]
            maximum = 2 ** path["adc_bits"] - 1
            rounded = math.floor(charge * path["gain_dn_per_e"]
                                 + path["black_level_dn"] + .5)
            code = max(0, min(maximum, rounded))
            flag |= (2 << (2 * index)) if rounded < 0 else 0
            flag |= (4 << (2 * index)) if rounded > maximum else 0
            good = 0 < code < maximum
            flag |= (32 << index) if good else 0
            codes.append(code)
            estimates.append((code - path["black_level_dn"]) / path["gain_dn_per_e"])
            usable.append(good)
        t = min(1, max(0, (estimates[1] - cfg["merge"]["start_e"])
                       / (cfg["merge"]["end_e"] - cfg["merge"]["start_e"])))
        weight = (1 - t) ** 2 * (1 + 2 * t)
        if not usable[0]:
            weight = 0
        elif not usable[1]:
            weight = 1
        estimate = weight * estimates[0] + (1 - weight) * estimates[1]
        if any(usable) and not physical:
            flag |= 128
        high.append(codes[0]); low.append(codes[1])
        merged.append(estimate); flags.append(flag)
    return dict(high_raw=high, low_raw=low, merged_electrons=merged, flags=flags)


def write_bundle(directory, *, mode, stage, configuration, geom, input_grid,
                 optical_grid, incident, optical, sampled, expected,
                 exposure=.5, seed=23, psf=None, kernel=None,
                 kernel_shape=(1, 1, 1), spatial_provenance=None):
    """Write explicitly supplied spatial arrays in plane-major row-major order."""
    directory.mkdir(parents=True)
    cfg = deepcopy(configuration)
    sensor = cfg if mode == "single" else cfg["sensor"]
    image = sensor["image_size"]
    wave = sensor["wavelength_nm"]
    bands = len(wave) if isinstance(wave, list) else 1
    records = {}

    def payload(key, name, kind, values, dimensions, units):
        code = {"float64": "d", "uint16": "H", "uint8": "B"}[kind]
        content = struct.pack(f"<{len(values)}{code}", *values)
        (directory / name).write_bytes(content)
        records[key] = dict(name=name, sha256=hashlib.sha256(content).hexdigest(),
                            byte_count=len(content), sample_type=kind,
                            shape=list(dimensions), units=units)

    payload("input_irradiance", "input.f64", "float64", incident,
            [len(input_grid["y_edges_m"]) - 1, len(input_grid["x_edges_m"]) - 1, bands], DENSITY)
    payload("optical_irradiance", "optical.f64", "float64", optical,
            [len(optical_grid["y_edges_m"]) - 1, len(optical_grid["x_edges_m"]) - 1, bands], DENSITY)
    payload("sampled_irradiance", "sampled.f64", "float64", sampled, [*image, bands], DENSITY)
    payload("expected_electrons", "expected.f64", "float64", expected, image, "electrons")
    if stage == "pre_psf":
        if psf is None:
            psf = dict(schema_version="1.0", origin_rc=[1, 1],
                       spacing_yx_m=[1, 1], wavelength_nm=[], boundary_policy="valid",
                       parameter_sources={"id001": "ARTIFICIAL-PSF"})
        payload("psf", "psf.f64", "float64", [1] if kernel is None else kernel,
                kernel_shape, "unitless weights")
    arrays = _readout_arrays(expected, cfg, mode)
    common = dict(schema_version="1.0", synthetic=True, authentic_arriraw=False,
                  exposure_s=exposure, seed=seed, runtime=deepcopy(ENGINE),
                  provenance=deepcopy(SOURCE), byte_order="little-endian")
    if mode == "single":
        payload("raw", "readout.raw", "uint16", arrays["raw"], image, "DN")
        nested = dict(common, format="ALEV4-SYNTHETIC-RAW", calibrated=False,
                      description="Artificial Python unit-test RAW",
                      height=image[0], width=image[1], byte_count=2 * math.prod(image),
                      sample_type="uint16", layout="row-major", units="DN",
                      cfa_pattern=sensor["cfa_pattern"], cfa_origin=[1, 1], sensor=cfg,
                      algorithm_version="phase1-baseline-v1", sampler_version="Poisson-Knuth-PTRS-v1")
    else:
        names = dict(high_raw="readout.high.raw", low_raw="readout.low.raw",
                     merged_electrons="readout.merged.f64", flags="readout.flags.u8")
        units = dict(high_raw="DN", low_raw="DN", merged_electrons="electrons", flags="bitmask")
        for key, values in arrays.items():
            kind = "uint16" if key.endswith("raw") else "uint8" if key == "flags" else "float64"
            payload(key, names[key], kind, values, image, units[key])
        nested = dict(common, format="ALEV4-SYNTHETIC-DUAL-GAIN", calibrated_alev4=False,
                      algorithm_version="phase2-dual-gain-v1", configuration=cfg,
                      image_size=image, input_units=DENSITY, array_order="row-major",
                      cfa_origin="top-left (1,1)", files=names, units=units)
    write_json(directory / "readout.json", nested)
    content = (directory / "readout.json").read_bytes()
    records["readout_metadata"] = dict(name="readout.json", sha256=hashlib.sha256(content).hexdigest(),
                                       byte_count=len(content), sample_type="utf8", shape=[], units="metadata")
    operations = (["optical_psf"] if stage == "pre_psf" else []) + [
        "area_overlap_average", "spectral_integration", mode + "_gain_readout"]
    meta = dict(format="ALEV4-SYNTHETIC-SPATIAL", schema_version="1.0",
                algorithm_version="phase3-spatial-v1", synthetic=True,
                calibrated_alev4=False, authentic_arriraw=False,
                byte_order="little-endian", array_order="plane-major-row-major",
                readout_mode=mode, input_stage=stage, geometry=deepcopy(geom),
                configuration=cfg, input_grid=deepcopy(input_grid), optical_grid=deepcopy(optical_grid),
                psf=[] if stage == "post_optics" else deepcopy(psf),
                operation_order={f"step{i:03d}": item for i, item in enumerate(operations, 1)},
                spatial_provenance={} if spatial_provenance is None else spatial_provenance,
                exposure_s=exposure, seed=seed, runtime=deepcopy(ENGINE), provenance=deepcopy(SOURCE),
                files=records)
    write_json(directory / "spatial.json", meta)
    return meta


def make_overlap_bundle(directory, mode="single"):
    """Two bins, nonuniform cells and crop parity, with literal rational answers.

    The crop is x=[1,3], y=[1,2]. Y averages are [25,35,45];
    X averages are [30,35]. Bin two is twice bin one. The crop starts
    on B,G of the full RGGB grid. Collection=.5 s * 1 m² * .5=.25.
    Thus B=(30*2*.75+60*3*1)/4=56.25 and
    G=(35*2*.5+70*3*.75)/4=48.125 electrons.
    """
    incident = [10, 20, 30, 40, 50, 60, 20, 40, 60, 80, 100, 120]
    g = grid([0, 1.5, 3, 4], [0, 1.5, 3])
    sensor = small_sensor()
    return write_bundle(directory, mode=mode, stage="post_optics",
                        configuration=sensor if mode == "single" else dual_config(sensor),
                        geom=geometry(), input_grid=g, optical_grid=g,
                        incident=incident, optical=incident, sampled=[30, 35, 60, 70],
                        expected=[56.25, 48.125])


def make_psf_bundle(directory, mode="single", *, shared=False):
    """Even 2x3 asymmetric convolution followed by an offset BGGR crop.

    For band one, reversal gives [13.125,26.25;210,420]. Its first
    coefficient is .25*32+.25*16+.125*4+.25*2+.125*1=13.125.
    Band two is an 8-unit impulse; the shared kernel gives [2,2;2,1],
    while its associated two-corner kernel gives [0,0;0,4]. These are
    handwritten results, so a correlation or an origin shift cannot agree.
    """
    incident = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048]
    incident += [0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0]
    kernel = [0, .25, .25, .125, .25, .125]
    optical = [13.125, 26.25, 210, 420] + ([2, 2, 2, 1] if shared else [0, 0, 0, 4])
    expected = [6.421875, 7.6875, 53.625, 52.875] if shared else [4.921875, 6.5625, 52.5, 54]
    if not shared:
        kernel += [.5, 0, 0, 0, 0, .5]
    psf = dict(schema_version="1.0", origin_rc=[1, 2], spacing_yx_m=[1, 1],
               wavelength_nm=[] if shared else [500, 600], boundary_policy="valid",
               parameter_sources={"id001": "ARTIFICIAL-PSF"})
    sensor = small_sensor(image=(2, 2))
    return write_bundle(directory, mode=mode, stage="pre_psf",
                        configuration=sensor if mode == "single" else dual_config(sensor),
                        geom=geometry(roi=(2, 2, 2, 2)),
                        input_grid=grid([0, 1, 2, 3, 4], [0, 1, 2, 3]),
                        optical_grid=grid([1, 2, 3], [1, 2, 3]),
                        incident=incident, optical=optical, sampled=optical, expected=expected,
                        psf=psf, kernel=kernel, kernel_shape=(2, 3, 1 if shared else 2))


def make_identity_bundle(directory, values=(1,), mode="single", stage="pre_psf"):
    sensor = small_sensor(image=(1, len(values)), pattern="RGGB")
    sensor.update(wavelength_nm=550, bin_width_nm=1, qe=[1, 1, 1],
                  fill_factor=1, gain_dn_per_e=1, black_level_dn=0)
    g = grid(list(range(len(values) + 1)), [0, 1])
    return write_bundle(directory, mode=mode, stage=stage,
                        configuration=sensor if mode == "single" else dual_config(sensor),
                        geom=geometry(full=(1, len(values)), roi=(1, 1, 1, len(values))),
                        input_grid=g, optical_grid=g, incident=values, optical=values,
                        sampled=values, expected=values, exposure=1)


def _demo_sensor(image, *, dual=False, crop=False):
    return dict(schema_version="1.0", image_size=list(image), wavelength_nm=[500, 600],
                bin_width_nm=[20, 20], qe=[[.1, .8, .2], [.7, .2, .05]],
                pixel_pitch_m=6e-6, fill_factor=.8, full_well_e=30000,
                read_noise_e=3 if dual else 0, gain_dn_per_e=.5,
                black_level_dn=64, adc_bits=16, cfa_pattern="BGGR" if crop else "RGGB",
                shot_noise=dual)


def _charge_from_planes(planes, image, sensor, exposure):
    """Spectral dot products only; spatial answers are supplied analytically."""
    height, width = image
    scale = exposure * sensor["pixel_pitch_m"] ** 2 * sensor["fill_factor"]
    result = []
    for r in range(height):
        for c in range(width):
            channel = "RGB".index(sensor["cfa_pattern"][2 * (r % 2) + c % 2])
            terms = [plane[r * width + c] * (qe[channel] * bin_width)
                     for plane, qe, bin_width in zip(planes, sensor["qe"], sensor["bin_width_nm"])]
            result.append(math.fsum(terms) * scale)
    return result


def _flatten(planes):
    return [value for plane in planes for value in plane]


def _analytic_demo(directory, name, index):
    p = 6e-6
    full = (7, 9) if name == "shifted_impulse" else (8, 10) if name == "crop_cfa" else (6, 8)
    roi = (2, 2, 5, 7) if name == "crop_cfa" else (1, 1, *full)
    geom = geometry(full, roi, p, sources=("ASSUMED-GENERIC-GEOMETRY", "ASSUMED-CFA-ORIGIN"))
    half = name == "sinusoid"
    step, factor = (p / 2, 2) if half else (p, 1)
    halo = (1, 0, 1, 1) if name == "shifted_impulse" else (1, 1, 1, 1) if name in (
        "flat_binomial", "edge", "sinusoid", "dual_spatial") else (0, 0, 0, 0)
    xe = [i * step for i in range(-halo[2], full[1] * factor + halo[3] + 1)]
    ye = [i * step for i in range(-halo[0], full[0] * factor + halo[1] + 1)]
    crop = name == "crop_cfa"
    sensor = _demo_sensor(roi[2:], dual=name == "dual_spatial", crop=crop)
    frequency = 1 / (8 * p)

    def field(x, y, r, c, *, optical=False):
        if name == "flat_binomial":
            return 1e14
        if name == "shifted_impulse":
            if not optical:
                return 2e15 if (r, c) == (3, 4) else 0
            weights = {(2, 3): .25, (2, 4): .25,
                       (3, 2): .125, (3, 3): .25, (3, 4): .125}
            return 2e15 * weights.get((r, c), 0)
        if name == "edge":
            return 1e14 * ([.2, .2, .2, .4, .8, 1, 1, 1][c]
                          if optical else .2 + .8 * (x >= 4 * p))
        if name == "sinusoid":
            z = frequency * step
            attenuation = math.cos(math.pi * z) ** 2 if optical else 1
            return 1e14 * (1 + .4 * attenuation * math.sin(2 * math.pi * frequency * x)
                          * math.sin(math.pi * z) / (math.pi * z))
        if name == "dual_spatial":
            return 1e14 * (2 + 25 * x / (full[1] * p))
        return 1e14 * (.25 + x / (full[1] * p) + .5 * y / (full[0] * p))

    def planes_for(x, y, *, optical=False):
        base = [field((a + b) / 2, (d + e) / 2, r, c, optical=optical)
                for r, (d, e) in enumerate(zip(y, y[1:]))
                for c, (a, b) in enumerate(zip(x, x[1:]))]
        return [base, [v * .6 for v in base]]

    input_planes = planes_for(xe, ye)
    identity = name == "identity_single"
    if identity or crop:
        ox, oy = xe, ye
        optical_planes = input_planes
    else:
        ox = xe[1:-1]
        oy = ye[1:] if name == "shifted_impulse" else ye[1:-1]
        optical_planes = planes_for(ox, oy, optical=True)
    if crop:
        width = full[1]
        sampled_planes = [[plane[r * width + c] for r in range(1, 6) for c in range(1, 8)]
                          for plane in optical_planes]
    elif half:
        # Four equal quarter-footprints; this is an independent exact area
        # rule, while the verifier separately checks the continuous sinc oracle.
        width = len(ox) - 1
        sampled_planes = [[math.fsum(plane[(2 * r + dy) * width + 2 * c + dx]
                                    for dy in (0, 1) for dx in (0, 1)) / 4
                           for r in range(full[0]) for c in range(full[1])]
                          for plane in optical_planes]
    else:
        sampled_planes = optical_planes
    expected = _charge_from_planes(sampled_planes, roi[2:], sensor, .01)
    kernel = [1] if identity else [0, .25, .25, .125, .25, .125] if name == "shifted_impulse" else [
        .0625, .125, .0625, .125, .25, .125, .0625, .125, .0625]
    kernel_shape = (1, 1, 1) if identity else (2, 3, 1) if name == "shifted_impulse" else (3, 3, 1)
    origin = [1, 1] if identity else [1, 2] if name == "shifted_impulse" else [2, 2]
    psf = dict(schema_version="1.0", origin_rc=origin, spacing_yx_m=[step, step],
               wavelength_nm=[], boundary_policy="valid",
               parameter_sources={"id001": "ASSUMED-DISCRETE-PSF"})
    mode = "dual" if name == "dual_spatial" else "single"
    meta = write_bundle(directory, mode=mode, stage="post_optics" if crop else "pre_psf",
                        configuration=dual_config(sensor, demo=True) if mode == "dual" else sensor,
                        geom=geom, input_grid=grid(xe, ye), optical_grid=grid(ox, oy),
                        incident=_flatten(input_planes), optical=_flatten(optical_planes),
                        sampled=_flatten(sampled_planes), expected=expected,
                        exposure=.01, seed=8301 + index, psf=psf, kernel=kernel, kernel_shape=kernel_shape)
    return meta, expected


def _iset_shaped_demo(directory):
    """A positive affine field in the required format, not actual ISET output."""
    p = 5e-6
    sensor = dict(schema_version="1.0", image_size=[16, 16],
                  wavelength_nm=list(range(400, 701, 10)), bin_width_nm=[10] * 31,
                  qe=[[.5, .5, .5] for _ in range(31)], pixel_pitch_m=p,
                  fill_factor=1, full_well_e=1e8, read_noise_e=0, gain_dn_per_e=1,
                  black_level_dn=64, adc_bits=16, cfa_pattern="RGGB", shot_noise=False)
    geom = geometry((16, 16), (1, 1, 16, 16), p, (-40e-6, -40e-6), ("ISET-PINNED-SPATIAL",))
    spacing = 6.5e-6
    # Partition at every target edge plus the twelve internal native optical
    # knots, so no partial source cell is mistaken for an affine integral.
    edges = sorted([-40e-6 + i * p for i in range(17)]
                   + [(i - 5.5) * spacing for i in range(12)])
    input_plane = [1e14 * (1 + ((x1 + x2) / 2 + (y1 + y2) / 4) / .0002)
                   for y1, y2 in zip(edges, edges[1:]) for x1, x2 in zip(edges, edges[1:])]
    # The average of an affine field over each complete target pixel is its
    # value at the center, independent of how the source cells partition it.
    sampled_plane = [1e14 * (1 + (-40e-6 + (c + .5) * p
                                + (-40e-6 + (r + .5) * p) / 2) / .0002)
                     for r in range(16) for c in range(16)]
    incident, sampled = input_plane * 31, sampled_plane * 31
    expected = _charge_from_planes([sampled_plane] * 31, (16, 16), sensor, .001)
    info = dict(adapter="restricted_iset_spatial_fixture", fixture_kind="checker",
                input_native_semantics="point_samples", reconstruction="bilinear_between_native_optical_points",
                cell_conversion="four_corner_mean_with_optical_knots_and_sensor_edges", oi_padding="mean",
                offaxis_method="skip", reference_source="ISET-PINNED-SPATIAL", native_point_units=DENSITY,
                optics_already_applied=True, extra_psf_applied=False, scene_hfov_degrees=3,
                native_point_size=[40, 40, 31], native_point_spacing_yx_m=[spacing, spacing],
                native_point_bounds_xy_m=[[-19.5 * spacing] * 2, [19.5 * spacing] * 2])
    meta = write_bundle(directory, mode="single", stage="post_optics", configuration=sensor,
                        geom=geom, input_grid=grid(edges, edges), optical_grid=grid(edges, edges),
                        incident=incident, optical=incident, sampled=sampled, expected=expected,
                        exposure=.001, seed=8308, spatial_provenance=info)
    return meta, expected


def make_numerical_report(checker=None):
    """Snapshot the required report structure using explicitly artificial data."""
    common = dict(schema_version="1.0", status="passed", calibrated_alev4=False,
                  runtime=ENGINE["name"], runtime_version=ENGINE["version"], provenance=deepcopy(SOURCE))
    previous1 = dict(deepcopy(common), phase=1, phase1_passed=True)
    for name in PHASE1_GATES:
        previous1[name] = dict(status="passed", passed=True, test_count=1)
    for name in ("first_exposure", "second_exposure"):
        previous1["iset"][name] = dict(status="passed", max_relative_error=0,
                                       relative_tolerance=5e-5)

    def suite(name):
        return dict(status="passed", passed=True, test_count=1,
                    tests=[dict(name="artificial_" + name, status="passed", passed=True)])

    previous2 = dict(deepcopy(common), phase=2, phase2_passed=True,
                     phase1_required=True, phase1=previous1)
    previous2.update({name: suite(name) for name in PHASE2_GATES})
    report = dict(deepcopy(common), phase=3, phase3_passed=True,
                  phase2_required=True, phase2=previous2)
    report.update({name: suite(name) for name in PHASE3_GATES})
    checker = [100.0] * 256 if checker is None else checker
    fixtures = {}
    for name in ("uniform", "ramp", "checker", "edge"):
        values = checker if name == "checker" else [100.0] * 256
        matrix = [list(values[start:start + 16]) for start in range(0, 256, 16)]
        fixtures[name] = dict(fixture_kind=name, image_size=[16, 16], input_stage="post_optics",
                              extra_psf_applied=False, provenance=deepcopy(SOURCE),
                              reference_expected_electrons=matrix, native_expected_electrons=deepcopy(matrix),
                              native_relative_error=0, project_relative_error=0,
                              native_samples_per_axis=[1, 3, 9, 27],
                              source_refinement_factors=[1, 2, 4, 8, 16],
                              native_relative_errors=[.02, .002, .0002, 0],
                              source_refinement_relative_errors=[.03, .003, .0003, .00003, 0],
                              oi_spatial_variation=0 if name == "uniform" else .2,
                              native_spacing_yx_m=[10e-6, 10e-6])
    report["iset_spatial"]["metrics"] = dict(synthetic=True, calibrated_alev4=False,
                                               native_matlab_executed=False, fixtures=fixtures)
    return report


def make_outputs(root):
    """Write all 66 artificial demo files and a complete artificial report."""
    demo = root / "demo"
    validation = root / "validation"
    demo.mkdir(parents=True)
    validation.mkdir()
    frames = []
    checker = None
    for index, name in enumerate(DEMO_NAMES):
        if name == "iset_checker":
            meta, expected = _iset_shaped_demo(demo / name)
            checker = expected
        else:
            meta, expected = _analytic_demo(demo / name, name, index)
        sensor = meta["configuration"] if meta["readout_mode"] == "single" else meta["configuration"]["sensor"]
        frames.append(dict(name=name, readout_mode=meta["readout_mode"], input_stage=meta["input_stage"],
                           image_size=sensor["image_size"], seed=meta["seed"], exposure_s=meta["exposure_s"],
                           minimum_expected_e=min(expected), maximum_expected_e=max(expected),
                           sum_expected_e=math.fsum(expected)))
    summary = dict(schema_version="1.0", phase=3, synthetic=True, calibrated_alev4=False,
                   demo_complete=True, iset_included=True, frame_count=8, frames=frames,
                   runtime=deepcopy(ENGINE), provenance=deepcopy(SOURCE))
    write_json(demo / "phase3-demo-summary.json", summary)
    report = make_numerical_report(checker)
    write_json(validation / "phase3-validation.json", report)
    return report, summary
