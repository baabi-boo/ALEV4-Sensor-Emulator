function report = test_phase1_core()
%TEST_PHASE1_CORE Executable generic-sensor physical/statistical acceptance.
%   REPORT = TEST_PHASE1_CORE() throws on the first failed assertion. Tests
%   require only the project MATLAB path; no ISETCam or statistics toolbox.
%   Moment tolerances use seven standard errors. Individual binomial/PMF
%   checks use Bernstein bounds at alpha=1e-12 per check, including rare bins
%   where a normal approximation is unreliable. Seeds are fixed. These
%   checks do not establish ALEV4 parity or prove an exact distribution.
    caller_rng = rng;
    restore_rng = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    names = { ...
        'independent_photon_electron_units', ...
        'exposure_intensity_area_qe_linearity', ...
        'zero_signal_endpoints', ...
        'all_bayer_phases_odd_dimensions', ...
        'energy_to_photon_si_conversion', ...
        'poisson_mean_variance_and_probabilities', ...
        'gaussian_read_noise_and_signed_dark', ...
        'full_well_and_adc_boundaries', ...
        'seed_reproducibility_and_rng_isolation', ...
        'noisy_boundary_seeds_and_late_failure_isolation', ...
        'invalid_configuration_and_signal_rejection', ...
        'controlled_spectral_fixtures', ...
        'poisson_shapes_and_zero_counts'};

    metrics = struct();
    metrics.analytical = testAnalytical();
    testLinearity();
    testZeros();
    testCfa();
    testEnergy();
    metrics.poisson = testPoissonStatistics();
    metrics.read_noise = testReadNoise();
    testReadoutBoundaries();
    testReproducibility();
    testBoundarySeeds();
    metrics.rejected_inputs = testRejection();
    testFixtures();
    testPoissonShapes();

    report = struct('suite', 'phase1_core', 'passed', true, ...
        'test_count', numel(names), 'tests', {names}, 'metrics', metrics, ...
        'runtime_version', version());
    fprintf('PASS: Phase 1 core, %d test groups.\n', numel(names));
end

function [cfg, flux] = analyticalFixture()
    cfg = alev4.createBaselineSensor(struct( ...
        'image_size', [3 5], 'wavelength_nm', [500; 600], ...
        'bin_width_nm', [10; 20], ...
        'qe', [0.5 0.5 0.5; 0.25 0.25 0.25], ...
        'pixel_pitch_m', 2e-6, 'fill_factor', 1, ...
        'shot_noise', false, 'read_noise_e', 0));
    flux = zeros(3, 5, 2);
    flux(:, :, 1) = 2e12;
    flux(:, :, 2) = 1e12;
end

function metrics = testAnalytical()
    [cfg, flux] = analyticalFixture();
    result = alev4.simulateExposure(flux, cfg, 0.1, 11);
    % Independent hand calculation:
    % 0.1 * 4e-12 * (2e12*.5*10 + 1e12*.25*20) = 6 e-.
    closeTo(result.expected_electrons, 6 * ones(3, 5), 1e-12, 1e-12, 'two-bin electrons');
    closeTo(result.expected_incident_photons, 16 * ones(3, 5), 1e-12, 1e-12, 'two-bin photons');
    assert(isequal(result.expected_electrons, result.collected_electrons), 'Noise-off collection must equal expectation.');
    assert(isa(result.raw_dn, 'uint16'), 'RAW storage must be uint16.');
    assert(isequal(result.raw_dn, uint16(67 * ones(3, 5))), '6 e- at 0.5 DN/e- plus 64 DN must be 67 DN.');
    metrics = struct('expected_electrons', 6, 'measured_electrons', result.expected_electrons(1), ...
        'expected_incident_photons', 16, 'measured_incident_photons', result.expected_incident_photons(1));
end

