function report = test_phase4_demo()
%TEST_PHASE4_DEMO Frozen inventory, real readbacks and isolated failure controls.
%   Exactly one real 24-frame demo executes. Later faults use the same cached
%   generated inventory and explicitly artificial exporters/readers; they test
%   demo orchestration and ownership, never claim additional wire round trips.
    state=rng; rng_guard=onCleanup(@()rng(state)); %#ok<NASGU>
    folder=tempname(); assert(mkdir(folder));
    marker=fullfile(folder,'owned-test-root'); writeBytes(marker,uint8('phase4-demo-test'));
    folder_guard=onCleanup(@()removeFolder(folder,marker)); %#ok<NASGU>
    names={ ...
        'fixed_24_frame_inventory_generation_only_and_rng', ...
        'four_physical_exposure_and_electronic_gain_sweeps', ...
        'three_sequence_roles_seed_wrap_reset_continuation_ei', ...
        'independent_adc_well_merge_map_coverage', ...
        'explicit_units_assumed_provenance_and_runtime', ...
        'complete_24_bundle_export_exact_native_readbacks', ...
        'existing_output_stale_success_is_never_overwritten', ...
        'invalid_output_paths_and_symlink_ancestors_reject', ...
        'missing_exporter_or_reader_reject_before_creation', ...
        'incomplete_summary_until_every_export_and_readback', ...
        'injected_exporter_failure_cleans_only_owned_stage', ...
        'injected_reader_failure_and_mismatch_clean_owned_stage', ...
        'staging_collision_and_replacement_identity_preserve_sentinels', ...
        'publication_failure_race_identity_and_summary_cleanup'};
    rng(724603,'twister'); rand(1,3); randn(1,4); before=rng;
    inventory=alev4.phase4Fixtures(); assert(isequal(before,rng));
    metrics=cell(1,numel(names));
    metrics{1}=checkInventory(inventory);
    metrics{2}=checkSweeps(inventory);
    metrics{3}=checkSequences(inventory);
    metrics{4}=checkCoverage(inventory);
    metrics{5}=checkDeclarations(inventory);
    [metrics{6},directory]=realDemo(folder,inventory);
    metrics{7}=existingOutputs(folder,directory);
    metrics{8}=invalidPaths(folder);
    [scope,scope_guard]=faultScope(folder,inventory); %#ok<NASGU>
    metrics{9}=missingIo(scope);
    metrics{10}=completionOrder(scope);
    metrics{11}=exportFailures(scope);
    metrics{12}=readerFailures(scope);
    metrics{13}=stagingOwnership(scope);
    metrics{14}=publicationFailures(scope);
    clear scope_guard;
    tests=repmat(struct('name','','status','passed','passed',true),1,numel(names));
    counts=zeros(1,numel(names));
    for k=1:numel(names), tests(k).name=names{k}; counts(k)=metrics{k}.case_count; end
    report=struct('suite','phase4_demo','status','passed','passed',true, ...
        'test_count',numel(names),'tests',tests,'metrics',struct( ...
        'case_count',sum(counts),'group_case_counts',counts,'groups',{metrics}, ...
        'real_24_frame_demo_runs',1,'real_exact_readbacks',24, ...
        'fault_controls_use_cached_inventory_and_artificial_io',true, ...
        'same_runtime_and_version_only',true,'synthetic',true,'calibrated_alev4',false));
    fprintf('PASS: Phase 4 demo contract, %d groups, %d cases.\n',numel(names),sum(counts));
end

function names = frozenNames()
    names={'deterministic_prnu_offsets','dark_short','dark_long','dark_noisy', ...
        'shared_row_dual','path_column_dual','mixed_dual','spatial_crop_single', ...
        'single_exposure_zero','single_exposure_mid','single_exposure_high', ...
        'dual_exposure_zero','dual_exposure_mid','dual_exposure_high', ...
        'single_gain_low','single_gain_high','dual_gain_low','dual_gain_high', ...
        'sequence_primary_001','sequence_primary_002','sequence_primary_003', ...
        'sequence_reset_001','sequence_continue_002','sequence_continue_003'};
end

