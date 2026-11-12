function samples = samplePoisson(lambda)
%SAMPLEPOISSON Draw Poisson counts without a Statistics Toolbox dependency.
%   X = alev4.samplePoisson(LAMBDA) returns a double array of nonnegative
%   integer counts, preserving the shape of the real, nonnegative 2-D input.
%   Accepted numeric inputs, including sparse matrices, become dense doubles.
%   This function consumes the caller's uniform RNG stream. To obtain seeded
%   simulation with RNG isolation, call alev4.applyNoise instead.
%
%   Means below 10 use the product-of-uniforms algorithm. Larger means use
%   Hoermann's PTRS transformed rejection algorithm (not a Gaussian
%   approximation): W. Hoermann, Insurance: Mathematics and Economics 12,
%   39-45 (1993), "The transformed rejection method for generating Poisson
%   random variables". The published PTRS coefficients are used below.
%   Algorithm reference cross-check: NumPy's random_poisson_ptrs in
%   numpy/random/src/distributions/distributions.c.
%
%   Supported means are 0 <= LAMBDA <= 1e9 electrons. The explicit upper
%   bound avoids unsupported large-count numerical precision regimes.
%   "Exact" describes the distributional rejection algorithm; arithmetic
%   and the underlying uniform generator retain their finite precision.

    if nargin ~= 1 || ~isnumeric(lambda) || ~isreal(lambda) || ...
            ~ismatrix(lambda) || any(~isfinite(lambda(:))) || ...
            any(lambda(:) < 0) || any(lambda(:) > 1e9)
        error('ALEV4:InvalidPoissonMean', ...
            'Poisson means must be a finite real matrix in [0, 1e9].');
    end

    lambda = full(double(lambda));
    samples = zeros(size(lambda));
    flatMeans = lambda(:);

    % A zero mean is exactly zero and consumes no random numbers.
    small = find(flatMeans > 0 & flatMeans < 10);
    if ~isempty(small)
        thresholds = exp(-flatMeans(small));
        products = ones(size(small));
        counts = zeros(size(small));
        active = (1:numel(small))';
        while ~isempty(active)
            products(active) = products(active) .* rand(numel(active), 1);
            stillActive = products(active) > thresholds(active);
            counts(active(stillActive)) = counts(active(stillActive)) + 1;
            active = active(stillActive);
        end
        samples(small) = counts;
    end

    large = find(flatMeans >= 10);
    if isempty(large)
        return;
    end
    means = flatMeans(large);
    b = 0.931 + 2.53 .* sqrt(means);
    a = -0.059 + 0.02483 .* b;
    invAlpha = 1.1239 + 1.1328 ./ (b - 3.4);
    squeeze = 0.9277 - 3.6224 ./ (b - 2);
    logMeans = log(means);

    active = (1:numel(large))';
    while ~isempty(active)
        u = rand(numel(active), 1) - 0.5;
        v = rand(numel(active), 1);
        us = 0.5 - abs(u);

        % A possible uniform endpoint giving us==0 is rejected before any
        % division. It must never produce an Inf/NaN integer candidate.
        valid = us > 0;
        candidates = zeros(size(active));
        indices = active(valid);
        candidates(valid) = floor((2 .* a(indices) ./ us(valid) + ...
            b(indices)) .* u(valid) + means(indices) + 0.43);
        valid = valid & candidates >= 0 & isfinite(candidates);

        accepted = valid & us >= 0.07 & v <= squeeze(active);
        check = valid & ~accepted & ~(us < 0.013 & v > us);
        if any(check)
            indices = active(check);
            k = candidates(check);
            logEnvelope = log(v(check)) + log(invAlpha(indices)) - ...
                log(a(indices) ./ (us(check) .^ 2) + b(indices));
            logProbability = -means(indices) + k .* logMeans(indices) - ...
                gammaln(k + 1);
            accepted(check) = logEnvelope <= logProbability;
        end

        samples(large(active(accepted))) = candidates(accepted);
        active = active(~accepted);
    end
end
