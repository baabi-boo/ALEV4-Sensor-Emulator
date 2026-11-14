function cfg = createDualGainSensor(overrides)
%CREATEDUALGAINSENSOR Validate a generic simultaneous dual-gain sensor.
%   CFG = alev4.createDualGainSensor() returns illustrative, uncalibrated
%   defaults. Nested overrides are partial; unknown fields are errors.
%   CFG.sensor controls shared spectral integration, shot noise and full
%   well. CFG.high_gain and CFG.low_gain control independent electronics.
%   The retained Phase 1 electronic fields in CFG.sensor must remain at
%   their canonical defaults, so a misplaced setting cannot be ignored.
%
%   Gain is DN/electron, read noise is RMS electrons, and merge thresholds
%   are electrons. Both paths observe the same charge, not two exposures.
%   These parameters are not measured ALEV4 or ARRI calibration data.

    baseline = alev4.createBaselineSensor();
    cfg = struct('schema_version', '2.0', 'sensor', baseline, ...
        'high_gain', struct('gain_dn_per_e', 4, 'read_noise_e', 1, ...
            'black_level_dn', 64, 'adc_bits', 12), ...
        'low_gain', struct('gain_dn_per_e', 0.1, 'read_noise_e', 5, ...
            'black_level_dn', 64, 'adc_bits', 12), ...
        'merge', struct('start_e', 600, 'end_e', 900));
    if nargin < 1, overrides = struct(); end
    requireStruct(overrides, 'Dual-gain overrides');
    names = fieldnames(overrides);
    for k = 1:numel(names)
        name = names{k};
        if ~isfield(cfg, name)
            error('ALEV4:UnknownDualGainField', ...
                'Unknown dual-gain configuration field: %s.', name);
        end
        if strcmp(name, 'sensor')
            cfg.sensor = alev4.createBaselineSensor(overrides.sensor);
        elseif strcmp(name, 'schema_version')
            cfg.schema_version = overrides.schema_version;
        else
            cfg.(name) = mergeFields(cfg.(name), overrides.(name), name);
        end
    end

    if ~ischar(cfg.schema_version) || ~isrow(cfg.schema_version) || ...
            ~strcmp(cfg.schema_version, '2.0')
        error('ALEV4:InvalidDualGainConfig', ...
            'schema_version must be the character row vector ''2.0''.');
    end
    shared_electronics = {'read_noise_e', 'gain_dn_per_e', ...
        'black_level_dn', 'adc_bits'};
    for k = 1:numel(shared_electronics)
        name = shared_electronics{k};
        if cfg.sensor.(name) ~= baseline.(name)
            error('ALEV4:AmbiguousSharedReadout', ...
                ['sensor.%s must retain its Phase 1 default. Configure ' ...
                 'electronics in high_gain or low_gain instead.'], name);
        end
    end

    [cfg.high_gain, high_headroom, high_interior] = ...
        validatePath(cfg.high_gain, 'high_gain');
    [cfg.low_gain, low_headroom] = validatePath(cfg.low_gain, 'low_gain');
    if cfg.high_gain.gain_dn_per_e <= cfg.low_gain.gain_dn_per_e
        error('ALEV4:InvalidDualGainConfig', ...
            'high_gain.gain_dn_per_e must exceed low_gain.gain_dn_per_e.');
    end
    if low_headroom <= high_headroom
        error('ALEV4:InvalidDualGainConfig', ...
            'The low-gain path must have greater positive electron headroom.');
    end
    cfg.merge.start_e = requireScalar(cfg.merge.start_e, 'merge.start_e');
    cfg.merge.end_e = requireScalar(cfg.merge.end_e, 'merge.end_e');
    if cfg.merge.start_e < 0 || cfg.merge.end_e <= cfg.merge.start_e
        error('ALEV4:InvalidDualGainConfig', ...
            'Merge thresholds must satisfy 0 <= start_e < end_e.');
    end
    if cfg.merge.end_e >= cfg.sensor.full_well_e || ...
            cfg.merge.end_e >= high_interior
        error('ALEV4:InvalidDualGainConfig', ...
            ['The merge must finish strictly below physical full well ' ...
             'and the high-gain last nonrail code center.']);
    end
    % The observed LOW code controls the crossfade and can lag the true
    % noiseless charge by half a low-path quantization step. Finish the
    % transition before the HIGH code first rounds to its unusable top rail,
    % even at that worst low-code error. Without this margin, a late merge
    % can step backwards when high usability suddenly forces its weight to
    % zero. This is a noiseless continuity guard, not a Gaussian-noise bound.
    high_first_rail_e = (2^cfg.high_gain.adc_bits - 1 - 0.5 - ...
        cfg.high_gain.black_level_dn) / cfg.high_gain.gain_dn_per_e;
    low_half_step_e = 0.5 / cfg.low_gain.gain_dn_per_e;
    safe_end_e = high_first_rail_e - low_half_step_e;
    safety_e = 8 * max(eps(high_first_rail_e), eps(low_half_step_e));
    if ~isfinite(safe_end_e) || safe_end_e <= 0 || ...
            cfg.merge.end_e > safe_end_e - safety_e
        error('ALEV4:InvalidDualGainConfig', ...
            ['The merge must finish before the high-gain rail after ' ...
             'allowing half a low-gain quantization step and numeric margin.']);
    end