function testLinearity()
    [cfg, flux] = analyticalFixture();
    factors = [0 0.25 0.5 1 2 4];
    for k = 1:numel(factors)
        scale = factors(k);
        r = alev4.simulateExposure(flux, cfg, 0.1 * scale, 12);
        closeTo(r.expected_electrons, 6 * scale * ones(3, 5), 1e-12, 1e-12, 'exposure linearity');
        r = alev4.simulateExposure(flux .* scale, cfg, 0.1, 12);
        closeTo(r.expected_electrons, 6 * scale * ones(3, 5), 1e-12, 1e-12, 'irradiance linearity');
    end
    altered = cfg; altered.pixel_pitch_m = 2 * cfg.pixel_pitch_m;
    r = alev4.simulateExposure(flux, altered, 0.1, 12);
    closeTo(r.expected_electrons, 24 * ones(3, 5), 1e-12, 1e-12, 'pixel area');
    altered = cfg; altered.fill_factor = 0.5;
    r = alev4.simulateExposure(flux, altered, 0.1, 12);
    closeTo(r.expected_electrons, 3 * ones(3, 5), 1e-12, 1e-12, 'fill factor applied once');
    altered = cfg; altered.qe = 0.5 * cfg.qe;
    r = alev4.simulateExposure(flux, altered, 0.1, 12);
    closeTo(r.expected_electrons, 3 * ones(3, 5), 1e-12, 1e-12, 'QE applied once');
    altered.qe = ones(size(cfg.qe));
    r = alev4.simulateExposure(flux, altered, 0.1, 12);
    closeTo(r.expected_electrons, r.expected_incident_photons, 1e-12, 1e-12, 'unit QE');
end

function testZeros()
    [cfg, flux] = analyticalFixture();
    variants = {cfg, cfg, cfg, cfg};
    variants{3}.qe(:) = 0;
    variants{4}.fill_factor = 0;
    for k = 1:4
        input = flux; exposure = 0.1;
        if k == 1, input(:) = 0; end
        if k == 2, exposure = 0; end
        r = alev4.simulateExposure(input, variants{k}, exposure, 13);
        assert(all(r.expected_electrons(:) == 0), 'Zero signal endpoint must be exactly zero.');
        assert(all(r.collected_electrons(:) == 0), 'Noise-off zero signal must remain zero.');
        assert(all(r.raw_dn(:) == 64), 'Zero signal must retain the configured black offset.');
    end
end

function testCfa()
    patterns = {'RGGB', 'BGGR', 'GRBG', 'GBRG'};
    tiles = {[1 2; 2 3], [3 2; 2 1], [2 1; 3 2], [2 3; 1 2]};
    cfg = alev4.createBaselineSensor(struct('image_size', [3 5], ...
        'wavelength_nm', 550, 'bin_width_nm', 10, 'qe', [0.2 0.4 0.6], ...
        'pixel_pitch_m', 5e-6, 'fill_factor', 1, 'shot_noise', false, 'read_noise_e', 0));
    flux = 1e13 * ones(3, 5);
    values = [5 10 15]; % t=.01 s, area=25e-12 m2, width=10 nm.
    for p = 1:numel(patterns)
        cfg.cfa_pattern = patterns{p};
        map = alev4.cfaMap([3 5], patterns{p});
        r = alev4.simulateExposure(flux, cfg, 0.01, 14);
        for row = 1:3
            for col = 1:5
                expected_channel = tiles{p}(mod(row-1, 2)+1, mod(col-1, 2)+1);
                assert(map(row, col) == expected_channel, 'CFA phase/origin mismatch.');
                closeTo(r.expected_electrons(row, col), values(expected_channel), 1e-12, 1e-12, 'CFA electron assignment');
            end
        end
    end
    assert(isequal(alev4.cfaMap([1 1], 'gbrg'), 2), 'Single-pixel lowercase CFA handling failed.');
end

function testEnergy()
    wave = [450; 650];
    energy = zeros(2, 3, 2);
    energy(:, :, 1) = 6.62607015e-34 * 299792458 / (450e-9);
    energy(:, :, 2) = 2 * 6.62607015e-34 * 299792458 / (650e-9);
    converted = alev4.energyToPhotons(energy, wave);
    expected = ones(2, 3, 2); expected(:, :, 2) = 2;
    closeTo(converted, expected, 1e-14, 1e-14, 'SI photon energy');
    zero_photons = alev4.energyToPhotons(zeros(2, 3), 500);
    assert(all(zero_photons(:) == 0), 'Zero spectral energy must give zero photons.');
end

