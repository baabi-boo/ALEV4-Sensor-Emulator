function result = simulateExposure(photon_irradiance, sensor, exposure_s, seed)
%SIMULATEEXPOSURE Integrate spectral photon irradiance into a Bayer RAW frame.
%   result = alev4.simulateExposure(irradiance, sensor, exposure_s, seed)
%   irradiance is H-by-W-by-K, in photons / (m^2 s nm), with each
%   wavelength sample a bin-average density. Bin widths are explicit in nm.
%   This is a generic single-gain model, not a calibrated ALEV4 model.
%   Noise-free expectations are retained BEFORE full-well and ADC clipping.
%   Exact zero collection/irradiance endpoints bypass spectral arithmetic,
%   but still undergo readout noise. Unsupported floating-point underflow or
%   overflow raises an error rather than masquerading as a zero exposure.
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
    expected = zeros(sensor.image_size);
    incident = zeros(sensor.image_size);
    % Avoid 0*Inf for a physically exact zero signal, even when accepted
    % finite irradiance or geometry would overflow intermediate arithmetic.
    has_collection = exposure_s > 0 && sensor.fill_factor > 0;
    if has_collection && any(irradiance(:) > 0)
        collection = double(exposure_s) * sensor.pixel_pitch_m^2 * sensor.fill_factor;
        if collection == 0
            error('ALEV4:CollectionUnderflow', ...
                'Positive exposure/area/fill product underflowed; rescale the input configuration.');
        end
        if ~isfinite(collection)
            error('ALEV4:SignalOverflow', 'Exposure/area/fill product overflowed.');
        end
        channels = alev4.cfaMap(sensor.image_size, sensor.cfa_pattern);
        incident = collection * sum(bsxfun(@times, irradiance, ...
            reshape(sensor.bin_width_nm, 1, 1, [])), 3);
        for channel = 1:3
            weights = sensor.qe(:, channel) .* sensor.bin_width_nm;
            signal = collection * sum(bsxfun(@times, irradiance, reshape(weights, 1, 1, [])), 3);
            expected(channels == channel) = signal(channels == channel);
        end
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
