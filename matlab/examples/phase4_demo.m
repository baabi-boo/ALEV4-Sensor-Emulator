function summary = phase4_demo(output_dir)
%PHASE4_DEMO Export and read back the 24 fixed structured-noise fixtures.
%   Call setup_project(false) first. OUTPUT_DIR must be a fresh named path.
%   Existing paths, symbolic-link ancestors and dot-segment aliases reject.
%   Missing ordinary parent directories may be created. Only exclusively
%   owned staging is cleaned on failure; existing artifacts are untouched.
%
%   The staging summary starts incomplete, so a failed attempt cannot reuse
%   stale successful status. Completion is written only after all 24 actual
%   exports and native readbacks succeed. This reports demo completion, not
%   Phase 4 release acceptance or measured sensor calibration. Generation
%   alone remains available independently through alev4.phase4Fixtures().
    if nargin > 1
        error('ALEV4:Phase4DemoArguments','Only an optional output directory is accepted.');
    end
    if nargin < 1
        output_dir = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), ...
            'outputs','phase4','demo');
    end
    caller_rng = rng;
    rng_guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    output_dir = destinationPath(output_dir);
    refuseExisting(output_dir);
    parent = fileparts(output_dir);
    validateParents(parent,false);
    if isempty(which('alev4.exportStructuredBundle')) || ...
            isempty(which('alev4.readStructuredBundle'))
        error('ALEV4:Phase4StructuredIoMissing', ...
            ['Phase 4 exportStructuredBundle and readStructuredBundle are required. ' ...
             'Use alev4.phase4Fixtures() for generation-only development checks.']);
    end
    inventory = alev4.phase4Fixtures();
    validateParents(parent,true);
    refuseExisting(output_dir);
    staging = [tempname(parent) '.phase4-demo-stage'];
    if alev4.bundlePathExists(staging)
        error('ALEV4:Phase4DemoWrite','Cannot claim an existing staging path.');
    end
    [ok,message] = mkdir(staging);
    % mkdir reports success for an existing directory in both runtimes.
    % Ownership requires an unqualified new creation, never just ok=true.
    if ~ok || ~isempty(message)
        error('ALEV4:Phase4DemoWrite','Cannot create owned staging: %s',message);
    end
    identity = directoryIdentity(staging);
    stage_guard = onCleanup(@() removeOwned(staging,identity)); %#ok<NASGU>
    summary = rmfield(inventory,{'results','fixtures'});
    summary.frames = inventory.fixtures;
    for k = 1:summary.frame_count
        summary.frames(k).export_complete = false;
        summary.frames(k).readback_verified = false;
    end
    summary.status = 'in_progress';
    summary.demo_complete = false;
    summary.export_readback_complete = false;
    summary.exported_frame_count = 0;
    summary.verified_frame_count = 0;
    summary.calibrated = false;
    summary.release_accepted = false;
    summary.completion_scope = 'all_24_fixture_exports_and_native_readbacks';
    summary_path = fullfile(staging,'phase4-demo-summary.json');
    writeSummary(summary_path,summary);
    for k = 1:summary.frame_count
        frame_dir = fullfile(staging,summary.frames(k).bundle_dir);
        alev4.exportStructuredBundle(inventory.results{k},frame_dir);
        summary.frames(k).export_complete = true;
        summary.exported_frame_count = summary.exported_frame_count+1;
        decoded = alev4.readStructuredBundle(frame_dir);
        verifyReadback(decoded,inventory.results{k},summary.frames(k).name);
        summary.frames(k).readback_verified = true;
        summary.verified_frame_count = summary.verified_frame_count+1;
    end
    if summary.exported_frame_count ~= 24 || summary.verified_frame_count ~= 24
        error('ALEV4:Phase4DemoIncomplete','All 24 exports and readbacks must execute.');
    end
    summary.status = 'complete';
    summary.demo_complete = true;
    summary.export_readback_complete = true;
    writeSummary(summary_path,summary);
    validateParents(parent,false);
    refuseExisting(output_dir);
    [ok,message] = movefile(staging,output_dir);
    if ~ok
        error('ALEV4:Phase4DemoWrite','Cannot publish demo directory: %s',message);
    end
    % A racing destination can make movefile nest the stage. Delete only the
    % directory whose observed identity is the one this call actually owns.
    [~,stem,ext] = fileparts(staging);
    nested = fullfile(output_dir,[stem ext]);
    if alev4.bundlePathExists(nested)
        removeOwned(nested,identity);
        error('ALEV4:Phase4DemoWrite','A concurrent destination caused nested publication.');
    end
    try
        if ~isequal(directoryIdentity(output_dir),identity) || ...
                alev4.bundlePathExists(staging)
            error('ALEV4:Phase4DemoWrite','Publication did not preserve the owned directory.');
        end
        verifySummaryFile(fullfile(output_dir,'phase4-demo-summary.json'),summary);
    catch observed
        removeOwned(output_dir,identity);
        rethrow(observed);
    end
    fprintf('Phase 4 demo exported and read back all %d synthetic frames; complete=1.\n', ...
        summary.frame_count);