function metrics = testPoissonStatistics()
    n = 100000;
    means = [0.1 1 10 1000];
    probability_alpha = 1e-12;
    cfg = alev4.createBaselineSensor(struct('image_size', [1000 100], ...
        'full_well_e', 1e6, 'read_noise_e', 0));
    metrics = repmat(struct('lambda', 0, 'samples', n, 'mean', 0, ...
        'variance', 0, 'mean_tolerance', 0, 'variance_tolerance', 0, ...
        'maximum_probability_error', 0, 'probability_check_count', 0, ...
        'probability_alpha_per_check', probability_alpha, ...
        'probability_bound', 'Bernstein', 'neighbor_covariance', 0), 1, numel(means));
    for k = 1:numel(means)
        lambda = means(k);
        r = alev4.applyNoise(lambda * ones(cfg.image_size), cfg, 200 + k);
        x = r.collected_electrons(:);
        assert(all(x >= 0 & x == floor(x)), 'Poisson samples must be nonnegative integers.');
        measured_mean = mean(x); measured_variance = var(x, 0);
        mean_tolerance = 7 * sqrt(lambda / n);
        variance_tolerance = 7 * sqrt(lambda / n + 2 * lambda^2 / (n-1));
        assert(abs(measured_mean-lambda) <= mean_tolerance, 'Poisson empirical mean exceeds seven standard errors.');
        assert(abs(measured_variance-lambda) <= variance_tolerance, 'Poisson variance does not track mean electrons.');
        max_error = 0;
        probability_checks = 0;
        if lambda <= 1
            for count = 0:5
                probability = exp(-lambda) * lambda^count / factorial(count);
                observed = sum(x == count) / n;
                % A histogram count is binomial under the Poisson model.
                % Bernstein remains conservative even when N*p is far
                % below one; a seven-normal-SE window does not.
                log_tail = log(2 / probability_alpha);
                tolerance = sqrt(2 * probability * (1-probability) * log_tail / n) + ...
                    2 * log_tail / (3 * n);
                assert(abs(observed-probability) <= tolerance, 'Low-count Poisson probability mismatch.');
                max_error = max(max_error, abs(observed-probability));
                probability_checks = probability_checks + 1;
            end
        end
        % Disjoint neighboring pairs avoid overlap in the covariance check.
        covariance = mean((x(1:2:end)-lambda) .* (x(2:2:end)-lambda));
        assert(abs(covariance) <= 7 * lambda / sqrt(n/2), 'Unexpected neighboring shot-noise correlation.');
        metrics(k) = struct('lambda', lambda, 'samples', n, 'mean', measured_mean, ...
            'variance', measured_variance, 'mean_tolerance', mean_tolerance, ...
            'variance_tolerance', variance_tolerance, 'maximum_probability_error', max_error, ...
            'probability_check_count', probability_checks, ...
            'probability_alpha_per_check', probability_alpha, ...
            'probability_bound', 'Bernstein', ...
            'neighbor_covariance', covariance);
    end
end

function metrics = testReadNoise()
    n = 100000; sigma = 3;
    cfg = alev4.createBaselineSensor(struct('image_size', [1000 100], ...
        'shot_noise', false, 'read_noise_e', sigma, 'black_level_dn', 64));
    r = alev4.applyNoise(zeros(cfg.image_size), cfg, 301);
    x = r.read_electrons(:);
    mean_tolerance = 7 * sigma / sqrt(n);
    variance_tolerance = 7 * sigma^2 * sqrt(2 / (n-1));
    assert(abs(mean(x)) <= mean_tolerance, 'Read-noise mean is biased.');
    assert(abs(var(x, 0)-sigma^2) <= variance_tolerance, 'Read-noise RMS does not match configuration.');
    assert(any(x < 0) && any(x > 0), 'Signed pre-ADC dark noise must be preserved.');
    assert(all(r.charge_electrons(:) == 0), 'Read noise must be added after charge accumulation.');
    metrics = struct('samples', n, 'sigma_e', sigma, 'mean_e', mean(x), ...
        'variance_e2', var(x, 0), 'mean_tolerance', mean_tolerance, ...
        'variance_tolerance', variance_tolerance);
    cfg.read_noise_e = 0;
    r = alev4.applyNoise(2.75 * ones(cfg.image_size), cfg, 302);
    assert(all(r.read_electrons(:) == 2.75), 'Zero read noise must retain fractional analog charge.');
