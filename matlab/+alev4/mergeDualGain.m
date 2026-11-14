function merged = mergeDualGain(high_dn, low_dn, cfg)
%MERGEDUALGAIN Reconstruct signed electrons from two observed ADC planes.
%   MERGED = alev4.mergeDualGain(HIGH_DN, LOW_DN, CFG) uses only recorded
%   integer codes and their declared gain/black calibration. A smoothstep
%   crossfade is controlled by reconstructed LOW_DN in the configured merge
%   interval. This policy is not a claim of statistically optimal fusion.
%
%   Codes at either ADC rail are conservatively unusable: RAW alone cannot
%   distinguish actual clipping from a sample which rounded to a rail. If
%   only one path is usable, it supplies the estimate. If neither is usable,
%   the finite low-path estimate is retained with valid=false. Consumers
%   must consult this mask. Physical full-well saturation is not observable
%   from these two RAW planes and must remain a separate simulation mask.

    if nargin ~= 3
        error('ALEV4:DualGainMergeArguments', ...
            'High RAW, low RAW, and dual-gain configuration are required.');
    end
    cfg = alev4.createDualGainSensor(cfg);
    high_max = 2 ^ cfg.high_gain.adc_bits - 1;
    low_max = 2 ^ cfg.low_gain.adc_bits - 1;
    high_dn = validateRaw(high_dn, cfg.sensor.image_size, high_max, 'high_gain');
    low_dn = validateRaw(low_dn, cfg.sensor.image_size, low_max, 'low_gain');
    high_e = (high_dn - cfg.high_gain.black_level_dn) / cfg.high_gain.gain_dn_per_e;
    low_e = (low_dn - cfg.low_gain.black_level_dn) / cfg.low_gain.gain_dn_per_e;
    if any(~isfinite(high_e(:))) || any(~isfinite(low_e(:)))
        error('ALEV4:MergeOverflow', 'Reconstructed electron values must be finite.');
    end

    % Compute the ratio only inside the interval. Evaluating it for an
    % extreme but valid negative reconstruction could overflow subtraction
    % before clamping; its correct endpoint weight is already known.
    t = zeros(cfg.sensor.image_size);
    above = low_e >= cfg.merge.end_e;
    inside = low_e > cfg.merge.start_e & ~above;
    t(above) = 1;
    t(inside) = (low_e(inside) - cfg.merge.start_e) / ...
        (cfg.merge.end_e - cfg.merge.start_e);
    weight = 1 - t .^ 2 .* (3 - 2 .* t);
    high_usable = high_dn > 0 & high_dn < high_max;
    low_usable = low_dn > 0 & low_dn < low_max;
    weight(~high_usable) = 0;
    weight(high_usable & ~low_usable) = 1;
    electrons = weight .* high_e + (1 - weight) .* low_e;
    if any(~isfinite(electrons(:)))
        error('ALEV4:MergeOverflow', 'Merged electron values exceed the finite numeric range.');
    end
    merged = struct('electrons', electrons, 'weight_high', weight, ...
        'valid', high_usable | low_usable, ...
        'high_usable', high_usable, 'low_usable', low_usable);
end

function raw = validateRaw(raw, image_size, maximum, label)
    if ~isnumeric(raw) || ~isreal(raw) || ~ismatrix(raw) || ...
            ~isequal(size(raw), image_size) || any(~isfinite(raw(:)))
        error('ALEV4:InvalidDualGainRaw', ...
            '%s RAW must be a finite real numeric matrix of image_size.', label);
    end
    raw = full(double(raw));
    if any(raw(:) < 0) || any(raw(:) > maximum) || ...
            any(raw(:) ~= fix(raw(:)))
        error('ALEV4:InvalidDualGainRaw', ...
            '%s RAW must contain integer codes within the configured ADC range.', label);
    end
end
