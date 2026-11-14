function files = exportDualGainBundle(result, cfg, output_base)
%EXPORTDUALGAINBUNDLE Export a labelled simultaneous-readout synthetic bundle.
%   Five files bind high/low uint16 DN, signed float64 merged electrons,
%   diagnostic/validity flags and a UTF-8 manifest. Binary planes are
%   little-endian, row-major. This is not ARRIRAW or calibrated camera data.
%   Existing files are refused; concurrent writers to one base are unsupported.
%   All files are staged, the manifest is published last, and failed partial
%   publications owned by this invocation are removed.
    if nargin ~= 3
        error('ALEV4:DualGainExportArguments', 'Result, configuration and output base are required.');
    end
    cfg = alev4.createDualGainSensor(cfg);
    [parent, stem] = alev4.validateBundleBase(output_base);
    names = {[stem '.high.raw'], [stem '.low.raw'], [stem '.merged.f64'], ...
        [stem '.flags.u8'], [stem '.json']};
    paths = cellfun(@(name) fullfile(parent, name), names, 'UniformOutput', false);
    for k = 1:numel(paths), refuseExisting(paths{k}); end
    if exist(parent, 'dir') ~= 7
        error('ALEV4:DualGainDirectoryMissing', 'The output directory must already exist.');
    end
    flags = validateResult(result, cfg);
    meta = struct('format', 'ALEV4-SYNTHETIC-DUAL-GAIN', ...
        'schema_version', '1.0', 'algorithm_version', 'phase2-dual-gain-v1', ...
        'synthetic', true, 'calibrated_alev4', false, 'authentic_arriraw', false, ...
        'configuration', cfg, 'image_size', cfg.sensor.image_size, ...
        'exposure_s', double(result.exposure_s), 'seed', double(result.seed), ...
        'input_units', 'photons m^-2 s^-1 nm^-1', 'array_order', 'row-major', ...
        'byte_order', 'little-endian', 'cfa_origin', 'top-left (1,1)', ...
        'files', struct('high_raw', names{1}, 'low_raw', names{2}, ...
            'merged_electrons', names{3}, 'flags', names{4}), ...
        'units', struct('high_raw', 'DN', 'low_raw', 'DN', ...
            'merged_electrons', 'electrons', 'flags', 'bitmask'));
    if exist('OCTAVE_VERSION', 'builtin')
        meta.runtime = struct('name', 'GNU Octave', 'version', OCTAVE_VERSION);
    else
        meta.runtime = struct('name', 'MATLAB', 'version', version);
    end
    meta.provenance = alev4.sourceProvenance();
    % Numeric tokens preserve binary64 precision. A bounded native-parser
    % check and configuration revalidation happen before any file staging;
    % native jsonencode must not silently turn a tiny exposure/QE into zero.
    [payload, observed] = alev4.encodeBundleJson(meta);
    try
        observed_cfg = observed.configuration;
        if numel(observed_cfg.sensor.wavelength_nm) == 1
            observed_cfg.sensor.qe = observed_cfg.sensor.qe(:).';
        end
        observed_cfg = alev4.createDualGainSensor(observed_cfg);
        observed_merge = alev4.mergeDualGain(result.high_gain.raw_dn, ...
            result.low_gain.raw_dn, observed_cfg);
        % Apply the same payload tolerance and observable validity contract
        % as the reader. A bounded metadata rounding error can otherwise be
        % amplified by near-black subtraction or a very small readout gain.
        tolerance = 64 * eps(max(1, abs(observed_merge.electrons)));
        if any(abs(result.merged.electrons(:) - observed_merge.electrons(:)) > tolerance(:)) || ...
                ~isequal(result.merged.high_usable, observed_merge.high_usable) || ...
                ~isequal(result.merged.low_usable, observed_merge.low_usable) || ...
                ~isequal(result.reconstruction_valid, ...
                    observed_merge.valid & ~result.full_well_saturated)
            error('ALEV4:InvalidDualGainMetadata', ...
                'Encoded configuration changes the readable RAW reconstruction.');
        end
    catch err
        error('ALEV4:InvalidDualGainMetadata', ...
            'Encoded configuration cannot be read back safely: %s', err.message);
    end
    bytes = unicode2native([payload sprintf('\n')], 'UTF-8');
    if numel(bytes) > 2e6
        error('ALEV4:InvalidDualGainMetadata', 'Manifest exceeds the 2,000,000-byte format limit.');
    end
    temps = cell(1, 5);
    for k = 1:5, temps{k} = [tempname(parent) '.dual.part']; end
    cleanup = onCleanup(@() cleanupFiles(temps)); %#ok<NASGU>
    published = false(1, 5);
    try
        writePlane(temps{1}, result.high_gain.raw_dn, 'uint16');
        writePlane(temps{2}, result.low_gain.raw_dn, 'uint16');
        writePlane(temps{3}, result.merged.electrons, 'double');
        writePlane(temps{4}, flags, 'uint8');
        writePlane(temps{5}, bytes(:).', 'uint8');
        for k = 1:5
            refuseExisting(paths{k});
            [ok, message] = movefile(temps{k}, paths{k});
            if ~ok, error('ALEV4:DualGainWriteFailed', 'Cannot publish bundle file: %s', message); end
            published(k) = true;
        end
    catch err
        cleanupFiles(paths(published));
        rethrow(err);
    end
    files = struct('high_raw', paths{1}, 'low_raw', paths{2}, ...
        'merged_electrons', paths{3}, 'flags', paths{4}, 'metadata', paths{5});
end

function flags = validateResult(result, cfg)
    fields = {'expected_electrons', 'collected_electrons', 'charge_electrons', ...
        'expected_incident_photons', 'full_well_saturated', 'high_gain', ...
        'low_gain', 'merged', 'reconstruction_valid', 'exposure_s', 'seed', 'input_units'};
    if ~isstruct(result) || ~isscalar(result) || ~all(isfield(result, fields))
        error('ALEV4:InvalidDualGainResult', 'A complete spectral dual-gain result is required.');
    end
    requireScalar(result.exposure_s, 0, realmax, false, 'exposure_s');
    requireScalar(result.seed, 0, 2^32 - 1, true, 'seed');
    if ~ischar(result.input_units) || ~strcmp(result.input_units, 'photons m^-2 s^-1 nm^-1')
        error('ALEV4:InvalidDualGainResult', 'Spectral input units are missing or invalid.');
    end
    shape = cfg.sensor.image_size;
    for name = {'expected_electrons', 'collected_electrons', 'charge_electrons', 'expected_incident_photons'}
        value = result.(name{1});
        requirePlane(value, shape, name{1});
        if any(value(:) < 0), error('ALEV4:InvalidDualGainResult', '%s must be nonnegative.', name{1}); end
    end
    if cfg.sensor.shot_noise
        if any(result.expected_electrons(:) > 1e9) || ...
                any(result.collected_electrons(:) ~= fix(result.collected_electrons(:)))
            error('ALEV4:InvalidDualGainResult', 'Shot-noise charge must be integer-valued with supported Poisson expectations.');
        end
    elseif ~isequal(result.collected_electrons, result.expected_electrons)
        error('ALEV4:InvalidDualGainResult', 'With shot noise disabled, collected charge must equal its expectation.');
    end
    photon_tolerance = 8 * eps(max(1, result.expected_incident_photons));
    if any(result.expected_electrons(:) - result.expected_incident_photons(:) > photon_tolerance(:))
        error('ALEV4:InvalidDualGainResult', 'Expected electrons cannot exceed incident photons for this QE model.');
    end
    if ~isequal(result.charge_electrons, min(result.collected_electrons, cfg.sensor.full_well_e))
        error('ALEV4:InvalidDualGainResult', 'Stored charge disagrees with shared full-well clipping.');
    end
    fullwell = requireMask(result.full_well_saturated, shape, 'full_well_saturated');
    if ~isequal(fullwell, result.collected_electrons >= cfg.sensor.full_well_e)
        error('ALEV4:InvalidDualGainResult', 'Physical-saturation mask disagrees with collected charge.');
    end
    for label = {'high_gain', 'low_gain'}
        name = label{1}; path = result.(name); setting = cfg.(name);
        if ~isstruct(path) || ~isscalar(path) || ...
                ~all(isfield(path, {'raw_dn', 'read_electrons', 'adc_low_clipped', 'adc_high_clipped'}))
            error('ALEV4:InvalidDualGainResult', 'Incomplete %s readout.', name);
        end
        requirePlane(path.read_electrons, shape, [name '.read_electrons']);
        requirePlane(path.raw_dn, shape, [name '.raw_dn']);
        if setting.read_noise_e == 0 && ~isequal(path.read_electrons, result.charge_electrons)
            error('ALEV4:InvalidDualGainResult', 'With read noise disabled, %s must read the shared stored charge exactly.', name);
        end
        if ~isa(path.raw_dn, 'uint16')
            error('ALEV4:InvalidDualGainResult', 'Recorded RAW must be uint16.');
        end
        analog = path.read_electrons .* setting.gain_dn_per_e + setting.black_level_dn;
        if any(~isfinite(analog(:)))
            error('ALEV4:InvalidDualGainResult', 'Readout arithmetic is nonfinite.');
        end
        rounded = round(analog); maximum = 2^setting.adc_bits - 1;
        if ~isequal(path.raw_dn, uint16(min(max(rounded, 0), maximum))) || ...
                ~isequal(requireMask(path.adc_low_clipped, shape, 'ADC low mask'), rounded < 0) || ...
                ~isequal(requireMask(path.adc_high_clipped, shape, 'ADC high mask'), rounded > maximum)
            error('ALEV4:InvalidDualGainResult', 'Recorded codes or clipping masks contradict %s electronics.', name);
        end
    end
    merged = alev4.mergeDualGain(result.high_gain.raw_dn, result.low_gain.raw_dn, cfg);
    if ~isstruct(result.merged) || ~isscalar(result.merged) || ...
            ~all(isfield(result.merged, fieldnames(merged)))
        error('ALEV4:InvalidDualGainResult', 'The complete merge result is required.');
    end
    for name = {'electrons', 'weight_high', 'valid', 'high_usable', 'low_usable'}
        if ~isequal(result.merged.(name{1}), merged.(name{1}))
            error('ALEV4:InvalidDualGainResult', 'Merge data disagree with the observed RAW channels.');
        end
    end
    valid = requireMask(result.reconstruction_valid, shape, 'reconstruction_valid');
    if ~isequal(valid, merged.valid & ~fullwell)
        error('ALEV4:InvalidDualGainResult', 'Reconstruction validity ignores a rail or physical saturation.');
    end
    flags = uint8(fullwell) + 2*uint8(result.high_gain.adc_low_clipped) + ...
        4*uint8(result.high_gain.adc_high_clipped) + 8*uint8(result.low_gain.adc_low_clipped) + ...
        16*uint8(result.low_gain.adc_high_clipped) + 32*uint8(merged.high_usable) + ...
        64*uint8(merged.low_usable) + 128*uint8(valid);
end

function requirePlane(value, shape, name)
    if ~isnumeric(value) || ~isreal(value) || ~ismatrix(value) || ...
            ~isequal(size(value), shape) || any(~isfinite(value(:)))
        error('ALEV4:InvalidDualGainResult', '%s must be a finite numeric image plane.', name);
    end
end

function mask = requireMask(mask, shape, name)
    if ~islogical(mask) || ~ismatrix(mask) || ~isequal(size(mask), shape)
        error('ALEV4:InvalidDualGainResult', '%s must be a logical image plane.', name);
    end
end

function requireScalar(value, lower, upper, integer, name)
    if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
            ~isfinite(value) || value < lower || value > upper || (integer && value ~= fix(value))
        error('ALEV4:InvalidDualGainResult', '%s is invalid.', name);
    end
end

function refuseExisting(path)
    exists = alev4.bundlePathExists(path);
    if exists
        error('ALEV4:DualGainAlreadyExists', 'Refusing to overwrite an existing bundle path.');
    end
end

function writePlane(path, values, precision)
    [fid, message] = fopen(path, 'wb', 'ieee-le');
    if fid < 0, error('ALEV4:DualGainWriteFailed', 'Cannot create staged payload: %s', message); end
    cleanup = onCleanup(@() closeQuietly(fid)); %#ok<NASGU>
    count = fwrite(fid, values.', precision);
    close_status = fclose(fid);
    if count ~= numel(values) || close_status ~= 0
        error('ALEV4:DualGainWriteFailed', 'Incomplete staged payload write.');
    end
end

function closeQuietly(fid)
    try, fclose(fid); catch, end
end

function cleanupFiles(paths)
    for k = 1:numel(paths)
        if exist(paths{k}, 'file') == 2
            try, delete(paths{k}); catch, end
        end
    end
end
