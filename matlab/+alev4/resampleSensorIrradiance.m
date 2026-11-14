function [sampled, report] = resampleSensorIrradiance(irradiance, input_grid, geometry)
%RESAMPLESENSORIRRADIANCE Conservatively average a rectangular spectral grid.
%   The source is piecewise constant in each explicitly bounded cell. Each
%   target value is its area average over a complete active photosite, still
%   in photons/(m^2 s nm). Area, QE, fill factor, time, and spectral-bin width
%   are deliberately NOT applied here. No random numbers are consumed.
%   Coverage is exact in represented coordinates: no extrapolation, edge
%   snapping, or partial-footprint normalization is performed. Exact aligned
%   source subgrids take a direct slicing path, preserving identity values.
    if nargin ~= 3
        error('ALEV4:InvalidSpatialSampling', 'Irradiance, input grid, and geometry are required.');
    end
    [irradiance, input_grid] = alev4.validateSpatialIrradiance(irradiance, input_grid);
    geometry = alev4.createSensorGeometry(geometry);
    bands = size(irradiance,3);
    if prod(geometry.active_roi(3:4)) > 1e8/bands
        error('ALEV4:InvalidSpatialSampling', 'Output cubes support at most 100 million numeric samples.');
    end
    target = alev4.sensorGrid(geometry);
    sx = input_grid.x_edges_m;
    sy = input_grid.y_edges_m;
    tx = target.x_edges_m;
    ty = target.y_edges_m;
    if tx(1) < sx(1) || tx(end) > sx(end) || ty(1) < sy(1) || ty(end) > sy(end)
        error('ALEV4:SpatialCoverage', 'Source cells must cover every complete active photosite footprint.');
    end
    col_start = alignedStart(sx, tx);
    row_start = alignedStart(sy, ty);
    aligned = col_start > 0 && row_start > 0;
    if aligned
        sampled = irradiance(row_start:row_start+target.image_size(1)-1, ...
            col_start:col_start+target.image_size(2)-1, :);
        x_nnz = target.image_size(2);
        y_nnz = target.image_size(1);
        x_error = 0;
        y_error = 0;
    else
        if any(irradiance(:) > 0 & irradiance(:) < realmin)
            error('ALEV4:SpatialNumericRange', 'Weighted averaging does not support positive subnormal input values.');
        end
        [wx, x_error] = axisWeights(sx, tx);
        [wy, y_error] = axisWeights(sy, ty);
        x_nnz = nnz(wx);
        y_nnz = nnz(wy);
        sampled = zeros([target.image_size bands]);
        for band = 1:bands
            % Choose the smaller separable intermediate. Oppositely shaped
            % singleton grids must not create an Htarget-by-Wsource array
            % whose size can dwarf both input and output.
            if target.image_size(1)*size(irradiance,2) <= ...
                    size(irradiance,1)*target.image_size(2)
                sampled(:,:,band) = (wy*irradiance(:,:,band))*wx.';
            else
                sampled(:,:,band) = wy*(irradiance(:,:,band)*wx.');
            end
        end
        if any(~isfinite(sampled(:))) || any(sampled(:) < 0) || ...
                any(sampled(:) > 0 & sampled(:) < realmin)
            error('ALEV4:SpatialNumericRange', 'Spatial averaging exceeded the supported numeric range.');
        end
        if any(sampled(:) == 0) && any(irradiance(:) > 0)
            % A dark cell is exact; an illuminated footprint erased by
            % underflow is an unsupported numerical range. Boolean support
            % uses unit nonzeros so tiny overlap weights cannot erase it.
            for band = 1:bands
                if target.image_size(1)*size(irradiance,2) <= ...
                        size(irradiance,1)*target.image_size(2)
                    lit = (spones(wy)*double(irradiance(:,:,band)>0))*spones(wx).';
                else
                    lit = spones(wy)*(double(irradiance(:,:,band)>0)*spones(wx).');
                end
                plane = sampled(:,:,band);
                if any(plane(lit > 0) == 0)
                    error('ALEV4:SpatialNumericRange', 'Positive sampled irradiance underflowed to zero.');
                end
            end
        end
    end
    % Descriptive integrals are independently useful but not an acceptance
    % assertion. Overflow/underflow in these optional diagnostics does not
    % invalidate a finite density average; mark them explicitly unavailable.
    dx = diff(sx);
    dy = diff(sy);
    crop_dx = max(0,min(sx(2:end),tx(end))-max(sx(1:end-1),tx(1)));
    crop_dy = max(0,min(sy(2:end),ty(end))-max(sy(1:end-1),ty(1)));
    source_integral = areaIntegral(irradiance, dy, dx);
    source_crop_integral = areaIntegral(irradiance, crop_dy, crop_dx);
    target_integral = areaIntegral(sampled, diff(ty), diff(tx));
    report = struct('schema_version','1.0', ...
        'method','piecewise_constant_area_overlap', ...
        'input_units','photons m^-2 s^-1 nm^-1', ...
        'output_units','photons m^-2 s^-1 nm^-1', ...
        'sample_semantics','cell_average', ...
        'coverage_policy','require_full_footprint', ...
        'source_image_size',[size(irradiance,1) size(irradiance,2)], ...
        'output_image_size',target.image_size, 'spectral_plane_count',bands, ...
        'source_bounds_xy_m',[sx(1) sy(1); sx(end) sy(end)], ...
        'target_bounds_xy_m',target.active_bounds_xy_m, ...
        'active_roi',geometry.active_roi, 'active_cfa_pattern',target.cfa_pattern, ...
        'aligned_copy',aligned, 'identity',aligned && isequal(sx,tx) && isequal(sy,ty), ...
        'x_weight_nonzeros',x_nnz, 'y_weight_nonzeros',y_nnz, ...
        'x_max_row_sum_error',x_error, 'y_max_row_sum_error',y_error, ...
        'represented_pitch_relative_error',max([abs(diff(tx)/geometry.pixel_pitch_m-1), ...
            abs(diff(ty)/geometry.pixel_pitch_m-1)]), ...
        'integral_units','photons s^-1 nm^-1', ...
        'source_integral',source_integral, ...
        'source_crop_integral',source_crop_integral, ...
        'target_integral',target_integral);
end

function first = alignedStart(source, target)
    first = find(source == target(1), 1);
    if isempty(first) || first+numel(target)-1 > numel(source) || ...
            ~isequal(source(first:first+numel(target)-1),target)
        first = 0;
    end
end

function [weights, maximum_error] = axisWeights(source, target)
    ns = numel(source)-1;
    nt = numel(target)-1;
    maximum_entries = ns+nt-1;
    capacity = min(maximum_entries,4096);
    ri = zeros(1,capacity);
    ci = zeros(1,capacity);
    values = zeros(1,capacity);
    count = 0;
    source_index = 1;
    row_sums = zeros(1,nt);
    row_counts = zeros(1,nt);
    for destination_index = 1:nt
        left = target(destination_index);
        right = target(destination_index+1);
        width = right-left;
        while source_index < ns && source(source_index+1) <= left
            source_index = source_index+1;
        end
        current = source_index;
        while current <= ns && source(current) < right
            overlap = min(right,source(current+1))-max(left,source(current));
            if overlap > 0
                value = overlap/width;
                if ~isfinite(overlap) || ~isfinite(value) || value <= 0
                    error('ALEV4:SpatialNumericRange', 'A positive overlap has an unrepresentable normalized weight.');
                end
                count = count+1;
                if count > capacity
                    capacity = min(maximum_entries,max(capacity+1,2*capacity));
                    ri(capacity) = 0;
                    ci(capacity) = 0;
                    values(capacity) = 0;
                end
                ri(count) = destination_index;
                ci(count) = current;
                values(count) = value;
                row_sums(destination_index) = row_sums(destination_index)+value;
                row_counts(destination_index) = row_counts(destination_index)+1;
            end
            if source(current+1) >= right, break; end
            current = current+1;
        end
        source_index = current;
    end
    errors = abs(row_sums-1);
    tolerances = 64*eps*max(1,row_counts);
    if any(row_counts == 0) || any(errors > tolerances)
        error('ALEV4:SpatialNumericRange', 'Complete overlap fractions do not sum to unity within the arithmetic bound.');
    end
    weights = sparse(ri(1:count),ci(1:count),values(1:count),nt,ns);
    maximum_error = max(errors);
end

function diagnostic = areaIntegral(data, heights, widths)
    bands = size(data,3);
    totals = zeros(1,bands);
    available = true;
    for band = 1:bands
        plane = data(:,:,band);
        % Apply area in its natural units before summation. The supported
        % input-grid bounds guarantee finite nonzero complete-cell areas;
        % a tiny crop intersection may still underflow and is diagnosed.
        areas = heights(:)*widths(:).';
        active = heights(:) > 0 & widths(:).' > 0;
        if any(~isfinite(areas(:))) || any(areas(active) == 0)
            available = false;
            break;
        end
        terms = plane.*areas;
        total = sum(terms(:));
        if ~isfinite(total) || any(terms(plane > 0 & areas > 0) == 0)
            available = false;
            break;
        end
        totals(band) = total;
    end
    if available
        diagnostic = struct('status','available','values',totals);
    else
        diagnostic = struct('status','unavailable_numeric_range','values',[]);
    end
end
