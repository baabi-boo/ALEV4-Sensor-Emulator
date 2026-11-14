function report = test_phase2_demo()
%TEST_PHASE2_DEMO Verify the complete fixed demonstration and file lifecycle.
%   Byte repeat here is within one process. Independent fresh-process
%   reproducibility remains a separate acceptance/CI gate.
    previous_rng = rng;
    previous_path = path;
    restore_rng = onCleanup(@() rng(previous_rng)); %#ok<NASGU>
    restore_path = onCleanup(@() path(previous_path)); %#ok<NASGU>
    folder = tempname;
    [ok, message] = mkdir(folder);
    assert(ok, message);
    remove_folder = onCleanup(@() removeOwnedFolder(folder)); %#ok<NASGU>
    primary = fullfile(folder, 'primary');
    repeat = fullfile(folder, 'repeat');
    names = {'fixed_fixture_identity_and_configuration', ...
        'binary_sizes_and_summary_from_readback', ...
        'deterministic_physics_and_rail_diagnostics', ...
        'noisy_fixture_variation_and_finite_validity', ...
        'caller_rng_and_same_process_repeat', ...
        'all_destinations_preflight_without_overwrite', ...
        'invalid_paths_and_unrelated_file_preservation'};
    stems = {'dark', 'shadow', 'transition', 'highlight', 'saturation', 'noisy'};
    suffixes = {'.high.raw', '.low.raw', '.merged.f64', '.flags.u8', '.json'};

    rng(6101, 'twister');
    before_success = rng;
    summary = phase2_demo(primary);
    assert(isequal(rng, before_success), 'Successful demonstration changed caller RNG.');
    assert(summary.demo_complete && summary.phase == 2 && summary.frame_count == 6);
    assert(strcmp(summary.schema_version, '1.0'));
    assert(summary.synthetic && ~summary.calibrated_alev4 && ~summary.authentic_arriraw);
    assert(~isfield(summary, 'phase2_passed'), 'A demo alone cannot claim complete numerical acceptance.');
    assert(isequal({summary.frames.name}, stems));
    assert(strcmp(summary.paths_relative_to, 'directory containing this summary'));

    expected_files = {'phase2-demo-summary.json'};
    for k = 1:numel(stems)
        for j = 1:numel(suffixes)
            expected_files{end+1} = [stems{k} suffixes{j}]; %#ok<AGROW>
        end
        [decoded, meta] = alev4.readDualGainBundle(fullfile(primary, stems{k}));
        cfg = meta.configuration;
        frame = summary.frames(k);
        assert(strcmp(frame.metadata_file, [stems{k} '.json']));
        assert(frame.seed == 200+k && meta.seed == 200+k);
        assert(frame.exposure_s == 0.01 && meta.exposure_s == 0.01);
        assert(isequal(cfg.sensor.image_size, [17 257]));
        assert(cfg.sensor.wavelength_nm == 550 && cfg.sensor.bin_width_nm == 10);
        assert(isequal(cfg.sensor.qe, [0.5 0.5 0.5]));
        % The manifest preserves the binary64 decimal value; native JSON
        % decoding permits only the documented own-scale four-ULP drift.
        assert(abs(cfg.sensor.pixel_pitch_m - 1e-6) <= 4*eps(1e-6) && ...
            cfg.sensor.fill_factor == 1);
        assert(cfg.sensor.full_well_e == 30000 && strcmp(cfg.sensor.cfa_pattern, 'RGGB'));
        assert(cfg.high_gain.gain_dn_per_e == 4 && cfg.low_gain.gain_dn_per_e == 0.1);
        assert(cfg.high_gain.black_level_dn == 64 && cfg.low_gain.black_level_dn == 64);
        assert(cfg.high_gain.adc_bits == 12 && cfg.low_gain.adc_bits == 12);
        assert(cfg.merge.start_e == 600 && cfg.merge.end_e == 900);
        assert(isequal(cfg.sensor.shot_noise, k == 6));
        assert(cfg.high_gain.read_noise_e == double(k == 6));
        assert(cfg.low_gain.read_noise_e == 5*double(k == 6));
        assert(isequal(meta.runtime, summary.runtime));
        assert(isequal(meta.provenance, summary.provenance));
        for j = 1:4
            widths = [2 2 8 1];
            bytes = readBytes(fullfile(primary, [stems{k} suffixes{j}]));
            assert(numel(bytes) == 17*257*widths(j), 'Demo payload has an unexpected byte count.');
        end
        expected = fixtureTarget(k);
        assertClose(frame.mean_expected_electrons, mean(expected(:)), 1e-8);
        assertClose(frame.mean_merged_electrons, mean(decoded.merged.electrons(:)), 1e-10);
        assertClose(frame.full_well_saturation_fraction, mean(decoded.full_well_saturated(:)), 1e-14);
        assertClose(frame.high_adc_clipping_fraction, ...
            mean(decoded.high_gain.adc_low_clipped(:) | decoded.high_gain.adc_high_clipped(:)), 1e-14);
        assertClose(frame.low_adc_clipping_fraction, ...
            mean(decoded.low_gain.adc_low_clipped(:) | decoded.low_gain.adc_high_clipped(:)), 1e-14);
        assertClose(frame.reconstruction_valid_fraction, mean(decoded.reconstruction_valid(:)), 1e-14);
        assert(all(isfinite(decoded.merged.electrons(:))));
        if k < 6
            stored = min(expected, 30000);
            high_rounded = floor(4*stored+64+0.5);
            low_rounded = floor(0.1*stored+64+0.5);
            assert(isequal(decoded.high_gain.raw_dn, uint16(min(high_rounded, 4095))));
            assert(isequal(decoded.low_gain.raw_dn, uint16(low_rounded)));
            assert(isequal(decoded.full_well_saturated, expected >= 30000));
            assert(isequal(decoded.high_gain.adc_high_clipped, high_rounded > 4095));
            assert(~any(decoded.high_gain.adc_low_clipped(:)));
            assert(~any(decoded.low_gain.adc_low_clipped(:) | decoded.low_gain.adc_high_clipped(:)));
            if k == 4
                assert(all(decoded.high_gain.adc_high_clipped(:)));
                assert(all(decoded.merged.electrons(:) == 12000));
                assert(all(decoded.reconstruction_valid(:)));
            elseif k == 5
                assert(all(decoded.merged.electrons(:) == 30000));
                assert(all(decoded.merged.valid(:)) && ~any(decoded.reconstruction_valid(:)));
            elseif k == 3
                increments = diff(decoded.merged.electrons, 1, 2);
                assert(all(increments(:) >= -1e-12));
                assert(any(decoded.merged.weight_high(:) > 0 & decoded.merged.weight_high(:) < 1));
            end
        else
            assert(numel(unique(decoded.high_gain.raw_dn)) > 1);
            assert(numel(unique(decoded.low_gain.raw_dn)) > 1);
            assert(~any(decoded.full_well_saturated(:)) && all(decoded.reconstruction_valid(:)));
            assert(all(decoded.high_gain.raw_dn(:) > 0 & decoded.high_gain.raw_dn(:) < 4095));
            assert(all(decoded.low_gain.raw_dn(:) > 0 & decoded.low_gain.raw_dn(:) < 4095));
        end
    end
    expected_files = sort(expected_files);
    assert(numel(expected_files) == 31 && isequal(fileInventory(primary), expected_files));
    persisted = jsondecode(native2unicode(readBytes(fullfile(primary, 'phase2-demo-summary.json')).', 'UTF-8'));
    assert(persisted.demo_complete && persisted.frame_count == 6 && persisted.phase == 2);
    assert(isequal({persisted.frames.name}, stems));
    for k = 1:6
        assertClose(persisted.frames(k).mean_merged_electrons, summary.frames(k).mean_merged_electrons, 1e-10);
    end

    repeated = phase2_demo(repeat);
    assert(isequal(repeated, summary));
    assert(isequal(rng, before_success));
    for k = 1:numel(expected_files)
        assert(isequal(readBytes(fullfile(primary, expected_files{k})), ...
            readBytes(fullfile(repeat, expected_files{k}))), 'Same-process demo bytes changed.');
    end

    % Every reserved destination is preflighted before the first frame.
    collision = fullfile(folder, 'collision');
    mkdir(collision);
    sentinel = uint8([0 83 65 86 69 255].');
    for k = 1:numel(expected_files)
        existing = fullfile(collision, expected_files{k});
        writeBytes(existing, sentinel);
        expectError(@() phase2_demo(collision), 'ALEV4:DualGainAlreadyExists');
        assert(isequal(readBytes(existing), sentinel), 'Preflight changed existing file bytes.');
        assert(isequal(fileInventory(collision), expected_files(k)), 'Preflight published partial demo files.');
        assert(isequal(rng, before_success), 'Failed demonstration changed caller RNG.');
        delete(existing);
    end
    invalid = {[], 7, true, struct(), {}, '', ['a'; 'b'], ['a' char(0) 'b'], ['a' char(10) 'b']};
    for k = 1:numel(invalid)
        expectError(@() phase2_demo(invalid{k}), 'ALEV4:InvalidDualGainDemoPath');
    end
    existing_file = fullfile(folder, 'existing-file');
    writeBytes(existing_file, sentinel);
    expectError(@() phase2_demo(existing_file), 'ALEV4:DualGainDemoDirectory');
    assert(isequal(readBytes(existing_file), sentinel));
    unrelated = fullfile(folder, 'with-unrelated');
    mkdir(unrelated);
    writeBytes(fullfile(unrelated, 'keep.txt'), sentinel);
    phase2_demo(unrelated);
    assert(isequal(readBytes(fullfile(unrelated, 'keep.txt')), sentinel));
    assert(isequal(fileInventory(unrelated), sort([expected_files {'keep.txt'}])));
    assert(isequal(rng, before_success));

    tests = repmat(struct('name', '', 'status', 'passed', 'passed', true), 1, numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    report = struct('suite', 'phase2_demo', 'status', 'passed', 'passed', true, ...
        'test_count', numel(names), 'tests', tests, ...
        'metrics', struct('fixture_frame_count', 6, 'fixture_file_count', 31, ...
        'preflight_destinations_checked', 31, 'repeat_scope', 'same process only'));
    fprintf('PASS: Phase 2 demonstration contract, %d test groups.\n', numel(names));
end

function target = fixtureTarget(index)
    values = [0 10 0 12000 40000 250];
    target = values(index)*ones(17, 257);
    if index == 3, target = repmat(400+4*(0:256), 17, 1); end
end

function assertClose(value, expected, tolerance)
    assert(isfinite(value) && abs(value-expected) <= tolerance, 'Summary disagrees with independent/readback value.');
end

function expectError(callback, identifier)
    caught = false;
    try
        callback();
    catch err
        caught = true;
        assert(strcmp(err.identifier, identifier), ...
            ['Unexpected error identifier: ' err.identifier]);
    end
    assert(caught, ['Expected failure ' identifier]);
end

function names = fileInventory(folder)
    entries = dir(folder);
    entries = entries(~ismember({entries.name}, {'.', '..'}));
    assert(~any([entries.isdir]), 'Unexpected directory in demo output.');
    names = sort({entries.name});
end

function bytes = readBytes(filename)
    fid = fopen(filename, 'rb');
    assert(fid >= 0, 'Missing test artifact.');
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    bytes = fread(fid, Inf, '*uint8');
end

function writeBytes(filename, bytes)
    fid = fopen(filename, 'wb');
    assert(fid >= 0, 'Cannot create owned fixture.');
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    assert(fwrite(fid, bytes, 'uint8') == numel(bytes));
end

function removeOwnedFolder(folder)
    if exist(folder, 'dir') == 7, rmdir(folder, 's'); end
end
