# Phase 3 parameter source register

This register separates manufacturer statements, arithmetic derived from them,
and choices made by this independent model. It supplies no measured sensor QE,
noise, optical transfer, or calibration data. Retrieved 2026-11-13 (America/Halifax).

## Published geometry

**Record `ARRI-A35-GEOMETRY`** — ARRI, *ALEXA 35*, Technical Data,
sections “Sensor Maximum Number of Photosites and Size”, “Photosite Pitch”,
“Sensor Active Image Area (photosites)”, and “Sensor Type”. This web specification has no
revision identifier displayed in those sections.

Source: <https://www.arri.com/en/cine-systems/cine-cameras/legacy-cine-cameras/alexa-35>

| Quantity | Published value | Classification and scope |
| --- | --- | --- |
| Open Gate photosites | 4608 columns by 3164 rows | Published active/readout dimensions |
| Photosite pitch | 6.075 micrometres | Published nominal pitch; measurement uncertainty not supplied |
| Sensor size | 27.99 by 19.22 millimetres | Published rounded dimensions; not a second geometry input |
| Filter arrangement | Bayer | Published type; top-left color order is not established here |

**Record `DERIVED-A35-EXTENT`** — multiplication of published count by nominal
pitch gives 27.9936 by 19.2213 mm. Rounding those to 0.01 mm reproduces the
published size. This checks displayed precision; it is not a physical tolerance
or uncertainty estimate. The profile's full grid models this Open Gate active
area, not unreported optical-black pixels or total die dimensions. Smaller
camera modes and their hardware crop origins are not inferred.

## Explicit model assumptions

| Record | Meaning |
| --- | --- |
| `ASSUMED-GENERIC-GEOMETRY` | Small generic grid, square 6 micrometre pitch, origin at its outer upper-left corner |
| `ASSUMED-CFA-ORIGIN` | Caller-selected Bayer order at full-grid (1,1); an RGGB example does not claim ARRI hardware ordering |
| `ASSUMED-GENERIC-QE` | Existing illustrative effective RGB QE curves, including CFA transmission, not measured ALEV4 spectra |
| `ASSUMED-RECTANGULAR-APERTURE` | Average over each square footprint; fill factor scales collection exactly once afterward |
| `ASSUMED-DISCRETE-PSF` | Identity or stated finite nonnegative unit-sum synthetic kernel; no measured ARRI OLPF or lens response |
| `ASSUMED-CELL-AVERAGE-GRID` | Piecewise-constant spectral photon irradiance on explicitly supplied rectangular cell edges |
| `ISET-PINNED-SPATIAL` | Restricted comparison against pinned ISETCam source; the adapter documents point-sample reconstruction and refinement separately |

ISETCam source is pinned at `3e0253421752eb72f2d1353327dffd0d433abdaf`:
<https://github.com/ISET/isetcam/tree/3e0253421752eb72f2d1353327dffd0d433abdaf>.
Its generic CFA/optics are research references, not ARRI measurements. Specific
spatial conventions below were checked in that exact checkout. No proprietary
source data are bundled.

| Pinned ISETCam source | Semantics used by the restricted adapter |
| --- | --- |
| [oiSpatialSupport.m](https://github.com/ISET/isetcam/blob/3e0253421752eb72f2d1353327dffd0d433abdaf/opticalimage/oiSpatialSupport.m) and [sample2space.m](https://github.com/ISET/isetcam/blob/3e0253421752eb72f2d1353327dffd0d433abdaf/utility/units/sample2space.m) | Centred optical point positions and image/sensor coordinate conventions |
| [sensorCompute.m](https://github.com/ISET/isetcam/blob/3e0253421752eb72f2d1353327dffd0d433abdaf/sensor/simulation/sensorCompute.m) and [signalCurrent.m](https://github.com/ISET/isetcam/blob/3e0253421752eb72f2d1353327dffd0d433abdaf/sensor/simulation/signalCurrent.m) | Native signal path and the explicit samples-per-pixel quadrature setting |
| [SignalCurrentDensity.m](https://github.com/ISET/isetcam/blob/3e0253421752eb72f2d1353327dffd0d433abdaf/sensor/simulation/SignalCurrentDensity.m) | Spectral integration and the native single-precision current-density storage boundary |
| [spatialIntegration.m](https://github.com/ISET/isetcam/blob/3e0253421752eb72f2d1353327dffd0d433abdaf/sensor/simulation/spatialIntegration.m) | Subpixel average, full-fill photodetector weighting and pixel-area multiplication |
| [regridOI2ISA.m](https://github.com/ISET/isetcam/blob/3e0253421752eb72f2d1353327dffd0d433abdaf/sensor/simulation/regridOI2ISA.m) | Linear interpolation of point samples, CFA/subpixel coordinates and an extra Gaussian prefilter whose support depends on pixel/OI spacing |

The fixture's 5 micrometre full-fill sensor pitch is smaller than its roughly
6.34 micrometre optical point spacing, making that native prefilter 1-by-1.
The project then defines piecewise bilinear reconstruction explicitly in
`isetPointGrid`, retains every interior native knot in the cell partition,
and integrates complete footprints. This is a deliberately restricted matched
comparison; it does not establish arbitrary ISET sensor/pixel compatibility.

The ARRI technical-data statements were independently rechecked on
2026-11-14 UTC. The displayed dimensions agree with the original source record;
no measurement uncertainty or hardware CFA-origin evidence was added.

Do not promote assumed records to measured or calibrated status without a new
traceable dataset, measurement conditions, method, units, and uncertainty.
