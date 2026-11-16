function report = run_phase4_tests(output_dir, require_phase3)
%RUN_PHASE4_TESTS Execute structured noise and preserved numerical gates.
%   run_phase4_tests() runs all Phase 4 suites and the complete Phase 3/Phase 2/Phase 1
%   numerical/ISETCam prerequisites. Missing or failed gates raise an error.
%   run_phase4_tests(path, false) runs standalone Phase 4 suites only;
%   status is core_only and phase4_passed remains FALSE.
%
%   This report covers numerical execution. Full phase acceptance also
%   requires independent demo artifacts, repeated-process verification and
%   clean pinned dependencies, as described in the Phase 4 documentation.
    if nargin < 1
        output_dir = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
            'outputs', 'phase4', 'validation');
    end
    if nargin < 2, require_phase3 = true; end
    if ~islogical(require_phase3) || ~isscalar(require_phase3)
        error('ALEV4:InvalidSetupMode', 'require_phase3 must be a logical scalar.');
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
    report = struct('schema_version', '1.0', 'phase', 4, ...
        'runtime_version', version, 'status', 'running', ...
        'phase4_passed', false, 'calibrated_alev4', false, ...
        'phase3_required', require_phase3);
    if exist('OCTAVE_VERSION', 'builtin')
        report.runtime = 'GNU Octave';
    else
        report.runtime = 'MATLAB';
    end
    report.phase3 = struct('status', 'not_run', 'phase3_passed', false, ...
        'reason', 'Phase 3 prerequisite has not executed.');
    destination = fullfile(output_dir, 'phase4-validation.json');
    % Invalidate any previous success before setup or numerical execution.
    % If this write itself fails, the invocation fails; an old report must
    % never substitute for the current process exit status.
    writeReport(destination, report);
    try
        setup_project(require_phase3);
        report.provenance = alev4.sourceProvenance();
        functions = {'test_phase4_config', 'test_phase4_core', ...
            'test_phase4_noise', 'test_phase4_rng', 'test_phase4_sequence', ...
            'test_phase4_spatial', 'test_phase4_artifacts', ...
            'test_phase4_demo', 'test_phase4_numerical_edges'};
        fields = {'config', 'core', 'noise', 'rng', 'sequence', 'spatial', ...
            'artifact_io', 'demo_contract', 'numerical_edges'};
        for k = 1:numel(functions)
            report.(fields{k}) = feval(functions{k});
            requirePassedSuite(report.(fields{k}), fields{k});
        end
        if require_phase3
            report.phase3 = run_phase3_tests( ...
                fullfile(output_dir, 'phase3-regression'), true);
            if ~passedReport(report.phase3,'phase3_passed') || ...
                    ~isfield(report.phase3,'phase2_required') || ...
                    ~trueLogical(report.phase3.phase2_required) || ...
                    ~isfield(report.phase3,'phase2') || ...
                    ~passedReport(report.phase3.phase2,'phase2_passed') || ...
                    ~isfield(report.phase3.phase2,'phase1_required') || ...
                    ~trueLogical(report.phase3.phase2.phase1_required) || ...
                    ~isfield(report.phase3.phase2,'phase1') || ...
                    ~passedReport(report.phase3.phase2.phase1,'phase1_passed') || ...
                    ~isfield(report.phase3,'iset_spatial') || ...
                    ~isstruct(report.phase3.iset_spatial) || ...
                    ~isscalar(report.phase3.iset_spatial) || ...
                    ~isfield(report.phase3.iset_spatial,'status') || ...
                    ~passedText(report.phase3.iset_spatial.status) || ...
                    ~isfield(report.phase3.phase2.phase1,'iset') || ...
                    ~isstruct(report.phase3.phase2.phase1.iset) || ...
                    ~isscalar(report.phase3.phase2.phase1.iset) || ...
                    ~isfield(report.phase3.phase2.phase1.iset,'status') || ...
                    ~passedText(report.phase3.phase2.phase1.iset.status) || ...
                    ~isfield(report.phase3.phase2.phase1.iset,'test_count') || ...
                    ~positiveTestCount(report.phase3.phase2.phase1.iset.test_count)
                error('ALEV4:Phase3Prerequisite', ...
                    'The complete Phase 3 prerequisite did not report a pass.');
            end
            % Phase 3 ISET has the same complete group inventory as Phase 4;
            % a top-level passed status alone cannot establish its execution.
            % Phase 1 ISET retains its older status/test_count report schema.
            requirePassedSuite(report.phase3.iset_spatial, ...
                'phase3.iset_spatial', 'ALEV4:Phase3Prerequisite');
            report.status = 'passed';
            report.phase4_passed = true;
        else
            report.phase3.reason = 'Standalone Phase 4 execution explicitly requested.';
            report.status = 'core_only';
        end
    catch err
        report.status = 'failed';
        report.phase4_passed = false;
        report.error = struct('identifier', err.identifier, 'message', err.message);
        writeReport(destination, report);
        rethrow(err);
    end
    writeReport(destination, report);
    fprintf('Phase 4 numerical gates passed: %d (%s %s)\n', ...
        report.phase4_passed, report.runtime, report.runtime_version);
end

function requirePassedSuite(suite, name, identifier)
    if nargin < 3, identifier = 'ALEV4:Phase4SuiteFailed'; end
    if ~isstruct(suite) || ~isscalar(suite) || ...
            ~isfield(suite, 'status') || ~passedText(suite.status) || ...
            ~isfield(suite, 'passed') || ~trueLogical(suite.passed) || ...
            ~isfield(suite, 'test_count') || ...
            ~positiveTestCount(suite.test_count) || ...
            ~isfield(suite, 'tests') || ~isstruct(suite.tests) || ...
            numel(suite.tests) ~= suite.test_count
        error(identifier, ...
            'Required suite %s did not report a complete pass.', name);
    end
    test_names = cell(1, numel(suite.tests));
    for k = 1:numel(suite.tests)
        test = suite.tests(k);
        if ~isfield(test, 'name') || ~ischar(test.name) || ...
                ~isrow(test.name) || isempty(strtrim(test.name)) || ...
                ~isfield(test, 'status') || ~passedText(test.status) || ...
                ~isfield(test, 'passed') || ~trueLogical(test.passed)
            error(identifier, ...
                'Required suite %s contains an unpassed test.', name);
        end
        test_names{k} = test.name;
    end
    if numel(unique(test_names)) ~= numel(test_names)
        error(identifier, ...
            'Required suite %s contains duplicate test group names.', name);
    end
end

function answer = positiveTestCount(value)
    answer = isnumeric(value) && isreal(value) && isscalar(value) && ...
        isfinite(value) && value >= 1 && value == fix(value);
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
    if fid < 0, error('ALEV4:ReportWrite', 'Cannot open Phase 4 validation report.'); end
    cleanup = onCleanup(@() closeQuietly(fid)); %#ok<NASGU>
    count = fwrite(fid, bytes, 'uint8');
    close_status = fclose(fid);
    if count ~= numel(bytes) || close_status ~= 0
        error('ALEV4:ReportWrite', 'Incomplete Phase 4 validation report write.');
    end
end

function closeQuietly(fid)
    try
        fclose(fid);
    catch
        % Normal completion has already closed this handle.
    end
end
