function [decoded, meta] = readSpatialBundle(directory)
%READSPATIALBUNDLE Validate bytes, provenance and spatial/spectral association.
%   Reads ALEV4-SYNTHETIC-SPATIAL 1.0 only. Original/intermediate arrays are
%   recomputed under the documented model. Noisy analog history is not inferred
%   from RAW and no noiseless expectation is used to improve a dual-gain merge.
    if nargin~=1
        error('ALEV4:InvalidSpatialPath','Exactly one spatial bundle directory is required.');
    end
    caller_rng=rng;
    rng_guard=onCleanup(@()rng(caller_rng)); %#ok<NASGU>
    directory=alev4.spatialBundleUtil('path',directory);
    alev4.spatialBundleUtil('directory',directory);
    manifest=fullfile(directory,'spatial.json');
    [meta,kinds]=alev4.spatialBundleUtil('readjson',manifest);
    names={'format','schema_version','algorithm_version','synthetic','calibrated_alev4', ...
        'authentic_arriraw','byte_order','array_order','readout_mode','input_stage', ...
        'geometry','configuration','input_grid','optical_grid','psf','operation_order', ...
        'spatial_provenance','exposure_s','seed','runtime','provenance','files'};
    alev4.spatialBundleUtil('fields',meta,names,'spatial manifest');
    requireWireKinds(kinds,{'exposure_s','seed'},{'number'},'manifest scalars');
    alev4.spatialBundleUtil('text',meta.format,'ALEV4-SYNTHETIC-SPATIAL','format');
    alev4.spatialBundleUtil('text',meta.schema_version,'1.0','schema_version');
    alev4.spatialBundleUtil('text',meta.algorithm_version,'phase3-spatial-v1','algorithm_version');
    alev4.spatialBundleUtil('text',meta.byte_order,'little-endian','byte_order');
    alev4.spatialBundleUtil('text',meta.array_order,'plane-major-row-major','array_order');
    alev4.spatialBundleUtil('boolean',meta.synthetic,true,'synthetic');
    alev4.spatialBundleUtil('boolean',meta.calibrated_alev4,false,'calibrated_alev4');
    alev4.spatialBundleUtil('boolean',meta.authentic_arriraw,false,'authentic_arriraw');
    alev4.spatialBundleUtil('scalar',meta.exposure_s,0,realmax,false,'exposure_s');
    alev4.spatialBundleUtil('scalar',meta.seed,0,2^32-1,true,'seed');
    validateIdentity(meta.runtime,meta.provenance);
    alev4.spatialBundleUtil('fields',meta.geometry,fieldnames(alev4.createSensorGeometry()),'geometry');
    requireWireKinds(kinds.geometry,{'pixel_pitch_m'},{'number'},'geometry pixel pitch');
    requireWireKinds(kinds.geometry,{'full_grid_size','active_roi','origin_xy_m'}, ...
        {'vector'},'geometry vectors');
    geometry=meta.geometry;
    geometry.parameter_sources=alev4.spatialBundleUtil('listdecode',geometry.parameter_sources,'id');
    geometry=alev4.createSensorGeometry(geometry);
    configuration=normalizeConfiguration(meta.configuration);
    validateConfigurationKinds(meta.configuration,kinds.configuration);
    configuration=alev4.bindSensorGeometry(configuration,geometry,'validate');
    if strcmp(configuration.schema_version,'2.0')
        mode='dual'; sensor=configuration.sensor;
    else
        mode='single'; sensor=configuration;
    end
    alev4.spatialBundleUtil('text',meta.readout_mode,mode,'readout_mode');
    alev4.spatialBundleUtil('fields',meta.input_grid,fieldnames(alev4.createSpatialGrid()),'input_grid');
    alev4.spatialBundleUtil('fields',meta.optical_grid,fieldnames(alev4.createSpatialGrid()),'optical_grid');
    requireWireKinds(kinds.input_grid,{'x_edges_m','y_edges_m'},{'vector'},'input grid axes');
    requireWireKinds(kinds.optical_grid,{'x_edges_m','y_edges_m'},{'vector'},'optical grid axes');
    input_grid=alev4.createSpatialGrid(meta.input_grid);
    optical_grid=alev4.createSpatialGrid(meta.optical_grid);
    order=alev4.spatialBundleUtil('listdecode',meta.operation_order,'step');
    if ~isstruct(meta.spatial_provenance) || ~isscalar(meta.spatial_provenance)
        error('ALEV4:InvalidSpatialMetadata','Spatial provenance must be a scalar informational struct.');
    end
    alev4.encodeBundleJson(meta.spatial_provenance);
    pre=ischar(meta.input_stage) && isrow(meta.input_stage) && strcmp(meta.input_stage,'pre_psf');
    post=ischar(meta.input_stage) && isrow(meta.input_stage) && strcmp(meta.input_stage,'post_optics');
    if ~pre && ~post
        error('ALEV4:InvalidSpatialMetadata','Unsupported input_stage.');
    end
    K=numel(sensor.wavelength_nm);
    density='photons m^-2 s^-1 nm^-1';
    keys={'input_irradiance','optical_irradiance','sampled_irradiance','expected_electrons'};
    files={'input.f64','optical.f64','sampled.f64','expected.f64'};
    types={'float64','float64','float64','float64'};
    shapes={[numel(input_grid.y_edges_m)-1 numel(input_grid.x_edges_m)-1 K], ...
        [numel(optical_grid.y_edges_m)-1 numel(optical_grid.x_edges_m)-1 K], ...
        [sensor.image_size K],sensor.image_size};
    units={density,density,density,'electrons'};
    if pre
        alev4.spatialBundleUtil('fields',meta.psf, ...
            {'schema_version','origin_rc','spacing_yx_m','wavelength_nm','boundary_policy','parameter_sources'},'PSF metadata');
        requireWireKinds(kinds.psf,{'origin_rc','spacing_yx_m'},{'vector'},'PSF coordinates');
        requireWireKinds(kinds.psf,{'wavelength_nm'},{'empty','number','vector'},'PSF wavelengths');
        if ~isstruct(meta.files) || ~isscalar(meta.files) || ~isfield(meta.files,'psf') || ...
                ~isstruct(meta.files.psf) || ~isscalar(meta.files.psf) || ~isfield(meta.files.psf,'shape')
            error('ALEV4:InvalidSpatialMetadata','PSF descriptor is required.');
        end
        psf_shape=alev4.spatialBundleUtil('shape',meta.files.psf.shape,3);
        if any(psf_shape(1:2)>63) || prod(psf_shape)>1e6 || ~any(psf_shape(3)==[1 K])
            error('ALEV4:InvalidSpatialMetadata','PSF shape exceeds supported kernel or spectral limits.');
        end
        keys{end+1}='psf'; files{end+1}='psf.f64'; types{end+1}='float64';
        shapes{end+1}=psf_shape; units{end+1}='unitless weights';
    elseif ~isnumeric(meta.psf) || ~isempty(meta.psf)
        error('ALEV4:DuplicateOptics','Post-optics manifest must have psf=[].');
    end
    if strcmp(mode,'single')
        keys{end+1}='raw'; files{end+1}='readout.raw'; types{end+1}='uint16';
        shapes{end+1}=sensor.image_size; units{end+1}='DN';
    else
        keys=[keys {'high_raw','low_raw','merged_electrons','flags'}];
        files=[files {'readout.high.raw','readout.low.raw','readout.merged.f64','readout.flags.u8'}];
        types=[types {'uint16','uint16','float64','uint8'}];
        shapes=[shapes {sensor.image_size,sensor.image_size,sensor.image_size,sensor.image_size}];
        units=[units {'DN','DN','electrons','bitmask'}];
    end
    keys{end+1}='readout_metadata'; files{end+1}='readout.json';
    types{end+1}='utf8'; shapes{end+1}=[]; units{end+1}='metadata';
    alev4.spatialBundleUtil('fields',meta.files,keys,'files');
    inventory=dir(directory);
    actual={inventory.name}; actual=actual(~ismember(actual,{'.','..'}));
    expected=[files {'spatial.json'}];
    if ~isequal(sort(actual),sort(expected))
        error('ALEV4:InvalidSpatialMetadata','Bundle directory must have exactly its declared file inventory.');
    end
    paths=cellfun(@(name)fullfile(directory,name),expected,'UniformOutput',false);
    alev4.spatialBundleUtil('distinct',paths);
    for k=1:numel(keys)
        validateDescriptor(meta.files.(keys{k}),kinds.files.(keys{k}),files{k},types{k},shapes{k},units{k},directory);
    end
    input=alev4.spatialBundleUtil('readplane',fullfile(directory,'input.f64'),shapes{1},'float64');
    optical=alev4.spatialBundleUtil('readplane',fullfile(directory,'optical.f64'),shapes{2},'float64');
    sampled=alev4.spatialBundleUtil('readplane',fullfile(directory,'sampled.f64'),shapes{3},'float64');
    expected_electrons=alev4.spatialBundleUtil('readplane',fullfile(directory,'expected.f64'),sensor.image_size,'float64');
    if pre
        psf=meta.psf;
        psf.parameter_sources=alev4.spatialBundleUtil('listdecode',psf.parameter_sources,'id');
        psf.kernel=alev4.spatialBundleUtil('readplane',fullfile(directory,'psf.f64'),psf_shape,'float64');
        psf=alev4.createOpticalPsf(psf);
    else
        psf=[];
    end
    [nested,nested_kinds]=alev4.spatialBundleUtil('readjson',fullfile(directory,'readout.json'));
    if strcmp(mode,'single')
        alev4.spatialBundleUtil('fields',nested,{'format','schema_version','synthetic','calibrated', ...
            'authentic_arriraw','description','height','width','byte_count','sample_type','byte_order', ...
            'layout','units','cfa_pattern','cfa_origin','exposure_s','seed','sensor','algorithm_version', ...
            'sampler_version','runtime','provenance'},'nested single manifest');
        requireWireKinds(nested_kinds,{'height','width','byte_count','exposure_s','seed'}, ...
            {'number'},'nested single scalars');
        requireWireKinds(nested_kinds,{'synthetic','calibrated','authentic_arriraw'}, ...
            {'boolean'},'nested single labels');
        requireWireKinds(nested_kinds,{'cfa_origin'},{'vector'},'nested CFA origin');
        if ~ischar(nested.description) || ~isrow(nested.description) || ...
                isempty(strtrim(nested.description)) || any(nested.description==char(0))
            error('ALEV4:InvalidSpatialMetadata','Nested single description must be nonempty text without NUL.');
        end
        normalizeConfiguration(nested.sensor);
        validateConfigurationKinds(nested.sensor,nested_kinds.sensor);
        [raw,nested]=alev4.readSyntheticRaw(fullfile(directory,'readout'));
        readout=struct('raw_dn',raw,'exposure_s',nested.exposure_s,'seed',nested.seed, ...
            'expected_electrons',expected_electrons);
        alev4.spatialBundleUtil('equalmeta',nested.sensor,configuration,'nested configuration');
    else
        alev4.spatialBundleUtil('fields',nested,{'format','schema_version','algorithm_version','synthetic', ...
            'calibrated_alev4','authentic_arriraw','configuration','image_size','exposure_s','seed', ...
            'input_units','array_order','byte_order','cfa_origin','files','units','runtime','provenance'},'nested dual manifest');
        requireWireKinds(nested_kinds,{'exposure_s','seed'},{'number'},'nested dual scalars');
        requireWireKinds(nested_kinds,{'synthetic','calibrated_alev4','authentic_arriraw'}, ...
            {'boolean'},'nested dual labels');
        requireWireKinds(nested_kinds,{'image_size'},{'vector'},'nested dual image size');
        requireWireKinds(nested_kinds,{'cfa_origin'},{'text'},'nested dual CFA origin');
        normalizeConfiguration(nested.configuration);
        validateConfigurationKinds(nested.configuration,nested_kinds.configuration);
        [readout,nested]=alev4.readDualGainBundle(fullfile(directory,'readout'));
        readout.expected_electrons=expected_electrons;
        alev4.spatialBundleUtil('equalmeta',nested.configuration,configuration,'nested configuration');
    end
    alev4.spatialBundleUtil('equalmeta',nested.runtime,meta.runtime,'nested runtime');
    alev4.spatialBundleUtil('equalmeta',nested.provenance,meta.provenance,'nested provenance');
    alev4.spatialBundleUtil('equalmeta',nested.exposure_s,meta.exposure_s,'nested exposure');
    alev4.spatialBundleUtil('equalmeta',nested.seed,meta.seed,'nested seed');
    decoded=struct('schema_version','1.0','readout_mode',mode,'input_stage',meta.input_stage, ...
        'input_irradiance',input,'input_grid',input_grid,'geometry',geometry,'configuration',configuration, ...
        'psf',psf,'optical_irradiance',optical,'optical_grid',optical_grid, ...
        'sampled_irradiance',sampled,'readout',readout,'operation_order',{order}, ...
        'spatial_provenance',meta.spatial_provenance,'synthetic',true,'calibrated_alev4',false);
    [decoded,~,incident]=alev4.spatialValidateResult(decoded,false);
    decoded.readout.expected_incident_photons=incident;
    % Deterministic readout has an independent, observable charge-to-code
    % association. Noisy bundles retain only verifiable recorded history.
    if strcmp(mode,'single')
        quiet=~sensor.shot_noise && sensor.read_noise_e==0;
        if quiet
            reference=alev4.simulateExposure(decoded.sampled_irradiance,configuration,meta.exposure_s,meta.seed);
            if ~isequal(decoded.readout.raw_dn,reference.raw_dn)
                error('ALEV4:SpatialSemanticMismatch','Deterministic single RAW contradicts the spatial expected charge.');
            end
        end
    else
        quiet=~sensor.shot_noise && configuration.high_gain.read_noise_e==0 && configuration.low_gain.read_noise_e==0;
        if quiet
            reference=alev4.simulateDualGainExposure(decoded.sampled_irradiance,configuration,meta.exposure_s,meta.seed);
            if ~isequal(decoded.readout.high_gain.raw_dn,reference.high_gain.raw_dn) || ...
                    ~isequal(decoded.readout.low_gain.raw_dn,reference.low_gain.raw_dn) || ...
                    ~isequal(decoded.readout.full_well_saturated,reference.full_well_saturated)
                error('ALEV4:SpatialSemanticMismatch','Deterministic dual RAW/physical flags contradict the spatial expected charge.');
            end
        end
    end
    % Return canonical native metadata for callers; bytes remain available
    % through the fixed manifest path and descriptor hashes.
    meta.geometry=geometry; meta.configuration=configuration;
    meta.input_grid=input_grid; meta.optical_grid=optical_grid;
    meta.psf=psf; meta.operation_order=order;
