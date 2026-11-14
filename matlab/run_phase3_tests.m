function report = run_phase3_tests(output_dir, require_phase2)
%RUN_PHASE3_TESTS Execute geometry, optics, and spatial gates and retain truthful validation evidence.
%   run_phase3_tests() runs all Phase 3 suites and the complete Phase 2/Phase 1
%   numerical/ISETCam prerequisites. Missing or failed gates raise an error.
%   run_phase3_tests(path, false) runs standalone Phase 3 suites only;
%   status is core_only and phase3_passed remains FALSE.
%
%   This report covers numerical execution. Full phase acceptance also
%   requires independent demo artifacts, repeated-process verification and
%   clean pinned dependencies, as described in the Phase 3 documentation.
    if nargin < 1
        output_dir = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
            'outputs', 'phase3', 'validation');
    end
    if nargin < 2, require_phase2 = true; end
    if ~islogical(require_phase2) || ~isscalar(require_phase2)
        error('ALEV4:InvalidSetupMode', 'require_phase2 must be a logical scalar.');
    end
    if ~ischar(output_dir) || isempty(output_dir) || size(output_dir, 1) ~= 1 || ...
            any(output_dir == char(0))
        error('ALEV4:InvalidOutputPath', 'Output directory must be a nonempty character row.');
    end
    if exist(output_dir, 'file') ~= 0 && exist(output_dir, 'dir') ~= 7
        error('ALEV4:OutputDirectory', 'The output path exists and is not a directory.');
    end
    if ~isfolder(output_dir)
        [ok, message] = mkdir(output_dir);
        if ~ok, error('ALEV4:OutputDirectory', '%s', message); end
    end
    report = struct('schema_version', '1.0', 'phase', 3, ...
        'runtime_version', version, 'status', 'running', ...
        'phase3_passed', false, 'calibrated_alev4', false, ...
        'phase2_required', require_phase2);
    if exist('OCTAVE_VERSION', 'builtin')
        report.runtime = 'GNU Octave';
    else
        report.runtime = 'MATLAB';
    end
    report.phase2 = struct('status', 'not_run', 'phase2_passed', false, ...
        'reason', 'Phase 2 prerequisite has not executed.');
    destination = fullfile(output_dir, 'phase3-validation.json');
    % Invalidate any previous success before setup or numerical execution.
    % If this write itself fails, the invocation fails; an old report must
    % never substitute for the current process exit status.
    writeReport(destination, report);
    try
        setup_project(require_phase2);
        report.provenance = alev4.sourceProvenance();
        functions = {'test_phase3_geometry', 'test_phase3_geometry_edges', ...
            'test_phase3_sampling', 'test_phase3_optics', ...
            'test_phase3_integration', 'test_phase3_artifacts', ...
            'test_phase3_numerical_edges', 'test_phase3_demo'};
        fields = {'geometry', 'geometry_edges', 'sampling', 'optics', ...
            'integration', 'spatial_io', 'numerical_edges', 'demo_contract'};
        for k = 1:numel(functions)
            report.(fields{k}) = feval(functions{k});
            requirePassedSuite(report.(fields{k}), fields{k});
        end
        if require_phase2
            report.iset_spatial = test_phase3_iset();
            requirePassedSuite(report.iset_spatial, 'iset_spatial');
            report.phase2 = run_phase2_tests( ...
                fullfile(output_dir, 'phase2-regression'), true);
            if ~passedReport(report.phase2,'phase2_passed') || ...
                    ~isfield(report.phase2,'phase1_required') || ...
                    ~trueLogical(report.phase2.phase1_required) || ...
                    ~isfield(report.phase2,'phase1') || ...
                    ~passedReport(report.phase2.phase1,'phase1_passed') || ...
                    ~isfield(report.phase2.phase1,'iset') || ...
                    ~isstruct(report.phase2.phase1.iset) || ...
                    ~isscalar(report.phase2.phase1.iset) || ...
                    ~isfield(report.phase2.phase1.iset,'status') || ...
                    ~passedText(report.phase2.phase1.iset.status)
                error('ALEV4:Phase2Prerequisite', ...
                    'The complete Phase 2 prerequisite did not report a pass.');
            end
            report.status = 'passed';
            report.phase3_passed = true;
        else
            report.phase2.reason = 'Standalone Phase 3 execution explicitly requested.';
            report.status = 'core_only';
        end
    catch err
        report.status = 'failed';
        report.phase3_passed = false;
        report.error = struct('identifier', err.identifier, 'message', err.message);
        writeReport(destination, report);
        rethrow(err);
    end
    writeReport(destination, report);
    fprintf('Phase 3 numerical gates passed: %d (%s %s)\n', ...
        report.phase3_passed, report.runtime, report.runtime_version);
end

function requirePassedSuite(suite, name)
    if ~isstruct(suite) || ~isscalar(suite) || ...
            ~isfield(suite, 'status') || ~passedText(suite.status) || ...
            ~isfield(suite, 'passed') || ~trueLogical(suite.passed) || ...
            ~isfield(suite, 'test_count') || ...
            ~isnumeric(suite.test_count) || ~isreal(suite.test_count) || ...
            ~isscalar(suite.test_count) || ~isfinite(suite.test_count) || ...
            suite.test_count < 1 || suite.test_count ~= fix(suite.test_count) || ...
            ~isfield(suite, 'tests') || ~isstruct(suite.tests) || ...
            numel(suite.tests) ~= suite.test_count
        error('ALEV4:Phase3SuiteFailed', ...
            'Required Phase 3 suite %s did not report a complete pass.', name);
    end
    test_names = cell(1, numel(suite.tests));
    for k = 1:numel(suite.tests)
        test = suite.tests(k);
        if ~isfield(test, 'name') || ~ischar(test.name) || ...
                ~isrow(test.name) || isempty(strtrim(test.name)) || ...
                ~isfield(test, 'status') || ~passedText(test.status) || ...
                ~isfield(test, 'passed') || ~trueLogical(test.passed)
            error('ALEV4:Phase3SuiteFailed', ...
                'Required Phase 3 suite %s contains an unpassed test.', name);
        end
        test_names{k} = test.name;
    end
    if numel(unique(test_names)) ~= numel(test_names)
        error('ALEV4:Phase3SuiteFailed', ...
            'Required Phase 3 suite %s contains duplicate test group names.', name);
    end
end

function answer = trueLogical(value)
    answer = islogical(value) && isscalar(value) && value;
end

function answer = passedText(value)
    answer = ischar(value) && isrow(value) && strcmp(value,'passed');
end

function answer = passedReport(value,flag)
    answer = isstruct(value) && isscalar(value) && ...
        isfield(value,'status') && passedText(value.status) && ...
        isfield(value,flag) && trueLogical(value.(flag));
end

function writeReport(destination, report)
    bytes = unicode2native(jsonencode(report), 'UTF-8');
    fid = fopen(destination, 'wb');
    if fid < 0, error('ALEV4:ReportWrite', 'Cannot open Phase 3 validation report.'); end
    cleanup = onCleanup(@() closeQuietly(fid)); %#ok<NASGU>
    count = fwrite(fid, bytes, 'uint8');
    close_status = fclose(fid);
    if count ~= numel(bytes) || close_status ~= 0
        error('ALEV4:ReportWrite', 'Incomplete Phase 3 validation report write.');
    end
end

function closeQuietly(fid)
    try
        fclose(fid);
    catch
        % Normal completion has already closed this handle.
    end
end
