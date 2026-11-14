function result = simulateExposure(photon_irradiance, sensor, exposure_s, seed)
%SIMULATEEXPOSURE Integrate spectral photon irradiance into a Bayer RAW frame.
%   result = alev4.simulateExposure(irradiance, sensor, exposure_s, seed)
%   irradiance is H-by-W-by-K, in photons / (m^2 s nm), with each
%   wavelength sample a bin-average density. Bin widths are explicit in nm.
%   This is a generic single-gain model, not a calibrated ALEV4 model.
%   Noise-free expectations are retained BEFORE full-well and ADC clipping.
%   Exact zero collection/irradiance endpoints bypass spectral arithmetic,
%   but still undergo readout noise. Collection-factor underflow to zero and
%   overflowing spectral accumulations raise explicit numeric-range errors.
%   Sparse one-bin images and other accepted numeric inputs are normalized
%   to dense doubles before integration; retained expectations are dense.
    [expected, incident, exposure_s] = ...
        alev4.integrateExposure(photon_irradiance, sensor, exposure_s);
    result = alev4.applyNoise(expected, sensor, seed);
    result.expected_incident_photons = incident;
    result.exposure_s = exposure_s;
    result.input_units = 'photons m^-2 s^-1 nm^-1';
    result.spectral_bin_convention = 'bin-average density times explicit width in nm';
end
