function report=test_phase3_staging_ownership()
%TEST_PHASE3_STAGING_OWNERSHIP Preserve unowned paths on staging collisions.
%   Only test-owned temporary paths are created or removed.
    caller_rng=rng; rng_guard=onCleanup(@()rng(caller_rng)); %#ok<NASGU>
    folder=tempname(); [ok,msg]=mkdir(folder); assert(ok && isempty(msg));
    folder_guard=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
    result=fixture();
    shadow=fullfile(folder,'shadow'); assert(mkdir(shadow));
    global alev4_test_stage_parent alev4_test_stage_base alev4_test_stage_inject_mkdir alev4_test_stage_original_mkdir alev4_test_stage_temp_counter;
    alev4_test_stage_parent=folder; alev4_test_stage_base=fullfile(folder,'unused-stage-base');
    alev4_test_stage_inject_mkdir=false; alev4_test_stage_original_mkdir=@mkdir; alev4_test_stage_temp_counter=0;
    staging=[alev4_test_stage_base '.spatial-stage'];
    writeBytes(fullfile(shadow,'tempname.m'),uint8(sprintf([ ...
        'function name=tempname(varargin)\n' ...
        'global alev4_test_stage_parent alev4_test_stage_base alev4_test_stage_temp_counter;\n' ...
        'if nargin>=1 && strcmp(varargin{1},alev4_test_stage_parent)\n' ...
        'name=alev4_test_stage_base;\nelse\n' ...
        'if nargin>=1, parent=varargin{1}; else, parent=alev4_test_stage_parent; end\n' ...
        'while true\nalev4_test_stage_temp_counter=alev4_test_stage_temp_counter+1;\n' ...
        'name=fullfile(parent,sprintf(''phase3-owned-test-%%d'',alev4_test_stage_temp_counter));\n' ...
        'if ~alev4.bundlePathExists(name), break; end\nend\nend\nend\n'])));
    writeBytes(fullfile(shadow,'mkdir.m'),uint8(sprintf([ ...
        'function [ok,message,messageid]=mkdir(varargin)\n' ...
        'global alev4_test_stage_base alev4_test_stage_inject_mkdir alev4_test_stage_original_mkdir alev4_test_stage_temp_counter;\n' ...
        '[ok,message,messageid]=alev4_test_stage_original_mkdir(varargin{:});\n' ...
        'if alev4_test_stage_inject_mkdir && nargin==1 && strcmp(varargin{1},[alev4_test_stage_base ''.spatial-stage''])\n' ...
        'assert(ok); fid=fopen(fullfile(varargin{1},''sentinel''),''wb''); assert(fid>=0);\n' ...
        'fprintf(fid,''created outside exporter ownership''); assert(fclose(fid)==0);\n' ...
        'message=''directory exists''; messageid=''mkdir'';\nend\nend\n'])));
    previous_path=path; path_guard=onCleanup(@()restorePath(previous_path));
    previous_warning=warning('query','all'); warning_guard=onCleanup(@()warning(previous_warning)); %#ok<NASGU>
    warning('off','Octave:shadowed-function'); addpath(shadow,'-begin'); clear tempname mkdir;
    assert(strcmp(which('tempname'),fullfile(shadow,'tempname.m')));
    assert(strcmp(which('mkdir'),fullfile(shadow,'mkdir.m')));
    rng(6333,'twister'); before_rng=rng; before_handles=fopen('all');
    cases={};
    for kind={'directory','file','symlink','dangling'}
        assert(~alev4.bundlePathExists(staging));
        assert(~alev4.bundlePathExists(alev4_test_stage_base));
        switch kind{1}
            case 'directory'
                assert(mkdir(staging)); writeBytes(fullfile(staging,'sentinel'),uint8('preserve directory'));
                writeBytes(fullfile(staging,'input.f64'),uint8('preserve existing payload'));
            case 'file'
                writeBytes(staging,uint8('preserve file'));
            case 'symlink'
                outside=fullfile(folder,'outside'); assert(mkdir(outside));
                writeBytes(fullfile(outside,'sentinel'),uint8('preserve linked directory'));
                makeSymlink(outside,staging);
            case 'dangling'
                makeSymlink(fullfile(folder,'absent'),staging);
        end
        assert(alev4.bundlePathExists(staging));
        destination=fullfile(folder,['target-' kind{1}]);
        err=captureError(@()alev4.exportSpatialBundle(destination,result));
        assert(strcmp(err.identifier,'ALEV4:SpatialWriteFailed'));
        assert(alev4.bundlePathExists(staging));
        assert(~alev4.bundlePathExists(destination));
        assert(isequal(rng,before_rng) && isequal(fopen('all'),before_handles));
        switch kind{1}
            case 'directory'
                assert(strcmp(fileread(fullfile(staging,'sentinel')),'preserve directory'));
                assert(strcmp(fileread(fullfile(staging,'input.f64')),'preserve existing payload'));
                assert(numel(dir(staging))==4); assert(rmdir(staging,'s'));
            case 'file'
                assert(strcmp(fileread(staging),'preserve file')); delete(staging);
            case 'symlink'
                assert(strcmp(fileread(fullfile(outside,'sentinel')),'preserve linked directory'));
                assert(isSymlink(staging));
                removeLink(staging);
            case 'dangling'
                assert(isSymlink(staging)); removeLink(staging);
        end
        cases{end+1}=['preserve_preexisting_stage_' kind{1}];
    end
    alev4_test_stage_inject_mkdir=true;
    destination=fullfile(folder,'target-mkdir-message');
    err=captureError(@()alev4.exportSpatialBundle(destination,result));
    assert(strcmp(err.identifier,'ALEV4:SpatialWriteFailed'));
    assert(strcmp(fileread(fullfile(staging,'sentinel')),'created outside exporter ownership'));
    assert(numel(dir(staging))==3 && ~alev4.bundlePathExists(destination));
    assert(isequal(rng,before_rng) && isequal(fopen('all'),before_handles));
    alev4_test_stage_inject_mkdir=false; assert(rmdir(staging,'s'));
    cases{end+1}='preserve_stage_after_mkdir_success_with_message';

    destination=fullfile(folder,'normal-publication');
    files=alev4.exportSpatialBundle(destination,result);
    decoded=alev4.readSpatialBundle(files.directory);
    assert(isequal(decoded.readout.raw_dn,result.readout.raw_dn));
    assert(isequal(decoded.sampled_irradiance,result.sampled_irradiance));
    assert(~alev4.bundlePathExists(staging));
    assert(isequal(rng,before_rng) && isequal(fopen('all'),before_handles));
    cases{end+1}='normal_export_read_control';
    report=struct('runtime_version',version,'status','passed','passed',true,'test_count',numel(cases), ...
        'tests',{cases},'rng_preserved',true,'handles_preserved',true);
    clear path_guard;