function m = checkInventory(i)
    names=frozenNames(); assert(i.frame_count==24 && numel(i.results)==24);
    assert(isequal({i.fixtures.name},names) && isequal({i.fixtures.bundle_dir},names));
    assert(i.generation_complete && ~i.demo_complete && ~i.export_readback_complete);
    for k=1:24
        r=i.results{k}; f=i.fixtures(k);
        assert(strcmp(r.readout_mode,f.readout_mode) && strcmp(r.result_kind,f.result_kind));
        assert(isequal(r.configuration,f.configuration) && isequal(r.geometry,f.geometry));
        assert(isequal(r.noise_model,f.noise_model) && isequal(r.seeds,f.component_seeds));
        assert(isequal(size(r.input_irradiance),f.image_size));
        assert(f.seed==r.seeds.frame && f.frame_seed==f.seed && f.exposure_s==r.readout.exposure_s);
    end
    assert(isequal(i.fixtures(8).image_size,[4 5]));
    assert(isequal(i.fixtures(8).geometry.active_roi,[2 2 4 5]));
    reject(@()alev4.phase4Fixtures(1),'');
    m=struct('case_count',25,'frozen_names',{names},'generation_is_not_demo_completion',true);
end

function m = checkSweeps(i)
    assert(numel(i.sweeps)==4);
    expected_names={'single_exposure','dual_exposure','single_electronic_gain','dual_electronic_gain'};
    ranges={9:11,12:14,15:16,17:18}; times={[0 .01 .1],[0 .01 .1],[.01 .01],[.01 .01]};
    scales={[1 1 1],[1 1 1],[.25 2],[1 4]}; seeds=[94100 94200 94300 94400];
    for k=1:4
        s=i.sweeps(k); f=i.fixtures(ranges{k});
        assert(strcmp(s.name,expected_names{k}) && isequal(s.fixture_names,{f.name}));
        assert(isequal(s.exposures_s,times{k}) && isequal(s.frame_seeds,seeds(k)*ones(size(times{k}))));
        assert(isequal(s.electronic_gain_scales,scales{k}) && isequal([f.sweep_index],1:numel(f)));
        assert(isequal([f.exposure_s],times{k}) && isequal([f.electronic_gain_scale],scales{k}));
        assert(strcmp(s.ei_policy,'metadata_only_no_exposure_or_gain_mapping'));
        if k<=2, assert(strcmp(s.variable,'physical_exposure_s'));
        else, assert(strcmp(s.variable,'electronic_gain_scale')); end
        if mod(k,2)==1
            assert(isequal(s.single_gain_dn_per_e,scales{k}));
            assert(isempty(s.high_gain_dn_per_e) && isempty(s.low_gain_dn_per_e));
        else
            assert(isequal(s.high_gain_dn_per_e,4*scales{k}) && isequal(s.low_gain_dn_per_e,.5*scales{k}));
            assert(isequal(s.merge_start_e,600./scales{k}) && isequal(s.merge_end_e,900./scales{k}));
        end
    end
    m=struct('case_count',4,'sweep_names',{expected_names},'exposure_and_electronic_gain_are_distinct',true);
end

function m = checkSequences(i)
    assert(numel(i.sequences)==3); roles={'primary','reset','continue'};
    ranges={19:21,22,23:24}; indices={1:3,1,2:3}; eis={[800 800 800],200,[1600 3200]};
    tags=[1 2 10 11 12 20 21 22 23 30 31 32 33 40 41 42 43];
    components={'photo','dark','shared_row','shared_column','shared_frame', ...
        'single_row','single_column','single_frame','single_pixel', ...
        'high_row','high_column','high_frame','high_pixel','low_row','low_column','low_frame','low_pixel'};
    for k=1:3
        s=i.sequences(k); f=i.fixtures(ranges{k});
        assert(strcmp(s.role,roles{k}) && strcmp(s.sequence_id,'ASSUMED-P4-DEMO-SEQUENCE-v1'));
        assert(s.sequence_seed==4294967200 && isequal(s.frame_indices,indices{k}));
        assert(isequal(s.frame_seeds,mod(4294967200+64*(indices{k}-1),2^32)));
        assert(isequal(s.ei_label,eis{k}) && isequal(s.fixture_names,{f.name}));
        assert(strcmp(s.temporal_policy,'independent_frames') && strcmp(s.rng_generator,'twister'));
        assert(strcmp(s.continuation_policy,'pure_function_of_arguments_and_absolute_frame_indices'));
        assert(s.seed_schedule.stride==64 && s.seed_schedule.modulus==2^32);
        assert(s.seed_schedule.minimum_frame_index==1 && s.seed_schedule.maximum_frame_index==2^26);
        assert(strcmp(s.seed_schedule.expression,'mod(sequence_seed + 64*(absolute_frame_index-1), 2^32)'));
        for j=1:numel(f)
            assert(f(j).sequence_seed==s.sequence_seed && f(j).absolute_frame_index==indices{k}(j));
            for q=1:numel(tags), assert(f(j).component_seeds.(components{q})==mod(f(j).seed+tags(q),2^32)); end
            assert(isequal(i.results{ranges{k}(j)},i.results{18+indices{k}(j)}));
        end
    end
    assert(isequal([i.fixtures(19:21).seed],[4294967200 4294967264 32]));
    assert(isequal(i.results(19:21),i.results(22:24)) && ~isequal([i.fixtures(19:21).ei_label],[i.fixtures(22:24).ei_label]));
    m=struct('case_count',3,'roles',{roles},'component_seed_checks',102,'whole_result_ei_identity',true);
