function report = test_phase4_numerical_edges()
%TEST_PHASE4_NUMERICAL_EDGES Binary64 limits and safe descriptor-only bounds.
%   Literal equations/ULP boundaries supply numerical expectations. Temporary
%   fault sentinels prevent large dense allocation even if a guard regresses.
    previous = rng;
    cleanup = onCleanup(@()rng(previous)); %#ok<NASGU>
    rng(904271,'twister'); rand(1,3); randn(1,5);
    names = {'represented_seed_and_sequence_index_endpoints', ...
        'exact_zero_support_at_finite_extremes', ...
        'normal_boundary_and_signed_cancellation', ...
        'spectral_overflow_and_positive_support_underflow', ...
        'prnu_dark_and_total_charge_arithmetic', ...
        'poisson_limit_and_component_preflight', ...
        'electronic_rms_and_gain_numeric_limits', ...
        'late_stochastic_failure_restores_rng', ...
        'constructor_aggregate_maps_reject_before_densification', ...
        'core_combined_budget_rejects_before_expansion', ...
        'spatial_combined_budget_rejects_before_legacy_sampling', ...
        'spatial_retained_options_and_spectral_storage_are_bounded', ...
        'bounded_spatial_and_disabled_legacy_results', ...
        'sequence_retained_model_budget_and_failure_cleanup'};
    checks = {@seedBounds,@zeroEndpoints,@normalBoundary,@spectralLimits, ...
        @chargeLimits,@poissonLimits,@electronicLimits,@lateFailure, ...
        @constructorBudget,@coreBudget,@spatialBudget,@spatialStorage, ...
        @spatialIdentity,@sequenceBounds};
    metrics = cell(1,numel(checks)); before = rng;
    for k = 1:numel(checks)
        metrics{k} = checks{k}();
        assert(isequal(before,rng),'An edge group changed the caller RNG.');
    end
    tests = repmat(struct('name','','status','passed','passed',true),1,numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    report = struct('suite','phase4_numerical_edges','status','passed','passed',true, ...
        'test_count',numel(tests),'tests',tests,'metrics',struct( ...
        'groups',{metrics},'runtime_version',version(),'numeric_sample_limit',1e8, ...
        'large_dense_fixtures_allocated',false,'synthetic',true,'calibrated_alev4',false));
    fprintf('PASS: Phase 4 numerical edges, %d test groups.\n',numel(tests));
end

function metrics = seedBounds()
    [cfg,g,m] = fixture();
    accepted = {0,uint32(4294967295),uint64(4294967295),single(4294967040),sparse(63)};
    for k = 1:numel(accepted)
        seed = accepted{k}; represented = double(seed);
        assert(alev4.structuredNoiseSeed(seed,'low_pixel') == mod(represented+43,4294967296));
        result = alev4.simulateStructuredExposure(0,cfg,0,seed,m,g);
        assert(result.seeds.frame==represented);
    end
    assert(double(single(4294967295))==4294967296);
    bad = {-eps(0),4294967295+eps(4294967295),4294967296, ...
        single(4294967295),intmax('uint64'),NaN,Inf,true};
    for k = 1:numel(bad)
        reject(@()alev4.simulateStructuredExposure(0,cfg,0,bad{k},m,g),'ALEV4:InvalidSeed');
    end
    last = alev4.simulateNoiseSequence(0,cfg,0,uint32(4294967295),m,g, ...
        struct('start_frame',uint64(67108864)));
    assert(last.frame_seeds==4294967231 && last.frames{1}.seeds.low_pixel==4294967274);
    rounded = alev4.simulateNoiseSequence(0,cfg,0,4294967295,m,g, ...
        struct('start_frame',single(67108863)));
    assert(double(single(67108863))==67108864 && isequal(last,rounded));
    reject(@()alev4.simulateNoiseSequence(0,cfg,0,0,m,g, ...
        struct('start_frame',uint64(67108865))),'ALEV4:InvalidNoiseSequenceIndices');
    metrics = struct('accepted_seed_representations',5,'rejected_seed_representations',8, ...
        'maximum_absolute_frame_index',67108864,'last_frame_seed',4294967231);
end

function metrics = zeroEndpoints()
    [cfg,g,m] = fixture(); m.prnu=realmax; m.dark_current_e_per_s=realmax;
    zero = alev4.simulateStructuredExposure(realmax,cfg,0,9,m,g);
    assert(zero.readout.expected_electrons==0 && zero.readout.expected_incident_photons==0);
    m.dark_current_e_per_s=0;
    dark = alev4.simulateStructuredExposure(0,cfg,realmax,9,m,g);
    assert(dark.readout.collected_electrons==0);
    empty = cfg; empty.fill_factor=0;
    result = alev4.simulateStructuredExposure(realmax,empty,realmax,9,m,g);
    assert(result.readout.expected_electrons==0);
    m.prnu=0;
    result = alev4.simulateStructuredExposure(realmax,cfg,1,9,m,g);
    assert(result.baseline_expected_electrons==realmax && result.readout.expected_electrons==0);
    cfg.qe=[0 0 0]; m.prnu=realmax;
    result = alev4.simulateStructuredExposure(realmax,cfg,1,9,m,g);
    assert(result.baseline_expected_electrons==0 && result.readout.expected_incident_photons==realmax);
    grid = unitGrid();
    spatial = alev4.simulateStructuredSpatialExposure(realmax,grid,g,cfg,0,9,m, ...
        struct('input_stage','post_optics'));
    assert(spatial.readout.expected_electrons==0 && spatial.spatial_baseline.readout.expected_electrons==0);
    metrics = struct('finite_extreme_zero_cases',6,'largest_input',realmax, ...
        'zero_qe_prnu_fill_exposure_and_support_distinguished',true);
end

function metrics = normalBoundary()
    [cfg,g,m] = fixture();
    result = alev4.simulateStructuredExposure(realmin,cfg,1,10,m,g);
    assert(result.readout.read_electrons==realmin && result.readout.raw_dn==0);
    assert(realmin-(realmin-eps(0))==eps(0));
    reject(@()alev4.simulateStructuredExposure(realmin-eps(0),cfg,1,10,m,g), ...
        'ALEV4:StructuredNoiseUnderflow');
    m.shared.fixed_offset_e=realmin; m.single.fixed_offset_e=-realmin;
    cancelled = alev4.simulateStructuredExposure(0,cfg,1,10,m,g);
    assert(cancelled.readout.read_electrons==0 && cancelled.readout.raw_dn==0);
    m.shared.fixed_offset_e=realmin+eps(0);
    reject(@()alev4.simulateStructuredExposure(0,cfg,1,10,m,g),'ALEV4:StructuredNoiseUnderflow');
    m.shared.fixed_offset_e=realmin; m.single.fixed_offset_e=-(realmin+eps(0));
    reject(@()alev4.simulateStructuredExposure(0,cfg,1,10,m,g),'ALEV4:StructuredNoiseUnderflow');
    % Native JSON numeric encoding can erase this boundary; retain binary64
    % diagnostics as 17-significant-digit decimal text and verify the bytes.
    metrics = struct('smallest_normal_accepted_decimal',sprintf('%.17g',realmin), ...
        'one_ulp_subnormal_rejected',true, ...
        'exact_signed_cancellation_accepted',true,'both_signed_residuals_rejected',true);
    decoded = jsondecode(jsonencode(metrics));
    assert(ischar(decoded.smallest_normal_accepted_decimal) && ...
        strcmp(decoded.smallest_normal_accepted_decimal,'2.2250738585072014e-308') && ...
        str2double(decoded.smallest_normal_accepted_decimal)==realmin, ...
        'The serialized diagnostic lost the smallest normal binary64 boundary.');
end

function metrics = spectralLimits()
    [cfg,g,m] = fixture();
    wide=cfg; wide.bin_width_nm=2;
    reject(@()alev4.simulateStructuredExposure(realmax,wide,1,11,m,g),'ALEV4:SignalOverflow');
    twice=cfg; twice.wavelength_nm=[500;502]; twice.bin_width_nm=[1;1]; twice.qe=ones(2,3);
    result=alev4.simulateStructuredExposure(reshape([realmax/2 realmax/2],1,1,2),twice,1,11,m,g);
    assert(result.baseline_expected_electrons==realmax);
    raised=realmax/2+eps(realmax/2); assert(isfinite(raised) && isinf(raised+raised));
    reject(@()alev4.simulateStructuredExposure(reshape([raised raised],1,1,2),twice,1,11,m,g), ...
        'ALEV4:SignalOverflow');
    tiny=cfg; tiny.qe=[eps(0) 1 1];
    reject(@()alev4.simulateStructuredExposure(.5,tiny,1,11,m,g),'ALEV4:StructuredNoiseUnderflow');
    tiny.qe=[realmin 1 1];
    reject(@()alev4.simulateStructuredExposure(.5,tiny,1,11,m,g),'ALEV4:StructuredNoiseUnderflow');
    tiny=cfg; tiny.fill_factor=.5;
    reject(@()alev4.simulateStructuredExposure(eps(0),tiny,1,11,m,g),'ALEV4:StructuredNoiseUnderflow');
    smallg=g; smallg.pixel_pitch_m=.5; small=alev4.bindSensorGeometry(cfg,smallg,'derive');
    reject(@()alev4.simulateStructuredExposure(1,small,eps(0),11,m,smallg),'ALEV4:CollectionUnderflow');
    largeg=g; largeg.pixel_pitch_m=2; large=alev4.bindSensorGeometry(cfg,largeg,'derive');
    reject(@()alev4.simulateStructuredExposure(1,large,realmax,11,m,largeg),'ALEV4:SignalOverflow');
    malformed=twice; malformed.qe=ones(1,3);
    reject(@()alev4.simulateStructuredExposure(0,malformed,0,11,m,g),'ALEV4:InvalidSensorConfig');
    metrics=struct('rejected_spectral_and_collection_cases',8, ...
        'finite_two_band_sum',realmax,'positive_support_erasure_detected',true);
end

function metrics = chargeLimits()
    [cfg,g,m] = fixture(); cfg.full_well_e=realmax;
    m.dark_current_e_per_s=realmax/2;
    result=alev4.simulateStructuredExposure(realmax/2,cfg,1,12,m,g);
    assert(result.readout.expected_electrons==realmax && result.readout.charge_electrons==realmax);
    assert(result.readout.full_well_saturated && result.readout.adc_high_clipped);
    m.dark_current_e_per_s=2^1023;
    reject(@()alev4.simulateStructuredExposure(2^1023,cfg,1,12,m,g),'ALEV4:StructuredNoiseOverflow');
    m.dark_current_e_per_s=0; m.prnu=realmax;
    result=alev4.simulateStructuredExposure(1,cfg,1,12,m,g);
    assert(result.readout.expected_photoelectrons==realmax);
    reject(@()alev4.simulateStructuredExposure(1+eps(1),cfg,1,12,m,g),'ALEV4:StructuredNoiseOverflow');
    m.prnu=1; m.dark_current_e_per_s=realmax;
    result=alev4.simulateStructuredExposure(0,cfg,1,12,m,g);
    assert(result.readout.expected_dark_electrons==realmax);
    reject(@()alev4.simulateStructuredExposure(0,cfg,1+eps(1),12,m,g),'ALEV4:StructuredNoiseOverflow');
    m.dark_current_e_per_s=0; m.prnu=realmin;
    result=alev4.simulateStructuredExposure(1,cfg,1,12,m,g);
    assert(result.readout.expected_photoelectrons==realmin);
    reject(@()alev4.simulateStructuredExposure(1-eps(1),cfg,1,12,m,g),'ALEV4:StructuredNoiseUnderflow');
    m.prnu=1; m.dark_current_e_per_s=realmin;
    result=alev4.simulateStructuredExposure(0,cfg,1,12,m,g);
    assert(result.readout.expected_dark_electrons==realmin);
    reject(@()alev4.simulateStructuredExposure(0,cfg,1-eps(1),12,m,g),'ALEV4:StructuredNoiseUnderflow');
    metrics=struct('accepted_finite_extreme_arithmetic_cases',5, ...
        'adjacent_rejected_products_or_sums',5,'finite_total_charge',realmax);
end

function metrics = poissonLimits()
    [cfg,g,m] = fixture(); cfg.shot_noise=true; m.dark_shot_noise=true;
    m.dark_current_e_per_s=1e9;
    result=alev4.simulateStructuredExposure(1e9,cfg,1,13,m,g);
    assert(result.readout.expected_electrons==2e9);
    assert(isfinite(result.components.photo_electrons) && result.components.photo_electrons>=0);
    assert(isfinite(result.components.dark_electrons) && result.components.dark_electrons>=0);
    assert(result.components.photo_electrons==fix(result.components.photo_electrons));
    assert(result.components.dark_electrons==fix(result.components.dark_electrons));
    above=1e9+eps(1e9); assert(above>1e9);
    reject(@()alev4.simulateStructuredExposure(above,cfg,1,13,m,g),'ALEV4:InvalidPoissonMean');
    m.dark_current_e_per_s=above;
    withFault('alev4.samplePoisson',@()preflightPoisson(cfg,g,m));
    % Native JSON numeric decoding can round this adjacent value to the limit.
    metrics=struct('accepted_component_mean',1e9,'accepted_total_mean',2e9, ...
        'first_representable_mean_above_limit_decimal',sprintf('%.17g',above), ...
        'dark_checked_before_photo_sampler',true);
    decoded = jsondecode(jsonencode(metrics));
    assert(ischar(decoded.first_representable_mean_above_limit_decimal) && ...
        strcmp(decoded.first_representable_mean_above_limit_decimal,'1000000000.0000001') && ...
        str2double(decoded.first_representable_mean_above_limit_decimal)==above, ...
        'The serialized diagnostic lost the adjacent Poisson boundary.');
end

function preflightPoisson(cfg,g,m)
    reject(@()alev4.samplePoisson(1),'ALEV4Test:FaultReached');
    reject(@()alev4.simulateStructuredExposure(3,cfg,1,13,m,g),'ALEV4:InvalidPoissonMean');
end

function metrics = electronicLimits()
    [cfg,g,m] = fixture();
    for magnitude={-realmin,Inf,NaN}
        bad=m; bad.shared.row_noise_e=magnitude{1};
        reject(@()alev4.simulateStructuredExposure(0,cfg,1,14,bad,g),'ALEV4:InvalidStructuredNoise');
    end
    bad=m; bad.shared.row_noise_e=realmin/2;
    reject(@()alev4.simulateStructuredExposure(0,cfg,1,14,bad,g),'ALEV4:StructuredNoiseUnderflow');
    tiny=cfg; tiny.gain_dn_per_e=realmin;
    result=alev4.simulateStructuredExposure(1,tiny,1,14,m,g);
    assert(result.readout.read_electrons==1 && result.readout.raw_dn==0);
    reject(@()alev4.simulateStructuredExposure(.5,tiny,1,14,m,g),'ALEV4:StructuredNoiseUnderflow');
    huge=cfg; huge.gain_dn_per_e=realmax;
    result=alev4.simulateStructuredExposure(1,huge,1,14,m,g);
    assert(result.readout.raw_dn==65535 && result.readout.adc_high_clipped);
    reject(@()alev4.simulateStructuredExposure(2,huge,1,14,m,g),'ALEV4:StructuredNoiseOverflow');
    [seed,z]=gaussianSeed(.25,.75);
    bad=m; bad.shared.row_noise_e=realmin;
    assert(abs(z)*realmin>0 && abs(z)*realmin<realmin);
    reject(@()alev4.simulateStructuredExposure(0,cfg,1,seed,bad,g),'ALEV4:StructuredNoiseUnderflow');
    metrics=struct('invalid_rms_cases',4,'gain_boundary_pairs',2, ...
        'gaussian_underflow_seed',seed,'independently_observed_normal_draw',z);
end

function metrics = lateFailure()
    [cfg,g,m] = fixture(); cfg.shot_noise=true; cfg.read_noise_e=1;
    m.dark_shot_noise=true; m.dark_current_e_per_s=2;
    m.shared.row_noise_e=1; m.shared.fixed_offset_e=realmax;
    control=alev4.simulateStructuredExposure(3,cfg,1,19,m,g);
    assert(control.components.shared.row_e~=0 && control.components.single.pixel_e~=0);
    saved={cfg,g,m}; before=rng;
    bad=m; bad.single.fixed_offset_e=realmax; saved_bad=bad;
    reject(@()alev4.simulateStructuredExposure(3,cfg,1,19,bad,g),'ALEV4:StructuredNoiseOverflow');
    assert(isequal(bad,saved_bad));
    [seed,z]=gaussianSeed(1.25,4);
    bad=m; bad.shared.fixed_offset_e=0; bad.shared.row_noise_e=realmax;
    assert(isinf(abs(z)*realmax));
    reject(@()alev4.simulateStructuredExposure(3,cfg,1,seed,bad,g),'ALEV4:StructuredNoiseOverflow');
    assert(isequal(before,rng) && isequal(saved,{cfg,g,m}));
    metrics=struct('late_failures_after_charge_and_gaussian_draws',2, ...
        'gaussian_overflow_seed',seed,'independent_draw',z,'caller_values_preserved',true);
end

function metrics = constructorBudget()
    m=alev4.createStructuredNoise([20000000 1]);
    empty=sparse([],[],[],20000000,1); inventory=whos('empty');
    assert(inventory.bytes<1e6 && numel(empty)==20000000 && nnz(empty)==0);
    m.prnu=empty; m.dark_current_e_per_s=empty;
    for name={'shared','single','high_gain','low_gain'}, m.(name{1}).fixed_offset_e=empty; end
    withFault('full',@()rejectConstructor(m));
    metrics=struct('represented_map_values',120000000,'sparse_fixture_bytes',inventory.bytes, ...
        'enabled_and_disabled_aggregate_rejections',2,'dense_conversion_sentinel_verified',true, ...
        'numeric_scan_sentinel_verified',true);
end

function rejectConstructor(m)
    probe=sparse([],[],[],200000,1);
    reject(@()full(probe),'ALEV4Test:DenseAllocationReached');
    reject(@()alev4.createStructuredNoise([20000000 1],m),'ALEV4:StructuredNoiseSize');
    m.enabled=false;
    reject(@()alev4.createStructuredNoise([20000000 1],m),'ALEV4:StructuredNoiseSize');
end

function metrics = coreBudget()
    [cfg,unused,m]=fixture(); %#ok<ASGLU>
    g=alev4.createSensorGeometry(struct('full_grid_size',[40000000 1], ...
        'active_roi',[1 1 1000000 1],'pixel_pitch_m',1));
    cfg=alev4.bindSensorGeometry(cfg,g,'derive');
    m.full_grid_size=[40000000 1]; m.prnu=sparse([],[],[],40000000,1);
    withFault('full',@()reject(@()alev4.simulateStructuredExposure(0,cfg,0,21,m,g), ...
        'ALEV4:StructuredNoiseSize'));
    [small,unused,neutral]=fixture(); %#ok<ASGLU>
    target=alev4.createSensorGeometry(struct('full_grid_size',[2000000 1],'pixel_pitch_m',1));
    small=alev4.bindSensorGeometry(small,target,'derive'); neutral.full_grid_size=[2000000 1];
    withFault('alev4.structuredNoiseMaps',@()reject(@() ...
        alev4.simulateStructuredExposure(0,small,0,21,neutral,target),'ALEV4:StructuredNoiseSize'));

    % Independently frozen singleton count: C=25, G=9, M=N+22 and the
    % remaining retained result has 86 values, so its total is N+142.
    % With N=2 this is safe to construct and inventory exactly. At the large
    % descriptor below, the old raw reservation was exactly 1e8 although
    % the complete result would have retained 1e8+11 values.
    dual=alev4.createDualGainSensor(struct('sensor',struct('image_size',[1 1], ...
        'wavelength_nm',500,'bin_width_nm',1,'qe',[1 1 1], ...
        'pixel_pitch_m',1,'fill_factor',1,'shot_noise',false), ...
        'high_gain',struct('read_noise_e',0),'low_gain',struct('read_noise_e',0)));
    unit=alev4.createSensorGeometry(struct('full_grid_size',[2 1], ...
        'active_roi',[1 1 1 1],'pixel_pitch_m',1));
    tiny=alev4.simulateStructuredExposure(0,dual,0,21,struct('prnu',zeros(2,1)),unit);
    assert(alev4.structuredNumericSamples(dual)==25 && ...
        alev4.structuredNumericSamples(unit)==9 && ...
        alev4.structuredNumericSamples(tiny.noise_model)==24 && ...
        alev4.structuredNumericSamples(tiny)==144);
    alev4.structuredValidateResult(tiny);
    map_count=99999869;
    assert(map_count+25+9+32+65==1e8 && map_count+142==1e8+11);
    unit.full_grid_size=[map_count 1];
    partial=struct('prnu',sparse([],[],[],map_count,1));
    withFault('full',@()reject(@()alev4.simulateStructuredExposure( ...
        0,dual,0,21,partial,unit),'ALEV4:StructuredNoiseSize'));
    metrics=struct('raw_full_map_values',40000000,'active_pixels_with_map',1000000, ...
        'scalar_map_target_pixels',2000000,'expansion_rejections',3, ...
        'singleton_dual_tiny_retained_values',144, ...
        'singleton_dual_sparse_map_values',map_count, ...
        'singleton_dual_former_retained_overrun',11,'compact_metadata_reservation',64);
end

function metrics = spatialBudget()
    [cfg,unused,m]=fixture(); %#ok<ASGLU>
    g=alev4.createSensorGeometry(struct('full_grid_size',[1000000 1],'pixel_pitch_m',1));
    cfg=alev4.bindSensorGeometry(cfg,g,'derive'); m.full_grid_size=[1000000 1];
    withFault('alev4.simulateSpatialExposure',@()rejectSpatialBaseline(cfg,g,m));
    metrics=struct('target_pixels',1000000,'legacy_baseline_sentinel_verified',true, ...
        'zero_exposure_still_obeys_storage_limit',true);
end

function rejectSpatialBaseline(cfg,g,m)
    reject(@()alev4.simulateSpatialExposure(),'ALEV4Test:FaultReached');
    reject(@()alev4.simulateStructuredSpatialExposure(0,unitGrid(),g,cfg,0,22,m), ...
        'ALEV4:StructuredNoiseSize');
end

function metrics = spatialStorage()
    [cfg,g,m]=fixture();
    options=struct('spatial_provenance',struct('retained',sparse([],[],[],1e8,1)));
    withFault('alev4.simulateSpatialExposure',@()reject(@() ...
        alev4.simulateStructuredSpatialExposure(0,unitGrid(),g,cfg,0,23,m,options), ...
        'ALEV4:StructuredNoiseSize'));
    source=sparse([],[],[],5001,5001); source_grid=alev4.createSpatialGrid( ...
        struct('x_edges_m',0:5001,'y_edges_m',0:5001));
    withFault('full',@()reject(@()alev4.simulateStructuredSpatialExposure( ...
        source,source_grid,g,cfg,0,23,m,struct('input_stage','post_optics')), ...
        'ALEV4:StructuredNoiseSize'));
    bands=200; large=cfg; large.wavelength_nm=(500:2:898).';
    large.bin_width_nm=ones(bands,1); large.qe=ones(bands,3);
    large=alev4.createBaselineSensor(large);
    target=alev4.createSensorGeometry(struct('full_grid_size',[300000 1],'pixel_pitch_m',1));
    large=alev4.bindSensorGeometry(large,target,'derive'); m.full_grid_size=[300000 1];
    withFault('alev4.simulateSpatialExposure',@()reject(@() ...
        alev4.simulateStructuredSpatialExposure(0,unitGrid(),target,large,0,23,m), ...
        'ALEV4:StructuredNoiseSize'));
    metrics=struct('retained_provenance_values',1e8,'sparse_source_shape',[5001 5001], ...
        'validated_spectral_bin_count',bands,'source_input_planes_in_spectral_probe',1, ...
        'distinct_storage_rejections',3);
end

function metrics = spatialIdentity()
    [cfg,g,m]=fixture([2 3]); cfg.shot_noise=true; cfg.read_noise_e=.5;
    input=[3 4 5;6 7 8]; grid=alev4.createSpatialGrid(struct('x_edges_m',0:3,'y_edges_m',0:2));
    options=struct('input_stage','post_optics','spatial_provenance', ...
        struct('measurements',[1 2 3],'nested',{{struct('values',[4;5])}}));
    result=alev4.simulateStructuredSpatialExposure(input,grid,g,cfg,1,24,m,options);
    legacy=alev4.simulateSpatialExposure(input,grid,g,cfg,1,24,options);
    assert(isequal(result.spatial_baseline,legacy));
    direct=alev4.simulateStructuredExposure(input,cfg,1,24,m,g);
    assert(isequal(result.readout,direct.readout) && isequal(result.components,direct.components));
    m.enabled=false;
    disabled=alev4.simulateStructuredSpatialExposure(input,grid,g,cfg,1,24,m,options);
    assert(isequal(disabled,legacy));
    derive=options; derive.binding_mode='derive'; unbound=alev4.createBaselineSensor();
    canonical=alev4.bindSensorGeometry(unbound,g,'derive');
    cube=repmat(input,1,1,numel(unbound.wavelength_nm)); m.enabled=true;
    derived=alev4.simulateStructuredSpatialExposure(cube,grid,g,unbound,0,24,m,derive);
    assert(isequal(derived.configuration,canonical));
    metrics=struct('retained_baseline_exact',true,'direct_core_exact',true, ...
        'disabled_legacy_exact',true,'explicit_derive_binding_preserved',true);
end

function metrics = sequenceBounds()
    [cfg,unused,m]=fixture(); %#ok<ASGLU>
    g=alev4.createSensorGeometry(struct('full_grid_size',[40000000 1], ...
        'active_roi',[1 1 1 1],'pixel_pitch_m',1));
    m.full_grid_size=[40000000 1]; m.prnu=sparse([],[],[],40000000,1);
    withFault('full',@()rejectSequenceDescriptors(cfg,g,m));
    [cfg,g,m]=fixture(); cfg.read_noise_e=1; m.dark_current_e_per_s=realmax/4;
    first=alev4.simulateNoiseSequence(0,cfg,1,25,m,g);
    assert(first.frames{1}.components.single.pixel_e~=0 && first.frames{1}.readout.full_well_saturated);
    saved={cfg,g,m};
    reject(@()alev4.simulateNoiseSequence(0,cfg,[1 8],25,m,g),'ALEV4:StructuredNoiseOverflow');
    assert(isequal(saved,{cfg,g,m}));
    metrics=struct('envelope_plus_frame_model_values',120000000, ...
        'oversized_sparse_exposure_and_index_checks',4,'later_frame_overflow_restored_rng',true);
end

function rejectSequenceDescriptors(cfg,g,m)
    reject(@()alev4.simulateNoiseSequence(0,cfg,[0 0],25,m,g),'ALEV4:NoiseSequenceSize');
    [small,unit,neutral]=fixture();
    exposed=sparse([],[],[],67108864,1);
    reject(@()alev4.simulateNoiseSequence(0,small,exposed,25,neutral,unit),'ALEV4:NoiseSequenceSize');
    too_many=sparse([],[],[],67108865,1);
    reject(@()alev4.simulateNoiseSequence(0,small,too_many,25,neutral,unit), ...
        'ALEV4:InvalidNoiseSequenceIndices');
    reject(@()alev4.simulateNoiseSequence(0,small,0,25,neutral,unit, ...
        struct('frame_indices',exposed)),'ALEV4:InvalidNoiseSequenceIndices');
    reject(@()alev4.simulateNoiseSequence(0,small,0,25,neutral,unit, ...
        struct('ei_label',exposed)),'ALEV4:InvalidNoiseSequenceEi');
end

function [cfg,g,m]=fixture(dimensions)
    if nargin<1, dimensions=[1 1]; end
    g=alev4.createSensorGeometry(struct('full_grid_size',dimensions,'pixel_pitch_m',1));
    cfg=alev4.createBaselineSensor(struct('image_size',dimensions, ...
        'wavelength_nm',500,'bin_width_nm',1,'qe',[1 1 1], ...
        'pixel_pitch_m',1,'fill_factor',1,'shot_noise',false,'full_well_e',1024, ...
        'read_noise_e',0,'gain_dn_per_e',1,'black_level_dn',0,'adc_bits',16));
    m=alev4.createStructuredNoise(dimensions,struct('dark_shot_noise',false));
end

function grid=unitGrid()
    grid=alev4.createSpatialGrid(struct('x_edges_m',[0 1],'y_edges_m',[0 1]));
end

function [seed,value]=gaussianSeed(lower,upper)
    previous=rng; cleanup=onCleanup(@()rng(previous)); %#ok<NASGU>
    for seed=0:127
        rng(mod(seed+10,4294967296),'twister'); value=randn();
        if abs(value)>lower && abs(value)<upper, return; end
    end
    error('ALEV4Test:MissingDeterministicProbe','No bounded deterministic Gaussian probe was found.');
end

function withFault(name,action)
    root=tempname(); mkdir(root); old_path=path; old_warning=warning;
    cleanup=onCleanup(@()removeFault(root,old_path,old_warning,name)); %#ok<NASGU>
    if strcmp(name,'full')
        destination=fullfile(root,'full.m');
        code=sprintf(['function value=full(input)\n' ...
            'if issparse(input) && numel(input)>100000\n' ...
            'error(''ALEV4Test:DenseAllocationReached'',''Large sparse conversion reached.'');\nend\n' ...
            'value=builtin(''full'',input);\nend\n']);
    else
        mkdir(fullfile(root,'+alev4')); leaf=name(7:end);
        destination=fullfile(root,'+alev4',[leaf '.m']);
        code=sprintf('function varargout=%s(varargin)\nerror(''ALEV4Test:FaultReached'',''Fault sentinel reached.'');\nend\n',leaf);
    end
    fid=fopen(destination,'wb'); assert(fid>=0); fwrite(fid,code,'char'); assert(fclose(fid)==0);
    if strcmp(name,'full')
        % isfinite(sparse_zero) represents true at every element and can
        % allocate proportional storage before a later full() is reached.
        destination=fullfile(root,'isfinite.m');
        code=sprintf(['function value=isfinite(input)\n' ...
            'if issparse(input) && numel(input)>100000\n' ...
            'error(''ALEV4Test:DenseAllocationReached'',''Large sparse numeric scan reached.'');\nend\n' ...
            'value=builtin(''isfinite'',input);\nend\n']);
        fid=fopen(destination,'wb'); assert(fid>=0); fwrite(fid,code,'char'); assert(fclose(fid)==0);
    end
    warning('off','Octave:shadowed-function'); warning('off','MATLAB:dispatcher:nameConflict');
    addpath(root,'-begin'); rehash; clear(name);
    if strcmp(name,'full'), clear('isfinite'); end
    % Prove the safety interlock is active before invoking any huge-shape
    % request. A path-resolution regression must fail without allocating.
    if strcmp(name,'full')
        reject(@()full(sparse([],[],[],200000,1)),'ALEV4Test:DenseAllocationReached');
        reject(@()isfinite(sparse([],[],[],200000,1)),'ALEV4Test:DenseAllocationReached');
    else
        reject(@()feval(name),'ALEV4Test:FaultReached');
    end
    action();
end

function removeFault(root,old_path,old_warning,name)
    path(old_path); clear(name); rehash; warning(old_warning);
    if strcmp(name,'full'), clear('isfinite'); end
    if isfolder(root), rmdir(root,'s'); end
end

function reject(action,identifier)
    before=rng; caught=false;
    try, action(); catch err
        caught=true;
        assert(strcmp(err.identifier,identifier),'Expected %s, received %s: %s', ...
            identifier,err.identifier,err.message);
    end
    assert(caught,'Expected rejection %s.',identifier);
    assert(isequal(before,rng),'Rejected numerical boundary call changed caller RNG.');
end
