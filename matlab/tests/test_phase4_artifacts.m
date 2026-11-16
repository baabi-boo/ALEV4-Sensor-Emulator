function report = test_phase4_artifacts()
%TEST_PHASE4_ARTIFACTS Complete native typed-tree integrity and ownership gates.
%   All fixtures are generated here. No ignored demo/development output is
%   required. Fault injection affects only files below an owned temporary
%   directory, and restores the MATLAB path, warning state and caller RNG.
    caller_rng = rng; rng_guard = onCleanup(@()rng(caller_rng)); %#ok<NASGU>
    [folder,folder_guard] = ownFolder(); %#ok<NASGU>
    context = struct('folder',folder);
    names = {'enabled_single_dual_core_and_spatial_exact_roundtrips', ...
        'singleton_scalar_full_grid_map_and_empty_metadata_shapes', ...
        'independent_asymmetric_2x3x4_c_order_little_endian_bytes', ...
        'strict_native_producer_validation_before_publication', ...
        'rehashed_maps_expectations_charge_and_well_semantic_corruptions', ...
        'rehashed_electronics_adc_and_observed_merge_corruptions', ...
        'complete_spatial_analog_and_report_history_corruptions', ...
        'strict_typed_fields_shapes_classes_and_role_units', ...
        'contiguous_offsets_lengths_totals_and_no_padding', ...
        'malformed_json_wire_kinds_duplicates_and_unicode_boundaries', ...
        'source_runtime_flags_and_unknown_metadata', ...
        'payload_hash_truncation_logical_and_nonfinite_bytes', ...
        'exact_inventory_missing_extra_symlink_hardlink_entries', ...
        'canonical_paths_symlink_ancestors_and_refuse_existing', ...
        'caller_rng_and_distinct_repeat_artifacts', ...
        'supported_stochastic_alternate_without_seed_replay', ...
        'staging_collision_and_ambiguous_creation_preserve_preexisting', ...
        'injected_midwrite_failure_owned_cleanup', ...
        'injected_publication_failure_foreign_and_replaced_identity', ...
        'injected_read_and_write_close_failure_propagation'};
    functions = {@testShapes,@testBytes,@testProducer,@testChargeCorruption, ...
        @testElectronicCorruption,@testSpatialCorruption,@testTypedDescriptors, ...
        @testSegments,@testJson,@testMetadata,@testPayload,@testInventory, ...
        @testPaths,@testRngRepeat,@testStochasticBoundary,@testStageCollisions, ...
        @testMidwrite,@testPublication,@testCloseFailures};
    [metrics{1},context] = testRoundTrips(context); %#ok<AGROW>
    for k = 1:numel(functions)
        metrics{k+1} = functions{k}(context); %#ok<AGROW>
    end
    tests = repmat(struct('name','','status','passed','passed',true),1,numel(names));
    counts = zeros(1,numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; counts(k) = metrics{k}.case_count; end
    report = struct('suite','phase4_artifacts','status','passed','passed',true, ...
        'test_count',numel(names),'tests',tests,'metrics',struct( ...
        'case_count',sum(counts),'group_case_counts',counts,'groups',{metrics}, ...
        'binary_order','C row-major, IEEE-754 little-endian', ...
        'fixtures_generated_in_owned_temporary_directories',true, ...
        'stochastic_seed_origin_claimed',false,'synthetic',true,'calibrated_alev4',false));
    fprintf('PASS: Phase 4 native artifacts, %d groups, %d cases.\n',numel(names),sum(counts));
end

function [metrics,c] = testRoundTrips(c)
    keys = {'core_single','core_dual','spatial_single','spatial_dual','quiet_dual'};
    modes = {'single','dual','single','dual','dual'};
    stages = {'core','core','post_optics','pre_psf','core'};
    noisy = [false true true true false];
    c.base = struct(); leaves = 0;
    for k = 1:numel(keys)
        result = fixture(modes{k},stages{k},[2 3],4,noisy(k),k~=1);
        directory = fullfile(c.folder,keys{k}); before = rng; handles = fopen('all');
        files = alev4.exportStructuredBundle(result,directory);
        [actual,meta] = alev4.readStructuredBundle(directory);
        assert(isequal(result,actual) && isequal(fieldnames(result),fieldnames(actual)));
        assertNativeSame(result,actual);
        assert(strcmp(files.directory,directory) && strcmp(files.metadata,fullfile(directory,'structured.json')));
        assert(strcmp(files.payload,fullfile(directory,'data.bin')));
        assert(isequal(namesOf(directory),{'data.bin','structured.json'}));
        bytes = readBytes(files.payload);
        [endpoint,samples,count] = auditTree(meta.result,result,'result',bytes,0);
        assert(endpoint==numel(bytes) && endpoint==meta.payload.byte_count && samples==meta.payload.sample_count);
        assert(strcmp(sha256(bytes),meta.payload.sha256)); leaves = leaves+count;
        assert(isequal(before,rng) && isequal(handles,fopen('all')));
        c.base.(keys{k}) = struct('result',result,'meta',meta,'bytes',bytes, ...
            'text',readBytes(files.metadata),'directory',directory);
        if k==3 || k==4
            assert(isequal(actual.spatial_baseline,result.spatial_baseline));
            if strcmp(modes{k},'single'), analog=actual.spatial_baseline.readout.read_electrons;
            else, analog=actual.spatial_baseline.readout.high_gain.read_electrons; end
            assert(any(analog(:)~=actual.spatial_baseline.readout.charge_electrons(:)));
        end
    end
    assert(isscalar(c.base.core_single.result.noise_model.prnu));
    assert(isequal(size(c.base.core_dual.result.noise_model.prnu),[4 5]));
    metrics = struct('case_count',numel(keys),'fixtures',{keys},'exact_numeric_leaf_checks',leaves);
end

function metrics = testShapes(c)
    shapes = {[1 1],[1 3],[2 1]}; count = 0;
    for k = 1:numel(shapes)
        for mode = {'single','dual'}
            r = fixture(mode{1},'core',shapes{k},1,true,false);
            directory=fullfile(c.folder,sprintf('shape_%d_%s',k,mode{1}));
            alev4.exportStructuredBundle(r,directory);
            actual=alev4.readStructuredBundle(directory);
            assertNativeSame(r,actual);
            assert(isequal(r,actual) && isequal(size(actual.input_irradiance),shapes{k})); count=count+1;
        end
    end
    r=c.base.spatial_single.result;
    r.spatial_baseline.spatial_provenance=struct('z_last',[0 -1/Inf realmin eps(0) -eps(0) pi], ...
        'empty00',zeros(0,0),'empty10',zeros(1,0),'empty01',zeros(0,1), ...
        'empty_char00',char(zeros(0,0)), ...
        'column',[1;2;3],'row',[1 2 3],'a_first',true);
    directory=fullfile(c.folder,'native_empty_shapes'); alev4.exportStructuredBundle(r,directory);
    [actual,meta]=alev4.readStructuredBundle(directory);
    assertNativeSame(r,actual);
    assert(isequal(r,actual));
    assert(isequal(fieldnames(r.spatial_baseline.spatial_provenance),fieldnames(actual.spatial_baseline.spatial_provenance)));
    assert(isequal(num2hex(r.spatial_baseline.spatial_provenance.z_last), ...
        num2hex(actual.spatial_baseline.spatial_provenance.z_last)));
    node=getNode(meta,'spatial_baseline.spatial_provenance.empty10');
    assert(isequal(node.shape,[1 0]) && node.byte_count==0 && strcmp(node.units,'metadata'));
    metrics=struct('case_count',count+1,'singleton_roundtrips',count,'signed_zero_and_subnormal_metadata_exact',true);
end

function metrics = testBytes(c)
    base=c.base.core_single; node=getNode(base.meta,'input_irradiance');
    expected=zeros(192,1,'uint8'); position=1; values=zeros(1,24); q=1;
    % This loop deliberately does not use permute/reshape on the source.
    for row=1:2
        for column=1:3
            for band=1:4
                value=100*row+10*column+band; values(q)=value; q=q+1;
                word=num2hex(value);
                for byte=1:8
                    start=17-2*byte; expected(position)=uint8(hex2dec(word(start:start+1))); position=position+1;
                end
            end
        end
    end
    assert(isequal(node.shape,[2 3 4]) && node.byte_count==192);
    assert(isequal(segment(base.bytes,node),expected));
    assert(isequal(values,[111:114 121:124 131:134 211:214 221:224 231:234]));
    assert(isequal(expected(1:8),uint8([0;0;0;0;0;192;91;64])));
    assert(isequal(scalarBytes(-1,'double'),uint8([0;0;0;0;0;0;240;191])));
    assert(isequal(scalarBytes(eps(0),'double'),uint8([1;0;0;0;0;0;0;0])));
    assert(isequal(scalarBytes(uint16(513),'uint16'),uint8([1;2])));
    assert(strcmp(sha256(uint8([0;1;127;128;255;0])), ...
        '39f8490195555de4f9ffa74f39874d7e5828c184e08bbde1d63a61545cf34b7b'));
    metrics=struct('case_count',5,'cube_shape',[2 3 4],'independent_input_values',24,'payload_bytes',192);
end

function metrics = testProducer(c)
    base=c.base.quiet_dual.result; bad={}; labels={};
    paths={'baseline_expected_electrons','active_maps.prnu','readout.expected_electrons', ...
        'readout.charge_electrons','components.shared.total_e','readout.high_gain.raw_dn','seeds.photo'};
    for k=1:numel(paths)
        value=getNative(base,paths{k}); value(1)=value(1)+1;
        bad{end+1}=setNative(base,paths{k},value); labels{end+1}=paths{k}; %#ok<AGROW>
    end
    r=base; r.foreign=1; bad{end+1}=r; labels{end+1}='unknown_root';
    r=rmfield(base,'components'); bad{end+1}=r; labels{end+1}='missing_components';
    r=base; r.configuration.foreign=1; bad{end+1}=r; labels{end+1}='unknown_configuration';
    r=base; r.noise_model.foreign=1; bad{end+1}=r; labels{end+1}='unknown_model';
    r=base; r.input_irradiance=uint16(r.input_irradiance); bad{end+1}=r; labels{end+1}='wrong_input_class';
    r=base; r.readout.high_gain.raw_dn=double(r.readout.high_gain.raw_dn); bad{end+1}=r; labels{end+1}='wrong_raw_class';
    r=base; r.synthetic=1; bad{end+1}=r; labels{end+1}='numeric_boolean';
    r=base; r.baseline_expected_electrons=sparse(r.baseline_expected_electrons); bad{end+1}=r; labels{end+1}='sparse_science';
    r=base; r.input_irradiance(1)=complex(1,1); bad{end+1}=r; labels{end+1}='complex_science';
    r=base; r.input_irradiance(1)=NaN; bad{end+1}=r; labels{end+1}='nonfinite_science';
    r=base; r.components.shared.row_e=r.components.shared.row_e.'; bad{end+1}=r; labels{end+1}='wrong_row_shape';
    r=base; r.noise_model.enabled=false; bad{end+1}=r; labels{end+1}='disabled_result';
    r=base; r.result_kind='sequence'; bad{end+1}=r; labels{end+1}='sequence_envelope';
    r=c.base.spatial_dual.result; r=rmfield(r,'spatial_baseline'); bad{end+1}=r; labels{end+1}='missing_spatial_history';
    r=c.base.spatial_single.result; r.spatial_baseline.readout.read_electrons(1)=r.spatial_baseline.readout.read_electrons(1)+100;
    bad{end+1}=r; labels{end+1}='corrupt_spatial_analog';
    r=c.base.spatial_single.result; r.spatial_baseline.spatial_provenance.bad=['a' char(0) 'b'];
    bad{end+1}=r; labels{end+1}='nul_before_publication';
    r=c.base.spatial_single.result; nested=struct('value',1);
    for k=1:25, nested=struct('nested',nested); end
    r.spatial_baseline.spatial_provenance=nested; bad{end+1}=r; labels{end+1}='typed_tree_depth_bound';
    r=c.base.spatial_single.result; r.spatial_baseline.spatial_provenance=struct();
    for k=1:257, r.spatial_baseline.spatial_provenance.(sprintf('field_%03d',k))=1; end
    bad{end+1}=r; labels{end+1}='metadata_field_bound';
    r=c.base.spatial_single.result; r.spatial_baseline.spatial_provenance.empty_char10=char(zeros(1,0));
    bad{end+1}=r; labels{end+1}='unsupported_legacy_provenance_char_orientation';
    parent=fullfile(c.folder,'producer_rejections'); assert(mkdir(parent));
    writeBytes(fullfile(parent,'sentinel'),uint8('keep producer parent'));
    before=namesOf(parent);
    for k=1:numel(bad)
        destination=fullfile(parent,sprintf('invalid_%d',k));
        reject(@()alev4.exportStructuredBundle(bad{k},destination),labels{k});
        assert(~alev4.bundlePathExists(destination) && isequal(namesOf(parent),before));
    end
    assert(strcmp(fileread(fullfile(parent,'sentinel')),'keep producer parent'));
    metrics=struct('case_count',numel(bad),'rejected_before_any_stage_or_destination',true,'cases',{labels});
end

function metrics = testChargeCorruption(c)
    paths={'input_irradiance','baseline_expected_electrons','active_maps.prnu', ...
        'active_maps.dark_current_e_per_s','readout.expected_photoelectrons', ...
        'readout.expected_dark_electrons','readout.expected_electrons','readout.expected_incident_photons', ...
        'components.photo_electrons','components.dark_electrons','readout.collected_electrons', ...
        'readout.charge_electrons','readout.full_well_saturated'};
    count=rejectChanges(c,'quiet_dual','charge',paths);
    for path={'noise_model.prnu','noise_model.dark_current_e_per_s'}
        value=getNative(c.base.quiet_dual.result,path{1}); value(2,2)=value(2,2)+1;
        rejectPatched(c,'quiet_dual',['full_' path{1}],path{1},value); count=count+1;
    end
    metrics=struct('case_count',count,'hash_recomputed_for_every_case',true,'cases',{paths});
end

function metrics = testElectronicCorruption(c)
    paths={'active_maps.shared.fixed_offset_e','components.shared.fixed_offset_e', ...
        'components.shared.row_e','components.shared.column_e','components.shared.frame_e', ...
        'components.shared.pixel_e','components.shared.total_e', ...
        'components.high_gain.row_e','components.high_gain.column_e','components.high_gain.frame_e', ...
        'components.high_gain.pixel_e','components.high_gain.total_e','components.low_gain.total_e', ...
        'readout.high_gain.read_electrons','readout.low_gain.read_electrons', ...
        'readout.high_gain.raw_dn','readout.low_gain.raw_dn', ...
        'readout.high_gain.adc_low_clipped','readout.high_gain.adc_high_clipped','readout.high_gain.adc_usable', ...
        'readout.reconstruction_valid','readout.merged.electrons','readout.merged.weight_high', ...
        'readout.merged.valid','readout.merged.high_usable','readout.merged.low_usable'};
    count=rejectChanges(c,'core_dual','electronics',paths);
    count=count+rejectChanges(c,'core_single','single_electronics', ...
        {'components.single.total_e','readout.read_electrons','readout.raw_dn','readout.adc_usable'});
    metrics=struct('case_count',count,'hash_recomputed_for_every_case',true,'observed_merge_checked',true);
end

function metrics = testSpatialCorruption(c)
    paths={'spatial_baseline.input_irradiance','spatial_baseline.optical_irradiance', ...
        'spatial_baseline.sampled_irradiance','spatial_baseline.input_grid.x_edges_m', ...
        'spatial_baseline.optical_grid.y_edges_m','spatial_baseline.psf.kernel', ...
        'spatial_baseline.optical_report.retained_row_indices', ...
        'spatial_baseline.sampling_report.source_integral.values', ...
        'spatial_baseline.sampling_report.target_integral.values', ...
        'spatial_baseline.readout.expected_electrons','spatial_baseline.readout.collected_electrons', ...
        'spatial_baseline.readout.charge_electrons','spatial_baseline.readout.full_well_saturated', ...
        'spatial_baseline.readout.high_gain.read_electrons','spatial_baseline.readout.low_gain.read_electrons', ...
        'spatial_baseline.readout.high_gain.raw_dn','spatial_baseline.readout.high_gain.adc_high_clipped', ...
        'spatial_baseline.readout.merged.electrons','spatial_baseline.readout.merged.weight_high', ...
        'spatial_baseline.readout.reconstruction_valid'};
    count=rejectChanges(c,'spatial_dual','spatial_history',paths);
    count=count+rejectChanges(c,'spatial_single','spatial_single_history', ...
        {'spatial_baseline.readout.read_electrons','spatial_baseline.readout.raw_dn'});
    [directory,meta]=newCase(c,'spatial_single','spatial_empty_orientation');
    node=getNode(meta,'spatial_baseline.psf'); node.shape=[1 0]; meta=setNode(meta,'spatial_baseline.psf',node);
    writeMeta(directory,meta); reject(@()alev4.readStructuredBundle(directory),'post-optics empty orientation');
    metrics=struct('case_count',count+1,'complete_legacy_history_verified',true);
end

function metrics = testTypedDescriptors(c)
    changes={{'kind','foreign'},{'class','single'},{'shape',[3 2 4]}, ...
        {'shape',[2 3 4 1]},{'shape',[2 3 1]},{'shape',[2 -3 4]}, ...
        {'shape',[2 3.5 4]},{'shape',[0 1e8 2]},{'units','photons'}, ...
        {'foreign',1}};
    count=0;
    for k=1:numel(changes)
        [directory,meta]=newCase(c,'core_single',sprintf('descriptor_%d',k));
        node=getNode(meta,'input_irradiance'); change=changes{k}; node.(change{1})=change{2};
        meta=setNode(meta,'input_irradiance',node); writeMeta(directory,meta);
        reject(@()alev4.readStructuredBundle(directory),sprintf('typed descriptor %d',k)); count=count+1;
    end
    for field={'kind','class','shape','offset','byte_count','units'}
        [directory,meta]=newCase(c,'core_single',['missing_descriptor_' field{1}]);
        node=rmfield(getNode(meta,'input_irradiance'),field{1}); meta=setNode(meta,'input_irradiance',node);
        writeMeta(directory,meta); reject(@()alev4.readStructuredBundle(directory),['missing ' field{1}]); count=count+1;
    end
    paths={'configuration.sensor.pixel_pitch_m','configuration.sensor.wavelength_nm', ...
        'configuration.high_gain.gain_dn_per_e','configuration.high_gain.black_level_dn', ...
        'configuration.high_gain.adc_bits','noise_model.dark_current_e_per_s', ...
        'noise_model.reference_temperature_K','readout.expected_incident_photons', ...
        'readout.exposure_s','seeds.photo','readout.high_gain.raw_dn','readout.high_gain.adc_usable', ...
        'geometry.active_roi','active_maps.prnu','readout.charge_electrons'};
    expected={'m','nm','DN electron^-1','DN','bits','electrons s^-1','K','photons', ...
        's','seed','DN','logical','index/count','dimensionless','electrons'};
    for k=1:numel(paths)
        [directory,meta]=newCase(c,'core_dual',sprintf('role_units_%d',k)); node=getNode(meta,paths{k});
        assert(strcmp(node.units,expected{k})); node.units=[node.units '_wrong'];
        meta=setNode(meta,paths{k},node); writeMeta(directory,meta);
        reject(@()alev4.readStructuredBundle(directory),['units ' paths{k}]); count=count+1;
    end
    for path={'operation_order','noise_model.parameter_sources'}
        [directory,meta]=newCase(c,'core_single',['cell_order_' path{1}]); node=getNode(meta,path{1});
        keys=fieldnames(node.items); node.items=orderfields(node.items,[2 1 3:numel(keys)]);
        meta=setNode(meta,path{1},node); writeMeta(directory,meta);
        reject(@()alev4.readStructuredBundle(directory),['nonlinear cell order ' path{1}]); count=count+1;
    end
    for path={'baseline_expected_electrons','readout.raw_dn'}
        r=c.base.core_single.result; value=getNative(r,path{1});
        if isa(value,'double'), value=uint16(value); else, value=double(value); end
        r=setNative(r,path{1},value); directory=writeNativeUnchecked(c,'core_single',['native_class_' path{1}],r);
        reject(@()alev4.readStructuredBundle(directory),['valid wire class, wrong scientific class ' path{1}]); count=count+1;
    end
    metrics=struct('case_count',count,'independent_unit_roles',numel(paths),'unknown_and_missing_descriptor_fields',true);
end

function metrics = testSegments(c)
    count=0; changes={{'offset',1},{'offset',-1},{'offset',.5},{'byte_count',0},{'byte_count',191},{'byte_count',193}};
    for k=1:numel(changes)
        [directory,meta]=newCase(c,'core_single',sprintf('segment_%d',k)); node=getNode(meta,'input_irradiance');
        change=changes{k}; node.(change{1})=change{2}; meta=setNode(meta,'input_irradiance',node); writeMeta(directory,meta);
        reject(@()alev4.readStructuredBundle(directory),sprintf('segment %d',k)); count=count+1;
    end
    for field={'byte_count','sample_count'}
        for delta=[-1 1]
            [directory,meta]=newCase(c,'core_single',sprintf('totals_%s_%d',field{1},delta));
            meta.payload.(field{1})=meta.payload.(field{1})+delta; writeMeta(directory,meta);
            reject(@()alev4.readStructuredBundle(directory),'payload totals'); count=count+1;
        end
    end
    [directory,meta,bytes]=newCase(c,'core_single','rehashed_padding'); bytes=[bytes;uint8(0)];
    meta.payload.byte_count=numel(bytes); writePayload(directory,meta,bytes);
    reject(@()alev4.readStructuredBundle(directory),'rehashed trailing padding'); count=count+1;
    [directory,meta]=newCase(c,'core_single','first_offset_gap'); node=getNode(meta,'configuration.image_size');
    assert(node.offset==0); node.offset=1; meta=setNode(meta,'configuration.image_size',node); writeMeta(directory,meta);
    reject(@()alev4.readStructuredBundle(directory),'first payload gap'); count=count+1;
    metrics=struct('case_count',count,'contiguous_no_padding_contract',true);
end

function metrics = testJson(c)
    base=c.base.core_single; original=char(base.text(:).');
    bad={['{"format":"foreign",' original(2:end)], ...
        strrep(original,'"synthetic":true','"synthetic":1'), ...
        strrep(original,'"synthetic":true','"synthetic":[true]'), ...
        strrep(original,'"wire_version":"typed-tree-v1"','"wire_version":1'), ...
        strrep(original,'"kind":"numeric"','"kind":["numeric"]'), ...
        strrep(original,'"shape":[2,3,4]','"shape":[[2,3,4]]'), ...
        strrep(original,'"offset":0','"offset":[0]'), ...
        strrep(original,'"offset":0','"offset":false'), ...
        strrep(original,'"offset":0','"offset":null'), ...
        strrep(original,'"offset":0','"offset":01'), ...
        strrep(original,'"offset":0','"offset":1e999'), ...
        strrep(original,'"offset":0','"offset":1e-999'), ...
        strrep(original,'"kind":"struct"','"kind":"struct",'), ...
        [original '{}'],original(1:end-3), ...
        strrep(original,'typed-tree-v1','typed\u0000tree-v1'), ...
        strrep(original,'typed-tree-v1','\uD800'), ...
        strrep(original,'typed-tree-v1','\uDC00'), ...
        strrep(original,'"wire_version"','"wire-version"'), ...
        strrep(original,'"wire_version"','"while"')};
    for k=1:numel(bad)
        assert(~strcmp(bad{k},original),sprintf('JSON mutation %d did not change bytes.',k));
        directory=newCase(c,'core_single',sprintf('json_%d',k));
        writeBytes(fullfile(directory,'structured.json'),unicode2native(bad{k},'UTF-8'));
        reject(@()alev4.readStructuredBundle(directory),sprintf('JSON mutation %d',k));
    end
    directory=newCase(c,'core_single','json_invalid_utf8'); bytes=base.text; bytes(2)=uint8(255);
    writeBytes(fullfile(directory,'structured.json'),bytes); reject(@()alev4.readStructuredBundle(directory),'invalid UTF-8');
    r=c.base.spatial_single.result;
    label=native2unicode(uint8([195 169 240 159 153 130]),'UTF-8');
    r.spatial_baseline.spatial_provenance.unicode_label=label;
    directory=fullfile(c.folder,'unicode_positive'); alev4.exportStructuredBundle(r,directory);
    actual=alev4.readStructuredBundle(directory); assert(isequal(actual,r));
    meta=wireManifest(directory); node=getNode(meta,'spatial_baseline.spatial_provenance.unicode_label');
    escaped=char(readBytes(fullfile(directory,'structured.json')).');
    escaped=strrep(escaped,label,'\u00e9\uD83D\uDE42');
    writeBytes(fullfile(directory,'structured.json'),unicode2native(escaped,'UTF-8'));
    assertNativeSame(r,alev4.readStructuredBundle(directory));
    assert(isequal(node.shape,size(label))); node.shape=[1 numel(label)+1];
    meta=setNode(meta,'spatial_baseline.spatial_provenance.unicode_label',node); writeMeta(directory,meta);
    reject(@()alev4.readStructuredBundle(directory),'Unicode native extent mismatch');
    directory=newCase(c,'core_single','json_oversized');
    writeBytes(fullfile(directory,'structured.json'),repmat(uint8(32),2000001,1));
    reject(@()alev4.readStructuredBundle(directory),'manifest byte bound');
    metrics=struct('case_count',numel(bad)+5,'strict_json_negative_cases',numel(bad)+2, ...
        'native_unicode_positive_and_wrong_extent',true);
end

function metrics = testMetadata(c)
    base=c.base.core_dual; changes={{'synthetic',false},{'calibrated_alev4',true}, ...
        {'authentic_arriraw',true},{'parameter_classification','measured'},{'schema_version','2.0'}, ...
        {'byte_order','big-endian'},{'array_order','column-major'},{'foreign',1}}; count=0;
    for k=1:numel(changes)
        [directory,meta]=newCase(c,'core_dual',sprintf('manifest_flags_%d',k)); change=changes{k};
        meta.(change{1})=change{2}; writeMeta(directory,meta);
        reject(@()alev4.readStructuredBundle(directory),['manifest ' change{1}]); count=count+1;
    end
    for field={'repository_head','isetcam_head','isethdrsensor_head','meaning'}
        [directory,meta]=newCase(c,'core_dual',['source_' field{1}]);
        meta.provenance.(field{1})='NOT-A-VALID-SOURCE-OBSERVATION'; writeMeta(directory,meta);
        reject(@()alev4.readStructuredBundle(directory),['source ' field{1}]); count=count+1;
    end
    [directory,meta]=newCase(c,'core_dual','unknown_provenance'); meta.provenance.foreign=1; writeMeta(directory,meta);
    reject(@()alev4.readStructuredBundle(directory),'unknown source metadata'); count=count+1;
    for path={'runtime.name','runtime.version','seed_policy','stream_scope','parameter_classification', ...
            'temperature_condition.policy','units.charge','operation_order'}
        [directory,meta]=newCase(c,'core_dual',['result_metadata_' path{1}]); node=getNode(meta,path{1});
        if strcmp(node.kind,'cell'), node.items=rmfield(node.items,'i000001');
        elseif strcmp(path{1},'runtime.version'), node.value=' '; node.shape=[1 1];
        else, node.value='invalid'; node.shape=[1 7]; end
        meta=setNode(meta,path{1},node); writeMeta(directory,meta);
        reject(@()alev4.readStructuredBundle(directory),['result metadata ' path{1}]); count=count+1;
    end
    for path={'synthetic','calibrated_alev4'}
        rejectPatched(c,'core_dual',['result_flag_' path{1}],path{1},~getNative(base.result,path{1})); count=count+1;
    end
    for path={'','runtime','configuration','noise_model','components.shared'}
        [directory,meta]=newCase(c,'core_dual',['unknown_native_' path{1}]); node=getNode(meta,path{1});
        node.fields.foreign=struct('kind','char','shape',[1 4],'value','info');
        meta=setNode(meta,path{1},node); writeMeta(directory,meta);
        reject(@()alev4.readStructuredBundle(directory),['unknown native ' path{1}]); count=count+1;
    end
    % Portable spatial provenance is informational, and does not establish
    % randomness origin, source cleanliness or a calibration claim.
    r=c.base.spatial_single.result; r.spatial_baseline.spatial_provenance.new_information=struct('note','informational','value',42);
    r.runtime=struct('name','MATLAB','version','foreign-runtime-association-1');
    directory=fullfile(c.folder,'informational_metadata'); alev4.exportStructuredBundle(r,directory);
    [actual,meta]=alev4.readStructuredBundle(directory); assert(isequal(actual,r));
    meta.provenance.repository_head=''; meta.provenance.isetcam_head=''; meta.provenance.isethdrsensor_head='';
    writeMeta(directory,meta); assert(isequal(alev4.readStructuredBundle(directory),r));
    metrics=struct('case_count',count+2,'unknown_scientific_fields_rejected',true,'informational_provenance_allowed',true);
end

function metrics = testPayload(c)
    [directory,meta,bytes]=newCase(c,'core_single','stale_hash'); bytes(end)=bitxor(bytes(end),uint8(1));
    writeBytes(fullfile(directory,'data.bin'),bytes); reject(@()alev4.readStructuredBundle(directory),'stale payload hash');
    directory=newCase(c,'core_single','truncated_payload'); writeBytes(fullfile(directory,'data.bin'),bytes(1:end-1));
    reject(@()alev4.readStructuredBundle(directory),'truncated payload');
    [directory,meta,bytes]=newCase(c,'core_single','noncanonical_logical'); node=getNode(meta,'synthetic');
    bytes(node.offset+1)=uint8(2); writePayload(directory,meta,bytes);
    reject(@()alev4.readStructuredBundle(directory),'logical byte two');
    words={'7ff8000000000000','7ff0000000000000','fff0000000000000'};
    for k=1:numel(words)
        [directory,meta,bytes]=newCase(c,'core_single',sprintf('nonfinite_%d',k)); node=getNode(meta,'input_irradiance');
        word=words{k}; for j=1:8, start=17-2*j; bytes(node.offset+j)=uint8(hex2dec(word(start:start+1))); end
        writePayload(directory,meta,bytes); reject(@()alev4.readStructuredBundle(directory),'nonfinite payload');
    end
    for value={'../data.bin','alternate.bin','sub/data.bin'}
        [directory,meta]=newCase(c,'core_single',['payload_name_' num2str(numel(value{1}))]);
        meta.payload.name=value{1}; writeMeta(directory,meta); reject(@()alev4.readStructuredBundle(directory),'payload path');
    end
    [directory,meta]=newCase(c,'core_single','uppercase_hash'); meta.payload.sha256=upper(meta.payload.sha256); writeMeta(directory,meta);
    reject(@()alev4.readStructuredBundle(directory),'noncanonical hash spelling');
    metrics=struct('case_count',10,'rehashed_nonfinite_and_logical_cases',4);
end

function metrics = testInventory(c)
    count=0;
    for name={'data.bin','structured.json'}
        directory=newCase(c,'core_single',['missing_' name{1}]); delete(fullfile(directory,name{1}));
        reject(@()alev4.readStructuredBundle(directory),['missing ' name{1}]); count=count+1;
        directory=newCase(c,'core_single',['directory_' name{1}]); delete(fullfile(directory,name{1})); assert(mkdir(fullfile(directory,name{1})));
        reject(@()alev4.readStructuredBundle(directory),['directory payload ' name{1}]); count=count+1;
        directory=newCase(c,'core_single',['symlink_' name{1}]); path=fullfile(directory,name{1}); delete(path);
        makeSymlink(fullfile(c.base.core_single.directory,name{1}),path);
        reject(@()alev4.readStructuredBundle(directory),['symlink payload ' name{1}]); removeLink(path); count=count+1;
        directory=newCase(c,'core_single',['hardlink_' name{1}]); path=fullfile(directory,name{1});
        alias=fullfile(c.folder,['alias_' name{1}]); makeHardLink(path,alias);
        reject(@()alev4.readStructuredBundle(directory),['hardlink payload ' name{1}]); delete(alias); count=count+1;
    end
    for kind={'file','directory','dangling'}
        directory=newCase(c,'core_single',['extra_' kind{1}]); extra=fullfile(directory,'foreign');
        switch kind{1}
            case 'file', writeBytes(extra,uint8('extra'));
            case 'directory', assert(mkdir(extra));
            case 'dangling', makeSymlink(fullfile(c.folder,'absent-target'),extra);
        end
        reject(@()alev4.readStructuredBundle(directory),['extra ' kind{1}]); count=count+1;
        if strcmp(kind{1},'dangling'), removeLink(extra); end
    end
    metrics=struct('case_count',count,'single_link_ordinary_exact_inventory',true);
end

function metrics = testPaths(c)
    base=c.base.core_single; parent=fullfile(c.folder,'path_checks'); assert(mkdir(parent)); count=0;
    for kind={'directory','file','symlink','dangling'}
        destination=fullfile(parent,kind{1});
        switch kind{1}
            case 'directory', assert(mkdir(destination)); writeBytes(fullfile(destination,'sentinel'),uint8('keep existing'));
            case 'file', writeBytes(destination,uint8('keep existing'));
            case 'symlink', makeSymlink(base.directory,destination);
            case 'dangling', makeSymlink(fullfile(parent,'absent'),destination);
        end
        reject(@()alev4.exportStructuredBundle(base.result,destination),['existing ' kind{1}]);
        assert(alev4.bundlePathExists(destination)); count=count+1;
        if strcmp(kind{1},'directory'), assert(strcmp(fileread(fullfile(destination,'sentinel')),'keep existing'));
        elseif strcmp(kind{1},'file'), assert(strcmp(fileread(destination),'keep existing'));
        else, assert(isSymlink(destination)); removeLink(destination); end
    end
    aliases={[base.directory filesep], [c.folder filesep '.' filesep 'core_single'], ...
        [c.folder filesep 'absent' filesep '..' filesep 'core_single'], [c.folder filesep filesep 'core_single']};
    for k=1:numel(aliases)
        reject(@()alev4.readStructuredBundle(aliases{k}),'noncanonical read path');
        reject(@()alev4.exportStructuredBundle(base.result,aliases{k}),'noncanonical export path'); count=count+2;
    end
    link=fullfile(parent,'ancestor'); makeSymlink(c.folder,link);
    reject(@()alev4.readStructuredBundle(fullfile(link,'core_single')),'symlink read ancestor');
    reject(@()alev4.exportStructuredBundle(base.result,fullfile(link,'future_bundle')),'symlink export ancestor'); removeLink(link);
    reject(@()alev4.exportStructuredBundle(base.result,fullfile(parent,'absent','child')),'missing parent');
    assert(isequal(readBytes(fullfile(base.directory,'data.bin')),base.bytes));
    metrics=struct('case_count',count+3,'existing_bytes_preserved',true);
end

function metrics = testRngRepeat(c)
    rng(6842,'twister'); before=rng; handles=fopen('all'); base=c.base.core_dual;
    a=fullfile(c.folder,'repeat_a'); b=fullfile(c.folder,'repeat_b');
    alev4.exportStructuredBundle(base.result,a); assert(isequal(before,rng));
    rand(1,7); randn(1,11); changed=rng;
    alev4.exportStructuredBundle(base.result,b); assert(isequal(changed,rng));
    for name={'data.bin','structured.json'}
        left=fullfile(a,name{1}); right=fullfile(b,name{1});
        assert(isequal(readBytes(left),readBytes(right))); assertDistinct(left,right);
    end
    alev4.readStructuredBundle(a); assert(isequal(changed,rng));
    reject(@()alev4.exportStructuredBundle(base.result,a),'repeat refuses existing');
    reject(@()alev4.readStructuredBundle(fullfile(c.folder,'absent_bundle')),'RNG read failure');
    assert(isequal(changed,rng) && isequal(handles,fopen('all')));
    metrics=struct('case_count',5,'caller_uniform_normal_states_preserved',true,'repeat_bytes_equal_independent_identities',true);
end

function metrics = testStochasticBoundary(c)
    r=c.base.core_dual.result; original=r;
    r.components.shared.row_e=r.components.shared.row_e+[.25;-.5];
    r.components.photo_electrons(1)=r.components.photo_electrons(1)+3;
    r=reassemble(r);
    assert(~isequal(r.components,original.components) && isequal(r.seeds,original.seeds));
    assert(isequal(alev4.structuredValidateResult(r),r));
    directory=fullfile(c.folder,'alternate_supported_draw'); alev4.exportStructuredBundle(r,directory);
    assert(isequal(alev4.readStructuredBundle(directory),r));
    count=1;
    for charge_value=[-1 .5]
        bad=r; bad.components.photo_electrons(1)=charge_value; bad=reassemble(bad);
        directory=writeNativeUnchecked(c,'core_dual',sprintf('unsupported_charge_%g',charge_value),bad);
        reject(@()alev4.readStructuredBundle(directory),'coherent invalid Poisson support'); count=count+1;
    end
    zero=c.base.core_dual.result; zero.noise_model.dark_current_e_per_s=0;
    zero=alev4.simulateStructuredExposure(zero.input_irradiance,zero.configuration,zero.readout.exposure_s, ...
        zero.readout.seed,zero.noise_model,zero.geometry);
    zero.components.dark_electrons(1)=1; zero=reassemble(zero);
    directory=writeNativeUnchecked(c,'core_dual','positive_charge_at_zero_mean',zero);
    reject(@()alev4.readStructuredBundle(directory),'coherent dark charge at zero mean'); count=count+1;
    zero=c.base.quiet_dual.result; zero.components.shared.row_e(1)=.25; zero=reassemble(zero);
    directory=writeNativeUnchecked(c,'quiet_dual','nonzero_zero_rms_draw',zero);
    reject(@()alev4.readStructuredBundle(directory),'coherent nonzero zero-RMS draw'); count=count+1;
    metrics=struct('case_count',count,'legal_alternate_realization_accepted',true,'random_seed_replay_required',false, ...
        'coherent_invalid_support_rejections',count-1);
end

function metrics = testStageCollisions(c)
    [scope,guard]=faultScope(c,'stage_collisions'); %#ok<NASGU>
    global alev4_p4_fault;
    base=c.base.core_single.result; stage=[scope.base '.structured-stage']; count=0;
    for kind={'directory','file','symlink','dangling'}
        switch kind{1}
            case 'directory', assert(mkdir(stage)); writeBytes(fullfile(stage,'sentinel'),uint8('preexisting stage'));
            case 'file', writeBytes(stage,uint8('preexisting stage'));
            case 'symlink', makeSymlink(c.base.core_single.directory,stage);
            case 'dangling', makeSymlink(fullfile(scope.parent,'absent'),stage);
        end
        destination=fullfile(scope.parent,['target_' kind{1}]);
        reject(@()alev4.exportStructuredBundle(base,destination),['stage collision ' kind{1}]);
        assert(alev4.bundlePathExists(stage) && ~alev4.bundlePathExists(destination));
        switch kind{1}
            case 'directory', assert(strcmp(fileread(fullfile(stage,'sentinel')),'preexisting stage')); assert(rmdir(stage,'s'));
            case 'file', assert(strcmp(fileread(stage),'preexisting stage')); delete(stage);
            otherwise, assert(isSymlink(stage)); removeLink(stage);
        end
        count=count+1;
    end
    alev4_p4_fault.mode='ambiguous_mkdir'; destination=fullfile(scope.parent,'ambiguous');
    reject(@()alev4.exportStructuredBundle(base,destination),'ambiguous successful mkdir');
    assert(strcmp(fileread(fullfile(stage,'foreign')),'foreign creation'));
    assert(isequal(namesOf(stage),{'foreign'}) && ~alev4.bundlePathExists(destination));
    assert(rmdir(stage,'s')); count=count+1;
    alev4_p4_fault.mode='none'; destination=fullfile(scope.parent,'control');
    alev4.exportStructuredBundle(base,destination); assert(isequal(alev4.readStructuredBundle(destination),base));
    assert(~alev4.bundlePathExists(stage));
    metrics=struct('case_count',count+1,'preexisting_stages_and_ambiguous_creation_preserved',true);
end

function metrics = testMidwrite(c)
    [scope,guard]=faultScope(c,'midwrite'); %#ok<NASGU>
    global alev4_p4_fault;
    modes={'short_payload','throw_payload','short_manifest','throw_manifest', ...
        'payload_foreign','manifest_replaced'};
    for k=1:numel(modes)
        alev4_p4_fault.mode=modes{k}; alev4_p4_fault.hits=0;
        destination=fullfile(scope.parent,['target_' modes{k}]); stage=[scope.base '.structured-stage'];
        if strncmp(modes{k},'short_',6), identifier='ALEV4:StructuredWrite';
        else, identifier='ALEV4:InjectedArtifactWrite'; end
        reject(@()alev4.exportStructuredBundle(c.base.core_single.result,destination),modes{k},identifier);
        assert(alev4_p4_fault.hits==1 && ~alev4.bundlePathExists(destination));
        assert(strcmp(fileread(fullfile(scope.parent,'sentinel')),'preserve parent'));
        if strcmp(modes{k},'payload_foreign')
            assert(isequal(namesOf(stage),{'foreign'})); assert(strcmp(fileread(fullfile(stage,'foreign')),'preserve foreign'));
            assert(rmdir(stage,'s'));
        elseif strcmp(modes{k},'manifest_replaced')
            assert(isequal(namesOf(stage),{'structured.json'}));
            assert(strcmp(fileread(fullfile(stage,'structured.json')),'preserve replacement'));
            assert(rmdir(stage,'s')); delete(alev4_p4_fault.relocated);
        else, assert(~alev4.bundlePathExists(stage),[modes{k} ' left an owned stage.']); end
    end
    alev4_p4_fault.mode='payload_foreign'; alev4_p4_fault.hits=0;
    warning('error','ALEV4:StructuredCleanup');
    destination=fullfile(scope.parent,'cleanup_warning_as_error');
    reject(@()alev4.exportStructuredBundle(c.base.core_single.result,destination), ...
        'cleanup warning preserves original exception','ALEV4:InjectedArtifactWrite');
    warning('off','ALEV4:StructuredCleanup');
    assert(isequal(namesOf(stage),{'foreign'}) && ~alev4.bundlePathExists(destination));
    assert(strcmp(fileread(fullfile(stage,'foreign')),'preserve foreign')); assert(rmdir(stage,'s'));
    metrics=struct('case_count',numel(modes)+1,'injection_modes',{modes},'only_recorded_owned_files_removed',true, ...
        'cleanup_warning_cannot_hide_original_error',true);
end

function metrics = testPublication(c)
    [scope,guard]=faultScope(c,'publication'); %#ok<NASGU>
    global alev4_p4_fault;
    modes={'publish_fail','publish_foreign','publish_replace','publish_nested','publish_identity','publish_postrename'};
    for k=1:numel(modes)
        alev4_p4_fault.mode=modes{k}; alev4_p4_fault.hits=0;
        destination=fullfile(scope.parent,['target_' modes{k}]); stage=[scope.base '.structured-stage'];
        if strcmp(modes{k},'publish_postrename'), identifier='ALEV4:InvalidStructuredBundle';
        else, identifier='ALEV4:StructuredWrite'; end
        reject(@()alev4.exportStructuredBundle(c.base.core_single.result,destination),modes{k},identifier);
        assert(alev4_p4_fault.hits==1 && strcmp(fileread(fullfile(scope.parent,'sentinel')),'preserve parent'));
        switch modes{k}
            case 'publish_fail'
                assert(~alev4.bundlePathExists(stage) && ~alev4.bundlePathExists(destination));
            case 'publish_foreign'
                assert(isequal(namesOf(stage),{'foreign'})); assert(strcmp(fileread(fullfile(stage,'foreign')),'preserve foreign'));
                assert(rmdir(stage,'s'));
            case 'publish_replace'
                assert(isequal(namesOf(stage),{'data.bin'})); assert(strcmp(fileread(fullfile(stage,'data.bin')),'preserve replacement'));
                assert(rmdir(stage,'s')); delete(alev4_p4_fault.relocated);
            case 'publish_nested'
                assert(~alev4.bundlePathExists(stage)); assert(isequal(namesOf(destination),{'racer'}));
                assert(strcmp(fileread(fullfile(destination,'racer')),'preserve racer'));
            case 'publish_identity'
                assert(~alev4.bundlePathExists(stage)); assert(isequal(namesOf(destination),{'foreign'}));
                assert(strcmp(fileread(fullfile(destination,'foreign')),'preserve directory replacement'));
                assert(exist(alev4_p4_fault.relocated,'dir')==7); assert(rmdir(alev4_p4_fault.relocated,'s'));
            case 'publish_postrename'
                assert(~alev4.bundlePathExists(stage)); assert(isequal(namesOf(destination),{'foreign'}));
                assert(strcmp(fileread(fullfile(destination,'foreign')),'preserve after rename'));
        end
    end
    metrics=struct('case_count',numel(modes),'injection_modes',{modes},'foreign_and_replaced_file_or_directory_preserved',true);
end

function metrics = testCloseFailures(c)
    [scope,guard]=faultScope(c,'close_failures'); %#ok<NASGU>
    global alev4_p4_fault;
    alev4_p4_fault.mode='close_failure'; count=0;
    for target={'data.bin','structured.json'}
        alev4_p4_fault.close_target=fullfile([scope.base '.structured-stage'],target{1}); alev4_p4_fault.hits=0;
        destination=fullfile(scope.parent,['write_' target{1}]);
        reject(@()alev4.exportStructuredBundle(c.base.core_single.result,destination),['write close ' target{1}]);
        assert(alev4_p4_fault.hits==1 && ~alev4.bundlePathExists(destination));
        assert(~alev4.bundlePathExists([scope.base '.structured-stage'])); count=count+1;
    end
    for target={'data.bin','structured.json'}
        alev4_p4_fault.close_target=fullfile(c.base.core_single.directory,target{1}); alev4_p4_fault.hits=0;
        reject(@()alev4.readStructuredBundle(c.base.core_single.directory),['read close ' target{1}]);
        assert(alev4_p4_fault.hits==1); count=count+1;
    end
    metrics=struct('case_count',count,'file_handles_and_rng_restored',true);
end

function r = fixture(mode,stage,shape,bands,noisy,full_maps)
    if full_maps, full_size=shape+[2 2]; roi=[2 2 shape]; else, full_size=shape; roi=[1 1 shape]; end
    geometry=alev4.createSensorGeometry(struct('full_grid_size',full_size,'active_roi',roi,'pixel_pitch_m',1));
    sensor=alev4.createBaselineSensor(struct('image_size',shape,'pixel_pitch_m',1, ...
        'wavelength_nm',(450:25:450+25*(bands-1))','bin_width_nm',(1:bands)', ...
        'qe',repmat([.5 .25 .75],bands,1),'fill_factor',1,'full_well_e',3000, ...
        'shot_noise',noisy,'read_noise_e',2*double(noisy),'gain_dn_per_e',.5,'black_level_dn',32,'adc_bits',12));
    if strcmp(mode,'dual')
        cfg=alev4.createDualGainSensor(struct('sensor',rmfield(sensor,{'read_noise_e','gain_dn_per_e','black_level_dn','adc_bits'}), ...
            'high_gain',struct('gain_dn_per_e',4,'black_level_dn',64,'adc_bits',12,'read_noise_e',2*double(noisy)), ...
            'low_gain',struct('gain_dn_per_e',.5,'black_level_dn',64,'adc_bits',12,'read_noise_e',3*double(noisy)), ...
            'merge',struct('start_e',600,'end_e',900)));
    else, cfg=sensor; end
    cfg=alev4.bindSensorGeometry(cfg,geometry,'derive');
    if full_maps
        [column,row]=meshgrid(1:full_size(2),1:full_size(1));
        prnu=1+row/32+column/64; dark=row+column/2; fixed=row/8-column/16;
    else, prnu=1.25; dark=2; fixed=-.25; end
    path=struct('fixed_offset_e',fixed,'row_noise_e',.5*double(noisy), ...
        'column_noise_e',.75*double(noisy),'frame_noise_e',.25*double(noisy));
    model=alev4.createStructuredNoise(full_size,struct('prnu',prnu,'dark_current_e_per_s',dark, ...
        'dark_shot_noise',noisy,'shared',path,'single',path,'high_gain',path,'low_gain',path));
    if strcmp(stage,'core')
        r=alev4.simulateStructuredExposure(cube(shape,bands),cfg,.25,64321,model,geometry);
    else
        grid=alev4.createSpatialGrid(struct('x_edges_m',0:full_size(2),'y_edges_m',0:full_size(1)));
        options=struct('input_stage',stage,'spatial_provenance',struct('source','native_phase4_artifact_test', ...
            'matrix',[1 2;3 4],'scalar',2,'flag',true));
        if strcmp(stage,'pre_psf')
            options.psf=alev4.createOpticalPsf(struct('kernel',[1 2;3 2]/8, ...
                'origin_rc',[1 1],'spacing_yx_m',[1 1]));
        end
        r=alev4.simulateStructuredSpatialExposure(cube(full_size,bands),grid,geometry,cfg,.25,64321,model,options);
    end
end

function value = cube(shape,bands)
    value=zeros([shape bands]);
    for row=1:shape(1)
        for column=1:shape(2)
            for band=1:bands, value(row,column,band)=100*row+10*column+band; end
        end
    end
end

function [endpoint,samples,leaves] = auditTree(node,value,path,bytes,offset)
    samples=0; leaves=0; endpoint=offset;
    if isstruct(value)
        assert(strcmp(node.kind,'struct') && isequal(fieldnames(node.fields),fieldnames(value)));
        names=fieldnames(value);
        for k=1:numel(names)
            [endpoint,n,l]=auditTree(node.fields.(names{k}),value.(names{k}),[path '.' names{k}],bytes,endpoint);
            samples=samples+n; leaves=leaves+l;
        end
    elseif iscell(value)
        assert(strcmp(node.kind,'cell') && isequal(node.shape,size(value)));
        names=fieldnames(node.items);
        for k=1:numel(value)
            key=sprintf('i%06d',k); assert(strcmp(names{k},key));
            [endpoint,n,l]=auditTree(node.items.(key),value{k},[path '.' key],bytes,endpoint);
            samples=samples+n; leaves=leaves+l;
        end
    elseif ischar(value)
        assert(strcmp(node.kind,'char') && isequal(node.shape,size(value)) && isequal(node.value,value));
    else
        assert(strcmp(node.kind,'numeric') && strcmp(node.class,class(value)) && isequal(node.shape,size(value)));
        expected=nativeBytes(value); assert(node.offset==offset && node.byte_count==numel(expected));
        assert(isequal(segment(bytes,node),expected),['Independent payload mismatch: ' path]);
        endpoint=offset+numel(expected); samples=numel(value); leaves=1;
    end
end

function count = rejectChanges(c,key,prefix,paths)
    for k=1:numel(paths)
        value=getNative(c.base.(key).result,paths{k});
        if islogical(value), value(1)=~value(1);
        elseif ~isempty(regexp(paths{k},'read_electrons$','once')), value(1)=value(1)+100;
        else, value(1)=value(1)+1; end
        rejectPatched(c,key,sprintf('%s_%d',prefix,k),paths{k},value);
    end
    count=numel(paths);
end

function assertNativeSame(expected,actual)
    assert(strcmp(class(expected),class(actual)) && isequal(size(expected),size(actual)), ...
        'Native roundtrip changed a class or shape.');
    if isstruct(expected)
        names=fieldnames(expected); assert(isequal(names,fieldnames(actual)),'Native roundtrip changed field order.');
        for k=1:numel(names), assertNativeSame(expected.(names{k}),actual.(names{k})); end
    elseif iscell(expected)
        for k=1:numel(expected), assertNativeSame(expected{k},actual{k}); end
    elseif isa(expected,'double')
        assert(isequal(num2hex(expected(:)),num2hex(actual(:))),'Native roundtrip changed binary64 bits.');
    else, assert(isequal(expected,actual),'Native roundtrip changed a value.'); end
end

function rejectPatched(c,key,label,path,value)
    [directory,meta,bytes]=newCase(c,key,label); node=getNode(meta,path); replacement=nativeBytes(value);
    assert(numel(replacement)==node.byte_count && isequal(size(value),node.shape) && strcmp(class(value),node.class));
    bytes(node.offset+(1:node.byte_count))=replacement;
    writePayload(directory,meta,bytes); reject(@()alev4.readStructuredBundle(directory),label);
end

function [directory,meta,bytes] = newCase(c,key,label)
    label=regexprep(label,'[^A-Za-z0-9_-]','_'); directory=fullfile(c.folder,['case_' label]);
    assert(~alev4.bundlePathExists(directory),['Duplicate generated case ' label]); assert(mkdir(directory));
    base=c.base.(key); meta=base.meta; bytes=base.bytes;
    writeBytes(fullfile(directory,'structured.json'),base.text); writeBytes(fullfile(directory,'data.bin'),bytes);
end

function directory = writeNativeUnchecked(c,key,label,result)
% Independent traversal emits modified native values without invoking either
% production exporter or encoder, so semantic rejection is a reader gate.
    [directory,meta]=newCase(c,key,label); bytes=zeros(0,1,'uint8'); samples=0;
    [meta.result,bytes,samples]=rewriteNative(meta.result,result,bytes,samples);
    meta.payload.byte_count=numel(bytes); meta.payload.sample_count=samples;
    writePayload(directory,meta,bytes);
end

function [node,bytes,samples] = rewriteNative(node,value,bytes,samples)
    if isstruct(value)
        names=fieldnames(value);
        for k=1:numel(names), [node.fields.(names{k}),bytes,samples]=rewriteNative(node.fields.(names{k}),value.(names{k}),bytes,samples); end
    elseif iscell(value)
        for k=1:numel(value), key=sprintf('i%06d',k); [node.items.(key),bytes,samples]=rewriteNative(node.items.(key),value{k},bytes,samples); end
    elseif ischar(value), node.shape=size(value); node.value=value;
    else
        node.offset=numel(bytes); node.shape=size(value); node.class=class(value); encoded=nativeBytes(value);
        node.byte_count=numel(encoded); bytes=[bytes;encoded]; samples=samples+numel(value); %#ok<AGROW>
    end
end

function r = reassemble(r)
    names={'shared','high_gain','low_gain'};
    for k=1:numel(names)
        component=r.components.(names{k});
        total=bsxfun(@plus,component.fixed_offset_e,component.row_e);
        total=bsxfun(@plus,total,component.column_e); total=total+component.frame_e; total=total+component.pixel_e;
        r.components.(names{k}).total_e=total;
    end
    r.readout.collected_electrons=r.components.photo_electrons+r.components.dark_electrons;
    r.readout.charge_electrons=min(r.readout.collected_electrons,r.configuration.sensor.full_well_e);
    r.readout.full_well_saturated=r.readout.collected_electrons>=r.configuration.sensor.full_well_e;
    for name={'high_gain','low_gain'}
        cfg=r.configuration.(name{1}); path=r.readout.(name{1});
        path.read_electrons=(r.readout.charge_electrons+r.components.shared.total_e)+r.components.(name{1}).total_e;
        analog=path.read_electrons*cfg.gain_dn_per_e+cfg.black_level_dn;
        rounded=sign(analog).*floor(abs(analog)+.5); maximum=2^cfg.adc_bits-1;
        path.raw_dn=uint16(min(maximum,max(0,rounded))); path.adc_low_clipped=rounded<0;
        path.adc_high_clipped=rounded>maximum; path.adc_usable=path.raw_dn>0 & double(path.raw_dn)<maximum;
        r.readout.(name{1})=path;
    end
    hi=r.readout.high_gain; lo=r.readout.low_gain; cfg=r.configuration;
    high=(double(hi.raw_dn)-cfg.high_gain.black_level_dn)/cfg.high_gain.gain_dn_per_e;
    low=(double(lo.raw_dn)-cfg.low_gain.black_level_dn)/cfg.low_gain.gain_dn_per_e;
    t=min(1,max(0,(low-cfg.merge.start_e)/(cfg.merge.end_e-cfg.merge.start_e)));
    weight=1-t.^2.*(3-2*t); weight(~hi.adc_usable)=0; weight(hi.adc_usable & ~lo.adc_usable)=1;
    r.readout.merged=struct('electrons',weight.*high+(1-weight).*low,'weight_high',weight, ...
        'valid',hi.adc_usable|lo.adc_usable,'high_usable',hi.adc_usable,'low_usable',lo.adc_usable);
    r.readout.reconstruction_valid=r.readout.merged.valid & ~r.readout.full_well_saturated;
end

function value = getNative(value,path)
    names=strsplit(path,'.'); for k=1:numel(names), value=value.(names{k}); end
end

function result = setNative(result,path,value)
    names=strsplit(path,'.'); name=names{1};
    if numel(names)==1, result.(name)=value;
    else, result.(name)=setNative(result.(name),strjoin(names(2:end),'.'),value); end
end

function node = getNode(meta,path)
    node=meta.result; if isempty(path), return; end
    names=strsplit(path,'.'); for k=1:numel(names), node=node.fields.(names{k}); end
end

function meta = setNode(meta,path,node)
    if isempty(path), meta.result=node; return; end
    names=strsplit(path,'.'); wire='result';
    for k=1:numel(names), wire=[wire '.fields.' names{k}]; end %#ok<AGROW>
    meta=setNative(meta,wire,node);
end

function bytes = nativeBytes(value)
    widths=struct('double',8,'uint16',2,'logical',1); cls=class(value);
    bytes=zeros(numel(value)*widths.(cls),1,'uint8'); offset=0;
    for row=1:size(value,1)
        for column=1:size(value,2)
            for band=1:size(value,3)
                encoded=scalarBytes(value(row,column,band),cls);
                bytes(offset+(1:numel(encoded)))=encoded; offset=offset+numel(encoded);
            end
        end
    end
end

function bytes = scalarBytes(value,cls)
    if strcmp(cls,'double')
        word=num2hex(value); bytes=zeros(8,1,'uint8');
        for k=1:8, start=17-2*k; bytes(k)=uint8(hex2dec(word(start:start+1))); end
    elseif strcmp(cls,'uint16'), bytes=uint8([mod(double(value),256);floor(double(value)/256)]);
    else, bytes=uint8(value); end
end

function bytes = segment(payload,node)
    bytes=payload(node.offset+(1:node.byte_count)); bytes=bytes(:);
end

function meta = wireManifest(directory)
    meta=alev4.spatialDecodeJson(native2unicode(readBytes(fullfile(directory,'structured.json')).','UTF-8'));
end

function writePayload(directory,meta,bytes)
    meta.payload.sha256=sha256(bytes); writeBytes(fullfile(directory,'data.bin'),bytes); writeMeta(directory,meta);
end

function writeMeta(directory,meta)
% The wire tree contains only exact bounded integers, booleans and strings.
% A separate native JSON encoder avoids testing the producer against itself.
    writeBytes(fullfile(directory,'structured.json'),unicode2native([jsonencode(meta) sprintf('\n')],'UTF-8'));
end

function digest = sha256(bytes)
    if exist('hash','builtin'), digest=lower(hash('sha256',char(bytes(:).')));
    elseif (exist('usejava','builtin') || exist('usejava','file')) && usejava('jvm')
        md=javaMethod('getInstance','java.security.MessageDigest','SHA-256'); md.update(typecast(uint8(bytes(:)),'int8'));
        raw=typecast(int8(md.digest()),'uint8'); digest=lower(reshape(dec2hex(raw,2).',1,[]));
    else, error('ALEV4:TestFilesystemCapability','SHA-256 tests require Octave hash or a JVM.'); end
end

function reject(action,label,identifier)
    if nargin<3, identifier=''; end
    state=rng; handles=fopen('all'); caught=false;
    try, action(); catch err
        % As in Phase 3, Octave can reject invalid UTF-8 in its native
        % converter before the schema check, with an empty identifier.
        native_utf8=strcmp(label,'invalid UTF-8') && isempty(err.identifier) && ...
            ~isempty(strfind(err.message,'native2unicode')); %#ok<STREMP>
        caught=true; assert(strncmp(err.identifier,'ALEV4:',6) || native_utf8, ...
            ['Unexpected error in ' label ': ' err.identifier ': ' err.message]);
        if ~isempty(identifier), assert(strcmp(err.identifier,identifier), ...
            ['Original error changed in ' label ': ' err.identifier]); end
    end
    assert(caught,['Expected rejection: ' label]);
    assert(isequal(state,rng),['Caller RNG changed on ' label]);
    assert(isequal(handles,fopen('all')),['File handles leaked on ' label]);
end

function bytes = readBytes(path)
    fid=fopen(path,'rb'); assert(fid>=0); guard=onCleanup(@()closeQuietly(fid)); %#ok<NASGU>
    bytes=fread(fid,Inf,'*uint8'); [message,status]=ferror(fid); assert(status==0,message); assert(fclose(fid)==0);
end

function writeBytes(path,bytes)
    fid=fopen(path,'wb'); assert(fid>=0); guard=onCleanup(@()closeQuietly(fid)); %#ok<NASGU>
    assert(fwrite(fid,bytes,'uint8')==numel(bytes)); assert(fclose(fid)==0);
end

function closeQuietly(fid)
    try, fclose(fid); catch, end
end

function names = namesOf(directory)
    entries=dir(directory); names={entries.name}; names=sort(names(~ismember(names,{'.','..'})));
end

function [folder,guard] = ownFolder()
    folder=tempname(); assert(mkdir(folder)); marker=fullfile(folder,'.phase4-artifacts-owned');
    writeBytes(marker,uint8('phase4-artifacts-test')); guard=onCleanup(@()removeTestFolder(folder,marker));
end

function removeTestFolder(folder,marker)
    if exist(folder,'dir')==7 && exist(marker,'file')==2 && strcmp(fileread(marker),'phase4-artifacts-test')
        [ok,message]=rmdir(folder,'s'); assert(ok,message);
    end
end

function makeSymlink(source,destination)
    if exist('symlink','builtin') || exist('symlink','file'), [status,message]=symlink(source,destination); assert(status==0,message);
    elseif (exist('usejava','builtin') || exist('usejava','file')) && usejava('jvm')
        from=javaObject('java.io.File',source); to=javaObject('java.io.File',destination);
        javaMethod('createSymbolicLink','java.nio.file.Files',to.toPath(),from.toPath(),javaArray('java.nio.file.attribute.FileAttribute',0));
    else, error('ALEV4:TestFilesystemCapability','Native artifact tests require symlink support.'); end
end

function makeHardLink(source,destination)
    if exist('link','builtin') || exist('link','file'), [status,message]=link(source,destination); assert(status==0,message);
    elseif (exist('usejava','builtin') || exist('usejava','file')) && usejava('jvm')
        from=javaObject('java.io.File',source); to=javaObject('java.io.File',destination);
        javaMethod('createLink','java.nio.file.Files',to.toPath(),from.toPath());
    else, error('ALEV4:TestFilesystemCapability','Native artifact tests require hardlink support.'); end
end

function yes = isSymlink(path)
    if exist('lstat','builtin') || exist('lstat','file'), [info,status]=lstat(path); yes=status==0 && info.modestr(1)=='l';
    else, file=javaObject('java.io.File',path); yes=javaMethod('isSymbolicLink','java.nio.file.Files',file.toPath()); end
end

function removeLink(path)
    if exist('unlink','builtin') || exist('unlink','file'), [status,message]=unlink(path); assert(status==0,message);
    else, file=javaObject('java.io.File',path); javaMethod('delete','java.nio.file.Files',file.toPath()); end
end

function assertDistinct(left,right)
    if exist('lstat','builtin') || exist('lstat','file')
        [a,sa]=lstat(left); [b,sb]=lstat(right); assert(sa==0 && sb==0 && (a.dev~=b.dev || a.ino~=b.ino));
    else
        a=javaObject('java.io.File',left); b=javaObject('java.io.File',right);
        assert(~javaMethod('isSameFile','java.nio.file.Files',a.toPath(),b.toPath()));
    end
end

function [scope,guard] = faultScope(c,label)
    global alev4_p4_fault;
    parent=fullfile(c.folder,['fault_' label]); assert(mkdir(parent));
    writeBytes(fullfile(parent,'sentinel'),uint8('preserve parent'));
    shadow=fullfile(parent,'shadow'); assert(mkdir(shadow));
    previous_path=path; previous_warning=warning('query','all');
    alev4_p4_fault=struct('parent',parent,'base',fullfile(parent,'owned_stage'),'mode','none','hits',0, ...
        'counter',0,'mkdir',@mkdir,'movefile',@movefile,'relocated',fullfile(parent,'relocated'), ...
        'close_target','');
    scope=struct('parent',parent,'base',alev4_p4_fault.base);
    sources=faultSources(); names=fieldnames(sources);
    for k=1:numel(names), writeBytes(fullfile(shadow,[names{k} '.m']),uint8(sprintf(sources.(names{k})))); end
    guard=onCleanup(@()restoreFaultScope(previous_path,previous_warning));
    warning('off','Octave:shadowed-function'); warning('off','ALEV4:StructuredCleanup');
    addpath(shadow,'-begin'); clear tempname mkdir movefile fwrite fclose;
    for k=1:numel(names), assert(strcmp(which(names{k}),fullfile(shadow,[names{k} '.m']))); end
end

function sources = faultSources()
    sources=struct();
    sources.tempname=[ ...
        'function name=tempname(varargin)\n' ...
        'global alev4_p4_fault;\n' ...
        'if nargin>=1 && strcmp(varargin{1},alev4_p4_fault.parent), name=alev4_p4_fault.base; return; end\n' ...
        'if nargin>=1, parent=varargin{1}; else, parent=alev4_p4_fault.parent; end\n' ...
        'while true, alev4_p4_fault.counter=alev4_p4_fault.counter+1;\n' ...
        'name=fullfile(parent,sprintf(''p4-internal-%%d'',alev4_p4_fault.counter));\n' ...
        'if ~alev4.bundlePathExists(name), return; end; end\nend\n'];
    sources.mkdir=[ ...
        'function [ok,message,messageid]=mkdir(varargin)\n' ...
        'global alev4_p4_fault; [ok,message,messageid]=alev4_p4_fault.mkdir(varargin{:});\n' ...
        'if strcmp(alev4_p4_fault.mode,''ambiguous_mkdir'') && nargin==1 && strcmp(varargin{1},[alev4_p4_fault.base ''.structured-stage''])\n' ...
        'fid=fopen(fullfile(varargin{1},''foreign''),''wb''); builtin(''fwrite'',fid,uint8(''foreign creation''),''uint8''); builtin(''fclose'',fid);\n' ...
        'message=''directory exists''; messageid=''mkdir''; end\nend\n'];
    sources.fwrite=[ ...
        'function count=fwrite(fid,data,varargin)\n' ...
        'global alev4_p4_fault; name=fopen(fid); stage=[alev4_p4_fault.base ''.structured-stage'']; mode=alev4_p4_fault.mode;\n' ...
        'payload=strcmp(name,fullfile(stage,''data.bin'')); manifest=strcmp(name,fullfile(stage,''structured.json''));\n' ...
        'fire=alev4_p4_fault.hits==0 && ((payload && any(strcmp(mode,{''short_payload'',''throw_payload'',''payload_foreign''}))) || (manifest && any(strcmp(mode,{''short_manifest'',''throw_manifest'',''manifest_replaced''}))));\n' ...
        'if ~fire, count=builtin(''fwrite'',fid,data,varargin{:}); return; end\n' ...
        'alev4_p4_fault.hits=alev4_p4_fault.hits+1; rand(1,3); randn(1,5);\n' ...
        'if any(strcmp(mode,{''short_payload'',''short_manifest''})), count=builtin(''fwrite'',fid,data(1:max(0,numel(data)-1)),varargin{:}); return; end\n' ...
        'if strcmp(mode,''payload_foreign''), other=fopen(fullfile(stage,''foreign''),''wb''); builtin(''fwrite'',other,uint8(''preserve foreign''),''uint8''); builtin(''fclose'',other); end\n' ...
        'if strcmp(mode,''manifest_replaced''), [ok,message]=alev4_p4_fault.movefile(name,alev4_p4_fault.relocated); assert(ok,message); other=fopen(name,''wb''); builtin(''fwrite'',other,uint8(''preserve replacement''),''uint8''); builtin(''fclose'',other); end\n' ...
        'error(''ALEV4:InjectedArtifactWrite'',''Injected owned temporary write failure.'');\nend\n'];
    sources.movefile=[ ...
        'function [ok,message]=movefile(source,destination,varargin)\n' ...
        'global alev4_p4_fault; mode=alev4_p4_fault.mode;\n' ...
        'if ~strcmp(source,[alev4_p4_fault.base ''.structured-stage'']) || ~strncmp(mode,''publish_'',8), [ok,message]=alev4_p4_fault.movefile(source,destination,varargin{:}); return; end\n' ...
        'alev4_p4_fault.hits=alev4_p4_fault.hits+1; rand(1,3); randn(1,5); ok=false; message=''injected publication failure'';\n' ...
        'if strcmp(mode,''publish_foreign''), name=fullfile(source,''foreign''); value=''preserve foreign'';\n' ...
        'elseif strcmp(mode,''publish_replace''), name=fullfile(source,''data.bin''); [done,msg]=alev4_p4_fault.movefile(name,alev4_p4_fault.relocated); assert(done,msg); value=''preserve replacement'';\n' ...
        'elseif strcmp(mode,''publish_nested''), [done,msg]=alev4_p4_fault.mkdir(destination); assert(done,msg); name=fullfile(destination,''racer''); value=''preserve racer'';\n' ...
        'elseif strcmp(mode,''publish_identity''), [done,msg]=alev4_p4_fault.movefile(source,alev4_p4_fault.relocated); assert(done,msg); [done,msg]=alev4_p4_fault.mkdir(destination); assert(done,msg); name=fullfile(destination,''foreign''); value=''preserve directory replacement'';\n' ...
        'elseif strcmp(mode,''publish_postrename''), [done,msg]=alev4_p4_fault.movefile(source,destination); assert(done,msg); name=fullfile(destination,''foreign''); value=''preserve after rename'';\n' ...
        'else, return; end\n' ...
        'fid=fopen(name,''wb''); builtin(''fwrite'',fid,uint8(value),''uint8''); builtin(''fclose'',fid);\n' ...
        'if strcmp(mode,''publish_nested''), [~,stem,ext]=fileparts(source); [ok,message]=alev4_p4_fault.movefile(source,fullfile(destination,[stem ext]));\n' ...
        'elseif any(strcmp(mode,{''publish_identity'',''publish_postrename''})), ok=true; message=''''; end\nend\n'];
    sources.fclose=[ ...
        'function status=fclose(fid)\n' ...
        'global alev4_p4_fault; name=''''; try, name=fopen(fid); catch, end\n' ...
        'status=builtin(''fclose'',fid);\n' ...
        'if strcmp(alev4_p4_fault.mode,''close_failure'') && strcmp(name,alev4_p4_fault.close_target) && alev4_p4_fault.hits==0\n' ...
        'alev4_p4_fault.hits=alev4_p4_fault.hits+1; status=-1; end\nend\n'];
end

function restoreFaultScope(previous_path,previous_warning)
    path(previous_path); clear tempname mkdir movefile fwrite fclose;
    warning(previous_warning); clear global alev4_p4_fault;
end