end

function m = checkCoverage(i)
    for k=1:24
        r=i.results{k}; o=r.readout; c=i.fixtures(k).coverage;
        assert(c.physical_saturation_pixels==nnz(o.full_well_saturated));
        assert(c.reconstruction_valid_pixels==nnz(o.reconstruction_valid));
        assert(i.fixtures(k).minimum_expected_e==min(o.expected_electrons(:)));
        assert(i.fixtures(k).maximum_expected_e==max(o.expected_electrons(:)));
        assert(i.fixtures(k).sum_expected_e==sum(o.expected_electrons(:)));
        if strcmp(r.readout_mode,'single')
            assert(c.single_adc_low_clipped_pixels==nnz(o.adc_low_clipped));
            assert(c.single_adc_high_clipped_pixels==nnz(o.adc_high_clipped));
        else
            assert(c.high_adc_low_clipped_pixels==nnz(o.high_gain.adc_low_clipped));
            assert(c.high_adc_high_clipped_pixels==nnz(o.high_gain.adc_high_clipped));
            assert(c.low_adc_low_clipped_pixels==nnz(o.low_gain.adc_low_clipped));
            assert(c.low_adc_high_clipped_pixels==nnz(o.low_gain.adc_high_clipped));
            assert(c.high_clipped_low_usable_pixels==nnz(o.high_gain.adc_high_clipped & o.low_gain.adc_usable & ~o.full_well_saturated));
            assert(c.merge_transition_pixels==nnz(o.merged.weight_high>0 & o.merged.weight_high<1));
            assert(c.low_high_clipped_before_well_pixels==nnz(o.low_gain.adc_high_clipped & ~o.full_well_saturated));
        end
    end
    f=i.fixtures;
    assert(f(9).coverage.single_adc_low_clipped_pixels>0 && f(10).coverage.single_adc_high_clipped_pixels>0);
    assert(f(11).coverage.physical_saturation_pixels>0 && f(14).coverage.physical_saturation_pixels>0);
    assert(f(12).coverage.high_adc_low_clipped_pixels>0 && f(12).coverage.low_adc_low_clipped_pixels>0);
    assert(f(13).coverage.high_clipped_low_usable_pixels>0 && f(13).coverage.merge_transition_pixels>0);
    assert(f(18).coverage.low_high_clipped_before_well_pixels>0);
    full=i.results{1}; crop=i.results{8};
    assert(isequal(full.noise_model,crop.noise_model));
    for key={'prnu','dark_current_e_per_s'}
        values=full.active_maps.(key{1}); assert(isequal(values(2:5,2:6),crop.active_maps.(key{1})));
    end
    for key={'shared','single','high_gain','low_gain'}
        values=full.active_maps.(key{1}).fixed_offset_e;
        assert(isequal(values(2:5,2:6),crop.active_maps.(key{1}).fixed_offset_e));
    end
    assert(numel(fieldnames(i.fixture_checks))==15 && all(structfun(@(x)islogical(x)&&isscalar(x)&&x,i.fixture_checks)));
    m=struct('case_count',24,'independent_coverage_records',24,'fixed_map_crop_checks',6);
end

