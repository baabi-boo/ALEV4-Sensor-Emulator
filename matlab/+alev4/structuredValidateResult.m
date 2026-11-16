function result = structuredValidateResult(result)
%STRUCTUREDVALIDATERESULT Verify complete native Phase 4 exposure semantics.
%   RESULT = alev4.structuredValidateResult(RESULT) returns an enabled,
%   canonical exposure or spatial_exposure unchanged. It checks native
%   classes/shapes, complete metadata, fixed-map crops, deterministic spectral
%   expectations, retained charge/electronic assembly, ADC and observed-only
%   merging. It never calls a stochastic simulator or samples a random stream.
%   Finite random realizations are checked for their declared support and
%   zero-noise constraints; this is not proof of their PRNG origin or law.
%   A spatial result must retain its complete legacy verification baseline.
%   Caller RNG is preserved on both success and failure.
    if nargin ~= 1
        error('ALEV4:StructuredValidationArguments','Exactly one complete result is required.');
    end
    caller_rng = rng;
    rng_guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    names = {'format','schema_version','result_kind','readout_mode', ...
        'configuration','geometry','noise_model','input_irradiance', ...
        'baseline_expected_electrons','active_maps','components','readout', ...
        'operation_order','seeds','seed_policy','stream_scope','runtime','units', ...
        'parameter_classification','temperature_condition','synthetic','calibrated_alev4'};
    if ~isstruct(result) || ~isscalar(result) || ~isfield(result,'result_kind')
        error('ALEV4:InvalidStructuredResult','A complete enabled structured result is required.');
    end
    if isequal(result.result_kind,'spatial_exposure')
        names = [names {'spatial_baseline','spatial_baseline_role','spatial_operation_order'}];
        spatial = true;
    elseif isequal(result.result_kind,'exposure')
        spatial = false;
    else
        error('ALEV4:InvalidStructuredResult','Unsupported structured result kind.');
    end
    fields(result,names,'structured result');
    text(result.format,'ALEV4-SYNTHETIC-STRUCTURED-NOISE','format');
    text(result.schema_version,'1.0','schema version');
    exact(result.synthetic,true,'synthetic');
    exact(result.calibrated_alev4,false,'calibrated_alev4');
    text(result.parameter_classification,'assumed','parameter classification');
    text(result.seed_policy, ...
        'component_seed = mod(frame_seed + tag, 2^32); locally saved/restored Twister','seed policy');
    text(result.stream_scope, ...
        'same runtime/version; no cross-runtime stream identity claim','stream scope');
    validateRuntime(result.runtime);

    fields(result.geometry,fieldnames(alev4.createSensorGeometry()),'geometry');
    geometry = alev4.createSensorGeometry(result.geometry);
    exact(result.geometry,geometry,'canonical geometry');
    configuration = alev4.bindSensorGeometry(result.configuration,geometry,'validate');
    exact(result.configuration,configuration,'canonical configuration');
    if strcmp(configuration.schema_version,'2.0')
        sensor = configuration.sensor; mode = 'dual';
    else
        sensor = configuration; mode = 'single';
    end
    text(result.readout_mode,mode,'readout mode');
    defaults = alev4.createStructuredNoise(geometry.full_grid_size);
    fields(result.noise_model,fieldnames(defaults),'noise model');
    path_names = {'shared','single','high_gain','low_gain'};
    for k = 1:numel(path_names)
        name = path_names{k};
        fields(result.noise_model.(name),fieldnames(defaults.(name)),['noise model.' name]);
    end
    model = alev4.createStructuredNoise(geometry.full_grid_size,result.noise_model);
    exact(result.noise_model,model,'canonical noise model');
    exact(model.enabled,true,'enabled model');
    exact(result.temperature_condition,struct( ...
        'reference_temperature_K',model.reference_temperature_K, ...
        'policy','declared applicability only; no temperature law or extrapolation'), ...
        'temperature condition');
    order = {'spectral_integration','prnu_response','dark_expectation', ...
        'separate_photo_dark_sampling','charge_sum','physical_full_well', ...
        'shared_electronics','path_electronics_and_pixel_read_noise', ...
        'gain_and_black','round','adc_clip'};
    if strcmp(mode,'dual'), order{end+1} = 'observed_channel_merge'; end
    exact(result.operation_order,order,'operation order');
    units = struct('input_irradiance','photons m^-2 s^-1 nm^-1', ...
        'expected_incident_photons','photons','charge','electrons', ...
        'components','electrons','read_electrons','electrons','raw_dn','DN', ...
        'exposure_s','s','dark_current_e_per_s','electrons s^-1','prnu','dimensionless');
    exact(result.units,units,'units');

    dimensions = sensor.image_size;
    bands = numel(sensor.wavelength_nm);
    % Match the producer's compact scalar-metadata allowance, including
    % singleton ROIs where per-pixel slack cannot cover these fixed fields.
    fixed_count = numericCount(model)+numericCount(configuration)+numericCount(geometry)+64;
    if fixed_count > 1e8 || prod(dimensions) > (1e8-fixed_count)/(64+bands)
        error('ALEV4:StructuredNoiseSize','Structured retained-array reservation exceeds its limit.');
    end
    doubleArray(result.input_irradiance,[dimensions bands],'input irradiance');
    if any(result.input_irradiance(:) < 0)
        error('ALEV4:InvalidStructuredResult','Input irradiance must be nonnegative.');
    end
    maps = cropMaps(model,geometry);
    exact(result.active_maps,maps,'active full-grid map crops');
    readout = result.readout;
    readout_names = {'expected_electrons','expected_photoelectrons', ...
        'expected_dark_electrons','collected_electrons','charge_electrons', ...
        'full_well_saturated','seed','expected_incident_photons','exposure_s', ...
        'input_units','spectral_bin_convention','reconstruction_valid'};
    if strcmp(mode,'dual')
        fields(readout,[readout_names {'high_gain','low_gain','merged'}],'readout');
        fields(result.components,{'photo_electrons','dark_electrons','shared', ...
            'high_gain','low_gain'},'components');
    else
        fields(readout,[readout_names pathFields(true)],'readout');
        fields(result.components,{'photo_electrons','dark_electrons','shared','single'},'components');
    end
    scalar(readout.exposure_s,0,realmax,false,'exposure seconds');
    scalar(readout.seed,0,2^32-1,true,'frame seed');
    validateSeeds(result.seeds,readout.seed);
    text(readout.input_units,units.input_irradiance,'readout input units');
    text(readout.spectral_bin_convention, ...
        'bin-average density times explicit width in nm','spectral bin convention');

    % Independent per-band accumulation and Bayer indexing; no simulation or
    % shared spectral-integration helper is used to establish this reference.
    [baseline,incident] = spectralReference(result.input_irradiance,sensor,readout.exposure_s);
    close(result.baseline_expected_electrons,baseline,8*bands,'baseline expectation');
    close(readout.expected_incident_photons,incident,8*bands,'incident photons');
    normal(result.baseline_expected_electrons,'retained baseline expectation');
    normal(readout.expected_incident_photons,'retained incident photons');
    photo_expected = product(maps.prnu,result.baseline_expected_electrons,'photo expectation');
    dark_expected = product(maps.dark_current_e_per_s,readout.exposure_s,'dark expectation');
    exact(readout.expected_photoelectrons,photo_expected,'PRNU photo expectation');
    exact(readout.expected_dark_electrons,dark_expected,'dark expectation');
    exact(readout.expected_electrons,add(photo_expected,dark_expected,'expected sum'), ...
        'total expected charge');
    charge(result.components.photo_electrons,photo_expected,sensor.shot_noise,'photo charge');
    charge(result.components.dark_electrons,dark_expected,model.dark_shot_noise,'dark charge');
    collected = add(result.components.photo_electrons,result.components.dark_electrons,'collected charge');
    stored = min(collected,sensor.full_well_e);
    exact(readout.collected_electrons,collected,'collected photo-plus-dark charge');
    exact(readout.charge_electrons,stored,'single shared physical well');
    saturated = collected >= sensor.full_well_e;
    exact(readout.full_well_saturated,saturated,'physical saturation');
    shared = electronics(result.components.shared,maps.shared,0,dimensions,'shared');
    shared_read = add(stored,shared,'shared signed readout');
    if strcmp(mode,'dual')
        for k = 1:2
            name = path_names{k+2};
            config = configuration.(name);
            total = electronics(result.components.(name),maps.(name), ...
                config.read_noise_e,dimensions,name);
            fields(readout.(name),pathFields(true),name);
            signed = add(shared_read,total,[name ' signed readout']);
            validatePath(readout.(name),signed,config,true,true,name);
        end
        valid = validateMerge(readout.merged,readout.high_gain.raw_dn, ...
            readout.low_gain.raw_dn,configuration);
    else
        total = electronics(result.components.single,maps.single,sensor.read_noise_e,dimensions,'single');
        signed = add(shared_read,total,'single signed readout');
        valid = validatePath(readout,signed,sensor,true,true,'single');
    end
    exact(readout.reconstruction_valid,valid & ~saturated,'reconstruction validity');
    if spatial, validateSpatial(result,sensor,mode); end
