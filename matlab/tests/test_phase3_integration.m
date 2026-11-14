function report = test_phase3_integration()
%TEST_PHASE3_INTEGRATION Independent complete spatial-to-readout invariants.
    caller_rng = rng;
    guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    names = {'scalar_optical_overlap_spectral_and_adc_oracle', ...
        'default_identity_matches_existing_seeded_single_and_dual', ...
        'one_shared_charge_and_equal_single_dual_expectations', ...
        'explicit_derive_and_strict_geometry_binding', ...
        'pre_psf_post_optics_equivalence_and_operation_order', ...
        'post_optics_double_blur_and_invalid_empty_psf_rejection', ...
        'exact_wavelength_kernel_association_and_plane_count', ...
        'cropped_full_grid_cfa_controls_spectral_integration', ...
        'area_fill_exposure_and_spectral_width_applied_once', ...
        'spectral_blur_precedes_cfa_wrong_model_control', ...
        'malformed_options_inputs_and_configuration_rejection', ...
        'rng_and_caller_state_on_success_and_early_late_failures'};
    error_e = testScalarPipeline();
    testSeededIdentity();
    testSharedCharge();
    testBinding();
    testStages();
    testDuplicateOptics();
    testSpectralMapping();
    testCropCfa();
    testCollection();
    wrong_model_gap = testWrongModel();
    testMalformed();
    testCallerState();
    tests = repmat(struct('name','','status','passed','passed',true),1,numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    report = struct('suite','phase3_integration','status','passed','passed',true, ...
        'test_count',numel(names),'tests',tests,'metrics', ...
        struct('maximum_scalar_pipeline_electron_error',error_e, ...
        'post_cfa_blur_wrong_model_maximum_gap_e',wrong_model_gap, ...
        'synthetic',true,'calibrated_alev4',false));
    fprintf('PASS: Phase 3 integration, %d test groups.\n',numel(names));
end

function error_e = testScalarPipeline()
    [input,grid,g,cfg,psf] = asymmetricFixture();
    exposure = 0.002;
    result = alev4.simulateSpatialExposure(input,grid,g,cfg,exposure,101,struct('psf',psf));
    [optical,sampled,expected,incident] = scalarPipeline(input,grid,g,cfg,psf,exposure);
    near(result.optical_irradiance,optical);
    near(result.sampled_irradiance,sampled);
    near(result.readout.expected_electrons,expected);
    near(result.readout.expected_incident_photons,incident);
    raw = uint16(min(65535,max(0,floor(expected*cfg.gain_dn_per_e+cfg.black_level_dn+0.5))));
    assert(isequal(result.readout.raw_dn,raw));
    assert(~any(result.readout.full_well_saturated(:)));
    assert(isequal(result.configuration,cfg));
    assert(strcmp(result.readout.input_units,'photons m^-2 s^-1 nm^-1'));
    error_e = max(abs(result.readout.expected_electrons(:)-expected(:)));
end

function testSeededIdentity()
    [input,grid,g,cfg] = identityFixture();
    a = alev4.simulateSpatialExposure(input,grid,g,cfg,0.003,9234);
    direct = alev4.simulateExposure(input,cfg,0.003,9234);
    assert(isequal(a.readout,direct) && isequal(a.sampled_irradiance,input));
    assert(isequal(a.optical_irradiance,input) && isequal(a.optical_grid,grid));
    assert(a.psf.kernel==1 && isequal(a.psf.spacing_yx_m,[g.pixel_pitch_m g.pixel_pitch_m]));
    dual = alev4.createDualGainSensor(struct('sensor',cfg));
    b = alev4.simulateSpatialExposure(input,grid,g,dual,0.003,9235);
    direct = alev4.simulateDualGainExposure(input,dual,0.003,9235);
    assert(isequal(b.readout,direct));
    assert(strcmp(a.readout_mode,'single') && strcmp(b.readout_mode,'dual'));
    assert(a.synthetic && ~a.calibrated_alev4 && b.synthetic && ~b.calibrated_alev4);
end

function testSharedCharge()
    [input,grid,g,cfg] = identityFixture();
    single = alev4.simulateSpatialExposure(input,grid,g,cfg,0.003,9236);
    dual_cfg = alev4.createDualGainSensor(struct('sensor',cfg, ...
        'high_gain',struct('read_noise_e',0),'low_gain',struct('read_noise_e',0)));
    dual = alev4.simulateSpatialExposure(input,grid,g,dual_cfg,0.003,9236);
    assert(isequal(single.readout.expected_electrons,dual.readout.expected_electrons));
    assert(isequal(single.readout.expected_incident_photons,dual.readout.expected_incident_photons));
    assert(isequal(single.readout.collected_electrons,dual.readout.collected_electrons));
    assert(isequal(dual.readout.high_gain.read_electrons,dual.readout.charge_electrons));
    assert(isequal(dual.readout.low_gain.read_electrons,dual.readout.charge_electrons));
    assert(any(dual.readout.collected_electrons(:)~=dual.readout.expected_electrons(:)));
end

function testBinding()
    [input,grid,g,cfg] = identityFixture();
    cfg.image_size = [32 32]; cfg.pixel_pitch_m = 6e-6; cfg.cfa_pattern = 'BGGR';
    old = cfg;
    expectError(@() alev4.simulateSpatialExposure(input,grid,g,cfg,0.003,1), ...
        'ALEV4:GeometryBindingConflict');
    actual = alev4.simulateSpatialExposure(input,grid,g,cfg,0.003,1,struct('binding_mode','derive'));
    expected = cfg;
    expected.image_size = [5 7]; expected.pixel_pitch_m = g.pixel_pitch_m; expected.cfa_pattern = 'RGGB';
    assert(isequal(actual.configuration,expected) && isequal(cfg,old));
    dual_cfg = alev4.createDualGainSensor(struct('sensor',cfg));
    d = alev4.simulateSpatialExposure(input,grid,g,dual_cfg,0.003,2,struct('binding_mode','derive'));
    expected_dual = dual_cfg; expected_dual.sensor = expected;
    assert(isequal(d.configuration,expected_dual));
    expectError(@() alev4.simulateSpatialExposure(input,grid,g,struct('schema_version','1.0'),0.003,1), ...
        'ALEV4:InvalidGeometryBinding');
    broken = dual_cfg; broken.high_gain = rmfield(broken.high_gain,'read_noise_e');
    expectError(@() alev4.simulateSpatialExposure(input,grid,g,broken,0.003,1,struct('binding_mode','derive')), ...
        'ALEV4:InvalidGeometryBinding');
end

function testStages()
    [input,grid,g,cfg,psf] = asymmetricFixture();
    provenance = struct('source','synthetic_fixture','classification','assumed');
    before = alev4.simulateSpatialExposure(input,grid,g,cfg,0.002,9, ...
        struct('psf',psf,'spatial_provenance',provenance));
    after = alev4.simulateSpatialExposure(before.optical_irradiance,before.optical_grid,g,cfg,0.002,9, ...
        struct('input_stage','post_optics','spatial_provenance',provenance));
    assert(isequal(before.readout,after.readout));
    assert(isequal(before.sampled_irradiance,after.sampled_irradiance));
    assert(isequal(before.operation_order,{'optical_psf','area_overlap_average','spectral_integration','single_gain_readout'}));
    assert(isequal(after.operation_order,{'area_overlap_average','spectral_integration','single_gain_readout'}));
    assert(isequal(after.psf,[]) && isequal(after.spatial_provenance,provenance));
    % A genuinely nonuniform cell grid is supported when optics is already done.
    nonuniform = alev4.createSpatialGrid(struct('x_edges_m',[0 0.3 1],'y_edges_m',[0 0.4 1]));
    geometry = alev4.createSensorGeometry(struct('full_grid_size',[1 1],'pixel_pitch_m',1));
    one = alev4.createBaselineSensor(struct('image_size',[1 1],'pixel_pitch_m',1, ...
        'wavelength_nm',500,'bin_width_nm',1,'qe',[1 1 1],'shot_noise',false,'read_noise_e',0));
    r = alev4.simulateSpatialExposure([1 2;3 4],nonuniform,geometry,one,1,0,struct('input_stage','post_optics'));
    assert(abs(r.sampled_irradiance-2.9)<8*eps(2.9));
    expectError(@() alev4.simulateSpatialExposure([1 2;3 4],nonuniform,geometry,one,1,0), ...
        'ALEV4:OpticalGridMismatch');
end

function testDuplicateOptics()
    [input,grid,g,cfg] = identityFixture();
    psf = alev4.createOpticalPsf(struct('spacing_yx_m',[g.pixel_pitch_m g.pixel_pitch_m]));
    expectError(@() alev4.simulateSpatialExposure(input,grid,g,cfg,0.003,2, ...
        struct('input_stage','post_optics','psf',psf)), 'ALEV4:DuplicateOptics');
    options = struct('input_stage','post_optics','psf',[]);
    a = alev4.simulateSpatialExposure(input,grid,g,cfg,0.003,2,options);
    assert(isequal(a.psf,[]));
    malformed = {'',{},struct([]),zeros(0,2),single([]),false(0,0)};
    for k = 1:numel(malformed)
        options.psf = malformed{k};
        expectError(@() alev4.simulateSpatialExposure(input,grid,g,cfg,0.003,2,options), ...
            'ALEV4:InvalidSpatialOptions');
        options.input_stage = 'pre_psf';
        expectError(@() alev4.simulateSpatialExposure(input,grid,g,cfg,0.003,2,options), ...
            'ALEV4:InvalidSpatialOptions');
        options.input_stage = 'post_optics';
    end
end

function testSpectralMapping()
    [input,grid,g,cfg,psf] = asymmetricFixture();
    kernels = cat(3,psf.kernel,fliplr(psf.kernel));
    bank = alev4.createOpticalPsf(struct('kernel',kernels,'origin_rc',psf.origin_rc, ...
        'spacing_yx_m',psf.spacing_yx_m,'wavelength_nm',cfg.wavelength_nm));
    actual = alev4.simulateSpatialExposure(input,grid,g,cfg,0.002,8,struct('psf',bank));
    [~,sampled,expected] = scalarPipeline(input,grid,g,cfg,bank,0.002);
    near(actual.sampled_irradiance,sampled); near(actual.readout.expected_electrons,expected);
    bank.wavelength_nm(1) = bank.wavelength_nm(1)+1;
    expectError(@() alev4.simulateSpatialExposure(input,grid,g,cfg,0.002,8,struct('psf',bank)), ...
        'ALEV4:OpticalSpectralMapping');
    expectError(@() alev4.simulateSpatialExposure(input(:,:,1),grid,g,cfg,0.002,8), ...
        'ALEV4:SpatialSpectralMismatch');
    too_many = cat(3,input,input(:,:,1));
    expectError(@() alev4.simulateSpatialExposure(too_many,grid,g,cfg,0.002,8), ...
        'ALEV4:SpatialSpectralMismatch');
end

function testCropCfa()
    [input,grid,g,cfg,psf] = asymmetricFixture();
    for pattern = {'RGGB','GRBG','GBRG','BGGR'}
        g.full_grid_cfa_pattern = pattern{1};
        actual = alev4.simulateSpatialExposure(input,grid,g,cfg,0.002,8, ...
            struct('psf',psf,'binding_mode','derive'));
        [~,~,expected] = scalarPipeline(input,grid,g,actual.configuration,psf,0.002);
        near(actual.readout.expected_electrons,expected);
    end
end

function testCollection()
    [input,grid,g,cfg,psf] = asymmetricFixture();
    options = struct('psf',psf);
    a = alev4.simulateSpatialExposure(input,grid,g,cfg,0.002,31,options);
    b = alev4.simulateSpatialExposure(input,grid,g,cfg,0.006,31,options);
    near(b.readout.expected_electrons,3*a.readout.expected_electrons);
    changed = cfg; changed.fill_factor = cfg.fill_factor/2;
    c = alev4.simulateSpatialExposure(input,grid,g,changed,0.002,31,options);
    near(c.readout.expected_electrons,0.5*a.readout.expected_electrons);
    assert(isequal(c.sampled_irradiance,a.sampled_irradiance));
    changed.fill_factor = 0;
    zero_fill = alev4.simulateSpatialExposure(input,grid,g,changed,0.002,31,options);
    zero_time = alev4.simulateSpatialExposure(input,grid,g,cfg,0,31,options);
    assert(all(zero_fill.readout.expected_electrons(:)==0) && all(zero_time.readout.expected_electrons(:)==0));
    assert(all(zero_fill.readout.raw_dn(:)==cfg.black_level_dn));
    % Independent oracle would differ by many orders if pixel area or bin
    % widths were repeated, and by a factor .37 if fill were applied twice.
    [~,~,expected] = scalarPipeline(input,grid,g,cfg,psf,0.002);
    assert(max(abs(expected(:)-expected(:)*cfg.fill_factor))>1);
    near(a.readout.expected_electrons,expected);
end

function gap = testWrongModel()
    p = 5e-6; exposure = 0.001;
    g = alev4.createSensorGeometry(struct('full_grid_size',[4 6],'pixel_pitch_m',p));
    grid = alev4.createSpatialGrid(struct('x_edges_m',(-1:7)*p,'y_edges_m',(-1:5)*p));
    cfg = quietSensor(g);
    cfg.qe = [0.8 0.2 0.05;0.1 0.6 0.3];
    input = cat(3,ones(6,8)*1e14,ones(6,8)*2e14);
    kernel = [1 2 1;2 4 2;1 2 1]/16;
    psf = alev4.createOpticalPsf(struct('kernel',kernel,'origin_rc',[2 2],'spacing_yx_m',[p p]));
    actual = alev4.simulateSpatialExposure(input,grid,g,cfg,exposure,3,struct('psf',psf));
    wrong_mosaic = zeros(6,8);
    for r = 1:6
        for c = 1:8
            channel = absoluteChannel(r-1,c-1,'RGGB');
            for k = 1:2
                wrong_mosaic(r,c) = wrong_mosaic(r,c)+input(r,c,k)*cfg.qe(k,channel)*cfg.bin_width_nm(k);
            end
        end
    end
    wrong = zeros(4,6);
    for r = 1:4
        for c = 1:6
            for a = 1:3
                for b = 1:3
                    wrong(r,c) = wrong(r,c)+kernel(a,b)*wrong_mosaic(r+3-a,c+3-b);
                end
            end
        end
    end
    wrong = wrong*(exposure*p^2*cfg.fill_factor);
    gap = max(abs(wrong(:)-actual.readout.expected_electrons(:)));
    assert(gap > 0.2*max(actual.readout.expected_electrons(:)), ...
        'The fixture must distinguish spectral optics from blurring a Bayer mosaic.');
end

function testMalformed()
    [input,grid,g,cfg] = identityFixture();
    expectError(@() alev4.simulateSpatialExposure(input,grid,g,cfg,0.003), 'ALEV4:SpatialExposureArguments');
    malformed = {[],{},struct([]),struct('unknown',1),struct('input_stage','rgb'), ...
        struct('input_stage',1),struct('spatial_provenance',[]),struct('spatial_provenance',{{'x'}})};
    for k = 1:numel(malformed)
        expectError(@() alev4.simulateSpatialExposure(input,grid,g,cfg,0.003,4,malformed{k}), ...
            'ALEV4:InvalidSpatialOptions');
    end
    expectError(@() alev4.simulateSpatialExposure(input,grid,g,cfg,0.003,4,struct('binding_mode','guess')), ...
        'ALEV4:InvalidGeometryBinding');
    expectError(@() alev4.simulateSpatialExposure(true(size(input)),grid,g,cfg,0.003,4), ...
        'ALEV4:InvalidSpatialIrradiance');
    invalid_input = input; invalid_input(1) = NaN;
    expectError(@() alev4.simulateSpatialExposure(invalid_input,grid,g,cfg,0.003,4), ...
        'ALEV4:InvalidSpatialIrradiance');
    expectError(@() alev4.simulateSpatialExposure(input,grid,g,cfg,-1,4), 'ALEV4:InvalidExposure');
    expectError(@() alev4.simulateSpatialExposure(input,grid,g,cfg,0.003,-1), 'ALEV4:InvalidSeed');
end

function testCallerState()
    [input,grid,g,cfg,psf] = asymmetricFixture();
    options = struct('psf',psf,'spatial_provenance',struct('label','retained'));
    saved = {input,grid,g,cfg,psf,options};
    rng(80172,'twister'); before = rng;
    alev4.simulateSpatialExposure(input,grid,g,cfg,0.002,7,options);
    assert(isequal(before,rng));
    bad_options = options; bad_options.input_stage = 'post_optics';
    expectError(@() alev4.simulateSpatialExposure(input,grid,g,cfg,0.002,7,bad_options),'ALEV4:DuplicateOptics');
    assert(isequal(before,rng));
    expectError(@() alev4.simulateSpatialExposure(input,grid,g,cfg,0.002,NaN,options),'ALEV4:InvalidSeed');
    assert(isequal(before,rng));
    expectError(@() alev4.simulateSpatialExposure(input,grid,g,cfg,-1,7,options),'ALEV4:InvalidExposure');
    assert(isequal(before,rng));
    outside = g; outside.origin_xy_m = [100 100];
    expectError(@() alev4.simulateSpatialExposure(input,grid,outside,cfg,0.002,7,options),'ALEV4:SpatialCoverage');
    assert(isequal(before,rng));
    assert(isequal(saved,{input,grid,g,cfg,psf,options}));
end

function [input,grid,g,cfg,psf] = asymmetricFixture()
    d = 1e-6;
    input = cat(3,reshape(mod((1:224)*7,19)+1,[14 16])*1e14, ...
        reshape(mod((1:224)*11,23)+2,[14 16])*2e13);
    grid = alev4.createSpatialGrid(struct('x_edges_m',(-2:14)*d,'y_edges_m',(-2:12)*d));
    g = alev4.createSensorGeometry(struct('full_grid_size',[4 5], ...
        'active_roi',[2 2 2 3],'pixel_pitch_m',2.5*d,'origin_xy_m',[0.25*d 0.1*d], ...
        'full_grid_cfa_pattern','GRBG'));
    cfg = quietSensor(g);
    psf = alev4.createOpticalPsf(struct('kernel',[1 2 3;4 5 1]/16, ...
        'origin_rc',[1 2],'spacing_yx_m',[d d]));
end

function [input,grid,g,cfg] = identityFixture()
    p = 4e-6;
    input = cat(3,reshape(1:35,[5 7])*2e13,reshape(36:70,[5 7])*1e13);
    g = alev4.createSensorGeometry(struct('full_grid_size',[5 7],'pixel_pitch_m',p));
    grid = alev4.createSpatialGrid(struct('x_edges_m',(0:7)*p,'y_edges_m',(0:5)*p));
    cfg = alev4.createBaselineSensor(struct('image_size',[5 7],'pixel_pitch_m',p, ...
        'wavelength_nm',[470;650],'bin_width_nm',[7;19],'qe',[0.4 0.1 0.8;0.7 0.6 0.2]));
end

function cfg = quietSensor(g)
    base = alev4.createBaselineSensor(struct('wavelength_nm',[470;650], ...
        'bin_width_nm',[7;19],'qe',[0.4 0.1 0.8;0.7 0.6 0.2], ...
        'fill_factor',0.37,'shot_noise',false,'read_noise_e',0));
    cfg = alev4.bindSensorGeometry(base,g,'derive');
end

function [optical,sampled,expected,incident] = scalarPipeline(input,grid,g,cfg,psf,exposure)
    kh = size(psf.kernel,1); kw = size(psf.kernel,2);
    oh = size(input,1)-kh+1; ow = size(input,2)-kw+1; bands = size(input,3);
    optical = zeros(oh,ow,bands);
    for k = 1:bands
        kernel_index = min(k,size(psf.kernel,3));
        for r = 1:oh
            for c = 1:ow
                for a = 1:kh
                    for b = 1:kw
                        optical(r,c,k) = optical(r,c,k)+psf.kernel(a,b,kernel_index)*input(r+kh-a,c+kw-b,k);
                    end
                end
            end
        end
    end
    first = [kh kw]-psf.origin_rc+1;
    xe = grid.x_edges_m(first(2):first(2)+ow);
    ye = grid.y_edges_m(first(1):first(1)+oh);
    roi = g.active_roi; p = g.pixel_pitch_m;
    sampled = zeros(roi(3),roi(4),bands);
    expected = zeros(roi(3:4)); incident = expected;
    for r = 1:roi(3)
        full_r = roi(1)+r-1;
        y0 = g.origin_xy_m(2)+(full_r-1)*p;
        y1 = g.origin_xy_m(2)+full_r*p;
        for c = 1:roi(4)
            full_c = roi(2)+c-1;
            x0 = g.origin_xy_m(1)+(full_c-1)*p;
            x1 = g.origin_xy_m(1)+full_c*p;
            channel = absoluteChannel(full_r,full_c,g.full_grid_cfa_pattern);
            for k = 1:bands
                integral = 0;
                for a = 1:oh
                    height = max(0,min(ye(a+1),y1)-max(ye(a),y0));
                    for b = 1:ow
                        width = max(0,min(xe(b+1),x1)-max(xe(b),x0));
                        integral = integral+optical(a,b,k)*height*width;
                    end
                end
                sampled(r,c,k) = integral/((x1-x0)*(y1-y0));
                incident(r,c) = incident(r,c)+sampled(r,c,k)*cfg.bin_width_nm(k);
                expected(r,c) = expected(r,c)+sampled(r,c,k)*cfg.qe(k,channel)*cfg.bin_width_nm(k);
            end
        end
    end
    expected = expected*(exposure*p^2*cfg.fill_factor);
    incident = incident*(exposure*p^2*cfg.fill_factor);
end

function channel = absoluteChannel(row,column,pattern)
    switch pattern
        case 'RGGB', red=[1 1]; blue=[0 0];
        case 'GRBG', red=[1 0]; blue=[0 1];
        case 'GBRG', red=[0 1]; blue=[1 0];
        case 'BGGR', red=[0 0]; blue=[1 1];
        otherwise, error('Invalid oracle Bayer pattern.');
    end
    channel = 2;
    if mod(row,2)==red(1) && mod(column,2)==red(2), channel=1; end
    if mod(row,2)==blue(1) && mod(column,2)==blue(2), channel=3; end
end

function near(actual,expected)
    assert(isequal(size(actual),size(expected)));
    scale = max(abs(expected(:)));
    if scale==0
        assert(all(actual(:)==0));
    else
        assert(max(abs(actual(:)-expected(:))) <= 256*eps(scale), ...
            'Independent scalar pipeline mismatch.');
    end
end

function expectError(action,identifier)
    before = rng;
    caught = false;
    try
        action();
    catch err
        caught = true;
        assert(strcmp(err.identifier,identifier),'Expected %s; received %s: %s',identifier,err.identifier,err.message);
    end
    assert(caught,'Expected rejection %s.',identifier);
    assert(isequal(before,rng),'Rejected spatial invocation changed caller RNG.');
end
