function report = test_phase4_config()
%TEST_PHASE4_CONFIG Strict fixed-map schema, crop identity and pure validation.
%   All maps are explicit synthetic fixtures. No stochastic distribution or
%   camera-calibration claim follows from these deterministic checks.
    caller_rng = rng;
    guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    names = {'defaults_partial_revalidation', ...
        'strict_schema_fields_and_structure', ...
        'strict_grid_and_full_grid_match', ...
        'nonnegative_maps_and_signed_offsets', ...
        'rms_and_temperature_ranges', ...
        'realization_and_source_identifiers', ...
        'numeric_representation_canonicalization', ...
        'all_bayer_roi_parity_map_identity', ...
        'constructor_map_rng_and_caller_isolation'};
    testDefaults();
    testStructure();
    testGrid();
    testMaps();
    testRmsAndTemperature();
    testIdentifiers();
    classes = testRepresentations();
    crop_cases = testCropIdentity();
    testIsolation();
    tests = repmat(struct('name', '', 'status', 'passed', 'passed', true), ...
        1, numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    metrics = struct('numeric_classes', {classes}, ...
        'bayer_roi_parity_cases', crop_cases, 'full_grid_size', [5 7], ...
        'fixed_map_comparison_tolerance', 0, 'expected_random_draws', 0);
    report = struct('suite', 'phase4_config', 'status', 'passed', ...
        'passed', true, 'test_count', numel(names), 'tests', tests, 'metrics', metrics);
    fprintf('PASS: Phase 4 configuration and fixed maps, %d test groups.\n', numel(names));
end

function testDefaults()
    model = alev4.createStructuredNoise([2 3]);
    assert(isequal(model, alev4.createStructuredNoise([2 3], struct())));
    assert(isequal(model, alev4.createStructuredNoise([2 3], model)));
    assert(strcmp(model.schema_version, '1.0') && model.enabled && model.dark_shot_noise);
    assert(model.prnu == 1 && model.dark_current_e_per_s == 0);
    assert(model.reference_temperature_K == 293.15);
    assert(strcmp(model.realization_id, 'ASSUMED-P4-DEFAULT'));
    paths = {'shared', 'single', 'high_gain', 'low_gain'};
    neutral = struct('fixed_offset_e', 0, 'row_noise_e', 0, ...
        'column_noise_e', 0, 'frame_noise_e', 0);
    empty_paths = struct();
    for k = 1:numel(paths)
        assert(isequal(model.(paths{k}), neutral));
        empty_paths.(paths{k}) = struct();
    end
    assert(isequal(model, alev4.createStructuredNoise([2 3], empty_paths)));
    overrides = struct('prnu', [0 .5 1; 1.25 1.5 2], ...
        'shared', struct('fixed_offset_e', -3), ...
        'high_gain', struct('row_noise_e', 2), ...
        'parameter_sources', {{'ASSUMED-CUSTOM-PRNU'; 'ASSUMED-CUSTOM-OFFSET'}});
    copy = overrides;
    partial = alev4.createStructuredNoise([2 3], overrides);
    assert(isequal(overrides, copy), 'Constructor changed caller overrides.');
    assert(isequal(partial.prnu, overrides.prnu), 'PRNU was normalized or replaced.');
    assert(partial.shared.fixed_offset_e == -3 && partial.shared.row_noise_e == 0);
    assert(partial.high_gain.row_noise_e == 2 && partial.high_gain.column_noise_e == 0);
    assert(isequal(partial.single, neutral) && isequal(partial.low_gain, neutral));
    assert(isequal(partial.parameter_sources, ...
        {'ASSUMED-CUSTOM-PRNU', 'ASSUMED-CUSTOM-OFFSET'}));
    assert(isequal(partial, alev4.createStructuredNoise([2 3], partial)));
end

function testStructure()
    expectError(@() alev4.createStructuredNoise(), 'ALEV4:StructuredNoiseArguments');
    expectError(@() alev4.createStructuredNoise([2 3], struct(), 1), ...
        {'ALEV4:StructuredNoiseArguments', 'Octave:invalid-fun-call', 'MATLAB:TooManyInputs', 'MATLAB:maxrhs'});
    malformed = {[], 1, true, 'model', {struct()}, struct([]), repmat(struct(), 1, 2)};
    paths = {'shared', 'single', 'high_gain', 'low_gain'};
    for k = 1:numel(malformed)
        expectError(@() alev4.createStructuredNoise([2 3], malformed{k}), ...
            'ALEV4:InvalidStructuredNoise');
        for p = 1:numel(paths)
            override = struct(); override.(paths{p}) = malformed{k};
            expectError(@() alev4.createStructuredNoise([2 3], override), ...
                'ALEV4:InvalidStructuredNoise');
        end
    end
    for bad = {1, '2.0', '1.0 ', '', ['1'; '.'; '0']}
        expectError(@() alev4.createStructuredNoise([2 3], ...
            struct('schema_version', bad{1})), 'ALEV4:InvalidStructuredNoise');
    end
    for name = {'seed', 'prnu_rms', 'temperature_K', 'map_generator', 'unknown'}
        override = struct(); override.(name{1}) = 1;
        expectError(@() alev4.createStructuredNoise([2 3], override), ...
            'ALEV4:UnknownStructuredNoiseField');
    end
    for p = 1:numel(paths)
        override = struct(); override.(paths{p}) = struct('read_noise_e', 1);
        expectError(@() alev4.createStructuredNoise([2 3], override), ...
            'ALEV4:UnknownStructuredNoiseField');
    end
    for field = {'enabled', 'dark_shot_noise'}
        for value = {0, 1, 'true', [], [true false], struct(), NaN}
            override = struct(); override.(field{1}) = value{1};
            expectError(@() alev4.createStructuredNoise([2 3], override), ...
                'ALEV4:InvalidStructuredNoise');
        end
    end
    expectError(@() alev4.createStructuredNoise([2 3], ...
        struct('enabled', false, 'prnu', -1)), 'ALEV4:InvalidStructuredNoise');
end

function testGrid()
    invalid = {[], 2, [1 2 3], [0 3], [-1 3], [1.5 3], ...
        [NaN 3], [Inf 3], [2+1i 3], [true true], '23', {2, 3}, ...
        [1e8+1 1], [10001 10000], reshape(1:4, 2, 2)};
    for k = 1:numel(invalid)
        expectError(@() alev4.createStructuredNoise(invalid{k}), ...
            'ALEV4:InvalidStructuredNoise');
    end
    boundary = alev4.createStructuredNoise([1 1e8]);
    assert(isequal(boundary.full_grid_size, [1 1e8]) && isscalar(boundary.prnu));
    column_grid = alev4.createStructuredNoise([3; 2]);
    assert(isequal(column_grid.full_grid_size, [3 2]));
    for enabled = [true false]
        model = alev4.createStructuredNoise([2 3], struct('enabled', enabled));
        expectError(@() alev4.createStructuredNoise([3 2], model), ...
            'ALEV4:StructuredNoiseGridMismatch');
        geometry = alev4.createSensorGeometry(struct('full_grid_size', [4 5], ...
            'active_roi', [2 2 2 3]));
        expectError(@() alev4.structuredNoiseMaps(model, geometry), ...
            'ALEV4:StructuredNoiseGridMismatch');
    end
    geometry = alev4.createSensorGeometry(struct('full_grid_size', [2 3]));
    model = alev4.createStructuredNoise([2 3]);
    expectError(@() alev4.structuredNoiseMaps(model), 'ALEV4:StructuredNoiseArguments');
    expectError(@() alev4.structuredNoiseMaps(model, geometry, 1), ...
        {'ALEV4:StructuredNoiseArguments', 'Octave:invalid-fun-call', 'MATLAB:TooManyInputs', 'MATLAB:maxrhs'});
    bad = geometry; bad.active_roi = [2 2 2 3];
    expectError(@() alev4.structuredNoiseMaps(model, bad), 'ALEV4:InvalidGeometry');
    bad = model; bad.full_grid_size = [2 NaN];
    expectError(@() alev4.structuredNoiseMaps(bad, geometry), 'ALEV4:InvalidStructuredNoise');
    for dims = {[1 1], [1 5], [5 1]}
        g = alev4.createSensorGeometry(struct('full_grid_size', dims{1}));
        m = alev4.createStructuredNoise(dims{1}, struct('prnu', 2));
        maps = alev4.structuredNoiseMaps(m, g);
        assert(isequal(maps.prnu, 2*ones(dims{1})));
    end
end

function testMaps()
    dims = [2 3];
    invalid = {[], zeros(3, 2), ones(1, 3), ones(2, 1), ones(2, 3, 2), ...
        NaN, Inf, -Inf, 1+1i, true, '1', {1}, struct(), ...
        [1 2 3; 4 NaN 6], [1 2 3; 4 Inf 6]};
    maps = {'prnu', 'dark_current_e_per_s'};
    paths = {'shared', 'single', 'high_gain', 'low_gain'};
    for k = 1:numel(invalid)
        for j = 1:numel(maps)
            override = struct(); override.(maps{j}) = invalid{k};
            expectError(@() alev4.createStructuredNoise(dims, override), ...
                'ALEV4:InvalidStructuredNoise');
        end
        for p = 1:numel(paths)
            component = struct(); component.fixed_offset_e = invalid{k};
            override = struct(); override.(paths{p}) = component;
            expectError(@() alev4.createStructuredNoise(dims, override), ...
                'ALEV4:InvalidStructuredNoise');
        end
    end
    for j = 1:numel(maps)
        for value = {-1, int8(-1), [0 1 2; 3 -eps 5]}
            override = struct(); override.(maps{j}) = value{1};
            expectError(@() alev4.createStructuredNoise(dims, override), ...
                'ALEV4:InvalidStructuredNoise');
        end
    end
    values = [-4 -.5 0; .25 3 12];
    override = struct('prnu', 0, 'dark_current_e_per_s', 0);
    for p = 1:numel(paths), override.(paths{p}) = struct('fixed_offset_e', values); end
    model = alev4.createStructuredNoise(dims, override);
    for p = 1:numel(paths), assert(isequal(model.(paths{p}).fixed_offset_e, values)); end
    assert(model.prnu == 0 && model.dark_current_e_per_s == 0);
    uniform = alev4.createStructuredNoise(dims, struct('prnu', 2.5, 'dark_current_e_per_s', 4));
    assert(uniform.prnu == 2.5 && uniform.dark_current_e_per_s == 4);
end

function testRmsAndTemperature()
    bad = {-1, [], [1 2], Inf, NaN, 1i, true, '2', {2}, struct()};
    for path = {'shared', 'single', 'high_gain', 'low_gain'}
        for field = {'row_noise_e', 'column_noise_e', 'frame_noise_e'}
            for k = 1:numel(bad)
                component = struct(); component.(field{1}) = bad{k};
                override = struct(); override.(path{1}) = component;
                expectError(@() alev4.createStructuredNoise([2 3], override), ...
                    'ALEV4:InvalidStructuredNoise');
            end
        end
    end
    bad_temperature = [bad {0}];
    for k = 1:numel(bad_temperature)
        override = struct(); override.reference_temperature_K = bad_temperature{k};
        expectError(@() alev4.createStructuredNoise([2 3], override), 'ALEV4:InvalidStructuredNoise');
    end
    zero = alev4.createStructuredNoise([2 3], ...
        struct('shared', struct('row_noise_e', 0, 'column_noise_e', 0, 'frame_noise_e', 0)));
    assert(zero.shared.row_noise_e == 0 && zero.shared.column_noise_e == 0 && ...
        zero.shared.frame_noise_e == 0);
end

function testIdentifiers()
    invalid = {'', 'has space', 'line/part', '.leading', '-leading', ...
        ['x' char(10)], ['x' char(0) 'y'], ['x' char(233)], ...
        ['a'; 'b'], ['ab'; 'cd'], repmat('a', 1, 129), 7, true, { 'nested' }};
    for k = 1:numel(invalid)
        override = struct(); override.realization_id = invalid{k};
        expectError(@() alev4.createStructuredNoise([2 3], override), 'ALEV4:InvalidStructuredNoise');
        override = struct(); override.parameter_sources = {invalid{k}};
        expectError(@() alev4.createStructuredNoise([2 3], override), ...
            'ALEV4:InvalidStructuredNoise');
    end
    invalid_sources = {{}, 'ASSUMED-ID', 1, {{'nested'}}, ...
        {'same', 'same'}, {'a', 'b'; 'c', 'd'}, repmat({'x'}, 1, 33)};
    for k = 1:numel(invalid_sources)
        override = struct(); override.parameter_sources = invalid_sources{k};
        expectError(@() alev4.createStructuredNoise([2 3], override), ...
            'ALEV4:InvalidStructuredNoise');
    end
    max_id = ['A' repmat('z', 1, 127)];
    sources = cell(32, 1);
    for k = 1:32, sources{k} = sprintf('SOURCE-%02d', k); end
    model = alev4.createStructuredNoise([2 3], ...
        struct('realization_id', max_id, 'parameter_sources', {sources}));
    assert(strcmp(model.realization_id, max_id));
    assert(isequal(size(model.parameter_sources), [1 32]));
    assert(isequal(model.parameter_sources, sources.'));
end

function classes = testRepresentations()
    classes = {'double', 'single', 'uint8', 'uint16', 'uint32', 'uint64', ...
        'int8', 'int16', 'int32', 'int64'};
    for k = 1:numel(classes)
        numeric = cast([0 1 2; 3 4 5], classes{k});
        override = struct('prnu', numeric, 'dark_current_e_per_s', numeric, ...
            'reference_temperature_K', cast(300, classes{k}));
        % The 8-bit class cannot represent 300; its converted value remains
        % valid and must be preserved, rather than compared with 300.
        paths = {'shared', 'single', 'high_gain', 'low_gain'};
        for p = 1:numel(paths)
            override.(paths{p}) = struct('fixed_offset_e', numeric, ...
                'row_noise_e', cast(1, classes{k}), ...
                'column_noise_e', cast(2, classes{k}), ...
                'frame_noise_e', cast(3, classes{k}));
        end
        copy = override;
        model = alev4.createStructuredNoise(cast([2; 3], classes{k}), override);
        assert(isequal(override, copy));
        assertDenseDouble(model.full_grid_size, [2 3]);
        assertDenseDouble(model.prnu, double(numeric));
        assertDenseDouble(model.dark_current_e_per_s, double(numeric));
        assertDenseDouble(model.reference_temperature_K, double(copy.reference_temperature_K));
        for p = 1:numel(paths)
            assertDenseDouble(model.(paths{p}).fixed_offset_e, double(numeric));
            assertDenseDouble(model.(paths{p}).row_noise_e, 1);
            assertDenseDouble(model.(paths{p}).column_noise_e, 2);
            assertDenseDouble(model.(paths{p}).frame_noise_e, 3);
        end
    end
    values = [0 .5 1; 1.25 1.5 2];
    override = struct('prnu', sparse(values), ...
        'dark_current_e_per_s', sparse(values*2), ...
        'enabled', logical(sparse(1)), 'dark_shot_noise', logical(sparse(0)), ...
        'single', struct('fixed_offset_e', sparse(-values), 'row_noise_e', sparse(2)));
    model = alev4.createStructuredNoise(sparse([2; 3]), override);
    assertDenseDouble(model.prnu, values);
    assertDenseDouble(model.dark_current_e_per_s, values*2);
    assertDenseDouble(model.single.fixed_offset_e, -values);
    assertDenseDouble(model.single.row_noise_e, 2);
    assert(islogical(model.enabled) && ~issparse(model.enabled) && model.enabled);
    assert(islogical(model.dark_shot_noise) && ~issparse(model.dark_shot_noise) && ~model.dark_shot_noise);
    geometry = alev4.createSensorGeometry(struct('full_grid_size', [2 3]));
    active = alev4.structuredNoiseMaps(model, geometry);
    assertDenseDouble(active.prnu, values);
    assertDenseDouble(active.single.fixed_offset_e, -values);
    assertDenseDouble(active.shared.fixed_offset_e, zeros(2, 3));
end

function count = testCropIdentity()
    dims = [5 7];
    marker = zeros(dims);
    for row = 1:5
        for column = 1:7, marker(row, column) = 100*row + column; end
    end
    override = struct('prnu', marker/8, 'dark_current_e_per_s', marker/4);
    paths = {'shared', 'single', 'high_gain', 'low_gain'};
    for p = 1:4
        override.(paths{p}) = struct('fixed_offset_e', (-1)^p*(marker+p)/16, ...
            'row_noise_e', p, 'column_noise_e', p+1, 'frame_noise_e', p+2);
    end
    model = alev4.createStructuredNoise(dims, override);
    patterns = {'RGGB', 'BGGR', 'GRBG', 'GBRG'};
    expected_patterns = {'RGGB','GRBG','GBRG','BGGR'; ...
        'BGGR','GBRG','GRBG','RGGB'; 'GRBG','RGGB','BGGR','GBRG'; ...
        'GBRG','BGGR','RGGB','GRBG'};
    count = 0;
    for pattern = 1:4
        geometry = alev4.createSensorGeometry(struct('full_grid_size', dims, ...
            'full_grid_cfa_pattern', patterns{pattern}));
        full_maps = alev4.structuredNoiseMaps(model, geometry);
        assert(isequal(full_maps.prnu, override.prnu));
        for row = 1:2
            for column = 1:2
                crop_geometry = geometry;
                crop_geometry.active_roi = [row column 3 4];
                crop_copy = crop_geometry;
                crop = alev4.structuredNoiseMaps(model, crop_geometry);
                rr = row:row+2; cc = column:column+3;
                assert(isequal(crop.prnu, override.prnu(rr, cc)));
                assert(isequal(crop.dark_current_e_per_s, override.dark_current_e_per_s(rr, cc)));
                for p = 1:4
                    reference = override.(paths{p});
                    reference.fixed_offset_e = reference.fixed_offset_e(rr, cc);
                    assert(isequal(crop.(paths{p}), reference));
                end
                bound = alev4.bindSensorGeometry(alev4.createBaselineSensor(), crop_geometry, 'derive');
                assert(strcmp(bound.cfa_pattern, expected_patterns{pattern, (row-1)*2+column}));
                assert(isequal(crop_geometry, crop_copy));
                count = count+1;
            end
        end
    end
    last = alev4.createSensorGeometry(struct('full_grid_size', dims, 'active_roi', [5 7 1 1]));
    last_maps = alev4.structuredNoiseMaps(model, last);
    assert(last_maps.prnu == 507/8 && last_maps.dark_current_e_per_s == 507/4);
    scalar = alev4.createStructuredNoise(dims, struct('prnu', 2, ...
        'dark_current_e_per_s', 3, 'shared', struct('fixed_offset_e', -4)));
    for row = 1:2
        for column = 1:2
            geometry = alev4.createSensorGeometry(struct('full_grid_size', dims, ...
                'active_roi', [row column 3 4]));
            maps = alev4.structuredNoiseMaps(scalar, geometry);
            assert(isequal(maps.prnu, 2*ones(3,4)) && ...
                isequal(maps.dark_current_e_per_s, 3*ones(3,4)) && ...
                isequal(maps.shared.fixed_offset_e, -4*ones(3,4)));
        end
    end
end

function testIsolation()
    rng(47001, 'twister'); before = rng;
    override = struct('prnu', single([0 .5 1; 1.25 1.5 2]), ...
        'shared', struct('fixed_offset_e', sparse([-2 0 1; 3 4 -5])));
    original = override;
    model = alev4.createStructuredNoise([2 3], override);
    assert(isequal(before, rng()) && isequal(override, original));
    geometry = alev4.createSensorGeometry(struct('full_grid_size', [2 3], ...
        'active_roi', [2 2 1 2]));
    model_copy = model; geometry_copy = geometry;
    first = alev4.structuredNoiseMaps(model, geometry);
    rng(47002, 'twister'); other_before = rng;
    second = alev4.structuredNoiseMaps(model, geometry);
    assert(isequal(first, second), 'Fixed-map realization depends on caller RNG.');
    assert(isequal(other_before, rng()) && isequal(model, model_copy) && ...
        isequal(geometry, geometry_copy));
    renamed = model; renamed.realization_id = 'ANOTHER-LABEL-SAME-MAPS';
    assert(isequal(first, alev4.structuredNoiseMaps(renamed, geometry)), ...
        'Realization labels must not generate or perturb fixed maps.');
    bad = model; bad.prnu(1, 1) = NaN; bad_copy = bad;
    expectError(@() alev4.structuredNoiseMaps(bad, geometry), 'ALEV4:InvalidStructuredNoise');
    assert(isequaln(bad, bad_copy) && isequal(geometry, geometry_copy));
    assert(isequal(other_before, rng()));
end

function assertDenseDouble(actual, expected)
    assert(isa(actual, 'double') && ~issparse(actual) && isequal(actual, expected));
end

function expectError(callback, identifier)
    before = rng;
    caught = false;
    try
        callback();
    catch err
        caught = true;
        if iscell(identifier), expected = identifier; else, expected = {identifier}; end
        assert(any(strcmp(err.identifier, expected)), ...
            ['Expected ' strjoin(expected, ' or ') ', received ' err.identifier ': ' err.message]);
    end
    assert(caught, 'Expected malformed configuration to reject.');
    assert(isequal(before, rng()), 'Rejected configuration changed caller RNG.');
end
