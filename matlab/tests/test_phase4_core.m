function report = test_phase4_core()
%TEST_PHASE4_CORE Independent exact stage, transfer and clipping oracles.
%   Small asymmetric fixtures use exactly representable binary fractions.
%   Expectations below are hand-calculated; the scalar ADC oracle uses
%   signed floor of absolute values, not the production round operation.
    caller_rng = rng;
    guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    names = {'independent_scalar_stage_oracle', ...
        'single_gain_transfer_and_signed_quantization', ...
        'dark_only_saturation_and_shared_well', ...
        'zero_exposure_fill_and_prnu', ...
        'fixed_offsets_after_well_and_gain_black_once', ...
        'fixed_map_crop_exposure_identity', ...
        'disabled_whole_result_identity', ...
        'distinct_adc_physical_and_reconstruction_masks', ...
        'raw_only_merge_transition_oracle', ...
        'arithmetic_failures_and_rng_restoration', ...
        'deterministic_wrong_model_controls'};
    fixture = testScalarStages();
    testSingleTransfer();
    testDarkAndWell();
    testZeroEndpoints();
    testOffsetPlacement();
    crop_cases = testCropExposure();
    disabled_cases = testDisabledIdentity();
    testMasks();
    testObservedMerge();
    error_cases = testArithmeticAndIsolation();
    controls = testWrongModels(fixture);
    tests = repmat(struct('name', '', 'status', 'passed', 'passed', true), ...
        1, numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    metrics = struct('scalar_oracle_size', [2 3], 'exact_comparison_tolerance', 0, ...
        'deterministic_crop_cases', crop_cases, ...
        'disabled_whole_result_cases', disabled_cases, ...
        'rejected_numerical_and_input_cases', error_cases, ...
        'wrong_model_controls', {controls}, 'wrong_model_rejections', numel(controls));
    report = struct('suite', 'phase4_core', 'status', 'passed', ...
        'passed', true, 'test_count', numel(names), 'tests', tests, 'metrics', metrics);
    fprintf('PASS: Phase 4 deterministic core, %d test groups.\n', numel(names));
end

function fixture = testScalarStages()
    [configuration, geometry] = quietDual([2 3], 20);
    geometry.pixel_pitch_m = .5;
    configuration.sensor.pixel_pitch_m = .5;
    configuration.sensor.fill_factor = .5;
    configuration.sensor.bin_width_nm = 4;
    configuration.sensor.qe = [1 .5 .25];
    input = [16 32 48; 64 80 96];
    model = alev4.createStructuredNoise([2 3], struct( ...
        'prnu', [0 .5 1; 1.25 1.5 2], ...
        'dark_current_e_per_s', [2 4 6; 8 10 12], 'dark_shot_noise', false, ...
        'shared', struct('fixed_offset_e', [-2 .5 3; 1 -.5 2]), ...
        'high_gain', struct('fixed_offset_e', [.25 -1 0; -2 .5 1]), ...
        'low_gain', struct('fixed_offset_e', [-.5 1 -3; 1 2 -1])));
    input_copy = input; cfg_copy = configuration; model_copy = model; geometry_copy = geometry;
    result = alev4.simulateStructuredExposure(input, configuration, .5, 47101, model, geometry);
    % At t=.5 s, area=.25 m^2, fill=.5 and width=4 nm, incident
    % conversion is 1/4. RGGB QE gives R=1/4, G=1/8 and B=1/16 e
    % per input unit, independently of any production integration helper.
    baseline = [4 4 12; 8 5 12];
    incident = [4 8 12; 16 20 24];
    photo = [0 2 12; 10 7.5 24];
    dark = [1 2 3; 4 5 6];
    total = [1 4 15; 14 12.5 30];
    stored = [1 4 15; 14 12.5 20];
    high = [-.75 3.5 18; 13 12.5 23];
    low = [-1.5 5.5 15; 16 14 21];
    observed = result.readout;
    assert(isequal(result.baseline_expected_electrons, baseline));
    assert(isequal(observed.expected_incident_photons, incident));
    assert(isequal(observed.expected_photoelectrons, photo));
    assert(isequal(observed.expected_dark_electrons, dark));
    assert(isequal(observed.expected_electrons, total));
    assert(isequal(result.components.photo_electrons, photo));
    assert(isequal(result.components.dark_electrons, dark));
    assert(isequal(observed.collected_electrons, total));
    assert(isequal(observed.charge_electrons, stored));
    assert(isequal(observed.full_well_saturated, logical([0 0 0; 0 0 1])));
    assert(isequal(observed.high_gain.read_electrons, high));
    assert(isequal(observed.low_gain.read_electrons, low));
    assert(isequal(observed.high_gain.raw_dn, uint16([3 11 40; 30 29 50])));
    assert(isequal(observed.low_gain.raw_dn, uint16([8 11 16; 17 16 19])));
    assertPath(observed.high_gain, high, 2, 4.25, 6);
    assertPath(observed.low_gain, low, .5, 8.5, 6);
    assertZeroTemporal(result.components.shared, model.shared.fixed_offset_e, [2 3]);
    assertZeroTemporal(result.components.high_gain, model.high_gain.fixed_offset_e, [2 3]);
    assertZeroTemporal(result.components.low_gain, model.low_gain.fixed_offset_e, [2 3]);
    assert(isequal(result.active_maps.prnu, model.prnu));
    assert(observed.expected_electrons(2,3) > observed.expected_incident_photons(2,3));
    assert(observed.high_gain.read_electrons(2,3) > configuration.sensor.full_well_e);
    assert(all(observed.merged.valid(:)) && ...
        isequal(observed.reconstruction_valid, logical([1 1 1; 1 1 0])));
    expected_order = {'spectral_integration', 'prnu_response', 'dark_expectation', ...
        'separate_photo_dark_sampling', 'charge_sum', 'physical_full_well', ...
        'shared_electronics', 'path_electronics_and_pixel_read_noise', ...
        'gain_and_black', 'round', 'adc_clip', 'observed_channel_merge'};
    assert(isequal(result.operation_order, expected_order));
    assert(strcmp(result.format, 'ALEV4-SYNTHETIC-STRUCTURED-NOISE') && ...
        strcmp(result.schema_version, '1.0') && strcmp(result.readout_mode, 'dual'));
    assert(result.synthetic && ~result.calibrated_alev4 && ...
        strcmp(result.parameter_classification, 'assumed'));
    assert(strcmp(result.units.raw_dn, 'DN') && strcmp(result.units.charge, 'electrons') && ...
        strcmp(result.units.dark_current_e_per_s, 'electrons s^-1'));
    assert(isequal(input, input_copy) && isequal(configuration, cfg_copy) && ...
        isequal(model, model_copy) && isequal(geometry, geometry_copy));
    fixture = struct('result', result, 'baseline', baseline, 'photo', photo, ...
        'dark', dark, 'total', total, 'stored', stored, 'high', high, 'low', low);
end

function testSingleTransfer()
    [configuration, geometry] = quietSingle([2 4], 100);
    configuration.gain_dn_per_e = 2;
    configuration.black_level_dn = 2.25;
    configuration.adc_bits = 4;
    signed = [-1.875 -1.375 -1.25 -1.125; -.875 6.125 6.5 6.625];
    model = alev4.createStructuredNoise([2 4], struct('dark_shot_noise', false, ...
        'single', struct('fixed_offset_e', signed)));
    result = alev4.simulateStructuredExposure(zeros(2,4), configuration, 1, 47102, model, geometry);
    observed = result.readout;
    % Analog DN = [-1.5 -.5 -.25 0; .5 14.5 15.25 15.5].
    % The exact half ties below zero must round away from zero, even
    % though both a rounded negative and a rounded zero emit RAW code 0.
    assert(isequal(observed.raw_dn, uint16([0 0 0 0; 1 15 15 15])));
    assert(isequal(observed.adc_low_clipped, logical([1 1 0 0; 0 0 0 0])));
    assert(isequal(observed.adc_high_clipped, logical([0 0 0 0; 0 0 0 1])));
    assert(isequal(observed.adc_usable, logical([0 0 0 0; 1 0 0 0])));
    assert(isequal(observed.reconstruction_valid, observed.adc_usable));
    assert(~any(observed.full_well_saturated(:)));
    assertPath(observed, signed, 2, 2.25, 4);
    assert(strcmp(result.readout_mode, 'single') && ...
        strcmp(result.operation_order{end}, 'adc_clip'));
end

function testDarkAndWell()
    [configuration, geometry] = quietDual([1 4], 20);
    model = alev4.createStructuredNoise([1 4], struct('dark_shot_noise', false, ...
        'dark_current_e_per_s', [0 10 20 30]));
    result = alev4.simulateStructuredExposure(zeros(1,4), configuration, 1, 47103, model, geometry);
    observed = result.readout;
    assert(isequal(result.baseline_expected_electrons, zeros(1,4)));
    assert(isequal(observed.expected_photoelectrons, zeros(1,4)));
    assert(isequal(observed.expected_dark_electrons, [0 10 20 30]));
    assert(isequal(observed.charge_electrons, [0 10 20 20]));
    assert(isequal(observed.full_well_saturated, logical([0 0 1 1])));
    assert(isequal(observed.high_gain.read_electrons, observed.charge_electrons));
    assert(isequal(observed.low_gain.read_electrons, observed.charge_electrons));
    assert(all(observed.merged.valid) && ...
        isequal(observed.reconstruction_valid, logical([1 1 0 0])));
    model.dark_current_e_per_s = [0 12 17 8];
    mixed = alev4.simulateStructuredExposure([0 12 5 16], configuration, 1, 47103, model, geometry);
    assert(isequal(mixed.components.photo_electrons, [0 12 5 16]));
    assert(isequal(mixed.components.dark_electrons, [0 12 17 8]));
    assert(isequal(mixed.readout.collected_electrons, [0 24 22 24]));
    assert(isequal(mixed.readout.charge_electrons, [0 20 20 20]), ...
        'Photo and dark electrons must share one physical well.');
end

function testZeroEndpoints()
    [configuration, geometry] = quietDual([2 3], 100);
    model = alev4.createStructuredNoise([2 3], struct('dark_shot_noise', false, ...
        'prnu', [0 .5 1; 1.25 1.5 2], 'dark_current_e_per_s', [2 4 6; 8 10 12], ...
        'shared', struct('fixed_offset_e', 1), ...
        'high_gain', struct('fixed_offset_e', 2), ...
        'low_gain', struct('fixed_offset_e', 3)));
    half = alev4.simulateStructuredExposure(4*ones(2,3), configuration, .5, 47104, model, geometry);
    twice = alev4.simulateStructuredExposure(4*ones(2,3), configuration, 2, 47105, model, geometry);
    assert(isequal(half.readout.expected_photoelectrons, [0 1 2; 2.5 3 4]));
    assert(isequal(half.readout.expected_dark_electrons, [1 2 3; 4 5 6]));
    assert(isequal(twice.readout.expected_photoelectrons, [0 4 8; 10 12 16]));
    assert(isequal(twice.readout.expected_dark_electrons, [4 8 12; 16 20 24]));
    assert(half.readout.expected_photoelectrons(1,1) == 0 && ...
        half.readout.expected_dark_electrons(1,1) == 1);
    assert(isequal(half.active_maps.prnu, model.prnu));
    no_fill = configuration; no_fill.sensor.fill_factor = 0;
    dark = alev4.simulateStructuredExposure(4*ones(2,3), no_fill, .5, 47104, model, geometry);
    assert(isequal(dark.baseline_expected_electrons, zeros(2,3)));
    assert(isequal(dark.readout.expected_dark_electrons, [1 2 3; 4 5 6]));
    assert(isequal(dark.readout.charge_electrons, [1 2 3; 4 5 6]));
    zero = alev4.simulateStructuredExposure(realmax*ones(2,3), configuration, 0, 47104, model, geometry);
    assert(isequal(zero.readout.expected_photoelectrons, zeros(2,3)));
    assert(isequal(zero.readout.expected_dark_electrons, zeros(2,3)));
    assert(isequal(zero.readout.charge_electrons, zeros(2,3)));
    assert(isequal(zero.readout.high_gain.read_electrons, 3*ones(2,3)));
    assert(isequal(zero.readout.low_gain.read_electrons, 4*ones(2,3)));
    zero_prnu = model; zero_prnu.prnu = 0;
    unresponsive = alev4.simulateStructuredExposure(4*ones(2,3), configuration, .5, 47104, zero_prnu, geometry);
    assert(isequal(unresponsive.readout.expected_photoelectrons, zeros(2,3)));
    assert(isequal(unresponsive.readout.expected_dark_electrons, [1 2 3; 4 5 6]));
    double_prnu = model; double_prnu.prnu = 2;
    doubled = alev4.simulateStructuredExposure(4*ones(2,3), configuration, .5, 47104, double_prnu, geometry);
    assert(isequal(doubled.readout.expected_photoelectrons, 4*ones(2,3)), ...
        'A uniform nonunit PRNU map must not be normalized.');
    assert(isequal(doubled.readout.expected_dark_electrons, [1 2 3; 4 5 6]));
end

function testOffsetPlacement()
    [configuration, geometry] = quietDual([1 4], 20);
    model = alev4.createStructuredNoise([1 4], struct('dark_shot_noise', false, ...
        'shared', struct('fixed_offset_e', [1 -1 -2 2]), ...
        'high_gain', struct('fixed_offset_e', [2 -2 -3 3]), ...
        'low_gain', struct('fixed_offset_e', [-1 1 1 -1])));
    input = [40 40 0 0];
    first = alev4.simulateStructuredExposure(input, configuration, 1, 47106, model, geometry);
    other = alev4.simulateStructuredExposure(input, configuration, 1, 4294967295, model, geometry);
    assert(isequal(first.readout.charge_electrons, [20 20 0 0]));
    assert(isequal(first.readout.high_gain.read_electrons, [23 17 -5 5]));
    assert(isequal(first.readout.low_gain.read_electrons, [20 20 -1 1]));
    assert(isequal(first.readout.full_well_saturated, logical([1 1 0 0])));
    assert(isequal(first.readout.high_gain.raw_dn, uint16([50 38 0 14])));
    assert(isequal(first.readout.low_gain.raw_dn, uint16([19 19 8 9])));
    assert(isequal(first.active_maps, other.active_maps) && ...
        isequal(first.components, other.components));
    assert(isequal(first.readout.high_gain, other.readout.high_gain) && ...
        isequal(first.readout.low_gain, other.readout.low_gain));
    changed = configuration;
    changed.high_gain.gain_dn_per_e = 4; changed.high_gain.black_level_dn = 7.25;
    changed.low_gain.gain_dn_per_e = 1; changed.low_gain.black_level_dn = 10.5;
    gained = alev4.simulateStructuredExposure(input, changed, 1, 47106, model, geometry);
    assert(isequal(gained.readout.high_gain.read_electrons, [23 17 -5 5]));
    assert(isequal(gained.readout.low_gain.read_electrons, [20 20 -1 1]));
    assert(isequal(gained.readout.high_gain.raw_dn, uint16([63 63 0 27])));
    assert(isequal(gained.readout.low_gain.raw_dn, uint16([31 31 10 12])));
    assertPath(gained.readout.high_gain, [23 17 -5 5], 4, 7.25, 6);
    assertPath(gained.readout.low_gain, [20 20 -1 1], 1, 10.5, 6);
end

function count = testCropExposure()
    dims = [5 7];
    values = reshape(0:34, dims);
    input = (values+1)/4;
    model = alev4.createStructuredNoise(dims, struct('dark_shot_noise', false, ...
        'prnu', values/16, 'dark_current_e_per_s', (values+2)/8, ...
        'shared', struct('fixed_offset_e', (values-8)/16), ...
        'single', struct('fixed_offset_e', (12-values)/8), ...
        'high_gain', struct('fixed_offset_e', (12-values)/8), ...
        'low_gain', struct('fixed_offset_e', (values-5)/4)));
    count = 0;
    for mode = 1:2
        for pattern = {'RGGB', 'BGGR', 'GRBG', 'GBRG'}
            if mode == 1
                [configuration, geometry] = quietSingle(dims, 20);
                configuration.qe = [1 .5 .25];
            else
                [configuration, geometry] = quietDual(dims, 20);
                configuration.sensor.qe = [1 .5 .25];
            end
            geometry.full_grid_cfa_pattern = pattern{1};
            configuration = alev4.bindSensorGeometry(configuration, geometry, 'derive');
            full_result = alev4.simulateStructuredExposure(input, configuration, .5, 47107, model, geometry);
            for row = 1:2
                for column = 1:2
                    crop_geometry = geometry; crop_geometry.active_roi = [row column 3 4];
                    crop_configuration = alev4.bindSensorGeometry(configuration, crop_geometry, 'derive');
                    rr = row:row+2; cc = column:column+3;
                    crop = alev4.simulateStructuredExposure(input(rr,cc), crop_configuration, ...
                        .5, 47108, model, crop_geometry);
                    assertSlice(crop.baseline_expected_electrons, full_result.baseline_expected_electrons, rr, cc);
                    for field = {'expected_electrons', 'expected_photoelectrons', ...
                            'expected_dark_electrons', 'expected_incident_photons', ...
                            'collected_electrons', 'charge_electrons', ...
                            'full_well_saturated', 'reconstruction_valid'}
                        assertSlice(crop.readout.(field{1}), full_result.readout.(field{1}), rr, cc);
                    end
                    assertSlice(crop.components.photo_electrons, full_result.components.photo_electrons, rr, cc);
                    assertSlice(crop.components.dark_electrons, full_result.components.dark_electrons, rr, cc);
                    if mode == 1
                        assertPathSlice(crop.readout, full_result.readout, rr, cc);
                    else
                        assertPathSlice(crop.readout.high_gain, full_result.readout.high_gain, rr, cc);
                        assertPathSlice(crop.readout.low_gain, full_result.readout.low_gain, rr, cc);
                        for field = {'electrons', 'weight_high', 'valid', 'high_usable', 'low_usable'}
                            assertSlice(crop.readout.merged.(field{1}), full_result.readout.merged.(field{1}), rr, cc);
                        end
                    end
                    count = count+1;
                end
            end
        end
    end
end

function count = testDisabledIdentity()
    geometry = alev4.createSensorGeometry(struct('full_grid_size', [4 5], ...
        'active_roi', [2 2 2 3], 'pixel_pitch_m', 1, 'full_grid_cfa_pattern', 'GBRG'));
    model = alev4.createStructuredNoise([4 5], struct('enabled', false, ...
        'prnu', 2, 'dark_current_e_per_s', 500, ...
        'shared', struct('fixed_offset_e', -2, 'row_noise_e', 3, 'frame_noise_e', 1), ...
        'single', struct('column_noise_e', 4), 'high_gain', struct('row_noise_e', 7)));
    input = [3 10 25; 30 50 80];
    count = 0;
    for mode = 1:2
        if mode == 1
            [configuration, unused] = quietSingle([2 3], 100); %#ok<ASGLU>
            configuration.shot_noise = true; configuration.read_noise_e = 2;
        else
            [configuration, unused] = quietDual([2 3], 100); %#ok<ASGLU>
            configuration.sensor.shot_noise = true;
            configuration.high_gain.read_noise_e = 1; configuration.low_gain.read_noise_e = 3;
        end
        configuration = alev4.bindSensorGeometry(configuration, geometry, 'derive');
        cfg_copy = configuration; input_copy = input; model_copy = model; geometry_copy = geometry;
        for seed = [0 4294967295]
            for exposure = [0 .5]
                rng(47109, 'twister'); before = rng;
                wrapped = alev4.simulateStructuredExposure(input, configuration, exposure, seed, model, geometry);
                assert(isequal(before, rng()));
                if mode == 1
                    legacy = alev4.simulateExposure(input, configuration, exposure, seed);
                else
                    legacy = alev4.simulateDualGainExposure(input, configuration, exposure, seed);
                end
                assert(isequaln(wrapped, legacy), 'Disabled wrapper changed the whole legacy result.');
                assert(isequal(before, rng()));
                count = count+1;
            end
        end
        assert(isequal(configuration, cfg_copy) && isequal(input, input_copy) && ...
            isequal(model, model_copy) && isequal(geometry, geometry_copy));
    end
end

function testMasks()
    input = [0 14.5 14.625 14.875 50 100 120];
    [configuration, geometry] = quietDual(size(input), 100);
    configuration.high_gain.gain_dn_per_e = 4; configuration.high_gain.black_level_dn = 4;
    configuration.low_gain.black_level_dn = 4;
    model = alev4.createStructuredNoise(size(input), struct('dark_shot_noise', false));
    result = alev4.simulateStructuredExposure(input, configuration, 1, 47110, model, geometry);
    observed = result.readout;
    assert(isequal(observed.high_gain.raw_dn, uint16([4 62 63 63 63 63 63])));
    assert(isequal(observed.high_gain.adc_high_clipped, logical([0 0 0 1 1 1 1])));
    assert(isequal(observed.high_gain.adc_usable, logical([1 1 0 0 0 0 0])));
    assert(isequal(observed.low_gain.raw_dn, uint16([4 11 11 11 29 54 54])));
    assert(~any(observed.low_gain.adc_high_clipped) && all(observed.low_gain.adc_usable));
    assert(isequal(observed.full_well_saturated, logical([0 0 0 0 0 1 1])));
    assert(all(observed.merged.valid));
    assert(isequal(observed.reconstruction_valid, logical([1 1 1 1 1 0 0])));
    input = [58.25 58.5 59.25 59.5 80];
    [configuration, geometry] = quietDual(size(input), 100);
    configuration.high_gain.gain_dn_per_e = 4; configuration.high_gain.black_level_dn = 4;
    configuration.low_gain.gain_dn_per_e = 1; configuration.low_gain.black_level_dn = 4;
    model = alev4.createStructuredNoise(size(input), struct('dark_shot_noise', false));
    result = alev4.simulateStructuredExposure(input, configuration, 1, 47111, model, geometry);
    observed = result.readout;
    assert(isequal(observed.low_gain.raw_dn, uint16([62 63 63 63 63])));
    assert(isequal(observed.low_gain.adc_high_clipped, logical([0 0 0 1 1])));
    assert(isequal(observed.low_gain.adc_usable, logical([1 0 0 0 0])));
    assert(~any(observed.full_well_saturated));
    assert(isequal(observed.merged.valid, logical([1 0 0 0 0])) && ...
        isequal(observed.reconstruction_valid, logical([1 0 0 0 0])));
    assert(all(isfinite(observed.merged.electrons)));
    [configuration, geometry] = quietDual([1 4], 100);
    configuration.high_gain.gain_dn_per_e = 4; configuration.high_gain.black_level_dn = 4;
    configuration.low_gain.gain_dn_per_e = 1; configuration.low_gain.black_level_dn = 4;
    model = alev4.createStructuredNoise([1 4], struct('dark_shot_noise', false, ...
        'high_gain', struct('fixed_offset_e', [-1.0625 -1.125 -1 -.875]), ...
        'low_gain', struct('fixed_offset_e', [0 -4.5 0 -4])));
    result = alev4.simulateStructuredExposure(zeros(1,4), configuration, 1, 47112, model, geometry);
    observed = result.readout;
    assert(isequal(observed.high_gain.raw_dn, uint16([0 0 0 1])));
    assert(isequal(observed.high_gain.adc_low_clipped, logical([0 1 0 0])));
    assert(isequal(observed.low_gain.raw_dn, uint16([4 0 4 0])));
    assert(isequal(observed.low_gain.adc_low_clipped, logical([0 1 0 0])));
    assert(isequal(observed.merged.valid, logical([1 0 1 1])));
    assert(isequal(observed.merged.weight_high, [0 0 0 1]));
    assert(~any(observed.full_well_saturated) && ...
        isequal(observed.reconstruction_valid, observed.merged.valid));
end

function testObservedMerge()
    [configuration, geometry] = quietDual([1 3], 100);
    configuration.high_gain.gain_dn_per_e = 4; configuration.high_gain.black_level_dn = 4;
    configuration.low_gain.gain_dn_per_e = 1; configuration.low_gain.black_level_dn = 4;
    model = alev4.createStructuredNoise([1 3], struct('dark_shot_noise', false, ...
        'high_gain', struct('fixed_offset_e', [-.5 .5 1.5])));
    result = alev4.simulateStructuredExposure([4 6 8], configuration, 1, 47113, model, geometry);
    assert(isequal(result.readout.high_gain.raw_dn, uint16([18 30 42])));
    assert(isequal(result.readout.low_gain.raw_dn, uint16([8 10 12])));
    assert(isequal(result.readout.merged.weight_high, [1 .5 0]));
    assert(isequal(result.readout.merged.electrons, [3.5 6.25 8]), ...
        'Merge must use observed path offsets, not hidden expectation.');
    changed_model = model; changed_model.shared.fixed_offset_e = -.0625;
    hidden = alev4.simulateStructuredExposure([4.0625 6.0625 8.0625], ...
        configuration, 1, 47113, changed_model, geometry);
    assert(~isequal(hidden.readout.expected_electrons, result.readout.expected_electrons));
    assert(isequal(hidden.readout.high_gain.raw_dn, result.readout.high_gain.raw_dn) && ...
        isequal(hidden.readout.low_gain.raw_dn, result.readout.low_gain.raw_dn));
    assert(isequal(hidden.readout.merged, result.readout.merged));
    observed = alev4.mergeDualGain(result.readout.high_gain.raw_dn, ...
        result.readout.low_gain.raw_dn, configuration);
    assert(isequal(result.readout.merged, observed));
end

function count = testArithmeticAndIsolation()
    [configuration, geometry] = quietDual([1 1], 100);
    model = alev4.createStructuredNoise([1 1], struct('dark_shot_noise', false));
    rng(47114, 'twister'); before = rng;
    base = alev4.simulateStructuredExposure(2, configuration, 1, 0, model, geometry);
    assert(isequal(before, rng()));
    represented = alev4.simulateStructuredExposure(uint16(2), configuration, single(1), uint32(0), model, geometry);
    sparse_result = alev4.simulateStructuredExposure(sparse(2), configuration, sparse(1), sparse(0), model, geometry);
    assert(isequal(base, represented) && isequal(base, sparse_result));
    cfg_copy = configuration; model_copy = model; geometry_copy = geometry;
    count = 0;
    for seed = {-1, .5, 4294967296, Inf, NaN, true, [0 1], '0'}
        expectError(@() alev4.simulateStructuredExposure(2, configuration, 1, seed{1}, model, geometry), 'ALEV4:InvalidSeed');
        count = count+1;
    end
    for exposure = {-1, Inf, NaN, true, [0 1], '1'}
        expectError(@() alev4.simulateStructuredExposure(2, configuration, exposure{1}, 0, model, geometry), 'ALEV4:InvalidExposure');
        count = count+1;
    end
    for input = {-1, Inf, NaN, true, 1i}
        expectError(@() alev4.simulateStructuredExposure(input{1}, configuration, 1, 0, model, geometry), 'ALEV4:InvalidIrradiance');
        count = count+1;
    end
    expectError(@() alev4.simulateStructuredExposure([1 2], configuration, 1, 0, model, geometry), 'ALEV4:IrradianceShape');
    bad_cfg = configuration; bad_cfg.sensor.cfa_pattern = 'BGGR';
    expectError(@() alev4.simulateStructuredExposure(2, bad_cfg, 1, 0, model, geometry), 'ALEV4:GeometryBindingConflict');
    bad_model = alev4.createStructuredNoise([1 2], struct('enabled', false));
    expectError(@() alev4.simulateStructuredExposure(2, configuration, 1, 0, bad_model, geometry), 'ALEV4:StructuredNoiseGridMismatch');
    count = count+3;

    bad = model; bad.prnu = realmax;
    expectError(@() alev4.simulateStructuredExposure(2, configuration, 1, 0, bad, geometry), 'ALEV4:StructuredNoiseOverflow');
    bad = model; bad.dark_current_e_per_s = realmax;
    expectError(@() alev4.simulateStructuredExposure(0, configuration, 2, 0, bad, geometry), 'ALEV4:StructuredNoiseOverflow');
    expectError(@() alev4.simulateStructuredExposure(realmax/2, configuration, 1, 0, bad, geometry), 'ALEV4:StructuredNoiseOverflow');
    bad = model; bad.prnu = realmin;
    expectError(@() alev4.simulateStructuredExposure(.5, configuration, 1, 0, bad, geometry), 'ALEV4:StructuredNoiseUnderflow');
    bad.prnu = eps(0);
    expectError(@() alev4.simulateStructuredExposure(.5, configuration, 1, 0, bad, geometry), 'ALEV4:StructuredNoiseUnderflow');
    bad = model; bad.dark_current_e_per_s = realmin;
    expectError(@() alev4.simulateStructuredExposure(0, configuration, .5, 0, bad, geometry), 'ALEV4:StructuredNoiseUnderflow');
    bad = model; bad.shared.fixed_offset_e = realmin/2;
    expectError(@() alev4.simulateStructuredExposure(0, configuration, 1, 0, bad, geometry), 'ALEV4:StructuredNoiseUnderflow');
    bad = model; bad.high_gain.row_noise_e = realmin/2;
    expectError(@() alev4.simulateStructuredExposure(0, configuration, 1, 0, bad, geometry), 'ALEV4:StructuredNoiseUnderflow');
    expectError(@() alev4.simulateStructuredExposure(realmin, configuration, 1, 0, model, geometry), 'ALEV4:StructuredNoiseUnderflow');
    count = count+9;

    poisson = configuration; poisson.sensor.shot_noise = true;
    expectError(@() alev4.simulateStructuredExposure(1e9+1, poisson, 1, 0, model, geometry), 'ALEV4:InvalidPoissonMean');
    bad = model; bad.dark_shot_noise = true; bad.dark_current_e_per_s = 1e9+1;
    expectError(@() alev4.simulateStructuredExposure(0, configuration, 1, 0, bad, geometry), 'ALEV4:InvalidPoissonMean');
    % This failure occurs after charge sampling and a Gaussian row draw.
    % Both fixed terms are normal and finite, but their signed sum is not.
    bad = model; bad.shared.fixed_offset_e = realmax; bad.shared.row_noise_e = 1;
    bad.high_gain.fixed_offset_e = realmax; bad_copy = bad;
    expectError(@() alev4.simulateStructuredExposure(2, poisson, 1, 0, bad, geometry), 'ALEV4:StructuredNoiseOverflow');
    assert(isequal(bad, bad_copy));
    [single, single_geometry] = quietSingle([1 1], 100);
    single.gain_dn_per_e = realmax;
    expectError(@() alev4.simulateStructuredExposure(2, single, 1, 0, model, single_geometry), 'ALEV4:StructuredNoiseOverflow');
    single.gain_dn_per_e = 1;
    bad = model; bad.shared.fixed_offset_e = realmin+eps(0); bad.single.fixed_offset_e = -realmin;
    expectError(@() alev4.simulateStructuredExposure(0, single, 1, 0, bad, single_geometry), 'ALEV4:StructuredNoiseUnderflow');
    count = count+5;
    % At one spectral bin, 1538462 pixels alone reserve 100000030
    % retained numeric samples, before any fixed metadata. The tiny input
    % ensures the resource guard must reject before map expansion or input
    % shape validation, without allocating a large diagnostic result.
    [large, large_geometry] = quietDual([1 1538462], 100);
    large_model = alev4.createStructuredNoise([1 1538462], struct('dark_shot_noise', false));
    expectError(@() alev4.simulateStructuredExposure(0, large, 1, 0, ...
        large_model, large_geometry), 'ALEV4:StructuredNoiseSize');
    count = count+1;
    assert(isequal(before, rng()) && isequal(configuration, cfg_copy) && ...
        isequal(model, model_copy) && isequal(geometry, geometry_copy));
    noisy_cfg = configuration; noisy_cfg.sensor.shot_noise = true;
    noisy_cfg.high_gain.read_noise_e = 2; noisy_cfg.low_gain.read_noise_e = 3;
    noisy_model = model; noisy_model.dark_current_e_per_s = 3; noisy_model.dark_shot_noise = true;
    noisy_model.shared.row_noise_e = 2; noisy_model.high_gain.frame_noise_e = 1;
    first = alev4.simulateStructuredExposure(20, noisy_cfg, 1, 4294967295, noisy_model, geometry);
    repeated = alev4.simulateStructuredExposure(20, noisy_cfg, 1, 4294967295, noisy_model, geometry);
    assert(isequal(first, repeated) && isequal(before, rng()));
end

function controls = testWrongModels(fixture)
    result = fixture.result;
    model = result.noise_model;
    controls = {'prnu_renormalized', 'prnu_applied_twice', 'dark_modulated_by_prnu', ...
        'dark_rate_used_as_offset', 'photo_dark_separate_wells', ...
        'offsets_before_well', 'signed_electrons_reclipped', ...
        'black_level_added_twice', 'shared_offset_omitted', ...
        'high_path_uses_low_gain', 'negative_half_tie_rounded_toward_zero'};
    % Every candidate is tested by the same exact-equality predicate as the
    % correct oracle. These controls establish that the fixtures distinguish
    % concrete wrong stage orders; they are not alternate production code.
    assertReject(fixture.baseline.*(model.prnu/mean(model.prnu(:))), fixture.photo, controls{1});
    assertReject(fixture.photo.*model.prnu, fixture.photo, controls{2});
    assertReject(fixture.dark.*model.prnu, fixture.dark, controls{3});
    assertReject(model.dark_current_e_per_s, fixture.dark, controls{4});
    assertReject(min(fixture.photo,20)+min(fixture.dark,20), fixture.stored, controls{5});
    offsets = model.shared.fixed_offset_e+model.high_gain.fixed_offset_e;
    assertReject(min(fixture.total+offsets,20), fixture.high, controls{6});
    assertReject(min(max(fixture.high,0),20), fixture.high, controls{7});
    [wrong_raw, unused, unused2, unused3] = scalarAdc(fixture.high, 2, 8.5, 6); %#ok<ASGLU>
    assertReject(wrong_raw, result.readout.high_gain.raw_dn, controls{8});
    assertReject(fixture.stored+model.high_gain.fixed_offset_e, fixture.high, controls{9});
    [wrong_raw, unused, unused2, unused3] = scalarAdc(fixture.high, .5, 4.25, 6); %#ok<ASGLU>
    assertReject(wrong_raw, result.readout.high_gain.raw_dn, controls{10});
    wrong_negative_clipped = floor(-.5+.5) < 0;
    assertReject(wrong_negative_clipped, true, controls{11});
end

function [configuration, geometry] = quietDual(dimensions, full_well)
    sensor = struct('image_size', dimensions, 'wavelength_nm', 500, ...
        'bin_width_nm', 1, 'qe', [1 1 1], 'pixel_pitch_m', 1, ...
        'fill_factor', 1, 'shot_noise', false, 'full_well_e', full_well);
    configuration = alev4.createDualGainSensor(struct('sensor', sensor, ...
        'high_gain', struct('gain_dn_per_e', 2, 'read_noise_e', 0, 'black_level_dn', 4.25, 'adc_bits', 6), ...
        'low_gain', struct('gain_dn_per_e', .5, 'read_noise_e', 0, 'black_level_dn', 8.5, 'adc_bits', 6), ...
        'merge', struct('start_e', 4, 'end_e', 8)));
    geometry = alev4.createSensorGeometry(struct('full_grid_size', dimensions, 'pixel_pitch_m', 1));
end

function [configuration, geometry] = quietSingle(dimensions, full_well)
    configuration = alev4.createBaselineSensor(struct('image_size', dimensions, ...
        'wavelength_nm', 500, 'bin_width_nm', 1, 'qe', [1 1 1], ...
        'pixel_pitch_m', 1, 'fill_factor', 1, 'shot_noise', false, ...
        'full_well_e', full_well, 'read_noise_e', 0, ...
        'gain_dn_per_e', 2, 'black_level_dn', 4.25, 'adc_bits', 6));
    geometry = alev4.createSensorGeometry(struct('full_grid_size', dimensions, 'pixel_pitch_m', 1));
end

function [raw, clipped_low, clipped_high, usable] = scalarAdc(electrons, gain, black, bits)
    raw = zeros(size(electrons), 'uint16');
    clipped_low = false(size(electrons)); clipped_high = false(size(electrons));
    usable = false(size(electrons)); maximum = 2^bits-1;
    for k = 1:numel(electrons)
        analog = electrons(k)*gain+black;
        if analog < 0, rounded = -floor(-analog+.5); else, rounded = floor(analog+.5); end
        clipped_low(k) = rounded < 0; clipped_high(k) = rounded > maximum;
        if rounded < 0, value = 0; elseif rounded > maximum, value = maximum; else, value = rounded; end
        raw(k) = uint16(value);
        usable(k) = value > 0 && value < maximum;
    end
end

function assertPath(observed, electrons, gain, black, bits)
    [raw, clipped_low, clipped_high, usable] = scalarAdc(electrons, gain, black, bits);
    assert(isequal(observed.read_electrons, electrons));
    assert(isequal(observed.raw_dn, raw));
    assert(isequal(observed.adc_low_clipped, clipped_low));
    assert(isequal(observed.adc_high_clipped, clipped_high));
    assert(isequal(observed.adc_usable, usable));
end

function assertZeroTemporal(component, fixed, dimensions)
    assert(isequal(component.fixed_offset_e, fixed) && isequal(component.total_e, fixed));
    assert(isequal(component.row_e, zeros(dimensions(1),1)));
    assert(isequal(component.column_e, zeros(1,dimensions(2))));
    assert(component.frame_e == 0 && isequal(component.pixel_e, zeros(dimensions)));
end

function assertSlice(cropped, full, rows, columns)
    assert(isequal(cropped, full(rows,columns)), 'Deterministic crop changed a full-grid photosite.');
end

function assertPathSlice(cropped, full, rows, columns)
    for field = {'read_electrons', 'raw_dn', 'adc_low_clipped', 'adc_high_clipped', 'adc_usable'}
        assertSlice(cropped.(field{1}), full.(field{1}), rows, columns);
    end
end

function assertReject(candidate, reference, name)
    assert(~isequal(candidate, reference), ['Fixture did not reject wrong model: ' name]);
end

function expectError(callback, identifier)
    before = rng;
    caught = false;
    try
        callback();
    catch err
        caught = true;
        assert(strcmp(err.identifier, identifier), ...
            ['Expected ' identifier ', received ' err.identifier ': ' err.message]);
    end
    assert(caught, ['Expected rejection: ' identifier]);
    assert(isequal(before, rng()), 'Rejected simulation changed caller RNG state.');
end
