function [filtered, filtered_grid, report] = applyOpticalPsf(irradiance, grid, psf, wavelength_nm)
%APPLYOPTICALPSF Convolve spectral irradiance with complete-support cropping.
%   Input/output are cell-average photons/(m^2 s nm). No pixel area, exposure,
%   fill factor or spectral response is applied here. Both spatial axes must
%   be uniform and match PSF spacing. All declared kernel positions require
%   support, including zero border coefficients. No boundary renormalization.
%   WAVELENGTH_NM is mandatory for a wavelength-specific kernel bank.
    if nargin < 3
        error('ALEV4:OpticalArguments', 'Irradiance, grid, and explicit PSF are required.');
    end
    if nargin < 4, wavelength_nm = []; end
    [irradiance, grid] = alev4.validateSpatialIrradiance(irradiance, grid);
    psf = alev4.createOpticalPsf(psf);
    requireUniform(grid.y_edges_m, psf.spacing_yx_m(1));
    requireUniform(grid.x_edges_m, psf.spacing_yx_m(2));
    bins = size(irradiance, 3);
    if ~isnumeric(wavelength_nm) || ~isreal(wavelength_nm) || ...
            (~isempty(wavelength_nm) && ~isvector(wavelength_nm)) || ...
            any(~isfinite(wavelength_nm(:)))
        error('ALEV4:OpticalSpectralMapping', 'Input wavelengths must be finite numeric spectral centres.');
    end
    if ~isempty(wavelength_nm)
        wavelength_nm = full(double(wavelength_nm(:)));
        if numel(wavelength_nm) ~= bins || any(wavelength_nm <= 0) || any(diff(wavelength_nm) <= 0)
            error('ALEV4:OpticalSpectralMapping', 'Input wavelengths must identify every irradiance plane.');
        end
    end
    if ~isempty(psf.wavelength_nm) && ~isequal(psf.wavelength_nm, wavelength_nm)
        error('ALEV4:OpticalSpectralMapping', 'PSF wavelengths must exactly match the supplied spectral planes.');
    end
    dims = [size(irradiance, 1) size(irradiance, 2)];
    support = [size(psf.kernel, 1) size(psf.kernel, 2)];
    if any(support > dims)
        error('ALEV4:OpticalSupport', 'Input does not contain the complete declared PSF support.');
    end
    first = support-psf.origin_rc+1;
    last = dims-psf.origin_rc+1;
    if all(support == 1) && all(psf.kernel(:) == 1)
        filtered = irradiance;
        filtered_grid = grid;
    else
        if any(irradiance(:) > 0 & irradiance(:) < realmin)
            error('ALEV4:OpticalNumericRange', 'Weighted convolution does not support positive subnormal inputs.');
        end
        filtered = zeros(dims(1)-support(1)+1, dims(2)-support(2)+1, bins);
        for k = 1:bins
            if isempty(psf.wavelength_nm), plane = 1; else, plane = k; end
            weights = psf.kernel(:, :, plane);
            source = irradiance(:, :, k);
            values = conv2(source, weights, 'valid');
            if any(~isfinite(values(:))) || any(values(:) < 0) || ...
                    any(values(:) > 0 & values(:) < realmin)
                error('ALEV4:OpticalNumericRange', 'Optical convolution exceeds the supported numeric range.');
            end
            % Distinguish an exact dark footprint from underflow erasing all
            % positive incident contributions in a supported footprint.
            if any(values(:) == 0) && any(source(:) > 0)
                positive_support = conv2(double(source > 0), double(weights > 0), 'valid') > 0;
                if any(values(positive_support) == 0)
                    error('ALEV4:OpticalNumericRange', 'Positive optical signal underflowed to zero.');
                end
            end
            filtered(:, :, k) = values;
        end
        filtered_grid = grid;
        filtered_grid.y_edges_m = grid.y_edges_m(first(1):last(1)+1);
        filtered_grid.x_edges_m = grid.x_edges_m(first(2):last(2)+1);
        filtered_grid = alev4.createSpatialGrid(filtered_grid);
    end
    report = struct('schema_version', '1.0', 'method', 'discrete_spectral_convolution', ...
        'boundary_policy', 'valid', 'normalization_policy', 'validated_unit_sum_no_renormalization', ...
        'input_units', 'photons m^-2 s^-1 nm^-1', ...
        'output_units', 'photons m^-2 s^-1 nm^-1', ...
        'kernel_shape', [support size(psf.kernel, 3)], ...
        'origin_rc', psf.origin_rc, 'spacing_yx_m', psf.spacing_yx_m, ...
        'retained_row_indices', [first(1) last(1)], ...
        'retained_column_indices', [first(2) last(2)], ...
        'required_halo_top_bottom_left_right', ...
        [support(1)-psf.origin_rc(1) psf.origin_rc(1)-1 ...
         support(2)-psf.origin_rc(2) psf.origin_rc(2)-1], ...
        'input_shape', [dims bins], ...
        'output_shape', [size(filtered,1) size(filtered,2) bins], ...
        'synthetic', true, 'calibrated_alev4', false);
end

function requireUniform(edges, spacing)
    widths = diff(edges);
    % Account for subtraction of nonzero physical edge coordinates, without
    % a metre-sized tolerance floor. Reject poorly resolved coordinates.
    tolerance = 8*max(eps(abs(edges))) + 32*eps(spacing);
    if tolerance >= spacing/1024
        error('ALEV4:OpticalNumericRange', 'Coordinates cannot resolve PSF sampling reliably.');
    end
    if any(abs(widths-spacing) > tolerance)
        error('ALEV4:OpticalGridMismatch', 'PSF requires uniform cells matching its physical spacing.');
    end
end
