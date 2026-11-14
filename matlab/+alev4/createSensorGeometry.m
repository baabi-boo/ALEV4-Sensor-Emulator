function geometry = createSensorGeometry(overrides)
%CREATESENSORGEOMETRY Validate a separate square-pixel spatial geometry.
%   Sizes are [rows columns], ROI is one-based [row column height width],
%   and origin is [x y] at the full grid's outer upper-left corner in metres.
%   Defaults are assumed generic geometry, not calibrated ARRI parameters.
    geometry = struct('schema_version', '1.0', ...
        'full_grid_size', [32 32], 'active_roi', [1 1 32 32], ...
        'pixel_pitch_m', 6e-6, 'origin_xy_m', [0 0], ...
        'full_grid_cfa_pattern', 'RGGB', ...
        'parameter_sources', {{'ASSUMED-GENERIC-GEOMETRY', 'ASSUMED-CFA-ORIGIN'}});
    if nargin < 1, overrides = struct(); end
    if ~isstruct(overrides) || ~isscalar(overrides)
        error('ALEV4:InvalidGeometry', 'Geometry must be a scalar struct.');
    end
    names = fieldnames(overrides);
    for k = 1:numel(names)
        if ~isfield(geometry, names{k})
            error('ALEV4:UnknownGeometryField', 'Unknown geometry field: %s.', names{k});
        end
        geometry.(names{k}) = overrides.(names{k});
    end
    if ~ischar(geometry.schema_version) || ~isrow(geometry.schema_version) || ...
            ~strcmp(geometry.schema_version, '1.0')
        error('ALEV4:InvalidGeometry', 'Geometry schema_version must be 1.0.');
    end
    dims = vectorOf(geometry.full_grid_size, 2, 'full_grid_size');
    if any(dims < 1 | dims ~= fix(dims)) || any(dims > 1e8) || dims(1) > 1e8/dims(2)
        error('ALEV4:InvalidGeometry', 'Full grid must contain 1 through 100 million pixels.');
    end
    if isfield(overrides, 'full_grid_size') && ~isfield(overrides, 'active_roi')
        geometry.active_roi = [1 1 dims];
    end
    roi = vectorOf(geometry.active_roi, 4, 'active_roi');
    if any(roi < 1 | roi ~= fix(roi)) || any(roi(1:2) > dims) || ...
            any(roi(3:4) > dims-roi(1:2)+1)
        error('ALEV4:InvalidGeometry', 'Active ROI must be entirely inside the full grid.');
    end
    pitch = vectorOf(geometry.pixel_pitch_m, 1, 'pixel_pitch_m');
    if pitch <= 0 || ~isfinite(pitch^2) || pitch^2 == 0
        error('ALEV4:InvalidGeometry', 'Pitch must have positive finite representable area.');
    end
    origin = vectorOf(geometry.origin_xy_m, 2, 'origin_xy_m');
    extent = fliplr(dims)*pitch;
    far = origin+extent;
    % A finite origin can erase micrometre differences. Retain enough
    % precision for edges and half-pitch centres over the complete grid.
    if any(~isfinite(extent)) || any(~isfinite(far)) || any(far <= origin) || ...
            any(pitch <= 4*eps(max(abs([origin; far]), [], 1))) || ...
            any(eps(max(abs([origin; far]), [], 1))/pitch > 1e-6)
        error('ALEV4:GeometryNumericRange', 'Coordinates cannot resolve the configured pixel pitch.');
    end
    pattern = geometry.full_grid_cfa_pattern;
    if ~ischar(pattern) || ~isrow(pattern) || ...
            ~any(strcmp(upper(pattern), {'RGGB','BGGR','GRBG','GBRG'}))
        error('ALEV4:InvalidGeometry', 'full_grid_cfa_pattern must be a supported Bayer pattern.');
    end
    sources = geometry.parameter_sources;
    if ~iscell(sources) || ~isvector(sources) || isempty(sources) || numel(sources) > 32
        error('ALEV4:InvalidGeometry', 'parameter_sources must be a nonempty cell vector of source IDs.');
    end
    for k = 1:numel(sources)
        id = sources{k};
        if ~ischar(id) || ~isrow(id) || isempty(id) || numel(id) > 128 || ...
                isempty(regexp(id, '^[A-Za-z0-9][A-Za-z0-9_.-]*\z', 'once'))
            error('ALEV4:InvalidGeometry', 'Invalid parameter source ID.');
        end
    end
    if numel(unique(sources)) ~= numel(sources)
        error('ALEV4:InvalidGeometry', 'Parameter source IDs must be unique.');
    end
    geometry.full_grid_size = dims;
    geometry.active_roi = roi;
    geometry.pixel_pitch_m = pitch;
    geometry.origin_xy_m = origin;
    geometry.full_grid_cfa_pattern = upper(pattern);
    geometry.parameter_sources = reshape(sources, 1, []);
end

function value = vectorOf(value, count, name)
    if ~isnumeric(value) || ~isreal(value) || ~isvector(value) || ...
            numel(value) ~= count || any(~isfinite(value(:)))
        error('ALEV4:InvalidGeometry', '%s must contain %d finite real numbers.', name, count);
    end
    value = full(double(value(:).'));
end