end

function validateDescriptor(value,kinds,name,type,shape,units,directory)
    alev4.spatialBundleUtil('fields',value,{'name','sha256','byte_count','sample_type','shape','units'},'file descriptor');
    requireWireKinds(kinds,{'byte_count'},{'number'},'descriptor byte count');
    alev4.spatialBundleUtil('text',value.name,name,'file name');
    alev4.spatialBundleUtil('text',value.sample_type,type,'sample type');
    alev4.spatialBundleUtil('text',value.units,units,'file units');
    if ~ischar(value.sha256) || ~isrow(value.sha256) || ...
            isempty(regexp(value.sha256,'^[0-9a-f]{64}\z','once'))
        error('ALEV4:InvalidSpatialMetadata','Malformed SHA-256 digest.');
    end
    if strcmp(type,'utf8')
        requireWireKinds(kinds,{'shape'},{'empty'},'metadata descriptor shape');
        if ~isnumeric(value.shape) || ~isempty(value.shape)
            error('ALEV4:InvalidSpatialMetadata','Text descriptor shape must be [].');
        end
        alev4.spatialBundleUtil('scalar',value.byte_count,2,2000000,true,'metadata byte count');
        limit=2000000;
    else
        requireWireKinds(kinds,{'shape'},{'vector'},'payload descriptor shape');
        observed=alev4.spatialBundleUtil('shape',value.shape,numel(shape));
        if ~isequal(observed,shape)
            error('ALEV4:InvalidSpatialMetadata','File shape conflicts with spatial/readout configuration.');
        end
        switch type
            case 'float64', width=8;
            case 'uint16', width=2;
            case 'uint8', width=1;
        end
        alev4.spatialBundleUtil('scalar',value.byte_count,1,800000000,true,'payload byte count');
        if value.byte_count~=prod(shape)*width
            error('ALEV4:InvalidSpatialMetadata','File byte count conflicts with declared shape/type.');
        end
        limit=value.byte_count;
    end
    [digest,count]=alev4.spatialBundleUtil('hash',fullfile(directory,name),limit);
    if count~=value.byte_count || ~strcmp(digest,value.sha256)
        error('ALEV4:SpatialChecksumMismatch','Actual file length or SHA-256 differs from descriptor.');
    end
