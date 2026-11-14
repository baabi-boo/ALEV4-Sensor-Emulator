function [irradiance, grid] = validateSpatialIrradiance(irradiance, grid)
%VALIDATESPATIALIRRADIANCE Validate cell-average spectral photon density.
%   Data are H-by-W-by-K in photons/(m^2 s nm), with one unmodified spectral
%   plane per readout bin. The exposure wrapper validates that association.
%   One-bin sparse matrices are accepted and normalized to dense doubles.
%   At most 100 million numeric samples are supported per input/output cube.
    if nargin ~= 2
        error('ALEV4:InvalidSpatialIrradiance', 'Irradiance and its spatial grid are required.');
    end
    grid = alev4.createSpatialGrid(grid);
    if ~isnumeric(irradiance) || ~isreal(irradiance) || isempty(irradiance) || ...
            ndims(irradiance) > 3 || numel(irradiance) > 1e8 || ...
            size(irradiance,1) ~= numel(grid.y_edges_m)-1 || ...
            size(irradiance,2) ~= numel(grid.x_edges_m)-1 || ...
            any(~isfinite(irradiance(:))) || any(irradiance(:) < 0)
        error('ALEV4:InvalidSpatialIrradiance', ...
            'Irradiance must be a finite nonnegative H-by-W-by-K numeric cube matching the grid.');
    end
    irradiance = full(double(irradiance));
end
