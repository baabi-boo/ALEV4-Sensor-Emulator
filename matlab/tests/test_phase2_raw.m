function report = test_phase2_raw()
%TEST_PHASE2_RAW Independent bundle bytes, validation and failed-publication checks.
%   Test-owned temporary directories contain all mutations. No camera data or
%   production functions are edited. Temporary path-local replacements inject
%   publication and numeric-formatting faults, then restore the caller path.
    previous_rng = rng;
    rng_guard = onCleanup(@() rng(previous_rng)); %#ok<NASGU>
    functions = {@testByteOrder, @testSignedFloat, @testFlags, @testLengths, ...
        @testCorruption, @testMetadata, @testOverwrite, @testInvalidResults, ...
        @testPublicationFailure, @testPathsAndManifestLimits, ...
        @testPortableStemsAndJsonKeys, @testMetadataPolicyAndAliases, ...
        @testMergeTolerance, @testDanglingSymlinkPreflight, ...
        @testNumericMetadataFidelity, @testMetadataFailureBeforePublication};
    names = {'independent_nonsquare_rowmajor_little_endian_bytes', ...
        'signed_float64_payload_and_negative_one_byte_oracle', ...
        'physical_saturation_distinct_from_observed_rail_validity', ...
        'all_payload_missing_truncated_and_extra_bytes_rejected', ...
        'raw_merged_and_diagnostic_corruption_rejected', ...
        'complete_metadata_and_exact_payload_association', ...
        'all_existing_destinations_preserved_without_overwrite', ...
        'inconsistent_simulation_results_rejected_before_staging', ...
        'late_publication_failure_removes_owned_files_and_staging', ...
        'path_and_manifest_size_boundaries', ...
        'portable_stems_and_original_json_key_validation', ...
        'runtime_payload_field_policy_and_hardlink_rejection', ...
        'native_python_merged_payload_ulp_tolerance', ...
        'dangling_symlink_export_and_demo_preflight', ...
        'tiny_and_extreme_scale_metadata_numeric_fidelity', ...
        'metadata_precision_failure_rejected_before_publication'};
    for k = 1:numel(functions)
        functions{k}();
    end
    tests = repmat(struct('name', '', 'status', 'passed', 'passed', true), 1, numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    report = struct('suite', 'phase2_raw', 'status', 'passed', 'passed', true, ...
        'test_count', numel(names), 'tests', tests, ...
        'metrics', struct('payloads_per_bundle', 4, 'fixture_shape', [3 5], ...
        'float64_oracle', 'IEEE-754 negative one bytes 000000000000f0bf'));
    fprintf('PASS: Phase 2 RAW bundle validation, %d test groups.\n', numel(names));
end

function testByteOrder()
    [folder, guard] = ownFolder(); %#ok<NASGU>
    [cfg, result, mu] = fixture();
    base = fullfile(folder, 'nonsquare');
    files = alev4.exportDualGainBundle(result, cfg, base);
    [decoded, meta] = alev4.readDualGainBundle(base);
    for item = {'high_gain', 'low_gain'}
        name = item{1}; settings = cfg.(name);
        expected = zeros(2*numel(mu), 1, 'uint8'); position = 1;
        for row = 1:3
            for column = 1:5
                stored = min(mu(row, column), 30000);
                code = min(floor(stored * settings.gain_dn_per_e + ...
                    settings.black_level_dn + 0.5), 2^settings.adc_bits-1);
                expected(position) = uint8(mod(code, 256));
                expected(position+1) = uint8(floor(code/256)); position = position+2;
            end
        end
        if strcmp(name, 'high_gain'), path = files.high_raw; else, path = files.low_raw; end
        assert(isequal(readBytes(path), expected), 'Independent row-major byte oracle failed.');
        assert(isequal(decoded.(name).raw_dn, result.(name).raw_dn));
        assert(isa(decoded.(name).raw_dn, 'uint16'));
    end
    assert(isequal(decoded.merged.electrons, result.merged.electrons));
    assert(isequal(decoded.reconstruction_valid, result.reconstruction_valid));
    assert(isequal(meta.image_size, [3 5]) && meta.exposure_s == result.exposure_s);
    assert(strcmp(meta.algorithm_version, 'phase2-dual-gain-v1'));
    assert(meta.synthetic && ~meta.calibrated_alev4 && ~meta.authentic_arriraw);
    assertMetadataEquivalent(cfg, meta.configuration);
end

function testSignedFloat()
    [folder, guard] = ownFolder(); %#ok<NASGU>
    [cfg, ~] = fixture(); cfg.sensor.image_size = [17 31];
    cfg.high_gain.read_noise_e = 1; cfg.low_gain.read_noise_e = 5;
    result = alev4.simulateDualGainExposure(zeros(17,31), cfg, 0.01, 9202);
    assert(any(result.merged.electrons(:) < 0), 'Dark fixture must include signed negative estimates.');
    base = fullfile(folder, 'signed');
    alev4.exportDualGainBundle(result, cfg, base);
    decoded = alev4.readDualGainBundle(base);
    assert(isequal(decoded.merged.electrons, result.merged.electrons));
    bytes = readBytes([base '.merged.f64']);
    location = 0; index = 0;
    for row = 1:17
        for column = 1:31
            index = index + 1;
            if result.merged.electrons(row,column) == -1, location = index; end
        end
    end
    assert(location > 0, 'Seeded dark fixture must contain an exact -1 electron code.');
    expected = uint8([0;0;0;0;0;0;240;191]);
    assert(isequal(bytes((location-1)*8+(1:8)), expected), ...
        'Signed float64 payload does not use little-endian IEEE-754 bytes.');
end

function testFlags()
    [folder, guard] = ownFolder(); %#ok<NASGU>
    [cfg, result] = fixture(); base = fullfile(folder, 'flags');
    alev4.exportDualGainBundle(result, cfg, base);
    decoded = alev4.readDualGainBundle(base);
    % First row: dark, shadow, blend, recoverable highlight, physical saturation.
    assert(isequal(decoded.flags(1,:), uint8([224 224 224 196 69])));
    assert(decoded.merged.valid(1,5) && ~decoded.reconstruction_valid(1,5));
    assert(decoded.full_well_saturated(1,5) && ~decoded.low_gain.adc_high_clipped(1,5));
    assert(decoded.reconstruction_valid(1,4) && decoded.high_gain.adc_high_clipped(1,4));
    assert(~decoded.high_gain.adc_low_clipped(1,4));
    assert(decoded.merged.electrons(1,4) == 12000);
    assert(decoded.merged.electrons(1,5) == 30000);
end

function testLengths()
    [folder, guard] = ownFolder(); %#ok<NASGU>
    [cfg, result] = fixture(); base = fullfile(folder, 'lengths');
    alev4.exportDualGainBundle(result, cfg, base);
    for suffix = {'.high.raw', '.low.raw', '.merged.f64', '.flags.u8'}
        file = [base suffix{1}]; original = readBytes(file);
        delete(file);
        expectError(@() alev4.readDualGainBundle(base), 'ALEV4:DualGainBundleMissing');
        writeBytes(file, original(1:end-1));
        expectError(@() alev4.readDualGainBundle(base), 'ALEV4:DualGainSizeMismatch');
        writeBytes(file, [original; uint8(0)]);
        expectError(@() alev4.readDualGainBundle(base), 'ALEV4:DualGainSizeMismatch');
        writeBytes(file, original);
    end
    decoded = alev4.readDualGainBundle(base);
    assert(isequal(decoded.high_gain.raw_dn, result.high_gain.raw_dn));
end

function testCorruption()
    [folder, guard] = ownFolder(); %#ok<NASGU>
    [cfg, result] = fixture(); base = fullfile(folder, 'corruption');
    alev4.exportDualGainBundle(result, cfg, base);
    for suffix = {'.high.raw', '.low.raw'}
        file = [base suffix{1}]; original = readBytes(file); bad = original;
        bad(1:2) = uint8([255;255]); writeBytes(file, bad);
        expectError(@() alev4.readDualGainBundle(base), 'ALEV4:InvalidDualGainMetadata');
        writeBytes(file, original);
    end
    file = [base '.high.raw']; original = readBytes(file); bad = original;
    bad(1) = bad(1)+1; writeBytes(file,bad);
    expectError(@() alev4.readDualGainBundle(base), 'ALEV4:InvalidDualGainMetadata');
    writeBytes(file,original);
    file = [base '.merged.f64']; original = readBytes(file);
    for value = [NaN Inf -Inf 0.25]
        changed = result.merged.electrons; changed(1,1) = value;
        writePlane(file, changed, 'double');
        expectError(@() alev4.readDualGainBundle(base), 'ALEV4:InvalidDualGainMetadata');
    end
    writeBytes(file, original);
    file = [base '.flags.u8']; original = readBytes(file);
    for bit = [1 2 4 8 16 32 64 128]
        bad = original; bad(1) = bitxor(bad(1), uint8(bit)); writeBytes(file,bad);
        expectError(@() alev4.readDualGainBundle(base), 'ALEV4:InvalidDualGainMetadata');
    end
    writeBytes(file,original);
end

function testMetadata()
    [folder, guard] = ownFolder(); %#ok<NASGU>
    [cfg, result] = fixture(); base = fullfile(folder, 'metadata');
    alev4.exportDualGainBundle(result, cfg, base);
    original = jsondecode(fileread([base '.json']));
    for field = {'configuration', 'exposure_s', 'seed', 'runtime', 'provenance', 'units'}
        bad = rmfield(original, field{1}); writeJson([base '.json'], bad);
        expectError(@() alev4.readDualGainBundle(base), 'ALEV4:InvalidDualGainMetadata');
    end
    for field = {'sensor', 'high_gain', 'low_gain', 'merge'}
        bad = original; names = fieldnames(bad.configuration.(field{1}));
        bad.configuration.(field{1}) = rmfield(bad.configuration.(field{1}),names{1});
        writeJson([base '.json'],bad);
        expectError(@() alev4.readDualGainBundle(base), 'ALEV4:InvalidDualGainMetadata');
    end
    fields = {'format','schema_version','algorithm_version','array_order','byte_order', ...
        'input_units','cfa_origin','synthetic','calibrated_alev4','authentic_arriraw','seed','exposure_s','image_size'};
    values = {'ARRIRAW','2.0','phase1-baseline-v1','column-major','big-endian', ...
        'electrons','bottom-right',1,true,true,0.5,-1,[5 3]};
    for k = 1:numel(fields)
        bad = original; bad.(fields{k}) = values{k}; writeJson([base '.json'],bad);
        expectError(@() alev4.readDualGainBundle(base), 'ALEV4:InvalidDualGainMetadata');
    end
    for name = {'../elsewhere.high.raw', 'another.high.raw', '/absolute.high.raw'}
        bad = original; bad.files.high_raw = name{1}; writeJson([base '.json'],bad);
        expectError(@() alev4.readDualGainBundle(base), 'ALEV4:InvalidDualGainMetadata');
    end
    bad = original; bad.units.merged_electrons = 'DN'; writeJson([base '.json'],bad);
    expectError(@() alev4.readDualGainBundle(base), 'ALEV4:InvalidDualGainMetadata');
    bad = original; bad.configuration.high_gain.gain_dn_per_e = -1; writeJson([base '.json'],bad);
    expectError(@() alev4.readDualGainBundle(base), 'ALEV4:InvalidDualGainMetadata');
    bad = original; bad.provenance.repository_head = 'not-a-SHA'; writeJson([base '.json'],bad);
    expectError(@() alev4.readDualGainBundle(base), 'ALEV4:InvalidDualGainMetadata');
    writeJson([base '.json'],original);
    alev4.readDualGainBundle(base);
end

function testOverwrite()
    [folder, guard] = ownFolder(); %#ok<NASGU>
    [cfg, result] = fixture(); suffixes = {'.high.raw','.low.raw','.merged.f64','.flags.u8','.json'};
    for k = 1:numel(suffixes)
        base = fullfile(folder, ['collision_' num2str(k)]);
        original = uint8([31;13;19]); writeBytes([base suffixes{k}],original);
        before = fileNames(folder);
        expectError(@() alev4.exportDualGainBundle(result,cfg,base),'ALEV4:DualGainAlreadyExists');
        assert(isequal(before,fileNames(folder)));
        assert(isequal(readBytes([base suffixes{k}]),original));
    end
    base = fullfile(folder,'complete'); alev4.exportDualGainBundle(result,cfg,base);
    originals = cellfun(@(s) readBytes([base s]),suffixes,'UniformOutput',false);
    expectError(@() alev4.exportDualGainBundle(result,cfg,base),'ALEV4:DualGainAlreadyExists');
    for k = 1:numel(suffixes), assert(isequal(readBytes([base suffixes{k}]),originals{k})); end
end

function testInvalidResults()
    [folder, guard] = ownFolder(); %#ok<NASGU>
    [cfg,result] = fixture(); base = fullfile(folder,'invalid');
    bads = cell(1,10);
    bads{1}=rmfield(result,'expected_incident_photons');
    bads{2}=result; bads{2}.seed=NaN;
    bads{3}=result; bads{3}.collected_electrons(1,1)=1;
    bads{4}=result; bads{4}.charge_electrons(1,1)=1;
    bads{5}=result; bads{5}.full_well_saturated(1,1)=true;
    bads{6}=result; bads{6}.high_gain.raw_dn=double(result.high_gain.raw_dn);
    bads{7}=result; bads{7}.high_gain.read_electrons(1,1)=1;
    bads{8}=result; bads{8}.merged.weight_high(1,1)=0;
    bads{9}=result; bads{9}.reconstruction_valid(1,5)=true;
    bads{10}=result; bads{10}.expected_incident_photons(1,2)=1;
    before = fileNames(folder);
    for k=1:numel(bads)
        expectError(@() alev4.exportDualGainBundle(bads{k},cfg,base),'ALEV4:InvalidDualGainResult');
        assert(isequal(before,fileNames(folder)), 'Rejected result left staging or published files.');
    end
end

function testPublicationFailure()
    [folder, guard] = ownFolder(); %#ok<NASGU>
    [cfg,result] = fixture(); destination=fullfile(folder,'target'); assert(mkdir(destination));
    shadow=fullfile(folder,'shadow'); assert(mkdir(shadow));
    source = sprintf(['function [ok,message]=movefile(source,destination,varargin)\n' ...
        'persistent invocation; if isempty(invocation), invocation=0; end\n' ...
        'invocation=invocation+1;\n' ...
        'if invocation==2, ok=false; message=''injected second publication failure''; return; end\n' ...
        '[ok,message]=copyfile(source,destination); if ok, delete(source); end\n' ...
        'end\n']);
    writeBytes(fullfile(shadow,'movefile.m'),uint8(source));
    previous_path=path; path_guard=onCleanup(@() restorePath(previous_path)); %#ok<NASGU>
    previous_warning=warning('query','all'); warning_guard=onCleanup(@() warning(previous_warning)); %#ok<NASGU>
    warning('off','all'); addpath(shadow,'-begin'); clear movefile;
    assert(strcmp(which('movefile'),fullfile(shadow,'movefile.m')));
    before=fileNames(destination);
    expectError(@() alev4.exportDualGainBundle(result,cfg,fullfile(destination,'partial')), ...
        'ALEV4:DualGainWriteFailed');
    assert(isequal(before,fileNames(destination)), ...
        'Second-publication failure left published or staged files.');
    clear path_guard;
end

function testPathsAndManifestLimits()
    [folder, guard] = ownFolder(); %#ok<NASGU>
    [cfg,result]=fixture();
    for bad = {'',7,['bad' char(0) 'path'],char('row1','row2')}
        expectError(@() alev4.readDualGainBundle(bad{1}),'ALEV4:InvalidDualGainPath');
        expectError(@() alev4.exportDualGainBundle(result,cfg,bad{1}),'ALEV4:InvalidDualGainPath');
    end
    expectError(@() alev4.readDualGainBundle(fullfile(folder,'absent')),'ALEV4:DualGainBundleMissing');
    expectError(@() alev4.exportDualGainBundle(result,cfg,fullfile(folder,'absent','frame')), ...
        'ALEV4:DualGainDirectoryMissing');
    base=fullfile(folder,'limits'); alev4.exportDualGainBundle(result,cfg,base);
    original=readBytes([base '.json']);
    for bad = {'{broken','[]','null','{}'}
        writeBytes([base '.json'],uint8(bad{1}));
        expectError(@() alev4.readDualGainBundle(base),'ALEV4:InvalidDualGainMetadata');
    end
    padded=[original;repmat(uint8(32),2000000-numel(original),1)];
    writeBytes([base '.json'],padded); alev4.readDualGainBundle(base);
    writeBytes([base '.json'],[padded;uint8(32)]);
    expectError(@() alev4.readDualGainBundle(base),'ALEV4:InvalidDualGainMetadata');
end

function testPortableStemsAndJsonKeys()
    [folder, guard] = ownFolder(); %#ok<NASGU>
    [cfg,result] = fixture();
    for name = {'colon:name', ['back' char(92) 'slash'], ['tab' char(9) 'name']}
        base = fullfile(folder, name{1});
        expectError(@() alev4.exportDualGainBundle(result,cfg,base),'ALEV4:InvalidDualGainPath');
        expectError(@() alev4.readDualGainBundle(base),'ALEV4:InvalidDualGainPath');
    end
    % Restriction is on the stem, not on a legitimate parent path.
    parent = fullfile(folder, 'a parent with spaces'); assert(mkdir(parent));
    base = fullfile(parent, 'escaped'); alev4.exportDualGainBundle(result,cfg,base);
    original = char(readBytes([base '.json']).');
    bad = strrep(original, '"gain_dn_per_e":', '"gain-dn-per-e":');
    writeBytes([base '.json'], uint8(bad));
    expectError(@() alev4.readDualGainBundle(base),'ALEV4:InvalidDualGainMetadata');
    for prefix = {'{"synthetic":false,', ['{"synt' char(92) 'u0068etic":false,']}
        writeBytes([base '.json'], uint8([prefix{1} original(2:end)]));
        expectError(@() alev4.readDualGainBundle(base),'ALEV4:InvalidDualGainMetadata');
    end
    bad = strrep(original, '"high_gain":{', ...
        ['"high_gain":{"gain' char(92) 'u005fdn_per_e":4,']);
    writeBytes([base '.json'], uint8(bad));
    expectError(@() alev4.readDualGainBundle(base),'ALEV4:InvalidDualGainMetadata');
    % A valid escaped spelling is legal once, and repeats in other objects
    % must not be confused with a duplicate in this object.
    valid = strrep(original, '"gain_dn_per_e":', ['"gain' char(92) 'u005fdn_per_e":']);
    valid = [char(9) char(10) valid char(13) ' '];
    writeBytes([base '.json'], uint8(valid));
    decoded = alev4.readDualGainBundle(base);
    assert(isequal(decoded.merged.electrons,result.merged.electrons));
    parsed = alev4.decodeBundleJson('{"a":{"key":1},"b":[{"key":2},{"key":3}]}');
    assert(parsed.a.key == 1);
    note = struct('text', ['braces {}[] and a quote ' char(34) ' inside text']);
    assert(isequal(alev4.decodeBundleJson(jsonencode(note)),note));
    deepest = [repmat('[',1,64) '0' repmat(']',1,64)];
    alev4.decodeBundleJson(deepest);
    expectError(@() alev4.decodeBundleJson(['[' deepest ']']),'ALEV4:InvalidDualGainMetadata');
    fields = cell(1,256);
    for k = 1:256, fields{k} = sprintf('"field%d":0',k); end
    wide = ['{' strjoin(fields,',') '}']; alev4.decodeBundleJson(wide);
    expectError(@() alev4.decodeBundleJson([wide(1:end-1) ',"extra":0}']), ...
        'ALEV4:InvalidDualGainMetadata');
    expectError(@() alev4.decodeBundleJson('{"a":1e400}'),'ALEV4:InvalidDualGainMetadata');
end

function testMetadataPolicyAndAliases()
    [folder, guard] = ownFolder(); %#ok<NASGU>
    [cfg,~] = fixture();
    result = alev4.simulateDualGainExposure(zeros(cfg.sensor.image_size),cfg,0.01,9201);
    base = fullfile(folder,'policy'); alev4.exportDualGainBundle(result,cfg,base);
    original = jsondecode(fileread([base '.json']));
    bad = original; bad.runtime.name = 'Unknown runtime'; writeJson([base '.json'],bad);
    expectError(@() alev4.readDualGainBundle(base),'ALEV4:InvalidDualGainMetadata');
    for name = {'files','units'}
        bad = original; bad.(name{1}).extra = 'unused'; writeJson([base '.json'],bad);
        expectError(@() alev4.readDualGainBundle(base),'ALEV4:InvalidDualGainMetadata');
    end
    writeJson([base '.json'],original);
    assert(isequal(readBytes([base '.high.raw']),readBytes([base '.low.raw'])));
    delete([base '.low.raw']); makeHardLink([base '.high.raw'],[base '.low.raw']);
    expectError(@() alev4.readDualGainBundle(base),'ALEV4:InvalidDualGainMetadata');
end

function testMergeTolerance()
    [folder, guard] = ownFolder(); %#ok<NASGU>
    [cfg,result] = fixture(); base = fullfile(folder,'ulp');
    alev4.exportDualGainBundle(result,cfg,base);
    changed = result.merged.electrons;
    assert(changed(1,1) == 0);
    changed(1,1) = 32*eps(1); writePlane([base '.merged.f64'],changed,'double');
    decoded = alev4.readDualGainBundle(base);
    assert(decoded.merged.electrons(1,1) == changed(1,1));
    changed(1,1) = 128*eps(1); writePlane([base '.merged.f64'],changed,'double');
    expectError(@() alev4.readDualGainBundle(base),'ALEV4:InvalidDualGainMetadata');
end

function testDanglingSymlinkPreflight()
    [folder, guard] = ownFolder(); %#ok<NASGU>
    [cfg,result] = fixture(); base = fullfile(folder,'dangling');
    target = fullfile(folder,'missing_target');
    link_path = [base '.high.raw']; makeSymlink(target,link_path);
    assert(alev4.bundlePathExists(link_path));
    before = fileNames(folder);
    expectError(@() alev4.exportDualGainBundle(result,cfg,base),'ALEV4:DualGainAlreadyExists');
    assert(isequal(before,fileNames(folder)) && isSymlink(link_path));
    demo = fullfile(folder,'demo'); assert(mkdir(demo));
    link_path = fullfile(demo,'dark.high.raw'); makeSymlink(target,link_path);
    before = fileNames(demo);
    expectError(@() phase2_demo(demo),'ALEV4:DualGainAlreadyExists');
    assert(isequal(before,fileNames(demo)) && isSymlink(link_path));
end

function testNumericMetadataFidelity()
    values = [0, 1e-20, 1e-300, realmin, realmax, 1/3, 0.1, pi, ...
        1+eps(1), 1e300, -1e-20];
    [text, decoded] = alev4.encodeBundleJson(values);
    assertMetadataClose(values, decoded);
    % str2double is an independent decimal conversion from the native JSON
    % decoder. Each literal must retain the original binary64 value exactly.
    tokens = strsplit(text(2:end-1), ',');
    assert(isequal(cellfun(@str2double,tokens),values));
    note = ['quote ' char(34) ', slash ' char(92) ', unicode ' ...
        native2unicode(uint8([206 187]),'UTF-8')];
    source = struct('matrix',[1e-20 1/3; 1e-300 pi], ...
        'column',[1e-20;1e300], 'note',note, 'flag',true, 'empty','');
    [~, parsed] = alev4.encodeBundleJson(source);
    assert(isequal(size(parsed.matrix),[2 2]));
    assertMetadataClose(source.matrix,parsed.matrix);
    assertMetadataClose(source.column,parsed.column);
    assert(isequal(parsed.note,note) && parsed.flag && isempty(parsed.empty));

    [folder, guard] = ownFolder(); %#ok<NASGU>
    cfg = alev4.createDualGainSensor(struct('sensor', ...
        struct('image_size',[1 1],'shot_noise',false), ...
        'high_gain',struct('read_noise_e',0),'low_gain',struct('read_noise_e',0)));
    irradiance = ones(1,1,numel(cfg.sensor.wavelength_nm))*1e30;
    for exposure = [1e-20, 0]
        result = alev4.simulateDualGainExposure(irradiance,cfg,exposure,39);
        if exposure > 0, name = 'tiny_exposure'; else, name = 'zero_exposure'; end
        base = fullfile(folder,name);
        alev4.exportDualGainBundle(result,cfg,base);
        [frame, metadata] = alev4.readDualGainBundle(base);
        assertMetadataClose(exposure,metadata.exposure_s);
        assertMetadataClose(cfg.sensor.qe,metadata.configuration.sensor.qe);
        assert(isequal(frame.merged.electrons,result.merged.electrons));
        token = regexp(fileread([base '.json']), '"exposure_s":([^,}]+)', 'tokens','once');
        assert(~isempty(token) && str2double(token{1}) == exposure);
        if exposure > 0
            assert(frame.high_gain.raw_dn == 135 && metadata.exposure_s > 0);
            assert(abs(result.expected_electrons - 17.643478212390843) < 1e-12);
        else
            assert(frame.high_gain.raw_dn == 64 && metadata.exposure_s == 0);
        end
    end

    [cfg,~] = fixture(); cfg.sensor.image_size = [2 2];
    cfg.sensor.qe = [1e-20 3e-20 7e-20];
    result = alev4.simulateDualGainExposure(ones(2,2)*1e34,cfg,0.01,39);
    base = fullfile(folder,'tiny_qe'); alev4.exportDualGainBundle(result,cfg,base);
    [frame, metadata] = alev4.readDualGainBundle(base);
    assertMetadataClose(cfg.sensor.qe,metadata.configuration.sensor.qe);
    assert(all(metadata.configuration.sensor.qe > 0));
    assert(isequal(frame.high_gain.raw_dn,result.high_gain.raw_dn));

    % Scaling charge and inverse readout gains together keeps observable DN
    % ordinary while exercising valid metadata near both binary64 extremes.
    for scale = [1e-300, 1e300]
        [cfg,~] = fixture(); cfg.sensor.image_size = [1 1];
        cfg.sensor.full_well_e = 30000*scale;
        cfg.high_gain.gain_dn_per_e = 4/scale;
        cfg.low_gain.gain_dn_per_e = 0.1/scale;
        cfg.merge.start_e = 600*scale; cfg.merge.end_e = 900*scale;
        exposure = 0.01*scale;
        result = alev4.simulateDualGainExposure(2e14,cfg,exposure,39);
        base = fullfile(folder,sprintf('scale_%g',scale));
        alev4.exportDualGainBundle(result,cfg,base);
        [frame, metadata] = alev4.readDualGainBundle(base);
        assert(frame.high_gain.raw_dn == 104 && metadata.exposure_s > 0);
        assertMetadataClose(exposure,metadata.exposure_s);
        assertMetadataClose(cfg.high_gain.gain_dn_per_e, ...
            metadata.configuration.high_gain.gain_dn_per_e);
        assertMetadataClose(cfg.sensor.full_well_e,metadata.configuration.sensor.full_well_e);
        assert(isequal(frame.merged.electrons,result.merged.electrons));
    end
end

function testMetadataFailureBeforePublication()
    for unsupported = {{1}, uint32(1), true(2), [NaN 1], Inf, 1+1i, ...
            ones(1,2,2), repmat(struct('a',1),1,2), char('row1','row2')}
        expectError(@() alev4.encodeBundleJson(unsupported{1}), ...
            'ALEV4:InvalidDualGainMetadata');
    end
    expectError(@() alev4.encodeBundleJson(struct('text',repmat('a',1,2000000))), ...
        'ALEV4:InvalidDualGainMetadata');
    [folder, guard] = ownFolder(); %#ok<NASGU>
    [cfg,~] = fixture();
    result = alev4.simulateDualGainExposure(ones(cfg.sensor.image_size)*1e30,cfg,1e-20,39);
    destination = fullfile(folder,'target'); assert(mkdir(destination));
    shadow = fullfile(folder,'shadow'); assert(mkdir(shadow));
    source = sprintf(['function varargout=sprintf(format,varargin)\n' ...
        'if any(strcmp(format,{''%%.17g'',''%%.17g,''}))\n' ...
        'values=varargin{1}; values(values~=0 & abs(values)<1e-16)=0; varargin{1}=values;\n' ...
        'end\n' ...
        '[varargout{1:nargout}]=builtin(''sprintf'',format,varargin{:});\n' ...
        'end\n']);
    writeBytes(fullfile(shadow,'sprintf.m'),uint8(source));
    previous_path = path; path_guard = onCleanup(@() restoreFormatterPath(previous_path)); %#ok<NASGU>
    previous_warning = warning('query','all'); warning_guard = onCleanup(@() warning(previous_warning)); %#ok<NASGU>
    warning('off','all'); addpath(shadow,'-begin'); clear sprintf;
    assert(strcmp(which('sprintf'),fullfile(shadow,'sprintf.m')));
    before = fileNames(destination);
    expectError(@() alev4.exportDualGainBundle(result,cfg,fullfile(destination,'precision_loss')), ...
        'ALEV4:InvalidDualGainMetadata');
    assert(isequal(before,fileNames(destination)), ...
        'Metadata precision failure left published or staged files.');
    clear path_guard;
end

function assertMetadataClose(expected,actual)
    expected = expected(:); actual = actual(:);
    assert(isequal(size(expected),size(actual)) && all(isfinite(actual)));
    assert(all(sign(expected) == sign(actual)), 'Metadata lost a nonzero value or changed sign.');
    assert(all(abs(expected-actual) <= 4*eps(abs(expected))), ...
        'Metadata exceeds its own-scale four-ULP native decoding bound.');
    discrete = expected == fix(expected) & abs(expected) <= flintmax;
    assert(all(expected(discrete) == actual(discrete)));
end

function assertMetadataEquivalent(expected,actual)
    if isstruct(expected)
        assert(isstruct(actual) && isscalar(actual));
        assert(isequal(sort(fieldnames(expected)),sort(fieldnames(actual))));
        names = fieldnames(expected);
        for k = 1:numel(names)
            assertMetadataEquivalent(expected.(names{k}),actual.(names{k}));
        end
    elseif isnumeric(expected)
        assert(isequal(size(expected),size(actual)));
        assertMetadataClose(expected,actual);
    else
        assert(isequal(expected,actual));
    end
end

function makeHardLink(source,destination)
    if exist('link','builtin') || exist('link','file')
        [status,message] = link(source,destination); assert(status == 0,message);
    elseif (exist('usejava','builtin') || exist('usejava','file')) && usejava('jvm')
        from = javaObject('java.io.File',source); to = javaObject('java.io.File',destination);
        javaMethod('createLink','java.nio.file.Files',to.toPath(),from.toPath());
    else
        error('ALEV4:TestFilesystemCapability','Hardlink regression needs lstat/link or Java NIO.');
    end
end

function makeSymlink(target,destination)
    if exist('symlink','builtin') || exist('symlink','file')
        [status,message] = symlink(target,destination); assert(status == 0,message);
    elseif (exist('usejava','builtin') || exist('usejava','file')) && usejava('jvm')
        from = javaObject('java.io.File',target); to = javaObject('java.io.File',destination);
        attributes = javaArray('java.nio.file.attribute.FileAttribute',0);
        javaMethod('createSymbolicLink','java.nio.file.Files',to.toPath(),from.toPath(),attributes);
    else
        error('ALEV4:TestFilesystemCapability','Symlink regression needs symlink or Java NIO.');
    end
end

function answer = isSymlink(path)
    if exist('lstat','builtin') || exist('lstat','file')
        [info,status] = lstat(path); answer = status == 0 && info.modestr(1) == 'l';
    else
        file = javaObject('java.io.File',path);
        answer = javaMethod('isSymbolicLink','java.nio.file.Files',file.toPath());
    end
end

function [cfg,result,mu]=fixture()
    mu=[0 10 750 12000 40000;1 6 32 600 900;22 333 500 1008 29999];
    cfg=alev4.createDualGainSensor(struct('sensor',struct('image_size',[3 5], ...
        'wavelength_nm',550,'bin_width_nm',10,'qe',[0.5 0.5 0.5], ...
        'pixel_pitch_m',1e-6,'fill_factor',1,'shot_noise',false), ...
        'high_gain',struct('read_noise_e',0),'low_gain',struct('read_noise_e',0)));
    result=alev4.simulateDualGainExposure(mu/5e-14,cfg,0.01,9201);
end

function [folder,guard]=ownFolder()
    folder=tempname(); assert(mkdir(folder));
    marker=fullfile(folder,'.phase2-raw-owned'); writeBytes(marker,uint8('phase2-raw-test'));
    guard=onCleanup(@() removeOwned(folder,marker));
end

function removeOwned(folder,marker)
    if exist(folder,'dir')==7 && exist(marker,'file')==2 && strcmp(fileread(marker),'phase2-raw-test')
        rmdir(folder,'s');
    end
end

function restorePath(previous)
    path(previous); clear movefile;
end

function restoreFormatterPath(previous)
    path(previous); clear sprintf;
end

function names=fileNames(folder)
    listing=dir(folder); names=sort({listing.name});
end

function bytes=readBytes(file)
    fid=fopen(file,'rb'); assert(fid>=0); guard=onCleanup(@() fclose(fid)); %#ok<NASGU>
    bytes=fread(fid,Inf,'*uint8');
end

function writeBytes(file,bytes)
    fid=fopen(file,'wb'); assert(fid>=0); guard=onCleanup(@() fclose(fid)); %#ok<NASGU>
    assert(fwrite(fid,bytes,'uint8')==numel(bytes));
end

function writePlane(file,plane,precision)
    fid=fopen(file,'wb','ieee-le'); assert(fid>=0); guard=onCleanup(@() fclose(fid)); %#ok<NASGU>
    assert(fwrite(fid,plane.',precision)==numel(plane));
end

function writeJson(file,value)
    writeBytes(file,unicode2native(jsonencode(value),'UTF-8'));
end

function expectError(action,identifier)
    caught=false;
    try, action(); catch err
        caught=true; assert(strcmp(err.identifier,identifier), ...
            ['Expected ' identifier ', received ' err.identifier ': ' err.message]);
    end
    assert(caught,['Expected error was not raised: ' identifier]);
end
