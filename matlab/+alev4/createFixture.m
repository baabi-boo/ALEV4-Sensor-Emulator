function irradiance = createFixture(kind, sensor, photon_density)
%CREATEFIXTURE Controlled sensor-plane irradiance fixtures (not sRGB images).
%   'flat', 'black', 'ramp', and 'checker' return spectral photon irradiance
%   in photons/(m^2 s nm). All spectral bins share the specified density;
%   black is exactly zero. Spatial values lie between zero and that density.
    sensor = alev4.createBaselineSensor(sensor);
    if nargin < 3, photon_density = 1e13; end
    if ~ischar(kind) || size(kind, 1) ~= 1
        error('ALEV4:InvalidFixture', 'Fixture name must be a character row.');
    end
    if ~isnumeric(photon_density) || ~isreal(photon_density) || ~isscalar(photon_density) || ...
            ~isfinite(photon_density) || photon_density < 0
        error('ALEV4:InvalidIrradiance', 'Photon density must be finite and nonnegative.');
    end
    h = sensor.image_size(1); w = sensor.image_size(2);
    switch lower(kind)
        case 'flat'
            spatial = ones(h, w);
        case 'black'
            spatial = zeros(h, w);
        case 'ramp'
            spatial = repmat(linspace(0, 1, w), h, 1);
        case 'checker'
            [row, col] = ndgrid(1:h, 1:w);
            spatial = mod(floor((row-1)/4) + floor((col-1)/4), 2);
        otherwise
            error('ALEV4:InvalidFixture', 'Unknown fixture; use flat, black, ramp or checker.');
    end
    irradiance = repmat(double(photon_density) * spatial, 1, 1, numel(sensor.wavelength_nm));
end
