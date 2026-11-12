function report = test_poisson_edges()
%TEST_POISSON_EDGES Exercise sampler branches, mixed indexing and endpoints.
%   REPORT = TEST_POISSON_EDGES() throws on any failed assertion. The suite
%   uses only ordinary MATLAB/Octave numeric functions, not a statistics
%   toolbox. Fixed seeds and seven-standard-error bounds limit flakiness.
%   These distribution checks are evidence, not a proof of exact arithmetic.
    caller_rng = rng;
    restore_rng = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    names = {'mixed_means_nonsquare_indexing', ...
        'threshold_probability_continuity', ...
        'supported_upper_mean_endpoint', ...
        'zero_means_consume_no_random_numbers'};

    % Interleave all regimes in MATLAB's linear indexing order. Each mean
    % occurs 50,000 times, spread over a nonsquare two-dimensional array.
    % This exercises the sampler's separate active-index lists in one call.
    means = [0 0.1 1 9.999 10 10.001 1000];
    samples_per_mean = 50000;
    labels = reshape(repmat(1:numel(means), 1, samples_per_mean), 350, 1000);
    mixed_means = reshape(means(labels(:)), size(labels));
    rng(1701, 'twister');
    mixed_samples = alev4.samplePoisson(mixed_means);
    assert(isequal(size(mixed_samples), size(mixed_means)), ...
        'Mixed-mean sampling changed the nonsquare array shape.');
    assert(all(isfinite(mixed_samples(:))) && ...
        all(mixed_samples(:) >= 0 & mixed_samples(:) == floor(mixed_samples(:))), ...
        'Mixed-mean Poisson samples must be finite nonnegative integers.');
    assert(all(mixed_samples(labels == 1) == 0), ...
        'Zero positions in a mixed array must remain exactly zero.');

    moment_metrics = struct([]);
    threshold_metrics = struct([]);
    for k = 1:numel(means)
        x = mixed_samples(labels == k);
        assert(numel(x) == samples_per_mean, 'The mixed fixture has incorrect group counts.');
        moment_metrics(k) = checkMoments(x, means(k)); %#ok<AGROW>
        if k >= 4 && k <= 6
            % A rounded Gaussian can approximate moments but not these
            % individual Poisson probabilities near the algorithm switch.
            threshold_metrics(end+1) = checkProbabilities(x, means(k), [5 9 10 11 15]); %#ok<AGROW>
        end
    end

    rng(1702, 'twister');
    upper_samples = alev4.samplePoisson(1e9 * ones(200, 250));
    assert(isequal(size(upper_samples), [200 250]), ...
        'Upper-endpoint sampling changed image dimensions.');
    assert(all(isfinite(upper_samples(:))) && all(upper_samples(:) >= 0) && ...
        all(upper_samples(:) == floor(upper_samples(:))), ...
        'Supported upper-endpoint samples must be finite integer counts.');
    upper_metrics = checkMoments(upper_samples(:), 1e9);

    rng(1703, 'twister');
    before_zero = rng;
    zero_samples = alev4.samplePoisson(zeros(3, 7));
    after_zero = rng;
    assert(isequal(zero_samples, zeros(3, 7)), 'All-zero means must return exact zeros.');
    assert(isequal(before_zero, after_zero), ...
        'All-zero means must not consume or otherwise change RNG state.');
    next_uniform = rand(1, 8);
    rng(before_zero);
    reference_uniform = rand(1, 8);
    assert(isequal(next_uniform, reference_uniform), ...
        'Zero-mean sampling unexpectedly advanced the uniform random stream.');

    report = struct('suite', 'poisson_edges', 'passed', true, ...
        'test_count', numel(names), 'tests', {names}, ...
        'samples_per_mean', samples_per_mean, 'mixed_shape', size(mixed_means), ...
        'mixed_moments', moment_metrics, 'threshold_probabilities', threshold_metrics, ...
        'upper_endpoint', upper_metrics, 'zero_rng_unchanged', true, ...
        'runtime_version', version());
    fprintf('PASS: Poisson edges, %d test groups.\n', numel(names));
end

function metrics = checkMoments(x, lambda)
    x = x(:);
    n = numel(x);
    measured_mean = mean(x);
    measured_variance = var(x, 0);
    % For Poisson, Var(sample mean)=lambda/N. The unbiased sample-variance
    % standard error is sqrt(lambda/N + 2*lambda^2/(N-1)).
    mean_tolerance = 7 * sqrt(lambda / n);
    variance_tolerance = 7 * sqrt(lambda / n + 2 * lambda^2 / (n-1));
    assert(abs(measured_mean - lambda) <= mean_tolerance, ...
        sprintf('Poisson mean at lambda=%g exceeds its finite-sample bound.', lambda));
    assert(abs(measured_variance - lambda) <= variance_tolerance, ...
        sprintf('Poisson variance at lambda=%g exceeds its finite-sample bound.', lambda));
    metrics = struct('lambda', lambda, 'samples', n, 'mean', measured_mean, ...
        'variance', measured_variance, 'mean_tolerance', mean_tolerance, ...
        'variance_tolerance', variance_tolerance);
end

function metrics = checkProbabilities(x, lambda, counts)
    n = numel(x);
    expected = exp(-lambda + counts * log(lambda) - gammaln(counts + 1));
    observed = zeros(size(counts));
    tolerances = 7 * sqrt(expected .* (1 - expected) / n) + 1 / n;
    for k = 1:numel(counts)
        observed(k) = sum(x == counts(k)) / n;
    end
    assert(all(abs(observed - expected) <= tolerances), ...
        sprintf('Poisson PMF at lambda=%g is inconsistent near the sampler switch.', lambda));
    metrics = struct('lambda', lambda, 'samples', n, 'counts', counts, ...
        'expected_probabilities', expected, 'observed_probabilities', observed, ...
        'probability_tolerances', tolerances);
end
