function [result, cfg, report] = isetBaseline(seed, exposure_s)
%ISETBASELINE Run a headless ISETCam scene-to-sensor integration fixture.
%   [RESULT, CFG, REPORT] = alev4.isetBaseline(SEED, EXPOSURE_S) creates a
%   uniform spectral scene, computes diffraction-limited optical irradiance,
%   and compares ISETCam's noiseless Bayer response with our independent
%   photon-to-electron integration. Defaults: seed 73, exposure 0.001 s.
%
%   This fixture deliberately disables lens relative illumination and sensor
%   vignetting. It uses a small sensor entirely inside the uniform optical
%   field, avoiding a false comparison between different spatial grids.
%   The imported effective QE is ISETCam's generic CFA/IR/pixel response,
%   NOT a measured ALEV4 response. RESULT is labelled synthetic by the RAW
%   exporter. ISETCam is required; missing dependencies are errors, not skips.
%
%   Call setup_project first. GNU Octave additionally needs the image package.
%   MATLAB needs the Image Processing Toolbox used by ISETCam's fspecial.
    if nargin < 1, seed = 73; end
    if nargin < 2, exposure_s = 1e-3; end
    if ~isnumeric(seed) || ~isreal(seed) || ~isscalar(seed) || ...
            ~isfinite(seed) || seed < 0 || seed > 2^32-1 || seed ~= fix(seed)
        error('ALEV4:InvalidSeed', 'Seed must be an integer in [0, 2^32-1].');
    end
    if ~isnumeric(exposure_s) || ~isreal(exposure_s) || ~isscalar(exposure_s) || ...
            ~isfinite(exposure_s) || exposure_s <= 0
        error('ALEV4:InvalidExposure', ...
            'The ISET fixture needs positive exposure: ISET treats zero as auto-exposure.');
    end
    required = {'sceneCreate', 'sceneSet', 'oiCreate', 'oiCompute', 'oiGet', ...
        'sensorCreate', 'sensorSet', 'sensorCompute', 'sensorGet', 'pixelCreate'};
    for k = 1:numel(required)
        if exist(required{k}, 'file') ~= 2
            error('ALEV4:MissingISETCam', ...
                'ISETCam function %s is absent. Initialize pinned submodules and run setup_project.', required{k});
        end
    end
    if exist('OCTAVE_VERSION', 'builtin') ~= 0 && exist('fspecial', 'file') ~= 2
        try
            pkg('load', 'image');
        catch err
            error('ALEV4:MissingImagePackage', ...
                'ISETCam integration needs the Octave image package: %s', err.message);
        end
    end
    if exist('fspecial', 'file') ~= 2
        error('ALEV4:MissingImagePackage', ...
            'ISETCam integration requires fspecial from Image Processing Toolbox / Octave image.');
    end

    previous_rng = rng;
    rng_guard = onCleanup(@() rng(previous_rng)); %#ok<NASGU>
    rng(double(seed), 'twister');
    ieInitSession;
    ieSessionSet('waitbar', 0);

    scene = sceneCreate('uniformEqualPhoton', [32 32]);
    scene = sceneSet(scene, 'hfov', 1);
    wave = double(sceneGet(scene, 'wave'));
    oi = oiCreate;
    oi = oiSet(oi, 'optics offaxis method', 'skip');
    oi = oiCompute(oi, scene, 'pad value', 'mean');

    pixel = pixelCreate('ideal', wave, 5e-6);
    sensor = sensorCreate('bayer-rggb', pixel);
    sensor = sensorSet(sensor, 'size', [16 16]);
    sensor = sensorSet(sensor, 'exposure time', double(exposure_s));
    sensor = sensorSet(sensor, 'auto exposure', 0);
    sensor = sensorSet(sensor, 'noise flag', 0);
    sensor = sensorSet(sensor, 'quantization method', 'analog');
    sensor = sensorSet(sensor, 'analog gain', 1);
    sensor = sensorSet(sensor, 'analog offset', 0);
    sensor = sensorSet(sensor, 'vignetting', 0);
    sensor = sensorCompute(sensor, oi, 0);

    % Read actual returned geometry, not just requested dimensions.
    image_size = double(sensorGet(sensor, 'size'));
    wave = double(oiGet(oi, 'wave'));
    bin_width = double(oiGet(oi, 'binwidth'));
    if ~isscalar(bin_width) || bin_width <= 0 || ...
            any(abs(diff(wave) - bin_width) > 1e-8 * max(1, bin_width))
        error('ALEV4:ISETWavelengthGrid', 'The ISET integration fixture requires equal-width spectral bins.');
    end
    sensor_wave = double(sensorGet(sensor, 'wave'));
    if ~isequal(wave(:), sensor_wave(:))
        error('ALEV4:ISETWavelengthGrid', 'ISET sensor and optical image wavelength grids differ.');
    end
    filter_letters = lower(sensorGet(sensor, 'filter color letters'));
    native_qe = double(sensorGet(sensor, 'spectral qe'));
    order = zeros(1, 3);
    rgb = 'rgb';
    for channel = 1:3
        matches = find(filter_letters == rgb(channel));
        if numel(matches) ~= 1
            error('ALEV4:ISETCFA', 'Expected exactly one ISET filter for each RGB channel.');
        end
        order(channel) = matches;
    end
    native_pattern = sensorGet(sensor, 'pattern');
    if ~isequal(size(native_pattern), [2 2])
        error('ALEV4:ISETCFA', 'Expected a 2-by-2 Bayer tile.');
    end
    pattern_letters = filter_letters(native_pattern);
    pattern_name = upper(reshape(pattern_letters.', 1, []));
    if ~strcmp(pattern_name, 'RGGB')
        error('ALEV4:ISETCFA', 'The requested ISET Bayer fixture did not return RGGB.');
    end
    pixel = sensorGet(sensor, 'pixel');
    pixel_area = double(pixelGet(pixel, 'area'));
    fill_factor = double(pixelGet(pixel, 'fill factor'));
    conversion_gain = double(pixelGet(pixel, 'conversion gain'));
    if abs(pixelGet(pixel, 'width') - pixelGet(pixel, 'height')) > 1e-15
        error('ALEV4:ISETGeometry', 'The baseline requires square ISET pixels.');
    end
    cfg = alev4.createBaselineSensor(struct( ...
        'image_size', image_size, 'wavelength_nm', wave(:), ...
        'bin_width_nm', repmat(bin_width, numel(wave), 1), ...
        'qe', native_qe(:, order), 'pixel_pitch_m', sqrt(pixel_area), ...
        'fill_factor', fill_factor, 'full_well_e', 1e8, ...
        'read_noise_e', 0, 'gain_dn_per_e', 1, 'black_level_dn', 64, ...
        'adc_bits', 16, 'cfa_pattern', pattern_name, 'shot_noise', false));

    % Mean padding and disabled off-axis loss preserve the uniform field.
    % Check that fact before replacing the OI grid by the sensor grid.
    oi_photons = double(oiGet(oi, 'photons'));
    if ndims(oi_photons) > 3 || size(oi_photons, 3) ~= numel(wave) || ...
            any(~isfinite(oi_photons(:))) || any(oi_photons(:) < 0)
        error('ALEV4:ISETIrradiance', 'ISET returned invalid spectral photon irradiance.');
    end
    spectrum = reshape(mean(mean(oi_photons, 1), 2), [], 1);
    if all(spectrum == 0)
        error('ALEV4:ISETIrradiance', 'The illuminated ISET fixture returned zero irradiance.');
    end
    uniform_reference = repmat(reshape(spectrum, 1, 1, []), size(oi_photons, 1), size(oi_photons, 2));
    uniformity_error = max(abs(oi_photons(:) - uniform_reference(:))) / max(spectrum);
    if uniformity_error > 2e-5
        error('ALEV4:ISETNonuniformFixture', ...
            'Uniform optical field check failed (relative deviation %.3g).', uniformity_error);
    end
    sensor_irradiance = repmat(reshape(spectrum, 1, 1, []), image_size(1), image_size(2));
    result = alev4.simulateExposure(sensor_irradiance, cfg, double(exposure_s), double(seed));

    % sensorGet('electrons') rounds and clamps. Volts/conversion gain retains
    % the fractional analog expectation in this unity-gain, zero-bias run.
    iset_expected = double(sensorGet(sensor, 'volts')) / conversion_gain;
    if ~isequal(size(iset_expected), image_size) || ...
            any(~isfinite(iset_expected(:))) || any(iset_expected(:) < 0)
        error('ALEV4:ISETSignal', 'ISET returned invalid analog sensor expectations.');
    end
    difference = result.expected_electrons - iset_expected;
    max_absolute_error = max(abs(difference(:)));
    max_relative_error = max_absolute_error / max(1, max(abs(iset_expected(:))));
    tolerance = 5e-5;
    % ISET stores parts of its pipeline as single precision. This tolerance
    % allows those roundoffs but rejects omitted spectral widths/fill factors.
    if max_relative_error > tolerance
        error('ALEV4:ISETComparison', ...
            'Independent photon integration disagrees with ISET: %.6g exceeds %.6g.', max_relative_error, tolerance);
    end
    if any(result.full_well_saturated(:)) || any(result.adc_high_clipped(:))
        error('ALEV4:ISETClippedFixture', 'The noiseless integration fixture unexpectedly saturated.');
    end
    report = struct('status', 'passed', 'source', 'pinned ISETCam uniform spectral scene', ...
        'image_size', image_size, 'exposure_s', double(exposure_s), ...
        'wavelength_nm', wave(:), 'bin_width_nm', bin_width, ...
        'effective_rgb_qe', cfg.qe, 'pixel_area_m2', pixel_area, ...
        'fill_factor', fill_factor, 'cfa_pattern', pattern_name, ...
        'filter_names', {sensorGet(sensor, 'filter names')}, ...
        'oi_uniformity_relative_error', uniformity_error, ...
        'max_absolute_error_e', max_absolute_error, ...
        'max_relative_error', max_relative_error, 'relative_tolerance', tolerance, ...
        'iset_expected_electrons', iset_expected, ...
        'synthetic', true, 'calibrated_alev4', false);
end
