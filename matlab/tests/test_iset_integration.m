function report = test_iset_integration()
%TEST_ISET_INTEGRATION Non-skippable ISETCam-to-baseline comparison gate.
%   Run after setup_project. Missing ISETCam or image processing dependencies
%   throw an error; they must never count as a passed Phase 1 integration.
    prior_rng = rng;
    [one, cfg, first] = alev4.isetBaseline(73, 1e-3);
    require(isequal(prior_rng, rng), 'ISET baseline changed the caller RNG state.');
    [two, cfg_two, second] = alev4.isetBaseline(73, 2e-3);
    require(strcmp(first.status, 'passed') && strcmp(second.status, 'passed'), ...
        'ISET comparisons did not pass.');
    require(isequal(size(one.raw_dn), [16 16]) && isa(one.raw_dn, 'uint16'), ...
        'Integration did not produce the expected 16-by-16 uint16 Bayer frame.');
    require(strcmp(cfg.cfa_pattern, 'RGGB') && isequal(cfg, cfg_two), ...
        'Sensor geometry/configuration changed across the exposure bracket.');
    require(any(one.expected_electrons(:) > 0), 'Illuminated frame is empty.');
    relative_linearity = max(abs(two.expected_electrons(:) - 2 * one.expected_electrons(:))) / ...
        max(1, max(two.expected_electrons(:)));
    require(relative_linearity <= 1e-12, 'Core exposure doubling is not linear.');
    iset_linearity = max(abs(second.iset_expected_electrons(:) - 2 * first.iset_expected_electrons(:))) / ...
        max(1, max(second.iset_expected_electrons(:)));
    require(iset_linearity <= 5e-5, 'ISET exposure doubling is not linear.');
    require(all(one.raw_dn(:) <= 65535) && all(two.raw_dn(:) <= 65535), ...
        'RAW samples exceed the declared ADC range.');
    require(~any(one.full_well_saturated(:)) && ~any(two.full_well_saturated(:)), ...
        'Integration fixture reached full well.');
    require(~any(one.adc_high_clipped(:)) && ~any(two.adc_high_clipped(:)), ...
        'Integration fixture reached the ADC upper limit.');
    report = struct('status', 'passed', 'test_count', 10, ...
        'first_exposure', first, 'second_exposure', second, ...
        'core_linearity_relative_error', relative_linearity, ...
        'iset_linearity_relative_error', iset_linearity);
    fprintf('PASS ISETCam integration: max relative errors %.3g / %.3g; exposure linearity %.3g.\n', ...
        first.max_relative_error, second.max_relative_error, iset_linearity);
end

function require(condition, message)
    if ~condition
        error('ALEV4:ISETIntegrationTest', '%s', message);
    end
end
