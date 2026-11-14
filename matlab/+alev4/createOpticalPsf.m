function psf = createOpticalPsf(overrides)
%CREATEOPTICALPSF Validate a finite, explicitly sampled synthetic PSF.
%   PSF weights are dimensionless and must sum to one per spectral plane.
%   They are never silently renormalized. A shared kernel has wavelength_nm
%   empty; a wavelength-specific bank identifies every plane explicitly.
%   origin_rc is the one-based zero-displacement coefficient. Only valid
%   (complete-support) boundaries are supported. This is not an ARRI OLPF.
%   A nontrivial kernel override requires an explicit origin_rc.
    psf = struct('schema_version', '1.0', 'kernel', 1, ...
        'origin_rc', [1 1], 'spacing_yx_m', [6e-6 6e-6], ...
        'wavelength_nm', [], 'boundary_policy', 'valid', ...
        'parameter_sources', {{'ASSUMED-DISCRETE-PSF'}});
    if nargin < 1, overrides = struct(); end
    if ~isstruct(overrides) || ~isscalar(overrides)
        error('ALEV4:InvalidOpticalPsf', 'PSF overrides must be a scalar struct.');
    end
    names = fieldnames(overrides);
    for k = 1:numel(names)
        if ~isfield(psf, names{k})
            error('ALEV4:UnknownOpticalPsfField', 'Unknown PSF field: %s.', names{k});
        end
        psf.(names{k}) = overrides.(names{k});
    end
    if ~ischar(psf.schema_version) || ~isrow(psf.schema_version) || ...
            ~strcmp(psf.schema_version, '1.0') || ...
            ~ischar(psf.boundary_policy) || ~isrow(psf.boundary_policy) || ...
            ~strcmp(psf.boundary_policy, 'valid')
        error('ALEV4:InvalidOpticalPsf', 'PSF requires schema 1.0 and valid boundary policy.');
    end
    kernel = psf.kernel;
    if ~isnumeric(kernel) || ~isreal(kernel) || isempty(kernel) || ...
            ndims(kernel) > 3 || any(~isfinite(kernel(:))) || any(kernel(:) < 0) || ...
            size(kernel, 1) > 63 || size(kernel, 2) > 63 || numel(kernel) > 1e6
        error('ALEV4:InvalidOpticalPsf', ...
            'Kernel must be a finite nonnegative numeric array, at most 63 by 63 and one million weights.');
    end
    kernel = full(double(kernel));
    dims = [size(kernel, 1) size(kernel, 2)];
    if isfield(overrides, 'kernel') && any(dims > 1) && ~isfield(overrides, 'origin_rc')
        error('ALEV4:InvalidOpticalPsf', 'A nontrivial kernel requires an explicit origin_rc.');
    end
    origin = numericVector(psf.origin_rc, 2, 'origin_rc');
    if any(origin < 1 | origin ~= fix(origin) | origin > dims)
        error('ALEV4:InvalidOpticalPsf', 'origin_rc must identify one coefficient inside the kernel.');
    end
    spacing = numericVector(psf.spacing_yx_m, 2, 'spacing_yx_m');
    if any(spacing <= 0) || any(~isfinite(0.5./spacing)) || ...
            any(~isfinite((dims-1).*spacing))
        error('ALEV4:OpticalNumericRange', 'PSF spacing must give finite positive sampling and Nyquist frequencies.');
    end
    count = prod(dims);
    % A summation error allowance, not a radiometric calibration tolerance.
    tolerance = 32 * count * eps(1);
    for k = 1:size(kernel, 3)
        plane = kernel(:, :, k);
        mass = sum(plane(:));
        if ~isfinite(mass) || abs(mass-1) > tolerance
            error('ALEV4:InvalidOpticalPsf', 'Each PSF plane must already sum to one.');
        end
    end
    wave = psf.wavelength_nm;
    if ~isnumeric(wave) || ~isreal(wave) || ...
            (~isempty(wave) && ~isvector(wave)) || any(~isfinite(wave(:)))
        error('ALEV4:InvalidOpticalPsf', 'wavelength_nm must be an empty or finite numeric vector.');
    end
    if isempty(wave)
        if size(kernel, 3) ~= 1
            error('ALEV4:OpticalSpectralMapping', 'A kernel bank must explicitly identify every spectral plane.');
        end
        wave = [];
    else
        wave = full(double(wave(:)));
        if numel(wave) ~= size(kernel, 3) || any(wave <= 0) || any(diff(wave) <= 0)
            error('ALEV4:OpticalSpectralMapping', 'Kernel wavelengths must be positive, increasing, and one per plane.');
        end
    end
    sources = psf.parameter_sources;
    if ~iscell(sources) || ~isvector(sources) || isempty(sources) || numel(sources) > 32
        error('ALEV4:InvalidOpticalPsf', 'parameter_sources must contain source-record IDs.');
    end
    for k = 1:numel(sources)
        id = sources{k};
        if ~ischar(id) || ~isrow(id) || isempty(id) || numel(id) > 128 || ...
                isempty(regexp(id, '^[A-Za-z0-9][A-Za-z0-9_.-]*\z', 'once'))
            error('ALEV4:InvalidOpticalPsf', 'Invalid PSF parameter source ID.');
        end
    end
    if numel(unique(sources)) ~= numel(sources)
        error('ALEV4:InvalidOpticalPsf', 'PSF source IDs must be unique.');
    end
    psf.kernel = kernel;
    psf.origin_rc = origin;
    psf.spacing_yx_m = spacing;
    psf.wavelength_nm = wave;
    psf.parameter_sources = reshape(sources, 1, []);
end

function value = numericVector(value, count, name)
    if ~isnumeric(value) || ~isreal(value) || ~isvector(value) || ...
            numel(value) ~= count || any(~isfinite(value(:)))
        error('ALEV4:InvalidOpticalPsf', '%s must contain %d finite real numbers.', name, count);
    end
    value = full(double(value(:).'));
end