function m = checkDeclarations(i)
    assert(i.synthetic && ~i.calibrated_alev4 && ~i.authentic_arriraw);
    assert(strcmp(i.parameter_classification,'assumed') && i.reference_temperature_K==293.15);
    assert(strcmp(i.reproducibility,'same_runtime_and_version_only'));
    assert(strcmp(i.temperature_policy,'declared applicability only; no temperature law'));
    expected=struct('input_irradiance','photons m^-2 s^-1 nm^-1','exposure_s','s', ...
        'charge_and_offsets','electrons','noise_magnitude','RMS electrons', ...
        'dark_current_e_per_s','electrons photosite^-1 s^-1','gain_dn_per_e','DN electron^-1', ...
        'black_level_dn','DN','prnu','dimensionless','pixel_pitch_m','m','reference_temperature_K','K');
    assert(isequal(i.units,expected) && isequal(i.runtime,alev4.spatialBundleUtil('runtime')));
    assert(isequal(i.provenance,alev4.sourceProvenance()));
    assert(strcmp(i.provenance.meaning,['Observed Git HEADs; an empty value means unavailable. ' ...
        'Uncommitted edits, object existence and agreement with dependency gitlinks ' ...
        'are not established by these metadata observations.']));
    m=struct('case_count',1,'unit_fields',10,'observed_heads_are_associations_only',true);
end

function [m,directory] = realDemo(folder,i)
    directory=fullfile(folder,'real','nested','demo'); before=rng; handles=fopen('all');
    s=phase4_demo(directory); assert(isequal(before,rng) && isequal(handles,fopen('all')));
    assert(strcmp(s.status,'complete') && s.demo_complete && s.export_readback_complete);
    assert(s.frame_count==24 && s.exported_frame_count==24 && s.verified_frame_count==24);
    assert(~s.calibrated && ~s.release_accepted && all([s.frames.export_complete]) && all([s.frames.readback_verified]));
    assert(isequal(namesOf(directory),sort([frozenNames() {'phase4-demo-summary.json'}])));
    disk=jsondecode(fileread(fullfile(directory,'phase4-demo-summary.json')));
    assert(strcmp(disk.status,'complete') && disk.verified_frame_count==24 && numel(disk.frames)==24);
    for k=1:24
        bundle=fullfile(directory,s.frames(k).bundle_dir);
        assert(isequal(namesOf(bundle),{'data.bin','structured.json'}));
        [actual,meta]=alev4.readStructuredBundle(bundle);
        assert(isequal(actual,i.results{k}) && isequal(fieldnames(actual),fieldnames(i.results{k})));
        assert(isequal(meta.provenance,s.provenance));
    end
    m=struct('case_count',24,'real_complete_demo_runs',1,'exact_complete_native_readbacks',24,'artifact_count',49);
end

function m = existingOutputs(folder,directory)
    summary=fullfile(directory,'phase4-demo-summary.json'); saved=readBytes(summary);
    reject(@()phase4_demo(directory),'ALEV4:OutputExists'); assert(isequal(readBytes(summary),saved));
    stale=fullfile(folder,'stale_success'); assert(mkdir(stale));
    bytes=uint8('{"status":"complete","demo_complete":true,"verified_frame_count":24}');
    writeBytes(fullfile(stale,'phase4-demo-summary.json'),bytes);
    writeBytes(fullfile(stale,'sentinel'),uint8('prior evidence'));
    reject(@()phase4_demo(stale),'ALEV4:OutputExists');
    assert(isequal(readBytes(fullfile(stale,'phase4-demo-summary.json')),bytes(:)));
    assert(strcmp(fileread(fullfile(stale,'sentinel')),'prior evidence'));
    file=fullfile(folder,'existing_file'); writeBytes(file,uint8('untouched file'));
    reject(@()phase4_demo(file),'ALEV4:OutputExists'); assert(strcmp(fileread(file),'untouched file'));
    m=struct('case_count',3,'prior_success_and_existing_file_bytes_preserved',true);
end

function m = invalidPaths(folder)
    bad={[],42,struct(),{'x'},'',char(['ab';'cd']),['bad' char(0) 'path'], ...
        ['bad' char(10) 'path'],['bad' char(13) 'path'], ...
        [folder filesep '.' filesep 'x'],[folder filesep '..' filesep 'x'], ...
        [folder filesep filesep 'x'],[folder filesep]};
    for k=1:numel(bad), reject(@()phase4_demo(bad{k}),'ALEV4:'); end
    reject(@()phase4_demo(folder,false),'');
    blocked=fullfile(folder,'file_parent'); writeBytes(blocked,uint8('preserve ordinary file'));
    reject(@()phase4_demo(fullfile(blocked,'demo')),'ALEV4:');
    link=fullfile(folder,'ancestor_link'); makeSymlink(folder,link);
    reject(@()phase4_demo(fullfile(link,'missing_demo')),'ALEV4:');
    dangling=fullfile(folder,'dangling'); makeSymlink(fullfile(folder,'absent_target'),dangling);
    reject(@()phase4_demo(dangling),'ALEV4:OutputExists');
    assert(strcmp(fileread(blocked),'preserve ordinary file') && ~alev4.bundlePathExists(fullfile(folder,'missing_demo')));
    m=struct('case_count',numel(bad)+4,'invalid_and_aliased_destinations_rejected',true);