end

function maps = cropMaps(model,geometry)
    roi = geometry.active_roi;
    rows = roi(1):roi(1)+roi(3)-1;
    columns = roi(2):roi(2)+roi(4)-1;
    maps = struct('prnu',crop(model.prnu),'dark_current_e_per_s',crop(model.dark_current_e_per_s));
    for name = {'shared','single','high_gain','low_gain'}
        component = model.(name{1});
        component.fixed_offset_e = crop(component.fixed_offset_e);
        maps.(name{1}) = component;
    end
    function active = crop(value)
        if isscalar(value), active = repmat(value,roi(3:4));
        else, active = value(rows,columns); end
    end
end

function validateSeeds(seeds,frame)
    names = {'photo','dark','shared_row','shared_column','shared_frame', ...
        'single_row','single_column','single_frame','single_pixel', ...
        'high_row','high_column','high_frame','high_pixel', ...
        'low_row','low_column','low_frame','low_pixel'};
    tags = [1 2 10 11 12 20 21 22 23 30 31 32 33 40 41 42 43];
    fields(seeds,[{'frame'} names],'seed schedule');
    exact(seeds.frame,frame,'schedule frame seed');
    for k = 1:numel(names)
        exact(seeds.(names{k}),mod(frame+tags(k),2^32),['component seed ' names{k}]);
    end
