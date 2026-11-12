# Architecture and boundaries

The main repository is the **integration and future ALEV4-specific implementation layer**. It does not fork, rewrite, or vendor the full history of ISETCam or ISETHdrsensor. Phase 1 currently provides a generic single-gain baseline; full acceptance remains pending the expanded verification run.

## Implemented Phase 1 path

1. Obtain sensor-plane spectral photon irradiance from a controlled fixture or the restricted ISETCam uniform-scene adapter.
2. Integrate explicit spectral bins using effective RGB QE, photosite area, fill factor, and exposure.
3. Sample photoelectrons once with a Poisson distribution, unless shot noise is disabled.
4. Clip charge at full well, then add signed Gaussian read noise.
5. Apply DN/electron gain and black-level offset, round, then clip to the ADC range.
6. Export the Bayer mosaic with its synthetic RAW metadata, or inspect retained intermediate arrays.

The core accepts irradiance in photons/(m² s nm), **not scene radiance, JPEG/sRGB values, or a rendered image**. Samples are bin-average densities, integrated using `sum(density .* QE .* bin_width_nm)`. `energyToPhotons` is an explicit, separate energy-to-photon conversion. Fill factor is excluded from effective QE and applied once through collection area.

Continuous expectations, sampled charge, full-well-limited charge, signed analog readout, and integer RAW remain distinct outputs. This lets tests distinguish a physical clipping error from an ADC or noise error.

## Dependency responsibilities

- `third_party/isetcam`: physically motivated scene, optical-image, sensor, pixel, and imaging utilities. The Phase 1 adapter executes `sceneCreate`, `oiCompute`, and a noiseless Bayer `sensorCompute`. It does not supply an ARRI ALEV4 preset.
- `third_party/isethdrsensor`: HDR architecture research and test scenes, linked but **not executed** by this baseline. Its examples concern designs such as RGBW and multiple exposures, not ARRI's specific dual-gain readout. Advanced upstream examples may require ISET3D-tiny and external datasets/packages, which are not bundled.
- `matlab/+alev4/`: the independently testable numerical core, synthetic RAW I/O, provenance observation, and ISETCam adapter. New project behavior belongs here rather than in modified submodules.
- `matlab/tests/` and `scripts/`: numerical acceptance and independent artifact/dependency checks. Python validation does not implement a second production sensor model.

## ISETCam adapter boundary

`alev4.isetBaseline(seed, exposure_s)` is a deliberately small **uniform-field integration fixture**, not a general arbitrary-scene importer. It computes optics, checks spatial uniformity, imports actual generic effective QE/filter ordering, and maps that uniform irradiance onto a 16 × 16 sensor. It disables off-axis illumination loss and sensor vignetting for the comparison.

The independent expectations are compared against analog volts divided by conversion gain. ISETCam's convenience electron getter rounds values and therefore is unsuitable for a fractional-electron reference. The relative-error tolerance permits upstream single-precision roundoff, not an arbitrary visual match.

Nonuniform optical images require separately validated resampling/spatial integration. This adapter does not claim to implement that extension, an ALEV4 optical low-pass filter, or a calibrated lens/MTF model.

## Design rules

1. Model exposure and sensor noise in physical units (photons, electrons, volts, digital numbers).
2. Make assumptions explicit and distinguish ARRI-published parameters from fitted or hypothetical ones.
3. Keep explicit seeds and test exposures reproducible within the recorded runtime/version; preserve caller RNG state. Do not promise cross-runtime bit-identical streams.
4. Keep the sensor model separate from color encoding, display rendering, subjective texture, and artistic LUTs.
5. Avoid claiming bit-perfect, sensor-identical, or ARRIRAW-compatible output without evidence.
6. Keep submodules pinned to reviewed commits; updates should be explicit, tested, and reversible.
7. Store real-camera reference data under an excluded `data/raw/` tree or use external links with license review, never auto-commit copyrighted recordings.
8. Treat unknown configuration fields, missing integration dependencies, malformed RAW metadata, and failed numerical assertions as errors, not successful fallbacks.
9. Distinguish observed Git revisions from verified source cleanliness. The strict dependency checker establishes checkout/pin agreement; provenance metadata alone does not.

## Planned later layers

Independent simultaneous high/low-gain paths and HDR merge belong to Phase 2. ALEV4-inspired geometry and optics, structured readout noise, demosaic/color characterization, and AWG4/LogC4 encoding remain separate later work. The Phase 1 RAW writer is an explicitly synthetic interchange format, not an ARRIRAW encoder.

## Scope exclusions

No firmware emulation, MIPI CSI-2 hardware emulation, camera UI, lens-mount mechanics, or ARRI camera control protocol is implemented here. Hardware or bitstream emulation would be separate workstreams.
