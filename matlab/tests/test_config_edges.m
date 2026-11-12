function report = test_config_edges()
%TEST_CONFIG_EDGES Configuration bounds and spectral-grid regression tests.
%   These tests never allocate a large image: limit-sized dimensions are
%   validated as configuration only, and oversized CFA requests must fail
%   before allocation. Sparse spectral fields are exercised on a 3x5 image.
    caller_rng = rng;
    guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    names = {'image_limits_without_large_allocation', ...
        'sparse_configuration_is_dense_and_equivalent', ...
        'local_spectral_overlap_tolerance', ...
        'single_and_touching_spectral_bins'};

    testImageLimits();
    testSparseConfiguration();
    testLocalTolerance();
    testBinEdges();

    report = struct('suite', 'config_edges', 'passed', true, ...
        'test_count', numel(names), 'tests', {names});
    fprintf('PASS: Configuration edge regressions, %d test groups.\n', numel(names));
end

function testImageLimits()
    % The sensor constructor stores dimensions without allocating an image.
    valid = {[1 1e8], [1e8 1], [10000 10000], [9999 10000]};
    for k = 1:numel(valid)
        cfg = alev4.createBaselineSensor(struct('image_size', valid{k}));
        assert(isequal(cfg.image_size, valid{k}), 'A valid image bound was changed.');
    end
    invalid = {[1 1e8+1], [1e8+1 1], [10000 10001], ...
        [1e8 2], [realmax 2], [1e200 1e200]};
    for k = 1:numel(invalid)
        dimensions = invalid{k};
        expectError(@() alev4.createBaselineSensor(struct('image_size', dimensions)), ...
            'ALEV4:InvalidSensorConfig');
        expectError(@() alev4.cfaMap(dimensions, 'RGGB'), 'ALEV4:InvalidImageSize');
    end
    % A sparse size vector must be normalized before colon/index generation.
    small = alev4.cfaMap(sparse([3 5]), 'RGGB');
    assert(isequal(small, [1 2 1 2 1; 2 3 2 3 2; 1 2 1 2 1]), ...
        'Sparse image-size vector changed CFA placement.');
end

function testSparseConfiguration()
    options = struct('image_size', [3 5], 'wavelength_nm', [500; 600], ...
        'bin_width_nm', [10; 20], 'qe', [0.5 0.25 0; 0.1 0.2 0.3], ...
        'pixel_pitch_m', 2e-6, 'fill_factor', 0.5, ...
        'read_noise_e', 0, 'shot_noise', false);
    dense = alev4.createBaselineSensor(options);
    numeric_fields = {'image_size', 'wavelength_nm', 'bin_width_nm', 'qe', ...
        'pixel_pitch_m', 'fill_factor', 'read_noise_e'};
    for k = 1:numel(numeric_fields)
        field = numeric_fields{k};
        options.(field) = sparse(options.(field));
    end
    options.shot_noise = sparse(false);
    canonical = alev4.createBaselineSensor(options);
    assert(isequal(canonical, dense), 'Sparse configuration must preserve dense semantics.');
    for k = 1:numel(numeric_fields)
        assert(~issparse(canonical.(numeric_fields{k})), ...
            'Sparse numeric configuration survived canonicalization.');
    end
    assert(~issparse(canonical.shot_noise), 'Sparse logical flag survived canonicalization.');
    photons = zeros(3, 5, 2);
    photons(:, :, 1) = 2e12;
    photons(:, :, 2) = 1e12;
    expected = alev4.simulateExposure(photons, dense, 0.1, 2301);
    observed = alev4.simulateExposure(photons, options, 0.1, 2301);
    assert(isequal(observed.expected_electrons, expected.expected_electrons), ...
        'Sparse configuration changed integrated expectations.');
    assert(isequal(observed.raw_dn, expected.raw_dn), ...
        'Sparse configuration changed the RAW frame.');
end

function testLocalTolerance()
    % Bins centred at 500 and 510 nm overlap by one nm. A remote huge
    % wavelength must not provide its much larger ULP as their tolerance.
    invalid = struct('wavelength_nm', [500; 510; 1e20], ...
        'bin_width_nm', [11; 11; 1e6], 'qe', 0.5 * ones(3, 3));
    expectError(@() alev4.createBaselineSensor(invalid), 'ALEV4:InvalidSensorConfig');
    invalid.bin_width_nm = [10.001; 10.001; 1e6];
    expectError(@() alev4.createBaselineSensor(invalid), 'ALEV4:InvalidSensorConfig');
    valid = invalid;
    valid.bin_width_nm = [10; 10; 1e6];
    cfg = alev4.createBaselineSensor(valid);
    assert(isequal(cfg.bin_width_nm, valid.bin_width_nm), ...
        'Touching early bins plus a distant bin should be valid.');
end

function testBinEdges()
    single_bin = alev4.createBaselineSensor(struct('wavelength_nm', 550, ...
        'bin_width_nm', 10, 'qe', [0.2 0.4 0.6]));
    assert(numel(single_bin.wavelength_nm) == 1, 'Single-bin validation failed.');
    adjacent = struct('wavelength_nm', [500; 510; 520], ...
        'bin_width_nm', [10; 10; 10], 'qe', 0.5 * ones(3, 3));
    cfg = alev4.createBaselineSensor(adjacent);
    assert(isequal(cfg.wavelength_nm, adjacent.wavelength_nm), ...
        'Exactly touching bins should remain valid.');
    adjacent.bin_width_nm(2) = 10 + 128 * eps(510);
    expectError(@() alev4.createBaselineSensor(adjacent), 'ALEV4:InvalidSensorConfig');
end

function expectError(callback, identifier)
    caught = false;
    try
        callback();
    catch err
        caught = true;
        assert(strcmp(err.identifier, identifier), ...
            sprintf('Expected %s but got %s.', identifier, err.identifier));
    end
    assert(caught, ['Expected rejection: ' identifier]);
end
