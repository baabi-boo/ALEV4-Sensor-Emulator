function result = simulateSpatialExposure(input, input_grid, geometry, readout, exposure_s, seed, options)
%SIMULATESPATIALEXPOSURE Explicit optics and pixel averaging before readout.
%   INPUT is spectral cell-average photon irradiance, not RGB or photon counts.
%   OPTIONS fields: input_stage ('pre_psf' default, or 'post_optics'), psf
%   (identity by default before optics; must be [] for post_optics),
%   binding_mode ('validate' default, or explicit 'derive'), and
%   spatial_provenance (scalar metadata struct, default empty).
%   Existing single/dual configurations and their noise contracts are retained.
    if nargin < 6 || nargin > 7
        error('ALEV4:SpatialExposureArguments', 'Six arguments and optional spatial options are required.');
    end
    if nargin < 7, options = struct(); end
    if ~isstruct(options) || ~isscalar(options)
        error('ALEV4:InvalidSpatialOptions', 'Spatial options must be a scalar struct.');
    end
    allowed = {'input_stage','psf','binding_mode','spatial_provenance'};
    names = fieldnames(options);
    for k = 1:numel(names)
        if ~any(strcmp(names{k},allowed))
            error('ALEV4:InvalidSpatialOptions', 'Unknown spatial option: %s.',names{k});
        end
    end
    if ~isfield(options,'input_stage'), options.input_stage = 'pre_psf'; end
    if ~isfield(options,'binding_mode'), options.binding_mode = 'validate'; end
    if ~isfield(options,'spatial_provenance'), options.spatial_provenance = struct(); end
    if isfield(options,'psf') && ...
            ~((isa(options.psf,'double') && isequal(options.psf,[])) || ...
              (isstruct(options.psf) && isscalar(options.psf)))
        error('ALEV4:InvalidSpatialOptions', 'psf must be [] or a scalar PSF configuration.');
    end
    if ~ischar(options.input_stage) || ~isrow(options.input_stage) || ...
            ~any(strcmp(options.input_stage,{'pre_psf','post_optics'})) || ...
            ~isstruct(options.spatial_provenance) || ~isscalar(options.spatial_provenance)
        error('ALEV4:InvalidSpatialOptions', 'Invalid input stage or spatial provenance.');
    end
    caller_rng = rng;
    rng_guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    geometry = alev4.createSensorGeometry(geometry);
    configuration = alev4.bindSensorGeometry(readout,geometry,options.binding_mode);
    if strcmp(configuration.schema_version,'2.0')
        sensor = configuration.sensor;
        mode = 'dual';
        last_operation = 'dual_gain_readout';
    else
        sensor = configuration;
        mode = 'single';
        last_operation = 'single_gain_readout';
    end
    [input,input_grid] = alev4.validateSpatialIrradiance(input,input_grid);
    bands = size(input,3);
    if bands ~= numel(sensor.wavelength_nm)
        error('ALEV4:SpatialSpectralMismatch', 'Spatial input planes must match the readout wavelength bins exactly.');
    end
    % Reject unsupported output cubes before constructing/applying a PSF or
    % allocating target coordinates. Both ROI and spectral count are valid.
    if prod(geometry.active_roi(3:4)) > 1e8/bands
        error('ALEV4:InvalidSpatialSampling', 'Output cubes support at most 100 million numeric samples.');
    end
    if strcmp(options.input_stage,'post_optics')
        if isfield(options,'psf') && ~isempty(options.psf)
            error('ALEV4:DuplicateOptics', 'Post-optics input cannot receive another PSF in schema 1.0.');
        end
        psf = [];
        optical = input;
        optical_grid = input_grid;
        optical_report = struct('operation','none','reason','input_already_post_optics');
        order = {'area_overlap_average','spectral_integration',last_operation};
    else
        if ~isfield(options,'psf') || isempty(options.psf)
            psf = alev4.createOpticalPsf(struct('spacing_yx_m', ...
                [input_grid.y_edges_m(2)-input_grid.y_edges_m(1), ...
                 input_grid.x_edges_m(2)-input_grid.x_edges_m(1)]));
        else
            psf = alev4.createOpticalPsf(options.psf);
        end
        [optical,optical_grid,optical_report] = ...
            alev4.applyOpticalPsf(input,input_grid,psf,sensor.wavelength_nm);
        order = {'optical_psf','area_overlap_average','spectral_integration',last_operation};
    end
    [sampled,sampling_report] = alev4.resampleSensorIrradiance(optical,optical_grid,geometry);
    if strcmp(mode,'dual')
        observed = alev4.simulateDualGainExposure(sampled,configuration,exposure_s,seed);
    else
        observed = alev4.simulateExposure(sampled,configuration,exposure_s,seed);
    end
    result = struct('schema_version','1.0','readout_mode',mode, ...
        'input_stage',options.input_stage, 'input_irradiance',input, ...
        'input_grid',input_grid, 'geometry',geometry, ...
        'configuration',configuration, 'psf',psf, ...
        'optical_irradiance',optical, 'optical_grid',optical_grid, ...
        'sampled_irradiance',sampled, 'readout',observed, ...
        'operation_order',{order}, 'spatial_provenance',options.spatial_provenance, ...
        'optical_report',optical_report, 'sampling_report',sampling_report, ...
        'synthetic',true, 'calibrated_alev4',false);
end
