function report = run_phase1_tests(output_dir, require_iset)
%RUN_PHASE1_TESTS Execute required tests and write machine-readable evidence.
%   run_phase1_tests() runs all gates, including ISETCam integration.
%   run_phase1_tests(path, false) runs core/I/O only; phase1_passed is FALSE.
%   A missing dependency or failing assertion raises an error/nonzero exit.
    if nargin < 1
        output_dir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'outputs', 'validation');
    end
    if nargin < 2, require_iset = true; end
    if ~islogical(require_iset) || ~isscalar(require_iset)
        error('ALEV4:InvalidSetupMode', 'require_iset must be a logical scalar.');
    end
    if ~ischar(output_dir) || isempty(output_dir) || size(output_dir, 1) ~= 1
        error('ALEV4:InvalidOutputPath', 'Output directory must be a nonempty character row.');
    end
    if ~isfolder(output_dir)
        [ok, message] = mkdir(output_dir);
        if ~ok, error('ALEV4:OutputDirectory', '%s', message); end
    end
    report = struct('schema_version', '1.0', 'phase', 1, 'runtime_version', version, ...
        'status', 'running', 'phase1_passed', false, 'calibrated_alev4', false);
    if exist('OCTAVE_VERSION', 'builtin')
        report.runtime = 'GNU Octave';
    else
        report.runtime = 'MATLAB';
    end
    destination = fullfile(output_dir, 'phase1-validation.json');
    % Invalidate any earlier success BEFORE executing new tests. Failure or
    % interruption cannot leave a stale pass report for the current run.
    writeReport(destination, report);
    try
        setup_project(require_iset);
        report.provenance = alev4.sourceProvenance();
        report.provenance_tests = test_provenance();
        report.core = test_phase1_core();
        report.config_edges = test_config_edges();
        report.spectral_properties = test_spectral_properties();
        report.input_representation = test_input_representation();
        report.numerical_edges = test_numerical_edges();
        report.poisson_edges = test_poisson_edges();
        report.raw_io = test_raw_io();
        if require_iset
            report.iset = test_iset_integration();
            report.phase1_passed = true;
            report.status = 'passed';
        else
            report.iset = struct('status', 'not_run', 'reason', 'Core-only execution requested');
            report.status = 'core_only';
        end
    catch err
        report.status = 'failed';
        report.phase1_passed = false;
        report.error = struct('identifier', err.identifier, 'message', err.message);
        writeReport(destination, report);
        rethrow(err);
    end
    writeReport(destination, report);
    fprintf('Phase 1 required gates passed: %d (%s %s)\n', report.phase1_passed, report.runtime, report.runtime_version);
end

function writeReport(destination, report)
    % JSON character data can contain localized errors or non-ASCII paths.
    % Encode explicitly so the report is valid UTF-8 on every host locale.
    payload = jsonencode(report);
    bytes = unicode2native(payload, 'UTF-8');
    fid = fopen(destination, 'wb');
    if fid < 0, error('ALEV4:ReportWrite', 'Cannot open validation report.'); end
    cleanup = onCleanup(@() closeQuietly(fid)); %#ok<NASGU>
    count = fwrite(fid, bytes, 'uint8');
    close_status = fclose(fid);
    if count ~= numel(bytes) || close_status ~= 0
        error('ALEV4:ReportWrite', 'Incomplete validation report write.');
    end
end

function closeQuietly(fid)
    try
        fclose(fid);
    catch
        % Normal completion has already closed this handle.
    end
end