end

function testReadoutBoundaries()
    cfg = alev4.createBaselineSensor(struct('image_size', [1 5], ...
        'shot_noise', false, 'read_noise_e', 0, 'full_well_e', 1000, ...
        'gain_dn_per_e', 0.25, 'black_level_dn', 64, 'adc_bits', 12));
    r = alev4.applyNoise([0 999 1000 1001 100000], cfg, 401);
    assert(isequal(r.charge_electrons, [0 999 1000 1000 1000]), 'Full-well clipping boundary failed.');
    assert(isequal(r.full_well_saturated, logical([0 0 1 1 1])), 'Physical saturation mask failed.');
    assert(isequal(r.raw_dn, uint16([64 314 314 314 314])), 'Gain/black-level/rounding order failed.');
    assert(~any(r.adc_high_clipped), 'Full-well saturation is not necessarily ADC clipping.');
    cfg.image_size = [1 8]; cfg.full_well_e = 1e6;
    cfg.gain_dn_per_e = 1; cfg.black_level_dn = 0;
    r = alev4.applyNoise([0 0.49 0.5 1.5 4094.49 4094.5 4095.49 4095.5], cfg, 402);
    assert(isequal(r.raw_dn, uint16([0 0 1 2 4094 4095 4095 4095])), 'ADC quantization boundaries failed.');
    assert(isequal(r.adc_high_clipped, logical([0 0 0 0 0 0 0 1])), 'ADC overflow mask must use rounded code.');
    assert(~any(r.full_well_saturated), 'ADC clipping must not imply physical full-well saturation.');
    cfg.image_size = [100 100]; cfg.read_noise_e = 10;
    r = alev4.applyNoise(zeros(cfg.image_size), cfg, 403);
    expected_low = round(r.read_electrons) < 0;
    assert(isequal(r.adc_low_clipped, expected_low), 'Low-ADC clipping mask failed.');
    assert(any(expected_low(:)) && all(r.raw_dn(expected_low) == 0), 'Negative readout must clamp only at the ADC.');
    for bits = [1 8 16]
        cfg.adc_bits = bits; cfg.read_noise_e = 0;
        r = alev4.applyNoise(1e5 * ones(cfg.image_size), cfg, 404);
        assert(all(double(r.raw_dn(:)) == 2^bits-1), 'Configured ADC depth must constrain the uint16 payload.');
    end
end

function testReproducibility()
    cfg = alev4.createBaselineSensor(struct('image_size', [20 30]));
    expectation = 42 * ones(cfg.image_size);
    rng(987, 'twister'); before = rng;
    first = alev4.applyNoise(expectation, cfg, 501);
    after = rng;
    assert(isequal(before, after), 'Simulation must restore the caller RNG state.');
    second = alev4.applyNoise(expectation, cfg, 501);
    assert(isequal(first, second), 'Identical seed/configuration must reproduce all result arrays.');
    third = alev4.applyNoise(expectation, cfg, 502);
    assert(~isequal(first.collected_electrons, third.collected_electrons), 'Different seeds must change a nontrivial shot realization.');
    assertError(@() alev4.applyNoise(1e9 + expectation, cfg, 503), 'ALEV4:InvalidPoissonMean');
    assert(isequal(before, rng()), 'RNG state must also restore after sampling error.');
    cfg.shot_noise = false; cfg.read_noise_e = 0;
    first = alev4.applyNoise(expectation, cfg, 504);
    second = alev4.applyNoise(expectation, cfg, 505);
    assert(isequal(first.raw_dn, second.raw_dn), 'Noise-disabled RAW must be seed-independent.');
    assert(isequal(first.collected_electrons, second.collected_electrons), 'Noise-disabled charge must be seed-independent.');
end