end

function [expected,incident] = spectralReference(input,sensor,exposure)
    dimensions = sensor.image_size;
    expected = zeros(dimensions); incident = zeros(dimensions);
    if exposure == 0 || sensor.fill_factor == 0 || ~any(input(:) > 0), return; end
    collection = exposure*sensor.pixel_pitch_m^2*sensor.fill_factor;
    if ~isfinite(collection) || collection == 0
        error('ALEV4:StructuredSemanticMismatch','Collection factor is outside its supported range.');
    end
    bands = numel(sensor.wavelength_nm);
    incident_sum = zeros(dimensions);
    for band = 1:bands
        incident_sum = incident_sum+input(:,:,band)*sensor.bin_width_nm(band);
    end
    incident = collection*incident_sum;
    normal(incident,'incident expectation');
    lit = any(input > 0,3);
    if any(incident(lit) == 0)
        error('ALEV4:StructuredSemanticMismatch','Positive incident support was erased.');
    end
    colors = 'RGB';
    for color = 1:3
        signal_sum = zeros(dimensions); support = false(dimensions);
        for band = 1:bands
            weight = sensor.qe(band,color)*sensor.bin_width_nm(band);
            signal_sum = signal_sum+input(:,:,band)*weight;
            if sensor.qe(band,color) > 0, support = support | input(:,:,band) > 0; end
        end
        signal = collection*signal_sum;
        for row = 1:2
            for column = 1:2
                if sensor.cfa_pattern(2*(row-1)+column) == colors(color)
                    expected(row:2:end,column:2:end) = signal(row:2:end,column:2:end);
                    selected = signal(row:2:end,column:2:end);
                    selected_support = support(row:2:end,column:2:end);
                    if any(selected(selected_support) == 0)
                        error('ALEV4:StructuredSemanticMismatch','Positive photo support was erased.');
                    end
                end
            end
        end
    end
    normal(expected,'baseline photo expectation');
