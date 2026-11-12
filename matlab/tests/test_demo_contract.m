function report = test_demo_contract()
%TEST_DEMO_CONTRACT Check standalone demo scope, artifacts and RNG isolation.
%   The fixture deliberately requests include_iset=false. Its nine generic
%   frames must never be presented as a full Phase 1 or calibrated-camera
%   pass. The required runner tests genuine ISET integration separately.
    prior_rng = rng;
    restore_rng = onCleanup(@() rng(prior_rng)); %#ok<NASGU>
    folder = tempname;
    [ok, message] = mkdir(folder);
    assert(ok, message);
    remove_folder = onCleanup(@() removeOwnedFolder(folder)); %#ok<NASGU>

    names = {'core_only_scope_and_labels', 'nine_frame_file_inventory', ...
        'independent_raw_payload_sizes', 'successful_demo_preserves_rng', ...
        'existing_output_failure_preserves_rng_and_bytes'};
    stems = {'black', 'flat', 'ramp', 'checker', 'exposure_025x', ...
        'exposure_050x', 'exposure_100x', 'exposure_200x', 'exposure_400x'};

    rng(8701, 'twister');
    before_success = rng;
    summary = phase1_demo(folder, false);
    assert(isequal(rng, before_success), 'The standalone demo changed caller RNG state.');
    assert(summary.demo_complete && summary.frame_count == 9 && numel(summary.frames) == 9);
    assert(summary.synthetic && ~summary.calibrated_alev4 && ~summary.authentic_arriraw);
    assert(strcmp(summary.iset_integration.status, 'not_run'));
    assert(~isempty(summary.iset_integration.reason));
    assert(~isfield(summary, 'phase1_passed') || isequal(summary.phase1_passed, false), ...
        'A standalone demo cannot claim a full Phase 1 pass.');
    assert(isequal({summary.frames.name}, stems));

    expected_files = {'phase1-demo-summary.json'};
    for k = 1:numel(stems)
        for extension = {'.raw', '.json', '.pgm'}
            expected_files{end+1} = [stems{k} extension{1}]; %#ok<AGROW>
        end
        frame = summary.frames(k);
        assert(strcmp(frame.raw_file, [stems{k} '.raw']));
        assert(strcmp(frame.metadata_file, [stems{k} '.json']));
        assert(strcmp(frame.preview_file, [stems{k} '.pgm']));
        assert(isequal(frame.image_size, [64 96]) && frame.raw_roundtrip_exact);
        bytes = readBytes(fullfile(folder, [stems{k} '.raw']));
        assert(numel(bytes) == 2 * 64 * 96, 'Standalone RAW payload size is incorrect.');
    end
    expected_files = sort(expected_files);
    assert(isequal(fileInventory(folder), expected_files), ...
        'The standalone demo must produce exactly 27 frame files and one summary.');
    before_bytes = cell(size(expected_files));
    for k = 1:numel(expected_files)
        before_bytes{k} = readBytes(fullfile(folder, expected_files{k}));
        assert(~isempty(before_bytes{k}), 'A demo artifact is empty.');
    end
    persisted = jsondecode(native2unicode(readBytes(fullfile(folder, ...
        'phase1-demo-summary.json')).', 'UTF-8'));
    assert(persisted.demo_complete && persisted.frame_count == 9);
    assert(strcmp(persisted.iset_integration.status, 'not_run'));
    assert(persisted.synthetic && ~persisted.calibrated_alev4 && ~persisted.authentic_arriraw);
    assert(~isfield(persisted, 'phase1_passed') || isequal(persisted.phase1_passed, false));

    rng(8702, 'twister');
    before_failure = rng;
    caught = false;
    try
        phase1_demo(folder, false);
    catch err
        caught = true;
        assert(strcmp(err.identifier, 'ALEV4:DemoAlreadyExists'), ...
            sprintf('Expected no-overwrite error, received %s.', err.identifier));
    end
    assert(caught, 'A second demo invocation must refuse existing artifacts.');
    assert(isequal(rng, before_failure), 'Failed demo invocation changed caller RNG state.');
    assert(isequal(fileInventory(folder), expected_files), ...
        'Failed demo invocation changed the artifact inventory.');
    for k = 1:numel(expected_files)
        assert(isequal(readBytes(fullfile(folder, expected_files{k})), before_bytes{k}), ...
            'Failed demo invocation changed an existing artifact.');
    end

    report = struct('suite', 'demo_contract', 'passed', true, ...
        'test_count', numel(names), 'tests', {names}, 'demo_mode', 'core_only', ...
        'fixture_frame_count', 9, 'fixture_file_count', 28, ...
        'iset_executed_by_this_suite', false, 'fixture_is_full_phase1_evidence', false);
    fprintf('PASS: Demo contract, %d test groups (core-only fixture).\n', numel(names));
end

function names = fileInventory(folder)
    entries = dir(folder);
    entries = entries(~ismember({entries.name}, {'.', '..'}));
    assert(~any([entries.isdir]), 'Unexpected directory in standalone demo output.');
    names = sort({entries.name});
end

function bytes = readBytes(path)
    fid = fopen(path, 'rb');
    assert(fid >= 0, ['Missing artifact: ' path]);
    close_file = onCleanup(@() fclose(fid)); %#ok<NASGU>
    bytes = fread(fid, Inf, '*uint8');
end

function removeOwnedFolder(folder)
    if exist(folder, 'dir') == 7
        rmdir(folder, 's');
    end
end