end

function requireWireKinds(kinds,names,allowed,label)
% The numeric value alone cannot distinguish 1 from [1] or [[1]].
    if ~isstruct(kinds) || ~isscalar(kinds) || ~all(isfield(kinds,names))
        error('ALEV4:InvalidSpatialMetadata','Missing JSON type information for %s.',label);
    end
    for k=1:numel(names)
        kind=kinds.(names{k});
        if ~ischar(kind) || ~any(strcmp(kind,allowed))
            error('ALEV4:InvalidSpatialMetadata','Invalid JSON scalar/container type for %s.',label);
        end
    end
end

function validateConfigurationKinds(configuration,kinds)
    if strcmp(configuration.schema_version,'2.0')
        sensor=configuration.sensor; sensor_kinds=kinds.sensor;
        for path={'high_gain','low_gain'}
            requireWireKinds(kinds.(path{1}), ...
                {'gain_dn_per_e','read_noise_e','black_level_dn','adc_bits'}, ...
                {'number'},'readout path scalars');
        end
        requireWireKinds(kinds.merge,{'start_e','end_e'},{'number'},'merge scalars');
    else
        sensor=configuration; sensor_kinds=kinds;
    end
    requireWireKinds(sensor_kinds,{'pixel_pitch_m','fill_factor','full_well_e','read_noise_e', ...
        'gain_dn_per_e','black_level_dn','adc_bits'},{'number'},'sensor scalars');
    requireWireKinds(sensor_kinds,{'shot_noise'},{'boolean'},'shot noise');
    requireWireKinds(sensor_kinds,{'image_size'},{'vector'},'sensor image size');
    requireWireKinds(sensor_kinds,{'wavelength_nm','bin_width_nm'},{'number','vector'},'spectral vectors');
    if numel(sensor.wavelength_nm)==1
        requireWireKinds(sensor_kinds,{'qe'},{'vector','matrix'},'single-bin QE');
        if strcmp(sensor_kinds.qe,'matrix') && ~isequal(size(sensor.qe),[1 3])
            error('ALEV4:InvalidSpatialMetadata','Single-bin QE matrix must have one RGB row.');
        end
    else
        requireWireKinds(sensor_kinds,{'qe'},{'matrix'},'spectral QE matrix');
    end
