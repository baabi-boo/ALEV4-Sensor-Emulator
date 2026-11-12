function report = test_fixture_edges()
%TEST_FIXTURE_EDGES Small geometric and amplitude contracts for irradiance.
%   The fixtures are sensor-plane photon densities, not display images. A
%   one-column ramp is the high endpoint (the documented linspace convention);
%   a checker smaller than its first four-by-four tile can be all black.
    before_rng = rng;
    names = {'degenerate_and_odd_shapes', 'black_flat_and_zero_density', ...
        'ramp_endpoints_and_single_column', 'checker_four_pixel_boundaries', ...
        'identical_spectral_planes', 'invalid_fixture_inputs', ...
        'deterministic_without_rng_consumption'};

    testShapes();
    testLevels();
    testRamp();
    testChecker();
    testSpectralPlanes();
    testInvalidInputs();
    cfg = configuration([5 7]);
    for kind = {'black', 'flat', 'ramp', 'checker'}
        first = alev4.createFixture(kind{1}, cfg, 17);
        second = alev4.createFixture(kind{1}, cfg, 17);
        assert(isequal(first, second), 'Fixtures must be deterministic.');
    end
    assert(isequal(rng, before_rng), 'Fixture generation changed the caller RNG.');

    report = struct('suite', 'fixture_edges', 'passed', true, ...
        'test_count', numel(names), 'tests', {names}, ...
        'one_column_ramp', 'high endpoint', 'checker_tile_size', [4 4]);
    fprintf('PASS: Fixture edges, %d test groups.\n', numel(names));
end

function cfg = configuration(dimensions)
    cfg = alev4.createBaselineSensor(struct('image_size', dimensions, ...
        'wavelength_nm', [450; 550; 650], 'bin_width_nm', [10; 20; 30], ...
        'qe', [0.1 0.2 0.3; 0.4 0.5 0.6; 0.7 0.8 0.9]));
end

function testShapes()
    shapes = {[1 1], [1 9], [9 1], [5 7]};
    for k = 1:numel(shapes)
        cfg = configuration(shapes{k});
        for kind = {'black', 'flat', 'ramp', 'checker'}
            actual = alev4.createFixture(kind{1}, cfg, 17);
            assert(isequal(size(actual), [shapes{k} 3]), ...
                'Fixture changed a degenerate/odd spatial or spectral dimension.');
            assert(isa(actual, 'double') && isreal(actual));
            assert(all(isfinite(actual(:))) && all(actual(:) >= 0 & actual(:) <= 17));
        end
    end
end

function testLevels()
    cfg = configuration([5 7]);
    black = alev4.createFixture('black', cfg, 17);
    flat = alev4.createFixture('flat', cfg, 17);
    assert(isequal(black, zeros(5, 7, 3)), 'Black must be exactly zero.');
    assert(isequal(flat, 17 * ones(5, 7, 3)), 'Flat must preserve photon density.');
    default_flat = alev4.createFixture('flat', cfg);
    assert(isequal(default_flat, 1e13 * ones(5, 7, 3)), 'Default density changed.');
    assert(isequal(alev4.createFixture('FlAt', cfg, 17), flat), ...
        'Fixture names must retain their case-insensitive convention.');
    for kind = {'black', 'flat', 'ramp', 'checker'}
        actual = alev4.createFixture(kind{1}, cfg, 0);
        assert(isequal(actual, black), 'Zero density must zero every fixture.');
    end
end

function testRamp()
    cfg = configuration([3 7]);
    actual = alev4.createFixture('ramp', cfg, 18);
    % Seven positions span six equal intervals; this oracle does not use
    % linspace, the implementation primitive being checked.
    expected = repmat([0 3 6 9 12 15 18], 3, 1);
    difference = actual(:, :, 1) - expected;
    assert(max(abs(difference(:))) <= 8 * eps(18), 'Ramp spacing/endpoints changed.');
    assert(all(actual(:, 1, 1) == 0) && all(actual(:, end, 1) == 18));
    cfg = configuration([5 1]);
    single_column = alev4.createFixture('ramp', cfg, 18);
    assert(isequal(single_column, 18 * ones(5, 1, 3)), ...
        'One-column ramp must retain the high-endpoint convention.');
end

function testChecker()
    cfg = configuration([9 11]);
    actual = alev4.createFixture('checker', cfg, 17);
    first_tile_row = [0 0 0 0 17 17 17 17 0 0 0];
    second_tile_row = [17 17 17 17 0 0 0 0 17 17 17];
    expected = [repmat(first_tile_row, 4, 1); ...
        repmat(second_tile_row, 4, 1); first_tile_row];
    assert(isequal(actual(:, :, 1), expected), ...
        'Checker phase, four-pixel tiles or partial edge tiles changed.');
    small = alev4.createFixture('checker', configuration([3 3]), 17);
    assert(isequal(small, zeros(3, 3, 3)), ...
        'A checker inside its first tile must be black.');
end

function testSpectralPlanes()
    cfg = configuration([5 7]);
    for kind = {'black', 'flat', 'ramp', 'checker'}
        actual = alev4.createFixture(kind{1}, cfg, 17);
        assert(isequal(actual(:, :, 1), actual(:, :, 2)) && ...
            isequal(actual(:, :, 2), actual(:, :, 3)), ...
            'Fixture density must repeat across bins, independent of bin widths/QE.');
    end
end

function testInvalidInputs()
    cfg = configuration([1 1]);
    invalid_names = {'unknown', '', ['flat'; 'ramp'], 1, {'flat'}};
    for k = 1:numel(invalid_names)
        value = invalid_names{k};
        expectError(@() alev4.createFixture(value, cfg, 1), 'ALEV4:InvalidFixture');
    end
    invalid_density = {-1, NaN, Inf, -Inf, 1 + 1i, [1 2], [], '1', true};
    for k = 1:numel(invalid_density)
        value = invalid_density{k};
        expectError(@() alev4.createFixture('flat', cfg, value), 'ALEV4:InvalidIrradiance');
    end
end

function expectError(callback, identifier)
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
