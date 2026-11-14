function files = exportSpatialBundle(directory, result)
%EXPORTSPATIALBUNDLE Publish a verified synthetic spatial directory bundle.
%   This new format binds original/intermediate irradiance, geometry, PSF,
%   expected charge and unchanged Phase 1/2 readout files through SHA-256.
%   A fresh directory is required. Staging is verified before publication;
%   concurrent writers to one destination remain unsupported.
    if nargin~=2
        error('ALEV4:SpatialExportArguments','Directory and complete spatial result are required.');
    end
    caller_rng=rng;
    rng_guard=onCleanup(@()rng(caller_rng)); %#ok<NASGU>
    directory=alev4.spatialBundleUtil('path',directory);
    parent=fileparts(directory);
    if isempty(parent), parent='.'; end
    alev4.spatialBundleUtil('directory',parent);
    refuseExisting(directory);
    result=alev4.spatialValidateResult(result,true);
    % Validate portable wire metadata before any filesystem mutation.
    geometry=result.geometry;
    geometry.parameter_sources=alev4.spatialBundleUtil('listencode',geometry.parameter_sources,'id');
    psf=result.psf;
    if ~isempty(psf)
        psf=rmfield(psf,'kernel');
        psf.parameter_sources=alev4.spatialBundleUtil('listencode',psf.parameter_sources,'id');
    end
    meta=struct('format','ALEV4-SYNTHETIC-SPATIAL','schema_version','1.0', ...
        'algorithm_version','phase3-spatial-v1','synthetic',true, ...
        'calibrated_alev4',false,'authentic_arriraw',false, ...
        'byte_order','little-endian','array_order','plane-major-row-major', ...
        'readout_mode',result.readout_mode,'input_stage',result.input_stage, ...
        'geometry',geometry,'configuration',result.configuration, ...
        'input_grid',result.input_grid,'optical_grid',result.optical_grid, ...
        'psf',psf,'operation_order',alev4.spatialBundleUtil('listencode',result.operation_order,'step'), ...
        'spatial_provenance',result.spatial_provenance, ...
        'exposure_s',double(result.readout.exposure_s),'seed',double(result.readout.seed), ...
        'runtime',alev4.spatialBundleUtil('runtime'),'provenance',alev4.sourceProvenance(), ...
        'files',struct());
    alev4.spatialDecodeJson(alev4.encodeBundleJson(meta));
    staging=[tempname(parent) '.spatial-stage'];
    if alev4.bundlePathExists(staging)
        error('ALEV4:SpatialWriteFailed','Cannot claim an existing staging path.');
    end
    [ok,message]=mkdir(staging);
    % mkdir can report success for an existing directory. Only an unqualified
    % new creation establishes ownership for writes and recursive cleanup.
    if ~ok || ~isempty(message)
        error('ALEV4:SpatialWriteFailed','Cannot create owned staging directory: %s',message);
    end
    cleanup=onCleanup(@()removeOwned(staging)); %#ok<NASGU>
    density='photons m^-2 s^-1 nm^-1';
    meta.files.input_irradiance=writeData(staging,'input.f64',result.input_irradiance,'float64',shape3(result.input_irradiance),density);
    meta.files.optical_irradiance=writeData(staging,'optical.f64',result.optical_irradiance,'float64',shape3(result.optical_irradiance),density);
    meta.files.sampled_irradiance=writeData(staging,'sampled.f64',result.sampled_irradiance,'float64',shape3(result.sampled_irradiance),density);
    meta.files.expected_electrons=writeData(staging,'expected.f64',result.readout.expected_electrons,'float64',size(result.readout.expected_electrons),'electrons');
    if ~isempty(result.psf)
        meta.files.psf=writeData(staging,'psf.f64',result.psf.kernel,'float64',shape3(result.psf.kernel),'unitless weights');
    end
    base=fullfile(staging,'readout');
    if strcmp(result.readout_mode,'single')
        alev4.exportSyntheticRaw(result.readout,result.configuration,base);
        shape=result.configuration.image_size;
        meta.files.raw=describe(staging,'readout.raw','uint16',shape,'DN');
    else
        alev4.exportDualGainBundle(result.readout,result.configuration,base);
        shape=result.configuration.sensor.image_size;
        meta.files.high_raw=describe(staging,'readout.high.raw','uint16',shape,'DN');
        meta.files.low_raw=describe(staging,'readout.low.raw','uint16',shape,'DN');
        meta.files.merged_electrons=describe(staging,'readout.merged.f64','float64',shape,'electrons');
        meta.files.flags=describe(staging,'readout.flags.u8','uint8',shape,'bitmask');
    end
    meta.files.readout_metadata=describe(staging,'readout.json','utf8',[],'metadata');
    alev4.spatialBundleUtil('writejson',fullfile(staging,'spatial.json'),meta);
    alev4.readSpatialBundle(staging);
    refuseExisting(directory);
    [ok,message]=movefile(staging,directory);
    if ~ok, error('ALEV4:SpatialWriteFailed','Cannot publish spatial bundle: %s',message); end
    % A racing writer is unsupported, but never mistake nested movefile
    % behavior for a publication into the requested directory.
    [~,staging_name,staging_ext]=fileparts(staging);
    nested=fullfile(directory,[staging_name staging_ext]);
    if exist(nested,'dir')==7
        removeOwned(nested);
        error('ALEV4:SpatialWriteFailed','A concurrent destination caused directory nesting; owned staging was removed.');
    end
    if exist(staging,'dir')==7 || exist(fullfile(directory,'spatial.json'),'file')~=2
        error('ALEV4:SpatialWriteFailed','Publication did not produce the requested bundle directory.');
    end
    files=struct('directory',directory,'metadata',fullfile(directory,'spatial.json'));
end

function descriptor=writeData(directory,name,data,type,shape,units)
    alev4.spatialBundleUtil('shape',shape,numel(shape));
    if strcmp(type,'float64'), precision='double'; else, precision=type; end
    alev4.spatialBundleUtil('writeplane',fullfile(directory,name),data,precision);
    descriptor=describe(directory,name,type,shape,units);
end

function descriptor=describe(directory,name,type,shape,units)
    if strcmp(type,'utf8'), bound=2000000; else, bound=800000000; end
    [digest,count]=alev4.spatialBundleUtil('hash',fullfile(directory,name),bound);
    descriptor=struct('name',name,'sha256',digest,'byte_count',double(count), ...
        'sample_type',type,'shape',double(shape),'units',units);
end

function shape=shape3(value)
    shape=[size(value,1) size(value,2) size(value,3)];
end

function refuseExisting(path)
    if alev4.bundlePathExists(path)
        error('ALEV4:SpatialAlreadyExists','Refusing to overwrite an existing spatial bundle path.');
    end
end

function removeOwned(path)
    if exist(path,'dir')==7
        [ok,message]=rmdir(path,'s');
        if ~ok
            warning('ALEV4:SpatialCleanupFailed','Owned staging cleanup failed: %s',message);
        end
    end
end
