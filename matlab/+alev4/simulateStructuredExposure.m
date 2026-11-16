function result = simulateStructuredExposure(input, readout, exposure_s, frame_seed, model, geometry)
%SIMULATESTRUCTUREDEXPOSURE One exposure with explicit persistent noise maps.
%   RESULT = alev4.simulateStructuredExposure(INPUT, READOUT, EXPOSURE_S,
%   FRAME_SEED, MODEL, GEOMETRY) validates an already geometry-bound single
%   or dual configuration. INPUT is spectral bin-average photon irradiance
%   [photons m^-2 s^-1 nm^-1]. MODEL is separate from the readout schema.
%
%   Disabled models directly return the unchanged corresponding legacy
%   result. Enabled models have a distinct result identity and stream policy:
%   spectral integration -> PRNU and dark expectations -> separately seeded
%   photo/dark sampling -> charge sum -> one physical full well -> shared
%   electronics -> path electronics and pixel read noise -> gain/black ->
%   round/ADC -> observed-channel dual merge, where applicable.
%
%   All retained component values are electrons. Row/column/frame draws have
%   shapes H-by-1, 1-by-W and scalar; fixed/pixel/total arrays are H-by-W.
%   Each component.total_e is summed fixed, row, column, frame, then pixel.
%   Each signed readout is (stored + shared.total_e) + path.total_e. Charge
%   stays physical; negative signed electronics are never clipped to the well.
%   readout.expected_electrons is TOTAL expected photo-plus-dark charge, so
%   neither it nor PRNU-scaled photocharge is bounded by incident photons.
%
%   Caller RNG is restored on success and every failure. Each nonzero random
%   component additionally saves/restores a local Twister state at its named
%   seed. Zero components cannot perturb other enabled-model streams. Only
%   same-runtime/version reproducibility is promised. Supplied fixed maps
%   are assumed synthetic parameters, not measured sensor calibration.
    if nargin ~= 6
        error('ALEV4:StructuredExposureArguments', ...
            'Input, readout, exposure, frame seed, noise model, and geometry are required.');
    end
    caller_rng = rng;
    rng_guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    geometry = alev4.createSensorGeometry(geometry);
    configuration = alev4.bindSensorGeometry(readout, geometry, 'validate');
    model = alev4.createStructuredNoise(geometry.full_grid_size, model);
    % Validate even the disabled wrapper's seed against the documented range;
    % the helper consumes no randomness and does not alter a valid input.
    alev4.structuredNoiseSeed(frame_seed, 'photo');
    if strcmp(configuration.schema_version, '2.0')
        sensor = configuration.sensor;
        mode = 'dual';
    else
        sensor = configuration;
        mode = 'single';
    end

    % The whole disabled result is exactly the legacy result: no wrapper
    % fields, component seeds, extra draws, or altered readout arithmetic.
    if ~model.enabled
        if strcmp(mode, 'dual')
            result = alev4.simulateDualGainExposure( ...
                input, configuration, exposure_s, frame_seed);
        else
            result = alev4.simulateExposure( ...
                input, configuration, exposure_s, frame_seed);
        end
        return;
    end

    seeds = componentSeeds(frame_seed); % Validate before numerical work.
    frame_seed = seeds.frame;
    if prod(sensor.image_size) > 1e8 / numel(sensor.wavelength_nm)
        error('ALEV4:StructuredNoiseSize', ...
            'Retained structured irradiance supports at most 100 million numeric samples.');
    end
    % A structured result retains many diagnostic planes. Bound their total
    % reservation before expanding scalar maps or sampling charge; an input
    % cube limit alone would permit multi-gigabyte intermediate allocations.
    % The conservative 64 values/pixel includes all single/dual maps,
    % components, flags and readouts, plus compact row/column terms.
    fixed_samples = numericSamples(model) + numericSamples(configuration) + ...
        numericSamples(geometry);
    samples_per_pixel = 64 + numel(sensor.wavelength_nm);
    if fixed_samples > 1e8 || ...
            prod(sensor.image_size) > (1e8-fixed_samples)/samples_per_pixel
        error('ALEV4:StructuredNoiseSize', ...
            'Structured retained arrays exceed the 100 million sample reservation.');
    end
    maps = alev4.structuredNoiseMaps(model, geometry);
    [baseline, incident, exposure_s] = ...
        alev4.integrateExposure(input, sensor, exposure_s);
    input = double(input);
    if issparse(input), input = full(input); end
    checkBaselineRange(input, sensor, exposure_s, baseline, incident);
    expected_photo = checkedProduct(maps.prnu, baseline, 'PRNU-scaled photo expectation');
    expected_dark = checkedProduct( ...
        maps.dark_current_e_per_s, exposure_s, 'dark-current expectation');
    expected = checkedSum(expected_photo, expected_dark, 'total expected charge');
    % Validate both Poisson ranges before either stream is sampled.
    checkPoissonRange(expected_photo, sensor.shot_noise);
    checkPoissonRange(expected_dark, model.dark_shot_noise);
    checkElectronics(maps.shared, 0, 'shared');
    if strcmp(mode, 'dual')
        checkElectronics(maps.high_gain, configuration.high_gain.read_noise_e, 'high_gain');
        checkElectronics(maps.low_gain, configuration.low_gain.read_noise_e, 'low_gain');
    else
        checkElectronics(maps.single, sensor.read_noise_e, 'single');
    end

    photo = sampleCharge(expected_photo, sensor.shot_noise, seeds.photo);
    dark = sampleCharge(expected_dark, model.dark_shot_noise, seeds.dark);
    collected = checkedSum(photo, dark, 'sampled photo-plus-dark charge');
    stored = min(collected, sensor.full_well_e);
    components = struct('photo_electrons', photo, 'dark_electrons', dark);
    components.shared = electronicComponents( ...
        maps.shared, 0, sensor.image_size, seeds, 'shared');
    shared_read = checkedSum(stored, components.shared.total_e, 'shared signed readout');

    observed = struct('expected_electrons', expected, ...
        'expected_photoelectrons', expected_photo, ...
        'expected_dark_electrons', expected_dark, ...
        'collected_electrons', collected, 'charge_electrons', stored, ...
        'full_well_saturated', collected >= sensor.full_well_e, ...
        'seed', frame_seed, 'expected_incident_photons', incident, ...
        'exposure_s', exposure_s, ...
        'input_units', 'photons m^-2 s^-1 nm^-1', ...
        'spectral_bin_convention', 'bin-average density times explicit width in nm');
    if strcmp(mode, 'dual')
        components.high_gain = electronicComponents(maps.high_gain, ...
            configuration.high_gain.read_noise_e, sensor.image_size, seeds, 'high');
        components.low_gain = electronicComponents(maps.low_gain, ...
            configuration.low_gain.read_noise_e, sensor.image_size, seeds, 'low');
        observed.high_gain = readPath(shared_read, ...
            components.high_gain.total_e, configuration.high_gain);
        observed.low_gain = readPath(shared_read, ...
            components.low_gain.total_e, configuration.low_gain);
        % Only the recorded channels and canonical electronics reach merge.
        observed.merged = alev4.mergeDualGain( ...
            observed.high_gain.raw_dn, observed.low_gain.raw_dn, configuration);
        observed.reconstruction_valid = ...
            observed.merged.valid & ~observed.full_well_saturated;
    else
        components.single = electronicComponents(maps.single, ...
            sensor.read_noise_e, sensor.image_size, seeds, 'single');
        single = readPath(shared_read, components.single.total_e, sensor);
        names = fieldnames(single);
        for k = 1:numel(names), observed.(names{k}) = single.(names{k}); end
        observed.reconstruction_valid = ...
            observed.adc_usable & ~observed.full_well_saturated;
    end

    order = {'spectral_integration', 'prnu_response', 'dark_expectation', ...
        'separate_photo_dark_sampling', 'charge_sum', 'physical_full_well', ...
        'shared_electronics', 'path_electronics_and_pixel_read_noise', ...
        'gain_and_black', 'round', 'adc_clip'};
    if strcmp(mode, 'dual'), order{end+1} = 'observed_channel_merge'; end
    units = struct('input_irradiance', 'photons m^-2 s^-1 nm^-1', ...
        'expected_incident_photons', 'photons', 'charge', 'electrons', ...
        'components', 'electrons', 'read_electrons', 'electrons', ...
        'raw_dn', 'DN', 'exposure_s', 's', ...
        'dark_current_e_per_s', 'electrons s^-1', 'prnu', 'dimensionless');
    runtime_name = 'MATLAB';
    if exist('OCTAVE_VERSION', 'builtin'), runtime_name = 'GNU Octave'; end
    result = struct('format', 'ALEV4-SYNTHETIC-STRUCTURED-NOISE', ...
        'schema_version', '1.0', 'result_kind', 'exposure', ...
        'readout_mode', mode, 'configuration', configuration, ...
        'geometry', geometry, 'noise_model', model, ...
        'input_irradiance', input, 'baseline_expected_electrons', baseline, ...
        'active_maps', maps, 'components', components, 'readout', observed, ...
        'operation_order', {order}, 'seeds', seeds, ...
        'seed_policy', 'component_seed = mod(frame_seed + tag, 2^32); locally saved/restored Twister', ...
        'stream_scope', 'same runtime/version; no cross-runtime stream identity claim', ...
        'runtime', struct('name', runtime_name, 'version', version()), ...
        'units', units, 'parameter_classification', 'assumed', ...
        'temperature_condition', struct( ...
            'reference_temperature_K', model.reference_temperature_K, ...
            'policy', 'declared applicability only; no temperature law or extrapolation'), ...
        'synthetic', true, 'calibrated_alev4', false);
