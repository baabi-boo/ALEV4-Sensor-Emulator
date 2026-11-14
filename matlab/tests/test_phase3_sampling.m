function report = test_phase3_sampling()
%TEST_PHASE3_SAMPLING Independent rectangular-overlap and density contracts.
%   Oracles use scalar physical rectangle intersections and analytical source
%   integrals, not the production overlap matrices or producer pass flags.
    caller_rng = rng;
    guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    names = {'nonuniform_crop_matches_hand_integrals', ...
        'same_extent_conserves_each_spectral_integral', ...
        'noninteger_ratio_and_subpixel_offset', ...
        'constant_linearity_and_spectral_independence', ...
        'deterministic_scalar_overlap_matrix', ...
        'source_edge_refinement_has_analytical_error_bound', ...
        'full_footprint_coverage_is_strict', ...
        'spatial_grid_validation_and_numeric_representation', ...
        'irradiance_validation_singletons_and_sparse_input', ...
        'collection_factors_are_applied_exactly_once', ...
        'aligned_crop_and_seeded_readout_identity', ...
        'numeric_underflow_and_diagnostic_limits_are_explicit', ...
        'deterministic_sampling_preserves_rng_and_caller_inputs'};
    metrics.crop = testHandCrop();
    testConservation();
    testNonintegerAndOffset();
    testLinearProperties();
    metrics.scalar_oracle = testScalarOracleCases();
    metrics.edge_refinement = testEdgeRefinement();
    testCoverage();
    testGridValidation();
    testIrradianceValidation();
    testCollectionFactors();
    testAlignedAndSeededIdentity();
    testNumericLimits();
    testStatePreservation();
    tests = repmat(struct('name','','status','passed','passed',true),1,numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    report = struct('suite','phase3_sampling','status','passed','passed',true, ...
        'test_count',numel(names),'tests',tests,'metrics',metrics);
    fprintf('PASS: Phase 3 conservative sampling, %d test groups.\n',numel(names));
end

function metrics = testHandCrop()
    grid = spatialGrid([0 1 3],[0 2 3]);
    data = [2 6;10 14];
    geometry = pixelGeometry([2 2],1,[0.5 0.5]);
    [actual,description] = alev4.resampleSensorIrradiance(data,grid,geometry);
    expected = [4 6;8 10];
    assert(isequal(actual,expected));
    % Full source areas are [2,4;1,2]; crop covers only part of that region.
    full_integral = 2*2+6*4+10*1+14*2;
    crop_integral = 4+6+8+10;
    assert(full_integral==66 && crop_integral==28);
    assert(isequal(description.source_integral.values,66));
    assert(isequal(description.source_crop_integral.values,28));
    assert(isequal(description.target_integral.values,28));
    assert(~description.identity && ~description.aligned_copy);
    assert(strcmp(description.output_units,'photons m^-2 s^-1 nm^-1'));
    metrics = struct('source_integral',66,'crop_integral',28, ...
        'maximum_absolute_density_error',max(abs(actual(:)-expected(:))));
end

function testConservation()
    grid = spatialGrid([0 1 3],[0 2 3]);
    data = cat(3,[2 6;10 14],[3 1;7 2],[0 0;0 0]);
    geometry = pixelGeometry([3 3],1,[0 0]);
    [actual,description] = alev4.resampleSensorIrradiance(data,grid,geometry);
    expected_first = [2 6 6;2 6 6;10 14 14];
    expected_second = [3 1 1;3 1 1;7 2 2];
    assert(isequal(actual(:,:,1),expected_first));
    assert(isequal(actual(:,:,2),expected_second));
    assert(all(reshape(actual(:,:,3),[],1)==0));
    expected_integrals = [66 21 0];
    for k=1:3
        plane = actual(:,:,k);
        assert(sum(plane(:))==expected_integrals(k));
    end
    assert(isequal(description.source_integral.values,expected_integrals));
    assert(isequal(description.source_crop_integral.values,expected_integrals));
    assert(isequal(description.target_integral.values,expected_integrals));
end

function testNonintegerAndOffset()
    grid = spatialGrid([0 0.6 1.4 2],[0 1]);
    actual = alev4.resampleSensorIrradiance([1 3 5],grid,pixelGeometry([1 2],1,[0 0]));
    assertNear(actual,[1.8 4.2],64);
    % Quarter-cell horizontal and half-cell vertical offset. Four weights
    % are independently 3/8,1/8,3/8,1/8, giving an average of six.
    grid = spatialGrid([0 1 2],[0 1 2]);
    actual = alev4.resampleSensorIrradiance([1 5;9 13],grid,pixelGeometry([1 1],1,[0.25 0.5]));
    assert(actual==6);
    unshifted = alev4.resampleSensorIrradiance([1 5;9 13],grid,pixelGeometry([1 1],1,[0 0]));
    assert(unshifted==1 && actual~=unshifted);
    % Transposing source and geometry exercises singleton columns as well.
    transposed_grid = spatialGrid([0 1],[0 0.6 1.4 2]);
    vertical = alev4.resampleSensorIrradiance([1;3;5],transposed_grid,pixelGeometry([2 1],1,[0 0]));
    assertNear(vertical,[1.8;4.2],64);
end

function testLinearProperties()
    grid = spatialGrid([0 0.4 0.9 1.7 2.3],[0 0.5 1.1 2]);
    geometry = pixelGeometry([2 2],0.8,[0.3 0.2]);
    a = reshape(1:12,3,4)/7;
    b = reshape(mod(0:11,5),3,4)/3;
    x = alev4.resampleSensorIrradiance(a,grid,geometry);
    y = alev4.resampleSensorIrradiance(b,grid,geometry);
    combined = alev4.resampleSensorIrradiance(0.25*a+1.75*b,grid,geometry);
    assertNear(combined,0.25*x+1.75*y,256);
    data = cat(3,a,zeros(size(a)),b,7*ones(size(a)));
    actual = alev4.resampleSensorIrradiance(data,grid,geometry);
    assertNear(actual(:,:,1),x,64);
    assertNear(actual(:,:,3),y,64);
    assert(all(reshape(actual(:,:,2),[],1)==0));
    assertNear(actual(:,:,4),7*ones(2),128);
    assert(all(actual(:)>=0) && max(actual(:))<=7+128*eps(7));
end

function metrics = testScalarOracleCases()
    maximum_error = 0;
    for trial=1:24
        nx = 3+mod(trial,4);
        ny = 2+mod(trial,3);
        dx = 1+mod((1:nx)*(trial+2),7)/8;
        dy = 1+mod((1:ny)*(trial+4),5)/6;
        sx = [0 cumsum(dx)]; sx = 3*sx/sx(end);
        sy = [0 cumsum(dy)]; sy = 2.5*sy/sy(end);
        data = zeros(ny,nx,3);
        for k=1:3
            for r=1:ny
                for c=1:nx
                    data(r,c,k) = mod(7*r+11*c+13*k+trial,29)/5;
                end
            end
        end
        geometry = pixelGeometry([2 3],0.5,[0.1+trial/200 0.2+trial/300]);
        grid = spatialGrid(sx,sy);
        actual = alev4.resampleSensorIrradiance(data,grid,geometry);
        expected = scalarOverlap(data,sx,sy,geometry);
        assertNear(actual,expected,512);
        maximum_error = max(maximum_error,max(abs(actual(:)-expected(:))));
    end
    metrics = struct('cases',24,'maximum_absolute_density_error',maximum_error);
end

function metrics = testEdgeRefinement()
    % The continuous field is a unit step at 0.3897. Each source value is
    % its exact cell average. Replacing that field by cellwise constants
    % causes a bounded error only where the cropped pixel splits the cell
    % containing the discontinuity. The error is <= cell_width/pixel_width.
    location = 0.3897;
    left = 0.383;
    pitch = 0.5;
    truth = (left+pitch-location)/pitch;
    counts = [4 8 16 32 64 128 256];
    errors = zeros(size(counts));
    bounds = zeros(size(counts));
    geometry = pixelGeometry([1 1],pitch,[left 0]);
    for j=1:numel(counts)
        n = counts(j);
        sx = (0:n)/n;
        source = max(0,sx(2:end)-max(sx(1:end-1),location))./diff(sx);
        actual = alev4.resampleSensorIrradiance(source,spatialGrid(sx,[0 pitch]),geometry);
        errors(j) = abs(actual-truth);
        bounds(j) = 1/(n*pitch);
        assert(errors(j)<=bounds(j)+128*eps(truth));
        % Source conservation is independently known before any crop.
        assertNear(sum(source.*diff(sx)),1-location,128);
    end
    assert(errors(1)>0.05,'Coarse fixture no longer exposes source approximation error.');
    assert(errors(end)<errors(1)/1000 && errors(end)<128*eps(truth));
    metrics = struct('source_cell_counts',counts,'absolute_error',errors, ...
        'analytical_absolute_bound',bounds,'exact_crop_average',truth, ...
        'source_model','exact step-cell averages represented as piecewise constants');
end

function testCoverage()
    geometry = pixelGeometry([1 1],1,[0 0]);
    grids = {spatialGrid([eps(1) 1],[0 1]), ...
        spatialGrid([0 1-eps(1)],[0 1]), ...
        spatialGrid([0 1],[eps(1) 1]), ...
        spatialGrid([0 1],[0 1-eps(1)]), ...
        spatialGrid([2 3],[0 1])};
    for k=1:numel(grids)
        expectError(@() alev4.resampleSensorIrradiance(7,grids{k},geometry), ...
            'ALEV4:SpatialCoverage');
    end
    assert(alev4.resampleSensorIrradiance(7,spatialGrid([0 1],[0 1]),geometry)==7);
end

function testGridValidation()
    grid = alev4.createSpatialGrid(struct('x_edges_m',sparse([0;1;3]), ...
        'y_edges_m',int16([-2;0;3])));
    assert(isequal(grid.x_edges_m,[0 1 3]) && isequal(grid.y_edges_m,[-2 0 3]));
    assert(isa(grid.y_edges_m,'double') && ~issparse(grid.x_edges_m));
    expectError(@() alev4.createSpatialGrid([]),'ALEV4:InvalidSpatialGrid');
    expectError(@() alev4.createSpatialGrid(struct('x_edge_m',[0 1])), ...
        'ALEV4:UnknownSpatialGridField');
    fields = {'schema_version','units','sample_semantics'};
    values = {'2.0','mm','point_samples'};
    for k=1:numel(fields)
        invalid = struct(); invalid.(fields{k})=values{k};
        expectError(@() alev4.createSpatialGrid(invalid),'ALEV4:InvalidSpatialGrid');
    end
    edges = {[],1,[0 0],[1 0],[0 NaN],[0 Inf],[0 1i],true(1,2), ...
        [0 1;2 3],[-realmax realmax],reshape([0 1],1,1,2)};
    for k=1:numel(edges)
        expectError(@() alev4.createSpatialGrid(struct('x_edges_m',edges{k})), ...
            'ALEV4:InvalidSpatialGrid');
    end
    expectError(@() spatialGrid([0 1e-200],[0 1e-200]),'ALEV4:SpatialNumericRange');
    expectError(@() spatialGrid([0 1e200],[0 1e200]),'ALEV4:SpatialNumericRange');
    % Adjacent edges can be distinct while no longer accurately describing
    % nominal pitch; the geometry support bound must reject this distortion.
    expectError(@() pixelGeometry([1 2],0.6,[1e15 0]),'ALEV4:GeometryNumericRange');
end

function testIrradianceValidation()
    grid = spatialGrid([0 1 2],[0 1]);
    [actual,canonical] = alev4.validateSpatialIrradiance(sparse([3 5]),grid);
    assert(isequal(actual,[3 5]) && ~issparse(actual));
    assert(isequal(canonical,grid));
    [actual,~] = alev4.validateSpatialIrradiance(uint16([3 5]),grid);
    assert(isa(actual,'double') && isequal(actual,[3 5]));
    invalid = {[],[1;2],[1 2 3],[-1 2],[1 Inf],[NaN 2],[1+1i 2], ...
        true(1,2),'12',ones(1,2,1,2),{1,2}};
    for k=1:numel(invalid)
        expectError(@() alev4.validateSpatialIrradiance(invalid{k},grid), ...
            'ALEV4:InvalidSpatialIrradiance');
    end
    cube = cat(3,[1 2],[5 7],[11 13]);
    [actual,~] = alev4.validateSpatialIrradiance(cube,grid);
    assert(isequal(actual,cube) && size(actual,3)==3);
    % A small input must still reject an oversized output spectral cube.
    % Keep axes bounded even if validation order regresses, so the negative
    % test itself cannot require the prohibited output allocation.
    for dims = {[1 100000],[100000 1]}
        shape = dims{1};
        large_geometry = pixelGeometry(shape,1,[0 0]);
        coarse = spatialGrid([0 shape(2)],[0 shape(1)]);
        expectError(@()alev4.resampleSensorIrradiance(ones(1,1,1001), ...
            coarse,large_geometry),'ALEV4:InvalidSpatialSampling');
    end
end

function testCollectionFactors()
    % Two pitch-2 square pixels average four source columns into [3,7].
    % The independent expected charge is density*10nm*0.2s*4m2*0.25*QE.
    data = [2 4 6 8];
    grid = spatialGrid(0:4,[0 2]);
    geometry = pixelGeometry([1 2],2,[0 0]);
    cfg = alev4.createBaselineSensor(struct('image_size',[1 2], ...
        'pixel_pitch_m',2,'wavelength_nm',500,'bin_width_nm',10, ...
        'qe',[0.2 0.5 0.8],'fill_factor',0.25,'shot_noise',false, ...
        'read_noise_e',0,'gain_dn_per_e',1));
    sampled = alev4.resampleSensorIrradiance(data,grid,geometry);
    assert(isequal(sampled,[3 7]));
    observed = alev4.simulateExposure(sampled,cfg,0.2,3813);
    assertNear(observed.expected_incident_photons,[6 14],64);
    assertNear(observed.expected_electrons,[1.2 7],64);
    assertNear(double(observed.raw_dn),[65 71],1);
    cfg.fill_factor = 0.5;
    doubled = alev4.simulateExposure(sampled,cfg,0.2,3813);
    assertNear(doubled.expected_electrons,[2.4 14],64);
    assert(isequal(alev4.resampleSensorIrradiance(data,grid,geometry),sampled));
    cfg.fill_factor = 0;
    zero = alev4.simulateExposure(sampled,cfg,0.2,3813);
    assert(all(zero.expected_electrons(:)==0));
end

function testAlignedAndSeededIdentity()
    pitch = 2^-20;
    source = reshape(1:126,7,9,2)*1e11;
    grid = spatialGrid((0:9)*pitch,(0:7)*pitch);
    geometry = alev4.createSensorGeometry(struct('full_grid_size',[7 9], ...
        'active_roi',[2 3 3 5],'pixel_pitch_m',pitch));
    [crop,description] = alev4.resampleSensorIrradiance(source,grid,geometry);
    assert(isequal(crop,source(2:4,3:7,:)) && description.aligned_copy && ~description.identity);

    geometry = pixelGeometry([7 9],pitch,[0 0]);
    base = alev4.createBaselineSensor(struct('image_size',[7 9], ...
        'pixel_pitch_m',pitch,'wavelength_nm',[500;600],'bin_width_nm',[10;20], ...
        'qe',[0.3 0.5 0.2;0.7 0.4 0.1],'read_noise_e',1.4));
    options = struct('input_stage','post_optics');
    direct = alev4.simulateExposure(source,base,0.02,3814);
    spatial = alev4.simulateSpatialExposure(source,grid,geometry,base,0.02,3814,options);
    assert(isequal(spatial.sampled_irradiance,source));
    assert(isequal(spatial.readout,direct),'Identity spatial sampling changed single-gain random draws.');
    shared = rmfield(base,{'read_noise_e','gain_dn_per_e','black_level_dn','adc_bits'});
    dual = alev4.createDualGainSensor(struct('sensor',shared));
    direct_dual = alev4.simulateDualGainExposure(source,dual,0.02,3814);
    spatial_dual = alev4.simulateSpatialExposure(source,grid,geometry,dual,0.02,3814,options);
    assert(isequal(spatial_dual.readout,direct_dual), ...
        'Identity spatial sampling changed the shared-shot dual-gain path.');
end

function testNumericLimits()
    % A represented positive constant must not silently disappear in
    % fractional weight products. Explicit range rejection is also valid.
    for multiple=[1 3 5 7 9]
        tiny = multiple*eps(0);
        try
            output = alev4.resampleSensorIrradiance([tiny tiny], ...
                spatialGrid([0 0.5 1],[0 1]),pixelGeometry([1 1],1,[0 0]));
            assert(output==tiny,'Representable positive constant changed during spatial averaging.');
        catch err
            assert(strcmp(err.identifier,'ALEV4:SpatialNumericRange'), ...
                sprintf('Subnormal fixture must preserve density or explicitly reject range: %s',err.message));
        end
    end
    % Optional area-integrated diagnostics can overflow even when density
    % and grid are finite and the exact identity output is representable.
    huge_grid = spatialGrid([0 1e50],[0 1e50]);
    [output,description] = alev4.resampleSensorIrradiance(1e300,huge_grid, ...
        pixelGeometry([1 1],1e50,[0 0]));
    assert(output==1e300);
    assert(strcmp(description.source_integral.status,'unavailable_numeric_range'));
    assert(isempty(description.source_integral.values));
    assert(strcmp(description.target_integral.status,'unavailable_numeric_range'));
    assert(isempty(description.target_integral.values));
end

function testStatePreservation()
    rng(3815,'twister');
    before = rng;
    geometry = pixelGeometry([2 2],1,[0.5 0.5]);
    grid = spatialGrid([0 1 3],[0 2 3]);
    data = [2 6;10 14];
    original_geometry = geometry; original_grid = grid; original_data = data;
    alev4.resampleSensorIrradiance(data,grid,geometry);
    expectError(@() alev4.resampleSensorIrradiance(data*NaN,grid,geometry), ...
        'ALEV4:InvalidSpatialIrradiance');
    expectError(@() alev4.resampleSensorIrradiance(1,spatialGrid([0 1],[0 1]),geometry), ...
        'ALEV4:SpatialCoverage');
    assert(isequal(rng,before),'Deterministic sampling changed caller RNG state.');
    assert(isequal(geometry,original_geometry) && isequal(grid,original_grid) && isequal(data,original_data));
end

function output = scalarOverlap(data,sx,sy,geometry)
    % Independently enumerate every source rectangle for every destination.
    % This intentionally shares no sparse axis construction with production.
    roi = geometry.active_roi;
    p = geometry.pixel_pitch_m;
    origin = geometry.origin_xy_m;
    output = zeros(roi(3),roi(4),size(data,3));
    for k=1:size(data,3)
        for r=1:roi(3)
            bottom = origin(2)+(roi(1)-1+r)*p;
            top = origin(2)+(roi(1)-2+r)*p;
            for c=1:roi(4)
                right = origin(1)+(roi(2)-1+c)*p;
                left = origin(1)+(roi(2)-2+c)*p;
                total = 0;
                for a=1:numel(sy)-1
                    for b=1:numel(sx)-1
                        width = max(0,min(right,sx(b+1))-max(left,sx(b)));
                        height = max(0,min(bottom,sy(a+1))-max(top,sy(a)));
                        total = total+data(a,b,k)*width*height;
                    end
                end
                output(r,c,k) = total/((right-left)*(bottom-top));
            end
        end
    end
end

function grid = spatialGrid(xedges,yedges)
    grid = alev4.createSpatialGrid(struct('x_edges_m',xedges,'y_edges_m',yedges));
end

function geometry = pixelGeometry(size_rc,pitch,origin)
    geometry = alev4.createSensorGeometry(struct('full_grid_size',size_rc, ...
        'pixel_pitch_m',pitch,'origin_xy_m',origin));
end

function assertNear(actual,expected,ulps)
    assert(isequal(size(actual),size(expected)),'Numerical oracle shape differs.');
    scale = max(abs(expected(:)));
    if scale==0
        assert(all(actual(:)==0),'Exact-zero oracle failed.');
    else
        assert(all(isfinite(actual(:))) && max(abs(actual(:)-expected(:)))<=ulps*eps(scale), ...
            sprintf('Scalar oracle discrepancy %.17g exceeds %.17g.', ...
                max(abs(actual(:)-expected(:))),ulps*eps(scale)));
    end
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