end

function charge(values,expected,shot,label)
    doubleArray(values,size(expected),label);
    if shot
        if any(expected(:) > 1e9) || any(values(:) < 0 | values(:) ~= fix(values(:))) || ...
                any(values(expected == 0) ~= 0)
            error('ALEV4:StructuredSemanticMismatch','%s violates Poisson support or mean limits.',label);
        end
    else
        exact(values,expected,[label ' with shot noise disabled']);
    end
end

function total = electronics(component,maps,pixel_sigma,dimensions,label)
    fields(component,{'fixed_offset_e','row_e','column_e','frame_e','pixel_e','total_e'},label);
    normal(maps.fixed_offset_e,[label ' fixed map']);
    normal([maps.row_noise_e maps.column_noise_e maps.frame_noise_e pixel_sigma],[label ' RMS']);
    exact(component.fixed_offset_e,maps.fixed_offset_e,[label ' fixed offset']);
    draw(component.row_e,[dimensions(1) 1],maps.row_noise_e,[label ' row']);
    draw(component.column_e,[1 dimensions(2)],maps.column_noise_e,[label ' column']);
    draw(component.frame_e,[1 1],maps.frame_noise_e,[label ' frame']);
    draw(component.pixel_e,dimensions,pixel_sigma,[label ' pixel']);
    total = add(component.fixed_offset_e,component.row_e,[label ' fixed plus row']);
    total = add(total,component.column_e,[label ' plus column']);
    total = add(total,component.frame_e,[label ' plus frame']);
    total = add(total,component.pixel_e,[label ' plus pixel']);
    exact(component.total_e,total,[label ' electronic total']);
end

function draw(value,dimensions,sigma,label)
    doubleArray(value,dimensions,label);
    normal(value,label);
    if sigma == 0 && any(value(:) ~= 0)
        error('ALEV4:StructuredSemanticMismatch','Zero RMS requires an exactly zero %s draw.',label);
    end
end

function names = pathFields(structured)
    names = {'read_electrons','raw_dn','adc_low_clipped','adc_high_clipped'};
    if structured, names{end+1} = 'adc_usable'; end
end

function usable = validatePath(path,signed,configuration,structured,enforce_signed,label)
    dimensions = size(signed);
    doubleArray(path.read_electrons,dimensions,[label ' signed readout']);
    if enforce_signed, exact(path.read_electrons,signed,[label ' signed readout']); end
    if structured
        gained = product(path.read_electrons,configuration.gain_dn_per_e,[label ' gain']);
        analog = add(gained,configuration.black_level_dn,[label ' black offset']);
    else
        analog = path.read_electrons.*configuration.gain_dn_per_e+configuration.black_level_dn;
        doubleArray(analog,dimensions,[label ' legacy analog DN']);
    end
    rounded = round(analog);
    maximum = 2^configuration.adc_bits-1;
    raw = uint16(min(max(rounded,0),maximum));
    exact(path.raw_dn,raw,[label ' RAW']);
    exact(path.adc_low_clipped,rounded < 0,[label ' lower ADC clipping']);
    exact(path.adc_high_clipped,rounded > maximum,[label ' upper ADC clipping']);
    usable = raw > 0 & double(raw) < maximum;
    if structured, exact(path.adc_usable,usable,[label ' ADC usability']); end
