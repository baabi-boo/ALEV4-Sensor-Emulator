function summary = phase1_demo(output_dir, include_iset)
%PHASE1_DEMO Produce reproducible generic sensor fixtures and synthetic RAW.
%   SUMMARY = phase1_demo() writes to outputs/demo and requires ISETCam.
%   SUMMARY = phase1_demo(OUTPUT_DIR, false) runs standalone fixtures only;
%   its summary explicitly records that ISET integration was not run.
%
%   The four irradiance fixtures and five exposure-bracket frames use fixed
%   seeds. Each frame has a synthetic RAW payload, JSON sensor manifest, and
%   an 8-bit grayscale PGM of the Bayer mosaic. The preview is NOT demosaiced,
%   white-balanced, color-rendered, or independently normalized per frame.
%   RAW codes are linearly mapped from the configured ADC range to [0,255].
%
%   Use a fresh output directory for each invocation. Existing conflicting
%   files are refused before simulation. Files completed before a later
%   failure are retained for diagnosis, never silently deleted or replaced.
%   Concurrent writers to the same output directory are unsupported.
%   This demo does not establish ALEV4 calibration or 17-stop performance.
    root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    if nargin < 1, output_dir = fullfile(root, 'outputs', 'demo'); end
    if nargin < 2, include_iset = true; end
    if ~ischar(output_dir) || isempty(output_dir) || size(output_dir, 1) ~= 1 || ...
            any(output_dir == char(0))
        error('ALEV4:InvalidDemoPath', 'Output directory must be a nonempty character row.');
    end
    if ~islogical(include_iset) || ~isscalar(include_iset)
        error('ALEV4:InvalidDemoMode', 'include_iset must be a logical scalar.');
    end
    if exist(output_dir, 'file') ~= 0 && exist(output_dir, 'dir') ~= 7
        error('ALEV4:DemoDirectory', 'The output path exists and is not a directory.');
    end

    fixture_names = {'black', 'flat', 'ramp', 'checker'};
    bracket_names = {'exposure_025x', 'exposure_050x', 'exposure_100x', ...
        'exposure_200x', 'exposure_400x'};
    stems = [fixture_names bracket_names];
    if include_iset, stems{end+1} = 'iset_scene'; end
    for k = 1:numel(stems)
        for extension = {'.raw', '.json', '.pgm'}
            refuseExisting(fullfile(output_dir, [stems{k} extension{1}]));
        end
    end
    summary_path = fullfile(output_dir, 'phase1-demo-summary.json');
    refuseExisting(summary_path);

    addpath(fullfile(root, 'matlab'));
    setup_project(include_iset);
    if exist(output_dir, 'dir') ~= 7
        [ok, message] = mkdir(output_dir);
        if ~ok, error('ALEV4:DemoDirectory', 'Cannot create output directory: %s', message); end
    end

    cfg = alev4.createBaselineSensor(struct('image_size', [64 96]));
    exposure_s = 0.01;
    photon_density = 1e15; % photons/(m^2 s nm), illustrative, not measured ARRI data
    multipliers = [0.25 0.5 1 2 4];
    frames = struct([]);
    provenance = struct();
    for k = 1:numel(fixture_names)
        irradiance = alev4.createFixture(fixture_names{k}, cfg, photon_density);
        result = alev4.simulateExposure(irradiance, cfg, exposure_s, 100 + k);
        [frame, meta] = writeFrame(result, cfg, output_dir, fixture_names{k}, 'fixture');
        frames(end+1) = frame; %#ok<AGROW>
        if k == 1, provenance = meta.provenance; end
    end

    flat = alev4.createFixture('flat', cfg, photon_density);
    for k = 1:numel(multipliers)
        result = alev4.simulateExposure(flat, cfg, exposure_s * multipliers(k), 200 + k);
        frame = writeFrame(result, cfg, output_dir, bracket_names{k}, 'exposure_bracket');
        frames(end+1) = frame; %#ok<AGROW>
    end

    if include_iset
        [result, iset_cfg, integration] = alev4.isetBaseline(301, 1e-3);
        frame = writeFrame(result, iset_cfg, output_dir, 'iset_scene', 'iset_scene_to_raw');
        frames(end+1) = frame; %#ok<AGROW>
    else
        integration = struct('status', 'not_run', ...
            'reason', 'include_iset=false explicitly requested; this is not a full Phase 1 validation');
    end

    summary = struct();
    summary.schema_version = '1.0';
    summary.demo_complete = true;
    summary.synthetic = true;
    summary.calibrated_alev4 = false;
    summary.authentic_arriraw = false;
    summary.description = 'Generic Bayer CMOS fixtures; this demo is not an ALEV4 calibration claim.';
    summary.reference_exposure_s = exposure_s;
    summary.photon_density_per_m2_s_nm = photon_density;
    summary.exposure_multipliers = multipliers;
    summary.sensor = cfg;
    summary.frame_count = numel(frames);
    summary.frames = frames;
    summary.iset_integration = integration;
    summary.provenance = provenance;
    summary.paths_relative_to = 'directory containing this summary';
    summary.preview_description = ['8-bit linear grayscale Bayer mosaic: DN/(2^adc_bits-1); ' ...
        'no demosaic, black subtraction, white balance, color transform, or per-frame normalization'];
    summary.variance_description = ['collected_variance_e2 is unbiased sample variance across spatial/CFA ' ...
        'samples, not a temporal shot-noise measurement; shot_residual_variance_e2 uses collected minus expected'];
    if exist('OCTAVE_VERSION', 'builtin') ~= 0
        summary.runtime = struct('name', 'GNU Octave', 'version', OCTAVE_VERSION);
    else
        summary.runtime = struct('name', 'MATLAB', 'version', version);
    end
    writeSummary(summary_path, summary);
    fprintf('Demo completed: %d synthetic frames, ISET status %s.\n', ...
        summary.frame_count, summary.iset_integration.status);
