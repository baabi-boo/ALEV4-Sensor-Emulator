function report = test_phase2_numerical_edges()
%TEST_PHASE2_NUMERICAL_EDGES Range, representation and error-path invariants.
%   These checks exercise the dual public APIs, including their shared
%   integrator. Extreme configurations are numerical probes, not sensor data.
    previous_rng = rng;
    guard = onCleanup(@() rng(previous_rng)); %#ok<NASGU>
    names = {'argument_seed_and_expected_array_rejection', ...
        'poisson_supported_limit_and_rng_isolation', ...
        'exact_zero_collection_preserves_electronics', ...
        'spectral_arithmetic_range_failures', ...
        'numeric_representation_equivalence', ...
        'both_readout_failures_restore_rng', ...
        'endpoint_safe_extreme_merge_arithmetic', ...
        'spectral_validation_before_zero_shortcuts'};

    testInputs();
    testPoissonLimit();
    testExactZero();
    testSpectralRange();
    testRepresentations();
    testReadoutFailures();
    metrics = testExtremeMerge();
    testSpectralValidation();

    tests = repmat(struct('name', '', 'status', 'passed', 'passed', true), 1, numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    report = struct('suite', 'phase2_numerical_edges', 'status', 'passed', ...
        'passed', true, 'test_count', numel(names), 'tests', tests, 'metrics', metrics);
    fprintf('PASS: Phase 2 numerical edges, %d test groups.\n', numel(names));
end

function testInputs()
    cfg = smallConfig();
    mu = ones(2, 3);
    bad_expected = {[], zeros(3, 2), ones(2, 3, 2), -mu, NaN*mu, ...
        Inf*mu, mu + 1i, false(2, 3), 'invalid'};
    before = rng;
    for k = 1:numel(bad_expected)
        assertError(@() alev4.applyDualGainNoise(bad_expected{k}, cfg, 6201), ...
            'ALEV4:InvalidExpectedElectrons');
    end
    bad_seeds = {-1, 2^32, 1.5, NaN, Inf, 1i, [], [1 2], true, '0'};
    for k = 1:numel(bad_seeds)
        assertError(@() alev4.applyDualGainNoise(mu, cfg, bad_seeds{k}), 'ALEV4:InvalidSeed');
    end
    assertError(@() alev4.applyDualGainNoise(mu, cfg), 'ALEV4:DualGainNoiseArguments');
    assertError(@() alev4.simulateDualGainExposure(mu, cfg, 1), 'ALEV4:DualGainExposureArguments');
    for seed = [0 2^32-1]
        first = alev4.applyDualGainNoise(mu, cfg, seed);
        assert(isequal(first, alev4.applyDualGainNoise(mu, cfg, uint32(seed))));
        assert(first.seed == seed && isa(first.seed, 'double'));
    end
    assert(isequal(before, rng()), 'Rejected inputs or seed endpoints changed caller RNG.');
end

function testPoissonLimit()
    cfg = smallConfig();
    cfg.sensor.shot_noise = true;
    before = rng;
    at_limit = alev4.applyDualGainNoise(1e9*ones(2, 3), cfg, 6202);
    assert(all(isfinite(at_limit.collected_electrons(:))));
    assert(all(at_limit.collected_electrons(:) >= 0));
    assert(all(at_limit.collected_electrons(:) == fix(at_limit.collected_electrons(:))));
    assert(isequal(at_limit.charge_electrons, 30000*ones(2, 3)));
    assert(all(at_limit.full_well_saturated(:)) && ~any(at_limit.reconstruction_valid(:)));
    assertError(@() alev4.applyDualGainNoise((1e9+1)*ones(2, 3), cfg, 6202), ...
        'ALEV4:InvalidPoissonMean');
    assert(isequal(before, rng()), 'Poisson range failure did not restore RNG.');
    % The Poisson sampler's bound is not a bound on deterministic input:
    % shared physical clipping safely limits even a finite realmax charge.
    cfg.sensor.shot_noise = false;
    cfg.high_gain.read_noise_e = 0;
    cfg.low_gain.read_noise_e = 0;
    deterministic = alev4.applyDualGainNoise(realmax*ones(2, 3), cfg, 6202);
    assert(all(deterministic.collected_electrons(:) == realmax));
    assert(all(deterministic.charge_electrons(:) == 30000));
    assert(all(deterministic.low_gain.read_electrons(:) == 30000));
    assert(all(isfinite(deterministic.merged.electrons(:))));
end

function testExactZero()
    cfg = smallConfig();
    flux = realmax*ones(2, 3);
    zero_time = alev4.simulateDualGainExposure(flux, cfg, 0, 6203);
    assertZeroCharge(zero_time);
    cfg.sensor.fill_factor = 0;
    zero_area = alev4.simulateDualGainExposure(flux, cfg, realmax, 6203);
    assertZeroCharge(zero_area);
    assert(isequal(zero_time.high_gain, zero_area.high_gain));
    assert(isequal(zero_time.low_gain, zero_area.low_gain));
    assert(any(zero_time.high_gain.read_electrons(:) ~= 0));
    assert(any(zero_time.low_gain.read_electrons(:) ~= 0));

    cfg = smallConfig();
    cfg.sensor.pixel_pitch_m = 1e150;
    cfg.sensor.fill_factor = 1;
    zero_flux = alev4.simulateDualGainExposure(zeros(2, 3), cfg, 1e100, 6203);
    assertZeroCharge(zero_flux);
    assert(isequal(zero_time.high_gain, zero_flux.high_gain));
    assert(isequal(zero_time.low_gain, zero_flux.low_gain));
end

function testSpectralRange()
    cfg = smallConfig();
    cfg.sensor.pixel_pitch_m = 1e-100;
    cfg.sensor.fill_factor = 1;
    before = rng;
    assertError(@() alev4.simulateDualGainExposure(1e300*ones(2, 3), cfg, 1e-200, 6204), ...
        'ALEV4:CollectionUnderflow');
    cfg.sensor.pixel_pitch_m = 1e150;
    assertError(@() alev4.simulateDualGainExposure(ones(2, 3), cfg, 1e100, 6204), ...
        'ALEV4:SignalOverflow');
    cfg = smallConfig();
    % Bin multiplication overflows even though the collection scale is tiny.
    % The documented finite-arithmetic contract rejects this range instead
    % of inventing a finite rescaled answer or a zero signal.
    assertError(@() alev4.simulateDualGainExposure(realmax*ones(2, 3), cfg, 0.01, 6204), ...
        'ALEV4:SignalOverflow');
    assert(isequal(before, rng()), 'Failed spectral integration consumed RNG state.');
end

function testRepresentations()
    cfg = smallConfig();
    cfg.sensor.shot_noise = true;
    values = [0 1 9; 10 50 100];
    reference = alev4.applyDualGainNoise(values, cfg, 6205);
    alternatives = {sparse(values), single(values), uint16(values)};
    for k = 1:numel(alternatives)
        actual = alev4.applyDualGainNoise(alternatives{k}, cfg, uint32(6205));
        assert(isequal(actual, reference), 'Numeric storage changed the seeded dual realization.');
        assertDense(actual);
    end
    cfg.sensor.shot_noise = false;
    cfg.sensor.pixel_pitch_m = 1;
    cfg.sensor.fill_factor = 1;
    reference = alev4.simulateDualGainExposure(values, cfg, 0.25, 6205);
    for k = 1:numel(alternatives)
        actual = alev4.simulateDualGainExposure(alternatives{k}, cfg, sparse(0.25), sparse(6205));
        assert(isequal(actual, reference), 'Numeric storage changed spectral integration/readout.');
        assertDense(actual);
        assert(isa(actual.expected_incident_photons, 'double') && ~issparse(actual.expected_incident_photons));
        assert(isa(actual.exposure_s, 'double') && ~issparse(actual.exposure_s));
    end
end

function testReadoutFailures()
    cfg = smallConfig();
    cfg.sensor.shot_noise = false;
    cfg.high_gain.read_noise_e = 0;
    cfg.low_gain.read_noise_e = 0;
    cfg.high_gain.gain_dn_per_e = 1e308;
    cfg.low_gain.gain_dn_per_e = 5e307;
    cfg.merge.start_e = 1e-306;
    cfg.merge.end_e = 1e-305;
    before = rng;
    assertError(@() alev4.applyDualGainNoise(10*ones(2, 3), cfg, 6206), ...
        'ALEV4:ReadoutOverflow');
    assert(isequal(before, rng()), 'High-path gain overflow did not restore caller RNG.');

    cfg = alev4.createDualGainSensor(struct('sensor', ...
        struct('image_size', [20 21], 'shot_noise', false), ...
        'high_gain', struct('read_noise_e', 0), ...
        'low_gain', struct('read_noise_e', realmax)));
    assertError(@() alev4.applyDualGainNoise(zeros(20, 21), cfg, 6206), ...
        'ALEV4:ReadoutOverflow');
    assert(isequal(before, rng()), 'Late low-path readout overflow did not restore caller RNG.');
end

function metrics = testExtremeMerge()
    low_gain = 4000 / (realmax * 0.999);
    cfg = alev4.createDualGainSensor(struct('sensor', ...
        struct('image_size', [1 4], 'full_well_e', 1e307), ...
        'high_gain', struct('gain_dn_per_e', 1.01*low_gain, 'black_level_dn', 4000), ...
        'low_gain', struct('gain_dn_per_e', low_gain, 'black_level_dn', 4000), ...
        'merge', struct('start_e', 2e306, 'end_e', 3e306)));
    low_minimum = -4000 / low_gain;
    assert(isfinite(low_minimum));
    assert(~isfinite(low_minimum - cfg.merge.start_e), ...
        'Fixture no longer exercises overflowing outside-interval subtraction.');
    raw = uint16([0 1 4001 4095]);
    merged = alev4.mergeDualGain(raw, raw, cfg);
    assert(all(isfinite(merged.electrons)) && all(isfinite(merged.weight_high)));
    assert(isequal(merged.weight_high, [0 1 1 0]));
    assert(isequal(merged.valid, logical([0 1 1 0])));
    assert(merged.electrons(1) == low_minimum);
    assert(merged.electrons(2) == (1-4000)/cfg.high_gain.gain_dn_per_e);
    assert(merged.electrons(4) == (4095-4000)/low_gain);
    bad = cfg; bad.low_gain.gain_dn_per_e = realmin;
    assertError(@() alev4.mergeDualGain(raw, raw, bad), 'ALEV4:InvalidDualGainConfig');
    metrics = struct('poisson_mean_limit_e', 1e9, ...
        'extreme_low_reconstruction_e', low_minimum, ...
        'outside_interval_subtraction_overflows', true, ...
        'endpoint_safe_merge_finite', true);
end

function testSpectralValidation()
    cfg = smallConfig();
    flux = ones(2, 3);
    invalid_flux = {-flux, NaN*flux, Inf*flux, flux+1i, true(2, 3), 'invalid'};
    for k = 1:numel(invalid_flux)
        assertError(@() alev4.simulateDualGainExposure(invalid_flux{k}, cfg, 0, 6207), ...
            'ALEV4:InvalidIrradiance');
    end
    for invalid_shape = {zeros(3, 2), zeros(2, 3, 2), zeros(2, 3, 1, 2)}
        assertError(@() alev4.simulateDualGainExposure(invalid_shape{1}, cfg, 0, 6207), ...
            'ALEV4:IrradianceShape');
    end
    for exposure = {-1, NaN, Inf, 1i, [], [0 1], true, '0'}
        assertError(@() alev4.simulateDualGainExposure(zeros(2, 3), cfg, exposure{1}, 6207), ...
            'ALEV4:InvalidExposure');
    end
    assertError(@() alev4.simulateDualGainExposure(flux, cfg, 0, -1), 'ALEV4:InvalidSeed');
end

function cfg = smallConfig()
    cfg = alev4.createDualGainSensor(struct('sensor', struct('image_size', [2 3], ...
        'wavelength_nm', 550, 'bin_width_nm', 10, 'qe', [0.25 0.5 0.75])));
end

function assertZeroCharge(result)
    for name = {'expected_electrons', 'expected_incident_photons', ...
                'collected_electrons', 'charge_electrons'}
        value = result.(name{1});
        assert(all(value(:) == 0), 'Exact zero collection produced charge.');
    end
end

function assertDense(result)
    for name = {'expected_electrons', 'collected_electrons', 'charge_electrons'}
        value = result.(name{1});
        assert(isa(value, 'double') && ~issparse(value));
    end
    for name = {'high_gain', 'low_gain'}
        path = result.(name{1});
        assert(isa(path.read_electrons, 'double') && ~issparse(path.read_electrons));
        assert(isa(path.raw_dn, 'uint16') && ~issparse(path.raw_dn));
    end
    assert(isa(result.merged.electrons, 'double') && ~issparse(result.merged.electrons));
end

function assertError(callback, identifier)
    caught = false;
    try
        callback();
    catch err
        caught = true;
        assert(strcmp(err.identifier, identifier), ...
            sprintf('Expected %s, received %s.', identifier, err.identifier));
    end
    assert(caught, ['Expected error not raised: ' identifier]);
end