end

function count = numericSamples(value)
    if isnumeric(value) || islogical(value)
        count = numel(value);
    elseif isstruct(value)
        count = 0;
        fields = fieldnames(value);
        for j = 1:numel(value)
            for k = 1:numel(fields)
                count = count + numericSamples(value(j).(fields{k}));
            end
        end
    elseif iscell(value)
        count = 0;
        for k = 1:numel(value), count = count + numericSamples(value{k}); end
    else
        count = 0;
    end
end

function seeds = componentSeeds(frame_seed)
    % All schedule entries are retained, including inactive readout paths.
    names = {'photo','dark','shared_row','shared_column','shared_frame', ...
        'single_row','single_column','single_frame','single_pixel', ...
        'high_row','high_column','high_frame','high_pixel', ...
        'low_row','low_column','low_frame','low_pixel'};
    photo_seed = alev4.structuredNoiseSeed(frame_seed, 'photo');
    seeds = struct('frame', full(double(frame_seed)), 'photo', photo_seed);
    for k = 2:numel(names)
        seeds.(names{k}) = alev4.structuredNoiseSeed(frame_seed, names{k});
    end
end

function checkBaselineRange(input, sensor, exposure_s, baseline, incident)
    requireNormal(baseline, 'baseline photo expectation');
    requireNormal(incident, 'incident-photon expectation');
    if exposure_s == 0 || sensor.fill_factor == 0 || ~any(input(:) > 0)
        return;
    end
    % Earlier APIs retain their own arithmetic contract. The enabled model
    % additionally refuses positive spectral support erased to exact zero.
    incident_support = any(input > 0, 3);
    if any(incident(incident_support) == 0)
        error('ALEV4:StructuredNoiseUnderflow', ...
            'Positive incident-photon support underflowed during spectral integration.');
    end
    channels = alev4.cfaMap(sensor.image_size, sensor.cfa_pattern);
    for channel = 1:3
        support = false(sensor.image_size);
        for band = 1:numel(sensor.wavelength_nm)
            if sensor.qe(band, channel) > 0
                support = support | input(:,:,band) > 0;
            end
        end
        support = support & channels == channel;
        if any(baseline(support) == 0)
            error('ALEV4:StructuredNoiseUnderflow', ...
                'Positive photoelectron support underflowed during spectral integration.');
        end
    end
