# Phase 1 usage

Phase 1 is implemented; full acceptance is pending. The first core/ISETCam tests have run successfully in GNU Octave 8.4.0. MATLAB execution is not yet verified. All examples below describe a generic, uncalibrated, single-gain sensor, not an ALEV4-equivalent capture.

## Prerequisites and dependency checks

Run commands from the repository root. Use Python 3.10 or newer for the validation utilities. Full integration needs the two pinned submodule checkouts and GNU Octave with its `image` package, or MATLAB with the Image Processing Toolbox. The standalone numerical core uses no ISET or Statistics Toolbox functionality. CI installs the Octave statistics package as well, but the custom Poisson sampler does not require it.

```bash
git submodule update --init --recursive --depth 1
python3 scripts/verify_submodules.py --require-checkout
python3 -m unittest discover -s scripts/tests -v
```

The strict dependency check rejects uninitialized checkouts, changed pins, wrong origins, or tracked/non-ignored untracked changes. Without `--require-checkout`, the script checks declarations/gitlinks only. Do not update submodules with `--remote` as a routine setup step: that changes the scientific dependency versions. Intentional updates require new integration evidence and an explicitly reviewed pin change.

`setup_project(true)` checks that key ISET functions resolve to the intended submodule, rather than an unrelated ISET installation elsewhere on the path. A conflict must be resolved, not silently accepted.

## Full Octave acceptance run

Choose a fresh output root, such as `outputs/run-01`. Use a different name for another run. Generated outputs are excluded from Git.

```bash
octave --no-gui --quiet --eval "addpath('matlab'); report=run_phase1_tests('outputs/run-01/validation',true); assert(report.phase1_passed);"
octave --no-gui --quiet --eval "addpath('matlab'); setup_project(true); phase1_demo('outputs/run-01/demo',true);"
octave --no-gui --quiet --eval "addpath('matlab'); setup_project(true); phase1_demo('outputs/run-01/demo-repeat',true);"
python3 scripts/verify_phase1_artifacts.py outputs/run-01 --expected-commit "$(git rev-parse HEAD)" --compare-dir outputs/run-01/demo-repeat
python3 scripts/verify_submodules.py --require-checkout
```

The two demo commands run in separate processes. The independent Python checker validates the full report, ten frame triplets, analytic exposure-bracket expectations, and matching same-runtime files. A report alone is not a substitute for these artifact checks. CI uploads the validation report and primary demo directory; inspect the job conclusion as well as any uploaded failure artifacts.

## MATLAB commands

From MATLAB's Current Folder at the repository root:

```matlab
addpath('matlab');
report = run_phase1_tests('outputs/matlab-run-01/validation', true);
assert(report.phase1_passed);
summary = phase1_demo('outputs/matlab-run-01/demo', true);
assert(summary.demo_complete && summary.frame_count == 10);
```

For batch execution, the corresponding command is:

```bash
matlab -batch "addpath('matlab'); report=run_phase1_tests('outputs/matlab-run-01/validation',true); assert(report.phase1_passed);"
```

These are usage instructions, not a claim of a tested MATLAB release. Record the actual MATLAB version and toolboxes when establishing MATLAB acceptance. Do not compare MATLAB and Octave noisy frames for bit identity; compare each runtime's output with a repeated run of that same runtime/version.

## Core-only development

The core can run without initialized ISET submodules:

```matlab
addpath('matlab');
setup_project(false);
report = run_phase1_tests('outputs/core-01/validation', false);
assert(strcmp(report.status, 'core_only'));
assert(~report.phase1_passed);
summary = phase1_demo('outputs/core-01/demo', false);
```

This runs the standalone numerical/I/O gates and creates nine generic demo frames. It explicitly omits ISETCam integration and **does not pass Phase 1**. The full artifact verifier is intended for a complete ten-frame run, not for this development subset.

## Minimal sensor API

```matlab
addpath('matlab');
setup_project(false);
cfg = alev4.createBaselineSensor(struct( ...
    'image_size', [32 48], 'cfa_pattern', 'RGGB'));
irradiance = alev4.createFixture('flat', cfg, 1e13);
result = alev4.simulateExposure(irradiance, cfg, 0.01, 1234);

mkdir('outputs/example-01');
files = alev4.exportSyntheticRaw(result, cfg, 'outputs/example-01/flat');
[raw, metadata] = alev4.readSyntheticRaw('outputs/example-01/flat');
assert(isequal(raw, result.raw_dn));
```

