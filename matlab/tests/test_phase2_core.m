function report = test_phase2_core()
%TEST_PHASE2_CORE Independent transfer, shared-charge and merge invariants.
%   These tests need no ISET toolbox. Statistical noise-distribution checks
%   belong to the separate Phase 2 noise suite; no camera calibration is made.
    caller_rng = rng;
    guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    names = {'analytic_path_transfer_and_distinct_electronics', ...
        'one_shared_shot_charge_realization', ...
        'physical_saturation_and_adc_rounding_boundaries', ...
        'raw_only_rail_fallback_and_signed_output', ...
        'dense_merge_ramp_quantization_bound', ...
        'fractional_black_near_rail_continuity', ...
        'independent_two_bin_four_cfa_spectral_oracle', ...
        'repeatability_and_rng_isolation_on_success_and_error', ...
        'fixed_gaussian_draw_order'};

    testTransfer();
    testSharedCharge();
    testSaturation();
    testMergeRails();
    metrics = testMergeRamp();
    metrics.fractional_black = testFractionalBlackContinuity();
    testSpectralOracle();
    testReproducibility();
    testDrawOrder();

    tests = repmat(struct('name', '', 'status', 'passed', 'passed', true), ...
        1, numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    report = struct('suite', 'phase2_core', 'status', 'passed', ...
        'passed', true, 'test_count', numel(names), 'tests', tests, 'metrics', metrics);
    fprintf('PASS: Phase 2 core invariants, %d test groups.\n', numel(names));
end

function metrics = testFractionalBlackContinuity()
    % The prior accepted 1000..1007 e transition dropped by about 1.38 e
    % when the high code reached its top rail while low's rounded estimate
    % remained 1004 e. The constructor now rejects this unsafe interval.
    bad = struct('sensor', struct('image_size', [1 5], 'shot_noise', false), ...
        'high_gain', struct('read_noise_e', 0), ...
        'low_gain', struct('read_noise_e', 0, 'black_level_dn', 64.6), ...
        'merge', struct('start_e', 1000, 'end_e', 1007));
    caught = false;
    try
        alev4.createDualGainSensor(bad);
    catch err
        caught = true;
        assert(strcmp(err.identifier, 'ALEV4:InvalidDualGainConfig'));
    end
    assert(caught, 'Near-rail transition ignored low-path quantization lag.');

    mu = linspace(950, 1050, 10001);
    good = bad;
    good.sensor.image_size = size(mu);
    good.merge = struct('start_e', 990, 'end_e', 1000);
    cfg = alev4.createDualGainSensor(good);
    result = alev4.applyDualGainNoise(mu, cfg, 4125);
    weight = result.merged.weight_high;
    errors = abs(result.merged.electrons - mu);
    bound = weight/8 + (1-weight)*5;
    increments = diff(result.merged.electrons);
    assert(all(result.reconstruction_valid));
    assert(all(errors <= bound + 2e-12));
    assert(all(increments >= -2e-12), ...
        'Safe fractional-black configuration still steps backwards.');
    high_rail = result.high_gain.raw_dn == 4095;
    assert(any(high_rail) && all(weight(high_rail) == 0));
    first_rail = find(high_rail, 1);
    assert(weight(first_rail-1) == 0, ...
        'Crossfade must already finish before high gain reaches its upper rail.');
    assert(max(increments) <= 10 + 2e-12);
    metrics = struct('samples', numel(mu), 'minimum_step_e', min(increments), ...
        'maximum_step_e', max(increments), 'maximum_abs_error_e', max(errors), ...
        'unsafe_interval_rejected', true, 'weight_before_first_high_rail', weight(first_rail-1));
end

function testTransfer()
    mu = [0 0.124 0.125 100 600; 750 900 1007.875 12000 40000];
    cfg = quietConfig(size(mu));
    result = alev4.applyDualGainNoise(mu, cfg, 4101);
    assert(isequal(result.expected_electrons, mu));
    assert(isequal(result.collected_electrons, mu));
    stored = min(mu, 30000);
    assert(isequal(result.charge_electrons, stored));
    assert(isequal(result.high_gain.read_electrons, stored));
    assert(isequal(result.low_gain.read_electrons, stored));
    assert(isequal(result.high_gain.raw_dn, ...
        uint16(min(floor(4 * stored + 64 + 0.5), 4095))));
    assert(isequal(result.low_gain.raw_dn, ...
        uint16(min(floor(0.1 * stored + 64 + 0.5), 4095))));
    assert(result.high_gain.raw_dn(1, 4) == 464 && ...
        result.low_gain.raw_dn(1, 4) == 74, '100-electron reference transfer changed.');
    assert(isa(result.high_gain.raw_dn, 'uint16') && isa(result.low_gain.raw_dn, 'uint16'));

    % Distinct ADC depths and fractional black levels expose accidental use
    % of the common Phase 1 electronic settings for either branch.
    cfg.high_gain.gain_dn_per_e = 3.5;
    cfg.high_gain.black_level_dn = 23.25;
    cfg.low_gain.gain_dn_per_e = 0.2;
    cfg.low_gain.black_level_dn = 57.5;
    cfg.low_gain.adc_bits = 14;
    alternate = alev4.applyDualGainNoise(mu, cfg, 4101);
    assert(isequal(alternate.high_gain.raw_dn, ...
        uint16(min(floor(3.5 * stored + 23.25 + 0.5), 4095))));
    assert(isequal(alternate.low_gain.raw_dn, ...
        uint16(min(floor(0.2 * stored + 57.5 + 0.5), 16383))));
end

function testSharedCharge()
    cfg = quietConfig([96 97]);
    cfg.sensor.shot_noise = true;
    result = alev4.applyDualGainNoise(37 * ones(cfg.sensor.image_size), cfg, 4102);
    assert(any(result.collected_electrons(:) ~= 37), 'Shot noise was not sampled.');
    assert(isequal(result.high_gain.read_electrons, result.charge_electrons), ...
        'High readout must reuse the shared charge when its read noise is zero.');
    assert(isequal(result.low_gain.read_electrons, result.charge_electrons), ...
        'Low readout must reuse the same charge, not a second exposure.');
    assert(isequal(result.collected_electrons, result.charge_electrons));
    assert(all(result.collected_electrons(:) == fix(result.collected_electrons(:))));
end

function testSaturation()
    mu = [1007.625 1007.874 1007.875 12000 30000 40000];
    cfg = quietConfig(size(mu));
    result = alev4.applyDualGainNoise(mu, cfg, 4103);
    assert(isequal(result.high_gain.adc_high_clipped, ...
        logical([0 0 1 1 1 1])), 'Rounded ADC overflow boundary changed.');
    assert(all(result.high_gain.raw_dn == 4095));
    assert(~any(result.low_gain.adc_high_clipped));
    assert(isequal(result.full_well_saturated, logical([0 0 0 0 1 1])));
    assert(all(result.merged.valid), 'Usable low readout must remain observable at full well.');
    assert(isequal(result.reconstruction_valid, logical([1 1 1 1 0 0])), ...
        'A physically saturated well cannot be reconstructed from low gain.');
    assert(result.merged.electrons(4) == 12000, 'High-clipped highlight was not recovered.');
    assert(result.merged.electrons(6) == 30000, 'Merged output invented charge beyond full well.');

    % The low ADC can also run out of range before the common physical well.
    cfg = quietConfig([1 3]);
    cfg.low_gain.gain_dn_per_e = 0.2;
    both = alev4.applyDualGainNoise([20157.4 20157.5 25000], cfg, 4103);
    assert(isequal(both.low_gain.adc_high_clipped, logical([0 1 1])));
    assert(~any(both.full_well_saturated));
    assert(~any(both.merged.valid) && ~any(both.reconstruction_valid));
    assert(all(isfinite(both.merged.electrons)));
end

function testMergeRails()
    high = uint16([464 0 4095 464 0 4095 63]);
    low = uint16([74 74 1264 0 0 4095 64]);
    cfg = quietConfig(size(high));
    merged = alev4.mergeDualGain(high, low, cfg);
    assert(isequal(merged.high_usable, logical([1 0 0 1 0 0 1])));
    assert(isequal(merged.low_usable, logical([1 1 1 0 0 0 1])));
    assert(isequal(merged.valid, logical([1 1 1 1 0 0 1])));
    assert(isequal(merged.weight_high, [1 0 0 1 0 0 1]));
    assert(isequal(merged.electrons, [100 100 12000 100 -640 40310 -0.25]), ...
        'Fallback must use calibrated recorded codes and preserve signed values.');
    assert(all(isfinite(merged.electrons)));

    % Deliberately inconsistent interior observations make the observable
    % low-channel weighting policy independently visible without scene truth.
    cfg = quietConfig([1 3]);
    direct = alev4.mergeDualGain(uint16([2064 3264 3664]), ...
        uint16([124 139 154]), cfg);
    assert(isequal(direct.weight_high, [1 0.5 0]));
    assert(isequal(direct.electrons, [500 775 900]));

    % The upper-transition guard is not a global monotonicity guarantee.
    % At a custom lower-rail crossing, usable low code 1 estimates 4.9 e
    % until high first becomes usable at 0.125 e and estimates 0.25 e.
    % Both are legitimate quantized observations within their own bounds.
    mu = [0 0.1 0.124 0.125 0.126];
    cfg = quietConfig(size(mu));
    cfg.high_gain.black_level_dn = 0;
    cfg.low_gain.black_level_dn = 0.51;
    lower = alev4.applyDualGainNoise(mu, cfg, 4138);
    assert(isequal(lower.high_gain.raw_dn, uint16([0 0 0 1 1])));
    assert(isequal(lower.low_gain.raw_dn, uint16([1 1 1 1 1])));
    assert(isequal(lower.merged.weight_high, [0 0 0 1 1]));
    assert(max(abs(lower.merged.electrons - [4.9 4.9 4.9 0.25 0.25])) < 2e-14);
    assert(all(lower.merged.valid) && all(lower.reconstruction_valid));
    assert(~any(lower.full_well_saturated));
    bound = lower.merged.weight_high / (2 * cfg.high_gain.gain_dn_per_e) + ...
        (1 - lower.merged.weight_high) / (2 * cfg.low_gain.gain_dn_per_e);
    assert(all(abs(lower.merged.electrons - mu) <= bound + 2e-14), ...
        'Lower-rail fallback exceeded the selected-path quantization bound.');
    assert(lower.merged.electrons(4) < lower.merged.electrons(3), ...
        'The documented lower-rail fallback example changed.');
end

function metrics = testMergeRamp()
    mu = linspace(500, 1100, 12001);
    cfg = quietConfig(size(mu));
    result = alev4.applyDualGainNoise(mu, cfg, 4104);
    weight = result.merged.weight_high;
    bound = weight / 8 + (1 - weight) * 5;
    error_e = abs(result.merged.electrons - mu);
    assert(all(result.reconstruction_valid));
    assert(all(weight >= 0 & weight <= 1));
    assert(all(error_e <= bound + 2e-12), ...
        'Merge exceeded its convex per-path quantization-error bound.');
    increments = diff(result.merged.electrons);
    assert(all(increments >= -2e-12), 'Noiseless increasing input produced a descending merge step.');
    assert(max(increments) <= 10 + 2e-12, ...
        'Merge produced a discontinuity larger than the low-path quantization step.');
    low_e = (double(result.low_gain.raw_dn) - 64) / 0.1;
    assert(all(weight(low_e <= 600) == 1));
    assert(all(weight(low_e >= 900) == 0));
    assert(any(weight > 0 & weight < 1), 'The transition interval was not exercised.');
    metrics = struct('ramp_samples', numel(mu), ...
        'ramp_max_abs_error_e', max(error_e), ...
        'ramp_max_quantization_bound_e', max(bound), ...
        'ramp_max_step_e', max(increments), ...
        'ramp_min_step_e', min(increments));
end

function testSpectralOracle()
    dims = [3 5];
    spatial = reshape(1:15, dims) / 10;
    irradiance = cat(3, 2e12 * spatial, 1e12 * spatial);
    shared = struct('image_size', dims, 'wavelength_nm', [500; 600], ...
        'bin_width_nm', [10; 20], 'qe', [0.5 0.25 0; 0.1 0.2 0.3], ...
        'pixel_pitch_m', 2e-6, 'fill_factor', 0.5, 'shot_noise', false);
    patterns = {'RGGB', 'BGGR', 'GRBG', 'GBRG'};
    tiles = {[1 2; 2 3], [3 2; 2 1], [2 1; 3 2], [2 3; 1 2]};
    % Direct bin sums: R=2.4, G=1.8, B=1.2 electrons at unit spatial scale.
    channel_e = [2.4 1.8 1.2];
    for k = 1:numel(patterns)
        shared.cfa_pattern = patterns{k};
        cfg = alev4.createDualGainSensor(struct('sensor', shared, ...
            'high_gain', struct('read_noise_e', 0), ...
            'low_gain', struct('read_noise_e', 0)));
        expected = zeros(dims);
        tile = tiles{k};
        for row = 1:dims(1)
            for column = 1:dims(2)
                channel = tile(mod(row - 1, 2) + 1, mod(column - 1, 2) + 1);
                expected(row, column) = channel_e(channel) * spatial(row, column);
            end
        end
        result = alev4.simulateDualGainExposure(irradiance, cfg, 0.1, 4105);
        assert(max(abs(result.expected_electrons(:) - expected(:))) < 1e-13);
        assert(max(abs(result.expected_incident_photons(:) - 8 * spatial(:))) < 1e-13);
        assert(isequal(result.high_gain.read_electrons, result.expected_electrons));
        assert(isequal(result.low_gain.read_electrons, result.expected_electrons));
        doubled = alev4.simulateDualGainExposure(irradiance, cfg, 0.2, 4105);
        assert(max(abs(doubled.expected_electrons(:) - 2 * expected(:))) < 2e-13);
        assert(strcmp(result.input_units, 'photons m^-2 s^-1 nm^-1'));
        assert(result.exposure_s == 0.1);
    end
end

function testReproducibility()
    cfg = alev4.createDualGainSensor(struct('sensor', struct('image_size', [16 17])));
    mu = 100 * ones(cfg.sensor.image_size);
    rng(4106, 'twister');
    before = rng;
    first = alev4.applyDualGainNoise(mu, cfg, 0);
    assert(isequal(before, rng()), 'Successful dual readout changed caller RNG state.');
    repeated = alev4.applyDualGainNoise(mu, cfg, 0);
    assert(isequal(first, repeated), 'Same seed did not reproduce every returned result.');
    other = alev4.applyDualGainNoise(mu, cfg, 4294967295);
    assert(~isequal(first.high_gain.read_electrons, other.high_gain.read_electrons));
    assert(isequal(other, alev4.applyDualGainNoise(mu, cfg, 4294967295)));
    assert(isequal(before, rng()));

    overflow = cfg;
    overflow.sensor.shot_noise = false;
    overflow.high_gain.read_noise_e = realmax;
    caught = false;
    try
        alev4.applyDualGainNoise(zeros(cfg.sensor.image_size), overflow, 4106);
    catch err
        caught = true;
        assert(strcmp(err.identifier, 'ALEV4:ReadoutOverflow'), ...
            ['Expected late readout overflow, received ' err.identifier]);
    end
    assert(caught, 'Nonfinite readout was not rejected.');
    assert(isequal(before, rng()), 'Late failure changed caller RNG state.');
end

function testDrawOrder()
    cfg = alev4.createDualGainSensor(struct('sensor', ...
        struct('image_size', [31 33], 'shot_noise', false)));
    mu = 100 * ones(cfg.sensor.image_size);
    both = alev4.applyDualGainNoise(mu, cfg, 4107);
    only_low_cfg = cfg;
    only_low_cfg.high_gain.read_noise_e = 0;
    only_low = alev4.applyDualGainNoise(mu, only_low_cfg, 4107);
    assert(isequal(both.low_gain.read_electrons, only_low.low_gain.read_electrons), ...
        'Disabling high noise shifted the low electronic-noise realization.');
    only_high_cfg = cfg;
    only_high_cfg.low_gain.read_noise_e = 0;
    only_high = alev4.applyDualGainNoise(mu, only_high_cfg, 4107);
    assert(isequal(both.high_gain.read_electrons, only_high.high_gain.read_electrons));
end

function cfg = quietConfig(dimensions)
    cfg = alev4.createDualGainSensor(struct('sensor', ...
        struct('image_size', dimensions, 'shot_noise', false), ...
        'high_gain', struct('read_noise_e', 0), ...
        'low_gain', struct('read_noise_e', 0)));
end