end

function checkPoissonRange(expected, enabled)
    if enabled && any(expected(:) > 1e9)
        error('ALEV4:InvalidPoissonMean', ...
            'Enabled photo and dark Poisson expectations must each lie in [0, 1e9].');
    end
end

function checkElectronics(component, pixel_sigma, label)
    requireNormal(component.fixed_offset_e, [label ' fixed offset']);
    requireNormal([component.row_noise_e, component.column_noise_e, ...
        component.frame_noise_e, pixel_sigma], [label ' electronic RMS']);
end

function values = sampleCharge(expected, enabled, seed)
    if ~enabled || ~any(expected(:) > 0)
        values = expected;
        return;
    end
    previous_rng = rng;
    restore_rng = onCleanup(@() rng(previous_rng)); %#ok<NASGU>
    rng(seed, 'twister');
    values = alev4.samplePoisson(expected);
end

function component = electronicComponents(maps, pixel_sigma, image_size, seeds, prefix)
    row = gaussianComponent(maps.row_noise_e, [image_size(1) 1], ...
        seeds.([prefix '_row']), [prefix ' row component']);
    column = gaussianComponent(maps.column_noise_e, [1 image_size(2)], ...
        seeds.([prefix '_column']), [prefix ' column component']);
    frame = gaussianComponent(maps.frame_noise_e, [1 1], ...
        seeds.([prefix '_frame']), [prefix ' frame component']);
    if strcmp(prefix, 'shared')
        pixel = zeros(image_size);
    else
        pixel = gaussianComponent(pixel_sigma, image_size, ...
            seeds.([prefix '_pixel']), [prefix ' pixel component']);
    end
    total = checkedSum(maps.fixed_offset_e, row, [prefix ' fixed plus row']);
    total = checkedSum(total, column, [prefix ' plus column']);
    total = checkedSum(total, frame, [prefix ' plus frame']);
    total = checkedSum(total, pixel, [prefix ' plus pixel']);
    component = struct('fixed_offset_e', maps.fixed_offset_e, ...
        'row_e', row, 'column_e', column, 'frame_e', frame, ...
        'pixel_e', pixel, 'total_e', total);