end

function path = destinationPath(path)
    if ~ischar(path) || ~isrow(path) || isempty(path) || ...
            any(path==char(0) | path==char(10) | path==char(13))
        error('ALEV4:InvalidOutputPath','Output must be a nonempty character path.');
    end
    pieces = regexp(path,'[\\/]','split');
    if any(strcmp(pieces,'.') | strcmp(pieces,'..')) || ...
            any(cellfun(@isempty,pieces(2:end)))
        error('ALEV4:Phase4DemoAliasedPath','Dot segments and repeated/trailing separators reject.');
    end
    absolute = path(1)==filesep || ~isempty(regexp(path,'^[A-Za-z]:[\\/]','once'));
    if ~absolute, path = fullfile(pwd,path); end
    [~,stem,ext] = fileparts(path);
    if isempty([stem ext])
        error('ALEV4:InvalidOutputPath','A named demo directory is required.');
    end
end

function validateParents(parent,create_missing)
    ancestors = {parent};
    while true
        next = fileparts(ancestors{end});
        if isempty(next) || strcmp(next,ancestors{end}), break; end
        ancestors{end+1} = next; %#ok<AGROW>
    end
    for k = numel(ancestors):-1:1
        path = ancestors{k};
        if alev4.bundlePathExists(path)
            alev4.spatialBundleUtil('directory',path);
        elseif create_missing
            [ok,message] = mkdir(path);
            if ~ok || ~isempty(message)
                error('ALEV4:Phase4DemoWrite','Cannot create ordinary parent directory: %s',message);
            end
            alev4.spatialBundleUtil('directory',path);
        end
    end
end

function refuseExisting(path)
    if alev4.bundlePathExists(path)
        error('ALEV4:OutputExists','Phase 4 demo refuses an existing output path.');
    end
end

function identity = directoryIdentity(path)
    alev4.spatialBundleUtil('directory',path);
    if exist('lstat','builtin') || exist('lstat','file')
        [info,status] = lstat(path);
        if status~=0 || isempty(info.modestr) || info.modestr(1)~='d'
            error('ALEV4:Phase4DemoIdentity','Cannot observe an ordinary directory identity.');
        end
        identity = struct('kind','lstat','device',info.dev,'inode',info.ino);
    elseif (exist('usejava','builtin') || exist('usejava','file')) && usejava('jvm')
        file = javaObject('java.io.File',path);
        options = javaArray('java.nio.file.LinkOption',1);
        options(1) = javaMethod('valueOf','java.nio.file.LinkOption','NOFOLLOW_LINKS');
        attributes = javaMethod('readAttributes','java.nio.file.Files',file.toPath(), ...
            'basic:fileKey',options);
        key = attributes.get('fileKey');
        if isempty(key)
            error('ALEV4:Phase4DemoIdentity','Filesystem does not expose a stable directory identity.');
        end
        identity = struct('kind','java_file_key','key',char(key.toString()));
    else
        error('ALEV4:Phase4DemoIdentity','Directory ownership requires lstat or a JVM file key.');
    end
