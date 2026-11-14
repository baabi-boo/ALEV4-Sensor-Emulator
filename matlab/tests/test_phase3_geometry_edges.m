function report = test_phase3_geometry_edges()
%TEST_PHASE3_GEOMETRY_EDGES Adversarial geometry and binding contracts.
%   Limit-sized grids are descriptors only; every allocated active grid is
%   small. These checks do not imply practical full-frame throughput.
    caller_rng = rng;
    guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    names = {'numeric_representations_are_canonical', ...
        'bounded_descriptors_without_large_allocation', ...
        'malformed_geometry_and_numeric_range_reject', ...
        'source_identifiers_are_unambiguous', ...
        'geometry_binding_preserves_nonspatial_settings', ...
        'each_single_and_dual_binding_conflict_rejects', ...
        'complete_readout_and_explicit_binding_mode_required', ...
        'large_binding_descriptors_preserve_parity_and_strict_readouts', ...
        'spatial_output_limit_precedes_optics_for_validated_bands', ...
        'success_and_failure_consume_no_randomness'};
    testCanonicalRepresentations();
    testBoundedDescriptors();
    testMalformedGeometry();
    testSourceIdentifiers();
    testPreservedReadout();
    testBindingConflicts();
    testExplicitCompleteBinding();
    testLargeBindingDescriptors();
    testSpatialOutputLimit();
    testNoRandomness();
    tests = repmat(struct('name','','status','passed','passed',true),1,numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    report = struct('suite','phase3_geometry_edges','status','passed', ...
        'passed',true,'test_count',numel(names),'tests',tests);
    fprintf('PASS: Phase 3 geometry edge cases, %d test groups.\n',numel(names));
end

function testCanonicalRepresentations()
    options = struct('full_grid_size',[7 9], 'active_roi',[2 3 4 5], ...
        'pixel_pitch_m',2, 'origin_xy_m',[-4 6], ...
        'full_grid_cfa_pattern','gbrg', 'parameter_sources',{{'TEST-GEOMETRY';'TEST-CFA'}});
    expected = alev4.createSensorGeometry(options);
    sparse_options = options;
    numeric_fields = {'full_grid_size','active_roi','pixel_pitch_m','origin_xy_m'};
    for k = 1:numel(numeric_fields)
        field = numeric_fields{k};
        sparse_options.(field) = sparse(options.(field).');
    end
    actual = alev4.createSensorGeometry(sparse_options);
    assert(isequal(actual,expected));
    for k = 1:numel(numeric_fields)
        field = numeric_fields{k};
        assert(isa(actual.(field),'double') && ~issparse(actual.(field)));
        assert(isrow(actual.(field)));
    end
    integer_options = options;
    integer_options.full_grid_size = uint32([7;9]);
    integer_options.active_roi = uint16([2;3;4;5]);
    integer_options.pixel_pitch_m = uint8(2);
    integer_options.origin_xy_m = int16([-4;6]);
    assert(isequal(alev4.createSensorGeometry(integer_options),expected));
    assert(strcmp(actual.full_grid_cfa_pattern,'GBRG'));
    assert(isequal(actual.parameter_sources,{'TEST-GEOMETRY','TEST-CFA'}));
    original = sparse_options;
    alev4.sensorGrid(sparse_options);
    assert(isequal(sparse_options,original), 'Geometry helpers mutated caller configuration.');
end

function testBoundedDescriptors()
    cases = {[1 1e8],[1e8 1],[10000 10000],[9999 10000]};
    for k = 1:numel(cases)
        dims = cases{k};
        g = alev4.createSensorGeometry(struct('full_grid_size',dims, ...
            'active_roi',[dims 1 1]));
        assert(isequal(g.full_grid_size,dims));
        small = alev4.sensorGrid(g);
        assert(isequal(small.image_size,[1 1]));
        assert(numel(small.x_edges_m)==2 && numel(small.y_edges_m)==2);
        endpoint = fliplr(dims)*6e-6;
        assert(isequal(small.active_bounds_xy_m(2,:),endpoint));
    end
    oversized = {[1 1e8+1],[1e8+1 1],[10000 10001],[1e8 2],[realmax 1]};
    for k = 1:numel(oversized)
        expectError(@() alev4.createSensorGeometry(struct('full_grid_size',oversized{k})), ...
            'ALEV4:InvalidGeometry');
    end
    % A changed grid size without an explicit ROI has a documented full ROI.
    g = alev4.createSensorGeometry(struct('full_grid_size',[1 7]));
    assert(isequal(g.active_roi,[1 1 1 7]));
    grid = alev4.sensorGrid(g);
    assert(isequal(grid.image_size,[1 7]));
end

function testMalformedGeometry()
    expectError(@() alev4.createSensorGeometry([]),'ALEV4:InvalidGeometry');
    expectError(@() alev4.createSensorGeometry({}),'ALEV4:InvalidGeometry');
    expectError(@() alev4.createSensorGeometry(repmat(struct(),1,2)),'ALEV4:InvalidGeometry');
    expectError(@() alev4.createSensorGeometry(struct('pixel_pich_m',6e-6)), ...
        'ALEV4:UnknownGeometryField');
    bad_versions = {'2.0',1,{'1.0'},char('1.0','1.0')};
    for k = 1:numel(bad_versions)
        expectOverride('schema_version',bad_versions{k},'ALEV4:InvalidGeometry');
    end
    bad_dims = {[],1,[2 3 4],[0 3],[-1 3],[2.5 3],[Inf 3],[NaN 3], ...
        [2+1i 3],true(1,2),reshape([2 3],1,1,2)};
    for k = 1:numel(bad_dims)
        expectOverride('full_grid_size',bad_dims{k},'ALEV4:InvalidGeometry');
    end
    bad_rois = {[],[1 1 2],[0 1 2 2],[1 -1 2 2],[1 1 0 2], ...
        [32 32 2 1],[33 1 1 1],[1 1 33 1],[1 1 2.5 2], ...
        [1 1 Inf 1],[1 1 NaN 1],[1 1 realmax 1],true(1,4)};
    for k = 1:numel(bad_rois)
        expectOverride('active_roi',bad_rois{k},'ALEV4:InvalidGeometry');
    end
    bad_pitches = {0,-1,Inf,NaN,realmin,realmax,1e155,[1 2],true,1+1i};
    for k = 1:numel(bad_pitches)
        expectOverride('pixel_pitch_m',bad_pitches{k},'ALEV4:InvalidGeometry');
    end
    bad_origins = {[],1,[1 2 3],[Inf 0],[0 NaN],[0 1i],true(1,2)};
    for k = 1:numel(bad_origins)
        expectOverride('origin_xy_m',bad_origins{k},'ALEV4:InvalidGeometry');
    end
    % Finite endpoints are insufficient if pitch is below their precision.
    expectOverride('origin_xy_m',[1e20 0],'ALEV4:GeometryNumericRange');
    expectOverride('origin_xy_m',[0 -1e20],'ALEV4:GeometryNumericRange');
    expectOverride('origin_xy_m',[realmax 0],'ALEV4:GeometryNumericRange');
    bad_cfa = {'RGBG','',1,{'RGGB'},char('RGGB','BGGR')};
    for k = 1:numel(bad_cfa)
        expectOverride('full_grid_cfa_pattern',bad_cfa{k},'ALEV4:InvalidGeometry');
    end
    % The preset must require a declared model CFA assumption and valid ROI.
    expectError(@() alev4.alexa35Geometry(),'ALEV4:AssumedCfaRequired');
    expectError(@() alev4.alexa35Geometry('RGGB',[3164 4608 2 1]), ...
        'ALEV4:InvalidGeometry');
end

function testSourceIdentifiers()
    malformed = {[],{},'SOURCE',42,{''},{42},{'HAS SPACE'}, ...
        {'/absolute'},{'../parent'},{'A','A'},repmat({'A'},2,2), ...
        {repmat('a',1,129)},{sprintf('SOURCE\n')},{sprintf('A\tB')}, ...
        {['A' char(0) 'B']},{char('AB','CD')}};
    for k = 1:numel(malformed)
        expectOverride('parameter_sources',malformed{k},'ALEV4:InvalidGeometry');
    end
    many = cell(1,33);
    for k=1:33, many{k}=sprintf('SOURCE-%d',k); end
    expectOverride('parameter_sources',many,'ALEV4:InvalidGeometry');
    valid = {'SOURCE-1','Source_2.v3','A'};
    g = alev4.createSensorGeometry(struct('parameter_sources',{valid}));
    assert(isequal(g.parameter_sources,valid));
end

function testPreservedReadout()
    geometry = fixtureGeometry();
    single = alev4.createBaselineSensor(struct('image_size',[7 9], ...
        'wavelength_nm',[500;600],'bin_width_nm',[10;20], ...
        'qe',[0.2 0.3 0.4;0.7 0.5 0.1], 'fill_factor',0.37, ...
        'full_well_e',24000,'read_noise_e',2.7,'gain_dn_per_e',0.7, ...
        'black_level_dn',70.5,'adc_bits',14,'shot_noise',false));
    original = single;
    bound = alev4.bindSensorGeometry(single,geometry,'derive');
    expected = single;
    expected.image_size = [3 5];
    expected.pixel_pitch_m = 2e-6;
    expected.cfa_pattern = 'BGGR';
    assert(isequal(bound,expected), 'Single derive changed a nonspatial setting.');
    assert(isequal(single,original));
    assert(isequal(alev4.bindSensorGeometry(bound,geometry,'validate'),bound));

    dual = alev4.createDualGainSensor(struct('sensor',struct('image_size',[7 9], ...
        'wavelength_nm',[500;600],'bin_width_nm',[10;20], ...
        'qe',[0.2 0.3 0.4;0.7 0.5 0.1], 'fill_factor',0.37, ...
        'full_well_e',24000,'shot_noise',false), ...
        'high_gain',struct('read_noise_e',1.7,'black_level_dn',70.5), ...
        'low_gain',struct('read_noise_e',7.1,'black_level_dn',62.5), ...
        'merge',struct('start_e',500,'end_e',850)));
    original_dual = dual;
    bound_dual = alev4.bindSensorGeometry(dual,geometry,'derive');
    expected_dual = dual;
    expected_dual.sensor.image_size = [3 5];
    expected_dual.sensor.pixel_pitch_m = 2e-6;
    expected_dual.sensor.cfa_pattern = 'BGGR';
    assert(isequal(bound_dual,expected_dual), 'Dual derive changed nonspatial settings.');
    assert(isequal(dual,original_dual));
    assert(isequal(alev4.bindSensorGeometry(bound_dual,geometry,'validate'),bound_dual));
end

function testBindingConflicts()
    geometry = fixtureGeometry();
    single = alev4.bindSensorGeometry(alev4.createBaselineSensor(),geometry,'derive');
    dual = alev4.bindSensorGeometry(alev4.createDualGainSensor(),geometry,'derive');
    fields = {'image_size','pixel_pitch_m','cfa_pattern'};
    values = {[3 4],4e-6,'RGGB'};
    for k = 1:numel(fields)
        incorrect_single = single;
        incorrect_single.(fields{k}) = values{k};
        expectError(@() alev4.bindSensorGeometry(incorrect_single,geometry,'validate'), ...
            'ALEV4:GeometryBindingConflict');
        incorrect_dual = dual;
        incorrect_dual.sensor.(fields{k}) = values{k};
        expectError(@() alev4.bindSensorGeometry(incorrect_dual,geometry,'validate'), ...
            'ALEV4:GeometryBindingConflict');
    end
end

function testExplicitCompleteBinding()
    geometry = alev4.createSensorGeometry();
    single = alev4.createBaselineSensor();
    dual = alev4.createDualGainSensor();
    bad_modes = {'','auto','DERIVE',[],false,{'derive'}};
    for k = 1:numel(bad_modes)
        expectError(@() alev4.bindSensorGeometry(single,geometry,bad_modes{k}), ...
            'ALEV4:InvalidGeometryBinding');
    end
    expectError(@() alev4.bindSensorGeometry(single,geometry),'ALEV4:InvalidGeometryBinding');
    bad_readouts = {[],{},struct(),struct('schema_version','3.0'), ...
        struct('schema_version',1),repmat(single,1,2)};
    for k = 1:numel(bad_readouts)
        expectError(@() alev4.bindSensorGeometry(bad_readouts{k},geometry,'derive'), ...
            'ALEV4:InvalidGeometryBinding');
    end
    % Binding a supposedly complete config must never manufacture omitted
    % physical/electronic settings through the constructors' override mode.
    partials = {struct('schema_version','1.0'),struct('schema_version','2.0'), ...
        rmfield(single,'qe'),rmfield(single,'fill_factor'),rmfield(dual,'merge')};
    partial_dual = dual;
    partial_dual.sensor = rmfield(partial_dual.sensor,'qe');
    partials{end+1} = partial_dual;
    partial_dual = dual;
    partial_dual.high_gain = rmfield(partial_dual.high_gain,'read_noise_e');
    partials{end+1} = partial_dual;
    for k = 1:numel(partials)
        expectError(@() alev4.bindSensorGeometry(partials{k},geometry,'derive'), ...
            'ALEV4:InvalidGeometryBinding');
        expectError(@() alev4.bindSensorGeometry(partials{k},geometry,'validate'), ...
            'ALEV4:InvalidGeometryBinding');
    end
end

function testLargeBindingDescriptors()
    % Bound axes remain modest even if coordinate allocation regresses.
    % The production binding itself must only manipulate descriptors.
    shapes = {[1 100000],[100000 1],[9999 9999]};
    patterns = {'RGGB','BGGR','GRBG','GBRG'};
    shifted = {'BGGR','RGGB','GBRG','GRBG'};
    single = alev4.createBaselineSensor();
    dual = alev4.createDualGainSensor();
    for s = 1:numel(shapes)
        for p = 1:numel(patterns)
            g = alev4.createSensorGeometry(struct('full_grid_size',shapes{s}+1, ...
                'active_roi',[2 2 shapes{s}],'full_grid_cfa_pattern',patterns{p}));
            expected = single;
            expected.image_size = shapes{s};
            expected.cfa_pattern = shifted{p};
            actual = alev4.bindSensorGeometry(single,g,'derive');
            assert(isequal(actual,expected));
            assert(isequal(alev4.bindSensorGeometry(actual,g,'validate'),expected));
            expected_dual = dual;
            expected_dual.sensor.image_size = shapes{s};
            expected_dual.sensor.cfa_pattern = shifted{p};
            actual_dual = alev4.bindSensorGeometry(dual,g,'derive');
            assert(isequal(actual_dual,expected_dual));
            assert(isequal(alev4.bindSensorGeometry(actual_dual,g,'validate'),expected_dual));
        end
        partial_dual = dual;
        partial_dual.low_gain = rmfield(partial_dual.low_gain,'read_noise_e');
        invalid_single = single;
        invalid_single.qe(1) = NaN;
        for mode = {'derive','validate'}
            expectError(@() alev4.bindSensorGeometry(rmfield(single,'qe'),g,mode{1}), ...
                'ALEV4:InvalidGeometryBinding');
            expectError(@() alev4.bindSensorGeometry(partial_dual,g,mode{1}), ...
                'ALEV4:InvalidGeometryBinding');
            expectError(@() alev4.bindSensorGeometry(invalid_single,g,mode{1}), ...
                'ALEV4:InvalidSensorConfig');
        end
        expectError(@() alev4.bindSensorGeometry(single,g,'validate'), ...
            'ALEV4:GeometryBindingConflict');
    end
end

function testSpatialOutputLimit()
    bands = 1001;
    single = alev4.createBaselineSensor(struct('wavelength_nm',(1:bands)', ...
        'bin_width_nm',ones(bands,1),'qe',ones(bands,3)/2));
    dual = alev4.createDualGainSensor(struct('sensor',single));
    input = ones(1,1,bands);
    before = rng;
    for dims = {[1 100000],[100000 1]}
        shape = dims{1};
        g = alev4.createSensorGeometry(struct('full_grid_size',shape,'pixel_pitch_m',1));
        grid = alev4.createSpatialGrid(struct('x_edges_m',[0 shape(2)], ...
            'y_edges_m',[0 shape(1)]));
        % This valid kernel cannot fit the one-cell input. An oversized
        % requested output must reject before PSF support is considered.
        psf = struct('kernel',[0.5 0.5],'origin_rc',[1 1], ...
            'spacing_yx_m',shape);
        for readout = {single,dual}
            for mode = {'derive','validate'}
                configuration = readout{1};
                if strcmp(mode{1},'validate')
                    configuration = alev4.bindSensorGeometry(configuration,g,'derive');
                end
                pre = struct('binding_mode',mode{1},'psf',psf);
                post = struct('binding_mode',mode{1},'input_stage','post_optics');
                expectError(@() alev4.simulateSpatialExposure(input,grid,g,configuration, ...
                    0.01,1,pre),'ALEV4:InvalidSpatialSampling');
                expectError(@() alev4.simulateSpatialExposure(input,grid,g,configuration, ...
                    0.01,1,post),'ALEV4:InvalidSpatialSampling');
            end
        end
        % Exactly 100 million samples remain admitted by the size check;
        % the deliberately insufficient PSF support prevents allocation.
        boundary = alev4.createBaselineSensor(struct('wavelength_nm',(1:1000)', ...
            'bin_width_nm',ones(1000,1),'qe',ones(1000,3)/2));
        expectError(@() alev4.simulateSpatialExposure(ones(1,1,1000),grid,g,boundary, ...
            0.01,1,struct('binding_mode','derive','psf',psf)), 'ALEV4:OpticalSupport');
        expectError(@() alev4.simulateSpatialExposure(ones(1,1,1000),grid,g,single, ...
            0.01,1,struct('binding_mode','derive','psf',psf)), 'ALEV4:SpatialSpectralMismatch');
        % The limit concerns active photosites, not the full descriptor.
        g.active_roi = [shape 1 1];
        p = shape-1;
        tiny_grid = alev4.createSpatialGrid(struct('x_edges_m',[p(2) shape(2)], ...
            'y_edges_m',[p(1) shape(1)]));
        for readout = {single,dual}
            result = alev4.simulateSpatialExposure(input,tiny_grid,g,readout{1},0,1, ...
                struct('binding_mode','derive','input_stage','post_optics'));
            assert(isequal(size(result.sampled_irradiance),[1 1 bands]));
            assert(isequal(result.sampled_irradiance,input));
        end
    end
    assert(isequal(rng,before),'Output limit checks altered caller RNG state.');
end

function testNoRandomness()
    rng(3802,'twister');
    before = rng;
    geometry = fixtureGeometry();
    alev4.sensorGrid(geometry);
    single = alev4.bindSensorGeometry(alev4.createBaselineSensor(),geometry,'derive');
    alev4.bindSensorGeometry(single,geometry,'validate');
    alev4.alexa35Geometry('GBRG',[11 13 3 5]);
    expectOverride('origin_xy_m',[1e20 0],'ALEV4:GeometryNumericRange');
    expectError(@() alev4.bindSensorGeometry(alev4.createBaselineSensor(),geometry,'validate'), ...
        'ALEV4:GeometryBindingConflict');
    assert(isequal(rng,before),'Deterministic geometry consumed or reset caller RNG state.');
end

function g = fixtureGeometry()
    g = alev4.createSensorGeometry(struct('full_grid_size',[5 7], ...
        'active_roi',[2 2 3 5],'pixel_pitch_m',2e-6));
end

function expectOverride(field,value,identifier)
    options = struct();
    options.(field) = value;
    expectError(@() alev4.createSensorGeometry(options),identifier);
end

function expectError(action,identifier)
    caught = false;
    try
        action();
    catch err
        caught = true;
        assert(strcmp(err.identifier,identifier), ...
            sprintf('Expected %s, observed %s: %s',identifier,err.identifier,err.message));
    end
    assert(caught,sprintf('Expected rejection %s, but input was accepted.',identifier));
end