end

function result=fixture()
    geometry=alev4.createSensorGeometry(struct('full_grid_size',[2 3],'pixel_pitch_m',1));
    grid=alev4.createSpatialGrid(struct('x_edges_m',0:3,'y_edges_m',0:2));
    cfg=alev4.createBaselineSensor(struct('image_size',[2 3],'pixel_pitch_m',1, ...
        'wavelength_nm',550,'bin_width_nm',1,'qe',[1 1 1],'shot_noise',false,'read_noise_e',0));
    result=alev4.simulateSpatialExposure([1 2 3;4 5 6],grid,geometry,cfg,1,33,struct('input_stage','post_optics'));
end

function writeBytes(path,bytes)
    fid=fopen(path,'wb'); assert(fid>=0); assert(fwrite(fid,bytes,'uint8')==numel(bytes)); assert(fclose(fid)==0);
end

function err=captureError(action)
    err=struct('identifier','','message','');
    try, action(); catch observed, err.identifier=observed.identifier; err.message=observed.message; end
end

function restorePath(previous)
    path(previous); clear tempname mkdir;
    clear global alev4_test_stage_parent alev4_test_stage_base alev4_test_stage_inject_mkdir alev4_test_stage_original_mkdir alev4_test_stage_temp_counter;
end

function makeSymlink(target,destination)
    if exist('symlink','builtin') || exist('symlink','file')
        [status,message]=symlink(target,destination); assert(status==0,message);
    elseif (exist('usejava','builtin') || exist('usejava','file')) && usejava('jvm')
        from=javaObject('java.io.File',target); to=javaObject('java.io.File',destination);
        attributes=javaArray('java.nio.file.attribute.FileAttribute',0);
        javaMethod('createSymbolicLink','java.nio.file.Files',to.toPath(),from.toPath(),attributes);
    else
        error('ALEV4:TestFilesystemCapability','Staging symlink tests need native symlink or Java NIO.');
    end
end

function answer=isSymlink(path)
    if exist('lstat','builtin') || exist('lstat','file')
        [info,status]=lstat(path); answer=status==0 && info.modestr(1)=='l';
    else
        file=javaObject('java.io.File',path);
        answer=javaMethod('isSymbolicLink','java.nio.file.Files',file.toPath());
    end
end

function removeLink(path)
    if exist('unlink','builtin') || exist('unlink','file')
        [status,message]=unlink(path); assert(status==0,message);
    else
        file=javaObject('java.io.File',path); javaMethod('delete','java.nio.file.Files',file.toPath());
    end
end