end

function m = missingIo(s)
    global alev4_demo_fault;
    names={'alev4.exportStructuredBundle','alev4.readStructuredBundle'};
    for k=1:2
        resetFault(s,['missing_' num2str(k)],'none',1); alev4_demo_fault.missing=names{k};
        reject(@()phase4_demo(alev4_demo_fault.destination),'ALEV4:Phase4StructuredIoMissing');
        assert(alev4_demo_fault.generations==0 && alev4_demo_fault.exports==0);
        assert(~alev4.bundlePathExists(alev4_demo_fault.destination));
    end
    m=struct('case_count',2,'required_exporter_and_reader_each_missing',true);
end

function m = completionOrder(s)
    global alev4_demo_fault;
    resetFault(s,'last_readback','reader_fail',24);
    reject(@()phase4_demo(alev4_demo_fault.destination),'ALEV4:InjectedDemoReader');
    assert(alev4_demo_fault.exports==24 && alev4_demo_fault.reads==24);
    assert(alev4_demo_fault.incomplete_checks==48 && alev4_demo_fault.publications==0);
    assertNoOwnedOutput(s);
    resetFault(s,'all_readbacks','publish_fail',1);
    reject(@()phase4_demo(alev4_demo_fault.destination),'ALEV4:Phase4DemoWrite');
    assert(alev4_demo_fault.exports==24 && alev4_demo_fault.reads==24);
    assert(alev4_demo_fault.incomplete_checks==48 && alev4_demo_fault.complete_checks==1);
    assertNoOwnedOutput(s);
    m=struct('case_count',2,'last_readback_failure_blocks_completion',true,'all_48_io_boundary_checks_incomplete',true);
end

function m = exportFailures(s)
    global alev4_demo_fault;
    for k=[1 12 24]
        resetFault(s,['export_' num2str(k)],'export_fail',k);
        reject(@()phase4_demo(alev4_demo_fault.destination),'ALEV4:InjectedDemoExporter');
        assert(alev4_demo_fault.exports==k && alev4_demo_fault.reads==k-1 && alev4_demo_fault.publications==0);
        assertNoOwnedOutput(s);
    end
    m=struct('case_count',3,'failure_frame_indices',[1 12 24],'owned_stage_removed_parent_preserved',true);
end

function m = readerFailures(s)
    global alev4_demo_fault; modes={'reader_fail','reader_mismatch','reader_missing','reader_nonscalar'};
    for k=1:numel(modes)
        resetFault(s,modes{k},modes{k},2);
        reject(@()phase4_demo(alev4_demo_fault.destination),'ALEV4:');
        assert(alev4_demo_fault.exports==2 && alev4_demo_fault.reads==2 && alev4_demo_fault.publications==0);
        assertNoOwnedOutput(s);
    end
    m=struct('case_count',numel(modes),'modes',{modes},'throw_and_nonexact_readback_reject',true);
end

function m = stagingOwnership(s)
    global alev4_demo_fault;
    for k=1:2
        resetFault(s,['collision_' num2str(k)],'none',1);
        if k==1, assert(mkdir(s.stage)); file=fullfile(s.stage,'foreign'); else, file=s.stage; end
        writeBytes(file,uint8('preexisting stage sentinel'));
        reject(@()phase4_demo(alev4_demo_fault.destination),'ALEV4:Phase4DemoWrite');
        assert(strcmp(fileread(file),'preexisting stage sentinel') && alev4_demo_fault.exports==0);
        if k==1, assert(rmdir(s.stage,'s')); else, delete(s.stage); end
    end
    resetFault(s,'ambiguous_creation','ambiguous_mkdir',1);
    reject(@()phase4_demo(alev4_demo_fault.destination),'ALEV4:Phase4DemoWrite');
    assert(strcmp(fileread(fullfile(s.stage,'foreign')),'foreign stage sentinel'));
    assert(alev4_demo_fault.exports==0); assert(rmdir(s.stage,'s'));
    for mode={'export_replace','reader_replace'}
        resetFault(s,mode{1},mode{1},2);
        reject(@()phase4_demo(alev4_demo_fault.destination),'ALEV4:InjectedDemoReplacement');
        assert(strcmp(fileread(fullfile(s.stage,'foreign')),'foreign stage sentinel'));
        assert(exist(alev4_demo_fault.relocated,'dir')==7 && ~alev4.bundlePathExists(alev4_demo_fault.destination));
        assert(rmdir(s.stage,'s')); assert(rmdir(alev4_demo_fault.relocated,'s'));
    end
    m=struct('case_count',5,'preexisting_ambiguous_and_replaced_stage_sentinels_preserved',true);