end

function [frame, meta] = writeFrame(result, cfg, output_dir, stem, kind)
    base = fullfile(output_dir, stem);
    alev4.exportSyntheticRaw(result, cfg, base);
    [decoded, meta] = alev4.readSyntheticRaw(base);
    if ~isequal(decoded, result.raw_dn)
        error('ALEV4:DemoRoundtrip', 'Synthetic RAW readback differs for %s.', stem);
    end
    writePreview([base '.pgm'], result.raw_dn, cfg.adc_bits);
    count = numel(result.raw_dn);
    expected = result.expected_electrons(:);
    collected = result.collected_electrons(:);
    residual = collected - expected;
    frame = struct('name', stem, 'kind', kind, ...
        'raw_file', [stem '.raw'], 'metadata_file', [stem '.json'], ...
        'preview_file', [stem '.pgm'], 'image_size', cfg.image_size, ...
        'exposure_s', result.exposure_s, 'seed', result.seed, ...
        'mean_expected_electrons', mean(expected), ...
        'mean_collected_electrons', mean(collected), ...
        'collected_variance_e2', var(collected, 0), ...
        'shot_residual_variance_e2', var(residual, 0), ...
        'mean_raw_dn', mean(double(result.raw_dn(:))), ...
        'full_well_saturation_fraction', sum(result.full_well_saturated(:)) / count, ...
        'adc_low_clipping_fraction', sum(result.adc_low_clipped(:)) / count, ...
        'adc_high_clipping_fraction', sum(result.adc_high_clipped(:)) / count, ...
        'raw_roundtrip_exact', true);
    fprintf('%s: exposure %.6g s, mean %.6g e-, full-well saturation %.4f\n', ...
        stem, result.exposure_s, frame.mean_expected_electrons, frame.full_well_saturation_fraction);
end

function writePreview(path, raw, adc_bits)
    refuseExisting(path);
    temporary = [tempname(fileparts(path)) '.pgm.part'];
    cleanup = onCleanup(@() removeTemporary(temporary)); %#ok<NASGU>
    [fid, message] = fopen(temporary, 'wb');
    if fid < 0, error('ALEV4:DemoWrite', 'Cannot open preview: %s', message); end
    closer = onCleanup(@() closeQuietly(fid)); %#ok<NASGU>
    header = sprintf('P5\n# Synthetic Bayer mosaic; linear ADC scaling, no demosaic\n%d %d\n255\n', ...
        size(raw, 2), size(raw, 1));
    pixels = uint8(round(255 * double(raw) / (2^adc_bits - 1)));
    header_count = fwrite(fid, header, 'char');
    pixel_count = fwrite(fid, pixels.', 'uint8');
    close_status = fclose(fid);
    if header_count ~= numel(header) || pixel_count ~= numel(raw) || close_status ~= 0
        error('ALEV4:DemoWrite', 'Incomplete PGM preview write.');
    end
    publish(temporary, path);
end

function writeSummary(path, summary)
    refuseExisting(path);
    temporary = [tempname(fileparts(path)) '.json.part'];
    cleanup = onCleanup(@() removeTemporary(temporary)); %#ok<NASGU>
    [fid, message] = fopen(temporary, 'wb');
    if fid < 0, error('ALEV4:DemoWrite', 'Cannot open summary: %s', message); end
    closer = onCleanup(@() closeQuietly(fid)); %#ok<NASGU>
    bytes = unicode2native([jsonencode(summary) sprintf('\n')], 'UTF-8');
    count = fwrite(fid, bytes, 'uint8');
    close_status = fclose(fid);
    if count ~= numel(bytes) || close_status ~= 0
        error('ALEV4:DemoWrite', 'Incomplete demo summary write.');
    end
    publish(temporary, path);
end

function publish(temporary, path)
    refuseExisting(path);
    [ok, message] = movefile(temporary, path);
    if ~ok, error('ALEV4:DemoWrite', 'Cannot publish demo artifact: %s', message); end
end

function refuseExisting(path)
    if exist(path, 'file') ~= 0
        error('ALEV4:DemoAlreadyExists', ...
            'Refusing to overwrite %s. Run the demo with a fresh output directory.', path);
    end
end

function closeQuietly(fid)
    try
        fclose(fid);
    catch
        % The successful write path already closed this handle.
    end
end

function removeTemporary(path)
    if exist(path, 'file') == 2
        try
            delete(path);
        catch
            % Preserve the original failure, never remove another artifact.
        end
    end
end
