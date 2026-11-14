function [averages, grid, report] = isetPointGrid(point_photons, x_samples_m, y_samples_m, x_edges_m, y_edges_m)
%ISETPOINTGRID Explicit bilinear point reconstruction to exact cell averages.
%   ISET optical images contain point samples. This helper defines their
%   bilinear reconstruction inside the rectangular point-support domain.
%   Each requested cell must stay inside one native bilinear patch: every
%   interior native knot must appear among the supplied cell edges. The
%   average then equals the arithmetic mean of its four corner values.
%   Nothing is extrapolated; original point samples are never relabelled as
%   cell averages. Photon density units remain photons/(m^2 s nm).
    if nargin ~= 5
        error('ALEV4:ISETPointGridArguments', 'Point data, two sample axes, and two cell-edge axes are required.');
    end
    x = pointAxis(x_samples_m, 'x_samples_m');
    y = pointAxis(y_samples_m, 'y_samples_m');
    if ~isnumeric(point_photons) || ~isreal(point_photons) || ...
            isempty(point_photons) || ndims(point_photons) > 3 || ...
            size(point_photons,1) ~= numel(y) || size(point_photons,2) ~= numel(x) || ...
            numel(point_photons) > 1e8 || any(~isfinite(point_photons(:))) || ...
            any(point_photons(:) < 0)
        error('ALEV4:ISETPointSamples', 'Point irradiance must be a matching finite nonnegative spectral cube.');
    end
    point_photons = full(double(point_photons));
    grid = alev4.createSpatialGrid(struct('x_edges_m',x_edges_m,'y_edges_m',y_edges_m));
    xe = grid.x_edges_m;
    ye = grid.y_edges_m;
    if xe(1) < x(1) || xe(end) > x(end) || ye(1) < y(1) || ye(end) > y(end)
        error('ALEV4:ISETPointCoverage', 'Cells must lie inside the complete native point-support rectangle.');
    end
    if ~all(ismember(x(x > xe(1) & x < xe(end)),xe)) || ...
            ~all(ismember(y(y > ye(1) & y < ye(end)),ye))
        error('ALEV4:ISETPointKnots', 'Each cell must stay inside one native bilinear patch; retain all interior knots.');
    end
    [xl,xu] = checkFractions(x,xe);
    [yl,yu] = checkFractions(y,ye);
    shape = [numel(ye)-1 numel(xe)-1 size(point_photons,3)];
    if prod(shape(1:2)) > 1e8/shape(3)
        error('ALEV4:ISETPointSamples', 'Converted cubes support at most 100 million numeric samples.');
    end
    [xx,yy] = meshgrid(xe,ye);
    averages = zeros(shape);
    for k = 1:shape(3)
        plane = point_photons(:,:,k);
        scale = max(plane(:));
        if scale == 0, continue; end
        normalized = plane/scale;
        if any(normalized(plane > 0) < realmin)
            error('ALEV4:ISETPointNumericRange', ...
                'Point-sample normalization loses relative precision in a positive value.');
        end
        corners = interp2(x,y,normalized,xx,yy,'linear');
        if any(corners(:) == 0)
            supported = plane(yl,xl)>0 | plane(yl,xu)>0 | ...
                plane(yu,xl)>0 | plane(yu,xu)>0;
            if any(corners(supported) == 0)
                error('ALEV4:ISETPointNumericRange', ...
                    'Positive bilinear support underflowed to zero.');
            end
        end
        if any(corners(:) > 0 & corners(:) < realmin)
            error('ALEV4:ISETPointNumericRange', ...
                'Normalized interpolation is below the supported relative-precision range.');
        end
        % Unit-scale interpolation and averaging avoid artificial overflow
        % or division underflow when the entire field has an extreme scale.
        cell_average = corners(1:end-1,1:end-1)/4 + ...
            corners(2:end,1:end-1)/4 + corners(1:end-1,2:end)/4 + ...
            corners(2:end,2:end)/4;
        if any(cell_average(:) > 0 & cell_average(:) < realmin)
            error('ALEV4:ISETPointNumericRange', ...
                'Normalized averaging is below the supported relative-precision range.');
        end
        converted = cell_average*scale;
        if any(converted(cell_average > 0) == 0)
            error('ALEV4:ISETPointNumericRange', 'A positive cell-average irradiance is not representable.');
        end
        averages(:,:,k) = converted;
    end
    if any(~isfinite(averages(:))) || any(averages(:) < 0)
        error('ALEV4:ISETPointSamples', 'Bilinear reconstruction exceeded the supported numeric range.');
    end
    report = struct('method','bilinear_point_reconstruction_exact_cell_average', ...
        'source_semantics','point_samples','output_semantics','cell_average', ...
        'boundary_policy','no_extrapolation', ...
        'native_point_shape',[numel(y) numel(x) size(point_photons,3)], ...
        'cell_shape',shape,'all_native_knots_retained',true, ...
        'units','photons m^-2 s^-1 nm^-1');
end

function [lower_indices,upper_indices] = checkFractions(samples, edges)
    % An interior coordinate that rounds to either enclosing knot can erase
    % an illuminated contribution even when the physical mean is normal.
    % Reject that unsupported representation before interp2 can hide it.
    lower_indices = zeros(size(edges));
    upper_indices = zeros(size(edges));
    lower = 1;
    for k = 1:numel(edges)
        coordinate = edges(k);
        while lower < numel(samples)-1 && coordinate >= samples(lower+1)
            lower = lower+1;
        end
        if coordinate == samples(lower)
            lower_indices(k) = lower;
            upper_indices(k) = lower;
            continue;
        elseif coordinate == samples(lower+1)
            lower_indices(k) = lower+1;
            upper_indices(k) = lower+1;
            continue;
        end
        lower_indices(k) = lower;
        upper_indices(k) = lower+1;
        width = samples(lower+1)-samples(lower);
        fractions = [(coordinate-samples(lower))/width, ...
            (samples(lower+1)-coordinate)/width];
        if any(fractions < realmin) || any(fractions >= 1)
            error('ALEV4:ISETPointNumericRange', ...
                'An interior reconstruction coordinate loses its fractional support.');
        end
    end
end

function axis = pointAxis(axis, name)
    if ~isnumeric(axis) || ~isreal(axis) || ~isvector(axis) || ...
            numel(axis) < 2 || numel(axis) > 1e8 || any(~isfinite(axis(:)))
        error('ALEV4:ISETPointSamples', '%s must be a finite real sample-position vector.',name);
    end
    axis = full(double(axis(:).'));
    if any(diff(axis) <= 0) || any(~isfinite(diff(axis))) || ~isfinite(axis(end)-axis(1))
        error('ALEV4:ISETPointSamples', '%s must be strictly increasing with finite extent.',name);
    end
end