end

function m = publicationFailures(s)
    global alev4_demo_fault; modes={'publish_fail','publish_nested','publish_identity','publish_corrupt_summary'};
    for k=1:numel(modes)
        resetFault(s,modes{k},modes{k},1);
        reject(@()phase4_demo(alev4_demo_fault.destination),'ALEV4:');
        assert(alev4_demo_fault.publications==1 && alev4_demo_fault.complete_checks==1);
        assert(~alev4.bundlePathExists(s.stage));
        if any(strcmp(modes{k},{'publish_nested','publish_identity'}))
            assert(isequal(namesOf(alev4_demo_fault.destination),{'foreign'}));
            assert(strcmp(fileread(fullfile(alev4_demo_fault.destination,'foreign')),'foreign destination sentinel'));
        else, assert(~alev4.bundlePathExists(alev4_demo_fault.destination)); end
        if strcmp(modes{k},'publish_identity'), assert(rmdir(alev4_demo_fault.relocated,'s')); end
        assert(strcmp(fileread(s.sentinel),'preserve parent sentinel'));
    end
    m=struct('case_count',numel(modes),'modes',{modes},'publication_sentinels_preserved_and_bad_success_removed',true);
end

function [s,guard] = faultScope(folder,inventory)
    global alev4_demo_fault;
    parent=fullfile(folder,'faults'); assert(mkdir(parent));
    shadow=fullfile(parent,'shadow'); assert(mkdir(shadow)); assert(mkdir(fullfile(shadow,'+alev4')));
    sentinel=fullfile(parent,'sentinel'); writeBytes(sentinel,uint8('preserve parent sentinel'));
    old_path=path; old_warning=warning('query','all');
    alev4_demo_fault=struct('inventory',inventory,'mkdir',@mkdir,'movefile',@movefile,'which',@which);
    s=struct('parent',parent,'base',fullfile(parent,'controlled_stage'),'stage',fullfile(parent,'controlled_stage.phase4-demo-stage'),'sentinel',sentinel);
    sources=faultSources(); names=fieldnames(sources);
    for k=1:numel(names), writeBytes(fullfile(shadow,[names{k} '.m']),uint8(sprintf(sources.(names{k})))); end
    packages=packageSources(); names=fieldnames(packages);
    for k=1:numel(names), writeBytes(fullfile(shadow,'+alev4',[names{k} '.m']),uint8(sprintf(packages.(names{k})))); end
    guard=onCleanup(@()restoreFaultScope(old_path,old_warning));
    warning('off','Octave:shadowed-function'); warning('off','ALEV4:Phase4DemoCleanup');
    addpath(shadow,'-begin'); clearFaultFunctions();
    assert(strcmp(which('alev4.phase4Fixtures'),fullfile(shadow,'+alev4','phase4Fixtures.m')));
end

function resetFault(s,label,mode,target)
    global alev4_demo_fault;
    assert(~alev4.bundlePathExists(s.stage));
    alev4_demo_fault.parent=s.parent; alev4_demo_fault.base=s.base; alev4_demo_fault.stage=s.stage;
    alev4_demo_fault.destination=fullfile(s.parent,['output_' label]);
    alev4_demo_fault.relocated=fullfile(s.parent,['relocated_' label]);
    alev4_demo_fault.mode=mode; alev4_demo_fault.target=target; alev4_demo_fault.missing='';
    for name={'generations','exports','reads','publications','incomplete_checks','complete_checks'}
        alev4_demo_fault.(name{1})=0;
    end
end

function assertNoOwnedOutput(s)
    global alev4_demo_fault;
    assert(~alev4.bundlePathExists(s.stage) && ~alev4.bundlePathExists(alev4_demo_fault.destination));
    assert(strcmp(fileread(s.sentinel),'preserve parent sentinel'));
end

