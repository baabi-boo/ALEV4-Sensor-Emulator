function report = test_iset_integration()
%TEST_ISET_INTEGRATION Non-skippable ISETCam-to-baseline comparison gate.
%   Run after setup_project. Missing ISETCam or image processing dependencies
%   throw an error; they must never count as a passed Phase 1 integration.
    prior_rng = rng;
    original_state = captureState();
    caller_guard = onCleanup(@() restoreCaller(original_state, prior_rng)); %#ok<NASGU>
    global vcSESSION;
    vcSESSION = struct('NAME', 'caller-session-sentinel', ...
        'SELECTED', struct('SCENE', 7), ...
        'SCENE', {{struct('caller_data', [3 1 4])}}, ...
        'GUI', struct('waitbar', 1), ...
        'opaque', struct('matrix', [1 2; 3 4]));
    setpref('ISET', 'waitbar', 1);
    setpref('ISET', 'alev4StateSentinel', struct('value', [9 -2 5]));
    sentinel_state = captureState();
    unrelated_preferences = otherPreferences();
    [one, cfg, first] = alev4.isetBaseline(73, 1e-3);
    require(isequal(prior_rng, rng), 'ISET baseline changed the caller RNG state.');
    requireState(sentinel_state, 'successful first exposure');
    [two, cfg_two, second] = alev4.isetBaseline(73, 2e-3);
    requireState(sentinel_state, 'successful second exposure');
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

    % Positive but excessive exposure fails after initialization/simulation,
    % exercising cleanup after the fixture has changed session/preferences.
    expectClippedFixture();
    requireState(sentinel_state, 'failed exposure');
    require(isequal(prior_rng, rng), 'Failed ISET exposure changed caller RNG state.');

    % Absence is also state: neither a new global nor new preference defaults
    % may remain after an otherwise successful or failed fixture.
    clear global vcSESSION;
    if ispref('ISET'), rmpref('ISET'); end
    absent_state = captureState();
    alev4.isetBaseline(73, 1e-3);
    requireState(absent_state, 'successful exposure with absent state');
    expectClippedFixture();
    requireState(absent_state, 'failed exposure with absent state');
    require(isequal(unrelated_preferences, otherPreferences()), ...
        'ISET fixture modified an unrelated preference group.');
    require(isequal(prior_rng, rng), 'State-isolation checks changed caller RNG state.');

    report = struct('status', 'passed', 'test_count', 14, ...
        'first_exposure', first, 'second_exposure', second, ...
        'core_linearity_relative_error', relative_linearity, ...
        'iset_linearity_relative_error', iset_linearity, ...
        'state_isolation', struct('existing_state_success', true, ...
            'existing_state_error', true, 'absent_state_success', true, ...
            'absent_state_error', true, 'unrelated_preferences_unchanged', true));
    fprintf('PASS ISETCam integration: max relative errors %.3g / %.3g; exposure linearity %.3g.\n', ...
        first.max_relative_error, second.max_relative_error, iset_linearity);
end

function state = captureState()
    names = who('global');
    state.had_session = any(strcmp(names, 'vcSESSION'));
    if state.had_session
        global vcSESSION;
        state.session = vcSESSION;
    else
        state.session = [];
    end
    state.had_preferences = ispref('ISET');
    if state.had_preferences
        state.preferences = getpref('ISET');
    else
        state.preferences = struct();
    end
end

function requireState(expected, context)
    observed = captureState();
    require(isequal(expected, observed), ['ISET state was not restored after ' context '.']);
end

function preferences = otherPreferences()
    preferences = getpref();
    if isfield(preferences, 'ISET')
        preferences = rmfield(preferences, 'ISET');
    end
end

function expectClippedFixture()
    caught = false;
    try
        alev4.isetBaseline(73, 1);
    catch err
        caught = true;
        require(strcmp(err.identifier, 'ALEV4:ISETClippedFixture'), ...
            ['Expected late clipping failure, received ' err.identifier '.']);
    end
    require(caught, 'An excessive exposure unexpectedly passed the ISET fixture.');
end

function restoreCaller(state, prior_rng)
    if state.had_session
        global vcSESSION;
        vcSESSION = state.session;
    else
        clear global vcSESSION;
    end
    if ispref('ISET'), rmpref('ISET'); end
    if state.had_preferences
        names = fieldnames(state.preferences);
        for k = 1:numel(names)
            setpref('ISET', names{k}, state.preferences.(names{k}));
        end
    end
    rng(prior_rng);
end

function require(condition, message)
    if ~condition
        error('ALEV4:ISETIntegrationTest', '%s', message);
    end
end
