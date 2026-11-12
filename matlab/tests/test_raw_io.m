function report = test_raw_io()
%TEST_RAW_IO Exercise synthetic RAW serialization with independent byte checks.
%   Uses only ordinary assertions and temporary, test-owned directories.
%   No proprietary RAW reader or image-processing toolbox is required.
    tests = {@testAsymmetricRoundtrip, @testScalarRoundtrip, ...
        @testSingleRowRoundtrip, @testSingleColumnRoundtrip, ...
        @testMetadata, @testSingleWavelength, ...
        @testOverwriteProtection, @testInvalidExports, @testInvalidMetadata, ...
        @testMalformedJson, @testManifestSizeLimit, @testPayloadLength, @testAdcPayload, @testPaths};
    names = {'asymmetric_row_major_little_endian', ...
        'scalar_roundtrip_all_bayer_patterns', 'single_row_roundtrip_all_bayer_patterns', ...
        'single_column_roundtrip_all_bayer_patterns', 'complete_metadata', ...
        'single_wavelength_odd_shape', 'overwrite_and_partial_pair_protection', ...
        'invalid_export_rejection', 'invalid_metadata_rejection', ...
        'malformed_json_rejection', 'shared_manifest_byte_limit', 'truncated_and_extra_bytes', ...
        'payload_adc_bounds', 'invalid_and_missing_paths'};
    for k = 1:numel(tests)
        tests{k}();
        fprintf('RAW I/O PASS: %s\n', names{k});
    end
    report = struct('status', 'passed', 'test_count', numel(tests), ...
        'names', {names}, 'byte_order_oracle', 'independent uint8 low/high byte calculation');
end

