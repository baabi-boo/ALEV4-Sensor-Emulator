function report = test_phase4_sequence()
%TEST_PHASE4_SEQUENCE Absolute-frame identity and strict temporal integration.
%   This suite uses small deterministic and independently seeded examples.
%   The separate noise suite owns long-sequence moment/covariance acceptance.
    caller_rng = rng;
    guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    rng(724601,'twister'); rand(1,5); randn(1,7);
    [input,single,dual,model,geometry] = fixture();
    saved = {input,single,dual,model,geometry};
    names = {'exact_reset_start_absolute_and_gapped_continuation', ...
        'frame_seed_wrap_maximum_index_and_17_component_disjointness', ...
        'independent_frame_draws_and_fixed_map_persistence', ...
        'fixed_pattern_cancellation_from_signed_frame_differences', ...
        'ei_labels_leave_every_frame_unchanged', ...
        'exposure_vector_scales_photo_dark_not_fixed_offsets', ...
        'accepted_numeric_representations_are_canonical', ...
        'strict_sequence_options_and_absolute_index_rejection', ...
        'strict_exposure_and_ei_label_rejection', ...
        'caller_configuration_and_rng_survive_success_and_second_frame_failure', ...
        'retained_sequence_resource_bounds', ...
        'disabled_single_dual_frames_match_complete_legacy_results'};
    metrics = struct();
    metrics.continuation = continuation(input,single,dual,model,geometry);
    metrics.schedule = seedSchedule(input,single,model,geometry);
    metrics.independent_frames = persistentFrames(input,dual,model,geometry);
    metrics.cancellation = cancellation(input,single,dual,model,geometry);
    metrics.ei = eiInvariance(input,dual,model,geometry);
    metrics.scaling = exposureScaling(input,single,model,geometry);
    metrics.representations = representations(input,single,model,geometry);
    metrics.options_and_indices = invalidOptions(input,single,model,geometry);
    metrics.exposures_and_ei = invalidVectors(input,single,model,geometry);
    metrics.cleanup = callerCleanup(input,single,dual,model,geometry);
    metrics.resource_bounds = resourceBounds(input,single,model,geometry);
    metrics.disabled = disabledIdentity(input,single,dual,model,geometry);
    assert(isequal(saved,{input,single,dual,model,geometry}));
    metrics.runtime_version = version();
    metrics.reproducibility_scope = 'same_runtime_and_version_only';
    tests = repmat(struct('name','','status','passed','passed',true),1,numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    report = struct('suite','phase4_sequence','status','passed','passed',true, ...
        'test_count',numel(names),'tests',tests,'metrics',metrics);
    fprintf('PASS: Phase 4 sequence integration, %d test groups.\n',numel(names));
end

function metrics = continuation(input,single,dual,model,geometry)
    times = [0 .25 1 2]; seed = 4294967200;
    configurations = {single,dual}; comparisons = 0;
    for mode = 1:2
        cfg = configurations{mode};
        primary = alev4.simulateNoiseSequence(input,cfg,times,seed,model,geometry);
        reset = alev4.simulateNoiseSequence(input,cfg,times,seed,model,geometry);
        explicit = alev4.simulateNoiseSequence(input,cfg,times,seed,model,geometry, ...
            struct('frame_indices',1:4));
        started = alev4.simulateNoiseSequence(input,cfg,times,seed,model,geometry, ...
            struct('start_frame',1));
        assert(isequal(primary,reset) && isequal(primary,explicit) && isequal(primary,started));
        tail = alev4.simulateNoiseSequence(input,cfg,times(3:4),seed,model,geometry, ...
            struct('start_frame',3));
        gaps = alev4.simulateNoiseSequence(input,cfg,times([1 3 4]),seed,model,geometry, ...
            struct('frame_indices',[1 3 4]));
        assert(isequal(tail.frames,primary.frames(3:4)));
        assert(isequal(gaps.frames,primary.frames([1 3 4])));
        assert(isequal(primary.frame_indices,1:4) && isequal(tail.frame_indices,[3 4]));
        for k = 1:4
            direct = alev4.simulateStructuredExposure(input,cfg,times(k), ...
                mod(seed+64*(k-1),2^32),model,geometry);
            assert(isequal(primary.frames{k},direct)); comparisons = comparisons+1;
        end
        assert(strcmp(primary.result_kind,'independent_frame_sequence'));
        assert(strcmp(primary.temporal_policy,'independent_frames'));
        assert(strcmp(primary.continuation_policy,'pure_function_of_arguments_and_absolute_frame_indices'));
        assert(primary.synthetic && ~primary.calibrated_alev4 && primary.structured_noise_enabled);
    end
    metrics = struct('readout_modes',2,'whole_sequence_reset_checks',6, ...
        'direct_frame_identity_checks',comparisons,'gapped_absolute_indices',[1 3 4]);
end

function metrics = seedSchedule(input,cfg,model,geometry)
    component_names = {'photo','dark','shared_row','shared_column','shared_frame', ...
        'single_row','single_column','single_frame','single_pixel', ...
        'high_row','high_column','high_frame','high_pixel', ...
        'low_row','low_column','low_frame','low_pixel'};
    tags = [1 2 10 11 12 20 21 22 23 30 31 32 33 40 41 42 43];
    indices = [1 2 3 31 32 65536 33554432 67108863 67108864];
    identities = [0 4294967200 4294967295]; checked = 0;
    % Algebraic coverage of every supported absolute index: different
    % component residues modulo 64 cannot collide. Equal tags require an
    % index difference divisible by 2^26; its absolute value is at most
    % 2^26-1. No enumeration/allocation of 2^26 frames is necessary.
    assert(2^32 == 64*67108864 && max(tags)-min(tags)<64);
    assert(numel(unique(mod(tags,64)))==17);
    assert(67108864-1 < 2^32/64);
    for seed = identities
        result = alev4.simulateNoiseSequence(input,cfg,ones(size(indices)),seed,model,geometry, ...
            struct('frame_indices',indices));
        expected = mod(seed+64*(indices-1),4294967296);
        assert(isequal(result.frame_seeds,expected));
        all_seeds = zeros(17,numel(indices));
        for k = 1:numel(indices)
            assert(result.frames{k}.readout.seed==expected(k));
            for j = 1:17
                oracle = mod(expected(k)+tags(j),4294967296);
                all_seeds(j,k) = result.frames{k}.seeds.(component_names{j});
                assert(all_seeds(j,k)==oracle); checked=checked+1;
            end
        end
        assert(numel(unique(all_seeds(:)))==numel(all_seeds));
    end
    last = alev4.simulateNoiseSequence(input,cfg,1,uint32(4294967295),model,geometry, ...
        struct('start_frame',uint64(67108864)));
    assert(isequal(last.frame_indices,67108864) && isequal(last.frame_seeds,4294967231));
    metrics = struct('component_names',{component_names},'component_tags',tags, ...
        'sampled_absolute_indices',indices,'sequence_seed_identities',identities, ...
        'component_schedule_checks',checked,'maximum_supported_frame_index',67108864, ...
        'all_supported_frames_disjoint_by_residue_and_period',true);
end

function metrics = persistentFrames(input,cfg,model,geometry)
    sequence = alev4.simulateNoiseSequence(input,cfg,ones(1,4),3191,model,geometry);
    varying = 0;
    for k = 2:4
        a = sequence.frames{1}; b = sequence.frames{k};
        assert(isequal(a.active_maps,b.active_maps) && isequal(a.noise_model,b.noise_model));
        assert(isequal(a.readout.expected_electrons,b.readout.expected_electrons));
        assert(~isequal(a.components.photo_electrons,b.components.photo_electrons));
        assert(~isequal(a.components.dark_electrons,b.components.dark_electrons));
        for path = {'shared','high_gain','low_gain'}
            name = path{1};
            assert(isequal(a.components.(name).fixed_offset_e,b.components.(name).fixed_offset_e));
            assert(~isequal(a.components.(name).row_e,b.components.(name).row_e));
            assert(~isequal(a.components.(name).column_e,b.components.(name).column_e));
            assert(a.components.(name).frame_e~=b.components.(name).frame_e);
            varying = varying+3;
        end
        assert(~isequal(a.components.high_gain.pixel_e,b.components.high_gain.pixel_e));
        assert(~isequal(a.components.low_gain.pixel_e,b.components.low_gain.pixel_e));
    end
    metrics = struct('frames',4,'varying_electronic_component_comparisons',varying, ...
        'fixed_model_and_crops_exact',true,'statistical_law_owned_by','phase4_noise');
end

function metrics = cancellation(input,single,dual,model,geometry)
    single.shot_noise=false; dual.sensor.shot_noise=false; model.dark_shot_noise=false;
    configurations = {single,dual}; maximum_error = 0; fixed_gap = 0;
    for mode = 1:2
        cfg = configurations{mode};
        sequence = alev4.simulateNoiseSequence(input,cfg,[.5 .5],7123,model,geometry);
        a=sequence.frames{1}; b=sequence.frames{2};
        assert(isequal(a.components.photo_electrons,b.components.photo_electrons));
        assert(isequal(a.components.dark_electrons,b.components.dark_electrons));
        assert(isequal(a.readout.charge_electrons,b.readout.charge_electrons));
        paths = {'single'}; if mode==2, paths={'high_gain','low_gain'}; end
        for j=1:numel(paths)
            name=paths{j};
            expected=(temporal(b.components.shared)-temporal(a.components.shared))+ ...
                (temporal(b.components.(name))-temporal(a.components.(name)));
            if mode==1, actual=b.readout.read_electrons-a.readout.read_electrons;
            else, actual=b.readout.(name).read_electrons-a.readout.(name).read_electrons; end
            maximum_error=max(maximum_error,max(abs(actual(:)-expected(:))));
            near(actual,expected,128);
            residual_fixed=a.components.shared.fixed_offset_e+a.components.(name).fixed_offset_e;
            wrong=expected+residual_fixed;
            fixed_gap=max(fixed_gap,max(abs(actual(:)-wrong(:))));
            assert(max(abs(actual(:)-wrong(:)))>1, ...
                'A frame-difference oracle must reject retained fixed-pattern offsets.');
        end
    end
    metrics=struct('readout_paths_checked',3,'maximum_difference_error_e',maximum_error, ...
        'wrong_retained_fixed_pattern_gap_e',fixed_gap,'comparison','signed_unquantized_readouts');
end

function value = temporal(component)
    value=bsxfun(@plus,component.row_e,component.column_e);
    value=bsxfun(@plus,value,component.frame_e)+component.pixel_e;
end

function metrics = eiInvariance(input,cfg,model,geometry)
    options=struct('frame_indices',[2 7 29]); times=[.25 .5 1];
    absent=alev4.simulateNoiseSequence(input,cfg,times,8199,model,geometry,options);
    options.ei_label=800;
    scalar=alev4.simulateNoiseSequence(input,cfg,times,8199,model,geometry,options);
    options.ei_label=[100;1600;12800];
    vector=alev4.simulateNoiseSequence(input,cfg,times,8199,model,geometry,options);
    options.ei_label=[];
    empty=alev4.simulateNoiseSequence(input,cfg,times,8199,model,geometry,options);
    assert(isequal(absent,empty));
    assert(isequal(absent.frames,scalar.frames) && isequal(absent.frames,vector.frames));
    assert(isequal(scalar.ei_label,[800 800 800]) && isequal(vector.ei_label,[100 1600 12800]));
    scalar.ei_label=[]; vector.ei_label=[];
    assert(isequal(absent,scalar) && isequal(absent,vector));
    assert(strcmp(absent.ei_policy,'metadata_only_no_exposure_or_gain_mapping'));
    metrics=struct('label_selections',4,'whole_frame_identity_checks',9, ...
        'only_envelope_ei_label_changes',true);
end

function metrics = exposureScaling(input,cfg,model,geometry)
    cfg.shot_noise=false; cfg.read_noise_e=0; cfg.full_well_e=1e6;
    model=quietModel(model); times=[0 .25 .5 2];
    result=alev4.simulateNoiseSequence(input,cfg,times,1301,model,geometry);
    % Fixture p=.5, fill=.5 and width=2 give 1/4 before CFA QE.
    qe=[1 .5 .25]; tile=[1 2;2 3];
    rate=zeros(size(input));
    for r=1:size(input,1)
        for c=1:size(input,2)
            rate(r,c)=input(r,c)*.25*qe(tile(mod(r-1,2)+1,mod(c-1,2)+1));
        end
    end
    for k=1:4
        frame=result.frames{k};
        photo=model.prnu.*rate*times(k); dark=model.dark_current_e_per_s*times(k);
        assert(isequal(frame.baseline_expected_electrons,rate*times(k)));
        assert(isequal(frame.readout.expected_photoelectrons,photo));
        assert(isequal(frame.readout.expected_dark_electrons,dark));
        assert(isequal(frame.readout.collected_electrons,photo+dark));
        expected=(photo+dark+model.shared.fixed_offset_e)+model.single.fixed_offset_e;
        assert(isequal(frame.readout.read_electrons,expected));
        assert(isequal(frame.components.single.fixed_offset_e,model.single.fixed_offset_e));
    end
    assert(all(result.frames{1}.readout.collected_electrons(:)==0));
    one=alev4.simulateNoiseSequence(input,cfg,.5,1301,model,geometry);
    assert(one.frame_count==1 && isequal(size(one.frames),[1 1]));
    metrics=struct('exposures_s',times,'scalar_requests_one_frame',true, ...
        'independent_expectation_tolerance',0,'fixed_offsets_independent_of_exposure',true);
end

function metrics = representations(input,cfg,model,geometry)
    candidates={ ...
        {single([0 .5 1]),uint32(4294967295),uint32([1 2 3]),uint16([200 800 3200])}, ...
        {uint16([0 1 2]),uint64(4294967295),uint64([1 31 67108864]),single(800)}, ...
        {int64([0 1 2]),int64(63),int64([3 9 17]),int64([100 200 400])}, ...
        {sparse([0 .5 1]),sparse(64),sparse([2 5 8]),sparse([200 400 800])}, ...
        {[0;.5;1],single(32),single([4;8;16]),[200;400;800]}};
    for k=1:numel(candidates)
        c=candidates{k};
        actual=alev4.simulateNoiseSequence(input,cfg,c{1},c{2},model,geometry, ...
            struct('frame_indices',c{3},'ei_label',c{4}));
        expected=alev4.simulateNoiseSequence(input,cfg,full(double(c{1})), ...
            full(double(c{2})),model,geometry,struct( ...
            'frame_indices',full(double(c{3})),'ei_label',full(double(c{4}))));
        assert(isequal(actual,expected));
        for name={'exposures_s','sequence_seed','frame_indices','frame_seeds','ei_label'}
            v=actual.(name{1}); assert(isa(v,'double') && ~issparse(v) && isrow(v));
        end
    end
    metrics=struct('accepted_representation_combinations',numel(candidates), ...
        'classes',{{'single','uint16','uint32','uint64','int64','sparse double','column double'}});
end

function metrics = invalidOptions(input,cfg,model,geometry)
    bad_options={[],{},struct([]),repmat(struct('ei_label',1),1,2), ...
        struct('unknown',1),struct('reset',true),struct('start_frame',1,'frame_indices',[1 2])};
    count=0;
    for k=1:numel(bad_options)
        expectError(@() alev4.simulateNoiseSequence(input,cfg,[1 1],4,model,geometry,bad_options{k}), ...
            'ALEV4:InvalidNoiseSequenceOptions'); count=count+1;
    end
    bad_indices={[],1,[1 1],[2 1],[0 2],[-1 2],[1 1.5],[1 NaN],[1 Inf], ...
        [1 67108865],uint64([1 67108865]),single([1 67108872]), ...
        true(1,2),'12',{1,2},[1 2i],ones(2,2)};
    for k=1:numel(bad_indices)
        options=struct(); options.frame_indices=bad_indices{k};
        expectError(@() alev4.simulateNoiseSequence(input,cfg,[1 1],4,model,geometry,options), ...
            'ALEV4:InvalidNoiseSequenceIndices'); count=count+1;
    end
    bad_start={0,-1,.5,NaN,Inf,67108865,uint64(67108865),single(67108872), ...
        true,'1',[],[1 2],1i,67108864};
    for k=1:numel(bad_start)
        options=struct(); options.start_frame=bad_start{k};
        expectError(@() alev4.simulateNoiseSequence(input,cfg,[1 1],4,model,geometry,options), ...
            'ALEV4:InvalidNoiseSequenceIndices'); count=count+1;
    end
    expectError(@() alev4.simulateNoiseSequence(input,cfg,1,4,model), ...
        'ALEV4:NoiseSequenceArguments'); count=count+1;
    metrics=struct('rejected_calls',count,'duplicates_reversed_gaps_and_range_distinguished',true);
end

function metrics = invalidVectors(input,cfg,model,geometry)
    bad_exposures={[],zeros(0,2),single([]),true,[true false],'12',{1,2}, ...
        [-1 1],[0 NaN],[0 Inf],[0 -Inf],[1 2i],ones(2,2),zeros(2,1,2)};
    count=0;
    for k=1:numel(bad_exposures)
        expectError(@() alev4.simulateNoiseSequence(input,cfg,bad_exposures{k},4,model,geometry), ...
            'ALEV4:InvalidNoiseSequenceExposures'); count=count+1;
    end
    bad_labels={single([]),false(0,0),zeros(0,2),true,'800',{800},0,-1,NaN,Inf, ...
        [100 0],[100 -1],[100 NaN],[100 Inf],[100 2i],[100 200 400],ones(2,2)};
    for k=1:numel(bad_labels)
        options=struct(); options.ei_label=bad_labels{k};
        expectError(@() alev4.simulateNoiseSequence(input,cfg,[1 1],4,model,geometry,options), ...
            'ALEV4:InvalidNoiseSequenceEi'); count=count+1;
    end
    bad_seeds={uint64(4294967296),single(4294967295),-1,.5,true,NaN};
    for k=1:numel(bad_seeds)
        expectError(@() alev4.simulateNoiseSequence(input,cfg,1,bad_seeds{k},model,geometry), ...
            'ALEV4:InvalidSeed'); count=count+1;
    end
    metrics=struct('rejected_calls',count,'exposure_shapes_and_classes',numel(bad_exposures), ...
        'ei_shapes_and_classes',numel(bad_labels),'seed_representation_boundaries',numel(bad_seeds));
end

function metrics = callerCleanup(input,single,dual,model,geometry)
    options=struct('frame_indices',[3;8],'ei_label',[200;1600]);
    values={input,single,dual,model,geometry,options}; before=rng;
    alev4.simulateNoiseSequence(input,single,[.5 1],77,model,geometry,options);
    alev4.simulateNoiseSequence(input,dual,[.5 1],77,model,geometry,options);
    assert(isequal(before,rng) && isequal(values,{input,single,dual,model,geometry,options}));
    late=model; late.dark_shot_noise=false; late.dark_current_e_per_s=realmax/4;
    saved_late=late;
    first=alev4.simulateNoiseSequence(input,single,1,77,late,geometry);
    assert(first.frame_count==1 && all(first.frames{1}.readout.full_well_saturated(:)));
    assert(any(first.frames{1}.components.single.pixel_e(:)~=0));
    expectError(@() alev4.simulateNoiseSequence(input,single,[1 8],77,late,geometry), ...
        'ALEV4:StructuredNoiseOverflow');
    bad=single; bad.image_size=[4 4];
    expectError(@() alev4.simulateNoiseSequence(input,bad,1,77,model,geometry), ...
        'ALEV4:GeometryBindingConflict');
    assert(isequal(before,rng) && isequal(late,saved_late));
    assert(isequal(values,{input,single,dual,model,geometry,options}));
    metrics=struct('success_modes',2,'first_frame_proved_successful',true, ...
        'second_frame_failure','ALEV4:StructuredNoiseOverflow', ...
        'rng_and_caller_values_preserved',true);
end

function metrics = resourceBounds(input,cfg,model,geometry)
    % 5001 small 100x100 frames already exceed the inexpensive input/pixel
    % lower bound. No result frames need to be allocated for this rejection.
    large_g=alev4.createSensorGeometry(struct('full_grid_size',[100 100],'pixel_pitch_m',.5));
    large_cfg=alev4.bindSensorGeometry(cfg,large_g,'derive');
    large_model=alev4.createStructuredNoise([100 100]);
    expectError(@() alev4.simulateNoiseSequence(ones(100),large_cfg,ones(1,5001), ...
        1,large_model,large_g),'ALEV4:NoiseSequenceSize');
    % The second request clears that lower bound, but complete retained
    % components, maps, metadata and configuration exceed the same 1e8 cap.
    first=alev4.simulateStructuredExposure(input,cfg,1,1,model,geometry);
    retained_per_frame=storedValues(first); count=200000;
    assert(count*(numel(input)+prod(geometry.active_roi(3:4)))<1e8);
    assert(count*retained_per_frame>1e8);
    expectError(@() alev4.simulateNoiseSequence(input,cfg,ones(1,count),1,model,geometry), ...
        'ALEV4:NoiseSequenceSize');
    metrics=struct('numerical_value_limit',1e8,'lower_bound_rejected_frames',5001, ...
        'retained_bound_rejected_frames',count,'observed_values_per_frame',retained_per_frame, ...
        'complete_retention_exceeds_limit',count*retained_per_frame);
end

function count = storedValues(value)
    if isnumeric(value) || islogical(value), count=numel(value);
    elseif isstruct(value)
        count=0; names=fieldnames(value);
        for j=1:numel(value)
            for k=1:numel(names), count=count+storedValues(value(j).(names{k})); end
        end
    elseif iscell(value)
        count=0; for k=1:numel(value), count=count+storedValues(value{k}); end
    else, count=0;
    end
end

function metrics = disabledIdentity(input,single,dual,model,geometry)
    model.enabled=false; configs={single,dual}; indices=[1 3 67108864]; times=[0 .5 2];
    for mode=1:2
        result=alev4.simulateNoiseSequence(input,configs{mode},times,4294967295,model,geometry, ...
            struct('frame_indices',indices,'ei_label',[100 800 6400]));
        assert(~result.structured_noise_enabled);
        kinds={'legacy_single_gain_exposure','legacy_dual_gain_exposure'};
        assert(strcmp(result.frame_result_kind,kinds{mode}));
        assert(strcmp(result.format,'ALEV4-SYNTHETIC-STRUCTURED-NOISE'));
        for k=1:3
            seed=mod(4294967295+64*(indices(k)-1),2^32);
            if mode==1, legacy=alev4.simulateExposure(input,single,times(k),seed);
            else, legacy=alev4.simulateDualGainExposure(input,dual,times(k),seed); end
            assert(isequal(result.frames{k},legacy));
            assert(~isfield(result.frames{k},'noise_model') && ~isfield(result.frames{k},'components'));
        end
    end
    metrics=struct('complete_legacy_frame_equalities',6,'readout_modes',2, ...
        'new_envelope_distinguishes_disabled_frames',true);
end

function [input,single,dual,model,geometry] = fixture()
    geometry=alev4.createSensorGeometry(struct('full_grid_size',[3 4],'pixel_pitch_m',.5));
    sensor=struct('image_size',[3 4],'pixel_pitch_m',.5,'wavelength_nm',550, ...
        'bin_width_nm',2,'qe',[1 .5 .25],'fill_factor',.5,'full_well_e',1000,'shot_noise',true);
    single=alev4.createBaselineSensor(sensor);
    single.read_noise_e=.75; single.gain_dn_per_e=2; single.black_level_dn=16; single.adc_bits=12;
    dual=alev4.createDualGainSensor(struct('sensor',sensor, ...
        'high_gain',struct('gain_dn_per_e',4,'read_noise_e',.5), ...
        'low_gain',struct('gain_dn_per_e',.5,'read_noise_e',1.25), ...
        'merge',struct('start_e',100,'end_e',200)));
    [r,c]=ndgrid(1:3,1:4); input=16+8*r+4*c;
    model=alev4.createStructuredNoise([3 4],struct( ...
        'realization_id','ASSUMED-P4-SEQUENCE-TEST','prnu',.5+r/4+c/8, ...
        'dark_current_e_per_s',2+r+c/2, ...
        'shared',struct('fixed_offset_e',2*r-3*c,'row_noise_e',.75,'column_noise_e',.5,'frame_noise_e',1), ...
        'single',struct('fixed_offset_e',r-c/2,'row_noise_e',.5,'column_noise_e',.75,'frame_noise_e',.25), ...
        'high_gain',struct('fixed_offset_e',r/2-c,'row_noise_e',.5,'column_noise_e',.25,'frame_noise_e',.75), ...
        'low_gain',struct('fixed_offset_e',-r+c/4,'row_noise_e',.25,'column_noise_e',1,'frame_noise_e',.5)));
end

function model = quietModel(model)
    model.dark_shot_noise=false;
    for name={'shared','single','high_gain','low_gain'}
        model.(name{1}).row_noise_e=0;
        model.(name{1}).column_noise_e=0;
        model.(name{1}).frame_noise_e=0;
    end
end

function near(actual,expected,multiplier)
    assert(isequal(size(actual),size(expected)));
    scale=max(1,max(abs(expected(:))));
    assert(max(abs(actual(:)-expected(:)))<=multiplier*eps(scale), ...
        'Independent sequence oracle mismatch.');
end

function expectError(action,identifier)
    before=rng; caught=false;
    try, action(); catch err
        caught=true;
        assert(strcmp(err.identifier,identifier),'Expected %s, received %s: %s',identifier,err.identifier,err.message);
    end
    assert(caught,'Expected rejection %s.',identifier);
    assert(isequal(before,rng),'A rejected sequence call changed caller RNG.');
end
