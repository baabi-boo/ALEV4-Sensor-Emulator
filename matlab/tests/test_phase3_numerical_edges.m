function report = test_phase3_numerical_edges()
%TEST_PHASE3_NUMERICAL_EDGES Cross-layer floating-point and representation gates.
    previous = rng;
    cleanup = onCleanup(@()rng(previous)); %#ok<NASGU>
    names = {'translated_origin_footprint_distortion_rejected', ...
        'weighted_subnormal_sampling_rejected', ...
        'weighted_subnormal_optics_rejected', ...
        'exact_copy_preserves_subnormal_values', ...
        'finite_extreme_constant_convex_averages', ...
        'unrepresentable_physical_areas_rejected', ...
        'spatial_numeric_tokens_preserve_binary64', ...
        'late_spectral_failure_restores_rng', ...
        'weighted_output_threshold_and_positive_support', ...
        'representable_and_underflowed_overlap_weights', ...
        'nonuniform_axis_area_extrema_are_checked', ...
        'point_reconstruction_extreme_contrast_is_explicit', ...
        'point_reconstruction_fraction_underflow_is_explicit', ...
        'point_reconstruction_corner_product_underflow_is_explicit', ...
        'extreme_mtf_scales_preserve_analytical_phase', ...
        'continuous_aperture_phase_limits_are_explicit', ...
        'spatial_wrapper_range_failures_restore_rng'};
    reject(@()alev4.createSensorGeometry(struct('full_grid_size',[2 3], ...
        'pixel_pitch_m',.6,'origin_xy_m',[1e15 1e15])),'ALEV4:GeometryNumericRange');
    testTranslatedPrecisionBoundary();
    g = alev4.createSensorGeometry(struct('full_grid_size',[1 1],'pixel_pitch_m',1));
    fine = alev4.createSpatialGrid(struct('x_edges_m',[0 .5 1],'y_edges_m',[0 1]));
    optical_grid = alev4.createSpatialGrid(struct('x_edges_m',[0 1 2],'y_edges_m',[0 1]));
    psf = alev4.createOpticalPsf(struct('kernel',[.5 .5], ...
        'origin_rc',[1 1],'spacing_yx_m',[1 1]));
    for multiplier = [1 3 5 7 9]
        small = multiplier*eps(0);
        reject(@()alev4.resampleSensorIrradiance([small small],fine,g),'ALEV4:SpatialNumericRange');
        reject(@()alev4.applyOpticalPsf([small small],optical_grid,psf),'ALEV4:OpticalNumericRange');
    end
    grid = alev4.createSpatialGrid(struct('x_edges_m',[0 1],'y_edges_m',[0 1]));
    copied = alev4.resampleSensorIrradiance(3*eps(0),grid,g);
    assert(isequal(copied,3*eps(0)));
    identity = alev4.createOpticalPsf(struct('spacing_yx_m',[1 1]));
    assert(isequal(alev4.applyOpticalPsf(copied,grid,identity),copied));
    testAlignedSubnormalCrop();
    assert(isequal(alev4.resampleSensorIrradiance([realmax realmax],fine,g),realmax));
    assert(isequal(alev4.applyOpticalPsf([realmax realmax],optical_grid,psf),realmax));
    testExtremeContrast();
    reject(@()alev4.createSensorGeometry(struct('pixel_pitch_m',1e-200)),'ALEV4:InvalidGeometry');
    reject(@()alev4.createSpatialGrid(struct('x_edges_m',[0 1e-200], ...
        'y_edges_m',[0 1e-200])),'ALEV4:SpatialNumericRange');
    values = [0 -0 eps(0) realmin 7*6e-6 9*6e-6 pi realmax -1e-200 flintmax];
    for value = values
        text = ['{"number":' sprintf('%.17g',value) '}'];
        decoded = alev4.spatialDecodeJson(text);
        assert(strcmp(num2hex(decoded.number),num2hex(value)));
    end
    reject(@()alev4.spatialDecodeJson('{"number":1e-400}'),'ALEV4:InvalidSpatialMetadata');
    reject(@()alev4.spatialDecodeJson('{"number":1,"number":2}'),'ALEV4:InvalidDualGainMetadata');
    testLateFailure();
    testWeightedOutputRange();
    testOverlapWeightRange();
    testNonuniformAreaRange();
    testPointContrast();
    testPointFractions();
    testPointCornerUnderflow();
    testMtfPhaseScale();
    testAperturePhaseRange();
    testWrapperRangeFailures();
    tests = repmat(struct('name','','status','passed','passed',true),1,numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    report = struct('suite','phase3_numerical_edges','status','passed','passed',true, ...
        'test_count',numel(names),'tests',tests);
    fprintf('PASS: Phase 3 numerical edges, %d test groups.\n',numel(names));
end

function testTranslatedPrecisionBoundary()
    % At these origins, the coordinate ULP is respectively 2^-20 and
    % 2^-19 of unit pitch, on opposite sides of the declared 1e-6 bound.
    % The noninteger pitch exposes actual footprint rounding below it.
    pitch = 1+2^-21;
    g = alev4.createSensorGeometry(struct('full_grid_size',[3 5], ...
        'active_roi',[2 3 2 2],'pixel_pitch_m',pitch, ...
        'origin_xy_m',[2^32 -2^32]));
    target = alev4.sensorGrid(g);
    assert(isequal(target.x_edges_m-2^32, ...
        [2+2^-20 3+2^-19 4+2^-19]));
    assert(isequal(target.y_edges_m+2^32,[1 2 3]*pitch));
    source = spatialGrid(target.x_edges_m,target.y_edges_m);
    [value,report] = alev4.resampleSensorIrradiance(ones(2),source,g);
    assert(isequal(value,ones(2)) && report.identity);
    actual_error = max(abs(diff(target.x_edges_m)/pitch-1));
    assert(actual_error > 0 && actual_error < 1e-6);
    assert(report.represented_pitch_relative_error == actual_error);
    origins = [2^33 0;-2^33 0;0 2^33;0 -2^33];
    for k = 1:size(origins,1)
        reject(@()alev4.createSensorGeometry(struct('full_grid_size',[2 3], ...
            'pixel_pitch_m',1,'origin_xy_m',origins(k,:))), ...
            'ALEV4:GeometryNumericRange');
    end
end

function testAlignedSubnormalCrop()
    % A crop must use the exact copy path even when values at unrelated
    % source sites span the entire finite binary64 range.
    plane = [realmax 0 realmin eps(0); ...
        eps(0) 3*eps(0) 0 realmin; ...
        0 realmin-eps(0) 7*eps(0) realmax];
    input = cat(3,plane,flipud(fliplr(plane)));
    grid = spatialGrid(0:4,0:3);
    g = alev4.createSensorGeometry(struct('full_grid_size',[3 4], ...
        'active_roi',[2 2 2 2],'pixel_pitch_m',1));
    [actual,report] = alev4.resampleSensorIrradiance(input,grid,g);
    expected = input(2:3,2:3,:);
    assert(isequal(num2hex(actual(:)),num2hex(expected(:))));
    assert(report.aligned_copy && ~report.identity);
    identity = alev4.createOpticalPsf(struct('spacing_yx_m',[1 1]));
    actual = alev4.applyOpticalPsf(input,grid,identity);
    assert(isequal(num2hex(actual(:)),num2hex(input(:))));
end

function testExtremeContrast()
    g = unitGeometry();
    input = [0 realmax;realmax realmin];
    fine = spatialGrid([0 .5 1],[0 .5 1]);
    sampled = alev4.resampleSensorIrradiance(input,fine,g);
    % Two of four equal areas contain realmax; the remaining positive
    % contribution is far below the ULP of the representable half maximum.
    assert(isequal(sampled,realmax/2));
    psf = alev4.createOpticalPsf(struct('kernel',ones(2)/4, ...
        'origin_rc',[1 1],'spacing_yx_m',[1 1]));
    filtered = alev4.applyOpticalPsf(input,spatialGrid(0:2,0:2),psf);
    assert(isequal(filtered,realmax/2));
    % Non-dyadic unit sums can round over the largest finite value during
    % accumulation. An explicit range failure is preferable to Inf/NaN.
    psf = alev4.createOpticalPsf(struct('kernel',[.1 .2 .7], ...
        'origin_rc',[1 2],'spacing_yx_m',[1 1]));
    accurateOrRange(@()alev4.applyOpticalPsf(realmax*ones(1,3), ...
        spatialGrid(0:3,[0 1]),psf),realmax,'ALEV4:OpticalNumericRange');
    accurateOrRange(@()alev4.resampleSensorIrradiance(realmax*ones(1,3), ...
        spatialGrid([0 .1 .3 1],[0 1]),g),realmax,'ALEV4:SpatialNumericRange');
end

function testLateFailure()
    cfg = alev4.createBaselineSensor(struct('image_size',[1 1], ...
        'wavelength_nm',500,'bin_width_nm',20,'qe',[1 1 1], ...
        'pixel_pitch_m',1,'fill_factor',1));
    readouts = {cfg,alev4.createDualGainSensor(struct('sensor',cfg))};
    grid = spatialGrid([0 1],[0 1]);
    g = unitGeometry();
    rng(38003,'twister'); before = rng;
    for k = 1:numel(readouts)
        reject(@()alev4.simulateSpatialExposure(realmax,grid,g, ...
            readouts{k},realmax,1),'ALEV4:SignalOverflow');
        assert(isequal(rng,before));
        % Exact zero exposure remains valid even when a positive exposure
        % would overflow spectral integration of the same finite density.
        zero = alev4.simulateSpatialExposure(realmax,grid,g,readouts{k},0,1);
        assert(zero.readout.expected_electrons == 0);
        assert(zero.readout.expected_incident_photons == 0);
        assert(isequal(rng,before));
    end
end

function testWeightedOutputRange()
    g = unitGeometry();
    fine = spatialGrid([0 .5 1],[0 1]);
    optical_grid = spatialGrid(0:2,[0 1]);
    psf = alev4.createOpticalPsf(struct('kernel',[.5 .5], ...
        'origin_rc',[1 1],'spacing_yx_m',[1 1]));
    % Inputs are normal in both cases. Only the second average is below
    % the normal-output boundary, so input-only checks cannot pass this gate.
    assert(alev4.resampleSensorIrradiance([2*realmin 0],fine,g) == realmin);
    assert(alev4.applyOpticalPsf([2*realmin 0],optical_grid,psf) == realmin);
    reject(@()alev4.resampleSensorIrradiance([realmin 0],fine,g), ...
        'ALEV4:SpatialNumericRange');
    reject(@()alev4.applyOpticalPsf([realmin 0],optical_grid,psf), ...
        'ALEV4:OpticalNumericRange');
    % A real positive contribution rounds all the way to zero. Its support
    % must still be recognized, whereas an entirely dark footprint is exact.
    tiny_weight = 2^-53;
    reject(@()alev4.resampleSensorIrradiance([realmin 0], ...
        spatialGrid([0 tiny_weight 1],[0 1]),g),'ALEV4:SpatialNumericRange');
    small_psf = alev4.createOpticalPsf(struct('kernel',[1-tiny_weight tiny_weight], ...
        'origin_rc',[1 1],'spacing_yx_m',[1 1]));
    reject(@()alev4.applyOpticalPsf([realmin 0],optical_grid,small_psf), ...
        'ALEV4:OpticalNumericRange');
    pair = alev4.createSensorGeometry(struct('full_grid_size',[1 2],'pixel_pitch_m',1));
    actual = alev4.resampleSensorIrradiance([0 0 2*realmin 0], ...
        spatialGrid([0 .5 1 1.5 2],[0 1]),pair);
    assert(isequal(actual,[0 realmin]));
    actual = alev4.applyOpticalPsf([0 0 2*realmin 0],spatialGrid(0:4,[0 1]),psf);
    assert(isequal(actual,[0 realmin realmin]));
end

function testOverlapWeightRange()
    pitch = 2^500;
    g = alev4.createSensorGeometry(struct('full_grid_size',[1 1],'pixel_pitch_m',pitch));
    % Both source cell areas remain normal. The small overlap/target ratio
    % reaches eps(0), yet multiplication by realmax gives a normal density.
    % Transposition forces both choices of separable multiplication order.
    for exponent = [-500 -574]
        width = 2^exponent;
        expected = (realmax/pitch)*width;
        horizontal = spatialGrid([0 width pitch],[0 pitch]);
        vertical = spatialGrid([0 pitch],[0 width pitch]);
        assert(alev4.resampleSensorIrradiance([realmax 0],horizontal,g) == expected);
        assert(alev4.resampleSensorIrradiance([realmax;0],vertical,g) == expected);
    end
    % One more binary exponent makes a positive normalized weight round to
    % zero. Reject it even though the mathematical final density is normal.
    width = 2^-575;
    assert((realmax/pitch)*width > realmin && width/pitch == 0);
    reject(@()alev4.resampleSensorIrradiance([realmax 0], ...
        spatialGrid([0 width pitch],[0 pitch]),g),'ALEV4:SpatialNumericRange');
    reject(@()alev4.resampleSensorIrradiance([realmax;0], ...
        spatialGrid([0 pitch],[0 width pitch]),g),'ALEV4:SpatialNumericRange');
end

function testNonuniformAreaRange()
    % A rectangular grid contains every x/y width pairing. Total extent or
    % a nominal spacing cannot substitute for the smallest/largest cell area.
    reject(@()spatialGrid([0 2^-600 1],[0 2^-600 1]), ...
        'ALEV4:SpatialNumericRange');
    reject(@()spatialGrid([0 1 2^600],[0 1 2^600]), ...
        'ALEV4:SpatialNumericRange');
    x = [0 2^-1000 3*2^-1000];
    y = [0 2^1000 1.5*2^1000];
    valid = spatialGrid(x,y);
    assert(isequal(valid.x_edges_m,x) && isequal(valid.y_edges_m,y));
    assert(isequal(diff(y).'*diff(x),[1 2;.5 1]));
end

function testPointContrast()
    % The requested cell is a constant, normal-valued crop. A bright point
    % outside that crop must not silently erase or change its faint density.
    for multiplier = [1 3]
        faint = realmax*(multiplier*eps(0));
        points = [realmax faint faint;realmax faint faint];
        accurateOrRange(@()alev4.isetPointGrid(points,[0 1 2],[0 1], ...
            [1 2],[0 1]),faint,'ALEV4:ISETPointNumericRange');
        accurateOrRange(@()alev4.isetPointGrid(points.',[0 1],[0 1 2], ...
            [0 1],[1 2]),faint,'ALEV4:ISETPointNumericRange');
    end
    faint = realmax*realmin;
    points = [realmax faint faint;realmax faint faint];
    actual = alev4.isetPointGrid(points,[0 1 2],[0 1],[1 2],[0 1]);
    assert(actual == faint);
    % Extreme anisotropy alone is not loss of cell area or signal precision.
    actual = alev4.isetPointGrid([1 2;3 4],[0 eps(0)],[0 realmax], ...
        [0 eps(0)],[0 realmax]);
    assert(actual == 2.5);
end

function testPointFractions()
    pitch = 2^500;
    points = [0 realmax;0 realmax];
    for exponent = [-574 -575]
        width = 2^exponent;
        % Exact integral of a linear ramp over [0,width], evaluated in an
        % order that does not underflow the normalized interpolation weight.
        expected = (realmax/pitch)*(width/2);
        assert(expected > realmin);
        accurateOrRange(@()alev4.isetPointGrid(points,[0 pitch],[0 pitch], ...
            [0 width],[0 pitch]),expected,'ALEV4:ISETPointNumericRange');
        accurateOrRange(@()alev4.isetPointGrid(points.',[0 pitch],[0 pitch], ...
            [0 pitch],[0 width]),expected,'ALEV4:ISETPointNumericRange');
    end
end

function testPointCornerUnderflow()
    % On the first native patch the bilinear field is exactly 4*x*y.
    % Its average over [0,eps]^2 is eps^2. The distant bright point
    % changes normalization, not that physical crop. Both coordinates and
    % normalized positive input remain supported individually, while their
    % product would otherwise erase the only illuminated corner.
    points = zeros(3);
    points(2,2) = 4;
    points(3,3) = realmax;
    expected = eps^2;
    accurateOrRange(@()alev4.isetPointGrid(points,[0 1 2],[0 1 2], ...
        [0 eps],[0 eps]),expected,'ALEV4:ISETPointNumericRange');
end

function testMtfPhaseScale()
    % The same quarter/Nyquist phases are represented by enormous y
    % frequencies and subnormal x frequencies. The separable kernel gives
    % an exact, independent four-phase oracle without multiplying SI terms.
    spacing = [2^-1024 2^1022];
    psf = alev4.createOpticalPsf(struct('kernel',[.125 .375;.125 .375], ...
        'origin_rc',[2 1],'spacing_yx_m',spacing));
    phases = [-.5 0 .25 .5];
    fx = phases/spacing(2); fy = phases/spacing(1);
    report = alev4.opticalMtf(psf,fx,fy);
    expected = [0;1;.5+.5i;0]*[-.5 1 .25-.75i -.5];
    assert(all(isfinite(report.optical_otf(:))));
    assert(max(abs(report.optical_otf(:)-expected(:))) <= 16*eps(1));
    assert(max(abs(report.optical_mtf(:)-abs(expected(:)))) <= 16*eps(1));
    assert(isequal(report.nyquist_yx_cycles_per_m,[2^1023 2^-1023]));
    reject(@()alev4.opticalMtf(psf,2^-1023+eps(0),0),'ALEV4:OpticalFrequencyRange');
    reject(@()alev4.opticalMtf(psf,0,2^1023+eps(2^1023)),'ALEV4:OpticalFrequencyRange');
end

function testAperturePhaseRange()
    psf = alev4.createOpticalPsf(struct('spacing_yx_m',[1 1]));
    dc = alev4.opticalMtf(psf,0,0,realmax);
    assert(dc.pixel_aperture_otf == 1 && dc.optical_mtf == 1);
    % Frequency times pitch is finite; multiplying that phase by pi is not.
    assert(isfinite(.5*realmax) && ~isfinite(pi*(.5*realmax)));
    reject(@()alev4.opticalMtf(psf,.5,0,realmax),'ALEV4:OpticalNumericRange');
    reject(@()alev4.opticalMtf(psf,0,-.5,realmax),'ALEV4:OpticalNumericRange');
    spacing = 2^1022;
    wide = alev4.createOpticalPsf(struct('spacing_yx_m',[spacing spacing]));
    actual = alev4.opticalMtf(wide,[-2^-1023 0 2^-1023],0,spacing);
    assert(max(abs(actual.pixel_aperture_otf-[2/pi 1 2/pi])) <= 4*eps(1));
end

function testWrapperRangeFailures()
    cfg = alev4.createBaselineSensor(struct('image_size',[1 1], ...
        'wavelength_nm',500,'bin_width_nm',1,'qe',[1 1 1], ...
        'pixel_pitch_m',1,'fill_factor',1));
    readouts = {cfg,alev4.createDualGainSensor(struct('sensor',cfg))};
    g = unitGeometry();
    fine = spatialGrid([0 .5 1],[0 1]);
    optical_grid = spatialGrid(0:2,[0 1]);
    psf = alev4.createOpticalPsf(struct('kernel',[.5 .5], ...
        'origin_rc',[1 2],'spacing_yx_m',[1 1]));
    rng(38004,'twister'); before = rng;
    for k = 1:numel(readouts)
        reject(@()alev4.simulateSpatialExposure([realmin 0],fine,g,readouts{k},1,8, ...
            struct('input_stage','post_optics')),'ALEV4:SpatialNumericRange');
        assert(isequal(rng,before));
        reject(@()alev4.simulateSpatialExposure([realmin 0],optical_grid,g,readouts{k},1,8, ...
            struct('psf',psf)),'ALEV4:OpticalNumericRange');
        assert(isequal(rng,before));
    end
end

function grid = spatialGrid(x,y)
    grid = alev4.createSpatialGrid(struct('x_edges_m',x,'y_edges_m',y));
end

function g = unitGeometry()
    g = alev4.createSensorGeometry(struct('full_grid_size',[1 1],'pixel_pitch_m',1));
end

function accurateOrRange(action,expected,identifier)
    try
        actual = action();
    catch err
        assert(strcmp(err.identifier,identifier), ...
            ['Expected an accurate finite result or ' identifier ', observed ' err.identifier]);
        return;
    end
    assert(isequal(size(actual),size(expected)) && all(isfinite(actual(:))));
    assert(all(abs(actual(:)-expected(:)) <= 8*eps(abs(expected(:)))), ...
        'Finite output must retain the independently calculated density.');
end

function reject(action,identifier)
    failed = false;
    try, action(); catch err
        failed = true;
        assert(strcmp(err.identifier,identifier), ...
            ['Expected ' identifier ', observed ' err.identifier]);
    end
    assert(failed,['Expected rejection ' identifier]);
end
