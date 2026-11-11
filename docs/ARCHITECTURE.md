# Architecture and boundaries

The main repository is the **integration and ALEV4-specific implementation layer**. It does not fork, rewrite or vendor the full history of ISETCam or ISETHdrsensor.

```text
Spectral scene radiance
  -> lens, OLPF and spectral irradiance (ISETCam / optional ISET3d)
  -> ALEV4-inspired CFA/pixel spectral QE and electron accumulation (future work)
  -> high-gain + low-gain read paths (future work)
  -> HDR merge and sensor ADC / synthetic mosaic RAW (future work)
  -> demosaic and color characterization (future work)
  -> ARRI Wide Gamut 4 / LogC4-compatible encoding (future work)
```

## Dependency responsibilities

- `third_party/isetcam`: physically motivated scene, optical image, sensor, pixel, and imaging utilities. It is a MATLAB toolbox; it does not supply an ARRI ALEV4 preset.
- `third_party/isethdrsensor`: useful HDR architecture research and test scenes. Its examples cover designs such as RGBW and multiple exposures, **not ARRI's specific dual-gain readout**. Upstream examples may require ISET3D-tiny and external data/neural network packages; they are not bundled.
- `matlab/`: small local initialization glue now; future ALEV4-specific code should live here rather than editing submodules.

## Design rules

1. Model exposure and sensor noise in physical units (photons, electrons, volts, digital numbers).
2. Make assumptions explicit and distinguish ARRI-published parameters from fitted or hypothetical ones.
3. Keep random seeds and test exposures reproducible; retain the same noise realization when benchmarking algorithm changes.
4. Keep the sensor model separate from color encoding, display rendering, subjective texture, and artistic LUTs.
5. Avoid claiming bit-perfect, sensor-identical, or ARRIRAW-compatible output without evidence.
6. Keep submodules pinned to reviewed commits; updates should be explicit, tested, and reversible.
7. Store real-camera reference data under an excluded `data/raw/` tree or use external links with license review, never auto-commit copyrighted recordings.

## Scope exclusions

No firmware emulation, MIPI CSI-2 hardware emulation, camera UI, lens-mount mechanics, or ARRI camera control protocol is implemented here. Hardware or bitstream emulation would be separate workstreams.