function testBoundarySeeds()
    cfg = alev4.createBaselineSensor(struct('image_size', [5 7], ...
        'shot_noise', true, 'read_noise_e', 3));
    % Both Poisson regimes and a zero-mean column share each seeded run.
    expectation = repmat([0 0.25 9.999 10 10.001 42 100], 5, 1);
    for seed = [0 4294967295]
        rng(988, 'twister');
        rand(2, 3); randn(3, 2); % Exercise both caller streams before capture.
        before = rng;
        first = alev4.applyNoise(expectation, cfg, seed);
        assert(isequal(before, rng()), ...
            'Noisy boundary-seed success must restore caller RNG state.');
        assert(first.seed == seed, 'Boundary seed must be retained exactly.');
        assert(any(first.collected_electrons(:) ~= expectation(:)), ...
            'Boundary-seed regression must exercise nontrivial shot noise.');
        assert(any(first.read_electrons(:) ~= first.charge_electrons(:)), ...
            'Boundary-seed regression must exercise Gaussian read noise.');
        second = alev4.applyNoise(expectation, cfg, seed);
        assert(isequal(first, second), ...
            'Boundary seeds must reproduce the complete noisy result.');
        assert(isequal(before, rng()), ...
            'Repeated boundary-seed simulation must restore caller RNG state.');

        % Only the final gain changes: identical seeded shot/read draws now
        % overflow after both random stages. This is not a preflight error.
        assert(any(abs(first.read_electrons(:)) > 1), ...
            'The seeded fixture must produce a signal that overflows realmax gain.');
        overflow_cfg = cfg;
        overflow_cfg.gain_dn_per_e = realmax;
        assertError(@() alev4.applyNoise(expectation, overflow_cfg, seed), ...
            'ALEV4:ReadoutOverflow');
        assert(isequal(before, rng()), ...
            'Boundary-seed late readout failure must restore both caller RNG streams.');
        after_failure = alev4.applyNoise(expectation, cfg, seed);
        assert(isequal(first, after_failure), ...
            'A late readout failure must not affect subsequent seeded results.');
        assert(isequal(before, rng()), ...
            'Post-failure boundary-seed simulation must preserve caller RNG state.');
    end
end

function count = testRejection()
    [cfg, flux] = analyticalFixture();
    tests = { ...
        @() alev4.createBaselineSensor(struct('typo_gain', 1)), 'ALEV4:UnknownSensorField'; ...
        @() alev4.createBaselineSensor(struct('qe', NaN(16, 3))), 'ALEV4:InvalidSensorConfig'; ...
        @() alev4.createBaselineSensor(struct('qe', 1.1*ones(16, 3))), 'ALEV4:InvalidSensorConfig'; ...
        @() alev4.createBaselineSensor(struct('pixel_pitch_m', 0)), 'ALEV4:InvalidSensorConfig'; ...
        @() alev4.createBaselineSensor(struct('fill_factor', -0.1)), 'ALEV4:InvalidSensorConfig'; ...
        @() alev4.createBaselineSensor(struct('adc_bits', 17)), 'ALEV4:InvalidSensorConfig'; ...
        @() alev4.createBaselineSensor(struct('shot_noise', 1)), 'ALEV4:InvalidSensorConfig'; ...
        @() alev4.createBaselineSensor(struct('wavelength_nm', [500; 500])), 'ALEV4:InvalidSensorConfig'; ...
        @() alev4.createBaselineSensor(struct('bin_width_nm', zeros(16, 1))), 'ALEV4:InvalidSensorConfig'; ...
        @() alev4.cfaMap([3 5], 'RGBW'), 'ALEV4:InvalidCFA'; ...
        @() alev4.cfaMap([0 5], 'RGGB'), 'ALEV4:InvalidImageSize'; ...
        @() alev4.simulateExposure(-flux, cfg, 0.1, 1), 'ALEV4:InvalidIrradiance'; ...
        @() alev4.simulateExposure(NaN(size(flux)), cfg, 0.1, 1), 'ALEV4:InvalidIrradiance'; ...
        @() alev4.simulateExposure(flux(:, :, 1), cfg, 0.1, 1), 'ALEV4:IrradianceShape'; ...
        @() alev4.simulateExposure(flux, cfg, -0.1, 1), 'ALEV4:InvalidExposure'; ...
        @() alev4.simulateExposure(flux, cfg, Inf, 1), 'ALEV4:InvalidExposure'; ...
        @() alev4.applyNoise(-ones(3, 5), cfg, 1), 'ALEV4:InvalidExpectedElectrons'; ...
        @() alev4.applyNoise(ones(5, 3), cfg, 1), 'ALEV4:InvalidExpectedElectrons'; ...
        @() alev4.applyNoise(ones(3, 5), cfg, -1), 'ALEV4:InvalidSeed'; ...
        @() alev4.applyNoise(ones(3, 5), cfg, 0.5), 'ALEV4:InvalidSeed'; ...
        @() alev4.applyNoise(ones(3, 5), cfg, 4294967296), 'ALEV4:InvalidSeed'; ...
        @() alev4.samplePoisson(-1), 'ALEV4:InvalidPoissonMean'; ...
        @() alev4.samplePoisson(Inf), 'ALEV4:InvalidPoissonMean'; ...
        @() alev4.samplePoisson(1e9+1), 'ALEV4:InvalidPoissonMean'; ...
        @() alev4.energyToPhotons(-ones(2, 2), 500), 'ALEV4:InvalidEnergy'; ...
        @() alev4.energyToPhotons(ones(2, 2), [400 500]), 'ALEV4:InvalidWavelength'; ...
        @() alev4.createFixture('unknown', cfg), 'ALEV4:InvalidFixture'; ...
        @() alev4.createFixture('flat', cfg, -1), 'ALEV4:InvalidIrradiance'};
    for k = 1:size(tests, 1)
        assertError(tests{k, 1}, tests{k, 2});
    end
    count = size(tests, 1);
