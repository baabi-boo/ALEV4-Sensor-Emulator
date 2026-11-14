function report = test_phase2_spectral()
%TEST_PHASE2_SPECTRAL Shared integration and dimensional properties of dual gain.
%   Scalar spectral sums and unit conversions provide independent oracles.
%   These tests do not import arbitrary ISET optical images or claim calibrated
%   spectral response. The complete runner retains the separate ISET gate.
    caller_rng = rng;
    guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    names = {'nonuniform_spectral_oracle_and_single_gain_parity', ...
        'qe_exposure_area_fill_and_flux_scaling', ...
        'conserved_bin_refinement_and_grid_order_rejection', ...
        'explicit_energy_conversion_reaches_both_paths_once', ...
        'zero_collection_retains_independent_electronic_readout', ...
        'input_immutability_and_integration_rng_isolation', ...
        'malformed_spectral_input_errors_reach_dual_entrypoint'};
    metrics = testNonuniformParity();
    testScaling();
    testRefinement();
    testEnergyConversion();
    testZeroCollection();
    testInputIsolation();
    testInvalidSpectra();
    tests = repmat(struct('name', '', 'status', 'passed', 'passed', true), ...
        1, numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    report = struct('suite', 'phase2_spectral', 'status', 'passed', ...
        'passed', true, 'test_count', numel(names), 'tests', tests, 'metrics', metrics);
    fprintf('PASS: Phase 2 spectral properties, %d test groups.\n', numel(names));
end

function metrics = testNonuniformParity()
    dimensions = {[1 1], [1 7], [7 1], [5 9]};
    patterns = {'RGGB', 'BGGR', 'GRBG', 'GBRG'};
    max_error = 0;
    for d = 1:numel(dimensions)
        cfg = spectralConfig(dimensions{d});
        cfg.sensor.shot_noise = true;
        irradiance = nonuniformSpectrum(dimensions{d});
        for p = 1:numel(patterns)
            cfg.sensor.cfa_pattern = patterns{p};
            [oracle, photons] = scalarOracle(irradiance, cfg.sensor, 0.012);
            dual = alev4.simulateDualGainExposure(irradiance, cfg, 0.012, 7310);
            single = alev4.simulateExposure(irradiance, cfg.sensor, 0.012, 7310);
            requireNear(dual.expected_electrons, oracle, 'Scalar spectral oracle');
            requireNear(dual.expected_incident_photons, photons, 'Incident photon oracle');
            assert(isequal(single.expected_electrons, dual.expected_electrons));
            assert(isequal(single.expected_incident_photons, dual.expected_incident_photons));
            assert(isequal(single.collected_electrons, dual.collected_electrons), ...
                'The dual spectral wrapper shifted the shared photon realization.');
            assert(isequal(single.charge_electrons, dual.charge_electrons));
            assert(all(dual.expected_electrons(:) <= dual.expected_incident_photons(:)));
            max_error = max(max_error, max(abs(dual.expected_electrons(:) - oracle(:))));
        end
    end
    metrics = struct('nonuniform_configurations', numel(dimensions)*numel(patterns), ...
        'scalar_oracle_max_abs_error_e', max_error);
end

function testScaling()
    cfg = spectralConfig([5 9]);
    irradiance = nonuniformSpectrum(cfg.sensor.image_size);
    exposure = 0.012;
    base = alev4.simulateDualGainExposure(irradiance, cfg, exposure, 7311);
    settings = {cfg, cfg, cfg, cfg, cfg};
    settings{1}.sensor.qe = cfg.sensor.qe / 2;
    settings{3}.sensor.pixel_pitch_m = 2 * cfg.sensor.pixel_pitch_m;
    settings{4}.sensor.fill_factor = cfg.sensor.fill_factor / 3;
    exposures = [exposure, 2*exposure, exposure, exposure, exposure];
    fluxes = [1 1 1 1 2.5];
    electron_factors = [0.5 2 4 1/3 2.5];
    photon_factors = [1 2 4 1/3 2.5];
    for k = 1:numel(settings)
        result = alev4.simulateDualGainExposure(fluxes(k)*irradiance, ...
            settings{k}, exposures(k), 7311);
        requireNear(result.expected_electrons, electron_factors(k)*base.expected_electrons, ...
            'Independent collection-factor scaling');
        requireNear(result.expected_incident_photons, ...
            photon_factors(k)*base.expected_incident_photons, 'Incident collection scaling');
        assert(isequal(result.high_gain.read_electrons, result.expected_electrons));
        assert(isequal(result.low_gain.read_electrons, result.expected_electrons));
    end
end

function testRefinement()
    cfg = spectralConfig([3 7]);
    cfg.sensor.wavelength_nm = [450; 650];
    cfg.sensor.bin_width_nm = [40; 60];
    cfg.sensor.qe = [0.2 0.4 0.6; 0.7 0.3 0.1];
    [rows, columns] = ndgrid(1:3, 1:7);
    irradiance = cat(3, 1e13*(rows + columns/8), 2e13*(columns + rows/5));
    coarse = alev4.simulateDualGainExposure(irradiance, cfg, 0.01, 7312);
    refined = cfg;
    refined.sensor.wavelength_nm = [440; 460; 635; 665];
    refined.sensor.bin_width_nm = [20; 20; 30; 30];
    refined.sensor.qe = cfg.sensor.qe([1 1 2 2], :);
    split = irradiance(:, :, [1 1 2 2]);
    fine = alev4.simulateDualGainExposure(split, refined, 0.01, 7312);
    requireNear(fine.expected_electrons, coarse.expected_electrons, 'Conserved-bin electron integral');
    requireNear(fine.expected_incident_photons, coarse.expected_incident_photons, ...
        'Conserved-bin photon integral');
    % The API requires an increasing explicit grid; it must not silently sort
    % wavelengths while leaving the irradiance/QE channels in another order.
    reversed = cfg;
    reversed.sensor.wavelength_nm = flipud(cfg.sensor.wavelength_nm);
    reversed.sensor.bin_width_nm = flipud(cfg.sensor.bin_width_nm);
    reversed.sensor.qe = flipud(cfg.sensor.qe);
    expectError(@() alev4.simulateDualGainExposure(irradiance(:, :, [2 1]), ...
        reversed, 0.01, 7312), 'ALEV4:InvalidSensorConfig');
    overlap = cfg;
    overlap.sensor.bin_width_nm = [300; 300];
    expectError(@() alev4.simulateDualGainExposure(irradiance, overlap, 0.01, 7312), ...
        'ALEV4:InvalidSensorConfig');
end

function testEnergyConversion()
    cfg = spectralConfig([3 7]);
    energy = nonuniformSpectrum(cfg.sensor.image_size) * 1e-20;
    photons = alev4.energyToPhotons(energy, cfg.sensor.wavelength_nm);
    direct = zeros(size(energy));
    for k = 1:numel(cfg.sensor.wavelength_nm)
        photon_energy = (6.62607015e-34 * 299792458) / ...
            (cfg.sensor.wavelength_nm(k) * 1e-9);
        direct(:, :, k) = energy(:, :, k) / photon_energy;
    end
    requireNear(photons, direct, 'Explicit SI photon-energy conversion');
    [oracle, incident] = scalarOracle(direct, cfg.sensor, 0.02);
    result = alev4.simulateDualGainExposure(photons, cfg, 0.02, 7313);
    requireNear(result.expected_electrons, oracle, 'Energy-origin electron integral');
    requireNear(result.expected_incident_photons, incident, 'Energy-origin photon integral');
    % No unit guessing or hidden second conversion occurs in the spectral API.
    unconverted = alev4.simulateDualGainExposure(energy, cfg, 0.02, 7313);
    assert(max(result.expected_electrons(:)) > ...
        1e12 * max(unconverted.expected_electrons(:)));
    assert(isequal(result.high_gain.read_electrons, result.expected_electrons));
    assert(isequal(result.low_gain.read_electrons, result.expected_electrons));
end

function testZeroCollection()
    cfg = spectralConfig([11 13]);
    cfg.sensor.shot_noise = true;
    cfg.high_gain.read_noise_e = 1;
    cfg.low_gain.read_noise_e = 5;
    irradiance = nonuniformSpectrum(cfg.sensor.image_size);
    no_exposure = alev4.simulateDualGainExposure(irradiance, cfg, 0, 7314);
    empty_area = cfg; empty_area.sensor.fill_factor = 0;
    no_area = alev4.simulateDualGainExposure(irradiance, empty_area, 0.01, 7314);
    dark = alev4.simulateDualGainExposure(zeros(size(irradiance)), cfg, 0.01, 7314);
    zero_qe = cfg; zero_qe.sensor.qe(:) = 0;
    insensitive = alev4.simulateDualGainExposure(irradiance, zero_qe, 0.01, 7314);
    outputs = {no_exposure, no_area, dark, insensitive};
    for k = 1:numel(outputs)
        result = outputs{k};
        assert(~any(result.expected_electrons(:)) && ~any(result.collected_electrons(:)));
        assert(~any(result.full_well_saturated(:)));
        assert(isequal(result.high_gain.read_electrons, no_exposure.high_gain.read_electrons));
        assert(isequal(result.low_gain.read_electrons, no_exposure.low_gain.read_electrons));
    end
    assert(~any(no_exposure.expected_incident_photons(:)) && ...
        ~any(no_area.expected_incident_photons(:)) && ~any(dark.expected_incident_photons(:)));
    assert(all(insensitive.expected_incident_photons(:) > 0), ...
        'Zero QE must not erase the independently retained incident photons.');
    assert(any(no_exposure.high_gain.read_electrons(:) < 0) && ...
        any(no_exposure.high_gain.read_electrons(:) > 0));
    assert(any(no_exposure.low_gain.read_electrons(:) < 0) && ...
        any(no_exposure.low_gain.read_electrons(:) > 0));
end

function testInputIsolation()
    cfg = spectralConfig([5 9]);
    irradiance = single(nonuniformSpectrum(cfg.sensor.image_size));
    original_cfg = cfg;
    original_irradiance = irradiance;
    rng(7315, 'twister'); before = rng;
    [expected, incident, exposure] = alev4.integrateExposure(irradiance, cfg.sensor, single(0.01));
    assert(isequal(before, rng()), 'Noise-free spectral integration consumed RNG values.');
    assert(isa(expected, 'double') && isa(incident, 'double') && isa(exposure, 'double'));
    alev4.simulateDualGainExposure(irradiance, cfg, single(0.01), 7315);
    assert(isequal(before, rng()));
    assert(isequal(cfg, original_cfg) && isequal(irradiance, original_irradiance), ...
        'Spectral entry points changed caller-owned inputs.');
    expectError(@() alev4.simulateDualGainExposure(irradiance(:, :, 1), cfg, 0.01, 7315), ...
        'ALEV4:IrradianceShape');
    assert(isequal(before, rng()));
end

function testInvalidSpectra()
    cfg = spectralConfig([3 7]);
    irradiance = nonuniformSpectrum(cfg.sensor.image_size);
    invalid = {nan(size(irradiance)), inf(size(irradiance)), ...
        -ones(size(irradiance)), irradiance + 1i, true(size(irradiance)), {irradiance}, 'photons'};
    for k = 1:numel(invalid)
        expectError(@() alev4.simulateDualGainExposure(invalid{k}, cfg, 0.01, 7316), ...
            'ALEV4:InvalidIrradiance');
    end
    shapes = {ones(7, 3, 3), ones(3, 7, 2), ones(3, 7, 3, 2), []};
    for k = 1:numel(shapes)
        expectError(@() alev4.simulateDualGainExposure(shapes{k}, cfg, 0.01, 7316), ...
            'ALEV4:IrradianceShape');
    end
    exposures = {-1, nan, inf, 1i, [0.01 0.02], true, '0.01'};
    for k = 1:numel(exposures)
        expectError(@() alev4.simulateDualGainExposure(irradiance, cfg, exposures{k}, 7316), ...
            'ALEV4:InvalidExposure');
    end
end

function cfg = spectralConfig(dimensions)
    sensor = struct('image_size', dimensions, 'wavelength_nm', [450; 550; 650], ...
        'bin_width_nm', [10; 20; 30], ...
        'qe', [0.10 0.25 0.65; 0.30 0.60 0.20; 0.70 0.35 0.05], ...
        'pixel_pitch_m', 3e-6, 'fill_factor', 0.6, 'shot_noise', false);
    cfg = alev4.createDualGainSensor(struct('sensor', sensor, ...
        'high_gain', struct('read_noise_e', 0), 'low_gain', struct('read_noise_e', 0)));
end

function irradiance = nonuniformSpectrum(dimensions)
    [rows, columns] = ndgrid(1:dimensions(1), 1:dimensions(2));
    irradiance = cat(3, 1e13*(0.3 + rows/7 + columns/11), ...
        1e13*(0.6 + rows.*columns/23), 1e13*(0.9 + columns/5 + rows.^2/17));
end

function [electrons, photons] = scalarOracle(irradiance, sensor, exposure)
    electrons = zeros(sensor.image_size);
    photons = zeros(sensor.image_size);
    tile = reshape(sensor.cfa_pattern, 2, 2).';
    labels = 'RGB';
    collection = exposure * sensor.pixel_pitch_m^2 * sensor.fill_factor;
    for row = 1:sensor.image_size(1)
        for column = 1:sensor.image_size(2)
            channel = find(labels == tile(mod(row-1, 2)+1, mod(column-1, 2)+1));
            photon_sum = 0; electron_sum = 0;
            for bin = 1:numel(sensor.wavelength_nm)
                bin_photons = irradiance(row, column, bin) * sensor.bin_width_nm(bin);
                photon_sum = photon_sum + bin_photons;
                electron_sum = electron_sum + bin_photons * sensor.qe(bin, channel);
            end
            photons(row, column) = collection * photon_sum;
            electrons(row, column) = collection * electron_sum;
        end
    end
end

function requireNear(actual, expected, label)
    tolerance = 64 * eps(max([1; abs(expected(:))]));
    assert(isequal(size(actual), size(expected)) && ...
        all(abs(actual(:)-expected(:)) <= tolerance), [label ' disagrees.']);
end

function expectError(action, expected)
    caught = false;
    try
        action();
    catch err
        caught = true;
        assert(strcmp(err.identifier, expected), ...
            ['Expected ' expected ', received ' err.identifier]);
    end
    assert(caught, ['Expected rejection: ' expected]);
end
