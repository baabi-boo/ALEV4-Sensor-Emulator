function provenance = sourceProvenance(root)
%SOURCEPROVENANCE Observe repository and dependency Git HEADs without a shell.
%   P = alev4.sourceProvenance() inspects this project's Git metadata.
%   P = alev4.sourceProvenance(ROOT) supports alternate checkouts and isolated
%   metadata tests. Ordinary repositories, submodule gitdir files, detached
%   HEADs, loose/packed refs and linked-worktree commondir files are supported.
%
%   Empty SHA fields mean unavailable or unsupported metadata, never a
%   guessed revision. These observations do NOT verify a clean worktree,
%   object existence, or equality with committed dependency gitlinks. The
%   separate verify_submodules.py acceptance gate performs checkout checks.
%   This helper supports the SHA-1 repositories used by this project.
    if nargin < 1
        root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    end
    if ~ischar(root) || isempty(root) || size(root, 1) ~= 1 || any(root == char(0))
        error('ALEV4:InvalidProvenanceRoot', 'Root must be a nonempty character row path.');
    end
    provenance = struct( ...
        'repository_head', observedHead(root), ...
        'isetcam_head', observedHead(fullfile(root, 'third_party', 'isetcam')), ...
        'isethdrsensor_head', observedHead(fullfile(root, 'third_party', 'isethdrsensor')), ...
        'meaning', ['Observed Git HEADs; an empty value means unavailable. ' ...
            'Uncommitted edits, object existence and agreement with dependency gitlinks ' ...
            'are not established by these metadata observations.']);
end

function sha = observedHead(root)
    sha = '';
    git_dir = fullfile(root, '.git');
    try
        if exist(git_dir, 'file') == 2
            pointer = strtrim(readMetadata(git_dir));
            if numel(pointer) < 8 || ~strcmp(pointer(1:8), 'gitdir: ')
                return;
            end
            target = strtrim(pointer(9:end));
            if ~validPathText(target), return; end
            git_dir = resolvePath(root, target);
        elseif exist(git_dir, 'dir') ~= 7
            return;
        end
        common_dir = git_dir;
        common_file = fullfile(git_dir, 'commondir');
        if exist(common_file, 'file') == 2
            target = strtrim(readMetadata(common_file));
            if ~validPathText(target), return; end
            common_dir = resolvePath(git_dir, target);
            if exist(common_dir, 'dir') ~= 7, return; end
        end
        value = strtrim(readMetadata(fullfile(git_dir, 'HEAD')));
        % Bound symbolic-ref traversal; malformed/cyclic refs are unavailable.
        for depth = 1:8
            if isSha(value)
                sha = value;
                return;
            end
            token = regexp(value, '^ref: (refs/[A-Za-z0-9_./-]+)$', 'tokens', 'once');
            if isempty(token) || ~isempty(strfind(token{1}, '..')) || ...
                    ~isempty(strfind(token{1}, '//')) %#ok<STREMP>
                return;
            end
            ref = token{1};
            ref_root = common_dir;
            % Git keeps these namespaces per-worktree rather than shared.
            local_prefixes = {'refs/bisect/', 'refs/worktree/', 'refs/rewritten/'};
            for k = 1:numel(local_prefixes)
                if strncmp(ref, local_prefixes{k}, numel(local_prefixes{k}))
                    ref_root = git_dir;
                end
            end
            ref_file = fullfile(ref_root, strrep(ref, '/', filesep));
            if exist(ref_file, 'file') == 2
                value = strtrim(readMetadata(ref_file));
            else
                value = packedRef(fullfile(ref_root, 'packed-refs'), ref);
                if isempty(value), return; end
            end
        end
    catch
        % Missing, unreadable or malformed metadata has an explicit unknown
        % representation. Do not invent a revision or invoke Git implicitly.
        sha = '';
    end
end

function value = packedRef(path, ref)
    value = '';
    if exist(path, 'file') ~= 2, return; end
    lines = regexp(readMetadata(path), '\r?\n', 'split');
    for k = 1:numel(lines)
        record = regexp(lines{k}, '^([0-9a-f]{40}) (refs/\S+)$', 'tokens', 'once');
        if ~isempty(record) && strcmp(record{2}, ref)
            value = record{1};
            return;
        end
    end
end

function answer = isSha(value)
    answer = ~isempty(regexp(value, '^[0-9a-f]{40}$', 'once'));
end

function answer = validPathText(value)
    answer = ~isempty(value) && size(value, 1) == 1 && ...
        ~any(value == char(0) | value == char(10) | value == char(13));
end

function path = resolvePath(base, target)
    if target(1) == '/' || target(1) == '\' || ...
            (numel(target) >= 3 && target(2) == ':' && ...
            (target(3) == '/' || target(3) == '\'))
        path = target;
    else
        path = fullfile(base, target);
    end
end

function value = readMetadata(path)
% Bound local metadata reads, including packed-refs, before allocation.
    fid = fopen(path, 'rb');
    if fid < 0, error('ALEV4:UnreadableGitMetadata', 'Cannot read Git metadata.'); end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    limit = 8 * 1024 * 1024;
    bytes = fread(fid, limit + 1, '*uint8');
    if numel(bytes) > limit
        error('ALEV4:OversizedGitMetadata', 'Git metadata exceeds the observation limit.');
    end
    value = char(bytes(:).');
end