end

function value = mergeFields(defaults, overrides, context)
    requireStruct(overrides, context);
    value = defaults;
    names = fieldnames(overrides);
    for k = 1:numel(names)
        name = names{k};
        if ~isfield(defaults, name)
            error('ALEV4:UnknownDualGainField', ...
                'Unknown dual-gain configuration field: %s.%s.', context, name);
        end
        value.(name) = overrides.(name);
    end
end

function requireStruct(value, name)
    if ~isstruct(value) || ~isscalar(value)
        error('ALEV4:InvalidDualGainConfig', '%s must be a scalar struct.', name);
    end
end

function value = requireScalar(value, name)
    if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
            ~isfinite(value)
        error('ALEV4:InvalidDualGainConfig', ...
            '%s must be a finite real numeric scalar.', name);
    end
    value = full(double(value));
end

function [path, headroom, interior] = validatePath(path, label)
    names = {'gain_dn_per_e', 'read_noise_e', 'black_level_dn', 'adc_bits'};
    for k = 1:numel(names)
        name = names{k};
        path.(name) = requireScalar(path.(name), [label '.' name]);
    end
    if path.gain_dn_per_e <= 0 || path.read_noise_e < 0
        error('ALEV4:InvalidDualGainConfig', ...
            '%s gain must be positive and read noise nonnegative.', label);
    end
    if path.adc_bits < 2 || path.adc_bits > 16 || ...
            path.adc_bits ~= fix(path.adc_bits)
        error('ALEV4:InvalidDualGainConfig', ...
            '%s.adc_bits must be an integer from 2 through 16 so nonrail codes exist.', label);
    end
    maximum = 2 ^ path.adc_bits - 1;
    if path.black_level_dn < 0 || path.black_level_dn > maximum
        error('ALEV4:InvalidDualGainConfig', ...
            '%s.black_level_dn must lie within the ADC range.', label);
    end
    headroom = (maximum - path.black_level_dn) / path.gain_dn_per_e;
    interior = (maximum - 1 - path.black_level_dn) / path.gain_dn_per_e;
    minimum = -path.black_level_dn / path.gain_dn_per_e;
    if ~isfinite(headroom) || ~isfinite(interior) || ~isfinite(minimum) || ...
            headroom <= 0
        error('ALEV4:InvalidDualGainConfig', ...
            '%s must have finite reconstruction limits and positive headroom.', label);
    end
end
