function [raw, meta] = readSyntheticRaw(output_base)
%READSYNTHETICRAW Validate and read an ALEV4-SYNTHETIC-RAW pair.
%   [RAW, META] = alev4.readSyntheticRaw(BASE) reads BASE.raw and BASE.json.
%   RAW is a height-by-width uint16 Bayer mosaic. The on-disk payload is
%   little-endian, row-major. This reader deliberately rejects other RAW
%   formats, missing metadata, truncated/extra bytes and out-of-range DN.
%   Payloads are limited to 100 million pixels and manifests to 2 MB before
%   allocation/JSON decoding. No proprietary camera format is supported.

    if ~ischar(output_base) || isempty(output_base) || ...
            size(output_base, 1) ~= 1 || any(output_base == char(0))
        error('ALEV4:InvalidRawPath', 'output_base must be a nonempty character row vector.');
    end
    raw_path = [output_base '.raw'];
    json_path = [output_base '.json'];
    if exist(raw_path, 'file') ~= 2 || exist(json_path, 'file') ~= 2
        error('ALEV4:RawPairMissing', 'Both .raw and .json files are required.');
    end
    json_info = dir(json_path);
    if numel(json_info) ~= 1 || json_info.bytes < 2 || json_info.bytes > 2e6
        error('ALEV4:InvalidRawMetadata', 'Manifest size is invalid.');
    end
    try
        meta = jsondecode(fileread(json_path));
    catch err
        error('ALEV4:InvalidRawMetadata', 'Cannot decode manifest: %s', err.message);
    end
    required = {'format', 'schema_version', 'synthetic', 'calibrated', ...
        'authentic_arriraw', 'height', 'width', 'byte_count', 'sample_type', ...
        'byte_order', 'layout', 'units', 'cfa_pattern', 'cfa_origin', ...
        'exposure_s', 'seed', 'sensor', 'runtime', 'provenance', ...
        'algorithm_version', 'sampler_version'};
    if ~isstruct(meta) || ~isscalar(meta) || ~all(isfield(meta, required))
        error('ALEV4:InvalidRawMetadata', 'Manifest is missing required fields.');
    end
    requireText(meta.format, 'ALEV4-SYNTHETIC-RAW', 'format');
    requireText(meta.schema_version, '1.0', 'schema_version');
    requireText(meta.sample_type, 'uint16', 'sample_type');
    requireText(meta.byte_order, 'little-endian', 'byte_order');
    requireText(meta.layout, 'row-major', 'layout');
    requireText(meta.units, 'DN', 'units');
    requireText(meta.algorithm_version, 'phase1-baseline-v1', 'algorithm_version');
    requireText(meta.sampler_version, 'Poisson-Knuth-PTRS-v1', 'sampler_version');
    if ~islogical(meta.synthetic) || ~isscalar(meta.synthetic) || ~meta.synthetic || ...
            ~islogical(meta.calibrated) || ~isscalar(meta.calibrated) || meta.calibrated || ...
            ~islogical(meta.authentic_arriraw) || ~isscalar(meta.authentic_arriraw) || meta.authentic_arriraw
        error('ALEV4:InvalidRawMetadata', 'Synthetic, uncalibrated, non-ARRIRAW labels are required.');
    end
    requireInteger(meta.height, 1, 1e8, 'height');
    requireInteger(meta.width, 1, 1e8, 'width');
    pixels = double(meta.height) * double(meta.width);
    if pixels > 1e8
        error('ALEV4:InvalidRawMetadata', 'Payload exceeds the pixel limit.');
    end
    requireInteger(meta.byte_count, 2, 2e8, 'byte_count');
    if meta.byte_count ~= 2 * pixels
        error('ALEV4:InvalidRawMetadata', 'byte_count does not match image dimensions.');
    end
    if ~isnumeric(meta.cfa_origin) || ~isreal(meta.cfa_origin) || ...
            ~isequal(double(meta.cfa_origin(:).'), [1 1])
        error('ALEV4:InvalidRawMetadata', 'CFA origin must be top-left [1, 1].');
    end
    requireInteger(meta.seed, 0, 2^32 - 1, 'seed');
    if ~isnumeric(meta.exposure_s) || ~isreal(meta.exposure_s) || ...
            ~isscalar(meta.exposure_s) || ~isfinite(meta.exposure_s) || meta.exposure_s < 0
        error('ALEV4:InvalidRawMetadata', 'exposure_s must be finite and nonnegative.');
    end
    if ~isstruct(meta.sensor) || ~isscalar(meta.sensor) || ~isfield(meta.sensor, 'image_size')
        error('ALEV4:InvalidRawMetadata', 'sensor configuration is missing or invalid.');
    end
    try
        required_sensor_fields = fieldnames(alev4.createBaselineSensor());
        if ~all(isfield(meta.sensor, required_sensor_fields))
            error('ALEV4:InvalidRawMetadata', 'The manifest must contain the complete sensor configuration.');
        end
        meta.sensor.image_size = meta.sensor.image_size(:).';
        % JSON has no distinction between a MATLAB row and column vector.
        if numel(meta.sensor.wavelength_nm) == 1 && ...
                isnumeric(meta.sensor.qe) && isvector(meta.sensor.qe) && numel(meta.sensor.qe) == 3
            meta.sensor.qe = meta.sensor.qe(:).';
        end
        cfg = alev4.createBaselineSensor(meta.sensor);
    catch err
        error('ALEV4:InvalidRawMetadata', 'Invalid sensor configuration: %s', err.message);
    end
    if ~isequal(double(cfg.image_size(:).'), [double(meta.height) double(meta.width)])
        error('ALEV4:InvalidRawMetadata', 'Sensor and payload dimensions disagree.');
    end
    requireText(meta.cfa_pattern, cfg.cfa_pattern, 'cfa_pattern');
    if ~isstruct(meta.runtime) || ~isscalar(meta.runtime) || ...
            ~all(isfield(meta.runtime, {'name', 'version'})) || ...
            ~isNonemptyText(meta.runtime.name) || ~isNonemptyText(meta.runtime.version)
        error('ALEV4:InvalidRawMetadata', 'Runtime identity is missing or invalid.');
    end
    provenance_fields = {'repository_head', 'isetcam_head', 'isethdrsensor_head', 'meaning'};
    if ~isstruct(meta.provenance) || ~isscalar(meta.provenance) || ...
            ~all(isfield(meta.provenance, provenance_fields)) || ...
            ~isNonemptyText(meta.provenance.meaning)
        error('ALEV4:InvalidRawMetadata', 'Provenance is missing or invalid.');
    end
    for k = 1:3
        sha = meta.provenance.(provenance_fields{k});
        if ~ischar(sha) || (~isempty(sha) && ...
                (size(sha, 1) ~= 1 || isempty(regexp(sha, '^[0-9a-f]{40}$', 'once'))))
            error('ALEV4:InvalidRawMetadata', 'A provenance SHA is invalid.');
        end
    end
    raw_info = dir(raw_path);
    if numel(raw_info) ~= 1 || raw_info.bytes ~= meta.byte_count
        error('ALEV4:RawSizeMismatch', 'Payload byte count differs from the manifest.');
    end
    [fid, message] = fopen(raw_path, 'rb', 'ieee-le');
    if fid < 0
        error('ALEV4:RawReadFailed', 'Cannot open RAW payload: %s', message);
    end
    cleanup = onCleanup(@() closeQuietly(fid)); %#ok<NASGU>
    [values, count] = fread(fid, pixels, '*uint16');
    trailing = fread(fid, 1, '*uint8');
    if count ~= pixels || ~isempty(trailing)
        error('ALEV4:RawSizeMismatch', 'Payload changed or is truncated.');
    end
    if any(double(values) > 2^cfg.adc_bits - 1)
        error('ALEV4:RawOutOfRange', 'Payload contains values above the configured ADC range.');
    end
    raw = reshape(values, double(meta.width), double(meta.height)).';
    meta.sensor = cfg;
end

function requireText(value, expected, name)
    if ~ischar(value) || size(value, 1) ~= 1 || ~strcmp(value, expected)
        error('ALEV4:InvalidRawMetadata', 'Unsupported or invalid %s.', name);
    end
end

function answer = isNonemptyText(value)
    answer = ischar(value) && ~isempty(value) && size(value, 1) == 1;
end

function requireInteger(value, lower, upper, name)
    if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
            ~isfinite(value) || value < lower || value > upper || value ~= floor(value)
        error('ALEV4:InvalidRawMetadata', '%s must be an integer in the supported range.', name);
    end
end

function closeQuietly(fid)
    try
        fclose(fid);
    catch
        % Do not mask an earlier validation/read error.
    end
end