function sources = packageSources()
    sources=struct();
    sources.phase4Fixtures=['function value=phase4Fixtures()\n' ...
        'global alev4_demo_fault; alev4_demo_fault.generations=alev4_demo_fault.generations+1; value=alev4_demo_fault.inventory;\nend\n'];
    sources.exportStructuredBundle=['function files=exportStructuredBundle(result,directory)\n' ...
        'global alev4_demo_fault; alev4_demo_fault.exports=alev4_demo_fault.exports+1; k=alev4_demo_fault.exports; demoFaultCheck();\n' ...
        'assert(isequal(result,alev4_demo_fault.inventory.results{k})); assert(alev4_demo_fault.mkdir(directory));\n' ...
        'fid=fopen(fullfile(directory,''artificial-owned-file''),''wb''); fwrite(fid,uint8(''artificial orchestration fixture''),''uint8''); fclose(fid);\n' ...
        'if k==alev4_demo_fault.target && strcmp(alev4_demo_fault.mode,''export_replace''), demoFaultReplace(); end\n' ...
        'if k==alev4_demo_fault.target && strcmp(alev4_demo_fault.mode,''export_fail''), error(''ALEV4:InjectedDemoExporter'',''Owned test exporter failed.''); end\n' ...
        'files=struct(''directory'',directory);\nend\n'];
    sources.readStructuredBundle=['function value=readStructuredBundle(directory)\n' ...
        'global alev4_demo_fault; alev4_demo_fault.reads=alev4_demo_fault.reads+1; k=alev4_demo_fault.reads; demoFaultCheck();\n' ...
        'assert(exist(fullfile(directory,''artificial-owned-file''),''file'')==2); value=alev4_demo_fault.inventory.results{k};\n' ...
        'if k~=alev4_demo_fault.target, return; end\n' ...
        'switch alev4_demo_fault.mode\n' ...
        'case ''reader_fail'', error(''ALEV4:InjectedDemoReader'',''Owned test reader failed.'');\n' ...
        'case ''reader_mismatch'', value.seeds.frame=value.seeds.frame+1;\n' ...
        'case ''reader_missing'', value=rmfield(value,''components'');\n' ...
        'case ''reader_nonscalar'', value=[value value];\n' ...
        'case ''reader_replace'', demoFaultReplace();\nend\nend\n'];
end

function sources = faultSources()
    sources=struct();
    sources.demoFaultCheck=['function demoFaultCheck()\n' ...
        'global alev4_demo_fault; s=jsondecode(fileread(fullfile(alev4_demo_fault.stage,''phase4-demo-summary.json'')));\n' ...
        'assert(strcmp(s.status,''in_progress'') && ~s.demo_complete && ~s.export_readback_complete);\n' ...
        'assert(~s.release_accepted && ~s.calibrated && s.exported_frame_count==0 && s.verified_frame_count==0);\n' ...
        'assert(~any([s.frames.export_complete]) && ~any([s.frames.readback_verified]));\n' ...
        'alev4_demo_fault.incomplete_checks=alev4_demo_fault.incomplete_checks+1;\nend\n'];
    sources.demoFaultReplace=['function demoFaultReplace()\n' ...
        'global alev4_demo_fault; assert(alev4_demo_fault.movefile(alev4_demo_fault.stage,alev4_demo_fault.relocated));\n' ...
        'assert(alev4_demo_fault.mkdir(alev4_demo_fault.stage)); fid=fopen(fullfile(alev4_demo_fault.stage,''foreign''),''wb'');\n' ...
        'fwrite(fid,uint8(''foreign stage sentinel''),''uint8''); fclose(fid); error(''ALEV4:InjectedDemoReplacement'',''Owned test stage replaced.'');\nend\n'];
    sources.which=['function varargout=which(varargin)\n' ...
        'global alev4_demo_fault; if nargin==1 && isfield(alev4_demo_fault,''missing'') && strcmp(varargin{1},alev4_demo_fault.missing), varargout={''''}; return; end\n' ...
        '[varargout{1:nargout}]=alev4_demo_fault.which(varargin{:});\nend\n'];
    sources.tempname=['function name=tempname(varargin)\n' ...
        'global alev4_demo_fault; assert(nargin==1 && strcmp(varargin{1},alev4_demo_fault.parent)); name=alev4_demo_fault.base;\nend\n'];
    sources.mkdir=['function [ok,message,messageid]=mkdir(varargin)\n' ...
        'global alev4_demo_fault; [ok,message,messageid]=alev4_demo_fault.mkdir(varargin{:});\n' ...
        'if strcmp(alev4_demo_fault.mode,''ambiguous_mkdir'') && nargin==1 && strcmp(varargin{1},alev4_demo_fault.stage)\n' ...
        'fid=fopen(fullfile(varargin{1},''foreign''),''wb''); fwrite(fid,uint8(''foreign stage sentinel''),''uint8''); fclose(fid); message=''directory exists''; messageid=''mkdir''; end\nend\n'];
    sources.movefile=['function [ok,message]=movefile(source,destination,varargin)\n' ...
        'global alev4_demo_fault; assert(strcmp(source,alev4_demo_fault.stage));\n' ...
        'alev4_demo_fault.publications=alev4_demo_fault.publications+1; s=jsondecode(fileread(fullfile(source,''phase4-demo-summary.json'')));\n' ...
        'assert(alev4_demo_fault.exports==24 && alev4_demo_fault.reads==24 && s.demo_complete && s.export_readback_complete && strcmp(s.status,''complete''));\n' ...
        'assert(s.exported_frame_count==24 && s.verified_frame_count==24 && all([s.frames.export_complete]) && all([s.frames.readback_verified]));\n' ...
        'alev4_demo_fault.complete_checks=alev4_demo_fault.complete_checks+1; mode=alev4_demo_fault.mode;\n' ...
        'if strcmp(mode,''publish_fail''), ok=false; message=''injected publication failure''; return; end\n' ...
        'if any(strcmp(mode,{''publish_nested'',''publish_identity''}))\n' ...
        'assert(alev4_demo_fault.mkdir(destination)); fid=fopen(fullfile(destination,''foreign''),''wb''); fwrite(fid,uint8(''foreign destination sentinel''),''uint8''); fclose(fid);\n' ...
        'if strcmp(mode,''publish_identity''), assert(alev4_demo_fault.movefile(source,alev4_demo_fault.relocated)); ok=true; message=''''; return; end; end\n' ...
        '[ok,message]=alev4_demo_fault.movefile(source,destination,varargin{:});\n' ...
        'if strcmp(mode,''publish_corrupt_summary''), fid=fopen(fullfile(destination,''phase4-demo-summary.json''),''wb''); fwrite(fid,uint8(''forged complete summary''),''uint8''); fclose(fid); end\nend\n'];
