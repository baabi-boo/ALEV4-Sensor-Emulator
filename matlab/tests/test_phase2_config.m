function report = test_phase2_config()
%TEST_PHASE2_CONFIG Validate configuration and observed-RAW input boundaries.
%   These checks exercise the public contracts without using simulation
%   truth or duplicating the analytical transfer-function tests.
    caller_rng = rng;
    guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    names = {'partial_overrides_canonicalization_and_revalidation', ...
        'schema_unknown_fields_and_scalar_structs', ...
        'misplaced_shared_electronics_reject', ...
        'path_scalar_and_adc_ranges', ...
        'gain_headroom_and_strict_merge_boundaries', ...
        'malformed_observed_raw_reject', ...
        'numeric_representation_and_rng_isolation'};
    testDefaults();
    testStructure();
    testSharedElectronics();
    testPathRanges();
    testHeadroomAndMerge();
    testInvalidRaw();
    testRepresentationAndRng();
    tests = repmat(struct('name', '', 'status', 'passed', 'passed', true), ...
        1, numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    report = struct('suite', 'phase2_config', 'status', 'passed', ...
        'passed', true, 'test_count', numel(names), 'tests', tests);
    fprintf('PASS: Phase 2 configuration and RAW boundaries, %d test groups.\n', numel(names));
end

function testDefaults()
    defaults = alev4.createDualGainSensor();
    assert(isequal(defaults, alev4.createDualGainSensor(struct())));
    assert(isequal(defaults, alev4.createDualGainSensor(defaults)));
    overrides = struct('sensor', struct('image_size', uint16([2 3]), ...
        'cfa_pattern', 'bggr'), 'high_gain', struct('read_noise_e', int16(2)), ...
        'merge', struct('start_e', single(500)));
    original = overrides;
    cfg = alev4.createDualGainSensor(overrides);
    assert(isequal(overrides, original), 'Constructor mutated its caller configuration.');
    assert(isequal(cfg.sensor.image_size, [2 3]) && strcmp(cfg.sensor.cfa_pattern, 'BGGR'));
    assert(cfg.high_gain.read_noise_e == 2 && cfg.high_gain.gain_dn_per_e == 4);
    assert(cfg.merge.start_e == 500 && cfg.merge.end_e == 900);
    assert(isequal(cfg.low_gain, defaults.low_gain));
    assert(isequal(cfg, alev4.createDualGainSensor(cfg)));
    empty_nested = struct('sensor', struct(), 'high_gain', struct(), ...
        'low_gain', struct(), 'merge', struct());
    assert(isequal(defaults, alev4.createDualGainSensor(empty_nested)));
end

function testStructure()
    bad_structs = {[], 7, true, 'invalid', {struct()}, struct([]), repmat(struct(), 1, 2)};
    for k = 1:numel(bad_structs)
        expectError(@() alev4.createDualGainSensor(bad_structs{k}), 'ALEV4:InvalidDualGainConfig');
        for label = {'high_gain', 'low_gain', 'merge'}
            value = struct(); value.(label{1}) = bad_structs{k};
            expectError(@() alev4.createDualGainSensor(value), 'ALEV4:InvalidDualGainConfig');
        end
    end
    for version = {2, '1.0', '2.0 ', ['2'; '.'; '0'], ''}
        expectError(@() alev4.createDualGainSensor(struct('schema_version', version{1})), ...
            'ALEV4:InvalidDualGainConfig');
    end
    expectError(@() alev4.createDualGainSensor(struct('high', struct())), 'ALEV4:UnknownDualGainField');
    for label = {'high_gain', 'low_gain', 'merge'}
        value = struct(); value.(label{1}) = struct('misspelled_parameter', 1);
        expectError(@() alev4.createDualGainSensor(value), 'ALEV4:UnknownDualGainField');
    end
    expectError(@() alev4.createDualGainSensor(struct('sensor', struct('gain', 1))), ...
        'ALEV4:UnknownSensorField');
    expectError(@() alev4.createDualGainSensor(struct('sensor', struct([]))), ...
        'ALEV4:InvalidSensorConfig');
    expectError(@() alev4.createDualGainSensor(struct('high_gain', struct('full_well_e', 10))), ...
        'ALEV4:UnknownDualGainField');
end

function testSharedElectronics()
    names = {'read_noise_e', 'gain_dn_per_e', 'black_level_dn', 'adc_bits'};
    values = {0, 0.25, 63, 12};
    for k = 1:numel(names)
        shared = struct(); shared.(names{k}) = values{k};
        expectError(@() alev4.createDualGainSensor(struct('sensor', shared)), ...
            'ALEV4:AmbiguousSharedReadout');
    end
    shared = struct('read_noise_e', uint8(3), 'gain_dn_per_e', single(0.5), ...
        'black_level_dn', sparse(64), 'adc_bits', uint8(16));
    cfg = alev4.createDualGainSensor(struct('sensor', shared));
    baseline = alev4.createBaselineSensor();
    assert(isequal(cfg.sensor, baseline), 'Equivalent canonical electronics must normalize.');
end

function testPathRanges()
    scalar_bad = {NaN, Inf, -Inf, 1i, [], [1 2], true, '1', {1}};
    fields = {'gain_dn_per_e', 'read_noise_e', 'black_level_dn', 'adc_bits'};
    for label = {'high_gain', 'low_gain'}
        for k = 1:numel(fields)
            for j = 1:numel(scalar_bad)
                path = struct(); path.(fields{k}) = scalar_bad{j};
                value = struct(); value.(label{1}) = path;
                expectError(@() alev4.createDualGainSensor(value), 'ALEV4:InvalidDualGainConfig');
            end
        end
        invalid = {'gain_dn_per_e', 0; 'gain_dn_per_e', -1; ...
            'read_noise_e', -eps; 'black_level_dn', -eps; ...
            'black_level_dn', 4096; 'adc_bits', 0; 'adc_bits', 1; ...
            'adc_bits', 17; 'adc_bits', 12.5};
        for k = 1:size(invalid, 1)
            path = struct(); path.(invalid{k, 1}) = invalid{k, 2};
            value = struct(); value.(label{1}) = path;
            expectError(@() alev4.createDualGainSensor(value), 'ALEV4:InvalidDualGainConfig');
        end
    end
    cfg = alev4.createDualGainSensor(struct('high_gain', ...
        struct('read_noise_e', 0, 'black_level_dn', 0), 'low_gain', ...
        struct('read_noise_e', 0, 'black_level_dn', 0, 'adc_bits', 16)));
    assert(cfg.high_gain.read_noise_e == 0 && cfg.high_gain.black_level_dn == 0);
    assert(cfg.low_gain.adc_bits == 16, 'The supported 16-bit endpoint rejected.');
    % A one-bit low ADC may have ample nominal headroom but no code that
    % the conservative rail-based merger can use.
    expectError(@() alev4.createDualGainSensor(struct('low_gain', ...
        struct('adc_bits', 1, 'black_level_dn', 0, 'gain_dn_per_e', 0.0001))), ...
        'ALEV4:InvalidDualGainConfig');
    two_bit = alev4.createDualGainSensor(struct('high_gain', ...
        struct('adc_bits', 2, 'black_level_dn', 0, 'gain_dn_per_e', 0.002), ...
        'low_gain', struct('adc_bits', 2, 'black_level_dn', 0, 'gain_dn_per_e', 0.001), ...
        'merge', struct('start_e', 100, 'end_e', 700)));
    assert(two_bit.high_gain.adc_bits == 2 && two_bit.low_gain.adc_bits == 2, ...
        'The supported two-bit endpoint rejected despite valid quantization headroom.');
end

function testHeadroomAndMerge()
    expectError(@() alev4.createDualGainSensor(struct('high_gain', ...
        struct('gain_dn_per_e', 0.1))), 'ALEV4:InvalidDualGainConfig');
    expectError(@() alev4.createDualGainSensor(struct('low_gain', ...
        struct('gain_dn_per_e', 5))), 'ALEV4:InvalidDualGainConfig');
    % Lower gain alone is insufficient when a smaller ADC has less range.
    expectError(@() alev4.createDualGainSensor(struct('low_gain', ...
        struct('adc_bits', 5, 'black_level_dn', 0))), 'ALEV4:InvalidDualGainConfig');
    expectError(@() alev4.createDualGainSensor(struct('low_gain', ...
        struct('gain_dn_per_e', realmin))), 'ALEV4:InvalidDualGainConfig');
    expectError(@() alev4.createDualGainSensor(struct('high_gain', ...
        struct('black_level_dn', 4095))), 'ALEV4:InvalidDualGainConfig');
    for merge = {struct('start_e', -eps), struct('start_e', 900), ...
            struct('start_e', 901), struct('end_e', 600), ...
            struct('end_e', 0), struct('end_e', Inf), ...
            struct('start_e', NaN), struct('end_e', [800 900]), ...
            struct('start_e', true)}
        expectError(@() alev4.createDualGainSensor(struct('merge', merge{1})), ...
            'ALEV4:InvalidDualGainConfig');
    end
    ceiling = (4095 - 1 - 64) / 4;
    expectError(@() alev4.createDualGainSensor(struct('merge', struct('end_e', ceiling))), ...
        'ALEV4:InvalidDualGainConfig');
    expectError(@() alev4.createDualGainSensor(struct('merge', ...
        struct('end_e', ceiling - eps(ceiling)))), 'ALEV4:InvalidDualGainConfig');
    % The low observation can lag by five electrons with default gain 0.1.
    % The first high rail occurs at 1007.625 e, so a transition ending at
    % 1002.625 e needs the explicit floating-point safety margin as well.
    safe_ceiling = 1002.625;
    expectError(@() alev4.createDualGainSensor(struct('merge', ...
        struct('end_e', safe_ceiling))), 'ALEV4:InvalidDualGainConfig');
    expectError(@() alev4.createDualGainSensor(struct('merge', ...
        struct('end_e', safe_ceiling - 4*eps(safe_ceiling)))), 'ALEV4:InvalidDualGainConfig');
    accepted = alev4.createDualGainSensor(struct('merge', ...
        struct('end_e', safe_ceiling - 8*eps(safe_ceiling))));
    assert(accepted.merge.end_e < safe_ceiling);
    % Fractional low black offsets expose a real descending merge at the
    % high rail unless the observed-channel quantization margin is enforced.
    expectError(@() alev4.createDualGainSensor(struct('low_gain', ...
        struct('black_level_dn', 64.6), 'merge', ...
        struct('start_e', 1000, 'end_e', 1007))), 'ALEV4:InvalidDualGainConfig');
    expectError(@() alev4.createDualGainSensor(struct('sensor', struct('full_well_e', 900))), ...
        'ALEV4:InvalidDualGainConfig');
    accepted = alev4.createDualGainSensor(struct('sensor', struct('full_well_e', 900), ...
        'merge', struct('end_e', 900 - eps(900))));
    assert(accepted.merge.end_e < accepted.sensor.full_well_e);
    accepted = alev4.createDualGainSensor(struct('merge', struct('start_e', 0, 'end_e', realmin)));
    assert(accepted.merge.start_e == 0 && accepted.merge.end_e > 0);
end

function testInvalidRaw()
    cfg = alev4.createDualGainSensor(struct('sensor', struct('image_size', [2 3])));
    good = ones(2, 3) * 64;
    invalid = {[], zeros(3, 2), zeros(1, 6), zeros(2, 3, 2), ...
        NaN(2, 3), Inf(2, 3), -ones(2, 3), 4096 * ones(2, 3), ...
        0.5 * ones(2, 3), 1i * ones(2, 3), false(2, 3), 'abcdef', {good}};
    for k = 1:numel(invalid)
        expectError(@() alev4.mergeDualGain(invalid{k}, good, cfg), 'ALEV4:InvalidDualGainRaw');
        expectError(@() alev4.mergeDualGain(good, invalid{k}, cfg), 'ALEV4:InvalidDualGainRaw');
    end
    expectError(@() alev4.mergeDualGain(good, good), 'ALEV4:DualGainMergeArguments');
end

function testRepresentationAndRng()
    cfg = alev4.createDualGainSensor(struct('sensor', struct('image_size', [2 3]), ...
        'high_gain', struct('gain_dn_per_e', single(4), 'read_noise_e', sparse(1), ...
            'black_level_dn', uint16(64), 'adc_bits', uint8(12)), ...
        'low_gain', struct('gain_dn_per_e', single(0.125)), ...
        'merge', struct('start_e', single(600), 'end_e', uint16(900))));
    for label = {'high_gain', 'low_gain', 'merge'}
        values = struct2cell(cfg.(label{1}));
        for k = 1:numel(values)
            assert(isa(values{k}, 'double') && ~issparse(values{k}));
        end
    end
    high = [0 1 63; 64 100 4095];
    low = [64 64 64; 64 100 4095];
    rng(6813, 'twister'); before = rng;
    reference = alev4.mergeDualGain(high, low, cfg);
    assert(isequal(reference, alev4.mergeDualGain(single(high), uint16(low), cfg)));
    sparse_result = alev4.mergeDualGain(sparse(high), sparse(low), cfg);
    assert(isequal(reference, sparse_result));
    assert(isa(sparse_result.electrons, 'double') && ~issparse(sparse_result.electrons));
    assert(isa(sparse_result.weight_high, 'double') && ~issparse(sparse_result.weight_high));
    assert(islogical(sparse_result.valid) && ~issparse(sparse_result.valid));
    expectError(@() alev4.mergeDualGain(high + 0.5, low, cfg), 'ALEV4:InvalidDualGainRaw');
    expectError(@() alev4.createDualGainSensor(struct('merge', struct('end_e', 0))), ...
        'ALEV4:InvalidDualGainConfig');
    assert(isequal(before, rng()), 'Configuration or RAW-only merge changed caller RNG state.');
end

function expectError(callback, identifier)
    caught = false;
    try
        callback();
    catch err
        caught = true;
        assert(strcmp(err.identifier, identifier), ...
            ['Expected ' identifier ', received ' err.identifier]);
    end
    assert(caught, ['Expected rejection: ' identifier]);
end
