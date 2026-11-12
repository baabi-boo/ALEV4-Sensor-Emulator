function report = test_spectral_properties()
%TEST_SPECTRAL_PROPERTIES Independent spectral-integration invariants.
%   REPORT = TEST_SPECTRAL_PROPERTIES() checks continuous expectations before
%   quantization, using small noiseless, unsaturated fixtures. The oracle is
%   an explicit pixel/bin loop; it does not call the core CFA or integration
%   helpers. These tests establish generic-model properties, not calibration.
    caller_rng = rng;
    guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    names = {'nonuniform_bins_spatial_oracle', ...
        'spectral_bin_split_invariance', ...
        'spectral_linear_additivity', ...
        'all_cfa_patterns_independent_oracle', ...
        'fractional_fill_exposure_density_scaling', ...
        'quantum_efficiency_photon_bound'};

    metrics = struct();
    metrics.nonuniform_max_error_e = testNonuniformOracle();
    metrics.split_max_error_e = testBinSplit();
    metrics.additivity_max_error_e = testAdditivity();
    metrics.cfa_max_error_e = testCfaPatterns();
    testFractionalScaling();
    metrics.maximum_electron_photon_ratio = testPhotonBound();

    report = struct('suite', 'spectral_properties', 'passed', true, ...
        'test_count', numel(names), 'tests', {names}, 'metrics', metrics);
    fprintf('PASS: Spectral properties, %d test groups.\n', numel(names));
end

function [cfg, photons, exposure] = fixture()
    cfg = alev4.createBaselineSensor(struct( ...
        'image_size', [5 7], ...
        'wavelength_nm', [410; 470; 555; 650], ...
        'bin_width_nm', [7; 13; 21; 40], ...
        'qe', [0.05 0.15 0.80; 0.10 0.35 0.60; ...
               0.30 0.90 0.10; 0.85 0.20 0.02], ...
        'pixel_pitch_m', 4e-6, 'fill_factor', 0.37, ...
        'full_well_e', 1e6, 'read_noise_e', 0, ...
        'gain_dn_per_e', 0.25, 'black_level_dn', 64, ...
        'shot_noise', false));
    exposure = 0.007;
    photons = zeros(5, 7, 4);
    for row = 1:5
        for col = 1:7
            for bin = 1:4
                photons(row, col, bin) = 1e12 * (row + 2*col + 3*bin) * ...
                    (1 + mod(row*col + bin, 5)/10);
            end
        end
    end
end

function error_e = testNonuniformOracle()
    [cfg, photons, exposure] = fixture();
    actual = alev4.simulateExposure(photons, cfg, exposure, 2601);
    [expected_e, expected_photons] = independentOracle(photons, cfg, exposure);
    closeTo(actual.expected_electrons, expected_e, 'Nonuniform spectral integral');
    closeTo(actual.expected_incident_photons, expected_photons, 'Incident photon integral');
    % At (1,1), densities are [7.2,11.7,16.8,15]*1e12. For red:
    % .007*(4e-6)^2*.37*(7.2*.05*7 + 11.7*.1*13 +
    %                      16.8*.3*21 + 15*.85*40)*1e12.
    closeTo(actual.expected_electrons(1, 1), 26.2551408, 'Hand-calculated red photosite');
    closeTo(actual.expected_incident_photons(1, 1), 47.875632, 'Hand-calculated photon count');
    requireNoClipping(actual);
    error_e = max(abs(actual.expected_electrons(:) - expected_e(:)));
end

function error_e = testBinSplit()
    [coarse, original, exposure] = fixture();
    coarse.wavelength_nm = [440; 560; 650];
    coarse.bin_width_nm = [20; 40; 30];
    coarse.qe = coarse.qe([1 2 4], :);
    photons = original(:, :, 1:3);
    one = alev4.simulateExposure(photons, coarse, exposure, 2602);

    % The [540,580] nm bin is split into contiguous widths 7,11,22 nm.
    % Its bin-average density and QE remain constant across all three parts.
    fine = coarse;
    fine.wavelength_nm = [440; 543.5; 552.5; 569; 650];
    fine.bin_width_nm = [20; 7; 11; 22; 30];
    fine.qe = coarse.qe([1 2 2 2 3], :);
    split_photons = photons(:, :, [1 2 2 2 3]);
    many = alev4.simulateExposure(split_photons, fine, exposure, 2602);
    closeTo(many.expected_electrons, one.expected_electrons, 'Spectral-bin splitting');
    closeTo(many.expected_incident_photons, one.expected_incident_photons, ...
        'Incident photons under bin splitting');
    requireNoClipping(one);
    requireNoClipping(many);
    error_e = max(abs(many.expected_electrons(:) - one.expected_electrons(:)));
end

function error_e = testAdditivity()
    [cfg, photons_a, exposure] = fixture();
    photons_b = 0.17 * photons_a(end:-1:1, end:-1:1, :);
    a = alev4.simulateExposure(photons_a, cfg, exposure, 2603);
    b = alev4.simulateExposure(photons_b, cfg, exposure, 2603);
    both = alev4.simulateExposure(photons_a + photons_b, cfg, exposure, 2603);
    sum_e = a.expected_electrons + b.expected_electrons;
    closeTo(both.expected_electrons, sum_e, 'Photon-input additivity');
    closeTo(both.expected_incident_photons, ...
        a.expected_incident_photons + b.expected_incident_photons, ...
        'Incident photon additivity');
    requireNoClipping(both);
    % RAW codes are deliberately not tested for additivity: their bias and
    % quantization are nonlinear even when physical expectations are linear.
    error_e = max(abs(both.expected_electrons(:) - sum_e(:)));
