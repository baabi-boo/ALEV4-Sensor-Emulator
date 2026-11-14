function [spatial, cfg, report] = isetSpatialFixture(kind, seed, exposure_s)
%ISETSPATIALFIXTURE Restricted nonuniform scene/optics/Bayer comparison.
%   [SPATIAL,CFG,REPORT] = alev4.isetSpatialFixture(KIND,SEED,EXPOSURE_S)
%   supports KIND='uniform','ramp','checker','edge'; defaults are seed 83,
%   exposure 0.001 s. Call setup_project(true) first. GNU Octave additionally
%   needs the image package; MATLAB needs Image Processing Toolbox.
%
%   Genuine ISETCam oiCompute supplies post-optics POINT samples. An explicit
%   bilinear reconstruction is converted to cell averages on a partition of
%   optical knots and sensor edges. No second optical PSF is applied. Native
%   sensorCompute quadrature and separate source-grid refinement are compared
%   with an independently integrated bilinear field before noise/rounding.
%   This fixture intentionally supports only square, full-fill-factor pixels
%   whose pitch does not trigger ISETCam's additional Gaussian prefilter.
%   It is not a general optical-image importer or measured ARRI calibration.
%   Caller RNG, vcSESSION, and the full ISET preference group are restored.
%   The pinned upstream coordinate/interpolation/quadrature source map is
%   in docs/PHASE3_SOURCES.md (ISET-PINNED-SPATIAL), including
%   sensor/simulation/regridOI2ISA.m and spatialIntegration.m.
    if nargin < 1 || nargin > 3 || ~ischar(kind) || ~isrow(kind) || ...
            ~any(strcmp(kind,{'uniform','ramp','checker','edge'}))
        error('ALEV4:UnsupportedISETSpatialFixture', 'Choose uniform, ramp, checker, or edge.');
    end
    if nargin < 2, seed = 83; end
    if nargin < 3, exposure_s = 1e-3; end
    if ~isnumeric(seed) || ~isreal(seed) || ~isscalar(seed) || ...
            ~isfinite(seed) || seed < 0 || seed > 2^32-1 || seed ~= fix(seed)
        error('ALEV4:InvalidSeed', 'Seed must be an integer in [0,2^32-1].');
    end
    if ~isnumeric(exposure_s) || ~isreal(exposure_s) || ~isscalar(exposure_s) || ...
            ~isfinite(exposure_s) || exposure_s <= 0
        error('ALEV4:InvalidExposure', 'The ISET fixture requires positive finite exposure.');
    end
    seed = full(double(seed));
    exposure_s = full(double(exposure_s));
    previous_rng = rng;
    rng_guard = onCleanup(@() rng(previous_rng)); %#ok<NASGU>
    requireIset();
    previous_state = captureIsetState();
    state_guard = onCleanup(@() restoreIsetState(previous_state));
    rng(seed,'twister');
    global vcSESSION;
    vcSESSION = struct();
    ieInitSession;
    ieSessionSet('waitbar',0);

    scene = sceneCreate('uniformEqualPhoton',[32 32]);
    scene = sceneSet(scene,'hfov',3);
    [x,y] = meshgrid(1:32,1:32);
    switch kind
        case 'uniform'
            modulation = ones(32);
        case 'ramp'
            modulation = 0.2+0.8*(x+2*y)/96;
        case 'checker'
            modulation = 0.2+0.8*mod(floor((x-1)/4)+floor((y-1)/4),2);
        case 'edge'
            modulation = 0.2+0.8*(x>16);
    end
    scene = sceneSet(scene,'photons',bsxfun(@times,double(sceneGet(scene,'photons')),modulation));
    oi = oiCreate;
    oi = oiSet(oi,'optics offaxis method','skip');
    oi = oiCompute(oi,scene,'pad value','mean');
    wave = double(oiGet(oi,'wave'));
    spacing = double(oiGet(oi,'distance per sample'));
    support = oiGet(oi,'spatial support linear');
    photons = double(oiGet(oi,'photons'));
    bin_width = double(oiGet(oi,'binwidth'));
    if ~isscalar(bin_width) || ~isfinite(bin_width) || bin_width <= 0 || ...
            any(abs(diff(wave)-bin_width) > 1e-8*bin_width)
        error('ALEV4:ISETWavelengthGrid', 'The spatial fixture requires matching equal-width spectral bins.');
    end
    native_x = double(support.x(:).');
    native_y = double(support.y(:).');
    if numel(spacing) ~= 2 || any(~isfinite(spacing(:))) || any(spacing(:) <= 0) || ...
            numel(native_x) ~= size(photons,2) || numel(native_y) ~= size(photons,1) || ...
            size(photons,3) ~= numel(wave) || any(~isfinite(photons(:))) || any(photons(:) < 0)
        error('ALEV4:ISETSpatialGrid', 'ISET returned an unsupported optical point grid.');
    end
    spacing = spacing(:).';
    if any(abs(diff(native_x)/spacing(2)-1) > 1e-10) || ...
            any(abs(diff(native_y)/spacing(1)-1) > 1e-10)
        error('ALEV4:ISETSpatialGrid', 'The native ISET optical sample grid must be uniform.');
    end
    pixel = pixelCreate('ideal',wave,5e-6);
    sensor = sensorCreate('bayer-rggb',pixel);
    sensor = sensorSet(sensor,'size',[16 16]);
    sensor = sensorSet(sensor,'exposure time',exposure_s);
    sensor = sensorSet(sensor,'auto exposure',0);
    sensor = sensorSet(sensor,'noise flag',0);
    sensor = sensorSet(sensor,'quantization method','analog');
    sensor = sensorSet(sensor,'analog gain',1);
    sensor = sensorSet(sensor,'analog offset',0);
    sensor = sensorSet(sensor,'vignetting',0);
    image_size = double(sensorGet(sensor,'size'));
    pixel = sensorGet(sensor,'pixel');
    pitch = double(pixelGet(pixel,'width'));
    fill = double(pixelGet(pixel,'fill factor'));
    conversion_gain = double(pixelGet(pixel,'conversion gain'));
    if ~isequal(image_size,[16 16]) || pitch ~= 5e-6 || ...
            pixelGet(pixel,'height') ~= pitch || fill ~= 1 || ...
            any(spacing < pitch) || any(ceil(pitch./spacing) ~= 1)
        error('ALEV4:ISETSpatialGeometry', 'Fixture requires 16x16 full-fill square pixels with a 1x1 native prefilter.');
    end
    sensor_wave = double(sensorGet(sensor,'wave'));
    if ~isequal(sensor_wave(:),wave(:))
        error('ALEV4:ISETWavelengthGrid', 'Optical and sensor wavelengths differ.');
    end
    letters = lower(sensorGet(sensor,'filter color letters'));
    native_qe = double(sensorGet(sensor,'spectral qe'));
    native_pattern = sensorGet(sensor,'pattern');
    if ~isequal(size(native_pattern),[2 2])
        error('ALEV4:ISETCFA', 'Expected a two-by-two native Bayer tile.');
    end
    pattern = upper(reshape(letters(native_pattern).',1,[]));
    if ~strcmp(pattern,'RGGB')
        error('ALEV4:ISETCFA', 'The spatial fixture requires the returned RGGB origin.');
    end
    rgb = 'rgb';
    order = zeros(1,3);
    for channel = 1:3
        locations = find(letters == rgb(channel));
        if numel(locations) ~= 1
            error('ALEV4:ISETCFA', 'Expected one native spectral filter per RGB channel.');
        end
        order(channel) = locations;
    end
    geometry = alev4.createSensorGeometry(struct('full_grid_size',image_size, ...
        'pixel_pitch_m',pitch,'origin_xy_m',-fliplr(image_size)*pitch/2, ...
        'full_grid_cfa_pattern',pattern,'parameter_sources',{{'ISET-PINNED-SPATIAL'}}));
    target = alev4.sensorGrid(geometry);
    cfg = alev4.createBaselineSensor(struct('image_size',image_size, ...
        'wavelength_nm',wave(:),'bin_width_nm',repmat(bin_width,numel(wave),1), ...
        'qe',native_qe(:,order),'pixel_pitch_m',pitch,'fill_factor',fill, ...
        'full_well_e',1e8,'read_noise_e',0,'gain_dn_per_e',1, ...
        'black_level_dn',64,'adc_bits',16,'cfa_pattern',pattern,'shot_noise',false));
    cfg = alev4.bindSensorGeometry(cfg,geometry,'validate');
    if target.x_edges_m(1) < native_x(1) || target.x_edges_m(end) > native_x(end) || ...
            target.y_edges_m(1) < native_y(1) || target.y_edges_m(end) > native_y(end)
        error('ALEV4:ISETPointCoverage', 'Every complete photosite footprint must lie inside native point support.');
    end
    xknots = clippedKnots(native_x,target.x_edges_m([1 end]));
    yknots = clippedKnots(native_y,target.y_edges_m([1 end]));
    exact_x = unique([xknots target.x_edges_m]);
    exact_y = unique([yknots target.y_edges_m]);
    [cell_photons,cell_grid,conversion] = ...
        alev4.isetPointGrid(photons,native_x,native_y,exact_x,exact_y);
    source_metadata = struct('adapter','restricted_iset_spatial_fixture', ...
        'fixture_kind',kind,'input_native_semantics','point_samples', ...
        'reconstruction','bilinear_between_native_optical_points', ...
        'cell_conversion','four_corner_mean_with_optical_knots_and_sensor_edges', ...
        'optics_already_applied',true,'extra_psf_applied',false, ...
        'scene_hfov_degrees',3,'oi_padding','mean','offaxis_method','skip', ...
        'native_point_size',[size(photons,1) size(photons,2) size(photons,3)], ...
        'native_point_spacing_yx_m',spacing, ...
        'native_point_units','photons m^-2 s^-1 nm^-1', ...
        'native_point_bounds_xy_m',[native_x(1) native_y(1); native_x(end) native_y(end)], ...
        'reference_source','ISET-PINNED-SPATIAL');
    spatial = alev4.simulateSpatialExposure(cell_photons,cell_grid,geometry,cfg, ...
        exposure_s,seed,struct('input_stage','post_optics','spatial_provenance',source_metadata));
    reference = scalarBilinearReference(photons,native_x,native_y,target,cfg,exposure_s);
    reference_scale = max(reference(:));
    if ~isfinite(reference_scale) || reference_scale <= 0
        error('ALEV4:ISETSignal', 'The illuminated spatial fixture requires finite positive reference electrons.');
    end
    project_error = max(abs(spatial.readout.expected_electrons(:)-reference(:)))/reference_scale;
    project_tolerance = 5e-12;
    if project_error > project_tolerance
        error('ALEV4:ISETSpatialComparison', 'Exact partition disagrees with scalar bilinear integration: %.6g.',project_error);
    end
    if any(spatial.readout.full_well_saturated(:)) || any(spatial.readout.adc_high_clipped(:))
        error('ALEV4:ISETClippedFixture', 'The spatial fixture unexpectedly saturated.');
    end

    refinement_factors = [1 2 4 8 16];
    refinement_errors = zeros(size(refinement_factors));
    for k = 1:numel(refinement_factors)
        xe = subdivide(xknots,refinement_factors(k));
        ye = subdivide(yknots,refinement_factors(k));
        [averages,grid] = alev4.isetPointGrid(photons,native_x,native_y,xe,ye);
        sampled = alev4.resampleSensorIrradiance(averages,grid,geometry);
        expected = alev4.integrateExposure(sampled,cfg,exposure_s);
        refinement_errors(k) = max(abs(expected(:)-reference(:)))/reference_scale;
    end
    native_samples_per_axis = [1 3 9 27];
    native_errors = zeros(size(native_samples_per_axis));
    native_expected = zeros(image_size);
    for k = 1:numel(native_samples_per_axis)
        native_sensor = sensorSet(sensor,'n samples per pixel',native_samples_per_axis(k));
        native_sensor = sensorCompute(native_sensor,oi,0);
        native_expected = double(sensorGet(native_sensor,'volts'))/conversion_gain;
        if ~isequal(size(native_expected),image_size) || ...
                any(~isfinite(native_expected(:))) || any(native_expected(:) < 0)
            error('ALEV4:ISETSignal', 'Native fractional-electron output is invalid.');
        end
        native_errors(k) = max(abs(native_expected(:)-reference(:)))/reference_scale;
    end
    native_tolerance = 5e-5;
    if native_errors(end) > native_tolerance
        error('ALEV4:ISETSpatialComparison', 'Native refined quadrature disagreement %.6g exceeds %.6g.',native_errors(end),native_tolerance);
    end
    if any(strcmp(kind,{'checker','edge'})) && ...
            (native_errors(end) >= native_errors(1)/10 || ...
             refinement_errors(end) >= refinement_errors(1)/10)
        error('ALEV4:ISETSpatialConvergence', 'Nonuniform source/native refinement failed to improve over coarse sampling.');
    end
    % Compare each band against its own spatial mean. CFA-channel differences
    % alone are not evidence that the actual optical field was nonuniform.
    spatial_mean = mean(mean(photons,1),2);
    deviations = abs(bsxfun(@minus,photons,spatial_mean));
    variation = max(deviations(:))/max(photons(:));
    if strcmp(kind,'uniform')
        if variation > 2e-5
            error('ALEV4:ISETNonuniformFixture', 'Uniform optical fixture failed its flat-field check.');
        end
    elseif variation < 0.05
        error('ALEV4:ISETFlatSpatialFixture', 'A required nonuniform fixture returned a nearly flat optical field.');
    end
    report = struct('status','passed','passed',true, ...
        'fixture_kind',kind,'source','pinned ISETCam genuine scene-oiCompute-sensorCompute', ...
        'image_size',image_size,'exposure_s',exposure_s,'seed',seed, ...
        'input_stage','post_optics','extra_psf_applied',false, ...
        'source_semantics','point_samples','reconstruction','piecewise_bilinear', ...
        'conversion',conversion,'native_point_x_m',native_x,'native_point_y_m',native_y, ...
        'native_spacing_yx_m',spacing,'native_prefilter_size_yx',[1 1], ...
        'oi_spatial_variation',variation,'wavelength_nm',wave(:), ...
        'bin_width_nm',bin_width,'effective_rgb_qe',cfg.qe, ...
        'pixel_pitch_m',pitch,'fill_factor',fill,'cfa_pattern',pattern, ...
        'reference_method','independent_scalar_piecewise_bilinear_footprint_integral', ...
        'reference_expected_electrons',reference,'native_expected_electrons',native_expected, ...
        'max_project_relative_error',project_error,'project_relative_tolerance',project_tolerance, ...
        'source_refinement_factors',refinement_factors,'source_refinement_relative_errors',refinement_errors, ...
        'native_samples_per_axis',native_samples_per_axis,'native_relative_errors',native_errors, ...
        'native_relative_tolerance',native_tolerance, ...
        'native_roundoff_note','ISET spectral and subpixel accumulation uses single precision; no bit-exact claim', ...
        'provenance',alev4.sourceProvenance(),'synthetic',true,'calibrated_alev4',false);
    clear state_guard;
end

function requireIset()
    required = {'ieInitSession','ieSessionSet','sceneCreate','sceneGet','sceneSet', ...
        'oiCreate','oiSet','oiCompute','oiGet','pixelCreate','pixelGet', ...
        'sensorCreate','sensorSet','sensorGet','sensorCompute'};
    for k = 1:numel(required)
        if exist(required{k},'file') ~= 2
            error('ALEV4:MissingISETCam', 'Required ISET function %s is unavailable; initialize dependencies and run setup_project.',required{k});
        end
    end
    if exist('OCTAVE_VERSION','builtin') && exist('fspecial','file') ~= 2
        try
            pkg('load','image');
        catch err
            error('ALEV4:MissingImagePackage', 'ISET integration needs Octave image: %s',err.message);
        end
    end
    if exist('fspecial','file') ~= 2
        error('ALEV4:MissingImagePackage', 'ISET integration needs the image processing fspecial function.');
    end
end

function knots = clippedKnots(points,bounds)
    knots = [bounds(1) points(points > bounds(1) & points < bounds(2)) bounds(2)];
end

function result = subdivide(knots,factor)
    result = zeros(1,(numel(knots)-1)*factor+1);
    for k = 1:numel(knots)-1
        indices = (k-1)*factor+(1:factor);
        result(indices) = knots(k)+(0:factor-1)/factor*(knots(k+1)-knots(k));
    end
    result(end) = knots(end);
end

function expected = scalarBilinearReference(photons,x,y,target,cfg,exposure)
    % Independent order: integrate QE spectrally on native POINTS first, then
    % integrate each channel's bilinear function through scalar rectangles.
    % This never calls interp2, isetPointGrid, cfaMap, or the overlap sampler.
    density = zeros(size(photons,1),size(photons,2),3);
    for channel = 1:3
        for band = 1:numel(cfg.wavelength_nm)
            density(:,:,channel) = density(:,:,channel)+ ...
                photons(:,:,band)*cfg.qe(band,channel)*cfg.bin_width_nm(band);
        end
    end
    letters = reshape(cfg.cfa_pattern,2,2).';
    expected = zeros(target.image_size);
    for r = 1:target.image_size(1)
        yy = clippedKnots(y,target.y_edges_m(r:r+1));
        for c = 1:target.image_size(2)
            xx = clippedKnots(x,target.x_edges_m(c:c+1));
            channel = find('RGB' == letters(mod(r-1,2)+1,mod(c-1,2)+1));
            plane = density(:,:,channel);
            integral = 0;
            for a = 1:numel(yy)-1
                for b = 1:numel(xx)-1
                    corner_sum = scalarValue(plane,x,y,xx(b),yy(a))+ ...
                        scalarValue(plane,x,y,xx(b+1),yy(a))+ ...
                        scalarValue(plane,x,y,xx(b),yy(a+1))+ ...
                        scalarValue(plane,x,y,xx(b+1),yy(a+1));
                    integral = integral+corner_sum/4*(xx(b+1)-xx(b))*(yy(a+1)-yy(a));
                end
            end
            expected(r,c) = integral*cfg.fill_factor*exposure;
        end
    end
end

function value = scalarValue(data,x,y,xx,yy)
    c = find(x <= xx,1,'last');
    r = find(y <= yy,1,'last');
    c = min(c,numel(x)-1);
    r = min(r,numel(y)-1);
    u = (xx-x(c))/(x(c+1)-x(c));
    v = (yy-y(r))/(y(r+1)-y(r));
    value = (1-u)*(1-v)*data(r,c)+u*(1-v)*data(r,c+1)+ ...
        (1-u)*v*data(r+1,c)+u*v*data(r+1,c+1);
end

function state = captureIsetState()
    names = who('global');
    state.had_session = any(strcmp(names,'vcSESSION'));
    if state.had_session
        global vcSESSION;
        state.session = vcSESSION;
    else
        state.session = [];
    end
    state.had_preferences = ispref('ISET');
    if state.had_preferences, state.preferences = getpref('ISET');
    else, state.preferences = struct(); end
end

function restoreIsetState(state)
    if state.had_session
        global vcSESSION;
        vcSESSION = state.session;
    else
        clear global vcSESSION;
    end
    if ispref('ISET'), rmpref('ISET'); end
    if state.had_preferences
        names = fieldnames(state.preferences);
        for k = 1:numel(names), setpref('ISET',names{k},state.preferences.(names{k})); end
    end
end
