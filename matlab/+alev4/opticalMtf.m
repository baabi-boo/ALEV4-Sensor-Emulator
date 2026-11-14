function report = opticalMtf(psf, fx_cycles_per_m, fy_cycles_per_m, pixel_pitch_m)
%OPTICALMTF Direct complex transfer of the declared finite discrete kernel.
%   Frequencies are vectors in cycles/metre within the principal Nyquist
%   rectangle. Output arrays have [numel(fy),numel(fx),kernel_planes].
%   Optional square-pixel sinc is a separate continuous-field analytical
%   reference, not the transfer of every discrete cell-average sampler.
    if nargin < 3
        error('ALEV4:OpticalArguments', 'PSF and physical x/y frequency vectors are required.');
    end
    psf = alev4.createOpticalPsf(psf);
    fx = frequencyVector(fx_cycles_per_m);
    fy = frequencyVector(fy_cycles_per_m);
    if numel(fx) > 1e6/numel(fy) || ...
            numel(fx)*numel(fy) > 1e6/size(psf.kernel,3)
        error('ALEV4:OpticalNumericRange', 'MTF output is limited to one million frequency samples.');
    end
    nyquist = 0.5./psf.spacing_yx_m;
    if any(abs(fx) > nyquist(2)) || any(abs(fy) > nyquist(1))
        error('ALEV4:OpticalFrequencyRange', 'Requested frequencies exceed the PSF sampling Nyquist rectangle.');
    end
    % Multiply frequency by spacing first, keeping finite phase arithmetic
    % even when individually valid SI coordinates have extreme magnitudes.
    xphase = fx*psf.spacing_yx_m(2);
    yphase = fy*psf.spacing_yx_m(1);
    otf = complex(zeros(numel(fy), numel(fx), size(psf.kernel,3)));
    for k = 1:size(psf.kernel,3)
        values = complex(zeros(numel(fy),numel(fx)));
        for r = 1:size(psf.kernel,1)
            for c = 1:size(psf.kernel,2)
                displacement = bsxfun(@plus, ...
                    (r-psf.origin_rc(1))*yphase(:), ...
                    (c-psf.origin_rc(2))*xphase(:).');
                values = values + psf.kernel(r,c,k)*exp(-2*pi*1i*displacement);
            end
        end
        otf(:,:,k) = values;
    end
    report = struct('schema_version','1.0', 'model','finite_discrete_synthetic_kernel', ...
        'frequency_units','cycles m^-1', 'fx_cycles_per_m',fx, ...
        'fy_cycles_per_m',fy, 'optical_otf',otf, 'optical_mtf',abs(otf), ...
        'nyquist_yx_cycles_per_m',nyquist, 'origin_rc',psf.origin_rc, ...
        'spacing_yx_m',psf.spacing_yx_m, ...
        'kernel_shape',[size(psf.kernel,1) size(psf.kernel,2) size(psf.kernel,3)], ...
        'wavelength_nm',psf.wavelength_nm, ...
        'finite_support_statement','Only the explicitly supplied finite kernel is evaluated.', ...
        'synthetic',true, 'calibrated_alev4',false);
    if nargin >= 4
        if ~isnumeric(pixel_pitch_m) || ~isreal(pixel_pitch_m) || ...
                ~isscalar(pixel_pitch_m) || ~isfinite(pixel_pitch_m) || pixel_pitch_m <= 0
            error('ALEV4:InvalidOpticalAperture', 'Pixel pitch must be a positive finite scalar in metres.');
        end
        pixel_pitch_m = full(double(pixel_pitch_m));
        ax = fx*pixel_pitch_m;
        ay = fy*pixel_pitch_m;
        if any(~isfinite(ax)) || any(~isfinite(ay)) || ...
                any(~isfinite(pi*ax)) || any(~isfinite(pi*ay))
            error('ALEV4:OpticalNumericRange', 'Continuous aperture phase exceeds the supported numeric range.');
        end
        aperture = sincPi(ay(:))*sincPi(ax(:)).';
        report.pixel_pitch_m = pixel_pitch_m;
        report.pixel_aperture_otf = aperture;
        report.pixel_aperture_mtf = abs(aperture);
        report.optical_times_continuous_aperture_mtf = ...
            bsxfun(@times, abs(otf), abs(aperture));
        report.aperture_model = 'ideal_continuous_square_analytical_reference';
        report.aperture_caveat = ...
            'Not the measured transfer of the discrete cell-average sampler; do not apply averaging twice.';
    end
end

function value = frequencyVector(value)
    if ~isnumeric(value) || ~isreal(value) || ~isvector(value) || ...
            isempty(value) || any(~isfinite(value(:)))
        error('ALEV4:InvalidOpticalFrequency', 'Frequencies must be nonempty finite real numeric vectors.');
    end
    value = full(double(value(:).'));
end

function result = sincPi(value)
    result = ones(size(value));
    mask = value ~= 0;
    result(mask) = sin(pi*value(mask))./(pi*value(mask));
end
