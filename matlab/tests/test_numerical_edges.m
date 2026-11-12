function report = test_numerical_edges()
%TEST_NUMERICAL_EDGES Regression tests for signal endpoints and readout order.
%   No toolbox or ISET dependency is required. Errors propagate to the caller.
    caller_rng = rng;
    guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    names = {'zero_collection_with_extreme_finite_flux', ...
        'zero_irradiance_with_extreme_collection', ...
        'zero_exposure_retains_signed_read_noise', ...
        'read_noise_after_physical_saturation', ...
        'readout_overflow_restores_rng', ...
        'positive_collection_underflow_rejected'};

    testZeroCollection();
    testZeroIrradiance();
    metrics = testZeroExposureReadNoise();
    testSaturationReadNoise();
    testReadoutOverflow();
    testCollectionUnderflow();

    report = struct('suite', 'numerical_edges', 'passed', true, ...
        'test_count', numel(names), 'tests', {names}, 'metrics', metrics);
    fprintf('PASS: Numerical edge regressions, %d test groups.\n', numel(names));
end

function testZeroCollection()
    cfg = alev4.createBaselineSensor(struct('image_size', [3 5]));
    flux = realmax * ones(3, 5, numel(cfg.wavelength_nm));
    zero_time = alev4.simulateExposure(flux, cfg, 0, 701);
    assertZeroCharge(zero_time);
    cfg.fill_factor = 0;
    zero_area = alev4.simulateExposure(flux, cfg, realmax, 701);
    assertZeroCharge(zero_area);
    assert(isequal(zero_time.read_electrons, zero_area.read_electrons), ...
        'Equal zero-charge states and seed must produce the same read noise.');
    assertError(@() alev4.simulateExposure(flux, cfg, 0, -1), 'ALEV4:InvalidSeed');
end

function testZeroIrradiance()
    cfg = alev4.createBaselineSensor(struct('image_size', [2 3], ...
        'pixel_pitch_m', 1e150, 'fill_factor', 1));
    flux = zeros(2, 3, numel(cfg.wavelength_nm));
    result = alev4.simulateExposure(flux, cfg, 1e100, 702);
    assertZeroCharge(result);
    assert(all(isfinite(result.read_electrons(:))), 'Black input readout must remain finite.');
end

function metrics = testZeroExposureReadNoise()
    cfg = alev4.createBaselineSensor(struct('image_size', [100 100], ...
        'shot_noise', true, 'read_noise_e', 3));
    flux = alev4.createFixture('flat', cfg, 1e15);
    result = alev4.simulateExposure(flux, cfg, 0, 703);
    assertZeroCharge(result);
    x = result.read_electrons(:);
    assert(any(x < 0) && any(x > 0), ...
        'Zero exposure must preserve signed, nonzero electronic read noise.');
    assert(var(x, 0) > 0, 'Read noise cannot be disabled by a zero exposure.');
    metrics = struct('zero_exposure_read_variance_e2', var(x, 0));
end

function testSaturationReadNoise()
    cfg = alev4.createBaselineSensor(struct('image_size', [100 100], ...
        'shot_noise', false, 'read_noise_e', 5, 'full_well_e', 100));
    result = alev4.applyNoise(1000 * ones(cfg.image_size), cfg, 704);
    assert(all(result.charge_electrons(:) == 100), 'Charge must clip to full well.');
    assert(all(result.full_well_saturated(:)), 'All illuminated wells must be marked saturated.');
    assert(any(result.read_electrons(:) > 100) && any(result.read_electrons(:) < 100), ...
        'Post-well read noise must not be clipped a second time at full well.');
end

function testReadoutOverflow()
    cfg = alev4.createBaselineSensor(struct('image_size', [10 10], ...
        'shot_noise', false, 'read_noise_e', 1, 'gain_dn_per_e', realmax));
    rng(705, 'twister');
    before = rng;
    assertError(@() alev4.applyNoise(100 * ones(cfg.image_size), cfg, 706), ...
        'ALEV4:ReadoutOverflow');
    assert(isequal(before, rng()), 'Readout overflow must restore the caller RNG state.');
end

function testCollectionUnderflow()
    cfg = alev4.createBaselineSensor(struct('image_size', [2 3], ...
        'pixel_pitch_m', 1e-100, 'fill_factor', 1, ...
        'wavelength_nm', 550, 'bin_width_nm', 1, 'qe', ones(1, 3)));
    % The separated collection factor is 1e-400, yet the full mathematical
    % product with 1e300 irradiance is 1e-100. Reject the unsupported dynamic
    % range explicitly instead of falsely returning zero signal.
    assertError(@() alev4.simulateExposure(1e300 * ones(2, 3), cfg, 1e-200, 707), ...
        'ALEV4:CollectionUnderflow');
end

function assertZeroCharge(result)
    assert(all(result.expected_electrons(:) == 0), 'Expected electrons must be exactly zero.');
    assert(all(result.expected_incident_photons(:) == 0), 'Incident photon expectation must be zero.');
    assert(all(result.collected_electrons(:) == 0), 'Zero expectation cannot produce shot charge.');
    assert(all(result.charge_electrons(:) == 0), 'Stored charge must remain zero.');
end

function assertError(callback, identifier)
    caught = false;
    try
        callback();
    catch err
        caught = true;
        assert(strcmp(err.identifier, identifier), ...
            sprintf('Expected %s but got %s.', identifier, err.identifier));
    end
    assert(caught, ['Expected error not raised: ' identifier]);
end
