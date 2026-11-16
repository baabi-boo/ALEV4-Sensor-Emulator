# Working on ALEV4 Sensor Emulator

## Start with the recorded state

Read `README.md`, `docs/ROADMAP.md`, `docs/ARCHITECTURE.md`, and the design,
usage, and completion documents for the phase being changed. Inspect the
current branch, worktree, dependency pins, and latest CI result before choosing
work. A roadmap target is not evidence that its implementation exists. Preserve
other contributors' changes and coordinate ownership when agents share files.

## Scientific and numerical contract

- Keep photons, electrons, seconds, spectral-bin widths, and digital numbers
  explicit. Preserve the distinction between expected charge, sampled charge,
  stored charge, signed readout, and quantized output.
- Simultaneous dual gain uses one exposure, one sampled photocharge array, and
  one physical full-well limit. Branch only into separate readout electronics.
  Shared shot noise and independent downstream read noises must remain testable.
- Reconstruct merged values from the observed readouts and their configuration.
  Do not use inaccessible noiseless expectations to improve a reported merge.
  Separate ADC clipping, conservative rail validity, and physical saturation.
- Keep explicit seeds, restore caller RNG state on success and failure, and
  state the runtime/version governing reproducibility. Do not promise identical
  random streams across MATLAB and Octave without measured evidence.
- Reject malformed configuration, unsupported numeric ranges, missing required
  dependencies, and failed assertions. Do not silently replace a required gate
  with a fallback or report a skipped test as passed.

## Spatial model contract

- Keep geometry separate from the existing readout schemas. Use one-based
  full-grid ROI coordinates, metres, and crop-adjusted Bayer parity; validate
  already bound readouts instead of silently repairing conflicting fields.
- Spatial inputs are cell-average spectral photon irradiance. Conservative
  sampling returns density, so pixel area, fill factor, exposure, QE and bin
  widths remain applied once by the existing spectral integration stage.
- Filter spectral planes before the CFA. Require explicit PSF sampling,
  origin, spectral association and complete support. Post-optics ISET output
  receives no implicit second PSF; native point samples require a declared
  reconstruction before they become cell averages.
- Preserve physical coordinates through serialization. Use the Phase 3
  numeric-token reader for spatial manifests; never conceal decoder rounding
  by relaxing coverage, snapping edges or renormalizing missing support.
- Keep published Open Gate geometry, assumed CFA/QE/PSF parameters and real
  measurements distinct. The geometry profile does not establish total die
  dimensions, camera crop origins, measured optical response or calibration.
- Follow the Phase 3 usage/artifact contracts and preserve all earlier phase
  gates. Core-only numerical or demo results must remain visibly incomplete.

## Structured-noise contract

- Keep the Phase 4 noise model separate from sensor and geometry schemas.
  Supplied full-grid maps define the persistent realization; a label or seed
  is not a substitute for the actual map values. Preserve scalar-uniform maps,
  one-based ROI identity and the declared assumed parameter classification.
- Apply achromatic PRNU to the photoelectron expectation and dark rate to
  exposure seconds. Sample their separately controlled components before one
  common physical well; add shared/path electronic components afterward.
  Do not use retained maps, expectations or component draws to correct the
  observed-channel merge.
- Preserve direct legacy results for valid disabled calls, and the documented
  isolated component streams for enabled calls. Validate represented numeric
  seeds in binary64 before bound comparisons. Independent frames, absolute
  indices and metadata-only EI have explicit contracts; additional temporal,
  temperature, EI or spectral models require their own design and evidence.
- Honor preallocation and retained-sample bounds. Demonstrations and acceptance
  use small fixtures; neither a supported geometry nor a sample-count limit is
  evidence of full-frame memory or throughput performance.
- Use the distinct structured bundle identity. Preserve every retained value,
  type, shape, unit, stage and fixed-map association. The packed payload uses
  C row-major order, unlike the earlier spatial plane-major format. Verify
  actual bytes and deterministic semantics independently; hashes alone cannot
  validate a modified result. Readers do not authenticate stochastic PRNG origin.
- Preserve all nine required Phase 4 numerical suites and every Phase 1–3 gate.
  Keep development and fixture-control results separate from clean-source
  release acceptance. Update source, usage, artifact and completion records
  when the implemented contract changes.

## Boundaries and dependencies

This is an independent, uncalibrated research model. Label assumed parameters
and synthetic artifacts. Do not claim sensor identity, measured ARRI dynamic
range, proprietary calibration, or genuine ARRIRAW support without the required
independent evidence. Keep sensor physics separate from display/color transforms.

Keep ISETCam and ISETHdrsensor as pinned, separately maintained submodules.
Implement project behavior in this repository; do not edit, update, or vendor
upstream dependencies accidentally. An intentional pin update needs documented
purpose and executed compatibility checks. Use
`python3 scripts/verify_submodules.py --require-checkout` before and after full
acceptance. Observed Git HEAD metadata alone does not prove source cleanliness.

## Verification and evidence

Preserve earlier phase acceptance gates when adding a later phase. Test changed
physics with independent analytical expectations and statistically justified
tolerances, including error paths and relevant boundary cases. For exported
artifacts, verify actual bytes, shape, order, units, metadata, and reconstruction;
do not trust the producer's success flags alone. Test repeatability in separate
processes when that is an acceptance requirement.

Record exact commands, runtime, tested source revision, dependency revisions,
results, and any missing execution. Invalidate stale successful reports before
rerunning tests. Mark a phase complete only after its required gates execute and
their evidence is retained. Native MATLAB compatibility remains unverified until
MATLAB itself runs the relevant gates.

## Handoff and delivery

Update the roadmap, usage/design documentation, and completion or progress report
with what changed, what passed, what remains uncertain, and the next concrete
step. Keep agent ledgers factual: count actual delegated tasks and record their
contributions; do not invent execution, reviewers, or passes.

Make focused, reviewable commits and inspect the final diff for accidental data,
generated outputs, dependency edits, or credentials. Keep raw camera/calibration
datasets in their excluded directories unless explicitly authorized for lawful
distribution. Respect the user's requested branch and existing authorization;
do not request permission again for work already authorized. Before pushing,
check for upstream changes, integrate them without discarding work, and report
the resulting commit and observed CI outcome. If a required gate cannot run,
state exactly what is missing and leave the completion claim open.
