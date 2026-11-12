function files = exportSyntheticRaw(result, cfg, output_base)
%EXPORTSYNTHETICRAW Write a labelled synthetic Bayer mosaic and JSON manifest.
%   FILES = alev4.exportSyntheticRaw(RESULT, CFG, OUTPUT_BASE) creates
%   OUTPUT_BASE.raw and OUTPUT_BASE.json. The payload is headerless uint16,
%   little-endian, ROW-MAJOR (the first complete image row comes first).
%   RESULT must contain raw_dn, exposure_s and seed. Neither destination may
%   already exist. Use a distinct base name for every export. This format is
%   not ARRIRAW, DNG, or a calibrated ALEV4 capture.
%
%   Temporary files are completed before publication. An ordinary failure
%   removes this invocation's incomplete pair. Publication of two separate
%   files is not an atomic transaction; concurrent writers to the same base
%   name are unsupported.

    cfg = alev4.createBaselineSensor(cfg);
    output_base = validateBase(output_base);
    if ~isstruct(result) || ~isscalar(result) || ...
            ~all(isfield(result, {'raw_dn', 'exposure_s', 'seed'}))
        error('ALEV4:InvalidRawResult', ...
            'result must contain raw_dn, exposure_s and seed.');
    end
    raw = result.raw_dn;
    if ~isa(raw, 'uint16') || ~isreal(raw) || ~ismatrix(raw) || ...
            ~isequal(size(raw), double(cfg.image_size(:).')) || ...
            any(double(raw(:)) > 2^cfg.adc_bits - 1)
        error('ALEV4:InvalidRawResult', ...
            'raw_dn must be uint16 with the sensor dimensions and ADC range.');
    end
    requireScalar(result.exposure_s, 0, realmax, 'exposure_s');
    requireScalar(result.seed, 0, 2^32 - 1, 'seed');
    if result.seed ~= floor(result.seed)
        error('ALEV4:InvalidRawResult', 'seed must be an integer.');
    end
    if numel(raw) > 1e8
        error('ALEV4:InvalidRawResult', 'Synthetic RAW is limited to 100 million pixels.');
    end

    raw_path = [output_base '.raw'];
    json_path = [output_base '.json'];
    refuseExisting(raw_path, json_path);
    parent = fileparts(output_base);
    if isempty(parent)
        parent = '.';
    end
    if exist(parent, 'dir') ~= 7
        error('ALEV4:RawDirectoryMissing', ...
            'The output directory must already exist: %s', parent);
    end

    meta = struct();
    meta.format = 'ALEV4-SYNTHETIC-RAW';
    meta.schema_version = '1.0';
    meta.synthetic = true;
    meta.calibrated = false;
    meta.authentic_arriraw = false;
    meta.description = 'Generic synthetic Bayer baseline; not ARRIRAW or calibrated ALEV4.';
    meta.height = size(raw, 1);
    meta.width = size(raw, 2);
    meta.byte_count = 2 * numel(raw);
    meta.sample_type = 'uint16';
    meta.byte_order = 'little-endian';
    meta.layout = 'row-major';
    meta.units = 'DN';
    meta.cfa_pattern = cfg.cfa_pattern;
    meta.cfa_origin = [1 1];
    meta.exposure_s = double(result.exposure_s);
    meta.seed = double(result.seed);
    meta.sensor = cfg;
    meta.algorithm_version = 'phase1-baseline-v1';
    meta.sampler_version = 'Poisson-Knuth-PTRS-v1';
    if exist('OCTAVE_VERSION', 'builtin') ~= 0
        meta.runtime = struct('name', 'GNU Octave', 'version', OCTAVE_VERSION);
    else
        meta.runtime = struct('name', 'MATLAB', 'version', version);
    end
    root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    meta.provenance = struct( ...
        'repository_head', observedHead(root), ...
        'isetcam_head', observedHead(fullfile(root, 'third_party', 'isetcam')), ...
        'isethdrsensor_head', observedHead(fullfile(root, 'third_party', 'isethdrsensor')), ...
        'meaning', 'Observed Git HEADs; an empty value means unavailable. Uncommitted edits are not identified.');

    raw_temp = [tempname(parent) '.raw.part'];
    json_temp = [tempname(parent) '.json.part'];
    published_raw = false;
    published_json = false;
    cleanup = onCleanup(@() cleanupTemps(raw_temp, json_temp)); %#ok<NASGU>
    try
        writePayload(raw_temp, raw);
        writeManifest(json_temp, meta);
        refuseExisting(raw_path, json_path);
        [ok, message] = movefile(raw_temp, raw_path);
        if ~ok
            error('ALEV4:RawWriteFailed', 'Cannot publish RAW: %s', message);
        end
        published_raw = true;
        if exist(json_path, 'file') ~= 0
            error('ALEV4:RawAlreadyExists', 'Manifest appeared during export: %s', json_path);
        end
        [ok, message] = movefile(json_temp, json_path);
        if ~ok
            error('ALEV4:RawWriteFailed', 'Cannot publish manifest: %s', message);
        end
        published_json = true;
        files = struct('raw', raw_path, 'metadata', json_path);
    catch err
        if published_raw
            deleteOwned(raw_path);
        end
        if published_json
            deleteOwned(json_path);
        end
        rethrow(err);
    end
end

function base = validateBase(base)
    if ~ischar(base) || isempty(base) || size(base, 1) ~= 1 || any(base == char(0))
        error('ALEV4:InvalidRawPath', 'output_base must be a nonempty character row vector.');
    end
end

function requireScalar(value, lower, upper, name)
    if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
            ~isfinite(value) || value < lower || value > upper
        error('ALEV4:InvalidRawResult', '%s is invalid.', name);
    end
end

function refuseExisting(raw_path, json_path)
    if exist(raw_path, 'file') ~= 0 || exist(json_path, 'file') ~= 0
        error('ALEV4:RawAlreadyExists', ...
            'Refusing to overwrite an existing RAW payload or manifest.');
    end
end

function writePayload(path, raw)
    [fid, message] = fopen(path, 'wb', 'ieee-le');
    if fid < 0
        error('ALEV4:RawWriteFailed', 'Cannot open temporary RAW: %s', message);
    end
    cleanup = onCleanup(@() closeQuietly(fid)); %#ok<NASGU>
    count = fwrite(fid, raw.', 'uint16');
    if count ~= numel(raw) || fclose(fid) ~= 0
        error('ALEV4:RawWriteFailed', 'Incomplete RAW payload write.');
    end
end

function writeManifest(path, meta)
    encoded = jsonencode(meta);
    [fid, message] = fopen(path, 'wb');
    if fid < 0
        error('ALEV4:RawWriteFailed', 'Cannot open temporary manifest: %s', message);
    end
    cleanup = onCleanup(@() closeQuietly(fid)); %#ok<NASGU>
    bytes = unicode2native([encoded sprintf('\n')], 'UTF-8');
    count = fwrite(fid, bytes, 'uint8');
    if count ~= numel(bytes) || fclose(fid) ~= 0
        error('ALEV4:RawWriteFailed', 'Incomplete manifest write.');
    end
end

function closeQuietly(fid)
    try
        fclose(fid);
    catch
        % The normal path has already closed the handle.
    end
end

function deleteOwned(path)
    if exist(path, 'file') == 2
        try
            delete(path);
        catch
            % Cleanup must not replace the primary write error.
        end
    end
end

function cleanupTemps(raw_temp, json_temp)
    deleteOwned(raw_temp);
    deleteOwned(json_temp);
end

function sha = observedHead(root)
% Read Git's ordinary HEAD/ref files without invoking a shell. This also
% handles submodule/worktree .git files. Never substitute a guessed revision.
    sha = '';
    git_dir = fullfile(root, '.git');
    try
        if exist(git_dir, 'file') == 2
            pointer = strtrim(fileread(git_dir));
            if numel(pointer) < 8 || ~strcmp(pointer(1:8), 'gitdir: ')
                return;
            end
            target = strtrim(pointer(9:end));
            if isempty(target)
                return;
            end
            if target(1) == '/' || target(1) == '\' || ...
                    (numel(target) >= 2 && target(2) == ':')
                git_dir = target;
            else
                git_dir = fullfile(root, target);
            end
        end
        head = strtrim(fileread(fullfile(git_dir, 'HEAD')));
        if ~isempty(regexp(head, '^[0-9a-f]{40}$', 'once'))
            sha = head;
            return;
        end
        token = regexp(head, '^ref: (refs/[A-Za-z0-9_./-]+)$', 'tokens', 'once');
        if isempty(token) || ~isempty(strfind(token{1}, '..')) %#ok<STREMP>
            return;
        end
        ref_file = fullfile(git_dir, strrep(token{1}, '/', filesep));
        if exist(ref_file, 'file') == 2
            candidate = strtrim(fileread(ref_file));
            if ~isempty(regexp(candidate, '^[0-9a-f]{40}$', 'once'))
                sha = candidate;
            end
        elseif exist(fullfile(git_dir, 'packed-refs'), 'file') == 2
            lines = regexp(fileread(fullfile(git_dir, 'packed-refs')), '\r?\n', 'split');
            for k = 1:numel(lines)
                record = regexp(lines{k}, '^([0-9a-f]{40}) (refs/\S+)$', 'tokens', 'once');
                if ~isempty(record) && strcmp(record{2}, token{1})
                    sha = record{1};
                    return;
                end
            end
        end
    catch
        sha = '';
    end
end