end

function clearFaultFunctions()
    clear tempname mkdir movefile which demoFaultCheck demoFaultReplace;
    clear('alev4.phase4Fixtures','alev4.exportStructuredBundle','alev4.readStructuredBundle');
    rehash;
end

function restoreFaultScope(old_path,old_warning)
    path(old_path); clearFaultFunctions(); warning(old_warning); clear global alev4_demo_fault;
end

function reject(action,identifier)
    before=rng; handles=fopen('all'); caught=false;
    try, action(); catch err
        caught=true;
        if ~isempty(identifier), assert(strncmp(err.identifier,identifier,numel(identifier)),[err.identifier ': ' err.message]); end
    end
    assert(caught,'Expected demo rejection.'); assert(isequal(before,rng) && isequal(handles,fopen('all')));
end

function names = namesOf(directory)
    entries=dir(directory); names={entries.name}; names=sort(names(~ismember(names,{'.','..'})));
end

function bytes = readBytes(file)
    fid=fopen(file,'rb'); assert(fid>=0); guard=onCleanup(@()closeQuietly(fid)); %#ok<NASGU>
    bytes=fread(fid,Inf,'*uint8'); assert(fclose(fid)==0);
end

function writeBytes(file,bytes)
    fid=fopen(file,'wb'); assert(fid>=0); guard=onCleanup(@()closeQuietly(fid)); %#ok<NASGU>
    assert(fwrite(fid,bytes,'uint8')==numel(bytes)); assert(fclose(fid)==0);
end

function closeQuietly(fid)
    try, fclose(fid); catch, end
end

function removeFolder(folder,marker)
    if exist(marker,'file')==2 && strcmp(fileread(marker),'phase4-demo-test'), assert(rmdir(folder,'s')); end
end

function makeSymlink(source,destination)
    if exist('symlink','builtin') || exist('symlink','file')
        [status,message]=symlink(source,destination); assert(status==0,message);
    elseif (exist('usejava','builtin') || exist('usejava','file')) && usejava('jvm')
        from=javaObject('java.io.File',source); to=javaObject('java.io.File',destination);
        javaMethod('createSymbolicLink','java.nio.file.Files',to.toPath(),from.toPath(),javaArray('java.nio.file.attribute.FileAttribute',0));
    else, error('ALEV4:TestFilesystemCapability','Demo tests require symbolic-link support.'); end
end