end

function testFixtures()
    cfg = alev4.createBaselineSensor(struct('image_size', [9 7]));
    level = 23;
    flat = alev4.createFixture('flat', cfg, level);
    black = alev4.createFixture('black', cfg, level);
    ramp = alev4.createFixture('ramp', cfg, level);
    checker = alev4.createFixture('checker', cfg, level);
    assert(isequal(size(flat), [9 7 numel(cfg.wavelength_nm)]), 'Fixture dimensions must match the sensor.');
    assert(all(flat(:) == level) && all(black(:) == 0), 'Flat/black fixture levels must be exact.');
    first = ramp(:, 1, :); last = ramp(:, end, :);
    assert(all(first(:) == 0) && all(last(:) == level), 'Ramp endpoints failed.');
    steps = diff(ramp, 1, 2);
    assert(all(steps(:) >= 0), 'Ramp must be monotonic.');
    assert(all(checker(:) == 0 | checker(:) == level), 'Checker fixture must contain only the two specified levels.');
    assert(any(checker(:) == 0) && any(checker(:) == level), 'Checker fixture must exercise both states.');
    assert(isequal(ramp(:, :, 1), ramp(:, :, end)), 'Flat-spectrum fixture must share spatial structure at every wavelength.');
end

function testPoissonShapes()
    shapes = {[1 1], [1 11], [11 1], [3 5]};
    rng(601, 'twister');
    for k = 1:numel(shapes)
        zero_samples = alev4.samplePoisson(zeros(shapes{k}));
        assert(isequal(size(zero_samples), shapes{k}) && all(zero_samples(:) == 0), 'Zero-count shape handling failed.');
        samples = alev4.samplePoisson(10 * ones(shapes{k}));
        assert(isequal(size(samples), shapes{k}), 'Poisson sampler changed array shape.');
        assert(all(samples(:) >= 0 & samples(:) == fix(samples(:))), 'Poisson output must contain counts.');
    end
end

function closeTo(actual, expected, absolute_tolerance, relative_tolerance, label)
    assert(isequal(size(actual), size(expected)), [label ': shape mismatch.']);
    difference = abs(double(actual)-double(expected));
    tolerance = absolute_tolerance + relative_tolerance * abs(double(expected));
    assert(all(isfinite(actual(:))) && all(difference(:) <= tolerance(:)), [label ': numeric mismatch.']);
end

function assertError(callback, expected_identifier)
    caught = false;
    try
        callback();
    catch exception
        caught = true;
        assert(strcmp(exception.identifier, expected_identifier), ...
            sprintf('Expected %s, received %s.', expected_identifier, exception.identifier));
    end
    assert(caught, ['Expected error was not raised: ' expected_identifier]);
end
