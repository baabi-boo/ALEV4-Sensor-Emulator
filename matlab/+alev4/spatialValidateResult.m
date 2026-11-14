function [result, expected, incident] = spatialValidateResult(result, validate_readout)
%SPATIALVALIDATERESULT Recompute the deterministic Phase 3 data association.
%   VALIDATE_READOUT additionally replays same-runtime stochastic readout for
%   export. A reader can check observed files without inventing analog history.
    if nargin<2, validate_readout=false; end
    required={'schema_version','readout_mode','input_stage','input_irradiance', ...
        'input_grid','geometry','configuration','psf','optical_irradiance', ...
        'optical_grid','sampled_irradiance','readout','operation_order', ...
        'spatial_provenance','synthetic','calibrated_alev4'};
    if ~isstruct(result) || ~isscalar(result) || ~all(isfield(result,required))
        error('ALEV4:InvalidSpatialResult','A complete spatial exposure result is required.');
    end
    extra=setdiff(fieldnames(result),[required {'optical_report','sampling_report'}]);
    if ~isempty(extra)
        error('ALEV4:InvalidSpatialResult','Unknown spatial result field.');
    end
    alev4.spatialBundleUtil('text',result.schema_version,'1.0','spatial result schema');
    alev4.spatialBundleUtil('boolean',result.synthetic,true,'synthetic');
    alev4.spatialBundleUtil('boolean',result.calibrated_alev4,false,'calibrated_alev4');
    alev4.spatialBundleUtil('fields',result.geometry,fieldnames(alev4.createSensorGeometry()),'geometry');
    alev4.spatialBundleUtil('fields',result.input_grid,fieldnames(alev4.createSpatialGrid()),'input grid');
    alev4.spatialBundleUtil('fields',result.optical_grid,fieldnames(alev4.createSpatialGrid()),'optical grid');
    result.geometry=alev4.createSensorGeometry(result.geometry);
    result.configuration=normalizeConfiguration(result.configuration);
    result.configuration=alev4.bindSensorGeometry(result.configuration,result.geometry,'validate');
    if strcmp(result.configuration.schema_version,'2.0')
        sensor=result.configuration.sensor; mode='dual'; operation='dual_gain_readout';
    else
        sensor=result.configuration; mode='single'; operation='single_gain_readout';
    end
    alev4.spatialBundleUtil('text',result.readout_mode,mode,'readout mode');
    if ~isstruct(result.spatial_provenance) || ~isscalar(result.spatial_provenance)
        error('ALEV4:InvalidSpatialMetadata','Spatial provenance must be a scalar informational struct.');
    end
    % Validate the optional informational metadata with the same bounded
    % portable JSON subset, rather than silently converting unknown cells.
    alev4.encodeBundleJson(result.spatial_provenance);
    [result.input_irradiance,result.input_grid]=alev4.validateSpatialIrradiance(result.input_irradiance,result.input_grid);
    if size(result.input_irradiance,3)~=numel(sensor.wavelength_nm)
        error('ALEV4:SpatialSpectralMismatch','Input planes and readout spectral bins differ.');
    end
    if ischar(result.input_stage) && strcmp(result.input_stage,'pre_psf')
        alev4.spatialBundleUtil('fields',result.psf,fieldnames(alev4.createOpticalPsf()),'PSF');
        result.psf=alev4.createOpticalPsf(result.psf);
        [optical,grid]=alev4.applyOpticalPsf(result.input_irradiance,result.input_grid,result.psf,sensor.wavelength_nm);
        order={'optical_psf','area_overlap_average','spectral_integration',operation};
        optics_operations=numel(result.psf.kernel);
    elseif ischar(result.input_stage) && strcmp(result.input_stage,'post_optics')
        if ~isa(result.psf,'double') || ~isequal(size(result.psf),[0 0])
            error('ALEV4:DuplicateOptics','Post-optics PSF metadata must be [].');
        end
        optical=result.input_irradiance; grid=result.input_grid;
        order={'area_overlap_average','spectral_integration',operation};
        optics_operations=1;
    else
        error('ALEV4:InvalidSpatialMetadata','Unsupported spatial input stage.');
    end
    if ~isequal(result.operation_order,order)
        error('ALEV4:InvalidSpatialMetadata','Spatial operation order is inconsistent with stage/readout.');
    end
    [result.optical_irradiance,result.optical_grid]=alev4.validateSpatialIrradiance(result.optical_irradiance,result.optical_grid);
    alev4.spatialBundleUtil('equalmeta',result.optical_grid,grid,'optical grid');
    alev4.spatialBundleUtil('close',result.optical_irradiance,optical,optics_operations,'optical irradiance');
    if strcmp(result.input_stage,'post_optics') && ~isequal(result.optical_irradiance,result.input_irradiance)
        error('ALEV4:SpatialSemanticMismatch','Post-optics input must be retained without modification.');
    end
    sampled=alev4.resampleSensorIrradiance(optical,grid,result.geometry);
    source_operations=size(optical,1)+size(optical,2);
    alev4.spatialBundleUtil('close',result.sampled_irradiance,sampled,source_operations,'sampled irradiance');
    if ~isstruct(result.readout) || ~isscalar(result.readout) || ...
            ~all(isfield(result.readout,{'exposure_s','seed','expected_electrons'}))
        error('ALEV4:InvalidSpatialResult','Readout exposure, seed, and expected electrons are required.');
    end
    alev4.spatialBundleUtil('scalar',result.readout.exposure_s,0,realmax,false,'exposure_s');
    alev4.spatialBundleUtil('scalar',result.readout.seed,0,2^32-1,true,'seed');
    [expected,incident]=alev4.integrateExposure(sampled,sensor,result.readout.exposure_s);
    alev4.spatialBundleUtil('close',result.readout.expected_electrons,expected,8*numel(sensor.wavelength_nm),'expected electrons');
    if validate_readout
        if strcmp(mode,'dual')
            replay=alev4.simulateDualGainExposure(sampled,result.configuration,result.readout.exposure_s,result.readout.seed);
        else
            replay=alev4.simulateExposure(sampled,result.configuration,result.readout.exposure_s,result.readout.seed);
        end
        if ~isequal(result.readout,replay)
            error('ALEV4:SpatialSemanticMismatch','Export readout does not match same-runtime input/configuration/seed replay.');
        end
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
        error('ALEV4:InvalidSpatialMetadata','Unsupported readout configuration schema.');
    end
end