end

function values = gaussianComponent(sigma, dimensions, seed, label)
    if sigma == 0
        values = zeros(dimensions);
        return;
    end
    previous_rng = rng;
    restore_rng = onCleanup(@() rng(previous_rng)); %#ok<NASGU>
    rng(seed, 'twister');
    values = checkedProduct(sigma, randn(dimensions), label);
end

function path = readPath(shared_read, path_component, configuration)
    signed = checkedSum(shared_read, path_component, 'path signed readout');
    gained = checkedProduct(signed, configuration.gain_dn_per_e, 'electronic DN gain');
    analog = checkedSum(gained, configuration.black_level_dn, 'black-offset DN');
    rounded = round(analog);
    maximum = 2 ^ configuration.adc_bits - 1;
    raw = uint16(min(max(rounded, 0), maximum));
    path = struct('read_electrons', signed, 'raw_dn', raw, ...
        'adc_low_clipped', rounded < 0, 'adc_high_clipped', rounded > maximum, ...
        'adc_usable', raw > 0 & double(raw) < maximum);
end

function value = checkedProduct(left, right, label)
    value = bsxfun(@times, left, right);
    if any(~isfinite(value(:)))
        error('ALEV4:StructuredNoiseOverflow', '%s exceeds the finite numeric range.', label);
    end
    nonzero = bsxfun(@and, left ~= 0, right ~= 0);
    if any(value(nonzero) == 0)
        error('ALEV4:StructuredNoiseUnderflow', '%s erased a nonzero product.', label);
    end
    requireNormal(value, label);
end

function value = checkedSum(left, right, label)
    value = bsxfun(@plus, left, right);
    if any(~isfinite(value(:)))
        error('ALEV4:StructuredNoiseOverflow', '%s exceeds the finite numeric range.', label);
    end
    requireNormal(value, label);
end

function requireNormal(value, label)
    if any(value(:) ~= 0 & abs(value(:)) < realmin)
        error('ALEV4:StructuredNoiseUnderflow', ...
            '%s enters an unsupported nonzero subnormal arithmetic range.', label);
    end
end
