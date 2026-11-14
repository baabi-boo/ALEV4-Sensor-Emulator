function [expected, incident, exposure_s] = integrateExposure(photon_irradiance, sensor, exposure_s)
%INTEGRATEEXPOSURE Shared, noise-free spectral photon-to-electron integration.
%   [EXPECTED, INCIDENT, EXPOSURE_S] = alev4.integrateExposure(IRRADIANCE,
%   SENSOR, EXPOSURE_S) applies the Phase 1 spectral contract to a Bayer grid.
%   IRRADIANCE is bin-average photons/(m^2 s nm), with explicit widths in nm.
%   EXPECTED and INCIDENT are dense double matrices before any sampling or
%   full-well clipping. No random numbers are consumed by this function.
%   Both single- and dual-gain exposures use this same integration path.
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
    if issparse(irradiance), irradiance = full(irradiance); end
    exposure_s = full(double(exposure_s));
    expected = zeros(sensor.image_size);
    incident = zeros(sensor.image_size);
    % Avoid 0*Inf for a physically exact zero signal, even when accepted
    % finite irradiance or geometry would overflow intermediate arithmetic.
    has_collection = exposure_s > 0 && sensor.fill_factor > 0;
    if has_collection && any(irradiance(:) > 0)
        collection = exposure_s * sensor.pixel_pitch_m^2 * sensor.fill_factor;
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
end