`simulateExposure` requires a finite, nonnegative `H × W × K` photon-irradiance array. The third dimension matches `cfg.wavelength_nm`; a single spectral bin uses an ordinary `H × W` array. An explicit integer seed in `[0, 2^32-1]` is required. `alev4.energyToPhotons(energy_irradiance, wavelength_nm)` converts energy density in W/(m² nm) to the accepted photon density.

### Configuration contract

| Field | Meaning / constraint |
| --- | --- |
| `image_size` | Positive integer `[height width]`; odd/nonsquare arrays supported |
| `wavelength_nm`, `bin_width_nm` | Increasing positive bin centers and explicit positive, nonoverlapping widths, in nm |
| `qe` | `K × 3` effective R/G/B efficiencies in `[0,1]`, including CFA transmission but excluding fill factor |
| `pixel_pitch_m`, `fill_factor` | Square-pixel pitch in metres; collection area is `pixel_pitch_m^2 * fill_factor` |
| `full_well_e`, `read_noise_e` | Positive physical capacity and nonnegative Gaussian RMS noise, in electrons |
| `gain_dn_per_e`, `black_level_dn` | Positive DN/electron gain and an offset within the ADC range |
| `adc_bits` | Integer 1–16; storage remains `uint16` |
| `cfa_pattern` | `RGGB`, `BGGR`, `GRBG`, or `GBRG`; origin is the top-left sample `(1,1)` |
| `shot_noise` | Logical `true` or `false`, not a numeric flag |
| `schema_version` | `'1.0'` |

Unknown fields are errors. Changing the wavelength grid requires matching bin-width and QE arrays. Inputs are integrated with explicit rectangular bins, not `trapz`, and no additional `1e-9` factor belongs in the per-nm integration. The metres conversion is used separately for photon energy.

The Poisson sampler supports expected means through `1e9` electrons. Unsupported overflow and a positive collection factor that underflows to zero raise errors. These are explicit numerical limits, not physical statements about a real camera.

### Retained outputs and readout order

`result.expected_incident_photons` and `result.expected_electrons` are continuous, unclipped expectations. `collected_electrons` is the sampled charge; `charge_electrons` is full-well-limited charge. `read_electrons` preserves signed read noise. `raw_dn` is gain/offset/rounding/ADC-clipped `uint16` data.

Read noise is added **after** full-well clipping and is not clipped again at full well. Negative read noise is retained until ADC processing, preventing a premature dark-frame bias. `full_well_saturated` marks collected charge at or above full well; `adc_low_clipped` and `adc_high_clipped` mark rounded codes outside the ADC range. They are different conditions.

## ISETCam integration API and limitations

```matlab
addpath('matlab');
setup_project(true);
[result, cfg, comparison] = alev4.isetBaseline(73, 0.001);
```

This creates an actual ISETCam uniform spectral scene, computes optics, and compares its noiseless Bayer output with independent integration. The adapter validates the uniform field before using its spectrum on the sensor grid. It is **not an arbitrary-image or arbitrary-scene import/resampling function**. The generic ISET QE, ideal pixel, and disabled off-axis/vignetting terms are deliberate test choices, not ALEV4 characterizations.

Exposure must be positive for this adapter because ISETCam treats zero exposure as auto-exposure. Test exact zero exposure in `simulateExposure` instead. The comparison uses continuous volts/conversion-gain values, not ISETCam's rounded electron getter. ISETHdrsensor is linked for future research but not used in this execution path.

## Artifact format and interpretation

Every exported frame has:

- `name.raw`: headerless row-major, little-endian `uint16`; exactly `height * width * 2` bytes.
- `name.json`: format/schema, synthetic and uncalibrated labels, dimensions, CFA origin/pattern, DN units, complete sensor configuration, exposure, seed, runtime, and observed repository/dependency HEADs.

Exports and imports enforce a maximum of **100 million pixels** and **2,000,000 UTF-8 manifest bytes**. The writer refuses existing `.raw` or `.json` destinations and cleans its ordinary failed temporary writes. Publication of two files is not a transactional filesystem operation; concurrent writers to the same base name are unsupported.

The demo additionally writes `name.pgm`, a fixed-ADC-scale grayscale preview of the Bayer mosaic, and `phase1-demo-summary.json`. Its four fixtures are `black`, `flat`, `ramp`, and `checker`. Five flat-field brackets use exposure multipliers `0.25`, `0.5`, `1`, `2`, and `4`; the full run adds `iset_scene`. Upper brackets exercise clipping. Preview brightness, spatial variance, and a synthetic RAW extension do not establish camera color quality, temporal noise calibration, exposure latitude, or ARRIRAW compatibility.

Full acceptance requires a passing current workflow, its numerical report, and independently verified artifacts. Real-camera calibration remains Phase 6.
