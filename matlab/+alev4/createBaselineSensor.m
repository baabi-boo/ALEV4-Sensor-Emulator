function cfg = createBaselineSensor(overrides)
%CREATEBASELINESENSOR Create and validate a generic spectral Bayer sensor.
%   CFG = alev4.createBaselineSensor() returns a small, uncalibrated sensor.
%   CFG = alev4.createBaselineSensor(OVERRIDES) replaces named fields. Unknown
%   fields are errors, so misspelled physical parameters cannot be ignored.
%   Passing an existing CFG through this function validates it again.
%
%   All defaults are illustrative, NOT measured ALEV4/ARRI parameters.
%   Spectral input uses bin-average photon irradiance per nm. Wavelengths
%   identify bin centres, and bin_width_nm gives each integration width.
%   Effective R/G/B QE includes CFA transmission once, but NOT fill factor.
%   Collection area is pixel_pitch_m^2 * fill_factor.
%   Gain is explicitly DN per electron; read noise is RMS electrons.
%
%   Changing wavelength_nm requires matching bin_width_nm and qe arrays.
%   Four Bayer patterns and odd image dimensions are supported. The pattern
%   starts at the top-left sample, MATLAB array index (1,1).

    wavelength_nm = (400:20:700)';
    qe = [0.55 * exp(-0.5 * ((wavelength_nm - 610) / 45).^2), ...
          0.65 * exp(-0.5 * ((wavelength_nm - 540) / 40).^2), ...
          0.50 * exp(-0.5 * ((wavelength_nm - 460) / 35).^2)];
    cfg = struct( ...
        'schema_version', '1.0', ...
        'image_size', [32 32], ...
        'wavelength_nm', wavelength_nm, ...
        'bin_width_nm', 20 * ones(numel(wavelength_nm), 1), ...
        'qe', qe, ...
        'pixel_pitch_m', 6e-6, ...
        'fill_factor', 0.8, ...
        'full_well_e', 30000, ...
        'read_noise_e', 3, ...
        'gain_dn_per_e', 0.5, ...
        'black_level_dn', 64, ...
        'adc_bits', 16, ...
        'cfa_pattern', 'RGGB', ...
        'shot_noise', true);

    if nargin < 1
        overrides = struct();
    end
    if ~isstruct(overrides) || ~isscalar(overrides)
        error('ALEV4:InvalidSensorConfig', ...
            'Sensor overrides must be a scalar struct.');
    end
    names = fieldnames(overrides);
    for k = 1:numel(names)
        name = names{k};
        if ~isfield(cfg, name)
            error('ALEV4:UnknownSensorField', ...
                'Unknown sensor configuration field: %s.', name);
        end
        cfg.(name) = overrides.(name);
    end

    if ~ischar(cfg.schema_version) || ~isrow(cfg.schema_version) || ...
            ~strcmp(cfg.schema_version, '1.0')
        error('ALEV4:InvalidSensorConfig', ...
            'schema_version must be the character row vector ''1.0''.');
    end
    if ~isRealFiniteNumeric(cfg.image_size) || ...
            ~isvector(cfg.image_size) || numel(cfg.image_size) ~= 2 || ...
            any(cfg.image_size(:) < 1) || ...
            any(cfg.image_size(:) ~= fix(cfg.image_size(:)))
        error('ALEV4:InvalidSensorConfig', ...
            'image_size must contain two positive integer dimensions.');
    end
    cfg.image_size = double(cfg.image_size(:).');

    if ~isRealFiniteNumeric(cfg.wavelength_nm) || ...
            ~isvector(cfg.wavelength_nm) || isempty(cfg.wavelength_nm) || ...
            any(cfg.wavelength_nm(:) <= 0)
        error('ALEV4:InvalidSensorConfig', ...
            'wavelength_nm must be a nonempty positive finite vector.');
    end
    cfg.wavelength_nm = double(cfg.wavelength_nm(:));
    if any(diff(cfg.wavelength_nm) <= 0)
        error('ALEV4:InvalidSensorConfig', ...
            'wavelength_nm must be strictly increasing.');
    end
    n_wavelengths = numel(cfg.wavelength_nm);
    if ~isRealFiniteNumeric(cfg.bin_width_nm) || ...
            ~isvector(cfg.bin_width_nm) || ...
            numel(cfg.bin_width_nm) ~= n_wavelengths || ...
            any(cfg.bin_width_nm(:) <= 0)
        error('ALEV4:InvalidSensorConfig', ...
            'bin_width_nm must contain one positive finite width per bin.');
    end
    cfg.bin_width_nm = double(cfg.bin_width_nm(:));
    lower_edges = cfg.wavelength_nm - cfg.bin_width_nm / 2;
    upper_edges = cfg.wavelength_nm + cfg.bin_width_nm / 2;
    if any(lower_edges <= 0) || any(~isfinite(upper_edges))
        error('ALEV4:InvalidSensorConfig', ...
            'Spectral bins must have positive finite wavelength edges.');
    end
    edge_tolerance = 8 * eps(max(upper_edges));
    if any(upper_edges(1:end-1) - lower_edges(2:end) > edge_tolerance)
        error('ALEV4:InvalidSensorConfig', ...
            'Spectral bins must not overlap; provide explicit bin widths.');
    end
    if ~isRealFiniteNumeric(cfg.qe) || ...
            ~isequal(size(cfg.qe), [n_wavelengths 3]) || ...
            any(cfg.qe(:) < 0) || any(cfg.qe(:) > 1)
        error('ALEV4:InvalidSensorConfig', ...
            'qe must be an N-by-3 finite R/G/B matrix in [0,1].');
    end
    cfg.qe = double(cfg.qe);

    cfg.pixel_pitch_m = requireScalar(cfg.pixel_pitch_m, 'pixel_pitch_m');
    if cfg.pixel_pitch_m <= 0 || ~isfinite(cfg.pixel_pitch_m^2) || ...
            cfg.pixel_pitch_m^2 == 0
        error('ALEV4:InvalidSensorConfig', ...
            'pixel_pitch_m must give a positive finite representable area.');
    end
    cfg.fill_factor = requireScalar(cfg.fill_factor, 'fill_factor');
    if cfg.fill_factor < 0 || cfg.fill_factor > 1
        error('ALEV4:InvalidSensorConfig', 'fill_factor must be in [0,1].');
    end
    cfg.full_well_e = requireScalar(cfg.full_well_e, 'full_well_e');
    if cfg.full_well_e <= 0
        error('ALEV4:InvalidSensorConfig', 'full_well_e must be positive.');
    end
    cfg.read_noise_e = requireScalar(cfg.read_noise_e, 'read_noise_e');
    if cfg.read_noise_e < 0
        error('ALEV4:InvalidSensorConfig', 'read_noise_e cannot be negative.');
    end
    cfg.gain_dn_per_e = requireScalar(cfg.gain_dn_per_e, 'gain_dn_per_e');
    if cfg.gain_dn_per_e <= 0
        error('ALEV4:InvalidSensorConfig', 'gain_dn_per_e must be positive.');
    end
    cfg.adc_bits = requireScalar(cfg.adc_bits, 'adc_bits');
    if cfg.adc_bits < 1 || cfg.adc_bits > 16 || ...
            cfg.adc_bits ~= fix(cfg.adc_bits)
        error('ALEV4:InvalidSensorConfig', ...
            'adc_bits must be an integer from 1 through 16 for uint16 RAW.');
    end
    cfg.black_level_dn = requireScalar(cfg.black_level_dn, 'black_level_dn');
    if cfg.black_level_dn < 0 || cfg.black_level_dn > 2^cfg.adc_bits - 1
        error('ALEV4:InvalidSensorConfig', ...
            'black_level_dn must lie within the configured ADC range.');
    end
    if ~ischar(cfg.cfa_pattern) || ~isrow(cfg.cfa_pattern)
        error('ALEV4:InvalidSensorConfig', ...
            'cfa_pattern must be a character row vector.');
    end
    cfg.cfa_pattern = upper(cfg.cfa_pattern);
    if ~any(strcmp(cfg.cfa_pattern, {'RGGB', 'BGGR', 'GRBG', 'GBRG'}))
        error('ALEV4:InvalidSensorConfig', ...
            'cfa_pattern must be RGGB, BGGR, GRBG, or GBRG.');
    end
    if ~islogical(cfg.shot_noise) || ~isscalar(cfg.shot_noise)
        error('ALEV4:InvalidSensorConfig', ...
            'shot_noise must be a scalar logical true or false.');
    end
end

function tf = isRealFiniteNumeric(value)
    tf = isnumeric(value) && isreal(value) && all(isfinite(value(:)));
end

function value = requireScalar(value, name)
    if ~isRealFiniteNumeric(value) || ~isscalar(value)
        error('ALEV4:InvalidSensorConfig', ...
            '%s must be a real finite numeric scalar.', name);
    end
    value = double(value);
end