end

function valid = validateMerge(merged,high_raw,low_raw,configuration)
    fields(merged,{'electrons','weight_high','valid','high_usable','low_usable'},'observed merge');
    high = (double(high_raw)-configuration.high_gain.black_level_dn)/configuration.high_gain.gain_dn_per_e;
    low = (double(low_raw)-configuration.low_gain.black_level_dn)/configuration.low_gain.gain_dn_per_e;
    doubleArray(high,configuration.sensor.image_size,'high reconstructed electrons');
    doubleArray(low,configuration.sensor.image_size,'low reconstructed electrons');
    high_usable = high_raw > 0 & double(high_raw) < 2^configuration.high_gain.adc_bits-1;
    low_usable = low_raw > 0 & double(low_raw) < 2^configuration.low_gain.adc_bits-1;
    t = zeros(configuration.sensor.image_size);
    above = low >= configuration.merge.end_e;
    inside = low > configuration.merge.start_e & ~above;
    t(above) = 1;
    t(inside) = (low(inside)-configuration.merge.start_e)/ ...
        (configuration.merge.end_e-configuration.merge.start_e);
    weight = 1-t.^2.*(3-2.*t);
    weight(~high_usable) = 0;
    weight(high_usable & ~low_usable) = 1;
    electrons = weight.*high+(1-weight).*low;
    doubleArray(electrons,configuration.sensor.image_size,'observed merged electrons');
    close(merged.weight_high,weight,12,'observed merge weights');
    if any(merged.weight_high(:) < 0 | merged.weight_high(:) > 1) || ...
            any(merged.weight_high(weight == 1) ~= 1)
        error('ALEV4:StructuredSemanticMismatch','Merge weights violate bounds or exact endpoint selection.');
    end
    close(merged.electrons,electrons,16,'observed merged electrons');
    valid = high_usable | low_usable;
    exact(merged.high_usable,high_usable,'merged high usability');
    exact(merged.low_usable,low_usable,'merged low usability');
    exact(merged.valid,valid,'merged validity');
end

function validateSpatial(result,sensor,mode)
    baseline = result.spatial_baseline;
    names = {'schema_version','readout_mode','input_stage','input_irradiance', ...
        'input_grid','geometry','configuration','psf','optical_irradiance', ...
        'optical_grid','sampled_irradiance','readout','operation_order', ...
        'spatial_provenance','optical_report','sampling_report','synthetic','calibrated_alev4'};
    fields(baseline,names,'complete legacy spatial baseline');
    exact(baseline.geometry,result.geometry,'spatial geometry association');
    exact(baseline.configuration,result.configuration,'spatial configuration association');
    text(baseline.readout_mode,mode,'spatial readout association');
    text(result.spatial_baseline_role,'verification_context_only','spatial baseline role');
    fields(baseline.input_grid,fieldnames(alev4.createSpatialGrid()),'spatial input grid');
    fields(baseline.optical_grid,fieldnames(alev4.createSpatialGrid()),'spatial optical grid');
    exact(baseline.input_grid,alev4.createSpatialGrid(baseline.input_grid),'canonical input grid');
    exact(baseline.optical_grid,alev4.createSpatialGrid(baseline.optical_grid),'canonical optical grid');
    bands = numel(sensor.wavelength_nm);
    doubleArray(baseline.input_irradiance, ...
        [numel(baseline.input_grid.y_edges_m)-1 numel(baseline.input_grid.x_edges_m)-1 bands], ...
        'spatial input irradiance');
    doubleArray(baseline.optical_irradiance, ...
        [numel(baseline.optical_grid.y_edges_m)-1 numel(baseline.optical_grid.x_edges_m)-1 bands], ...
        'spatial optical irradiance');
    exact(baseline.sampled_irradiance,result.input_irradiance,'spatial sampled-input association');
    % The existing spatial validator recomputes optics, sampling and spectral
    % association. false is essential: no legacy stochastic replay is used.
    validated = alev4.spatialValidateResult(baseline,false);
    exact(baseline,validated,'canonical complete spatial baseline');
    exact(result.spatial_operation_order, ...
        [baseline.operation_order(1:end-2) result.operation_order],'spatial operation order');
    if strcmp(baseline.input_stage,'pre_psf')
        [~,~,optical_report] = alev4.applyOpticalPsf(baseline.input_irradiance, ...
            baseline.input_grid,baseline.psf,sensor.wavelength_nm);
    else
        optical_report = struct('operation','none','reason','input_already_post_optics');
    end
    exact(baseline.optical_report,optical_report,'optical report');
    [~,sampling_report] = alev4.resampleSensorIrradiance( ...
        baseline.optical_irradiance,baseline.optical_grid,baseline.geometry);
    validateSamplingReport(baseline.sampling_report,sampling_report, ...
        numel(baseline.optical_irradiance));
    validateLegacyReadout(baseline.readout,result.readout, ...
        result.baseline_expected_electrons,result.configuration,mode);
