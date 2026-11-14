function report = test_phase3_geometry()
%TEST_PHASE3_GEOMETRY Independent physical-grid, CFA and binding invariants.
%   Geometry does not alter single/dual readout contracts or consume RNG.
    previous_rng = rng;
    guard = onCleanup(@() rng(previous_rng)); %#ok<NASGU>
    names = {'hand_calculated_centres_edges_and_extents', ...
        'all_full_cfa_patterns_and_crop_parities', ...
        'singleton_odd_and_last_pixel_boundary_grids', ...
        'numeric_representation_normalization', ...
        'invalid_geometry_and_metadata_rejection', ...
        'unsupported_numeric_range_rejection', ...
        'readout_binding_preserves_nonspatial_configuration', ...
        'binding_conflicts_and_explicit_mode_rejection', ...
        'noisy_full_grid_single_and_dual_identity', ...
        'nonuniform_crop_matches_independent_spectral_oracle', ...
        'published_geometry_and_rounding_consistency', ...
        'rng_and_caller_state_preserved_on_success_and_failure'};
    testCoordinates();
    testCfaParities();
    testGridBoundaries();
    testNormalization();
    testInvalidGeometry();
    testNumericRanges();
    testBindingPreservation();
    testBindingConflicts();
    testIdentityReadouts();
    testCroppedSpectrum();
    metrics = testPublishedGeometry();
    testCallerState();
    tests = repmat(struct('name','','status','passed','passed',true),1,numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    report = struct('suite','phase3_geometry','status','passed','passed',true, ...
        'test_count',numel(names),'tests',tests,'metrics',metrics);
    fprintf('PASS: Phase 3 geometry, %d test groups.\n',numel(names));
end

function testCoordinates()
    g = alev4.createSensorGeometry(struct('full_grid_size',[3 5], ...
        'pixel_pitch_m',2,'origin_xy_m',[10 20]));
    grid = alev4.sensorGrid(g);
    assert(isequal(grid.x_edges_m,[10 12 14 16 18 20]));
    assert(isequal(grid.y_edges_m,[20 22 24 26]));
    assert(isequal(grid.x_centers_m,[11 13 15 17 19]));
    assert(isequal(grid.y_centers_m,[21 23 25]));
    assert(isequal(grid.full_extent_xy_m,[10 6]));
    assert(isequal(grid.full_bounds_xy_m,[10 20;20 26]));
    g.active_roi = [2 2 2 3];
    crop = alev4.sensorGrid(g);
    assert(isequal(crop.x_edges_m,[12 14 16 18]));
    assert(isequal(crop.y_edges_m,[22 24 26]));
    assert(isequal(crop.x_centers_m,[13 15 17]));
    assert(isequal(crop.y_centers_m,[23 25]));
    assert(isequal(crop.active_extent_xy_m,[6 4]));
    assert(isequal(crop.active_bounds_xy_m,[12 22;18 26]));
    assert(isequal(crop.image_size,[2 3]));
    assert(strcmp(crop.cfa_pattern,'BGGR'));
    assert(isequal(crop.full_bounds_xy_m,grid.full_bounds_xy_m));
end

function testCfaParities()
    patterns = {'RGGB','BGGR','GRBG','GBRG'};
    dimensions = {[3 5],[1 5],[3 1],[1 1]};
    for p = 1:numel(patterns)
        fullmap = independentCfa([7 9],patterns{p});
        for row = 1:2
            for col = 1:2
                for s = 1:numel(dimensions)
                    sz = dimensions{s};
                    g = alev4.createSensorGeometry(struct('full_grid_size',[7 9], ...
                        'active_roi',[row col sz],'full_grid_cfa_pattern',patterns{p}));
                    grid = alev4.sensorGrid(g);
                    observed = alev4.cfaMap(sz,grid.cfa_pattern);
                    expected = fullmap(row:row+sz(1)-1,col:col+sz(2)-1);
                    assert(isequal(observed,expected), ...
                        'Crop restarted the CFA or used the wrong parity axis.');
                end
            end
        end
    end
end

function testGridBoundaries()
    sizes = {[1 1],[1 7],[5 1],[5 7]};
    for k = 1:numel(sizes)
        sz = sizes{k};
        g = alev4.createSensorGeometry(struct('full_grid_size',sz, ...
            'pixel_pitch_m',0.25,'origin_xy_m',[-3 -2]));
        grid = alev4.sensorGrid(g);
        assert(isequal(g.active_roi,[1 1 sz]));
        assert(numel(grid.x_edges_m) == sz(2)+1);
        assert(numel(grid.y_edges_m) == sz(1)+1);
        for c = 1:sz(2), assert(grid.x_centers_m(c) == -3+(2*c-1)/8); end
        for r = 1:sz(1), assert(grid.y_centers_m(r) == -2+(2*r-1)/8); end
    end
    % Descriptor for the largest supported grid; only one active site is
    % materialized. This must not allocate the full photosite image.
    g = alev4.createSensorGeometry(struct('full_grid_size',[1e8 1], ...
        'active_roi',[1e8 1 1 1]));
    grid = alev4.sensorGrid(g);
    assert(isequal(grid.image_size,[1 1]));
    assert(numel(grid.x_edges_m)==2 && numel(grid.y_edges_m)==2);
    assert(strcmp(grid.cfa_pattern,'GBRG'));
    bad = g; bad.active_roi = [1e8 1 2 1];
    expectError(@() alev4.sensorGrid(bad),'ALEV4:InvalidGeometry');
end

function testNormalization()
    g = alev4.createSensorGeometry(struct('full_grid_size',int32([5;7]), ...
        'active_roi',sparse([2;3;3;4]),'origin_xy_m',single([-1;2]), ...
        'pixel_pitch_m',single(0.5),'full_grid_cfa_pattern','gbrg', ...
        'parameter_sources',{{'TEST-A';'TEST-B'}}));
    assert(isequal(g.full_grid_size,[5 7]) && isa(g.full_grid_size,'double'));
    assert(isequal(g.active_roi,[2 3 3 4]) && ~issparse(g.active_roi));
    assert(isequal(g.origin_xy_m,[-1 2]) && isa(g.pixel_pitch_m,'double'));
    assert(strcmp(g.full_grid_cfa_pattern,'GBRG'));
    assert(isequal(g.parameter_sources,{'TEST-A','TEST-B'}));
    assert(isequal(alev4.createSensorGeometry(g),g));
end

function testInvalidGeometry()
    expectError(@() alev4.createSensorGeometry([]),'ALEV4:InvalidGeometry');
    expectError(@() alev4.createSensorGeometry(struct('typo',1)),'ALEV4:UnknownGeometryField');
    cases = { ...
        'schema_version','2.0'; 'schema_version',1; ...
        'full_grid_size',[]; 'full_grid_size',[1 2 3]; ...
        'full_grid_size',[0 2]; 'full_grid_size',[1.5 2]; ...
        'full_grid_size',[NaN 2]; 'full_grid_size',[Inf 2]; ...
        'full_grid_size',[1+1i 2]; 'full_grid_size',true(1,2); ...
        'active_roi',[1 1 0 1]; 'active_roi',[0 1 1 1]; ...
        'active_roi',[33 1 1 1]; 'active_roi',[32 1 2 1]; ...
        'active_roi',[1 1.5 1 1]; 'active_roi',[1 1 1 Inf]; ...
        'origin_xy_m',[1 NaN]; 'origin_xy_m',[1;2;3]; ...
        'pixel_pitch_m',[1 2]; 'pixel_pitch_m',0; ...
        'pixel_pitch_m',-1; 'pixel_pitch_m',NaN; ...
        'pixel_pitch_m',1+1i; 'pixel_pitch_m',true; ...
        'full_grid_cfa_pattern','RGBG'; 'full_grid_cfa_pattern',{'RGGB'}; ...
        'parameter_sources',{}; 'parameter_sources',{'same','same'}; ...
        'parameter_sources',{'bad id'}; 'parameter_sources',{42}; ...
        'parameter_sources',{'a/b'}; 'parameter_sources',{repmat('A',1,129)}};
    for k = 1:size(cases,1)
        overrides = struct(); overrides.(cases{k,1}) = cases{k,2};
        expectError(@() alev4.createSensorGeometry(overrides),'ALEV4:InvalidGeometry');
    end
end

function testNumericRanges()
    expectError(@() alev4.createSensorGeometry(struct('full_grid_size',[1e8 2])), ...
        'ALEV4:InvalidGeometry');
    expectError(@() alev4.createSensorGeometry(struct('full_grid_size',[1e8+1 1])), ...
        'ALEV4:InvalidGeometry');
    expectError(@() alev4.createSensorGeometry(struct('pixel_pitch_m',1e-200)), ...
        'ALEV4:InvalidGeometry');
    expectError(@() alev4.createSensorGeometry(struct('pixel_pitch_m',1e200)), ...
        'ALEV4:InvalidGeometry');
    expectError(@() alev4.createSensorGeometry(struct('origin_xy_m',[1e20 0])), ...
        'ALEV4:GeometryNumericRange');
    expectError(@() alev4.createSensorGeometry(struct('origin_xy_m',[0 -realmax])), ...
        'ALEV4:GeometryNumericRange');
end

function testBindingPreservation()
    g = alev4.createSensorGeometry(struct('full_grid_size',[7 9], ...
        'active_roi',[2 2 3 5],'pixel_pitch_m',4e-6));
    single = alev4.createBaselineSensor(struct('image_size',[2 4], ...
        'fill_factor',0.43,'full_well_e',27000,'gain_dn_per_e',0.7, ...
        'read_noise_e',1.3,'black_level_dn',71,'adc_bits',14));
    old = single;
    expected = single; expected.image_size=[3 5];
    expected.pixel_pitch_m=4e-6; expected.cfa_pattern='BGGR';
    derived = alev4.bindSensorGeometry(single,g,'derive');
    assert(isequal(single,old) && isequal(derived,expected));
    assert(isequal(alev4.bindSensorGeometry(derived,g,'validate'),derived));
    dual = alev4.createDualGainSensor(struct('sensor',struct('fill_factor',0.63), ...
        'high_gain',struct('read_noise_e',1.7),'low_gain',struct('read_noise_e',6.3)));
    old = dual; expected = dual;
    expected.sensor.image_size=[3 5]; expected.sensor.pixel_pitch_m=4e-6;
    expected.sensor.cfa_pattern='BGGR';
    derived = alev4.bindSensorGeometry(dual,g,'derive');
    assert(isequal(dual,old) && isequal(derived,expected));
    assert(isequal(alev4.bindSensorGeometry(derived,g,'validate'),derived));
end

function testBindingConflicts()
    g = alev4.createSensorGeometry();
    for dual = [false true]
        if dual, cfg = alev4.createDualGainSensor(); else, cfg = alev4.createBaselineSensor(); end
        changes = {'image_size',[31 32];'pixel_pitch_m',7e-6;'cfa_pattern','BGGR'};
        for k = 1:size(changes,1)
            bad = cfg;
            if dual, bad.sensor.(changes{k,1}) = changes{k,2};
            else, bad.(changes{k,1}) = changes{k,2}; end
            expectError(@() alev4.bindSensorGeometry(bad,g,'validate'),'ALEV4:GeometryBindingConflict');
        end
    end
    s = alev4.createBaselineSensor();
    expectError(@() alev4.bindSensorGeometry(s,g),'ALEV4:InvalidGeometryBinding');
    expectError(@() alev4.bindSensorGeometry(s,g,'auto'),'ALEV4:InvalidGeometryBinding');
    expectError(@() alev4.bindSensorGeometry(struct(),g,'derive'),'ALEV4:InvalidGeometryBinding');
    expectError(@() alev4.bindSensorGeometry(struct('schema_version','3.0'),g,'derive'), ...
        'ALEV4:InvalidGeometryBinding');
end

function testIdentityReadouts()
    g = alev4.createSensorGeometry(struct('full_grid_size',[5 7], ...
        'pixel_pitch_m',4e-6,'full_grid_cfa_pattern','GBRG','origin_xy_m',[-1e-3 2e-3]));
    s = alev4.createBaselineSensor(struct('image_size',[5 7], ...
        'pixel_pitch_m',4e-6,'cfa_pattern','GBRG'));
    d = alev4.createDualGainSensor(struct('sensor',s));
    light = reshape(1:(5*7*numel(s.wavelength_nm)),5,7,[])*1e12;
    bound_s = alev4.bindSensorGeometry(s,g,'derive');
    bound_d = alev4.bindSensorGeometry(d,g,'derive');
    assert(isequal(bound_s,s) && isequal(bound_d,d));
    a = alev4.simulateExposure(light,s,1e-3,32001);
    b = alev4.simulateExposure(light,bound_s,1e-3,32001);
    assert(isequal(a,b), 'Geometry changed exact seeded single-gain output.');
    a = alev4.simulateDualGainExposure(light,d,1e-3,32002);
    b = alev4.simulateDualGainExposure(light,bound_d,1e-3,32002);
    assert(isequal(a,b), 'Geometry changed exact seeded dual-gain output.');
    assert(any(a.collected_electrons(:) ~= a.expected_electrons(:)), ...
        'The identity fixture must exercise actual shot noise.');
end

function testCroppedSpectrum()
    g = alev4.createSensorGeometry(struct('full_grid_size',[5 7], ...
        'pixel_pitch_m',2e-6,'full_grid_cfa_pattern','GRBG'));
    s = alev4.createBaselineSensor(struct('image_size',[5 7], ...
        'pixel_pitch_m',2e-6,'cfa_pattern','GRBG','fill_factor',0.7, ...
        'wavelength_nm',[500;600],'bin_width_nm',[10;20], ...
        'qe',[0.1 0.2 0.3;0.7 0.6 0.5],'shot_noise',false,'read_noise_e',0));
    light = zeros(5,7,2);
    for r = 1:5
        for c = 1:7
            light(r,c,1)=(r+3*c)*1e14;
            light(r,c,2)=(2*r+c)*1e14;
        end
    end
    full = alev4.simulateExposure(light,s,0.02,32003);
    g.active_roi = [2 3 3 4];
    crop_s = alev4.bindSensorGeometry(s,g,'derive');
    crop = alev4.simulateExposure(light(2:4,3:6,:),crop_s,0.02,32003);
    assert(isequal(crop.expected_electrons,full.expected_electrons(2:4,3:6)));
    map = independentCfa([5 7],'GRBG');
    oracle = zeros(3,4);
    for r = 2:4
        for c = 3:6
            channel = map(r,c);
            oracle(r-1,c-2)=0.02*(2e-6)^2*0.7*( ...
                light(r,c,1)*10*s.qe(1,channel)+light(r,c,2)*20*s.qe(2,channel));
        end
    end
    assert(max(abs(crop.expected_electrons(:)-oracle(:))) <= ...
        8*eps(max(oracle(:))), 'Cropping mixed CFA, area or spectral factors.');
end

function metrics = testPublishedGeometry()
    expectError(@() alev4.alexa35Geometry(),'ALEV4:AssumedCfaRequired');
    g = alev4.alexa35Geometry('RGGB');
    assert(isequal(g.full_grid_size,[3164 4608]));
    assert(isequal(g.active_roi,[1 1 3164 4608]));
    assert(g.pixel_pitch_m == 6.075e-6);
    grid = alev4.sensorGrid(g);
    dimensions_mm = grid.full_extent_xy_m*1000;
    assert(max(abs(dimensions_mm-[27.9936 19.2213])) < 1e-13);
    assert(isequal(round(dimensions_mm*100)/100,[27.99 19.22]));
    assert(any(strcmp(g.parameter_sources,'ARRI-A35-GEOMETRY')));
    assert(any(strcmp(g.parameter_sources,'ASSUMED-CFA-ORIGIN')));
    cropped = alev4.alexa35Geometry('GRBG',[3164 4608 1 1]);
    grid = alev4.sensorGrid(cropped);
    assert(isequal(grid.image_size,[1 1]) && strcmp(grid.cfa_pattern,'GBRG'));
    metrics = struct('published_grid_rows_columns',[3164 4608], ...
        'nominal_pitch_m',g.pixel_pitch_m,'derived_extent_mm',dimensions_mm, ...
        'rounding_difference_mm',dimensions_mm-[27.99 19.22], ...
        'manufacturer_uncertainty_claimed',false);
end

function testCallerState()
    rng(32004,'twister');
    before = rng;
    g = alev4.createSensorGeometry(struct('full_grid_size',[3 5]));
    old = g;
    s = alev4.createBaselineSensor(); old_s = s;
    alev4.sensorGrid(g);
    alev4.bindSensorGeometry(s,g,'derive');
    alev4.alexa35Geometry('BGGR',[1 1 1 1]);
    assert(isequal(before,rng) && isequal(g,old) && isequal(s,old_s));
    expectError(@() alev4.createSensorGeometry(struct('pixel_pitch_m',0)), ...
        'ALEV4:InvalidGeometry');
    expectError(@() alev4.bindSensorGeometry(s,g,'validate'),'ALEV4:GeometryBindingConflict');
    assert(isequal(before,rng) && isequal(g,old) && isequal(s,old_s));
end

function map = independentCfa(sz,pattern)
    % Explicit colour positions rather than the production reshape/parity
    % transformation; the oracle works on full-grid absolute row/column.
    switch pattern
        case 'RGGB', red=[1 1]; blue=[0 0];
        case 'BGGR', red=[0 0]; blue=[1 1];
        case 'GRBG', red=[1 0]; blue=[0 1];
        case 'GBRG', red=[0 1]; blue=[1 0];
        otherwise, error('Invalid test fixture pattern.');
    end
    map = 2*ones(sz);
    for r = 1:sz(1)
        for c = 1:sz(2)
            if mod(r,2)==red(1) && mod(c,2)==red(2), map(r,c)=1; end
            if mod(r,2)==blue(1) && mod(c,2)==blue(2), map(r,c)=3; end
        end
    end
end

function expectError(action,identifier)
    caught = false;
    try
        action();
    catch err
        caught = true;
        assert(strcmp(err.identifier,identifier), ...
            'Expected %s; observed %s: %s',identifier,err.identifier,err.message);
    end
    assert(caught,'Expected rejection %s.',identifier);
end
