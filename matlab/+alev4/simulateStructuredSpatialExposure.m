function result = simulateStructuredSpatialExposure(input, input_grid, geometry, readout, exposure_s, frame_seed, model, options)
%SIMULATESTRUCTUREDSPATIALEXPOSURE Spatial sampling with structured readout.
%   The optional OPTIONS are exactly those of simulateSpatialExposure.
%   A disabled model directly returns that complete legacy spatial result.
%   An enabled model retains the intact legacy result in spatial_baseline as
%   verification context, then supplies its sampled irradiance to exactly one
%   structured exposure. The baseline's charge is never added to that exposure.
%   The enabled result has the structured-noise identity; it is not a legacy
%   spatial artifact. Its operation_order describes the structured readout;
%   spatial_operation_order additionally describes the optics and sampling.
%   Enabled calls reserve combined source, baseline and structured storage
%   before legacy sampling or dense-map conversion; disabled calls retain
%   the direct legacy allocation contract.
    if nargin < 7 || nargin > 8
        error('ALEV4:StructuredSpatialExposureArguments', ...
            'Seven arguments and optional spatial options are required.');
    end
    if nargin < 8, options = struct(); end
    caller_rng = rng;
    rng_guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    geometry = alev4.createSensorGeometry(geometry);
    % A raw inventory is necessary before either constructor can densify
    % sparse maps/configuration. It uses only dimensions and numeric counts.
    if enabledRequest(model)
        reserveSpatialSamples(input,input_grid,geometry,readout,model,options, ...
            declaredBands(readout,input));
    end
    model = alev4.createStructuredNoise(geometry.full_grid_size,model);
    alev4.structuredNoiseSeed(frame_seed,'photo');
    if ~model.enabled
        result = alev4.simulateSpatialExposure(input,input_grid,geometry, ...
            readout,exposure_s,frame_seed,options);
        return;
    end

    binding_mode = 'validate';
    if isstruct(options) && isscalar(options) && isfield(options,'binding_mode')
        binding_mode = options.binding_mode;
    end
    configuration = alev4.bindSensorGeometry(readout,geometry,binding_mode);
    sensor = configuration;
    if strcmp(configuration.schema_version,'2.0'), sensor = configuration.sensor; end
    % The authoritative spectral reservation uses validated configuration,
    % including an explicitly derived geometry binding. The legacy API still
    % validates the complete spatial option/input/PSF contract afterward.
    reserveSpatialSamples(input,input_grid,geometry,configuration,model,options, ...
        numel(sensor.wavelength_nm));

    % Preserve the legacy spatial schema and its valid legacy readout intact.
    % In particular, do not insert PRNU/dark/electronic results into a record
    % whose expected-charge and replay contract belongs to an earlier phase.
    baseline = alev4.simulateSpatialExposure(input,input_grid,geometry, ...
        configuration,exposure_s,frame_seed,options);
    result = alev4.simulateStructuredExposure(baseline.sampled_irradiance, ...
        baseline.configuration,exposure_s,frame_seed,model,baseline.geometry);
    result.result_kind = 'spatial_exposure';
    result.spatial_baseline = baseline;
    result.spatial_baseline_role = 'verification_context_only';
    result.spatial_operation_order = [baseline.operation_order(1:end-2), ...
        result.operation_order];
end

function answer = enabledRequest(model)
    answer = isstruct(model) && isscalar(model) && ...
        (~isfield(model,'enabled') || ...
        (islogical(model.enabled) && isscalar(model.enabled) && model.enabled));
end

function bands = declaredBands(configuration,input)
    sensor = configuration;
    if isstruct(configuration) && isscalar(configuration) && ...
            isfield(configuration,'schema_version') && ...
            isequal(configuration.schema_version,'2.0') && isfield(configuration,'sensor')
        sensor = configuration.sensor;
    end
    bands = size(input,3);
    if isstruct(sensor) && isscalar(sensor) && isfield(sensor,'wavelength_nm')
        bands = max(bands,numel(sensor.wavelength_nm));
    end
end

function reserveSpatialSamples(input,input_grid,geometry,configuration,model,options,bands)
    % Both configurations/geometries, both source grids, the entire full-grid
    % model, supplied PSF and arbitrary numerical provenance are retained.
    % 512+8*bands covers compact default descriptors/reports and spectral
    % diagnostics. Four input cubes cover retained input/optical data plus
    % optical/sampling workspace. Per target pixel reserve two sampled cubes
    % and 128 values for BOTH legacy and structured diagnostics, maps, compact
    % row/column terms, readouts and working arrays. This deliberately exceeds
    % the core-only reservation; it is not a memory/throughput guarantee.
    fixed = alev4.structuredNumericSamples(model) + ...
        2*alev4.structuredNumericSamples(configuration) + ...
        2*alev4.structuredNumericSamples(geometry) + ...
        2*alev4.structuredNumericSamples(input_grid) + ...
        alev4.structuredNumericSamples(options) + 512 + 8*bands;
    pixels = prod(geometry.active_roi(3:4));
    if fixed > 1e8 || numel(input) > (1e8-fixed)/4
        error('ALEV4:StructuredNoiseSize', ...
            'Structured spatial descriptors and source arrays exceed the 100 million sample reservation.');
    end
    remaining = 1e8-fixed-4*numel(input);
    if pixels > remaining/(128+2*bands)
        error('ALEV4:StructuredNoiseSize', ...
            'Retained legacy and structured spatial arrays exceed the 100 million sample reservation.');
    end
end
