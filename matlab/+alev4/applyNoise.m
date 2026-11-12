function result = applyNoise(expected_electrons, cfg, seed)
%APPLYNOISE Sample sensor charge and perform a single-gain digital readout.
%   RESULT = alev4.applyNoise(MU, CFG, SEED) uses this explicit order:
%       Poisson(MU) -> full-well clipping -> Gaussian read noise ->
%       gain [DN/e-] + black offset [DN] -> round -> ADC clipping.
%   With CFG.shot_noise=false, MU is used as deterministic collected charge.
%   All intermediate electron arrays remain double precision; RAW is uint16.
%
%   read_electrons can be negative. Clipping negative read noise before the
%   black offset would bias dark frames and is deliberately not performed.
%   full_well_saturated marks collected charge >= full well. ADC clipping
%   masks mark ROUNDED codes outside [0, 2^adc_bits-1], before range clipping.
%   They distinguish digital clipping from physical well saturation.
%
%   SEED is an integer in [0, 2^32-1]. RNG state is restored on normal return
%   and error. Reproducibility is within one supported runtime/version; the
%   same seed is not a promise of identical MATLAB and Octave noise streams.

    if nargin ~= 3
        error('ALEV4:NoiseArguments', ...
            'Expected photoelectrons, sensor configuration, and seed are required.');
    end
    cfg = alev4.createBaselineSensor(cfg);
    if ~isnumeric(expected_electrons) || ~isreal(expected_electrons) || ...
            ~ismatrix(expected_electrons) || ...
            ~isequal(size(expected_electrons), cfg.image_size) || ...
            any(~isfinite(expected_electrons(:))) || ...
            any(expected_electrons(:) < 0)
        error('ALEV4:InvalidExpectedElectrons', ...
            'Expected electrons must be a finite nonnegative matrix of image_size.');
    end
    if ~isnumeric(seed) || ~isreal(seed) || ~isscalar(seed) || ...
            ~isfinite(seed) || seed < 0 || seed > 4294967295 || seed ~= floor(seed)
        error('ALEV4:InvalidSeed', 'Seed must be an integer in [0, 2^32-1].');
    end

    expected_electrons = double(expected_electrons);
    previousRng = rng;
    restoreRng = onCleanup(@() rng(previousRng)); %#ok<NASGU>
    rng(double(seed), 'twister');

    if cfg.shot_noise
        collected = alev4.samplePoisson(expected_electrons);
    else
        collected = expected_electrons;
    end
    stored = min(collected, cfg.full_well_e);
    readout = stored;
    if cfg.read_noise_e > 0
        readout = stored + cfg.read_noise_e .* randn(size(stored));
    end
    analogDn = readout .* cfg.gain_dn_per_e + cfg.black_level_dn;
    if any(~isfinite(analogDn(:)))
        error('ALEV4:ReadoutOverflow', ...
            'Readout exceeds the finite numeric range; reduce charge, gain, or noise.');
    end
    roundedDn = round(analogDn);
    adcMax = 2 ^ cfg.adc_bits - 1;

    result = struct();
    result.expected_electrons = expected_electrons;
    result.collected_electrons = collected;
    result.charge_electrons = stored;
    result.read_electrons = readout;
    result.raw_dn = uint16(min(max(roundedDn, 0), adcMax));
    result.full_well_saturated = collected >= cfg.full_well_e;
    result.adc_low_clipped = roundedDn < 0;
    result.adc_high_clipped = roundedDn > adcMax;
    result.seed = double(seed);
end
