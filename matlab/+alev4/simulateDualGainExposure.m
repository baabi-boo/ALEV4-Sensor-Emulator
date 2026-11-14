function result = simulateDualGainExposure(photon_irradiance, cfg, exposure_s, seed)
%SIMULATEDUALGAINEXPOSURE Integrate one spectral exposure and read both gains.
%   RESULT = alev4.simulateDualGainExposure(IRRADIANCE, CFG, EXPOSURE_S, SEED)
%   accepts sensor-plane bin-average photon irradiance in photons/(m^2 s nm).
%   Spectral integration is shared with the Phase 1 API; the resulting charge
%   is sampled once and supplied to two independent electronic readouts.
%   This generic, synthetic model is not a calibrated ALEV4 sensor.
    if nargin ~= 4
        error('ALEV4:DualGainExposureArguments', ...
            'Irradiance, dual-gain configuration, exposure, and seed are required.');
    end
    cfg = alev4.createDualGainSensor(cfg);
    [expected, incident, exposure_s] = ...
        alev4.integrateExposure(photon_irradiance, cfg.sensor, exposure_s);
    result = alev4.applyDualGainNoise(expected, cfg, seed);
    result.expected_incident_photons = incident;
    result.exposure_s = exposure_s;
    result.input_units = 'photons m^-2 s^-1 nm^-1';
    result.spectral_bin_convention = 'bin-average density times explicit width in nm';
end
