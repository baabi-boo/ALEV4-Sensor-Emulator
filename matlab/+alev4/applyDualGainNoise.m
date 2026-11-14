function result = applyDualGainNoise(expected_electrons, cfg, seed)
%APPLYDUALGAINNOISE Read one collected charge through two electronic paths.
%   RESULT = alev4.applyDualGainNoise(MU, CFG, SEED) samples photoelectrons
%   once, clips that shared charge once at physical full well, then adds
%   independent signed Gaussian read noises before each path's gain, black
%   offset, rounding and ADC clipping. It is not a pair of exposures.
%
%   Expected, collected and stored charge remain dense double matrices.
%   RESULT.high_gain and RESULT.low_gain retain signed read_electrons,
%   uint16 raw_dn, and separate rounded-code ADC clipping masks. The merge
%   uses only recorded RAW and configuration; physical saturation is known
%   separately by the simulator and excludes reconstruction_valid samples.
%
%   The explicit seed is an integer in [0, 2^32-1]. Caller RNG state is
%   restored on success and failure. Both Gaussian arrays are always drawn
%   in high/low order, including for a zero configured standard deviation.
%   Reproducibility is within one runtime/version, not across runtimes.
    if nargin ~= 3
        error('ALEV4:DualGainNoiseArguments', ...
            'Expected photoelectrons, dual-gain configuration, and seed are required.');
    end
    cfg = alev4.createDualGainSensor(cfg);
    if ~isnumeric(expected_electrons) || ~isreal(expected_electrons) || ...
            ~ismatrix(expected_electrons) || ...
            ~isequal(size(expected_electrons), cfg.sensor.image_size) || ...
            any(~isfinite(expected_electrons(:))) || ...
            any(expected_electrons(:) < 0)
        error('ALEV4:InvalidExpectedElectrons', ...
            'Expected electrons must be a finite nonnegative matrix of image_size.');
    end
    if ~isnumeric(seed) || ~isreal(seed) || ~isscalar(seed) || ...
            ~isfinite(seed) || seed < 0 || seed > 4294967295 || seed ~= floor(seed)
        error('ALEV4:InvalidSeed', 'Seed must be an integer in [0, 2^32-1].');
    end
    expected_electrons = full(double(expected_electrons));
    seed = full(double(seed));
    previousRng = rng;
    restoreRng = onCleanup(@() rng(previousRng)); %#ok<NASGU>
    rng(seed, 'twister');

    if cfg.sensor.shot_noise
        collected = alev4.samplePoisson(expected_electrons);
    else
        collected = expected_electrons;
    end
    stored = min(collected, cfg.sensor.full_well_e);
    highNoise = randn(size(stored));
    lowNoise = randn(size(stored));

    result = struct();
    result.expected_electrons = expected_electrons;
    result.collected_electrons = collected;
    result.charge_electrons = stored;
    result.full_well_saturated = collected >= cfg.sensor.full_well_e;
    result.high_gain = readPath(stored, cfg.high_gain, highNoise);
    result.low_gain = readPath(stored, cfg.low_gain, lowNoise);
    result.seed = seed;
    result.merged = alev4.mergeDualGain( ...
        result.high_gain.raw_dn, result.low_gain.raw_dn, cfg);
    result.reconstruction_valid = result.merged.valid & ~result.full_well_saturated;
end

function path = readPath(stored, config, standardNoise)
    readout = stored + config.read_noise_e .* standardNoise;
    analogDn = readout .* config.gain_dn_per_e + config.black_level_dn;
    if any(~isfinite(readout(:))) || any(~isfinite(analogDn(:)))
        error('ALEV4:ReadoutOverflow', ...
            'Readout exceeds the finite numeric range; reduce charge, gain, or noise.');
    end
    roundedDn = round(analogDn);
    adcMax = 2 ^ config.adc_bits - 1;
    path = struct('read_electrons', readout, ...
        'raw_dn', uint16(min(max(roundedDn, 0), adcMax)), ...
        'adc_low_clipped', roundedDn < 0, ...
        'adc_high_clipped', roundedDn > adcMax);
end