end

function error_e = testCfaPatterns()
    [cfg, photons, exposure] = fixture();
    patterns = {'RGGB', 'GRBG', 'GBRG', 'BGGR'};
    error_e = 0;
    for p = 1:numel(patterns)
        cfg.cfa_pattern = patterns{p};
        actual = alev4.simulateExposure(photons, cfg, exposure, 2604);
        [expected, incident] = independentOracle(photons, cfg, exposure);
        closeTo(actual.expected_electrons, expected, ['CFA oracle: ' patterns{p}]);
        closeTo(actual.expected_incident_photons, incident, 'CFA-independent photons');
        requireNoClipping(actual);
        error_e = max(error_e, max(abs(actual.expected_electrons(:) - expected(:))));
    end
end

function testFractionalScaling()
    [cfg, photons, exposure] = fixture();
    baseline = alev4.simulateExposure(photons, cfg, exposure, 2605);
    factors = [0.125 0.3 1.7 3.25];
    for k = 1:numel(factors)
        factor = factors(k);
        scaled = alev4.simulateExposure(factor * photons, cfg, exposure, 2605);
        closeTo(scaled.expected_electrons, factor * baseline.expected_electrons, ...
            'Fractional density scaling');
        closeTo(scaled.expected_incident_photons, factor * baseline.expected_incident_photons, ...
            'Fractional incident-photon scaling');
        altered = cfg;
        altered.fill_factor = cfg.fill_factor / 2;
        combined = alev4.simulateExposure(factor * photons, altered, 0.4 * exposure, 2605);
        closeTo(combined.expected_electrons, factor * 0.2 * baseline.expected_electrons, ...
            'Combined exposure, fill-factor and density scaling');
        closeTo(combined.expected_incident_photons, factor * 0.2 * baseline.expected_incident_photons, ...
            'Combined incident-photon scaling');
        requireNoClipping(scaled);
        requireNoClipping(combined);
    end
end

function ratio = testPhotonBound()
    [cfg, photons, exposure] = fixture();
    actual = alev4.simulateExposure(photons, cfg, exposure, 2606);
    e = actual.expected_electrons;
    incident = actual.expected_incident_photons;
    assert(all(e(:) >= 0), 'Expected electron counts cannot be negative.');
    assert(all(e(:) <= incident(:) + 1e-11), ...
        'QE in [0,1] cannot yield more expected electrons than collected-area photons.');
    ratio = max(e(:) ./ incident(:));
    cfg.qe(:) = 1;
    unity = alev4.simulateExposure(photons, cfg, exposure, 2606);
    closeTo(unity.expected_electrons, unity.expected_incident_photons, 'Unit-QE photon bound');
    cfg.qe(:) = 0;
    zero = alev4.simulateExposure(photons, cfg, exposure, 2606);
    assert(all(zero.expected_electrons(:) == 0), 'Zero QE must produce zero electrons.');
    closeTo(zero.expected_incident_photons, incident, 'QE must not alter incoming photon expectation');
    requireNoClipping(unity);
end

function [electrons, photons] = independentOracle(irradiance, cfg, exposure)
% Deliberately explicit oracle: no cfaMap, vectorized core, or fixture helper.
    electrons = zeros(cfg.image_size);
    photons = zeros(cfg.image_size);
    for row = 1:cfg.image_size(1)
        for col = 1:cfg.image_size(2)
            tile_index = 2*mod(row-1, 2) + mod(col-1, 2) + 1;
            letter = cfg.cfa_pattern(tile_index);
            switch letter
                case 'R', channel = 1;
                case 'G', channel = 2;
                case 'B', channel = 3;
                otherwise, error('ALEV4:TestOracleCFA', 'Unexpected CFA letter.');
            end
            electron_density = 0;
            photon_density = 0;
            for bin = 1:numel(cfg.wavelength_nm)
                bin_photons = irradiance(row, col, bin) * cfg.bin_width_nm(bin);
                photon_density = photon_density + bin_photons;
                electron_density = electron_density + bin_photons * cfg.qe(bin, channel);
            end
            area = cfg.pixel_pitch_m * cfg.pixel_pitch_m;
            photons(row, col) = photon_density * area * cfg.fill_factor * exposure;
            electrons(row, col) = electron_density * area * cfg.fill_factor * exposure;
        end
    end
end

function requireNoClipping(result)
    assert(~any(result.full_well_saturated(:)) && ...
        ~any(result.adc_low_clipped(:)) && ~any(result.adc_high_clipped(:)), ...
        'Spectral property fixture must remain unsaturated and unclipped.');
end

function closeTo(actual, expected, label)
    assert(isequal(size(actual), size(expected)), [label ': shape mismatch.']);
    tolerance = 1e-11 + 1e-12 * abs(expected);
    assert(all(abs(actual(:) - expected(:)) <= tolerance(:)), [label ': numerical mismatch.']);
end
