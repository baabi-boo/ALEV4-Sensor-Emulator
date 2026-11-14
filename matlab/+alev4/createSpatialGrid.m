function grid = createSpatialGrid(overrides)
%CREATESPATIALGRID Validate rectangular cell edges for spectral irradiance.
%   Values on this grid are CELL AVERAGES, not samples at the cell centres.
%   Coordinates are metres, x increases with columns, and y with rows. Edges
%   are authoritative; this function never sorts, snaps, or infers them.
%   The generic default matches the default 32-by-32 geometry. Descriptors
%   support at most 100 million cells; this is not a memory/throughput claim.
    grid = struct('schema_version', '1.0', ...
        'x_edges_m', (0:32)*6e-6, 'y_edges_m', (0:32)*6e-6, ...
        'units', 'm', 'sample_semantics', 'cell_average');
    if nargin < 1, overrides = struct(); end
    if ~isstruct(overrides) || ~isscalar(overrides)
        error('ALEV4:InvalidSpatialGrid', 'Spatial-grid overrides must be a scalar struct.');
    end
    names = fieldnames(overrides);
    for k = 1:numel(names)
        if ~isfield(grid, names{k})
            error('ALEV4:UnknownSpatialGridField', 'Unknown spatial-grid field: %s.', names{k});
        end
        grid.(names{k}) = overrides.(names{k});
    end
    requireText(grid.schema_version, '1.0', 'schema_version');
    requireText(grid.units, 'm', 'units');
    requireText(grid.sample_semantics, 'cell_average', 'sample_semantics');
    grid.x_edges_m = requireEdges(grid.x_edges_m, 'x_edges_m');
    grid.y_edges_m = requireEdges(grid.y_edges_m, 'y_edges_m');
    nx = numel(grid.x_edges_m)-1;
    ny = numel(grid.y_edges_m)-1;
    if nx > 1e8 || ny > 1e8 || ny > 1e8/nx
        error('ALEV4:InvalidSpatialGrid', 'Spatial grids support at most 100 million cells.');
    end
    dx = diff(grid.x_edges_m);
    dy = diff(grid.y_edges_m);
    if min(dx)*min(dy) == 0 || ~isfinite(max(dx)*max(dy))
        error('ALEV4:SpatialNumericRange', 'Cell areas must be positive finite representable numbers.');
    end
end

function requireText(value, expected, name)
    if ~ischar(value) || ~isrow(value) || ~strcmp(value, expected)
        error('ALEV4:InvalidSpatialGrid', '%s must be the character row %s.', name, expected);
    end
end

function edges = requireEdges(edges, name)
    if ~isnumeric(edges) || ~isreal(edges) || ~isvector(edges) || ...
            numel(edges) < 2 || numel(edges) > 1e8+1 || any(~isfinite(edges(:)))
        error('ALEV4:InvalidSpatialGrid', '%s must contain at least two finite real edges.', name);
    end
    edges = full(double(edges(:).'));
    widths = diff(edges);
    if any(~isfinite(widths)) || any(widths <= 0) || ...
            ~isfinite(edges(end)-edges(1))
        error('ALEV4:InvalidSpatialGrid', '%s must have positive finite widths and extent.', name);
    end
end