end

function validateIdentity(runtime,provenance)
    alev4.spatialBundleUtil('fields',runtime,{'name','version'},'runtime');
    if ~ischar(runtime.name) || ~isrow(runtime.name) || ...
            ~any(strcmp(runtime.name,{'GNU Octave','MATLAB'})) || ...
            ~ischar(runtime.version) || ~isrow(runtime.version) || isempty(runtime.version) || any(runtime.version==char(0))
        error('ALEV4:InvalidSpatialMetadata','Invalid runtime identity.');
    end
    keys={'repository_head','isetcam_head','isethdrsensor_head','meaning'};
    alev4.spatialBundleUtil('fields',provenance,keys,'provenance');
    for k=1:3
        value=provenance.(keys{k});
        if ~ischar(value) || (~isempty(value) && (~isrow(value) || isempty(regexp(value,'^[0-9a-f]{40}\z','once'))))
            error('ALEV4:InvalidSpatialMetadata','Malformed observed provenance revision.');
        end
    end
    if ~ischar(provenance.meaning) || ~isrow(provenance.meaning) || isempty(provenance.meaning) || any(provenance.meaning==char(0))
        error('ALEV4:InvalidSpatialMetadata','Provenance meaning is required.');
    end
end

function configuration=normalizeConfiguration(configuration)
    if ~isstruct(configuration) || ~isscalar(configuration) || ~isfield(configuration,'schema_version')
        error('ALEV4:InvalidSpatialMetadata','Complete readout configuration is required.');
    end
    if isequal(configuration.schema_version,'2.0')
        defaults=alev4.createDualGainSensor();
        alev4.spatialBundleUtil('fields',configuration,fieldnames(defaults),'configuration');
        for f={'sensor','high_gain','low_gain','merge'}
            alev4.spatialBundleUtil('fields',configuration.(f{1}),fieldnames(defaults.(f{1})),f{1});
        end
        if isnumeric(configuration.sensor.qe) && numel(configuration.sensor.wavelength_nm)==1 && numel(configuration.sensor.qe)==3
            configuration.sensor.qe=configuration.sensor.qe(:).';
        end
        configuration=alev4.createDualGainSensor(configuration);
    elseif isequal(configuration.schema_version,'1.0')
        alev4.spatialBundleUtil('fields',configuration,fieldnames(alev4.createBaselineSensor()),'configuration');
        if isnumeric(configuration.qe) && numel(configuration.wavelength_nm)==1 && numel(configuration.qe)==3
            configuration.qe=configuration.qe(:).';
        end
        configuration=alev4.createBaselineSensor(configuration);
    else
        error('ALEV4:InvalidSpatialMetadata','Unsupported readout schema.');
    end
end
