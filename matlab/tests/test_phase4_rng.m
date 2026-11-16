function report = test_phase4_rng()
%TEST_PHASE4_RNG Named-stream schedules, isolation, boundaries and cleanup.
%   Seed/tag oracles are independently written here. Gaussian draw oracles
%   use a locally saved Twister state; Poisson draw oracles use the already
%   separately tested sampler, rather than another structured exposure call.
%   Whole-result reproducibility is limited to this runtime and version.
    caller_rng = rng;
    guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    rng(814231, 'twister');
    rand(1,5); randn(1,7); % Exercise both uniform and normal caller state.
    [input, single, dual, model, geometry, grid] = fixture();
    saved = {input, single, dual, model, geometry, grid};
    metrics = struct();
    metrics.seed_schedule = seedSchedule(input, single, model, geometry);
    metrics.seed_representations = seedRepresentations(input, single, model, geometry, grid);
    metrics.stream_oracles = componentOracles(input, single, dual, model, geometry);
    metrics.component_toggles = componentToggles(input, single, dual, model, geometry);
    metrics.charge_policy = chargeIsolation(input, single, dual, model, geometry);
    metrics.fixed_and_inactive = fixedAndInactive(input, single, dual, model, geometry);
    metrics.success_cleanup = successCleanup(input, single, dual, model, geometry, grid);
    metrics.early_cleanup = earlyCleanup(input, single, model, geometry, grid);
    metrics.late_cleanup = lateCleanup(input, single, dual, model, geometry, grid);
    metrics.repeatability = repeatability(input, single, dual, model, geometry, grid);
    assert(isequal(saved, {input, single, dual, model, geometry, grid}), ...
        'The RNG suite changed its caller-owned fixtures.');
    runtime_name = 'MATLAB';
    if exist('OCTAVE_VERSION','builtin'), runtime_name = 'GNU Octave'; end
    metrics.runtime = struct('name', runtime_name, 'version', version());
    metrics.reproducibility_scope = 'same_runtime_and_version_only';
    names = {'named_component_seed_schedule_and_wrap_boundaries', ...
        'accepted_and_rejected_seed_representations', ...
        'each_named_component_matches_independent_seeded_oracle', ...
        'added_component_toggles_isolate_all_other_draws', ...
        'photo_dark_switches_and_zero_support_isolate_streams', ...
        'fixed_maps_and_inactive_paths_are_rng_free', ...
        'public_success_paths_restore_rng_and_caller_values', ...
        'early_failures_restore_rng_and_caller_values', ...
        'post_draw_and_later_frame_failures_restore_rng', ...
        'same_runtime_whole_result_repeatability'};
    tests = repmat(struct('name','','status','passed','passed',true), 1, numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    report = struct('suite','phase4_rng','status','passed','passed',true, ...
        'test_count',numel(names),'tests',tests,'metrics',metrics);
    fprintf('PASS: Phase 4 RNG isolation, %d test groups.\n',numel(names));
end

function metrics = seedSchedule(input, cfg, model, geometry)
    [names, tags, seeds] = schedule();
    before = rng;
    count = 0;
    for k = 1:numel(seeds)
        actual = zeros(size(tags));
        for j = 1:numel(tags)
            actual(j) = alev4.structuredNoiseSeed(seeds(k), names{j});
            expected = mod(seeds(k)+tags(j), 4294967296);
            assert(isequal(actual(j), expected));
            count = count+1;
        end
        assert(numel(unique(actual)) == numel(tags));
    end
    assert(isequal(before, rng), 'Seed arithmetic consumed randomness.');
    indices = [1 2 67108863 67108864];
    sequence_seeds = [0 4294967295];
    sequence_checks = 0;
    for seed = sequence_seeds
        result = alev4.simulateNoiseSequence(input, cfg, ones(size(indices)), seed, model, ...
            geometry, struct('frame_indices', indices));
        expected = mod(seed+64*(indices-1), 4294967296);
        assert(isequal(result.frame_seeds, expected));
        all_component_seeds = [];
        for k = 1:numel(indices)
            observed = result.frames{k}.seeds;
            assert(observed.frame == expected(k));
            for j = 1:numel(tags)
                oracle = mod(expected(k)+tags(j), 4294967296);
                assert(observed.(names{j}) == oracle);
                all_component_seeds(end+1) = oracle; %#ok<AGROW>
                sequence_checks = sequence_checks+1;
            end
        end
        assert(numel(unique(all_component_seeds)) == numel(all_component_seeds), ...
            'Supported first/last absolute frames reused a named component seed.');
    end
    assert(isequal(before, rng));
    metrics = struct('component_names',{names}, 'component_tags',tags, ...
        'frame_seed_boundaries',seeds, 'seed_arithmetic_checks',count, ...
        'absolute_frame_indices',indices, 'sequence_seed_endpoints',sequence_seeds, ...
        'sequence_component_checks',sequence_checks, 'all_wrap_points_checked',true);
end

function metrics = seedRepresentations(input, cfg, model, geometry, grid)
    accepted = {0, 1, 4294967295, uint32(0), uint32(4294967295), ...
        uint64(4294967295), int64(4294967295), single(0), single(4294967040), ...
        sparse(0), sparse(4294967295)};
    accepted_classes = cell(size(accepted));
    for k = 1:numel(accepted)
        seed = accepted{k}; accepted_classes{k} = class(seed);
        before = rng;
        actual = alev4.structuredNoiseSeed(seed,'low_pixel');
        assert(isequal(actual, mod(full(double(seed))+43,4294967296)));
        r = alev4.simulateStructuredExposure(input,cfg,1,seed,model,geometry);
        assert(isequal(r.seeds.frame,full(double(seed))) && r.seeds.low_pixel == actual);
        assert(isequal(before,rng));
    end
    invalid = {-1, -eps, 0.5, 4294967296, NaN, Inf, -Inf, ...
        1+1i, true, '1', [], [0 1], uint64(4294967296), single(4294967295)};
    rejected_calls = 0;
    for k = 1:numel(invalid)
        bad = invalid{k};
        preservedError(@() alev4.structuredNoiseSeed(bad,'photo'), 'ALEV4:InvalidSeed');
        rejected_calls = rejected_calls+1;
        for enabled = [true false]
            selected = model; selected.enabled = enabled;
            preservedError(@() alev4.simulateStructuredExposure(input,cfg,1,bad,selected,geometry), 'ALEV4:InvalidSeed');
            preservedError(@() alev4.simulateStructuredSpatialExposure(input,grid,geometry,cfg,1,bad,selected), 'ALEV4:InvalidSeed');
            preservedError(@() alev4.simulateNoiseSequence(input,cfg,1,bad,selected,geometry), 'ALEV4:InvalidSeed');
            rejected_calls = rejected_calls+3;
        end
    end
    bad_names = {'', 'PHOTO', 'photo ', 'shared_pixel', 'high_gain_row', 1, {'photo'}, ['photo';'dark ']};
    for k = 1:numel(bad_names)
        preservedError(@() alev4.structuredNoiseSeed(0,bad_names{k}), 'ALEV4:InvalidStructuredNoiseComponent');
    end
    preservedError(@() alev4.structuredNoiseSeed(0), 'ALEV4:StructuredNoiseSeedArguments');
    metrics = struct('accepted_representation_count',numel(accepted), ...
        'accepted_classes',{accepted_classes}, 'invalid_seed_count',numel(invalid), ...
        'invalid_seed_public_calls',rejected_calls, 'invalid_component_name_count',numel(bad_names), ...
        'enabled_and_disabled_core_spatial_sequence_rejection',true, ...
        'single_precision_rounded_upper_endpoint_rejected',true);
end

function metrics = componentOracles(input, single, dual, model, geometry)
    [names, tags, seeds] = schedule();
    exposure_count = 0; gaussian_checks = 0; poisson_checks = 0;
    for k = 1:numel(seeds)
        for mode = 1:2
            if mode == 1, cfg = single; else, cfg = dual; end
            before = rng;
            r = alev4.simulateStructuredExposure(input,cfg,1,seeds(k),model,geometry);
            assert(isequal(before,rng));
            for j = 1:numel(tags)
                assert(r.seeds.(names{j}) == mod(seeds(k)+tags(j),4294967296));
            end
            assert(isequal(r.components.photo_electrons, poissonOracle(r.readout.expected_photoelectrons,mod(seeds(k)+1,4294967296))));
            assert(isequal(r.components.dark_electrons, poissonOracle(r.readout.expected_dark_electrons,mod(seeds(k)+2,4294967296))));
            poisson_checks = poisson_checks+2;
            paths = {'shared'}; prefixes = {'shared'};
            if mode == 1
                paths{end+1} = 'single'; prefixes{end+1} = 'single';
            else
                paths = [paths, {'high_gain','low_gain'}]; prefixes = [prefixes, {'high','low'}];
            end
            for j = 1:numel(paths)
                path = paths{j}; prefix = prefixes{j};
                component = r.components.(path); settings = model.(path);
                if strcmp(path,'shared')
                    pixel_sigma = 0;
                elseif strcmp(path,'single')
                    pixel_sigma = cfg.read_noise_e;
                else
                    pixel_sigma = cfg.(path).read_noise_e;
                end
                kinds = {'row','column','frame','pixel'};
                shapes = {[size(input,1) 1], [1 size(input,2)], [1 1], size(input)};
                sigmas = [settings.row_noise_e settings.column_noise_e settings.frame_noise_e pixel_sigma];
                for q = 1:numel(kinds)
                    actual = component.([kinds{q} '_e']);
                    if strcmp(path,'shared') && strcmp(kinds{q},'pixel')
                        assert(isequal(actual,zeros(size(input))));
                    else
                        tag = tags(strcmp(names,[prefix '_' kinds{q}]));
                        assert(isscalar(tag));
                        expected = gaussianOracle(sigmas(q),shapes{q},mod(seeds(k)+tag,4294967296));
                        assert(isequal(actual,expected), 'A component did not use its documented local Twister stream.');
                        gaussian_checks = gaussian_checks+1;
                    end
                end
            end
            assert(isequal(before,rng));
            exposure_count = exposure_count+1;
        end
    end
    metrics = struct('boundary_seed_count',numel(seeds), 'exposure_count',exposure_count, ...
        'gaussian_component_oracle_checks',gaussian_checks, 'poisson_component_oracle_checks',poisson_checks, ...
        'all_17_named_streams_covered',true, 'dimensions',size(input));
end

function metrics = componentToggles(input, single, dual, model, geometry)
    configurations = {single, dual};
    all_toggles = {}; unchanged_atom_checks = 0;
    for mode = 1:2
        cfg = configurations{mode};
        reference = alev4.simulateStructuredExposure(input,cfg,1,4294967286,model,geometry);
        original = atoms(reference);
        if mode == 1, paths = {'shared','single'}; else, paths = {'shared','high_gain','low_gain'}; end
        fields = {'fixed_offset_e','row_noise_e','column_noise_e','frame_noise_e'};
        atoms_for_fields = {'fixed_offset_e','row_e','column_e','frame_e'};
        for j = 1:numel(paths)
            path = paths{j};
            for k = 1:numel(fields)
                changed = model; changed.(path).(fields{k}) = 0;
                r = alev4.simulateStructuredExposure(input,cfg,1,4294967286,changed,geometry);
                current = atoms(r); selected = [path '__' atoms_for_fields{k}];
                value = current.(selected); prior = original.(selected);
                assert(all(value(:)==0) && any(prior(:)~=0));
                unchanged_atom_checks = unchanged_atom_checks+sameOtherAtoms(original,current,{selected});
                all_toggles{end+1} = [reference.readout_mode '.' path '.' fields{k}]; %#ok<AGROW>
            end
        end
        if mode == 1, paths = {'single'}; else, paths = {'high_gain','low_gain'}; end
        for j = 1:numel(paths)
            changed_cfg = cfg; path = paths{j};
            if mode == 1, changed_cfg.read_noise_e = 0; else, changed_cfg.(path).read_noise_e = 0; end
            r = alev4.simulateStructuredExposure(input,changed_cfg,1,4294967286,model,geometry);
            current = atoms(r); selected = [path '__pixel_e']; value = current.(selected);
            assert(all(value(:)==0));
            unchanged_atom_checks = unchanged_atom_checks+sameOtherAtoms(original,current,{selected});
            all_toggles{end+1} = [reference.readout_mode '.' path '.read_noise_e']; %#ok<AGROW>
        end
    end
    assert(numel(all_toggles) == 23);
    metrics = struct('toggle_count',numel(all_toggles), 'toggles',{all_toggles}, ...
        'unchanged_component_array_checks',unchanged_atom_checks, 'zero_components_are_exact',true);
end

function metrics = chargeIsolation(input, single, dual, model, geometry)
    configurations = {single, dual}; names = {'photo_shot_off','dark_shot_off', ...
        'zero_dark_rate','zero_prnu','unit_prnu','zero_input','zero_exposure'};
    unchanged = 0; cases = 0;
    for mode = 1:2
        cfg = configurations{mode};
        reference = alev4.simulateStructuredExposure(input,cfg,1,4294967295,model,geometry);
        original = atoms(reference);
        for k = 1:numel(names)
            changed_cfg = cfg; changed_model = model; changed_input = input; exposure = 1;
            switch names{k}
                case 'photo_shot_off'
                    if mode == 1, changed_cfg.shot_noise = false; else, changed_cfg.sensor.shot_noise = false; end
                    excluded = {'photo_electrons'};
                case 'dark_shot_off'
                    changed_model.dark_shot_noise = false; excluded = {'dark_electrons'};
                case 'zero_dark_rate'
                    changed_model.dark_current_e_per_s = 0; excluded = {'dark_electrons'};
                case 'zero_prnu'
                    changed_model.prnu = 0; excluded = {'photo_electrons'};
                case 'unit_prnu'
                    changed_model.prnu = 1; excluded = {'photo_electrons'};
                case 'zero_input'
                    changed_input = zeros(size(input)); excluded = {'photo_electrons'};
                otherwise
                    exposure = 0; excluded = {'photo_electrons','dark_electrons'};
            end
            r = alev4.simulateStructuredExposure(changed_input,changed_cfg,exposure,4294967295,changed_model,geometry);
            current = atoms(r);
            unchanged = unchanged+sameOtherAtoms(original,current,excluded);
            if strcmp(names{k},'photo_shot_off')
                assert(isequal(r.components.photo_electrons,r.readout.expected_photoelectrons));
            elseif strcmp(names{k},'dark_shot_off')
                assert(isequal(r.components.dark_electrons,r.readout.expected_dark_electrons));
            elseif ~strcmp(names{k},'unit_prnu')
                for j = 1:numel(excluded), value = current.(excluded{j}); assert(all(value(:)==0)); end
            end
            cases = cases+1;
        end
    end
    metrics = struct('policies',{names}, 'single_and_dual_case_count',cases, ...
        'unchanged_component_array_checks',unchanged, 'zero_expectations_do_not_advance_other_streams',true);
end

function metrics = fixedAndInactive(input, single, dual, model, geometry)
    saved = {model,geometry}; before = rng;
    canonical = alev4.createStructuredNoise(geometry.full_grid_size,model);
    maps = alev4.structuredNoiseMaps(canonical,geometry);
    assert(isequal(before,rng) && isequal(saved,{model,geometry}));
    assert(isequal(maps.prnu,repmat(model.prnu,size(input))));
    configurations = {single,dual}; checks = 0;
    for mode = 1:2
        cfg = configurations{mode};
        reference = alev4.simulateStructuredExposure(input,cfg,1,27481,model,geometry);
        changed = model;
        if mode == 1, inactive = {'high_gain','low_gain'}; else, inactive = {'single'}; end
        for k = 1:numel(inactive)
            path = inactive{k};
            changed.(path) = struct('fixed_offset_e',11, 'row_noise_e',12, 'column_noise_e',13, 'frame_noise_e',14);
        end
        r = alev4.simulateStructuredExposure(input,cfg,1,27481,changed,geometry);
        assert(isequal(r.components,reference.components) && isequal(r.readout,reference.readout));
        changed = model; changed.realization_id = 'ASSUMED-P4-IDENTICAL-MAPS-OTHER-LABEL';
        r = alev4.simulateStructuredExposure(input,cfg,1,27481,changed,geometry);
        assert(isequal(r.components,reference.components) && isequal(r.readout,reference.readout));
        checks = checks+2;
    end
    assert(isequal(before,rng));
    metrics = struct('constructor_and_roi_extraction_rng_free',true, ...
        'inactive_configuration_and_identity_label_checks',checks, ...
        'input_values_unchanged',true);
end

function metrics = successCleanup(input, single, dual, model, geometry, grid)
    configurations = {single,dual}; count = 0;
    saved = {input,single,dual,model,geometry,grid};
    for mode = 1:2
        cfg = configurations{mode};
        for enabled = [true false]
            selected = model; selected.enabled = enabled;
            preservedCall(@() alev4.simulateStructuredExposure(input,cfg,1,0,selected,geometry));
            preservedCall(@() alev4.simulateStructuredSpatialExposure(input,grid,geometry,cfg,1,4294967295,selected));
            preservedCall(@() alev4.simulateNoiseSequence(input,cfg,[1 2],4294967295,selected,geometry));
            count = count+3;
        end
    end
    assert(isequal(saved,{input,single,dual,model,geometry,grid}));
    metrics = struct('public_success_call_count',count, ...
        'enabled_and_disabled_single_dual_spatial_sequence',true, ...
        'uniform_and_normal_caller_rng_unchanged',true, 'caller_values_unchanged',true);
end

function metrics = earlyCleanup(input, cfg, model, geometry, grid)
    saved = {input,cfg,model,geometry,grid};
    broken = model; broken.unknown = 1;
    preservedError(@() alev4.simulateStructuredExposure(input,cfg,1,1,broken,geometry), 'ALEV4:UnknownStructuredNoiseField');
    preservedError(@() alev4.simulateStructuredSpatialExposure(input,grid,geometry,cfg,1,1,broken), 'ALEV4:UnknownStructuredNoiseField');
    bad_geometry = geometry; bad_geometry.active_roi(1) = 0;
    preservedError(@() alev4.simulateStructuredExposure(input,cfg,1,1,model,bad_geometry), 'ALEV4:InvalidGeometry');
    bad_cfg = cfg; bad_cfg.image_size = fliplr(cfg.image_size);
    preservedError(@() alev4.simulateStructuredExposure(input,bad_cfg,1,1,model,geometry), 'ALEV4:GeometryBindingConflict');
    bad_input = input; bad_input(1) = NaN;
    preservedError(@() alev4.simulateStructuredExposure(bad_input,cfg,1,1,model,geometry), 'ALEV4:InvalidIrradiance');
    preservedError(@() alev4.simulateStructuredExposure(input,cfg,-1,1,model,geometry), 'ALEV4:InvalidExposure');
    preservedError(@() alev4.simulateStructuredExposure(input,cfg,1,NaN,model,geometry), 'ALEV4:InvalidSeed');
    preservedError(@() alev4.simulateNoiseSequence(input,cfg,[1 1],1,model,geometry, ...
        struct('frame_indices',[67108864 67108865])), 'ALEV4:InvalidNoiseSequenceIndices');
    preservedError(@() alev4.simulateNoiseSequence(input,cfg,1,1,model,geometry, ...
        struct('ei_label',0)), 'ALEV4:InvalidNoiseSequenceEi');
    poisson_overflow = model; poisson_overflow.dark_current_e_per_s = 1e9+1;
    preservedError(@() alev4.simulateStructuredExposure(input,cfg,1,1,poisson_overflow,geometry), 'ALEV4:InvalidPoissonMean');
    assert(isequal(saved,{input,cfg,model,geometry,grid}));
    metrics = struct('failure_count',10, 'exact_error_identifiers_checked',true, ...
        'rng_restored',true, 'caller_values_unchanged',true);
end

function metrics = lateCleanup(input, single, dual, model, geometry, grid)
    saved = {input,single,dual,model,geometry,grid};
    gain_overflow = single; gain_overflow.gain_dn_per_e = realmax;
    preservedError(@() alev4.simulateStructuredExposure(input,gain_overflow,1,28,model,geometry), 'ALEV4:StructuredNoiseOverflow');
    % Normal RMS values draw first. Two separately finite post-well fixed
    % offsets then overflow when the read paths are assembled. The spatial
    % wrapper must also restore RNG after its successful legacy baseline.
    offset_overflow = model; offset_overflow.shared.fixed_offset_e = realmax;
    offset_overflow.single.fixed_offset_e = realmax;
    offset_overflow.high_gain.fixed_offset_e = realmax;
    preservedError(@() alev4.simulateStructuredExposure(input,single,1,29,offset_overflow,geometry), 'ALEV4:StructuredNoiseOverflow');
    preservedError(@() alev4.simulateStructuredExposure(input,dual,1,30,offset_overflow,geometry), 'ALEV4:StructuredNoiseOverflow');
    preservedError(@() alev4.simulateStructuredSpatialExposure(input,grid,geometry,single,1,31,offset_overflow), 'ALEV4:StructuredNoiseOverflow');
    preservedError(@() alev4.simulateStructuredSpatialExposure(input,grid,geometry,dual,1,32,offset_overflow), 'ALEV4:StructuredNoiseOverflow');
    % The first frame is independently proved executable. Only the second
    % frame's doubled dark mean crosses the sampler's explicit 1e9 limit.
    later_frame = model; later_frame.dark_current_e_per_s = 6e8;
    first = alev4.simulateStructuredExposure(input,single,1,33,later_frame,geometry);
    assert(all(first.readout.full_well_saturated(:)));
    preservedError(@() alev4.simulateNoiseSequence(input,single,[1 2],33,later_frame,geometry), 'ALEV4:InvalidPoissonMean');
    assert(isequal(saved,{input,single,dual,model,geometry,grid}));
    metrics = struct('post_draw_or_later_frame_failure_count',6, ...
        'gain_overflow_after_all_single_components',true, ...
        'spatial_legacy_baseline_executed_before_structured_failure',true, ...
        'first_sequence_frame_proved_executable',true, ...
        'rng_restored',true, 'caller_values_unchanged',true);
end

function metrics = repeatability(input, single, dual, model, geometry, grid)
    configurations = {single,dual}; pairs = 0; seed_changes = 0;
    for mode = 1:2
        cfg = configurations{mode};
        for seed = [0 4294967295]
            before = rng;
            first = alev4.simulateStructuredExposure(input,cfg,1,seed,model,geometry);
            rand(1,11); randn(1,13); different_caller = rng;
            second = alev4.simulateStructuredExposure(input,cfg,1,seed,model,geometry);
            assert(isequal(first,second) && isequal(different_caller,rng));
            rng(before);
            changed = alev4.simulateStructuredExposure(input,cfg,1,mod(seed+64,4294967296),model,geometry);
            assert(~isequal(first.components,changed.components));
            assert(isequal(first.active_maps,changed.active_maps));
            pairs = pairs+1; seed_changes = seed_changes+1;
        end
        spatial_first = alev4.simulateStructuredSpatialExposure(input,grid,geometry,cfg,1,82,model);
        spatial_second = alev4.simulateStructuredSpatialExposure(input,grid,geometry,cfg,1,82,model);
        assert(isequal(spatial_first,spatial_second));
        sequence_first = alev4.simulateNoiseSequence(input,cfg,[1 2],83,model,geometry);
        sequence_second = alev4.simulateNoiseSequence(input,cfg,[1 2],83,model,geometry);
        assert(isequal(sequence_first,sequence_second));
        pairs = pairs+2;
    end
    metrics = struct('whole_result_repeat_pairs',pairs, 'different_seed_component_checks',seed_changes, ...
        'unrelated_caller_random_draws_do_not_change_results',true, ...
        'fixed_maps_unchanged_across_frame_seeds',true, ...
        'separate_process_identity_claimed_here',false);
end

function [input, single, dual, model, geometry, grid] = fixture()
    dimensions = [3 5];
    input = reshape(16:30,dimensions);
    geometry = alev4.createSensorGeometry(struct('full_grid_size',dimensions,'pixel_pitch_m',1));
    grid = alev4.createSpatialGrid(struct('x_edges_m',0:dimensions(2),'y_edges_m',0:dimensions(1)));
    sensor = struct('image_size',dimensions, 'pixel_pitch_m',1, 'wavelength_nm',550, ...
        'bin_width_nm',1, 'qe',ones(1,3), 'fill_factor',1, 'shot_noise',true);
    single = alev4.createBaselineSensor(sensor); single.read_noise_e = 2;
    dual = alev4.createDualGainSensor(struct('sensor',sensor, ...
        'high_gain',struct('read_noise_e',3), 'low_gain',struct('read_noise_e',4)));
    fixed = reshape(-7:7,dimensions)/8;
    model = alev4.createStructuredNoise(dimensions,struct('prnu',1.25, ...
        'dark_current_e_per_s',7, ...
        'shared',struct('fixed_offset_e',fixed, 'row_noise_e',0.5, 'column_noise_e',0.75, 'frame_noise_e',1), ...
        'single',struct('fixed_offset_e',fixed+1, 'row_noise_e',1.25, 'column_noise_e',1.5, 'frame_noise_e',1.75), ...
        'high_gain',struct('fixed_offset_e',fixed+2, 'row_noise_e',2.25, 'column_noise_e',2.5, 'frame_noise_e',2.75), ...
        'low_gain',struct('fixed_offset_e',fixed+3, 'row_noise_e',3.25, 'column_noise_e',3.5, 'frame_noise_e',3.75)));
end

function [names, tags, seeds] = schedule()
    names = {'photo','dark','shared_row','shared_column','shared_frame', ...
        'single_row','single_column','single_frame','single_pixel', ...
        'high_row','high_column','high_frame','high_pixel', ...
        'low_row','low_column','low_frame','low_pixel'};
    tags = [1 2 10 11 12 20 21 22 23 30 31 32 33 40 41 42 43];
    modulus = 4294967296;
    % Include both integer seed endpoints and each tag's last unwrapped,
    % exact zero-wrap, and first wrapped values that remain accepted seeds.
    seeds = unique([0 1 modulus-2 modulus-1 modulus-tags-1 modulus-tags modulus-tags+1]);
    seeds = seeds(seeds >= 0 & seeds < modulus);
end

function value = gaussianOracle(sigma, shape, seed)
    before = rng; guard = onCleanup(@() rng(before)); %#ok<NASGU>
    rng(seed,'twister'); value = sigma*randn(shape);
end

function value = poissonOracle(expected, seed)
    before = rng; guard = onCleanup(@() rng(before)); %#ok<NASGU>
    rng(seed,'twister'); value = alev4.samplePoisson(expected);
end

function value = atoms(result)
    c = result.components;
    value = struct('photo_electrons',c.photo_electrons,'dark_electrons',c.dark_electrons);
    paths = fieldnames(c);
    fields = {'fixed_offset_e','row_e','column_e','frame_e','pixel_e'};
    for k = 1:numel(paths)
        if ~isstruct(c.(paths{k})), continue; end
        for j = 1:numel(fields)
            value.([paths{k} '__' fields{j}]) = c.(paths{k}).(fields{j});
        end
    end
end

function count = sameOtherAtoms(reference, actual, excluded)
    names = fieldnames(reference); assert(isequal(names,fieldnames(actual))); count = 0;
    for k = 1:numel(names)
        if any(strcmp(names{k},excluded)), continue; end
        assert(isequal(reference.(names{k}),actual.(names{k})), ...
            ['An unrelated named component changed: ' names{k}]);
        count = count+1;
    end
end

function preservedCall(call)
    before = rng; call();
    assert(isequal(before,rng), 'A successful public call changed the caller RNG state.');
end

function preservedError(call, expected_identifier)
    before = rng; caught = false;
    try
        call();
    catch err
        caught = true;
        assert(strcmp(err.identifier,expected_identifier), ...
            ['Expected ' expected_identifier ', received ' err.identifier ': ' err.message]);
    end
    assert(caught, ['Expected failure: ' expected_identifier]);
    assert(isequal(before,rng), 'A rejected public call changed the caller RNG state.');
end
