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
    if nargin < 7 || nargin > 8
        error('ALEV4:StructuredSpatialExposureArguments', ...
            'Seven arguments and optional spatial options are required.');
    end
    if nargin < 8, options = struct(); end
    caller_rng = rng;
    rng_guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    geometry = alev4.createSensorGeometry(geometry);
    model = alev4.createStructuredNoise(geometry.full_grid_size,model);
    alev4.structuredNoiseSeed(frame_seed,'photo');
    if ~model.enabled
        result = alev4.simulateSpatialExposure(input,input_grid,geometry, ...
            readout,exposure_s,frame_seed,options);
        return;
    end

    % Preserve the legacy spatial schema and its valid legacy readout intact.
    % In particular, do not insert PRNU/dark/electronic results into a record
    % whose expected-charge and replay contract belongs to an earlier phase.
    baseline = alev4.simulateSpatialExposure(input,input_grid,geometry, ...
        readout,exposure_s,frame_seed,options);
    result = alev4.simulateStructuredExposure(baseline.sampled_irradiance, ...
        baseline.configuration,exposure_s,frame_seed,model,baseline.geometry);
    result.result_kind = 'spatial_exposure';
    result.spatial_baseline = baseline;
    result.spatial_baseline_role = 'verification_context_only';
    result.spatial_operation_order = [baseline.operation_order(1:end-2), ...
        result.operation_order];
end
