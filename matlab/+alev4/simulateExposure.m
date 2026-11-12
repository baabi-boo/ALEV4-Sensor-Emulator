function result = simulateExposure(photon_irradiance, sensor, exposure_s, seed)
%SIMULATEEXPOSURE Integrate spectral photon irradiance into a Bayer RAW frame.
%   result = alev4.simulateExposure(irradiance, sensor, exposure_s, seed)
%   irradiance is H-by-W-by-K, in photons / (m^2 s nm), with each
%   wavelength sample a bin-average density. Bin widths are explicit in nm.
%   This is a generic single-gain model, not a calibrated ALEV4 model.
%   Noise-free expectations are retained BEFORE full-well and ADC clipping.
    sensor = alev4.createBaselineSensor(sensor);
    if ~isnumeric(photon_irradiance) || ~isreal(photon_irradiance) || ...
            any(~isfinite(photon_irradiance(:))) || any(photon_irradiance(:) < 0)
        error('ALEV4:InvalidIrradiance', 'Photon irradiance must be finite, real and nonnegative.');
    end
    if ndims(photon_irradiance) > 3 || ...
            size(photon_irradiance, 1) ~= sensor.image_size(1) || ...
            size(photon_irradiance, 2) ~= sensor.image_size(2) || ...
            size(photon_irradiance, 3) ~= numel(sensor.wavelength_nm)
        error('ALEV4:IrradianceShape', 'Irradiance must match image_size and wavelength_nm.');
    end
    if ~isnumeric(exposure_s) || ~isreal(exposure_s) || ~isscalar(exposure_s) || ...
            ~isfinite(exposure_s) || exposure_s < 0
        error('ALEV4:InvalidExposure', 'Exposure must be a finite nonnegative number of seconds.');
    end
    irradiance = double(photon_irradiance);
    collection = double(exposure_s) * sensor.pixel_pitch_m^2 * sensor.fill_factor;
    channels = alev4.cfaMap(sensor.image_size, sensor.cfa_pattern);
    expected = zeros(sensor.image_size);
    incident = collection * sum(bsxfun(@times, irradiance, ...
        reshape(sensor.bin_width_nm, 1, 1, [])), 3);
    for channel = 1:3
        weights = sensor.qe(:, channel) .* sensor.bin_width_nm;
        signal = collection * sum(bsxfun(@times, irradiance, reshape(weights, 1, 1, [])), 3);
        expected(channels == channel) = signal(channels == channel);
    end
    if any(~isfinite(expected(:))) || any(~isfinite(incident(:)))
        error('ALEV4:SignalOverflow', 'Integrated photon/electron expectation overflowed.');
    end
    result = alev4.applyNoise(expected, sensor, seed);
    result.expected_incident_photons = incident;
    result.exposure_s = double(exposure_s);
    result.input_units = 'photons m^-2 s^-1 nm^-1';
    result.spectral_bin_convention = 'bin-average density times explicit width in nm';
end