end

function validateLegacyReadout(readout,structured,expected,configuration,mode)
    names = {'expected_electrons','collected_electrons','charge_electrons', ...
        'full_well_saturated','seed','expected_incident_photons','exposure_s', ...
        'input_units','spectral_bin_convention'};
    if strcmp(mode,'dual')
        fields(readout,[names {'high_gain','low_gain','merged','reconstruction_valid'}],'legacy dual readout');
        sensor = configuration.sensor;
    else
        fields(readout,[names pathFields(false)],'legacy single readout');
        sensor = configuration;
    end
    exact(readout.exposure_s,structured.exposure_s,'legacy exposure association');
    exact(readout.seed,structured.seed,'legacy seed association');
    exact(readout.input_units,structured.input_units,'legacy input units');
    exact(readout.spectral_bin_convention,structured.spectral_bin_convention,'legacy spectral convention');
    exact(readout.expected_electrons,expected,'legacy baseline expectation association');
    exact(readout.expected_incident_photons,structured.expected_incident_photons,'legacy incident association');
    charge(readout.collected_electrons,expected,sensor.shot_noise,'legacy photo charge');
    stored = min(readout.collected_electrons,sensor.full_well_e);
    saturated = readout.collected_electrons >= sensor.full_well_e;
    exact(readout.charge_electrons,stored,'legacy physical well');
    exact(readout.full_well_saturated,saturated,'legacy physical saturation');
    if strcmp(mode,'dual')
        for name = {'high_gain','low_gain'}
            path = readout.(name{1}); config = configuration.(name{1});
            fields(path,pathFields(false),['legacy ' name{1}]);
            validatePath(path,stored,config,false,config.read_noise_e == 0,['legacy ' name{1}]);
        end
        valid = validateMerge(readout.merged,readout.high_gain.raw_dn,readout.low_gain.raw_dn,configuration);
        exact(readout.reconstruction_valid,valid & ~saturated,'legacy reconstruction validity');
    else
        validatePath(readout,stored,sensor,false,sensor.read_noise_e == 0,'legacy single');
    end
end

function validateRuntime(runtime)
    fields(runtime,{'name','version'},'runtime');
    if ~ischar(runtime.name) || ~isrow(runtime.name) || ...
            ~any(strcmp(runtime.name,{'GNU Octave','MATLAB'})) || ...
            ~ischar(runtime.version) || ~isrow(runtime.version) || ...
            isempty(strtrim(runtime.version)) || numel(runtime.version) > 256 || ...
            any(double(runtime.version) < 32 | double(runtime.version) > 126)
        error('ALEV4:InvalidStructuredResult','A supported runtime and explicit version are required.');
    end