end

function removeOwned(path,identity)
    if ~alev4.bundlePathExists(path), return; end
    try
        if ~isequal(directoryIdentity(path),identity)
            warning('ALEV4:Phase4DemoCleanup','Changed directory identity; leaving the unowned path intact.');
            return;
        end
        [ok,message] = rmdir(path,'s');
        if ~ok
            warning('ALEV4:Phase4DemoCleanup','Owned staging cleanup failed: %s',message);
        end
    catch observed
        warning('ALEV4:Phase4DemoCleanup','Owned staging cleanup could not proceed: %s',observed.message);
    end
end

function verifyReadback(decoded,expected,name)
% The new format retains analog/component history as well as observed RAW.
% Extra reader metadata is allowed, but no original result field may be lost.
    if ~isstruct(decoded) || ~isscalar(decoded)
        error('ALEV4:Phase4DemoReadback','Reader did not return a structured result for %s.',name);
    end
    fields = fieldnames(expected);
    for k = 1:numel(fields)
        field = fields{k};
        if ~isfield(decoded,field) || ~isequal(decoded.(field),expected.(field))
            error('ALEV4:Phase4DemoReadback', ...
                'Readback differs from generated fixture %s in field %s.',name,field);
        end
    end
end

function writeSummary(path,summary)
    text = [summaryJson(summary) sprintf('\n')];
    bytes = unicode2native(text,'UTF-8');
    if numel(bytes)>2000000
        error('ALEV4:Phase4DemoSummary','Demo summary exceeds 2,000,000 bytes.');
    end
    if alev4.bundlePathExists(path), alev4.spatialBundleUtil('regular',path); end
    [fid,message] = fopen(path,'wb');
    if fid<0, error('ALEV4:Phase4DemoSummary','Cannot write summary: %s',message); end
    guard = onCleanup(@() closeQuietly(fid)); %#ok<NASGU>
    count = fwrite(fid,bytes,'uint8');
    status = fclose(fid);
    if count~=numel(bytes) || status~=0
        error('ALEV4:Phase4DemoSummary','Incomplete demo summary write.');
    end
    verifySummaryFile(path,summary);
end

function verifySummaryFile(path,summary)
    alev4.spatialBundleUtil('regular',path);
    expected = unicode2native([summaryJson(summary) sprintf('\n')],'UTF-8');
    [fid,message] = fopen(path,'rb');
    if fid<0, error('ALEV4:Phase4DemoSummary','Cannot read summary: %s',message); end
    guard = onCleanup(@() closeQuietly(fid)); %#ok<NASGU>
    actual = fread(fid,numel(expected)+1,'*uint8');
    [message,status] = ferror(fid);
    if status~=0 || ~isequal(actual(:),expected(:))
        error('ALEV4:Phase4DemoSummary','Summary bytes failed readback: %s',message);
    end
end

function text = summaryJson(value)
% Preserve binary64 numbers while allowing the summary's lists of records.
% Primitive numeric/text encoding uses the preserved bounded bundle encoder.
    if isstruct(value)
        if ~isscalar(value)
            parts = cell(1,numel(value));
            for k = 1:numel(value), parts{k} = summaryJson(value(k)); end
            text = ['[' strjoin(parts,',') ']'];
        else
            fields = fieldnames(value); parts = cell(1,numel(fields));
            for k = 1:numel(fields)
                parts{k} = [jsonencode(fields{k}) ':' summaryJson(value.(fields{k}))];
            end
            text = ['{' strjoin(parts,',') '}'];
        end
    elseif iscell(value)
        if ~isempty(value) && ~isvector(value)
            error('ALEV4:Phase4DemoSummary','Summary cell lists must be vectors.');
        end
        parts = cell(1,numel(value));
        for k = 1:numel(value), parts{k} = summaryJson(value{k}); end
        text = ['[' strjoin(parts,',') ']'];
    else
        text = alev4.encodeBundleJson(value);
    end
end

function closeQuietly(fid)
    try, fclose(fid); catch, end
end
