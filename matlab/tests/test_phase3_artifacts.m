function report = test_phase3_artifacts()
%TEST_PHASE3_ARTIFACTS Native spatial wire bytes and adversarial associations.
%   Every fixture and mutation is generated inside a test-owned temporary
%   directory. Byte oracles enumerate (plane,row,column) explicitly and use
%   IEEE-754 hex words, independently of the production payload routines.
    caller_rng = rng;
    rng_guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    functions = {@testModeStageRoundTrips, @testSingletonRoundTrips, ...
        @testPerBinPsf, @testBytesAndHashes, @testReadoutOracle, ...
        @testNumericTokens, @testExactCoordinateCoverage, @testTinyPayloads, ...
        @testJsonGrammar, @testJsonWireTypes, @testStringEscapeIntegrity, ...
        @testWireLists, @testProducerMutations, ...
        @testPayloadLengthsAndHashes, @testRehashedSemantics, ...
        @testDescriptorPolicy, @testCompleteConfiguration, ...
        @testGeometryOpticsAssociation, @testNestedAssociation, ...
        @testNestedStrictJson, @testFileIdentity, @testInventory, ...
        @testExistingTargets, @testOwnedFailureCleanup, ...
        @testNoisyRepeat, @testRngRestoration, @testReadCloseFailures, ...
        @test_phase3_staging_ownership};
    names = {'single_dual_pre_psf_post_optics_multibin_roundtrips', ...
        'singleton_rows_columns_pixels_and_single_bin_qe_shapes', ...
        'asymmetric_even_per_bin_psf_bytes_and_scalar_convolution', ...
        'independent_plane_major_little_endian_bytes_and_sha256', ...
        'independent_expected_charge_adc_clipping_flags_and_observed_merge', ...
        'original_17_digit_tokens_realmin_subnormal_and_signed_zero', ...
        'seven_times_six_micrometre_exact_coverage_and_one_ulp_gap', ...
        'tiny_positive_payloads_cannot_be_replaced_by_zero', ...
        'strict_json_grammar_duplicates_escapes_controls_and_bounds', ...
        'original_json_scalar_vector_matrix_and_nested_description_types', ...
        'escaped_nul_unicode_and_frozen_portable_identifier_contract', ...
        'keyed_source_operation_lists_preserve_order_and_reject_ambiguity', ...
        'producer_rejects_mutated_retained_results_before_publication', ...
        'missing_truncated_extra_bytes_and_stale_hashes_rejected', ...
        'updated_sha256_cannot_hide_spatial_or_readout_corruption', ...
        'exact_shapes_units_types_names_hashes_and_descriptor_fields', ...
        'complete_configuration_and_foreign_metadata_fields_required', ...
        'crop_cfa_stage_psf_halo_and_spectral_association', ...
        'outer_nested_seed_exposure_runtime_and_provenance_association', ...
        'legacy_single_and_dual_nested_manifests_use_strict_json', ...
        'hardlink_aliases_payload_directory_and_dangling_symlinks', ...
        'exact_inventory_rejects_extra_files_directories_and_dangling_links', ...
        'all_existing_target_kinds_preserved_without_overwrite', ...
        'late_publish_failure_and_racing_nesting_remove_only_owned_staging', ...
        'seeded_noisy_repeats_have_equal_bytes_and_distinct_file_identities', ...
        'caller_rng_restored_on_export_read_success_and_failure', ...
        'manifest_hash_and_payload_read_close_failures_are_reported', ...
        'staging_collisions_preserve_existing_paths_and_ambiguous_creation'};
    for k = 1:numel(functions), functions{k}(); end
    tests = repmat(struct('name','','status','passed','passed',true),1,numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    report = struct('suite','phase3_artifacts','status','passed','passed',true, ...
        'test_count',numel(names),'tests',tests,'metrics', ...
        struct('mode_stage_combinations',4,'singleton_shapes',[1 1;1 4;4 1], ...
        'binary_order','plane-major-row-major, IEEE-754 little-endian', ...
        'numeric_coordinate_hex','3f06052502eec7ca', ...
        'synthetic',true,'calibrated_alev4',false));
    fprintf('PASS: Phase 3 spatial artifacts, %d test groups.\n',numel(names));
end

function testModeStageRoundTrips()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    for mode = {'single','dual'}
        for stage = {'pre_psf','post_optics'}
            result = fixture(mode{1},stage{1},[3 5],3,false);
            directory = fullfile(folder,[mode{1} '_' stage{1}]);
            files = alev4.exportSpatialBundle(directory,result);
            assert(strcmp(files.directory,directory));
            assert(strcmp(files.metadata,fullfile(directory,'spatial.json')));
            [decoded,meta] = alev4.readSpatialBundle(directory);
            assertRoundTrip(result,decoded,meta);
            checkInventoryAndHashes(directory,wireManifest(directory));
            if strcmp(stage{1},'pre_psf')
                assert(isequal(meta.files.psf.shape,[1 1 1]) && meta.psf.kernel==1);
            else
                assert(isempty(meta.psf) && ~isfield(meta.files,'psf'));
            end
        end
    end
end

function testSingletonRoundTrips()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    shapes = {[1 1],[1 4],[4 1]};
    for k = 1:numel(shapes)
        for mode = {'single','dual'}
            for stage = {'pre_psf','post_optics'}
                result = fixture(mode{1},stage{1},shapes{k},1,false);
                directory = fullfile(folder,sprintf('%s_%s_%d',mode{1},stage{1},k));
                alev4.exportSpatialBundle(directory,result);
                [decoded,meta] = alev4.readSpatialBundle(directory);
                assertRoundTrip(result,decoded,meta);
                for key = {'input_irradiance','optical_irradiance','sampled_irradiance'}
                    assert(isequal(meta.files.(key{1}).shape,[shapes{k} 1]));
                    assert(isequal(size(decoded.(key{1})),shapes{k}));
                end
                assert(isequal(meta.files.expected_electrons.shape,shapes{k}));
                sensor = sensorOf(meta.configuration);
                assert(isequal(size(sensor.qe),[1 3]));
                assert(isequal(sensor.qe,[0.5 0.25 0.75]));
            end
        end
    end
end

function testPerBinPsf()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    result = psfFixture();
    directory = fullfile(folder,'per_bin');
    alev4.exportSpatialBundle(directory,result);
    [decoded,meta] = alev4.readSpatialBundle(directory);
    assertRoundTrip(result,decoded,meta);
    assert(isequal(meta.files.psf.shape,[2 3 2]));
    assert(isequal(meta.psf.origin_rc,[1 2]));
    assert(isequal(meta.psf.wavelength_nm,result.configuration.wavelength_nm));
    assert(isequal(readBytes(fullfile(directory,'psf.f64')),floatBytes(result.psf.kernel)));
    expected = zeros(3,5,2);
    for bin = 1:2
        for row = 1:3
            for column = 1:5
                for kr = 1:2
                    for kc = 1:3
                        expected(row,column,bin) = expected(row,column,bin) + ...
                            result.psf.kernel(kr,kc,bin)*result.input_irradiance(row+2-kr,column+3-kc,bin);
                    end
                end
            end
        end
    end
    assert(isequal(decoded.optical_irradiance,expected));
    assert(isequal(decoded.sampled_irradiance,expected));
    assert(isequal(decoded.optical_grid.x_edges_m,1:6));
    assert(isequal(decoded.optical_grid.y_edges_m,1:4));
    assert(strcmp(decoded.configuration.cfa_pattern,'BGGR'));
    assert(isequal(decoded.readout.expected_electrons,chargeOracle(expected,decoded.configuration,1)));
end

function testBytesAndHashes()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    result = fixture('dual','pre_psf',[2 3],2,false);
    input = cat(3,[1 2 4;8 16 32],[0.5 0.25 0.125;64 128 256]);
    result = resimulate(result,input);
    directory = fullfile(folder,'bytes');
    alev4.exportSpatialBundle(directory,result);
    meta = wireManifest(directory);
    for name = {'input_irradiance','optical_irradiance','sampled_irradiance'}
        descriptor = meta.files.(name{1});
        assert(isequal(readBytes(fullfile(directory,descriptor.name)),floatBytes(input)));
    end
    assert(isequal(readBytes(fullfile(directory,'expected.f64')),floatBytes(result.readout.expected_electrons)));
    assert(isequal(readBytes(fullfile(directory,'psf.f64')),uint8([0;0;0;0;0;0;240;63])));
    assert(isequal(readBytes(fullfile(directory,'readout.high.raw')),uint16Bytes(result.readout.high_gain.raw_dn)));
    assert(isequal(readBytes(fullfile(directory,'readout.low.raw')),uint16Bytes(result.readout.low_gain.raw_dn)));
    assert(isequal(readBytes(fullfile(directory,'readout.merged.f64')),floatBytes(result.readout.merged.electrons)));
    input_bytes = readBytes(fullfile(directory,'input.f64'));
    assert(isequal(input_bytes(1:8),uint8([0;0;0;0;0;0;240;63])));
    assert(isequal(input_bytes(49:56),uint8([0;0;0;0;0;0;224;63])));
    assert(isequal(floatBytes(-1),uint8([0;0;0;0;0;0;240;191])));
    assert(isequal(floatBytes(eps(0)),uint8([1;0;0;0;0;0;0;0])));
    assert(strcmp(sha256(uint8([0;1;127;128;255;0])), ...
        '39f8490195555de4f9ffa74f39874d7e5828c184e08bbde1d63a61545cf34b7b'));
    checkInventoryAndHashes(directory,meta);
end

function testReadoutOracle()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    mu = [0 10 750 12000 40000;1 6 32 600 900;22 333 500 1008 29999];
    for mode = {'single','dual'}
        result = fixture(mode{1},'post_optics',[3 5],1,false);
        if strcmp(mode{1},'single')
            result.configuration.qe = [1 1 1];
        else
            result.configuration.sensor.qe = [1 1 1];
        end
        result = resimulate(result,mu);
        directory = fullfile(folder,mode{1});
        alev4.exportSpatialBundle(directory,result);
        decoded = alev4.readSpatialBundle(directory);
        assert(isequal(decoded.readout.expected_electrons,mu));
        stored = min(mu,30000);
        if strcmp(mode{1},'single')
            raw = uint16(min(65535,max(0,floor(stored*0.5+64+0.5))));
            assert(isequal(decoded.readout.raw_dn,raw));
            assert(isequal(readBytes(fullfile(directory,'readout.raw')),uint16Bytes(raw)));
        else
            high_before = floor(stored*4+64+0.5);
            low_before = floor(stored*0.1+64+0.5);
            high = min(4095,max(0,high_before)); low = min(4095,max(0,low_before));
            usable_h = high>0 & high<4095; usable_l = low>0 & low<4095;
            eh = (high-64)/4; el = (low-64)/0.1;
            t = min(1,max(0,(el-600)/300)); weight = 1-t.^2.*(3-2*t);
            weight(~usable_h)=0; weight(usable_h & ~usable_l)=1;
            merged = weight.*eh+(1-weight).*el;
            valid = (usable_h | usable_l) & mu<30000;
            flags = uint8(mu>=30000)+2*uint8(high_before<0)+4*uint8(high_before>4095) + ...
                8*uint8(low_before<0)+16*uint8(low_before>4095)+32*uint8(usable_h)+ ...
                64*uint8(usable_l)+128*uint8(valid);
            assert(isequal(decoded.readout.high_gain.raw_dn,uint16(high)));
            assert(isequal(decoded.readout.low_gain.raw_dn,uint16(low)));
            assert(isequal(decoded.readout.merged.electrons,merged));
            assert(isequal(decoded.readout.flags,flags));
            assert(isequal(decoded.readout.reconstruction_valid,valid));
            assert(isequal(readBytes(fullfile(directory,'readout.flags.u8')),rowBytes(flags)));
            assert(isequal(flags(1,:),uint8([224 224 224 196 69])));
        end
    end
end

function testNumericTokens()
    values = [0,-1/Inf,1,-1,2^32-1,flintmax,7*6e-6,9*6e-6,pi, ...
        1+eps(1),realmin,realmin/2,eps(0),-eps(0),1e-200,-1e-200,realmax];
    tokens = cell(1,numel(values));
    for k = 1:numel(values), tokens{k}=sprintf('%.17g',values(k)); end
    text = ['{"values":[' strjoin(tokens,',') ']}'];
    parsed = alev4.spatialDecodeJson(text);
    assert(isequal(num2hex(parsed.values),num2hex(values)));
    assert(isequal(num2hex(cellfun(@str2double,tokens)),num2hex(values)));
    encoded = alev4.encodeBundleJson(struct('values',values));
    encoded_tokens = regexp(encoded,'"values":\[([^]]+)\]','tokens','once');
    assert(~isempty(encoded_tokens));
    assert(isequal(num2hex(cellfun(@str2double,strsplit(encoded_tokens{1},','))),num2hex(values)));
    assert(strcmp(num2hex(parsed.values(7)),'3f06052502eec7ca'));
    matrix = alev4.spatialDecodeJson('{"matrix":[[1,2],[3,4]],"column":[[1],[2]],"yes":true,"no":false,"text":"quote \" and slash \\ and \u03bb","empty":[]}');
    assert(isequal(matrix.matrix,[1 2;3 4]) && isequal(matrix.column,[1;2]));
    assert(islogical(matrix.yes) && matrix.yes && islogical(matrix.no) && ~matrix.no);
    assert(isequal(matrix.text,['quote " and slash ' char(92) ' and ' native2unicode(uint8([206 187]),'UTF-8')]));
    assert(isnumeric(matrix.empty) && isempty(matrix.empty));
    for token = {'1e-400','-1e-400','1e400','-1e400'}
        expectError(@() alev4.spatialDecodeJson(['{"value":' token{1} '}']), ...
            {'ALEV4:InvalidSpatialMetadata','ALEV4:InvalidDualGainMetadata'});
    end
end

function testExactCoordinateCoverage()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    result = fixture('single','post_optics',[3 7],1,false);
    result.geometry.pixel_pitch_m = 6e-6;
    result.configuration.pixel_pitch_m = 6e-6;
    result.input_grid = alev4.createSpatialGrid(struct('x_edges_m',(0:7)*6e-6,'y_edges_m',(0:3)*6e-6));
    result = resimulate(result,result.input_irradiance);
    directory = fullfile(folder,'coordinate');
    alev4.exportSpatialBundle(directory,result);
    [decoded,meta] = alev4.readSpatialBundle(directory);
    assert(isequal(num2hex(decoded.input_grid.x_edges_m),num2hex(result.input_grid.x_edges_m)));
    assert(strcmp(num2hex(meta.input_grid.x_edges_m(end)),'3f06052502eec7ca'));
    original = wireManifest(directory); bad = original;
    edge = bad.input_grid.x_edges_m(end);
    bad.input_grid.x_edges_m(end) = edge-eps(edge);
    bad.optical_grid.x_edges_m(end) = edge-eps(edge);
    assert(bad.input_grid.x_edges_m(end)<7*6e-6);
    writeManifest(directory,bad);
    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:SpatialCoverage');
    writeManifest(directory,original);
    alev4.readSpatialBundle(directory);
end

function testTinyPayloads()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    result = fixture('single','pre_psf',[2 3],1,false);
    result.configuration.qe = [1 1 1];
    input = [realmin realmin/2 eps(0);1e-200 2*eps(0) 0];
    result = resimulate(result,input);
    directory = fullfile(folder,'tiny');
    alev4.exportSpatialBundle(directory,result);
    decoded = alev4.readSpatialBundle(directory);
    assert(isequal(num2hex(decoded.readout.expected_electrons),num2hex(input)));
    original = wireManifest(directory);
    for key = {'optical_irradiance','sampled_irradiance','expected_electrons'}
        descriptor = original.files.(key{1}); path = fullfile(directory,descriptor.name);
        bytes = readBytes(path);
        for index = [1 3]
            bad = input; bad(index)=0;
            altered = replacePayload(directory,original,key{1},floatBytes(bad));
            assert(strcmp(altered.files.(key{1}).sha256,sha256(readBytes(path))));
            expectError(@() alev4.readSpatialBundle(directory),'ALEV4:SpatialSemanticMismatch');
            writeBytes(path,bytes); writeManifest(directory,original);
        end
    end
    bad = input; bad(1)=2*realmin;
    replacePayload(directory,original,'expected_electrons',floatBytes(bad));
    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:SpatialSemanticMismatch');
end

function testJsonGrammar()
    invalid = {'{"a":1,"a":2}', '{"a":1,"\u0061":2}', ...
        '{"a-b":1}', '{"a":NaN}', '{"a":Infinity}', '{"a":null}', ...
        '{"a":01}', '{"a":+1}', '{"a":.1}', '{"a":1.}', ...
        '{"a":1e}', '{"a":1,}', '{"a":[1,]}', '{"a":true false}', ...
        '{"a":1}false', '{"a" 1}', '{"a":"\q"}', '{"a":', '', ...
        ['{"a":"bad' char(10) 'control"}'], ['{"a":"bad' char(0) 'control"}']};
    for k = 1:numel(invalid)
        expectError(@() alev4.spatialDecodeJson(invalid{k}), ...
            {'ALEV4:InvalidSpatialMetadata','ALEV4:InvalidDualGainMetadata'});
    end
    parsed = alev4.spatialDecodeJson([' ' char(9) '{"a":{"key":1},"b":{"key":2},"text":"{}[],:",' ...
        '"escaped":"line\nnext\tcolumn"}' char(13) char(10)]);
    assert(parsed.a.key==1 && parsed.b.key==2);
    assert(isequal(parsed.escaped,['line' char(10) 'next' char(9) 'column']));
    deepest = [repmat('{"a":',1,64) '0' repmat('}',1,64)];
    alev4.spatialDecodeJson(deepest);
    expectError(@() alev4.spatialDecodeJson(['{"a":' deepest '}']),'ALEV4:InvalidDualGainMetadata');
    fields = cell(1,256);
    for k=1:256, fields{k}=sprintf('"field%d":0',k); end
    wide = ['{' strjoin(fields,',') '}']; alev4.spatialDecodeJson(wide);
    expectError(@() alev4.spatialDecodeJson([wide(1:end-1) ',"extra":0}']),'ALEV4:InvalidDualGainMetadata');
    expectError(@() alev4.spatialDecodeJson(repmat(' ',1,2000001)),'ALEV4:InvalidSpatialMetadata');
    [folder,guard] = ownFolder(); %#ok<NASGU>
    result = fixture('single','post_optics',[1 1],1,false);
    directory = fullfile(folder,'utf8'); alev4.exportSpatialBundle(directory,result);
    writeBytes(fullfile(directory,'spatial.json'),uint8([123 34 97 34 58 34 255 34 125]));
    observed=expectError(@() alev4.readSpatialBundle(directory), ...
        {'ALEV4:InvalidSpatialMetadata','ALEV4:InvalidDualGainMetadata',''});
    % Octave rejects malformed UTF-8 inside its native converter before the
    % explicit roundtrip check; MATLAB may reach that schema check instead.
    if isempty(observed.identifier), assert(~isempty(strfind(observed.message,'native2unicode'))); end
end

function testJsonWireTypes()
    [values,kinds]=alev4.spatialDecodeJson( ...
        '{"scalar":1,"vector":[1],"matrix":[[1]],"column":[[1],[2]],"empty":[]}');
    assert(values.scalar==1 && values.vector==1 && values.matrix==1);
    assert(isequal(values.column,[1;2]));
    assert(strcmp(kinds.scalar,'number') && strcmp(kinds.vector,'vector') && ...
        strcmp(kinds.matrix,'matrix') && strcmp(kinds.column,'matrix') && strcmp(kinds.empty,'empty'));
    malformed={'[1,[2]]','[[[1]]]','[[1,2],[3]]','[true]','[false,0]','["text"]','[{}]'};
    for k=1:numel(malformed)
        expectError(@()alev4.spatialDecodeJson(['{"value":' malformed{k} '}']), ...
            'ALEV4:InvalidSpatialMetadata');
    end
    [folder,guard]=ownFolder(); %#ok<NASGU>
    for mode={'single','dual'}
        result=fixture(mode{1},'post_optics',[2 3],1,false);
        directory=fullfile(folder,mode{1}); alev4.exportSpatialBundle(directory,result);
        original=wireManifest(directory); outer=fileread(fullfile(directory,'spatial.json'));
        changes={'"seed":48301','"seed":[48301]'; ...
            '"exposure_s":1','"exposure_s":[1]'; ...
            '"read_noise_e":0','"read_noise_e":[0]'; ...
            '"adc_bits":16','"adc_bits":[[16]]'; ...
            '"byte_count":12','"byte_count":[12]'; ...
            '"shape":[2,3,1]','"shape":[[2],[3],[1]]'};
        for k=1:size(changes,1)
            changed=strrep(outer,changes{k,1},changes{k,2}); assert(~strcmp(changed,outer));
            writeBytes(fullfile(directory,'spatial.json'),unicode2native(changed,'UTF-8'));
            expectError(@()alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
        end
        writeManifest(directory,original);
        nested_text=fileread(fullfile(directory,'readout.json'));
        changes={'"seed":48301','"seed":[48301]'; ...
            '"exposure_s":1','"exposure_s":[[1]]'; ...
            '"synthetic":true','"synthetic":[true]'; ...
            '"shot_noise":false','"shot_noise":[false]'; ...
            '"cfa_origin":[1,1]','"cfa_origin":[[1],[1]]'};
        if strcmp(mode{1},'dual')
            changes(end,:)={'"image_size":[2,3]','"image_size":[[2],[3]]'};
        end
        for k=1:size(changes,1)
            changed=strrep(nested_text,changes{k,1},changes{k,2}); assert(~strcmp(changed,nested_text));
            replacePayload(directory,original,'readout_metadata',unicode2native(changed,'UTF-8'));
            expectError(@()alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
        end
        replacePayload(directory,original,'readout_metadata',unicode2native(nested_text,'UTF-8'));
        % A one-bin vector may use its scalar or explicit one-element wire
        % representation; QE may use a flat RGB row or one nested RGB row.
        changed=strrep(outer,'"wavelength_nm":450','"wavelength_nm":[450]');
        changed=strrep(changed,'"bin_width_nm":1','"bin_width_nm":[1]');
        changed=strrep(changed,'"qe":[0.5,0.25,0.75]','"qe":[[0.5,0.25,0.75]]');
        assert(~strcmp(changed,outer));
        writeBytes(fullfile(directory,'spatial.json'),unicode2native(changed,'UTF-8'));
        alev4.readSpatialBundle(directory);
        writeManifest(directory,original);
        if strcmp(mode{1},'single')
            nested=alev4.spatialDecodeJson(nested_text);
            for description={17,'','   ',true,[]}
                changed=nested; changed.description=description{1}; replaceNested(directory,original,changed);
                expectError(@()alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
            end
            replaceNested(directory,original,nested);
        end
        alev4.readSpatialBundle(directory);
    end
end

function testStringEscapeIntegrity()
    invalid={'{"seed\u0000evil":1}','{"text":"value\u0000suffix"}', ...
        '{"text":"\udc00"}','{"text":"\ud800"}','{"text":"\ud800\u0041"}'};
    for k=1:numel(invalid)
        expectError(@()alev4.spatialDecodeJson(invalid{k}),'ALEV4:InvalidSpatialMetadata');
    end
    parsed=alev4.spatialDecodeJson('{"text":"\\u0000","emoji":"\ud83d\ude00"}');
    assert(isequal(parsed.text,[char(92) 'u0000']));
    assert(isequal(parsed.emoji,native2unicode(uint8([240 159 152 128]),'UTF-8')));
    valid_key=repmat('a',1,63);
    alev4.spatialDecodeJson(['{"' valid_key '":1}']);
    expectError(@()alev4.spatialDecodeJson(['{"' valid_key 'a":1}']),'ALEV4:InvalidSpatialMetadata');
    keywords={'__FILE__','__LINE__','break','case','catch','classdef','continue', ...
        'do','else','elseif','end','end_try_catch','end_unwind_protect', ...
        'endarguments','endclassdef','endenumeration','endevents','endfor', ...
        'endfunction','endif','endmethods','endparfor','endproperties','endspmd', ...
        'endswitch','endwhile','for','function','global','if','otherwise','parfor', ...
        'persistent','return','spmd','switch','try','until','unwind_protect', ...
        'unwind_protect_cleanup','while'};
    for k=1:numel(keywords)
        expectError(@()alev4.spatialDecodeJson(['{"' keywords{k} '":1}']), ...
            'ALEV4:InvalidSpatialMetadata');
    end
    alev4.spatialDecodeJson('{"enumeration":1,"events":2,"methods":3,"properties":4,"arguments":5}');
    for terminal={'0','[0]','[[0]]'}
        arrays=sum(terminal{1}=='['); containers=64-arrays;
        deepest=[repmat('{"a":',1,containers) terminal{1} repmat('}',1,containers)];
        alev4.spatialDecodeJson(deepest);
        expectError(@()alev4.spatialDecodeJson(['{"a":' deepest '}']),'ALEV4:InvalidDualGainMetadata');
    end
    [folder,guard]=ownFolder(); %#ok<NASGU>
    result=fixture('single','post_optics',[2 3],1,false);
    directory=fullfile(folder,'nul'); alev4.exportSpatialBundle(directory,result);
    original=wireManifest(directory); text=fileread(fullfile(directory,'spatial.json'));
    variants={strrep(text,'"seed":','"seed\u0000evil":'), ...
        strrep(text,'"ALEV4-SYNTHETIC-SPATIAL"','"ALEV4-SYNTHETIC-SPATIAL\u0000evil"')};
    for k=1:numel(variants)
        assert(~strcmp(variants{k},text));
        writeBytes(fullfile(directory,'spatial.json'),unicode2native(variants{k},'UTF-8'));
        expectError(@()alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
    end
    nested=fileread(fullfile(directory,'readout.json'));
    changed=strrep(nested,'"seed":','"seed\u0000evil":'); assert(~strcmp(changed,nested));
    replacePayload(directory,original,'readout_metadata',unicode2native(changed,'UTF-8'));
    expectError(@()alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
    replacePayload(directory,original,'readout_metadata',unicode2native(nested,'UTF-8'));
    alev4.readSpatialBundle(directory);
end

function testWireLists()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    result = psfFixture(); directory = fullfile(folder,'lists');
    alev4.exportSpatialBundle(directory,result); original = wireManifest(directory);
    reversed = original;
    reversed.geometry.parameter_sources = orderfields(original.geometry.parameter_sources,flipud(fieldnames(original.geometry.parameter_sources)));
    reversed.operation_order = orderfields(original.operation_order,flipud(fieldnames(original.operation_order)));
    writeManifest(directory,reversed); decoded = alev4.readSpatialBundle(directory);
    assert(isequal(decoded.operation_order,result.operation_order));
    assert(isequal(decoded.geometry.parameter_sources,result.geometry.parameter_sources));
    bads = cell(1,8);
    bads{1}=original; bads{1}.geometry.parameter_sources=struct();
    bads{2}=original; bads{2}.geometry.parameter_sources=rmfield(original.geometry.parameter_sources,'id001');
    bads{3}=original; bads{3}.geometry.parameter_sources.id002=original.geometry.parameter_sources.id001;
    bads{4}=original; bads{4}.geometry.parameter_sources.foreign='ASSUMED-EXTRA';
    bads{5}=original; bads{5}.operation_order.step002=original.operation_order.step001;
    bads{6}=original; bads{6}.operation_order=rmfield(original.operation_order,'step002');
    bads{7}=original; bads{7}.psf.parameter_sources.id001='';
    bads{8}=original; bads{8}.operation_order=struct('step001',1);
    for k=1:numel(bads)
        writeManifest(directory,bads{k});
        expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
    end
end

function testProducerMutations()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    result = psfFixture(); bads = cell(1,15);
    bads{1}=rmfield(result,'input_grid');
    bads{2}=result; bads{2}.foreign=1;
    bads{3}=result; bads{3}.input_irradiance(1)=result.input_irradiance(1)+10;
    bads{4}=result; bads{4}.optical_irradiance(1)=result.optical_irradiance(1)+10;
    bads{5}=result; bads{5}.sampled_irradiance(1)=result.sampled_irradiance(1)+10;
    bads{6}=result; bads{6}.readout.expected_electrons(1)=result.readout.expected_electrons(1)+10;
    bads{7}=result; bads{7}.readout.raw_dn(1)=result.readout.raw_dn(1)+uint16(1);
    bads{8}=result; bads{8}.configuration=rmfield(result.configuration,'fill_factor');
    bads{9}=result; bads{9}.operation_order=fliplr(result.operation_order);
    bads{10}=result; bads{10}.readout_mode='dual';
    bads{11}=result; bads{11}.spatial_provenance=struct('unknown_cell',{{'one','two'}});
    bads{12}=result; bads{12}.geometry.active_roi(2)=1;
    bads{13}=result; bads{13}.psf.kernel=flip(result.psf.kernel,3);
    bads{14}=result; bads{14}.readout.expected_incident_photons(1)=0;
    bads{15}=result; bads{15}.synthetic=1;
    before = namesOf(folder);
    for k=1:numel(bads)
        expectError(@() alev4.exportSpatialBundle(fullfile(folder,'rejected'),bads{k}), ...
            {'ALEV4:InvalidSpatialResult','ALEV4:InvalidSpatialMetadata', ...
            'ALEV4:SpatialSemanticMismatch','ALEV4:InvalidDualGainMetadata', ...
            'ALEV4:GeometryBindingConflict'});
        assert(isequal(namesOf(folder),before),'Rejected producer result left owned output.');
    end
    noisy = fixture('dual','post_optics',[3 5],1,true);
    noisy.readout.seed=noisy.readout.seed+1;
    expectError(@() alev4.exportSpatialBundle(fullfile(folder,'seed_changed'),noisy), ...
        'ALEV4:SpatialSemanticMismatch');
    assert(isequal(namesOf(folder),before));
end

function testPayloadLengthsAndHashes()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    for mode = {'single','dual'}
        result = fixture(mode{1},'pre_psf',[2 3],2,false);
        directory = fullfile(folder,mode{1}); alev4.exportSpatialBundle(directory,result);
        original = wireManifest(directory); keys = fieldnames(original.files);
        for k=1:numel(keys)
            path = fullfile(directory,original.files.(keys{k}).name); bytes = readBytes(path);
            delete(path);
            expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
            writeBytes(path,bytes(1:end-1));
            expectError(@() alev4.readSpatialBundle(directory),'ALEV4:SpatialChecksumMismatch');
            writeBytes(path,[bytes;uint8(0)]);
            expectError(@() alev4.readSpatialBundle(directory), ...
                {'ALEV4:SpatialSizeMismatch','ALEV4:SpatialChecksumMismatch'});
            changed=bytes; changed(1)=bitxor(changed(1),uint8(1)); writeBytes(path,changed);
            expectError(@() alev4.readSpatialBundle(directory),'ALEV4:SpatialChecksumMismatch');
            writeBytes(path,bytes);
        end
        alev4.readSpatialBundle(directory);
    end
end

function testRehashedSemantics()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    result = psfFixture(); directory = fullfile(folder,'semantic');
    alev4.exportSpatialBundle(directory,result); original=wireManifest(directory);
    arrays = {'input_irradiance','optical_irradiance','sampled_irradiance','expected_electrons','psf'};
    for k=1:numel(arrays)
        key=arrays{k}; path=fullfile(directory,original.files.(key).name); bytes=readBytes(path);
        if strcmp(key,'expected_electrons'), changed=result.readout.expected_electrons;
        elseif strcmp(key,'psf'), changed=result.psf.kernel;
        else, changed=result.(key); end
        if strcmp(key,'psf')
            changed(1,1,1)=changed(1,1,1)+1/16;
            changed(2,3,1)=changed(2,3,1)-1/16;
        else
            changed(1)=changed(1)+max(1,abs(changed(1))/2);
        end
        altered=replacePayload(directory,original,key,floatBytes(changed));
        assert(strcmp(altered.files.(key).sha256,sha256(readBytes(path))));
        expectError(@() alev4.readSpatialBundle(directory),'ALEV4:SpatialSemanticMismatch');
        writeBytes(path,bytes); writeManifest(directory,original);
    end
    for value=[-1 NaN Inf]
        changed=result.input_irradiance; changed(1)=value;
        replacePayload(directory,original,'input_irradiance',floatBytes(changed));
        expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialIrradiance');
    end
    writeBytes(fullfile(directory,'input.f64'),floatBytes(result.input_irradiance));
    changed=result.sampled_irradiance(:,:,[2 1]);
    replacePayload(directory,original,'sampled_irradiance',floatBytes(changed));
    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:SpatialSemanticMismatch');
    writeBytes(fullfile(directory,'sampled.f64'),floatBytes(result.sampled_irradiance));
    raw=result.readout.raw_dn; raw(1)=raw(1)+uint16(1);
    replacePayload(directory,original,'raw',uint16Bytes(raw));
    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:SpatialSemanticMismatch');
    dual=fixture('dual','post_optics',[2 3],1,false);
    destination=fullfile(folder,'dual'); alev4.exportSpatialBundle(destination,dual); outer=wireManifest(destination);
    changed=dual.readout.merged.electrons; changed(1)=changed(1)+1;
    replacePayload(destination,outer,'merged_electrons',floatBytes(changed));
    expectError(@() alev4.readSpatialBundle(destination),'ALEV4:InvalidDualGainMetadata');
end

function testDescriptorPolicy()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    result=fixture('dual','pre_psf',[2 3],2,false);
    directory=fullfile(folder,'descriptors'); alev4.exportSpatialBundle(directory,result);
    original=wireManifest(directory); bads=cell(1,16);
    bads{1}=original; bads{1}.files.input_irradiance.shape=[3 2 2];
    bads{2}=original; bads{2}.files.input_irradiance.shape=[2 3];
    bads{3}=original; bads{3}.files.input_irradiance.shape=[2 3 1];
    bads{4}=original; bads{4}.files.input_irradiance.shape=[1e8 2 2];
    bads{5}=original; bads{5}.files.input_irradiance.shape=[2 3 1.5];
    bads{6}=original; bads{6}.files.input_irradiance.units='electrons';
    bads{7}=original; bads{7}.files.expected_electrons.units='DN';
    bads{8}=original; bads{8}.files.psf.units='photons m^-2 s^-1 nm^-1';
    bads{9}=original; bads{9}.files.input_irradiance.name='../input.f64';
    bads{10}=original; bads{10}.files.input_irradiance.sample_type='uint16';
    bads{11}=original; bads{11}.files.input_irradiance.byte_count=8;
    bads{12}=original; bads{12}.files.input_irradiance.sha256=upper(original.files.input_irradiance.sha256);
    bads{13}=original; bads{13}.files.input_irradiance.foreign=1;
    bads{14}=original; bads{14}.files.readout_metadata.shape=1;
    bads{15}=original; bads{15}.files=rmfield(original.files,'low_raw');
    bads{16}=original; bads{16}.files.raw=original.files.high_raw;
    for k=1:numel(bads)
        writeManifest(directory,bads{k});
        expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
    end
    writeManifest(directory,original);
    text=fileread(fullfile(directory,'spatial.json'));
    altered=strrep(text,'"shape":[2,3,2]','"shape":[true,3,2]'); assert(~strcmp(altered,text));
    writeBytes(fullfile(directory,'spatial.json'),uint8(altered));
    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
end

function testCompleteConfiguration()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    for mode={'single','dual'}
        result=fixture(mode{1},'pre_psf',[2 3],1,false);
        directory=fullfile(folder,mode{1}); alev4.exportSpatialBundle(directory,result); original=wireManifest(directory);
        for key={'configuration','geometry','input_grid','optical_grid','psf','spatial_provenance','runtime','provenance'}
            bad=rmfield(original,key{1}); writeManifest(directory,bad);
            expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
            bad=original; bad.(key{1}).foreign=1; writeManifest(directory,bad);
            if strcmp(key{1},'spatial_provenance')
                alev4.readSpatialBundle(directory); % Informational scalar data is explicitly extensible.
            else
                expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
            end
        end
        bad=original; bad.foreign=1; writeManifest(directory,bad);
        expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
        if strcmp(mode{1},'single')
            fields=fieldnames(original.configuration);
            for k=1:numel(fields)
                bad=original; bad.configuration=rmfield(original.configuration,fields{k}); writeManifest(directory,bad);
                expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
            end
        else
            for part={'sensor','high_gain','low_gain','merge'}
                fields=fieldnames(original.configuration.(part{1}));
                for k=1:numel(fields)
                    bad=original; bad.configuration.(part{1})=rmfield(original.configuration.(part{1}),fields{k});
                    writeManifest(directory,bad);
                    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
                end
            end
        end
        writeManifest(directory,original); alev4.readSpatialBundle(directory);
    end
end

function testGeometryOpticsAssociation()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    result=psfFixture(); directory=fullfile(folder,'geometry');
    alev4.exportSpatialBundle(directory,result); original=wireManifest(directory);
    bad=original; bad.geometry.active_roi(2)=1; writeManifest(directory,bad);
    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:GeometryBindingConflict');
    bad=original; bad.geometry.full_grid_cfa_pattern='GRBG'; writeManifest(directory,bad);
    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:GeometryBindingConflict');
    bad=original; bad.psf.origin_rc=[2 2]; writeManifest(directory,bad);
    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
    bad=original; bad.psf.wavelength_nm=flipud(bad.psf.wavelength_nm(:)); writeManifest(directory,bad);
    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:OpticalSpectralMapping');
    bad=original; bad.psf.wavelength_nm=bad.psf.wavelength_nm+1; writeManifest(directory,bad);
    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:OpticalSpectralMapping');
    bad=original; bad.input_stage='post_optics'; writeManifest(directory,bad);
    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:DuplicateOptics');
    bad=original; bad.operation_order.step001='area_overlap_average'; writeManifest(directory,bad);
    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
    % Remove the complete top halo, update both length and SHA, and retain
    % otherwise valid PSF metadata. Supported optical coverage must reject.
    bad=original; bad.input_grid.y_edges_m=bad.input_grid.y_edges_m(2:end);
    bad.files.input_irradiance.shape(1)=bad.files.input_irradiance.shape(1)-1;
    bytes=floatBytes(result.input_irradiance(2:end,:,:));
    replacePayload(directory,bad,'input_irradiance',bytes);
    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
end

function testNestedAssociation()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    for mode={'single','dual'}
        result=fixture(mode{1},'post_optics',[2 3],1,false);
        directory=fullfile(folder,mode{1}); alev4.exportSpatialBundle(directory,result);
        original=wireManifest(directory); nested=alev4.spatialDecodeJson(fileread(fullfile(directory,'readout.json')));
        for field={'seed','exposure_s','runtime','provenance'}
            name=field{1}; bad=original;
            bad.(name)=changedIdentity(bad.(name),name); writeManifest(directory,bad);
            expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
            changed=nested; changed.(name)=changedIdentity(changed.(name),name);
            replaceNested(directory,original,changed);
            expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
            replaceNested(directory,original,nested);
        end
        changed=nested;
        if strcmp(mode{1},'single'), changed.sensor.fill_factor=0.5;
        else, changed.configuration.sensor.fill_factor=0.5; end
        replaceNested(directory,original,changed);
        expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
    end
end

function testNestedStrictJson()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    for mode={'single','dual'}
        result=fixture(mode{1},'post_optics',[2 3],1,false);
        directory=fullfile(folder,mode{1}); alev4.exportSpatialBundle(directory,result);
        original=wireManifest(directory); text=fileread(fullfile(directory,'readout.json'));
        malformed={['{"seed":0,' text(2:end)], ['{"se' char(92) 'u0065d":0,' text(2:end)], ...
            strrep(text,'"seed":','"se-ed":'), ['{"foreign":1,' text(2:end)]};
        for k=1:numel(malformed)
            replacePayload(directory,original,'readout_metadata',unicode2native(malformed{k},'UTF-8'));
            expectError(@() alev4.readSpatialBundle(directory), ...
                {'ALEV4:InvalidDualGainMetadata','ALEV4:InvalidSpatialMetadata'});
        end
        valid=strrep(text,'"seed":',['"se' char(92) 'u0065d":']);
        replacePayload(directory,original,'readout_metadata',unicode2native(valid,'UTF-8'));
        alev4.readSpatialBundle(directory);
    end
end

function testFileIdentity()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    result=fixture('single','post_optics',[2 3],1,false);
    directory=fullfile(folder,'identity'); alev4.exportSpatialBundle(directory,result);
    optical=fullfile(directory,'optical.f64'); bytes=readBytes(optical);
    assert(isequal(bytes,readBytes(fullfile(directory,'input.f64'))));
    delete(optical); makeHardLink(fullfile(directory,'input.f64'),optical);
    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
    delete(optical); writeBytes(optical,bytes);
    original=wireManifest(directory); keys=fieldnames(original.files);
    all_names=cellfun(@(key) original.files.(key).name,keys,'UniformOutput',false);
    all_names{end+1}='spatial.json';
    for k=1:numel(all_names)
        path=fullfile(directory,all_names{k}); bytes=readBytes(path);
        outside=fullfile(folder,'outside'); writeBytes(outside,bytes);
        delete(path); makeSymlink(outside,path);
        expectError(@() alev4.readSpatialBundle(directory),'ALEV4:SpatialBundleMissing');
        assert(isequal(readBytes(outside),bytes));
        removeLink(path); writeBytes(path,bytes);
    end
    bytes=readBytes(optical); delete(optical); makeSymlink(fullfile(folder,'absent'),optical);
    expectError(@() alev4.readSpatialBundle(directory), ...
        {'ALEV4:SpatialBundleMissing','ALEV4:InvalidSpatialMetadata'});
    removeLink(optical); writeBytes(optical,bytes);
    alias=fullfile(folder,'bundle_link'); makeSymlink(directory,alias);
    expectError(@() alev4.readSpatialBundle(alias),'ALEV4:SpatialBundleMissing');
    alev4.readSpatialBundle(directory);
end

function testInventory()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    result=fixture('single','post_optics',[2 3],1,false);
    directory=fullfile(folder,'inventory'); alev4.exportSpatialBundle(directory,result);
    extra=fullfile(directory,'extra'); writeBytes(extra,uint8('unexpected'));
    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata'); delete(extra);
    assert(mkdir(extra));
    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata'); rmdir(extra);
    makeSymlink(fullfile(folder,'absent'),extra);
    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata'); removeLink(extra);
    writeBytes(fullfile(directory,'psf.f64'),floatBytes(1));
    expectError(@() alev4.readSpatialBundle(directory),'ALEV4:InvalidSpatialMetadata');
end

function testExistingTargets()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    result=fixture('single','post_optics',[2 3],1,false);
    targets={'file','empty','nonempty','complete','link','dangling'};
    writeBytes(fullfile(folder,'file'),uint8('preserve file'));
    assert(mkdir(fullfile(folder,'empty'))); assert(mkdir(fullfile(folder,'nonempty')));
    writeBytes(fullfile(folder,'nonempty','sentinel'),uint8('preserve directory'));
    alev4.exportSpatialBundle(fullfile(folder,'complete'),result);
    original=readBytes(fullfile(folder,'complete','spatial.json'));
    makeSymlink(fullfile(folder,'complete'),fullfile(folder,'link'));
    makeSymlink(fullfile(folder,'missing'),fullfile(folder,'dangling'));
    before=namesOf(folder);
    for k=1:numel(targets)
        expectError(@() alev4.exportSpatialBundle(fullfile(folder,targets{k}),result),'ALEV4:SpatialAlreadyExists');
        assert(isequal(namesOf(folder),before));
    end
    assert(strcmp(fileread(fullfile(folder,'file')),'preserve file'));
    assert(isempty(namesOf(fullfile(folder,'empty'))));
    assert(strcmp(fileread(fullfile(folder,'nonempty','sentinel')),'preserve directory'));
    assert(isequal(readBytes(fullfile(folder,'complete','spatial.json')),original));
    assert(isSymlink(fullfile(folder,'link')) && isSymlink(fullfile(folder,'dangling')));
    expectError(@() alev4.exportSpatialBundle(fullfile(folder,'missing','target'),result),'ALEV4:SpatialBundleMissing');
    for bad={'',1,['a' char(0) 'b'],char('ab','cd'),'.','..'}
        expectError(@() alev4.exportSpatialBundle(bad{1},result),'ALEV4:InvalidSpatialPath');
        expectError(@() alev4.readSpatialBundle(bad{1}),'ALEV4:InvalidSpatialPath');
    end
end

function testOwnedFailureCleanup()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    result=fixture('single','post_optics',[2 3],1,false);
    target=fullfile(folder,'target'); assert(mkdir(target));
    writeBytes(fullfile(target,'sentinel'),uint8('unrelated existing file'));
    shadow=fullfile(folder,'shadow'); assert(mkdir(shadow));
    previous_path=path; path_guard=onCleanup(@() restoreMovePath(previous_path)); %#ok<NASGU>
    previous_warning=warning('query','all'); warning_guard=onCleanup(@() warning(previous_warning)); %#ok<NASGU>
    warning('off','all');
    for nesting=[false true]
        if nesting
            directory_action = [ ...
                'mkdir(destination); fid=fopen(fullfile(destination,''racer''),''wb''); fwrite(fid,uint8(''preserve racer''),''uint8''); fclose(fid);\n' ...
                '[~,name,ext]=fileparts(source); [ok,message]=copyfile(source,fullfile(destination,[name ext])); if ok, rmdir(source,''s''); end\n'];
        else
            directory_action='ok=false; message=''injected final spatial publication failure'';\n';
        end
        source=sprintf(['function [ok,message]=movefile(source,destination,varargin)\n' ...
            'if exist(source,''dir'')==7\n' directory_action 'return; end\n' ...
            '[ok,message]=copyfile(source,destination); if ok, delete(source); end\nend\n']);
        writeBytes(fullfile(shadow,'movefile.m'),uint8(source));
        addpath(shadow,'-begin'); clear movefile;
        assert(strcmp(which('movefile'),fullfile(shadow,'movefile.m')));
        rng(4801,'twister'); before_rng=rng;
        destination=fullfile(target,'publication');
        expectError(@() alev4.exportSpatialBundle(destination,result),'ALEV4:SpatialWriteFailed');
        assert(isequal(rng,before_rng));
        assert(strcmp(fileread(fullfile(target,'sentinel')),'unrelated existing file'));
        if nesting
            assert(isequal(namesOf(target),{'publication','sentinel'}));
            assert(isequal(namesOf(destination),{'racer'}));
            assert(strcmp(fileread(fullfile(destination,'racer')),'preserve racer'));
        else
            assert(isequal(namesOf(target),{'sentinel'}));
        end
    end
    clear path_guard;
end

function testNoisyRepeat()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    for mode={'single','dual'}
        result=fixture(mode{1},'post_optics',[7 9],2,true);
        a=fullfile(folder,[mode{1} '_a']); b=fullfile(folder,[mode{1} '_b']);
        alev4.exportSpatialBundle(a,result);
        again=resimulate(result,result.input_irradiance);
        assert(isequal(again.readout,result.readout)); alev4.exportSpatialBundle(b,again);
        [decoded,meta]=alev4.readSpatialBundle(a); assertRoundTrip(result,decoded,meta);
        names=namesOf(a); assert(isequal(names,namesOf(b)));
        for k=1:numel(names)
            left=fullfile(a,names{k}); right=fullfile(b,names{k});
            assert(isequal(readBytes(left),readBytes(right)));
            assertDistinct(left,right);
        end
        assert(any(result.readout.collected_electrons(:)~=result.readout.expected_electrons(:)));
    end
    dark=fixture('dual','post_optics',[7 9],1,true);
    dark=resimulate(dark,zeros(7,9));
    directory=fullfile(folder,'signed_dark'); alev4.exportSpatialBundle(directory,dark);
    decoded=alev4.readSpatialBundle(directory);
    assert(any(decoded.readout.merged.electrons(:)<0));
    assert(isequal(readBytes(fullfile(directory,'readout.merged.f64')),floatBytes(dark.readout.merged.electrons)));
end

function testRngRestoration()
    [folder,guard] = ownFolder(); %#ok<NASGU>
    for mode={'single','dual'}
        result=fixture(mode{1},'post_optics',[3 5],1,true);
        directory=fullfile(folder,mode{1});
        rng(4802,'twister'); before=rng;
        alev4.exportSpatialBundle(directory,result); assert(isequal(rng,before));
        alev4.readSpatialBundle(directory); assert(isequal(rng,before));
        expectError(@() alev4.exportSpatialBundle(directory,result),'ALEV4:SpatialAlreadyExists');
        assert(isequal(rng,before));
        bad=result; bad.readout.seed=bad.readout.seed+1;
        expectError(@() alev4.exportSpatialBundle(fullfile(folder,[mode{1} '_failure']),bad),'ALEV4:SpatialSemanticMismatch');
        assert(isequal(rng,before));
        meta=wireManifest(directory); changed=result.sampled_irradiance; changed(1)=changed(1)+1;
        replacePayload(directory,meta,'sampled_irradiance',floatBytes(changed));
        expectError(@() alev4.readSpatialBundle(directory),'ALEV4:SpatialSemanticMismatch');
        assert(isequal(rng,before));
    end
end

function testReadCloseFailures()
    [folder,guard]=ownFolder(); %#ok<NASGU>
    result=fixture('single','post_optics',[2 3],1,false);
    directory=fullfile(folder,'reads'); alev4.exportSpatialBundle(directory,result);
    shadow=fullfile(folder,'shadow'); assert(mkdir(shadow));
    source=sprintf(['function status=fclose(fid)\n' ...
        'global alev4_test_close_target alev4_test_close_hits;\n' ...
        'name=''''; try, name=fopen(fid); catch, end\n' ...
        'status=builtin(''fclose'',fid);\n' ...
        'if ischar(name) && strcmp(name,alev4_test_close_target)\n' ...
        'alev4_test_close_hits=alev4_test_close_hits+1; status=-1;\n' ...
        'end\nend\n']);
    writeBytes(fullfile(shadow,'fclose.m'),uint8(source));
    previous_path=path; path_guard=onCleanup(@()restoreReadClosePath(previous_path));
    previous_warning=warning('query','all'); warning_guard=onCleanup(@()warning(previous_warning)); %#ok<NASGU>
    warning('off','Octave:shadowed-function'); addpath(shadow,'-begin'); clear fclose;
    assert(strcmp(which('fclose'),fullfile(shadow,'fclose.m')));
    global alev4_test_close_target alev4_test_close_hits;
    payload=fullfile(directory,'input.f64'); manifest=fullfile(directory,'spatial.json');
    actions={@()alev4.spatialBundleUtil('readjson',manifest), ...
        @()alev4.spatialBundleUtil('hash',payload,48), ...
        @()alev4.spatialBundleUtil('readplane',payload,[2 3 1],'float64'), ...
        @()alev4.readSpatialBundle(directory)};
    targets={manifest,payload,payload,payload};
    rng(4803,'twister'); before_rng=rng; before_handles=fopen('all');
    for k=1:numel(actions)
        alev4_test_close_target=targets{k}; alev4_test_close_hits=0;
        expectError(actions{k},'ALEV4:SpatialReadFailed');
        assert(alev4_test_close_hits==1);
        assert(isequal(fopen('all'),before_handles) && isequal(rng,before_rng));
    end
    clear path_guard;
    alev4.readSpatialBundle(directory);
    assert(isequal(fopen('all'),before_handles) && isequal(rng,before_rng));
end

function restoreReadClosePath(previous)
    path(previous); clear fclose;
    clear global alev4_test_close_target alev4_test_close_hits;
end

function result=fixture(mode,stage,shape,bins,noisy)
    geometry=alev4.createSensorGeometry(struct('full_grid_size',shape,'pixel_pitch_m',1));
    grid=alev4.createSpatialGrid(struct('x_edges_m',0:shape(2),'y_edges_m',0:shape(1)));
    qe=zeros(bins,3);
    for k=1:bins, qe(k,:)=[0.5 0.25 0.75]/2^(k-1); end
    sensor=alev4.createBaselineSensor(struct('image_size',shape,'pixel_pitch_m',1, ...
        'wavelength_nm',(450:50:450+50*(bins-1))','bin_width_nm',(1:bins)', ...
        'qe',qe,'fill_factor',1,'shot_noise',noisy));
    if strcmp(mode,'single')
        sensor.read_noise_e=double(noisy); configuration=sensor;
    else
        configuration=alev4.createDualGainSensor(struct('sensor',sensor, ...
            'high_gain',struct('read_noise_e',double(noisy)), ...
            'low_gain',struct('read_noise_e',5*double(noisy))));
    end
    input=zeros([shape bins]);
    for k=1:bins
        for row=1:shape(1)
            for column=1:shape(2), input(row,column,k)=(100*k+10*row+column)^2/16; end
        end
    end
    options=struct('input_stage',stage,'spatial_provenance', ...
        struct('source','native_artifact_test','classification','assumed','matrix',[1 2;3 4]));
    result=alev4.simulateSpatialExposure(input,grid,geometry,configuration,1,48301,options);
end

function result=psfFixture()
    base=fixture('single','pre_psf',[4 7],2,false);
    geometry=alev4.createSensorGeometry(struct('full_grid_size',[5 7], ...
        'active_roi',[2 2 3 5],'pixel_pitch_m',1));
    configuration=alev4.bindSensorGeometry(base.configuration,geometry,'derive');
    kernel=[0 1 2;3 4 6]/16;
    psf=alev4.createOpticalPsf(struct('kernel',cat(3,kernel,rot90(kernel,2)), ...
        'origin_rc',[1 2],'spacing_yx_m',[1 1],'wavelength_nm',configuration.wavelength_nm));
    result=alev4.simulateSpatialExposure(base.input_irradiance,base.input_grid,geometry,configuration,1,48302, ...
        struct('psf',psf,'spatial_provenance',base.spatial_provenance));
end

function result=resimulate(result,input)
    options=struct('input_stage',result.input_stage,'spatial_provenance',result.spatial_provenance);
    if strcmp(result.input_stage,'pre_psf'), options.psf=result.psf; end
    result=alev4.simulateSpatialExposure(input,result.input_grid,result.geometry,result.configuration, ...
        result.readout.exposure_s,result.readout.seed,options);
end

function sensor=sensorOf(configuration)
    if strcmp(configuration.schema_version,'2.0'), sensor=configuration.sensor; else, sensor=configuration; end
end

function expected=chargeOracle(input,sensor,exposure)
    expected=zeros(sensor.image_size); tile=reshape(sensor.cfa_pattern,2,2).';
    for row=1:sensor.image_size(1)
        for column=1:sensor.image_size(2)
            colour=tile(mod(row-1,2)+1,mod(column-1,2)+1); channel=find('RGB'==colour);
            for k=1:numel(sensor.wavelength_nm)
                expected(row,column)=expected(row,column)+input(row,column,k)*sensor.qe(k,channel)*sensor.bin_width_nm(k);
            end
            expected(row,column)=expected(row,column)*exposure*sensor.pixel_pitch_m^2*sensor.fill_factor;
        end
    end
end

function assertRoundTrip(expected,actual,meta)
    for key={'input_irradiance','optical_irradiance','sampled_irradiance','input_grid','optical_grid', ...
            'geometry','configuration','psf','operation_order','spatial_provenance','readout_mode','input_stage'}
        assert(isequal(actual.(key{1}),expected.(key{1})),['Round trip changed ' key{1}]);
    end
    assert(isequal(actual.readout.expected_electrons,expected.readout.expected_electrons));
    assert(isequal(actual.readout.expected_incident_photons,expected.readout.expected_incident_photons));
    if strcmp(expected.readout_mode,'single')
        assert(isequal(actual.readout.raw_dn,expected.readout.raw_dn));
    else
        assert(isequal(actual.readout.high_gain.raw_dn,expected.readout.high_gain.raw_dn));
        assert(isequal(actual.readout.low_gain.raw_dn,expected.readout.low_gain.raw_dn));
        assert(isequal(actual.readout.merged.electrons,expected.readout.merged.electrons));
        assert(isequal(actual.readout.reconstruction_valid,expected.readout.reconstruction_valid));
    end
    assert(strcmp(meta.format,'ALEV4-SYNTHETIC-SPATIAL') && strcmp(meta.algorithm_version,'phase3-spatial-v1'));
    assert(meta.synthetic && ~meta.calibrated_alev4 && ~meta.authentic_arriraw);
    assert(strcmp(meta.byte_order,'little-endian') && strcmp(meta.array_order,'plane-major-row-major'));
    assert(meta.exposure_s==expected.readout.exposure_s && meta.seed==expected.readout.seed);
end

function meta=wireManifest(directory)
    meta=alev4.spatialDecodeJson(fileread(fullfile(directory,'spatial.json')));
end

function writeManifest(directory,meta)
    writeBytes(fullfile(directory,'spatial.json'),unicode2native([alev4.encodeBundleJson(meta) sprintf('\n')],'UTF-8'));
end

function meta=replacePayload(directory,meta,key,bytes)
    descriptor=meta.files.(key); bytes=uint8(bytes(:));
    writeBytes(fullfile(directory,descriptor.name),bytes);
    meta.files.(key).sha256=sha256(bytes);
    meta.files.(key).byte_count=double(numel(bytes));
    writeManifest(directory,meta);
end

function replaceNested(directory,outer,nested)
    bytes=unicode2native([alev4.encodeBundleJson(nested) sprintf('\n')],'UTF-8');
    replacePayload(directory,outer,'readout_metadata',bytes);
end

function value=changedIdentity(value,name)
    if strcmp(name,'seed'), value=value+1;
    elseif strcmp(name,'exposure_s'), value=value+0.5;
    elseif strcmp(name,'runtime'), value.version=[value.version '-association-test'];
    else
        if strcmp(value.repository_head,repmat('a',1,40)), value.repository_head=repmat('b',1,40);
        else, value.repository_head=repmat('a',1,40); end
    end
end

function checkInventoryAndHashes(directory,meta)
    keys=fieldnames(meta.files); names={'spatial.json'};
    for k=1:numel(keys)
        descriptor=meta.files.(keys{k}); names{end+1}=descriptor.name; %#ok<AGROW>
        bytes=readBytes(fullfile(directory,descriptor.name));
        assert(numel(bytes)==descriptor.byte_count);
        assert(strcmp(sha256(bytes),descriptor.sha256));
        assert(isequal(sort(fieldnames(descriptor)),sort({'name';'sha256';'byte_count';'sample_type';'shape';'units'})));
    end
    assert(isequal(namesOf(directory),sort(names)));
end

function bytes=floatBytes(values)
    bytes=zeros(8*numel(values),1,'uint8'); position=1;
    for plane=1:size(values,3)
        for row=1:size(values,1)
            for column=1:size(values,2)
                word=num2hex(double(values(row,column,plane)));
                for octet=1:8
                    offset=17-2*octet;
                    bytes(position)=uint8(hex2dec(word(offset:offset+1))); position=position+1;
                end
            end
        end
    end
end

function bytes=uint16Bytes(values)
    bytes=zeros(2*numel(values),1,'uint8'); position=1;
    for row=1:size(values,1)
        for column=1:size(values,2)
            code=double(values(row,column));
            bytes(position)=uint8(mod(code,256)); bytes(position+1)=uint8(floor(code/256)); position=position+2;
        end
    end
end

function bytes=rowBytes(values)
    bytes=zeros(numel(values),1,'uint8'); position=1;
    for row=1:size(values,1)
        for column=1:size(values,2), bytes(position)=values(row,column); position=position+1; end
    end
end

function digest=sha256(bytes)
    if exist('hash','builtin')
        digest=lower(hash('sha256',char(bytes(:).')));
    elseif (exist('usejava','builtin') || exist('usejava','file')) && usejava('jvm')
        md=javaMethod('getInstance','java.security.MessageDigest','SHA-256');
        md.update(typecast(uint8(bytes(:)),'int8'));
        raw=typecast(int8(md.digest()),'uint8'); digest=lower(reshape(dec2hex(raw,2).',1,[]));
    else
        error('ALEV4:TestFilesystemCapability','SHA-256 tests require Octave hash or a MATLAB JVM.');
    end
end

function bytes=readBytes(path)
    fid=fopen(path,'rb'); assert(fid>=0); guard=onCleanup(@() closeQuietly(fid)); %#ok<NASGU>
    bytes=fread(fid,Inf,'*uint8'); [message,status]=ferror(fid); assert(status==0,message);
end

function writeBytes(path,bytes)
    fid=fopen(path,'wb'); assert(fid>=0); guard=onCleanup(@() closeQuietly(fid)); %#ok<NASGU>
    count=fwrite(fid,bytes,'uint8'); assert(count==numel(bytes)); assert(fclose(fid)==0);
end

function closeQuietly(fid)
    try, fclose(fid); catch, end
end

function observed=expectError(action,identifiers)
    if ischar(identifiers), identifiers={identifiers}; end
    try
        action();
    catch err
        observed=err;
        assert(any(strcmp(err.identifier,identifiers)), ...
            sprintf('Expected %s; observed %s: %s',strjoin(identifiers,', '),err.identifier,err.message));
        return;
    end
    error('ALEV4:TestExpectedRejection','Expected rejection: %s.',strjoin(identifiers,', '));
end

function names=namesOf(directory)
    entries=dir(directory); names={entries.name}; names=sort(names(~ismember(names,{'.','..'})));
end

function [folder,guard]=ownFolder()
    folder=tempname(); assert(mkdir(folder)); marker=fullfile(folder,'.phase3-artifacts-owned');
    writeBytes(marker,uint8('phase3-artifacts-test')); guard=onCleanup(@() removeOwned(folder,marker));
end

function removeOwned(folder,marker)
    if exist(folder,'dir')==7 && exist(marker,'file')==2 && strcmp(fileread(marker),'phase3-artifacts-test')
        [ok,message]=rmdir(folder,'s'); assert(ok,message);
    end
end

function makeHardLink(source,destination)
    if exist('link','builtin') || exist('link','file')
        [status,message]=link(source,destination); assert(status==0,message);
    elseif (exist('usejava','builtin') || exist('usejava','file')) && usejava('jvm')
        from=javaObject('java.io.File',source); to=javaObject('java.io.File',destination);
        javaMethod('createLink','java.nio.file.Files',to.toPath(),from.toPath());
    else
        error('ALEV4:TestFilesystemCapability','Hardlink tests need native link or Java NIO.');
    end
end

function makeSymlink(target,destination)
    if exist('symlink','builtin') || exist('symlink','file')
        [status,message]=symlink(target,destination); assert(status==0,message);
    elseif (exist('usejava','builtin') || exist('usejava','file')) && usejava('jvm')
        from=javaObject('java.io.File',target); to=javaObject('java.io.File',destination);
        attributes=javaArray('java.nio.file.attribute.FileAttribute',0);
        javaMethod('createSymbolicLink','java.nio.file.Files',to.toPath(),from.toPath(),attributes);
    else
        error('ALEV4:TestFilesystemCapability','Symlink tests need native symlink or Java NIO.');
    end
end

function value=isSymlink(path)
    if exist('lstat','builtin') || exist('lstat','file')
        [info,status]=lstat(path); value=status==0 && info.modestr(1)=='l';
    else
        file=javaObject('java.io.File',path); value=javaMethod('isSymbolicLink','java.nio.file.Files',file.toPath());
    end
end

function removeLink(path)
    if exist('unlink','builtin') || exist('unlink','file')
        [status,message]=unlink(path); assert(status==0,message);
    else
        file=javaObject('java.io.File',path); javaMethod('delete','java.nio.file.Files',file.toPath());
    end
end

function assertDistinct(left,right)
    if exist('lstat','builtin') || exist('lstat','file')
        [a,sa]=lstat(left); [b,sb]=lstat(right);
        assert(sa==0 && sb==0 && (a.dev~=b.dev || a.ino~=b.ino));
    else
        a=javaObject('java.io.File',left); b=javaObject('java.io.File',right);
        assert(~javaMethod('isSameFile','java.nio.file.Files',a.toPath(),b.toPath()));
    end
end

function restoreMovePath(previous)
    path(previous); clear movefile;
end