end

function fields(value,names,label)
    alev4.spatialBundleUtil('fields',value,names,label);
end

function text(value,expected,label)
    alev4.spatialBundleUtil('text',value,expected,label);
end

function scalar(value,low,high,integer,label)
    doubleArray(value,[1 1],label);
    alev4.spatialBundleUtil('scalar',value,low,high,integer,label);
end

function doubleArray(value,dimensions,label)
    while numel(dimensions) > 2 && dimensions(end) == 1, dimensions(end) = []; end
    if ~isa(value,'double') || ~isreal(value) || issparse(value) || ...
            ~isequal(size(value),dimensions) || any(~isfinite(value(:)))
        error('ALEV4:InvalidStructuredResult','%s must be a dense finite double of its exact declared shape.',label);
    end
end

function exact(actual,expected,label)
    if isstruct(expected)
        fields(actual,fieldnames(expected),label);
        names = fieldnames(expected);
        for k = 1:numel(names), exact(actual.(names{k}),expected.(names{k}),[label '.' names{k}]); end
    elseif iscell(expected)
        if ~iscell(actual) || ~isequal(size(actual),size(expected))
            error('ALEV4:InvalidStructuredResult','%s has an invalid cell shape or type.',label);
        end
        for k = 1:numel(expected), exact(actual{k},expected{k},label); end
    else
        if ~isa(actual,class(expected)) || ~isequal(size(actual),size(expected)) || ...
                ((isnumeric(actual) || islogical(actual)) && ...
                (~isreal(actual) || issparse(actual) || any(~isfinite(actual(:))))) || ...
                ~isequal(actual,expected)
            error('ALEV4:StructuredSemanticMismatch','%s disagrees in type, shape or value.',label);
        end
    end
end

function close(actual,expected,operations,label)
    doubleArray(actual,size(expected),label);
    alev4.spatialBundleUtil('close',actual,expected,operations,label);
end

function validateSamplingReport(actual,expected,operations)
    fields(actual,fieldnames(expected),'sampling report');
    names = fieldnames(expected);
    integrals = {'source_integral','source_crop_integral','target_integral'};
    for k = 1:numel(names)
        name = names{k};
        label = ['sampling report.' name];
        if any(strcmp(name,integrals))
            fields(actual.(name),{'status','values'},label);
            exact(actual.(name).status,expected.(name).status,[label ' status']);
            close(actual.(name).values,expected.(name).values,operations,[label ' values']);
        elseif any(strcmp(name,{'x_max_row_sum_error','y_max_row_sum_error'}))
            close(actual.(name),expected.(name),operations,label);
        else
            exact(actual.(name),expected.(name),label);
        end
    end
end

function value = product(left,right,label)
    value = bsxfun(@times,left,right);
    nonzero = bsxfun(@and,left ~= 0,right ~= 0);
    if any(value(nonzero) == 0)
        error('ALEV4:StructuredSemanticMismatch','%s erased nonzero product support.',label);
    end
    normal(value,label);
end

function value = add(left,right,label)
    value = bsxfun(@plus,left,right);
    normal(value,label);
end

function normal(value,label)
    if any(~isfinite(value(:))) || any(value(:) ~= 0 & abs(value(:)) < realmin)
        error('ALEV4:StructuredSemanticMismatch','%s is outside the supported normal finite range.',label);
    end
end

function count = numericCount(value)
    count = 0;
    if isnumeric(value) || islogical(value)
        count = numel(value);
    elseif isstruct(value)
        names = fieldnames(value);
        for k = 1:numel(names), count = count+numericCount(value.(names{k})); end
    elseif iscell(value)
        for k = 1:numel(value), count = count+numericCount(value{k}); end
    end
end
