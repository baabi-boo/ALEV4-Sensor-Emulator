function maps = structuredNoiseMaps(model, geometry)
%STRUCTUREDNOISEMAPS Select explicit fixed maps using full-grid ROI indices.
%   MAPS = alev4.structuredNoiseMaps(MODEL, GEOMETRY) validates the separate
%   model and existing geometry, requiring an exact full-grid-size match.
%   It expands scalar uniform maps only to the active ROI, and crops matrix
%   maps using one-based full-grid coordinates. The six output fields are
%   prnu, dark_current_e_per_s, shared, single, high_gain, and low_gain.
%   Every fixed value is a dense double active matrix; each named electronic
%   path also retains its scalar row_noise_e, column_noise_e, frame_noise_e.
%
%   The supplied maps define a persistent realization across crops. This
%   helper creates no random maps or temporal draws and changes no caller
%   values. A disabled model is still fully validated and can be inspected.

    if nargin ~= 2
        error('ALEV4:StructuredNoiseArguments', ...
            'A structured-noise model and sensor geometry are required.');
    end
    geometry = alev4.createSensorGeometry(geometry);
    model = alev4.createStructuredNoise(geometry.full_grid_size, model);
    roi = geometry.active_roi;
    rows = roi(1):(roi(1) + roi(3) - 1);
    columns = roi(2):(roi(2) + roi(4) - 1);
    active_size = roi(3:4);
    maps = struct('prnu', cropMap(model.prnu, rows, columns, active_size), ...
        'dark_current_e_per_s', cropMap(model.dark_current_e_per_s, ...
            rows, columns, active_size));
    path_names = {'shared', 'single', 'high_gain', 'low_gain'};
    for k = 1:numel(path_names)
        name = path_names{k};
        component = model.(name);
        component.fixed_offset_e = cropMap( ...
            component.fixed_offset_e, rows, columns, active_size);
        maps.(name) = component;
    end
end

function active = cropMap(value, rows, columns, active_size)
    if isscalar(value)
        active = repmat(value, active_size);
    else
        active = value(rows, columns);
    end
end
