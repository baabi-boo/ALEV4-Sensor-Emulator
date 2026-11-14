function [decoded, meta] = readDualGainBundle(output_base)
%READDUALGAINBUNDLE Validate and read a versioned synthetic dual-gain bundle.
%   [DECODED, META] = alev4.readDualGainBundle(BASE) decodes exact row-major
%   little-endian payloads, validates configuration/association, recomputes
%   the RAW-only merge, and checks observable validity/diagnostic consistency.
%   Physical-saturation flags are simulator knowledge, not inferred RAW data.
%   A valid manifest is required; partial publications are never accepted.
    if nargin ~= 1
        error('ALEV4:InvalidDualGainPath', 'Exactly one bundle base is required.');
    end
    [parent, stem] = alev4.validateBundleBase(output_base);
    metadata_path = fullfile(parent, [stem '.json']);
    requireRegularFile(metadata_path);
    try
        meta = alev4.decodeBundleJson(readMetadata(metadata_path));
    catch err
        error('ALEV4:InvalidDualGainMetadata', 'Cannot decode bundle manifest: %s', err.message);
    end
    required = {'format', 'schema_version', 'algorithm_version', 'synthetic', ...
        'calibrated_alev4', 'authentic_arriraw', 'configuration', 'image_size', ...
        'exposure_s', 'seed', 'input_units', 'array_order', 'byte_order', ...
        'runtime', 'provenance', 'files', 'units', 'cfa_origin'};
    requireFields(meta, required, 'manifest');
    requireText(meta.format, 'ALEV4-SYNTHETIC-DUAL-GAIN', 'format');
    requireText(meta.schema_version, '1.0', 'schema_version');
    requireText(meta.algorithm_version, 'phase2-dual-gain-v1', 'algorithm_version');
    requireText(meta.input_units, 'photons m^-2 s^-1 nm^-1', 'input_units');
    requireText(meta.array_order, 'row-major', 'array_order');
    requireText(meta.byte_order, 'little-endian', 'byte_order');
    requireText(meta.cfa_origin, 'top-left (1,1)', 'cfa_origin');
    requireBoolean(meta.synthetic, true, 'synthetic');
    requireBoolean(meta.calibrated_alev4, false, 'calibrated_alev4');
    requireBoolean(meta.authentic_arriraw, false, 'authentic_arriraw');
    requireScalar(meta.exposure_s, 0, realmax, false, 'exposure_s');
    requireScalar(meta.seed, 0, 2^32 - 1, true, 'seed');
    defaults = alev4.createDualGainSensor();
    requireFields(meta.configuration, fieldnames(defaults), 'configuration');
    for field = {'sensor', 'high_gain', 'low_gain', 'merge'}
        requireFields(meta.configuration.(field{1}), fieldnames(defaults.(field{1})), field{1});
    end
    try
        sensor = meta.configuration.sensor;
        if isnumeric(sensor.qe) && numel(sensor.wavelength_nm) == 1 && ...
                isvector(sensor.qe) && numel(sensor.qe) == 3
            sensor.qe = sensor.qe(:).';
        end
        meta.configuration.sensor = sensor;
        cfg = alev4.createDualGainSensor(meta.configuration);
    catch err
        error('ALEV4:InvalidDualGainMetadata', 'Invalid complete configuration: %s', err.message);
    end
    if ~isnumeric(meta.image_size) || ~isreal(meta.image_size) || ...
            ~isvector(meta.image_size) || numel(meta.image_size) ~= 2 || ...
            ~isequal(double(meta.image_size(:).'), cfg.sensor.image_size)
        error('ALEV4:InvalidDualGainMetadata', 'Manifest and sensor image dimensions disagree.');
    end
    requireFields(meta.runtime, {'name', 'version'}, 'runtime');
    if ~isNonemptyText(meta.runtime.name) || ~isNonemptyText(meta.runtime.version) || ...
            ~any(strcmp(meta.runtime.name, {'GNU Octave', 'MATLAB'}))
        error('ALEV4:InvalidDualGainMetadata', 'Runtime identity must contain nonempty text.');
    end
    provenance_names = {'repository_head', 'isetcam_head', 'isethdrsensor_head', 'meaning'};
    requireFields(meta.provenance, provenance_names, 'provenance');
    if ~isNonemptyText(meta.provenance.meaning)
        error('ALEV4:InvalidDualGainMetadata', 'Provenance meaning is required.');
    end
    for k = 1:3
        value = meta.provenance.(provenance_names{k});
        if ~ischar(value) || (~isempty(value) && ...
                (size(value, 1) ~= 1 || isempty(regexp(value, '^[0-9a-f]{40}$', 'once'))))
            error('ALEV4:InvalidDualGainMetadata', 'An observed provenance SHA is malformed.');
        end
    end
    keys = {'high_raw', 'low_raw', 'merged_electrons', 'flags'};
    names = {[stem '.high.raw'], [stem '.low.raw'], [stem '.merged.f64'], [stem '.flags.u8']};
    units = {'DN', 'DN', 'electrons', 'bitmask'};
    requireExactFields(meta.files, keys, 'files');
    requireExactFields(meta.units, keys, 'units');
    paths = cell(1, 4);
    for k = 1:4
        requireText(meta.files.(keys{k}), names{k}, ['files.' keys{k}]);
        requireText(meta.units.(keys{k}), units{k}, ['units.' keys{k}]);
        paths{k} = fullfile(parent, names{k}); requireRegularFile(paths{k});
    end
    requireDistinctPayloads(paths);
    high = readPlane(paths{1}, cfg.sensor.image_size, '*uint16', 2);
    low = readPlane(paths{2}, cfg.sensor.image_size, '*uint16', 2);
    exported = readPlane(paths{3}, cfg.sensor.image_size, '*double', 8);
    flags = readPlane(paths{4}, cfg.sensor.image_size, '*uint8', 1);
    try
        merged = alev4.mergeDualGain(high, low, cfg);
    catch err
        error('ALEV4:InvalidDualGainMetadata', 'Invalid recorded ADC values: %s', err.message);
    end
    % Match the independent Python verifier: 64 ULPs at the reconstructed
    % value (with a unit scale floor), never a tolerance widened by bad bytes.
    tolerance = 64 * eps(max(1, abs(merged.electrons)));
    if any(~isfinite(exported(:))) || any(abs(exported(:) - merged.electrons(:)) > tolerance(:))
        error('ALEV4:InvalidDualGainMetadata', 'Merged payload disagrees with reconstructed RAW.');
    end
    fullwell = logical(bitget(flags, 1));
    high_low = logical(bitget(flags, 2)); high_high = logical(bitget(flags, 3));
    low_low = logical(bitget(flags, 4)); low_high = logical(bitget(flags, 5));
    high_usable = logical(bitget(flags, 6)); low_usable = logical(bitget(flags, 7));
    valid = logical(bitget(flags, 8));
    if ~isequal(high_usable, merged.high_usable) || ~isequal(low_usable, merged.low_usable) || ...
            ~isequal(valid, merged.valid & ~fullwell) || ...
            any(high_low(:) & high(:) ~= 0) || ...
            any(high_high(:) & double(high(:)) ~= 2^cfg.high_gain.adc_bits - 1) || ...
            any(low_low(:) & low(:) ~= 0) || ...
            any(low_high(:) & double(low(:)) ~= 2^cfg.low_gain.adc_bits - 1)
        error('ALEV4:InvalidDualGainMetadata', 'Validity or clipping flags contradict recorded codes.');
    end
    % Keep the exported plane after verifying it, so readback reflects bytes.
    merged.electrons = exported;
    decoded = struct('high_gain', struct('raw_dn', high, 'adc_low_clipped', high_low, ...
        'adc_high_clipped', high_high), 'low_gain', struct('raw_dn', low, ...
        'adc_low_clipped', low_low, 'adc_high_clipped', low_high), ...
        'merged', merged, 'full_well_saturated', fullwell, ...
        'reconstruction_valid', valid, 'flags', flags, ...
        'exposure_s', double(meta.exposure_s), 'seed', double(meta.seed));
    meta.configuration = cfg;
    meta.image_size = cfg.sensor.image_size;
end

function requireFields(value, names, label)
    if ~isstruct(value) || ~isscalar(value) || ~all(isfield(value, names))
        error('ALEV4:InvalidDualGainMetadata', '%s must contain every required field.', label);
    end
end

function requireExactFields(value, names, label)
    requireFields(value, names, label);
    if numel(fieldnames(value)) ~= numel(names)
        error('ALEV4:InvalidDualGainMetadata', '%s contains unknown fields.', label);
    end
end

function requireText(value, expected, label)
    if ~ischar(value) || size(value, 1) ~= 1 || ~strcmp(value, expected)
        error('ALEV4:InvalidDualGainMetadata', 'Invalid or unsupported %s.', label);
    end
end

function requireBoolean(value, expected, label)
    if ~islogical(value) || ~isscalar(value) || value ~= expected
        error('ALEV4:InvalidDualGainMetadata', 'Invalid %s label.', label);
    end
end

function requireScalar(value, lower, upper, integer, label)
    if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
            ~isfinite(value) || value < lower || value > upper || (integer && value ~= fix(value))
        error('ALEV4:InvalidDualGainMetadata', 'Invalid %s.', label);
    end
end

function result = isNonemptyText(value)
    result = ischar(value) && ~isempty(value) && size(value, 1) == 1 && ~any(value == char(0));
end

function requireRegularFile(path)
    if exist('lstat', 'builtin') || exist('lstat', 'file')
        [info, status] = lstat(path);
        if status ~= 0 || isempty(info.modestr) || info.modestr(1) ~= '-'
            error('ALEV4:DualGainBundleMissing', 'Bundle paths must be existing regular files, never symlinks.');
        end
    elseif exist('usejava', 'builtin') || exist('usejava', 'file')
        if usejava('jvm')
            java_file = javaObject('java.io.File', path);
            if javaMethod('isSymbolicLink', 'java.nio.file.Files', java_file.toPath())
                error('ALEV4:DualGainBundleMissing', 'Symlinked bundle paths are unsupported.');
            end
        end
    end
    if exist(path, 'file') ~= 2
        error('ALEV4:DualGainBundleMissing', 'Every bundle payload and manifest is required.');
    end
end

function requireDistinctPayloads(paths)
    if exist('lstat', 'builtin') || exist('lstat', 'file')
        identities = cell(size(paths));
        for k = 1:numel(paths)
            [info, status] = lstat(paths{k});
            if status ~= 0
                error('ALEV4:DualGainBundleMissing', 'A payload disappeared during validation.');
            end
            identities{k} = info;
            for previous = 1:k-1
                other = identities{previous};
                if isequal(info.dev, other.dev) && isequal(info.ino, other.ino)
                    error('ALEV4:InvalidDualGainMetadata', 'Payload files must not alias the same file.');
                end
            end
        end
    elseif (exist('usejava', 'builtin') || exist('usejava', 'file')) && usejava('jvm')
        for k = 1:numel(paths)
            current = javaObject('java.io.File', paths{k});
            for previous = 1:k-1
                other = javaObject('java.io.File', paths{previous});
                if javaMethod('isSameFile', 'java.nio.file.Files', current.toPath(), other.toPath())
                    error('ALEV4:InvalidDualGainMetadata', 'Payload files must not alias the same file.');
                end
            end
        end
    end
end

function value = readMetadata(path)
    [fid, message] = fopen(path, 'rb');
    if fid < 0, error('ALEV4:DualGainReadFailed', 'Cannot open manifest: %s', message); end
    cleanup = onCleanup(@() closeQuietly(fid)); %#ok<NASGU>
    bytes = fread(fid, 2000001, '*uint8');
    [message, error_number] = ferror(fid);
    if error_number ~= 0 || numel(bytes) < 2 || numel(bytes) > 2000000
        error('ALEV4:InvalidDualGainMetadata', 'Invalid manifest read/size: %s', message);
    end
    value = native2unicode(bytes.', 'UTF-8');
    encoded = unicode2native(value, 'UTF-8');
    if ~isequal(encoded(:), bytes(:))
        error('ALEV4:InvalidDualGainMetadata', 'Manifest is not valid UTF-8.');
    end
end

function plane = readPlane(path, shape, precision, bytes_per_sample)
    pixels = prod(shape);
    [fid, message] = fopen(path, 'rb', 'ieee-le');
    if fid < 0, error('ALEV4:DualGainReadFailed', 'Cannot open payload: %s', message); end
    cleanup = onCleanup(@() closeQuietly(fid)); %#ok<NASGU>
    if fseek(fid, 0, 'eof') ~= 0 || ftell(fid) ~= pixels * bytes_per_sample || ...
            fseek(fid, 0, 'bof') ~= 0
        error('ALEV4:DualGainSizeMismatch', 'Payload byte count differs from configured dimensions.');
    end
    [values, count] = fread(fid, pixels, precision);
    trailing = fread(fid, 1, '*uint8');
    [message, error_number] = ferror(fid);
    if error_number ~= 0 || count ~= pixels || ~isempty(trailing)
        error('ALEV4:DualGainSizeMismatch', 'Payload is incomplete or changed while reading: %s', message);
    end
    plane = reshape(values, shape(2), shape(1)).';
end

function closeQuietly(fid)
    try, fclose(fid); catch, end
end
