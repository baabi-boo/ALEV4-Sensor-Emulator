function grid = sensorGrid(geometry)
%SENSORGRID Return active physical edges/centres and full-grid CFA parity.
%   Coordinates are image coordinates in metres, x rightward and y downward.
%   Only one-dimensional vectors for the active ROI are allocated.
    geometry = alev4.createSensorGeometry(geometry);
    roi = geometry.active_roi;
    p = geometry.pixel_pitch_m;
    origin = geometry.origin_xy_m;
    xindex = (roi(2)-1):(roi(2)+roi(4)-1);
    yindex = (roi(1)-1):(roi(1)+roi(3)-1);
    xedges = origin(1)+xindex*p;
    yedges = origin(2)+yindex*p;
    xcentres = origin(1)+(xindex(1:end-1)+0.5)*p;
    ycentres = origin(2)+(yindex(1:end-1)+0.5)*p;
    if any(diff(xedges) <= 0) || any(diff(yedges) <= 0) || ...
            any(abs(diff(xedges)/p-1) > 1e-6) || any(abs(diff(yedges)/p-1) > 1e-6) || ...
            any(xcentres <= xedges(1:end-1) | xcentres >= xedges(2:end)) || ...
            any(ycentres <= yedges(1:end-1) | ycentres >= yedges(2:end))
        error('ALEV4:GeometryNumericRange', 'Pixel edges or centres are not representable.');
    end
    tile = reshape(geometry.full_grid_cfa_pattern, 2, 2).';
    active_tile = tile(mod(roi(1)-1+(0:1),2)+1, mod(roi(2)-1+(0:1),2)+1);
    pattern = reshape(active_tile.',1,[]);
    grid = struct('x_edges_m',xedges, 'y_edges_m',yedges, ...
        'x_centers_m',xcentres, 'y_centers_m',ycentres, ...
        'image_size',roi(3:4), 'cfa_pattern',pattern, ...
        'full_extent_xy_m',fliplr(geometry.full_grid_size)*p, ...
        'active_extent_xy_m',fliplr(roi(3:4))*p, ...
        'full_bounds_xy_m',[origin; origin+fliplr(geometry.full_grid_size)*p], ...
        'active_bounds_xy_m',[xedges(1) yedges(1); xedges(end) yedges(end)]);
end
