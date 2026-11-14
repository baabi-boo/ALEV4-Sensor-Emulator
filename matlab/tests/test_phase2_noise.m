function report = test_phase2_noise()
%TEST_PHASE2_NOISE Shared shot charge and independent readout statistics.
%   Fixed-seed checks use seven analytical standard errors, not tolerances
%   fitted to observed samples. The covariance uses the known incident mean.
%   Shadow expectations integrate Gaussian probability over actual ADC bins;
%   they do not assume quantization error is independent uniform noise.
%   No unbiased or optimal estimator claim is made in the merge transition.
    caller_rng = rng;
    guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    dimensions = [256 512];
    cfg = alev4.createDualGainSensor(struct('sensor', ...
        struct('image_size', dimensions)));
    mu = 250;
    shared = alev4.applyDualGainNoise(mu * ones(dimensions), cfg, 5201);
    assert(~any(shared.full_well_saturated(:)), 'Moment fixture reached physical full well.');
    assert(~any(shared.high_gain.adc_low_clipped(:) | shared.high_gain.adc_high_clipped(:)));
    assert(~any(shared.low_gain.adc_low_clipped(:) | shared.low_gain.adc_high_clipped(:)));

    metrics = struct();
    metrics.read_residuals = readResiduals(shared, cfg, mu);
    metrics.shared_shot = sharedShot(shared, cfg, mu);
    metrics.shot_cancellation = shotCancellation(shared, cfg);
    metrics.negative_controls = negativeControls(shared, cfg, mu, ...
        metrics.shared_shot.covariance_tolerance_e2, ...
        metrics.shot_cancellation.variance_tolerance_e2);
    metrics.signed_dark = signedDark(dimensions);
    metrics.shadow_quantization = shadowQuantization(dimensions);
    metrics.highlight = noisyHighlight();
    metrics.saturated_readout = saturatedReadNoise();

    names = {'independent_gaussian_read_residuals', ...
        'shared_poisson_covariance_and_path_variances', ...
        'shot_noise_cancels_from_path_difference', ...
        'wrong_exposure_and_correlated_read_models_rejected', ...
        'signed_dark_noise_before_adc_underflow', ...
        'shadow_merge_exact_quantizer_moments', ...
        'noisy_highlight_recovers_low_gain_observation', ...
        'electronic_noise_remains_signed_after_full_well_clipping'};
    tests = repmat(struct('name', '', 'status', 'passed', 'passed', true), ...
        1, numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    report = struct('suite', 'phase2_noise', 'status', 'passed', ...
        'passed', true, 'test_count', numel(names), 'tests', tests, 'metrics', metrics);
    fprintf('PASS: Phase 2 noise statistics, %d test groups.\n', numel(names));
end

function metrics = readResiduals(result, cfg, mu)
    charge = result.charge_electrons(:);
    high = result.high_gain.read_electrons(:) - charge;
    low = result.low_gain.read_electrons(:) - charge;
    n = numel(charge);
    sh = cfg.high_gain.read_noise_e; sl = cfg.low_gain.read_noise_e;
    high_stats = checkMoments(high, 0, sh^2, 3*sh^4, 'High read residual');
    low_stats = checkMoments(low, 0, sl^2, 3*sl^4, 'Low read residual');
    cross = mean(high .* low);
    cross_bound = 7 * sh * sl / sqrt(n);
    assert(abs(cross) <= cross_bound, 'Downstream read noises are correlated.');
    % Independence from photon collection is a separate requirement from
    % independence of the two electronics. Both expected products are zero.
    high_shot_cov = mean((charge - mu) .* high);
    low_shot_cov = mean((charge - mu) .* low);
    high_shot_bound = 7 * sqrt(mu * sh^2 / n);
    low_shot_bound = 7 * sqrt(mu * sl^2 / n);
    assert(abs(high_shot_cov) <= high_shot_bound, 'High read noise tracks collected shot noise.');
    assert(abs(low_shot_cov) <= low_shot_bound, 'Low read noise tracks collected shot noise.');
    metrics = struct('sample_count', n, 'high', high_stats, 'low', low_stats, ...
        'residual_cross_covariance_e2', cross, 'cross_covariance_target_e2', 0, ...
        'cross_covariance_tolerance_e2', cross_bound, ...
        'high_shot_covariance_e2', high_shot_cov, ...
        'high_shot_covariance_tolerance_e2', high_shot_bound, ...
        'low_shot_covariance_e2', low_shot_cov, ...
        'low_shot_covariance_tolerance_e2', low_shot_bound);
end

function metrics = sharedShot(result, cfg, mu)
    high = result.high_gain.read_electrons(:);
    low = result.low_gain.read_electrons(:);
    n = numel(high);
    vh = cfg.high_gain.read_noise_e^2;
    vl = cfg.low_gain.read_noise_e^2;
    % For X=(Q-mu)+NH and Y=(Q-mu)+NL, E[XY]=mu and
    % Var(XY)=mu+2*mu^2+mu*(vh+vl)+vh*vl. Independent exposures
    % would instead have zero covariance despite identical path marginals.
    covariance = mean((high - mu) .* (low - mu));
    covariance_bound = 7 * sqrt((mu + 2*mu^2 + mu*(vh+vl) + vh*vl) / n);
    assert(abs(covariance - mu) <= covariance_bound, ...
        'High/low covariance does not retain the single shared Poisson charge.');
    charge_stats = checkMoments(result.collected_electrons(:), mu, mu, ...
        mu + 3*mu^2, 'Shared photocharge');
    high_stats = checkMoments(high, mu, mu + vh, mu + 3*(mu+vh)^2, 'High total readout');
    low_stats = checkMoments(low, mu, mu + vl, mu + 3*(mu+vl)^2, 'Low total readout');
    metrics = struct('sample_count', n, 'mean_photoelectrons', mu, ...
        'covariance_e2', covariance, 'covariance_target_e2', mu, ...
        'covariance_tolerance_e2', covariance_bound, ...
        'covariance_definition', 'mean((high-mu).*(low-mu)); known incident mean', ...
        'charge', charge_stats, 'high_total', high_stats, 'low_total', low_stats);
end

function metrics = shotCancellation(result, cfg)
    difference = result.high_gain.read_electrons(:) - result.low_gain.read_electrons(:);
    target = cfg.high_gain.read_noise_e^2 + cfg.low_gain.read_noise_e^2;
    metrics = checkMoments(difference, 0, target, 3*target^2, 'High minus low readout');
    metrics.description = 'Shared shot charge cancels; only independent read noises remain.';
end

function metrics = negativeControls(result, cfg, mu, covariance_bound, difference_bound)
    high = result.high_gain.read_electrons(:);
    low = result.low_gain.read_electrons(:);
    charge = result.charge_electrons(:);
    n = numel(high);
    target_difference = cfg.high_gain.read_noise_e^2 + cfg.low_gain.read_noise_e^2;
    % Shift pairing while preserving every low-path marginal sample. This
    % intentionally breaks the shared exposure association, resembling the
    % mistake of independently simulating two exposures before merging.
    wrong_low = circshift(low, 1);
    wrong_covariance = mean((high - mu) .* (wrong_low - mu));
    wrong_difference = var(high - wrong_low, 0);
    independent_rejected = abs(wrong_covariance-mu) > covariance_bound && ...
        abs(wrong_difference-target_difference) > difference_bound;
    assert(independent_rejected, 'The covariance/cancellation gate accepted an incorrect exposure pairing.');

    % A reused standard-normal draw has correct marginal read-noise RMS but
    % wrong covariance. Verify that the checks detect that separate failure.
    nh = high - charge;
    bad_nl = (cfg.low_gain.read_noise_e / cfg.high_gain.read_noise_e) * nh;
    correlated_covariance = mean(nh .* bad_nl);
    residual_bound = 7 * cfg.high_gain.read_noise_e * cfg.low_gain.read_noise_e / sqrt(n);
    correlated_difference = var(nh - bad_nl, 0);
    correlated_rejected = abs(correlated_covariance) > residual_bound && ...
        abs(correlated_difference-target_difference) > difference_bound;
    assert(correlated_rejected, 'The read-noise gates accepted a reused Gaussian draw.');
    metrics = struct('sample_count', n, 'independent_pairing_rejected', independent_rejected, ...
        'incorrect_pair_covariance_e2', wrong_covariance, ...
        'incorrect_pair_difference_variance_e2', wrong_difference, ...
        'correlated_read_rejected', correlated_rejected, ...
        'incorrect_read_covariance_e2', correlated_covariance, ...
        'incorrect_read_difference_variance_e2', correlated_difference, ...
        'correct_difference_target_e2', target_difference);
end

function metrics = signedDark(dimensions)
    cfg = alev4.createDualGainSensor(struct('sensor', struct('image_size', dimensions), ...
        'high_gain', struct('black_level_dn', 0), ...
        'low_gain', struct('black_level_dn', 0)));
    result = alev4.applyDualGainNoise(zeros(dimensions), cfg, 5202);
    assert(all(result.collected_electrons(:) == 0) && all(result.charge_electrons(:) == 0));
    assert(~any(result.full_well_saturated(:)));
    metrics = struct('sample_count', prod(dimensions));
    for label = {'high_gain', 'low_gain'}
        name = label{1}; path = result.(name); config = cfg.(name);
        values = path.read_electrons(:); sigma = config.read_noise_e;
        stats = checkMoments(values, 0, sigma^2, 3*sigma^4, [name ' signed dark']);
        assert(any(values < 0) && any(values > 0), 'Dark read noise was clipped before the ADC.');
        % Rounded ADC underflow starts at analog DN<-0.5. Zero black level
        % deliberately makes this likely, unlike the standard 64-DN offset.
        expected_fraction = 0.5 * erfc(0.5 / (config.gain_dn_per_e*sigma*sqrt(2)));
        fraction = mean(double(path.adc_low_clipped(:)));
        fraction_bound = 7 * sqrt(expected_fraction*(1-expected_fraction)/numel(values));
        assert(abs(fraction-expected_fraction) <= fraction_bound, 'Dark ADC-underflow probability is incorrect.');
        assert(~any(path.adc_high_clipped(:)));
        stats.adc_underflow_fraction = fraction;
        stats.adc_underflow_target = expected_fraction;
        stats.adc_underflow_tolerance = fraction_bound;
        metrics.(name) = stats;
    end
end

function metrics = shadowQuantization(dimensions)
    cfg = alev4.createDualGainSensor(struct('sensor', ...
        struct('image_size', dimensions, 'shot_noise', false)));
    mu = 10;
    result = alev4.applyDualGainNoise(mu*ones(dimensions), cfg, 5203);
    assert(all(result.merged.weight_high(:) == 1) && all(result.reconstruction_valid(:)), ...
        'Shadow fixture must exclusively use the nonrail high-gain observation.');
    high = (double(result.high_gain.raw_dn(:)) - cfg.high_gain.black_level_dn) / cfg.high_gain.gain_dn_per_e;
    low = (double(result.low_gain.raw_dn(:)) - cfg.low_gain.black_level_dn) / cfg.low_gain.gain_dn_per_e;
    assert(isequal(high, result.merged.electrons(:)));
    high_moments = quantizerMoments(cfg.high_gain.read_noise_e, cfg.high_gain.gain_dn_per_e);
    low_moments = quantizerMoments(cfg.low_gain.read_noise_e, cfg.low_gain.gain_dn_per_e);
    high_stats = checkMoments(high, mu, high_moments.variance_e2, ...
        high_moments.fourth_moment_e4, 'Merged high-gain shadow');
    low_stats = checkMoments(low, mu, low_moments.variance_e2, ...
        low_moments.fourth_moment_e4, 'Low-gain shadow');
    assert(high_stats.variance_e2 < low_stats.variance_e2 / 10, ...
        'The default high-gain shadow path lost its expected read/quantization advantage.');

    % Integer Poisson charge shifts a high-gain code by exactly 4 DN, so
    % the quantized Gaussian residual is independent of that shared charge.
    % Its moments can therefore be combined analytically with Poisson moments.
    cfg.sensor.shot_noise = true;
    shot = alev4.applyDualGainNoise(mu*ones(dimensions), cfg, 5204);
    assert(all(shot.merged.weight_high(:) == 1) && all(shot.reconstruction_valid(:)));
    total_variance = mu + high_moments.variance_e2;
    total_fourth = mu + 3*mu^2 + high_moments.fourth_moment_e4 + ...
        6*mu*high_moments.variance_e2;
    shot_stats = checkMoments(shot.merged.electrons(:), mu, total_variance, ...
        total_fourth, 'Shared-shot merged shadow');
    metrics = struct('sample_count', prod(dimensions), 'high_quantizer', high_moments, ...
        'low_quantizer', low_moments, 'read_only_merged', high_stats, ...
        'read_only_low', low_stats, 'shot_and_read_merged', shot_stats);
end

function moments = quantizerMoments(sigma, gain)
    % The fixture's noiseless analog code is an integer. Integrate a
    % zero-mean Gaussian over every relevant rounding bin, rather than use
    % the often-inaccurate delta^2/12 approximation for coarse quantizers.
    scale_dn = sigma * gain;
    limit = ceil(12 * scale_dn);
    codes = -limit:limit;
    upper = (codes + 0.5) / scale_dn;
    lower = (codes - 0.5) / scale_dn;
    probabilities = 0.5 * erfc(-upper/sqrt(2)) - 0.5 * erfc(-lower/sqrt(2));
    assert(all(probabilities >= 0) && abs(sum(probabilities)-1) < 1e-13);
    errors_e = codes/gain;
    moments = struct('variance_e2', sum(errors_e.^2 .* probabilities), ...
        'fourth_moment_e4', sum(errors_e.^4 .* probabilities), ...
        'included_probability', sum(probabilities), ...
        'minimum_covered_standard_deviations', (limit+0.5)/scale_dn, ...
        'method', 'Gaussian CDF differences over symmetric ADC rounding bins');
end

function metrics = noisyHighlight()
    dimensions = [128 256]; mu = 12000;
    cfg = alev4.createDualGainSensor(struct('sensor', struct('image_size', dimensions)));
    result = alev4.applyDualGainNoise(mu*ones(dimensions), cfg, 5205);
    assert(all(result.high_gain.adc_high_clipped(:)), 'Highlight must exceed the high-gain ADC range.');
    assert(~any(result.full_well_saturated(:)) && all(result.reconstruction_valid(:)));
    assert(~any(result.low_gain.adc_low_clipped(:) | result.low_gain.adc_high_clipped(:)));
    assert(all(result.merged.weight_high(:) == 0));
    low_reconstruction = (double(result.low_gain.raw_dn(:)) - cfg.low_gain.black_level_dn) / cfg.low_gain.gain_dn_per_e;
    assert(isequal(result.merged.electrons(:), low_reconstruction), ...
        'Saturated high-gain information leaked into highlight reconstruction.');
    quantization_bound = 0.5 / cfg.low_gain.gain_dn_per_e;
    errors = abs(result.merged.electrons(:) - result.low_gain.read_electrons(:));
    assert(all(errors <= quantization_bound + 1e-10));
    variance = mu + cfg.low_gain.read_noise_e^2;
    stats = checkMoments(result.low_gain.read_electrons(:), mu, variance, ...
        mu + 3*variance^2, 'Highlight low-gain analog readout');
    merged_mean = mean(result.merged.electrons(:));
    assert(abs(merged_mean-mu) <= stats.mean_tolerance_e + quantization_bound);
    metrics = struct('sample_count', prod(dimensions), 'low_readout', stats, ...
        'mean_merged_electrons', merged_mean, 'max_quantization_error_e', max(errors), ...
        'quantization_bound_e', quantization_bound, 'high_clip_fraction', 1, ...
        'reconstruction_valid_fraction', 1);
end

function metrics = saturatedReadNoise()
    % Physical charge is clipped before downstream electronic noise. A
    % second full-well clamp after adding that noise would censor positive
    % excursions, bias saturated readouts and incorrectly reduce variance.
    dimensions = [128 256];
    full_well = 30000; expected = 40000;
    cfg = alev4.createDualGainSensor(struct('sensor', struct( ...
        'image_size', dimensions, 'shot_noise', false, 'full_well_e', full_well), ...
        'high_gain', struct('read_noise_e', 1), ...
        'low_gain', struct('read_noise_e', 5)));
    result = alev4.applyDualGainNoise(expected * ones(dimensions), cfg, 5206);
    assert(all(result.collected_electrons(:) == expected));
    assert(all(result.charge_electrons(:) == full_well), ...
        'The common stored charge must remain at physical full well.');
    assert(all(result.full_well_saturated(:)) && ...
        ~any(result.reconstruction_valid(:)), ...
        'Electronic noise cannot recover a physically saturated exposure.');
    assert(all(result.high_gain.adc_high_clipped(:)) && all(result.merged.valid(:)), ...
        'Saturated fixture must distinguish usable low RAW from physical validity.');
    metrics = struct('sample_count', prod(dimensions), ...
        'expected_electrons', expected, 'shared_full_well_e', full_well, ...
        'full_well_saturation_fraction', 1, 'reconstruction_valid_fraction', 0);
    for label = {'high_gain', 'low_gain'}
        name = label{1}; sigma = cfg.(name).read_noise_e;
        readout = result.(name).read_electrons(:);
        residual = readout - full_well;
        stats = checkMoments(residual, 0, sigma^2, 3*sigma^4, ...
            [name ' read noise after full-well clipping']);
        assert(any(residual < 0) && any(residual > 0), ...
            'Electronic read noise was censored at the physical well limit.');

        % Deliberately incorrect processing order, using the same draws:
        % stored charge + noise -> another physical-full-well clamp.
        wrong_residual = min(readout, full_well) - full_well;
        wrong_mean = mean(wrong_residual);
        wrong_variance = var(wrong_residual, 0);
        wrong_rejected = abs(wrong_mean) > stats.mean_tolerance_e && ...
            abs(wrong_variance - sigma^2) > stats.variance_tolerance_e2;
        assert(wrong_rejected && ~any(wrong_residual > 0), ...
            'The saturated-noise gate accepted incorrect post-noise clipping.');
        stats.fraction_above_full_well = mean(double(residual > 0));
        stats.fraction_below_full_well = mean(double(residual < 0));
        stats.post_noise_clipped_mean_e = wrong_mean;
        stats.post_noise_clipped_variance_e2 = wrong_variance;
        stats.post_noise_clipped_reference_rejected = wrong_rejected;
        metrics.(name) = stats;
    end
end

function statistics = checkMoments(values, expected_mean, variance, fourth, label)
    n = numel(values);
    observed_mean = mean(values); observed_variance = var(values, 0);
    mean_tolerance = 7 * sqrt(variance/n);
    % Exact variance of the unbiased sample variance for IID observations.
    variance_tolerance = 7 * sqrt((fourth - ((n-3)/(n-1))*variance^2)/n);
    assert(abs(observed_mean-expected_mean) <= mean_tolerance, ...
        [label ' mean exceeds seven analytical standard errors.']);
    assert(abs(observed_variance-variance) <= variance_tolerance, ...
        [label ' variance exceeds seven analytical standard errors.']);
    statistics = struct('sample_count', n, 'mean_e', observed_mean, ...
        'mean_target_e', expected_mean, 'mean_tolerance_e', mean_tolerance, ...
        'variance_e2', observed_variance, 'variance_target_e2', variance, ...
        'variance_tolerance_e2', variance_tolerance, ...
        'fourth_central_moment_target_e4', fourth);
end
