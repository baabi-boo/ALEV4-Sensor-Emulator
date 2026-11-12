function report = test_provenance()
%TEST_PROVENANCE Exercise file-only Git observation using isolated fixtures.
%   Fixture SHAs are deliberately synthetic metadata, not Git objects. This
%   tests observation semantics only; checkout integrity is a separate gate.
    root = tempname;
    assert(exist(root, 'file') == 0, 'Temporary provenance fixture path exists.');
    [ok, message] = mkdir(root);
    assert(ok, message);
    marker = fullfile(root, 'alev4-provenance-test-marker');
    writeText(marker, 'owned temporary provenance fixtures');
    cleanup = onCleanup(@() cleanupRoot(root, marker)); %#ok<NASGU>
    sha_a = repmat('a', 1, 40);
    sha_b = repmat('b', 1, 40);
    sha_c = repmat('c', 1, 40);
    sha_d = repmat('d', 1, 40);

    p = alev4.sourceProvenance(fullfile(root, 'absent'));
    assert(isempty(p.repository_head) && isempty(p.isetcam_head) && isempty(p.isethdrsensor_head), ...
        'Absent metadata must be represented as unknown.');
    assert(~isempty(p.meaning), 'Provenance interpretation must be explicit.');

    ordinary = fullfile(root, 'ordinary');
    writeText(fullfile(ordinary, '.git', 'HEAD'), sprintf('ref: refs/heads/main\n'));
    writeText(fullfile(ordinary, '.git', 'refs', 'heads', 'main'), [sha_a sprintf('\n')]);
    p = alev4.sourceProvenance(ordinary);
    assert(strcmp(p.repository_head, sha_a), 'Loose branch ref was not observed.');

    % Submodule metadata may be a relative gitdir pointer or a .git folder.
    sub_a = fullfile(ordinary, 'third_party', 'isetcam');
    writeText(fullfile(sub_a, '.git'), ...
        sprintf('gitdir: ../../.git/modules/third_party/isetcam\n'));
    writeText(fullfile(ordinary, '.git', 'modules', 'third_party', 'isetcam', 'HEAD'), ...
        [sha_b sprintf('\n')]);
    writeText(fullfile(ordinary, 'third_party', 'isethdrsensor', '.git', 'HEAD'), ...
        [sha_c sprintf('\n')]);
    p = alev4.sourceProvenance(ordinary);
    assert(strcmp(p.isetcam_head, sha_b) && strcmp(p.isethdrsensor_head, sha_c), ...
        'Detached dependency HEAD observations are incorrect.');

    delete(fullfile(ordinary, '.git', 'refs', 'heads', 'main'));
    writeText(fullfile(ordinary, '.git', 'packed-refs'), ...
        sprintf('# pack-refs with: peeled fully-peeled sorted\n%s refs/heads/main\n%s refs/tags/v1\n^%s\n', ...
        sha_a, sha_c, sha_b));
    p = alev4.sourceProvenance(ordinary);
    assert(strcmp(p.repository_head, sha_a), 'Packed branch ref was not observed.');

    % A linked worktree's HEAD is local, but its branch refs are shared.
    linked = fullfile(root, 'linked');
    common = fullfile(root, 'shared.git');
    local = fullfile(common, 'worktrees', 'example');
    writeText(fullfile(linked, '.git'), sprintf('gitdir: ../shared.git/worktrees/example\n'));
    writeText(fullfile(local, 'HEAD'), sprintf('ref: refs/heads/feature\n'));
    writeText(fullfile(local, 'commondir'), sprintf('../..\n'));
    writeText(fullfile(common, 'refs', 'heads', 'feature'), [sha_d sprintf('\n')]);
    p = alev4.sourceProvenance(linked);
    assert(strcmp(p.repository_head, sha_d), 'Linked worktree shared loose ref was not observed.');
    delete(fullfile(common, 'refs', 'heads', 'feature'));
    writeText(fullfile(common, 'packed-refs'), sprintf('%s refs/heads/feature\n', sha_d));
    p = alev4.sourceProvenance(linked);
    assert(strcmp(p.repository_head, sha_d), 'Linked worktree shared packed ref was not observed.');
    writeText(fullfile(local, 'HEAD'), sprintf('ref: refs/worktree/local\n'));
    writeText(fullfile(local, 'refs', 'worktree', 'local'), [sha_b sprintf('\n')]);
    p = alev4.sourceProvenance(linked);
    assert(strcmp(p.repository_head, sha_b), 'Per-worktree ref namespace was not kept local.');

    % Symbolic chains resolve; cycles and malformed refs never guess a SHA.
    writeText(fullfile(ordinary, '.git', 'HEAD'), sprintf('ref: refs/heads/alias\n'));
    writeText(fullfile(ordinary, '.git', 'refs', 'heads', 'alias'), sprintf('ref: refs/heads/main\n'));
    p = alev4.sourceProvenance(ordinary);
    assert(strcmp(p.repository_head, sha_a), 'Symbolic ref chain did not resolve.');
    writeText(fullfile(ordinary, '.git', 'refs', 'heads', 'main'), sprintf('ref: refs/heads/alias\n'));
    p = alev4.sourceProvenance(ordinary);
    assert(isempty(p.repository_head), 'Cyclic refs must remain unavailable.');

    invalid_heads = {'not-a-sha', 'ref: refs/../../outside', 'ref: refs//heads/main'};
    for k = 1:numel(invalid_heads)
        writeText(fullfile(ordinary, '.git', 'HEAD'), invalid_heads{k});
        p = alev4.sourceProvenance(ordinary);
        assert(isempty(p.repository_head), 'Malformed ref must remain unavailable.');
    end
    writeText(fullfile(linked, '.git'), 'not a gitdir pointer');
    p = alev4.sourceProvenance(linked);
    assert(isempty(p.repository_head), 'Malformed gitdir pointer must remain unavailable.');
    rejected = false;
    try
        alev4.sourceProvenance(42);
    catch err
        rejected = strcmp(err.identifier, 'ALEV4:InvalidProvenanceRoot');
    end
    assert(rejected, 'Invalid root type was not rejected.');

    tests = {'missing_metadata', 'loose_branch', 'detached_submodules', ...
        'packed_refs', 'linked_worktree_commondir', 'symbolic_chains_and_cycles', ...
        'invalid_roots_and_metadata'};
    report = struct('suite', 'provenance', 'passed', true, ...
        'test_count', numel(tests), 'tests', {tests});
    fprintf('PASS: Git provenance, %d test groups.\n', numel(tests));
end

function writeText(path, value)
    parent = fileparts(path);
    if exist(parent, 'dir') ~= 7
        [ok, message] = mkdir(parent);
        assert(ok, message);
    end
    fid = fopen(path, 'wb');
    assert(fid >= 0, 'Cannot write test metadata.');
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    assert(fwrite(fid, value, 'char') == numel(value), 'Short test metadata write.');
end

function cleanupRoot(root, marker)
    if exist(root, 'dir') == 7 && exist(marker, 'file') == 2
        rmdir(root, 's');
    end
end