function testAsymmetricRoundtrip()
    [folder, cleanup] = ownFolder(); %#ok<NASGU>
    [cfg, result] = fixture();
    base = fullfile(folder, 'asymmetric');
    files = alev4.exportSyntheticRaw(result, cfg, base);
    assert(strcmp(files.raw, [base '.raw']));
    assert(strcmp(files.metadata, [base '.json']));
    [actual, meta] = alev4.readSyntheticRaw(base);
    assert(isa(actual, 'uint16') && isequal(actual, result.raw_dn));
    assert(isequal(size(actual), [3 5]));
    row_values = double(reshape(result.raw_dn.', [], 1));
    expected_bytes = zeros(2 * numel(row_values), 1, 'uint8');
    expected_bytes(1:2:end) = uint8(mod(row_values, 256));
    expected_bytes(2:2:end) = uint8(floor(row_values / 256));
    bytes = readBytes(files.raw);
    assert(isequal(bytes, expected_bytes), 'Independent little-endian row-major oracle failed.');
    assert(numel(bytes) == 30 && meta.byte_count == 30);
    fid = fopen(files.raw, 'rb', 'ieee-le');
    assert(fid >= 0);
    close_file = onCleanup(@() fclose(fid)); %#ok<NASGU>
    values = fread(fid, Inf, '*uint16');
    independent = reshape(values, 5, 3).';
    assert(isequal(independent, result.raw_dn));
end

function testScalarRoundtrip()
    checkDegenerateRoundtrip(uint16(43981));
end

function testSingleRowRoundtrip()
    checkDegenerateRoundtrip(uint16([258 17185 65535 32769 511]));
end

function testSingleColumnRoundtrip()
    checkDegenerateRoundtrip(uint16([258; 17185; 65535; 32769; 511]));
end

function checkDegenerateRoundtrip(values)
    [folder, cleanup] = ownFolder(); %#ok<NASGU>
    patterns = {'RGGB', 'BGGR', 'GRBG', 'GBRG'};
    [height, width] = size(values);
    % Calculate row-major bytes with explicit row/column iteration, not the
    % transpose/reshape operations used by the production writer and reader.
    expected_bytes = zeros(2 * numel(values), 1, 'uint8');
    offset = 1;
    for row = 1:height
        for column = 1:width
            value = double(values(row, column));
            expected_bytes(offset) = uint8(mod(value, 256));
            expected_bytes(offset + 1) = uint8(floor(value / 256));
            offset = offset + 2;
        end
    end
    for p = 1:numel(patterns)
        cfg = alev4.createBaselineSensor(struct('image_size', [height width], ...
            'wavelength_nm', [510; 650], 'bin_width_nm', [8; 12], ...
            'qe', [0.125 0.5 0.25; 0.75 0.25 0.125], ...
            'pixel_pitch_m', 4e-6, 'fill_factor', 0.625, ...
            'full_well_e', 4095, 'read_noise_e', 1.5, 'gain_dn_per_e', 0.75, ...
            'black_level_dn', 32, 'adc_bits', 16, ...
            'cfa_pattern', patterns{p}, 'shot_noise', false));
        result = struct('raw_dn', values, 'exposure_s', 0.125, 'seed', 4294967295);
        base = fullfile(folder, ['degenerate_' patterns{p}]);
        files = alev4.exportSyntheticRaw(result, cfg, base);
        [actual, meta] = alev4.readSyntheticRaw(base);
        assert(isa(actual, 'uint16') && isequal(size(actual), [height width]));
        assert(isequal(actual, values), 'Degenerate-shape pixels changed during round trip.');
        assert(isequal(readBytes(files.raw), expected_bytes), ...
            'Degenerate-shape row-major little-endian bytes do not match the independent oracle.');
        assert(meta.height == height && meta.width == width);
        assert(meta.byte_count == 2 * numel(values));
        assert(strcmp(meta.cfa_pattern, patterns{p}) && isequal(meta.cfa_origin(:).', [1 1]));
        assert(meta.exposure_s == result.exposure_s && meta.seed == result.seed);
        fields = fieldnames(cfg);
        assert(isequal(sort(fieldnames(meta.sensor)), sort(fields)));
        for k = 1:numel(fields)
            expected = cfg.(fields{k}); restored = meta.sensor.(fields{k});
            if isnumeric(expected)
                assert(isequal(size(restored), size(expected)));
                assert(all(abs(double(restored(:)) - double(expected(:))) <= ...
                    1e-14 * max(1, max(abs(double(expected(:)))))));
            else
                assert(isequal(restored, expected));
            end
        end
    end
end

function testMetadata()
    [folder, cleanup] = ownFolder(); %#ok<NASGU>
    [cfg, result] = fixture();
    base = fullfile(folder, 'metadata');
    alev4.exportSyntheticRaw(result, cfg, base);
    [~, meta] = alev4.readSyntheticRaw(base);
    assert(strcmp(meta.format, 'ALEV4-SYNTHETIC-RAW'));
    assert(strcmp(meta.schema_version, '1.0'));
    assert(islogical(meta.synthetic) && meta.synthetic);
    assert(islogical(meta.calibrated) && ~meta.calibrated);
    assert(islogical(meta.authentic_arriraw) && ~meta.authentic_arriraw);
    assert(strcmp(meta.sample_type, 'uint16') && strcmp(meta.units, 'DN'));
    assert(strcmp(meta.layout, 'row-major') && strcmp(meta.byte_order, 'little-endian'));
    assert(strcmp(meta.cfa_pattern, cfg.cfa_pattern));
    assert(isequal(meta.cfa_origin(:).', [1 1]));
    assert(meta.exposure_s == result.exposure_s && meta.seed == result.seed);
    fields = fieldnames(cfg);
    assert(all(isfield(meta.sensor, fields)));
    for k = 1:numel(fields)
        expected = cfg.(fields{k}); actual = meta.sensor.(fields{k});
        if isnumeric(expected)
            assert(isequal(size(expected), size(actual)));
            assert(all(abs(double(expected(:)) - double(actual(:))) <= ...
                1e-14 * max(1, max(abs(double(expected(:)))))));
        else
            assert(isequal(expected, actual));
        end
    end
    assert(~isempty(meta.runtime.name) && ~isempty(meta.runtime.version));
    assert(strcmp(meta.algorithm_version, 'phase1-baseline-v1'));
    assert(strcmp(meta.sampler_version, 'Poisson-Knuth-PTRS-v1'));
    shas = {'repository_head', 'isetcam_head', 'isethdrsensor_head'};
    for k = 1:numel(shas)
        sha = meta.provenance.(shas{k});
        assert(ischar(sha));
        assert(isempty(sha) || ~isempty(regexp(sha, '^[0-9a-f]{40}$', 'once')));
    end
    assert(~isempty(meta.provenance.meaning));
end

function testSingleWavelength()
    [folder, cleanup] = ownFolder(); %#ok<NASGU>
    cfg = alev4.createBaselineSensor(struct('image_size', [3 5], ...
        'wavelength_nm', 550, 'bin_width_nm', 10, 'qe', [0.2 0.4 0.6], ...
        'cfa_pattern', 'BGGR', 'adc_bits', 10, 'black_level_dn', 4));
    result = struct('raw_dn', uint16(reshape(31:45, 3, 5)), ...
        'exposure_s', 0, 'seed', 4294967295);
    base = fullfile(folder, 'one_wave');
    alev4.exportSyntheticRaw(result, cfg, base);
    [raw, meta] = alev4.readSyntheticRaw(base);
    assert(isequal(raw, result.raw_dn));
    assert(isequal(size(meta.sensor.qe), [1 3]));
    assert(max(abs(meta.sensor.qe - cfg.qe)) < 1e-14);
    assert(meta.sensor.wavelength_nm == 550 && meta.sensor.bin_width_nm == 10);
    assert(strcmp(meta.cfa_pattern, 'BGGR') && meta.seed == 4294967295);
end

function testOverwriteProtection()
    [folder, cleanup] = ownFolder(); %#ok<NASGU>
    [cfg, result] = fixture();
    base = fullfile(folder, 'existing_pair');
    alev4.exportSyntheticRaw(result, cfg, base);
    original_raw = readBytes([base '.raw']); original_json = readBytes([base '.json']);
    expectError(@() alev4.exportSyntheticRaw(result, cfg, base), 'ALEV4:RawAlreadyExists');
    assert(isequal(original_raw, readBytes([base '.raw'])));
    assert(isequal(original_json, readBytes([base '.json'])));
    base = fullfile(folder, 'only_raw');
    writeBytes([base '.raw'], uint8([13 17 29]));
    expectError(@() alev4.exportSyntheticRaw(result, cfg, base), 'ALEV4:RawAlreadyExists');
    assert(isequal(readBytes([base '.raw']), uint8([13; 17; 29])));
    assert(exist([base '.json'], 'file') == 0);
    base = fullfile(folder, 'only_manifest');
    writeBytes([base '.json'], uint8('existing data'));
    expectError(@() alev4.exportSyntheticRaw(result, cfg, base), 'ALEV4:RawAlreadyExists');
    assert(exist([base '.raw'], 'file') == 0);
    assert(isequal(readBytes([base '.json']), uint8('existing data').'));
    base = fullfile(folder, 'directory_collision');
    assert(mkdir([base '.raw']));
    expectError(@() alev4.exportSyntheticRaw(result, cfg, base), 'ALEV4:RawAlreadyExists');
    assert(exist([base '.raw'], 'dir') == 7);
end

function testInvalidExports()
    [folder, cleanup] = ownFolder(); %#ok<NASGU>
    [cfg, result] = fixture();
    base = fullfile(folder, 'invalid');
    bad = result; bad.raw_dn = double(result.raw_dn);
    expectError(@() alev4.exportSyntheticRaw(bad, cfg, base), 'ALEV4:InvalidRawResult');
    bad = result; bad.raw_dn = uint16(ones(5, 3));
    expectError(@() alev4.exportSyntheticRaw(bad, cfg, base), 'ALEV4:InvalidRawResult');
    narrow = cfg; narrow.adc_bits = 12;
    expectError(@() alev4.exportSyntheticRaw(result, narrow, base), 'ALEV4:InvalidRawResult');
    bad = rmfield(result, 'seed');
    expectError(@() alev4.exportSyntheticRaw(bad, cfg, base), 'ALEV4:InvalidRawResult');
    invalid_seeds = {-1, 0.5, 2^32, NaN, Inf, '7'};
    for k = 1:numel(invalid_seeds)
        bad = result; bad.seed = invalid_seeds{k};
        expectError(@() alev4.exportSyntheticRaw(bad, cfg, base), 'ALEV4:InvalidRawResult');
    end
    invalid_exposures = {-1, NaN, Inf, 1i, [1 2]};
    for k = 1:numel(invalid_exposures)
        bad = result; bad.exposure_s = invalid_exposures{k};
        expectError(@() alev4.exportSyntheticRaw(bad, cfg, base), 'ALEV4:InvalidRawResult');
    end
    assert(exist([base '.raw'], 'file') == 0 && exist([base '.json'], 'file') == 0);
end

function testInvalidMetadata()
    [folder, cleanup] = ownFolder(); %#ok<NASGU>
    [cfg, result] = fixture();
    base = fullfile(folder, 'invalid_meta');
    alev4.exportSyntheticRaw(result, cfg, base);
    original = jsondecode(fileread([base '.json']));
    names = {'schema_version', 'format', 'sample_type', 'byte_order', 'layout', ...
        'units', 'algorithm_version', 'sampler_version', 'synthetic', 'calibrated', ...
        'authentic_arriraw', 'height', 'width', 'byte_count', 'cfa_pattern', ...
        'cfa_origin', 'seed', 'exposure_s'};
    values = {'2.0', 'ARRIRAW', 'double', 'big-endian', 'column-major', ...
        'electrons', 'unknown', 'Gaussian-approximation', false, true, true, ...
        3.5, 0, 28, 'BGGR', [0 0], 0.5, -1};
    for k = 1:numel(names)
        changed = original; changed.(names{k}) = values{k};
        writeJson([base '.json'], changed);
        expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:InvalidRawMetadata');
    end
    changed = rmfield(original, 'runtime');
    writeJson([base '.json'], changed);
    expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:InvalidRawMetadata');
    changed = original; changed.sensor = rmfield(changed.sensor, 'qe');
    writeJson([base '.json'], changed);
    expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:InvalidRawMetadata');
    changed = original; changed.sensor.image_size = [5 3];
    writeJson([base '.json'], changed);
    expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:InvalidRawMetadata');
    changed = original; changed.sensor.gain_dn_per_e = -1;
    writeJson([base '.json'], changed);
    expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:InvalidRawMetadata');
    changed = original; changed.runtime.name = '';
    writeJson([base '.json'], changed);
    expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:InvalidRawMetadata');
    changed = original; changed.provenance.repository_head = 'not-a-git-sha';
    writeJson([base '.json'], changed);
    expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:InvalidRawMetadata');
    changed = original; changed.synthetic = 1;
    writeJson([base '.json'], changed);
    expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:InvalidRawMetadata');
    changed = original; changed.height = 1e8; changed.width = 2;
    writeJson([base '.json'], changed);
    expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:InvalidRawMetadata');
    writeJson([base '.json'], original);
    assert(isequal(alev4.readSyntheticRaw(base), result.raw_dn));
end

function testMalformedJson()
    [folder, cleanup] = ownFolder(); %#ok<NASGU>
    [cfg, result] = fixture();
    base = fullfile(folder, 'bad_json');
    alev4.exportSyntheticRaw(result, cfg, base);
    invalid_json = {'{broken', '[]', '{}', 'null', '"text"'};
    for k = 1:numel(invalid_json)
        writeBytes([base '.json'], uint8(invalid_json{k}));
        expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:InvalidRawMetadata');
    end
    writeBytes([base '.json'], uint8([]));
    expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:InvalidRawMetadata');
    writeBytes([base '.json'], zeros(2000001, 1, 'uint8'));
    expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:InvalidRawMetadata');
end

function testPayloadLength()
    [folder, cleanup] = ownFolder(); %#ok<NASGU>
    [cfg, result] = fixture();
    base = fullfile(folder, 'length');
    alev4.exportSyntheticRaw(result, cfg, base);
    original = readBytes([base '.raw']);
    writeBytes([base '.raw'], original(1:end-1));
    expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:RawSizeMismatch');
    writeBytes([base '.raw'], [original; uint8(0)]);
    expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:RawSizeMismatch');
    writeBytes([base '.raw'], uint8([]));
    expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:RawSizeMismatch');
    writeBytes([base '.raw'], original);
    assert(isequal(alev4.readSyntheticRaw(base), result.raw_dn));
end

function testManifestSizeLimit()
    [folder, cleanup] = ownFolder(); %#ok<NASGU>
    [cfg, result] = fixture();
    base = fullfile(folder, 'limit_boundary');
    alev4.exportSyntheticRaw(result, cfg, base);
    original = readBytes([base '.json']);
    assert(numel(original) < 2000000);
    padded = [original; repmat(uint8(32), 2000000-numel(original), 1)];
    writeBytes([base '.json'], padded);
    assert(isequal(alev4.readSyntheticRaw(base), result.raw_dn), ...
        'A valid manifest at exactly 2,000,000 UTF-8 bytes must be readable.');
    writeBytes([base '.json'], [padded; uint8(32)]);
    expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:InvalidRawMetadata');

    % A long but valid spectrum produces large metadata without allocating
    % a large image or RAW payload. Both writer and reader must agree on the
    % encoded UTF-8 byte limit; an exporter must not publish unreadable data.
    n = 60000;
    large_cfg = alev4.createBaselineSensor(struct('image_size', [1 1], ...
        'wavelength_nm', 400 + (0:n-1)' * 0.005, ...
        'bin_width_nm', 0.004 * ones(n, 1), ...
        'qe', repmat([0.123456789012345 0.345678901234567 0.567890123456789], n, 1)));
    encoded_cfg = unicode2native(jsonencode(large_cfg), 'UTF-8');
    assert(numel(encoded_cfg) > 2000000, 'Oversized-export fixture must exceed the format limit.');
    tiny_result = struct('raw_dn', uint16(42), 'exposure_s', 0.001, 'seed', 9);
    large_base = fullfile(folder, 'oversized_export');
    before = dir(folder); before_names = sort({before.name});
    expectError(@() alev4.exportSyntheticRaw(tiny_result, large_cfg, large_base), ...
        'ALEV4:InvalidRawMetadata');
    after = dir(folder); after_names = sort({after.name});
    assert(isequal(before_names, after_names), ...
        'Rejected oversized metadata must leave no payload, manifest, or temporary file.');
    assert(exist([large_base '.raw'], 'file') == 0 && exist([large_base '.json'], 'file') == 0);
end

function testAdcPayload()
    [folder, cleanup] = ownFolder(); %#ok<NASGU>
    cfg = alev4.createBaselineSensor(struct('image_size', [3 5], 'adc_bits', 12));
    result = struct('raw_dn', uint16(reshape(1:15, 3, 5)), 'exposure_s', 0.001, 'seed', 91);
    base = fullfile(folder, 'adc');
    alev4.exportSyntheticRaw(result, cfg, base);
    bytes = readBytes([base '.raw']);
    bytes(1:2) = uint8([255; 255]);
    writeBytes([base '.raw'], bytes);
    expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:RawOutOfRange');
end

function testPaths()
    [folder, cleanup] = ownFolder(); %#ok<NASGU>
    [cfg, result] = fixture();
    invalid = {'', 7, ['invalid' char(0) 'path'], char('row1', 'row2')};
    for k = 1:numel(invalid)
        expectError(@() alev4.exportSyntheticRaw(result, cfg, invalid{k}), 'ALEV4:InvalidRawPath');
        expectError(@() alev4.readSyntheticRaw(invalid{k}), 'ALEV4:InvalidRawPath');
    end
    base = fullfile(folder, 'absent');
    expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:RawPairMissing');
    writeBytes([base '.raw'], uint8([0 0]));
    expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:RawPairMissing');
    base = fullfile(folder, 'manifest_only');
    writeBytes([base '.json'], uint8('{}'));
    expectError(@() alev4.readSyntheticRaw(base), 'ALEV4:RawPairMissing');
    missing_directory = fullfile(folder, 'not_created', 'frame');
    expectError(@() alev4.exportSyntheticRaw(result, cfg, missing_directory), 'ALEV4:RawDirectoryMissing');
end

function [cfg, result] = fixture()
    cfg = alev4.createBaselineSensor(struct('image_size', [3 5]));
    values = [0 1 255 256 257; 511 512 1023 4095 4096; 8191 16384 32768 65534 65535];
    result = struct('raw_dn', uint16(values), 'exposure_s', 0.002, 'seed', 91);
end

function [folder, cleanup] = ownFolder()
    folder = tempname();
    assert(exist(folder, 'file') == 0 && exist(folder, 'dir') == 0);
    [ok, message] = mkdir(folder);
    assert(ok, message);
    marker = fullfile(folder, '.phase1-test-owned');
    writeBytes(marker, uint8('created-by-test_raw_io'));
    cleanup = onCleanup(@() removeOwnedFolder(folder, marker));
end

function removeOwnedFolder(folder, marker)
    % Both paths originate from this test's tempname call, never caller input.
    if exist(folder, 'dir') == 7 && exist(marker, 'file') == 2 && ...
            strcmp(fileread(marker), 'created-by-test_raw_io')
        rmdir(folder, 's');
    end
end

function bytes = readBytes(path)
    fid = fopen(path, 'rb');
    assert(fid >= 0, 'Cannot open test fixture.');
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    bytes = fread(fid, Inf, '*uint8');
end

function writeBytes(path, bytes)
    fid = fopen(path, 'wb');
    assert(fid >= 0, 'Cannot write test fixture.');
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    assert(fwrite(fid, bytes, 'uint8') == numel(bytes), 'Incomplete test fixture write.');
end

function writeJson(path, value)
    writeBytes(path, unicode2native(jsonencode(value), 'UTF-8'));
end

function expectError(action, identifier)
    caught = false;
    try
        action();
    catch err
        caught = true;
        assert(strcmp(err.identifier, identifier), ...
            ['Expected ' identifier ', received ' err.identifier ': ' err.message]);
    end
    assert(caught, ['Expected error was not raised: ' identifier]);
end
