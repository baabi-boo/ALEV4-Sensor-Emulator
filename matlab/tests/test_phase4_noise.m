function report = test_phase4_noise()
%TEST_PHASE4_NOISE Preregistered finite-sample structured-noise checks.
%   Non-Gaussian comparisons use exact second/fourth moments with Chebyshev
%   and a union bound, not a Gaussian tail approximation for Poisson data.
%   Gaussian comparisons use normal and chi-square concentration; correlated
%   Gaussian covariance uses polarization. Counts refer to independent draws:
%   pixels, rows, columns, or frames as appropriate. No samples are censored.
    caller_rng = rng;
    guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    allocation = struct('total_false_failure_allowance', 0.01, ...
        'non_gaussian_family_allowance', 0.005, ...
        'non_gaussian_comparison_limit', 32, ...
        'gaussian_family_allowance', 0.005, ...
        'gaussian_comparison_limit', 64, ...
        'maximum_pixel_fixture_size', [512 512], ...
        'independent_spatial_group_count', 8192, ...
        'independent_frame_count', 1024);
    allocation.chebyshev_multiplier = sqrt( ...
        allocation.non_gaussian_comparison_limit / allocation.non_gaussian_family_allowance);
    allocation.gaussian_t = log(4 * allocation.gaussian_comparison_limit / ...
        allocation.gaussian_family_allowance);
    allocation.interpretation = ['Bounds hold under the declared ideal independent-draw ' ...
        'model; fixed seeds do not establish PRNG independence or camera calibration.'];

    metrics = shotAndPixel(allocation);
    [metrics.row, row_controls] = spatialGroups('row', 62401, allocation);
    [metrics.column, column_controls] = spatialGroups('column', 62402, allocation);
    metrics.spatial_controls = struct('row', row_controls, 'column', column_controls);
    [metrics.frame, metrics.temporal] = frameGroups(allocation);
    metrics.mixed_components = mixedComponents();
    non_gaussian_count = comparisonCount(metrics, 'non_gaussian');
    gaussian_count = comparisonCount(metrics, 'gaussian');
    assert(non_gaussian_count == 22 && gaussian_count == 59, ...
        'Update the preregistered comparison inventory deliberately if tests change.');
    assert(non_gaussian_count <= allocation.non_gaussian_comparison_limit && ...
        gaussian_count <= allocation.gaussian_comparison_limit, ...
        'The declared statistical family budget was exceeded.');
    allocation.actual_non_gaussian_comparisons = non_gaussian_count;
    allocation.actual_gaussian_comparisons = gaussian_count;
    allocation.actual_union_bound = ...
        non_gaussian_count / allocation.chebyshev_multiplier^2 + ...
        gaussian_count * 4 * exp(-allocation.gaussian_t);
    metrics.statistical_allocation = allocation;
    metrics.synthetic = true;
    metrics.calibrated_alev4 = false;
    names = {'photo_dark_poisson_moments_and_independence', ...
        'independent_photo_dark_shot_policies', ...
        'shared_total_charge_covariance_and_path_variance_sums', ...
        'independent_pixel_noise_and_shot_cancellation', ...
        'independent_charge_and_reused_pixel_stream_controls', ...
        'row_covariance_counts_independent_rows', ...
        'column_covariance_counts_independent_columns', ...
        'wrong_spatial_axes_and_reused_path_stream_controls', ...
        'frame_shared_path_covariance_counts_independent_frames', ...
        'independent_frame_differences_and_disjoint_temporal_pairs', ...
        'mixed_components_sum_after_one_physical_charge'};
    tests = repmat(struct('name', '', 'status', 'passed', 'passed', true), 1, numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    report = struct('suite', 'phase4_noise', 'status', 'passed', 'passed', true, ...
        'test_count', numel(names), 'tests', tests, 'metrics', metrics);
    fprintf('PASS: Phase 4 noise statistics, %d test groups (%d bounded-moment, %d Gaussian comparisons).\n', ...
        numel(names), non_gaussian_count, gaussian_count);
end

function metrics = shotAndPixel(a)
    dimensions = a.maximum_pixel_fixture_size;
    [cfg, geometry] = dualFixture(dimensions, true, 2, 3);
    photo_mean = 64; dark_mean = 36; total_mean = photo_mean + dark_mean;
    input = photo_mean * ones(dimensions);
    model = alev4.createStructuredNoise(dimensions, struct('dark_current_e_per_s', dark_mean));
    seed = 62400;
    result = alev4.simulateStructuredExposure(input, cfg, 1, seed, model, geometry);
    assertUnclipped(result);
    photo = result.components.photo_electrons(:);
    dark = result.components.dark_electrons(:);
    charge = result.readout.charge_electrons(:);
    high = result.readout.high_gain.read_electrons(:);
    low = result.readout.low_gain.read_electrons(:);
    nh = result.components.high_gain.pixel_e(:);
    nl = result.components.low_gain.pixel_e(:);
    assert(all(photo >= 0 & photo == fix(photo)) && all(dark >= 0 & dark == fix(dark)));
    assert(isequal(charge, photo + dark));
    assert(isequal(high, charge + nh) && isequal(low, charge + nl), ...
        'Both readout paths must branch from exactly the same stored charge.');
    metrics.photo_dark = struct( ...
        'photo', boundedMoments(photo, photo_mean, photo_mean, photo_mean + 3*photo_mean^2, a), ...
        'dark', boundedMoments(dark, dark_mean, dark_mean, dark_mean + 3*dark_mean^2, a), ...
        'sum', boundedMoments(charge, total_mean, total_mean, total_mean + 3*total_mean^2, a), ...
        'independent_components', boundedCovariance(photo-photo_mean, dark-dark_mean, ...
            0, photo_mean*dark_mean, a));
    vh = cfg.high_gain.read_noise_e^2; vl = cfg.low_gain.read_noise_e^2;
    product_variance = total_mean + 2*total_mean^2 + total_mean*(vh+vl) + vh*vl;
    metrics.shared_total = struct( ...
        'high', boundedMoments(high, total_mean, total_mean+vh, ...
            total_mean + 3*(total_mean+vh)^2, a), ...
        'low', boundedMoments(low, total_mean, total_mean+vl, ...
            total_mean + 3*(total_mean+vl)^2, a), ...
        'cross_path', boundedCovariance(high-total_mean, low-total_mean, ...
            total_mean, product_variance, a), ...
        'high_shot_independence', boundedCovariance(charge-total_mean, nh, 0, total_mean*vh, a), ...
        'low_shot_independence', boundedCovariance(charge-total_mean, nl, 0, total_mean*vl, a));
    metrics.pixel = struct('high', gaussianMoments(nh, vh, a), ...
        'low', gaussianMoments(nl, vl, a), ...
        'cross_path', gaussianCovariance(nh, nl, vh, vl, 0, a), ...
        'path_difference', gaussianMoments(high-low, vh+vl, a));

    % Disjoint odd/even pixels supply independent wrong-path charge pairs.
    % Their own known moments are included in the non-Gaussian family budget.
    % Overlapping circular shifts are deliberately not counted as IID pairs.
    wrong_high = high(1:2:end) - total_mean;
    wrong_low = low(2:2:end) - total_mean;
    wrong_count = numel(wrong_high);
    wrong_cov = boundedCovariance(wrong_high, wrong_low, 0, ...
        (total_mean+vh)*(total_mean+vl), a);
    correct_cov_bound = a.chebyshev_multiplier * sqrt(product_variance/wrong_count);
    independent_pairing_rejected = abs(wrong_cov.covariance_e2-total_mean) > correct_cov_bound;
    wrong_difference_variance = 2*total_mean + vh + vl;
    wrong_difference = boundedSecondMoment(wrong_high-wrong_low, ...
        wrong_difference_variance, 2*total_mean+3*wrong_difference_variance^2, a);
    [correct_lower, correct_upper] = gaussianSecondBounds(vh+vl, wrong_count, a);
    independent_difference_rejected = ~within(wrong_difference.second_moment_e2, correct_lower, correct_upper);
    wrong_nl = sqrt(vl/vh) * nh;
    reused_cov = mean(nh .* wrong_nl);
    reused_difference = mean((nh-wrong_nl).^2);
    reused_rejected = abs(reused_cov) > metrics.pixel.cross_path.covariance_tolerance_e2 && ...
        ~within(reused_difference, metrics.pixel.path_difference.second_moment_lower_e2, ...
            metrics.pixel.path_difference.second_moment_upper_e2);
    assert(independent_pairing_rejected && independent_difference_rejected, ...
        'The shared-charge gates accepted independent path charge.');
    assert(reused_rejected, 'The pixel-noise gates accepted a reused Gaussian stream.');
    metrics.pixel_controls = struct('independent_pairing', wrong_cov, ...
        'independent_difference', wrong_difference, ...
        'correct_covariance_target_e2', total_mean, ...
        'correct_covariance_tolerance_e2', correct_cov_bound, ...
        'correct_difference_lower_e2', correct_lower, 'correct_difference_upper_e2', correct_upper, ...
        'independent_pairing_rejected', independent_pairing_rejected, ...
        'independent_difference_rejected', independent_difference_rejected, ...
        'reused_pixel_covariance_e2', reused_cov, ...
        'reused_pixel_difference_second_moment_e2', reused_difference, ...
        'reused_pixel_stream_rejected', reused_rejected);

    % Switching one charge policy must leave the other sampled component and
    % both electronic streams bit-for-bit unchanged, as well as give the
    % correct total variance. Fixtures are released before the next call.
    clear result;
    photo_off = cfg; photo_off.sensor.shot_noise = false;
    r = alev4.simulateStructuredExposure(input, photo_off, 1, seed, model, geometry);
    assertUnclipped(r);
    assert(all(r.components.photo_electrons(:) == photo_mean));
    assert(isequal(r.components.dark_electrons(:), dark));
    assert(isequal(r.components.high_gain.pixel_e(:), nh) && isequal(r.components.low_gain.pixel_e(:), nl));
    metrics.policies.photo_off = boundedMoments(r.readout.collected_electrons(:), ...
        total_mean, dark_mean, dark_mean+3*dark_mean^2, a);
    clear r;
    dark_off = model; dark_off.dark_shot_noise = false;
    r = alev4.simulateStructuredExposure(input, cfg, 1, seed, dark_off, geometry);
    assertUnclipped(r);
    assert(all(r.components.dark_electrons(:) == dark_mean));
    assert(isequal(r.components.photo_electrons(:), photo));
    assert(isequal(r.components.high_gain.pixel_e(:), nh) && isequal(r.components.low_gain.pixel_e(:), nl));
    metrics.policies.dark_off = boundedMoments(r.readout.collected_electrons(:), ...
        total_mean, photo_mean, photo_mean+3*photo_mean^2, a);
    clear r;
    r = alev4.simulateStructuredExposure(zeros(dimensions), photo_off, 2, 62403, model, geometry);
    assertUnclipped(r);
    assert(all(r.components.photo_electrons(:) == 0));
    assert(all(r.readout.expected_dark_electrons(:) == 2*dark_mean));
    metrics.policies.dark_double_exposure = boundedMoments(r.components.dark_electrons(:), ...
        2*dark_mean, 2*dark_mean, 2*dark_mean+3*(2*dark_mean)^2, a);
    metrics.policies.exposures_s = [1 2];
    metrics.policies.dark_rate_e_per_s = dark_mean;
end

function [metrics, controls] = spatialGroups(axis_name, seed, a)
    group_count = a.independent_spatial_group_count;
    if strcmp(axis_name, 'row'), dimensions = [group_count 2]; else, dimensions = [2 group_count]; end
    [cfg, geometry] = dualFixture(dimensions, false, 0, 0);
    model = alev4.createStructuredNoise(dimensions);
    field = [axis_name '_noise_e']; component_field = [axis_name '_e'];
    model.shared.(field) = 3; model.high_gain.(field) = 4; model.low_gain.(field) = 5;
    r = alev4.simulateStructuredExposure(100*ones(dimensions), cfg, 1, seed, model, geometry);
    assertUnclipped(r);
    shared = r.components.shared.(component_field); shared = shared(:);
    high_path = r.components.high_gain.(component_field); high_path = high_path(:);
    low_path = r.components.low_gain.(component_field); low_path = low_path(:);
    high = r.readout.high_gain.read_electrons - 100;
    low = r.readout.low_gain.read_electrons - 100;
    if strcmp(axis_name, 'column'), high = high.'; low = low.'; end
    assert(isequal(high(:,1), high(:,2)) && isequal(low(:,1), low(:,2)), ...
        'A row/column draw must be exactly shared across its entire spatial group.');
    assert(numel(shared) == group_count && numel(high_path) == group_count && numel(low_path) == group_count);
    metrics = struct('axis', axis_name, 'image_size', dimensions, ...
        'independent_group_count', group_count, 'pixels_per_group', 2, ...
        'shared_component', gaussianMoments(shared, 9, a), ...
        'high_component', gaussianMoments(high_path, 16, a), ...
        'low_component', gaussianMoments(low_path, 25, a), ...
        'high_total', gaussianMoments(high(:,1), 25, a), ...
        'low_total', gaussianMoments(low(:,1), 34, a), ...
        'same_group_high_covariance', gaussianCovariance(high(:,1), high(:,2), 25, 25, 25, a), ...
        'same_group_low_covariance', gaussianCovariance(low(:,1), low(:,2), 34, 34, 34, a), ...
        'cross_path_covariance', gaussianCovariance(high(:,1), low(:,2), 25, 34, 9, a), ...
        'different_group_covariance', gaussianCovariance(high(1:2:end,1), high(2:2:end,2), 25, 25, 0, a), ...
        'path_component_covariance', gaussianCovariance(high_path, low_path, 16, 25, 0, a), ...
        'shared_high_covariance', gaussianCovariance(shared, high_path, 9, 16, 0, a), ...
        'shared_low_covariance', gaussianCovariance(shared, low_path, 9, 25, 0, a));
    % Reading pairs along the wrong axis changes the target from 25 to zero.
    % The wrong pairs are disjoint: 4096 independent pairs, not 16384 pixels.
    axis_stat = metrics.different_group_covariance;
    wrong_axis_rejected = abs(axis_stat.covariance_e2-25) > axis_stat.covariance_tolerance_e2;
    wrong_pixel_matrix = [high(:,1), circshift(high(:,1),1)];
    wrong_broadcast_rejected = ~isequal(wrong_pixel_matrix(:,1), wrong_pixel_matrix(:,2));
    wrong_axis_matrix = repmat(high(1:2,1).', group_count, 1);
    exchanged_axes_rejected = ~isequal(wrong_axis_matrix(:,1), wrong_axis_matrix(:,2));
    reused_covariance = mean(high_path .* (5/4*high_path));
    reused_rejected = abs(reused_covariance) > metrics.path_component_covariance.covariance_tolerance_e2;
    assert(wrong_axis_rejected && wrong_broadcast_rejected && exchanged_axes_rejected && reused_rejected, ...
        'A spatial covariance, broadcast, or independent-path gate accepted its wrong-model control.');
    controls = struct('independent_wrong_axis_pair_count', group_count/2, ...
        'wrong_axis_covariance_e2', axis_stat.covariance_e2, ...
        'same_group_target_e2', 25, 'same_covariance_tolerance_e2', axis_stat.covariance_tolerance_e2, ...
        'wrong_axis_covariance_rejected', wrong_axis_rejected, ...
        'pixel_noise_as_group_noise_rejected', wrong_broadcast_rejected, ...
        'exchanged_axes_broadcast_rejected', exchanged_axes_rejected, ...
        'reused_path_covariance_e2', reused_covariance, 'reused_path_stream_rejected', reused_rejected);
end

function [metrics, temporal] = frameGroups(a)
    count = a.independent_frame_count;
    dimensions = [2 3];
    [cfg, geometry] = dualFixture(dimensions, false, 0, 0);
    fixed = [1 2 3; -1 -2 -3];
    model = alev4.createStructuredNoise(dimensions, struct( ...
        'shared', struct('fixed_offset_e', fixed, 'frame_noise_e', 4), ...
        'high_gain', struct('fixed_offset_e', fixed/2, 'frame_noise_e', 3), ...
        'low_gain', struct('fixed_offset_e', -fixed/4, 'frame_noise_e', 5)));
    shared = zeros(count,1); high_path = shared; low_path = shared; high = shared; low = shared;
    mean_high = 100 + fixed + fixed/2;
    mean_low = 100 + fixed - fixed/4;
    fixed_difference_maximum_error = 0;
    % Retain scalar observations only; release each complete frame on reuse.
    for k = 1:count
        seed = mod(62500 + 64*(k-1), 4294967296);
        r = alev4.simulateStructuredExposure(100*ones(dimensions), cfg, 1, seed, model, geometry);
        assertUnclipped(r);
        if k == 1, maps = r.active_maps; else, assert(isequal(maps, r.active_maps)); end
        shared(k) = r.components.shared.frame_e;
        high_path(k) = r.components.high_gain.frame_e;
        low_path(k) = r.components.low_gain.frame_e;
        centered_high = r.readout.high_gain.read_electrons - mean_high;
        centered_low = r.readout.low_gain.read_electrons - mean_low;
        near(centered_high, (shared(k)+high_path(k))*ones(dimensions));
        near(centered_low, (shared(k)+low_path(k))*ones(dimensions));
        high(k) = centered_high(1,1); low(k) = centered_low(1,1);
        if mod(k,2) == 1
            prior_high = r.readout.high_gain.read_electrons;
            prior_low = r.readout.low_gain.read_electrons;
        else
            high_difference = r.readout.high_gain.read_electrons-prior_high;
            low_difference = r.readout.low_gain.read_electrons-prior_low;
            expected_high = (shared(k)-shared(k-1)) + (high_path(k)-high_path(k-1));
            expected_low = (shared(k)-shared(k-1)) + (low_path(k)-low_path(k-1));
            near(high_difference, expected_high*ones(dimensions));
            near(low_difference, expected_low*ones(dimensions));
            fixed_difference_maximum_error = max([fixed_difference_maximum_error; ...
                abs(high_difference(:)-expected_high); abs(low_difference(:)-expected_low)]);
        end
    end
    metrics = struct('sample_count', count, 'image_size', dimensions, ...
        'sample_unit', 'independent frame; six pixels do not multiply the sample count', ...
        'shared_component', gaussianMoments(shared, 16, a), ...
        'high_component', gaussianMoments(high_path, 9, a), ...
        'low_component', gaussianMoments(low_path, 25, a), ...
        'high_total', gaussianMoments(high, 25, a), ...
        'low_total', gaussianMoments(low, 41, a), ...
        'shared_high_covariance', gaussianCovariance(shared, high_path, 16, 9, 0, a), ...
        'shared_low_covariance', gaussianCovariance(shared, low_path, 16, 25, 0, a), ...
        'path_component_covariance', gaussianCovariance(high_path, low_path, 9, 25, 0, a), ...
        'cross_path_covariance', gaussianCovariance(high, low, 25, 41, 16, a));
    odd = (1:2:count).'; even = odd+1;
    lag_two_left = reshape([1:4:count; 2:4:count], [], 1);
    lag_two_right = lag_two_left+2;
    assert(numel(unique([lag_two_left;lag_two_right])) == count);
    temporal = struct('difference', gaussianMoments(high(even)-high(odd), 50, a), ...
        'lag_one', gaussianCovariance(high(odd), high(even), 25, 25, 0, a), ...
        'lag_two', gaussianCovariance(high(lag_two_left), high(lag_two_right), 25, 25, 0, a), ...
        'pair_count_per_lag', count/2, ...
        'pairing_policy', 'Disjoint pairs within each lag; no frame repeats within that lag.', ...
        'fixed_maps_unchanged', true, ...
        'fixed_pattern_difference_maximum_error_e', fixed_difference_maximum_error);
    reused_covariance = mean(high.^2);
    reused_covariance_bound = gaussianCovarianceTolerance(25, 25, count, a);
    repeated_frame_rejected = reused_covariance > reused_covariance_bound && ...
        ~within(0, temporal.difference.second_moment_lower_e2, temporal.difference.second_moment_upper_e2);
    assert(repeated_frame_rejected, 'Temporal gates accepted one reused frame-noise stream.');
    temporal.reused_frame_covariance_e2 = reused_covariance;
    temporal.reused_frame_covariance_tolerance_e2 = reused_covariance_bound;
    temporal.reused_frame_stream_rejected = repeated_frame_rejected;
end

function metrics = mixedComponents()
    dimensions = [5 7];
    [cfg, geometry] = dualFixture(dimensions, false, 1, 2);
    fixed = reshape((1:prod(dimensions))-18, dimensions)/8;
    model = alev4.createStructuredNoise(dimensions, struct('dark_shot_noise', false, ...
        'dark_current_e_per_s', 4, ...
        'shared', struct('fixed_offset_e', fixed, 'row_noise_e', 2, 'column_noise_e', 3, 'frame_noise_e', 4), ...
        'high_gain', struct('fixed_offset_e', 2*fixed, 'row_noise_e', 5, 'column_noise_e', 6, 'frame_noise_e', 7), ...
        'low_gain', struct('fixed_offset_e', -3*fixed, 'row_noise_e', 8, 'column_noise_e', 9, 'frame_noise_e', 10)));
    r = alev4.simulateStructuredExposure(100*ones(dimensions), cfg, 1, 62404, model, geometry);
    assertUnclipped(r);
    assert(all(r.readout.charge_electrons(:) == 104));
    for label = {'shared','high_gain','low_gain'}
        c = r.components.(label{1});
        assert(isequal(size(c.row_e), [dimensions(1) 1]));
        assert(isequal(size(c.column_e), [1 dimensions(2)]) && isscalar(c.frame_e));
        total = bsxfun(@plus, c.fixed_offset_e, c.row_e);
        total = bsxfun(@plus, total, c.column_e);
        total = total + c.frame_e;
        total = total + c.pixel_e;
        assert(isequal(total, c.total_e));
    end
    base = r.readout.charge_electrons + r.components.shared.total_e;
    assert(isequal(base+r.components.high_gain.total_e, r.readout.high_gain.read_electrons));
    assert(isequal(base+r.components.low_gain.total_e, r.readout.low_gain.read_electrons));
    metrics = struct('image_size', dimensions, 'exact_retained_component_sum', true, ...
        'one_shared_stored_charge', true, 'sample_count_for_iid_claims', 0, ...
        'interpretation', 'Deterministic assembly check only; mixed correlated pixels are not treated as IID.');
end

function stats = boundedMoments(values, target_mean, variance, fourth, a)
    values = values(:); n = numel(values);
    mean_tolerance = a.chebyshev_multiplier*sqrt(variance/n);
    variance_tolerance = a.chebyshev_multiplier*sqrt((fourth-(n-3)/(n-1)*variance^2)/n);
    observed_mean = mean(values); observed_variance = var(values,0);
    assert(abs(observed_mean-target_mean) <= mean_tolerance, 'Non-Gaussian mean exceeded its preregistered moment bound.');
    assert(abs(observed_variance-variance) <= variance_tolerance, 'Non-Gaussian variance exceeded its preregistered moment bound.');
    stats = struct('sample_count', n, 'mean_e', observed_mean, 'mean_target_e', target_mean, ...
        'mean_tolerance_e', mean_tolerance, 'variance_e2', observed_variance, ...
        'variance_target_e2', variance, 'variance_tolerance_e2', variance_tolerance, ...
        'fourth_central_moment_target_e4', fourth, ...
        'statistical_family', 'non_gaussian', 'comparison_count', 2);
end

function stats = boundedCovariance(x, y, target, product_variance, a)
    assert(numel(x) == numel(y)); n = numel(x);
    observed = mean(x(:).*y(:));
    tolerance = a.chebyshev_multiplier*sqrt(product_variance/n);
    assert(abs(observed-target) <= tolerance, 'Non-Gaussian covariance exceeded its exact-moment bound.');
    stats = struct('sample_count', n, 'covariance_e2', observed, ...
        'covariance_target_e2', target, 'covariance_tolerance_e2', tolerance, ...
        'product_variance_e4', product_variance, 'definition', 'Known-mean centered product', ...
        'statistical_family', 'non_gaussian', 'comparison_count', 1);
end

function stats = boundedSecondMoment(x, variance, fourth, a)
    n = numel(x); observed = mean(x(:).^2);
    tolerance = a.chebyshev_multiplier*sqrt((fourth-variance^2)/n);
    assert(abs(observed-variance) <= tolerance, 'Control second moment exceeded its exact-moment bound.');
    stats = struct('sample_count', n, 'second_moment_e2', observed, ...
        'second_moment_target_e2', variance, 'second_moment_tolerance_e2', tolerance, ...
        'fourth_central_moment_target_e4', fourth, ...
        'statistical_family', 'non_gaussian', 'comparison_count', 1);
end

function stats = gaussianMoments(values, variance, a)
    values = values(:); n = numel(values);
    mean_tolerance = sqrt(2*variance*a.gaussian_t/n);
    [lower, upper] = gaussianSecondBounds(variance, n, a);
    observed_mean = mean(values); second = mean(values.^2);
    assert(abs(observed_mean) <= mean_tolerance, 'Gaussian mean exceeded its preregistered normal-tail bound.');
    assert(within(second, lower, upper), 'Gaussian second moment exceeded its chi-square concentration bounds.');
    stats = struct('sample_count', n, 'mean_e', observed_mean, 'mean_target_e', 0, ...
        'mean_tolerance_e', mean_tolerance, 'second_moment_e2', second, ...
        'second_moment_target_e2', variance, 'second_moment_lower_e2', lower, ...
        'second_moment_upper_e2', upper, 'statistical_family', 'gaussian', 'comparison_count', 2);
end

function stats = gaussianCovariance(x, y, vx, vy, target, a)
    assert(numel(x) == numel(y)); n = numel(x);
    observed = mean(x(:).*y(:));
    tolerance = gaussianCovarianceTolerance(vx, vy, n, a);
    assert(abs(observed-target) <= tolerance, 'Gaussian covariance exceeded its polarization concentration bound.');
    stats = struct('sample_count', n, 'covariance_e2', observed, 'covariance_target_e2', target, ...
        'covariance_tolerance_e2', tolerance, 'definition', 'Known-mean centered product; Gaussian polarization', ...
        'statistical_family', 'gaussian', 'comparison_count', 1);
end

function tolerance = gaussianCovarianceTolerance(vx, vy, n, a)
    % U=X/sqrt(vx)+Y/sqrt(vy), V=X/sqrt(vx)-Y/sqrt(vy).
    % Their variances sum to four even when X and Y are correlated.
    % Apply the two chi-square bounds and a union bound: <=4*exp(-t).
    tolerance = sqrt(vx*vy)*(2*sqrt(a.gaussian_t/n)+2*a.gaussian_t/n);
end

function [lower, upper] = gaussianSecondBounds(variance, n, a)
    lower = variance*(1-2*sqrt(a.gaussian_t/n));
    upper = variance*(1+2*sqrt(a.gaussian_t/n)+2*a.gaussian_t/n);
end

function yes = within(value, lower, upper)
    yes = value >= lower && value <= upper;
end

function count = comparisonCount(value, family)
    count = 0;
    if ~isstruct(value), return; end
    if isfield(value, 'statistical_family')
        if strcmp(value.statistical_family, family), count = value.comparison_count; end
        return;
    end
    names = fieldnames(value);
    for k = 1:numel(names), count = count+comparisonCount(value.(names{k}), family); end
end

function [cfg, geometry] = dualFixture(dimensions, shot, high_sigma, low_sigma)
    geometry = alev4.createSensorGeometry(struct('full_grid_size', dimensions, 'pixel_pitch_m', 1));
    sensor = struct('image_size', dimensions, 'wavelength_nm', 550, ...
        'bin_width_nm', 1, 'qe', ones(1,3), 'pixel_pitch_m', 1, ...
        'fill_factor', 1, 'shot_noise', shot);
    cfg = alev4.createDualGainSensor(struct('sensor', sensor, ...
        'high_gain', struct('read_noise_e', high_sigma, 'black_level_dn', 1024, 'adc_bits', 16), ...
        'low_gain', struct('read_noise_e', low_sigma, 'black_level_dn', 1024, 'adc_bits', 16)));
end

function assertUnclipped(result)
    r = result.readout;
    assert(~any(r.full_well_saturated(:)), 'A statistical fixture reached physical full well.');
    for label = {'high_gain','low_gain'}
        p = r.(label{1});
        assert(~any(p.adc_low_clipped(:) | p.adc_high_clipped(:)) && all(p.adc_usable(:)), ...
            'A statistical fixture reached an ADC rail; no observations may be discarded.');
    end
end

function near(actual, expected)
    magnitude = max([1; abs(actual(:)); abs(expected(:)); 100]);
    assert(isequal(size(actual), size(expected)) && ...
        all(abs(actual(:)-expected(:)) <= 32*eps(magnitude)), ...
        'Retained frame components or fixed-map cancellation disagree beyond 32 ULPs.');
end
