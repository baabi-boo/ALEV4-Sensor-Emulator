function summary = phase2_demo(output_dir)
%PHASE2_DEMO Six reproducible simultaneous dual-gain synthetic fixtures.
%   SUMMARY = phase2_demo(OUTPUT_DIR) creates six five-file bundles plus a
%   summary. Fixtures span dark, shadows, both merge boundaries, high-gain
%   clipping, shared full-well saturation and seeded noise. All parameters
%   are illustrative; no calibrated ALEV4 performance is claimed.
%   Use a fresh directory. Existing conflicting files are refused before
%   simulation. Completed bundles remain available if a later frame fails.
    root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    if nargin < 1, output_dir = fullfile(root, 'outputs', 'phase2-demo'); end
    if ~ischar(output_dir) || isempty(output_dir) || size(output_dir, 1) ~= 1 || ...
            any(double(output_dir) < 32)
        error('ALEV4:InvalidDualGainDemoPath', 'Output directory must be a nonempty character row.');
    end
    if exist(output_dir, 'file') ~= 0 && exist(output_dir, 'dir') ~= 7
        error('ALEV4:DualGainDemoDirectory', 'Output path exists and is not a directory.');
    end
    names = {'dark', 'shadow', 'transition', 'highlight', 'saturation', 'noisy'};
    suffixes = {'.high.raw', '.low.raw', '.merged.f64', '.flags.u8', '.json'};
    for k = 1:numel(names)
        for j = 1:numel(suffixes)
            refuseExisting(fullfile(output_dir, [names{k} suffixes{j}]));
        end
    end
    summary_path = fullfile(output_dir, 'phase2-demo-summary.json');
    refuseExisting(summary_path);
    addpath(fullfile(root, 'matlab'));
    setup_project(false);
    if exist(output_dir, 'dir') ~= 7
        [ok, message] = mkdir(output_dir);
        if ~ok, error('ALEV4:DualGainDemoDirectory', 'Cannot create output directory: %s', message); end
    end
    sensor = struct('image_size', [17 257], 'wavelength_nm', 550, ...
        'bin_width_nm', 10, 'qe', [0.5 0.5 0.5], 'pixel_pitch_m', 1e-6, ...
        'fill_factor', 1, 'shot_noise', false);
    exposure_s = 0.01;
    conversion = exposure_s * sensor.pixel_pitch_m^2 * sensor.fill_factor * ...
        sensor.bin_width_nm * sensor.qe(1);
    levels = [0 10 0 12000 40000 250];
    frames = struct([]);
    for k = 1:numel(names)
        cfg = alev4.createDualGainSensor(struct('sensor', sensor, ...
            'high_gain', struct('read_noise_e', 0), ...
            'low_gain', struct('read_noise_e', 0)));
        target = levels(k) * ones(sensor.image_size);
        if k == 3, target = repmat(400 + 4*(0:256), sensor.image_size(1), 1); end
        if k == 6
            cfg.sensor.shot_noise = true;
            cfg.high_gain.read_noise_e = 1;
            cfg.low_gain.read_noise_e = 5;
        end
        result = alev4.simulateDualGainExposure(target / conversion, cfg, exposure_s, 200 + k);
        base = fullfile(output_dir, names{k});
        alev4.exportDualGainBundle(result, cfg, base);
        [decoded, meta] = alev4.readDualGainBundle(base);
        if ~isequal(decoded.high_gain.raw_dn, result.high_gain.raw_dn) || ...
                ~isequal(decoded.low_gain.raw_dn, result.low_gain.raw_dn) || ...
                ~isequal(decoded.merged.electrons, result.merged.electrons) || ...
                ~isequal(decoded.full_well_saturated, result.full_well_saturated) || ...
                ~isequal(decoded.reconstruction_valid, result.reconstruction_valid)
            error('ALEV4:DualGainDemoRoundtrip', 'Bundle readback differs from the simulated result.');
        end
        frame = struct('name', names{k}, 'metadata_file', [names{k} '.json'], ...
            'exposure_s', exposure_s, 'seed', result.seed, ...
            'mean_expected_electrons', mean(result.expected_electrons(:)), ...
            'mean_merged_electrons', mean(result.merged.electrons(:)), ...
            'full_well_saturation_fraction', mean(result.full_well_saturated(:)), ...
            'high_adc_clipping_fraction', mean(result.high_gain.adc_low_clipped(:) | result.high_gain.adc_high_clipped(:)), ...
            'low_adc_clipping_fraction', mean(result.low_gain.adc_low_clipped(:) | result.low_gain.adc_high_clipped(:)), ...
            'reconstruction_valid_fraction', mean(result.reconstruction_valid(:)));
        frames(end+1) = frame; %#ok<AGROW>
        fprintf('%s: expected %.6g e-, merged %.6g e-, valid %.4f\n', ...
            names{k}, frame.mean_expected_electrons, frame.mean_merged_electrons, frame.reconstruction_valid_fraction);
    end
    summary = struct('schema_version', '1.0', 'phase', 2, ...
        'demo_complete', true, 'synthetic', true, 'calibrated_alev4', false, ...
        'authentic_arriraw', false, 'runtime', meta.runtime, 'provenance', meta.provenance, ...
        'frame_count', numel(frames), 'frames', frames, ...
        'paths_relative_to', 'directory containing this summary', ...
        'description', 'Generic simultaneous dual-gain synthetic fixtures; not calibrated ALEV4 or ARRIRAW.');
    bytes = unicode2native([jsonencode(summary) sprintf('\n')], 'UTF-8');
    temporary = [tempname(output_dir) '.summary.part'];
    cleanup = onCleanup(@() deleteTemporary(temporary)); %#ok<NASGU>
    fid = fopen(temporary, 'wb');
    if fid < 0, error('ALEV4:DualGainDemoWrite', 'Cannot create temporary summary.'); end
    closer = onCleanup(@() closeQuietly(fid)); %#ok<NASGU>
    count = fwrite(fid, bytes, 'uint8'); close_status = fclose(fid);
    if count ~= numel(bytes) || close_status ~= 0
        error('ALEV4:DualGainDemoWrite', 'Incomplete summary write.');
    end
    refuseExisting(summary_path);
    [ok, message] = movefile(temporary, summary_path);
    if ~ok, error('ALEV4:DualGainDemoWrite', 'Cannot publish summary: %s', message); end
    fprintf('Phase 2 demo completed: %d synthetic bundles.\n', numel(frames));
end

function refuseExisting(path)
    exists = alev4.bundlePathExists(path);
    if exists
        error('ALEV4:DualGainAlreadyExists', 'Use a fresh directory; a demo destination already exists.');
    end
end

function closeQuietly(fid)
    try, fclose(fid); catch, end
end

function deleteTemporary(path)
    if exist(path, 'file') == 2
        try, delete(path); catch, end
    end
end
