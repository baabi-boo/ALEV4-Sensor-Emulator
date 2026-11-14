function report = test_phase3_iset()
%TEST_PHASE3_ISET Non-skippable spatial ISET and point-reconstruction gates.
%   Requires setup_project(true). These small, controlled comparisons test
%   declared geometry and sampling; they do not establish ARRI calibration.
    previous_rng = rng;
    previous_state = captureState();
    guard = onCleanup(@() restoreCaller(previous_state,previous_rng)); %#ok<NASGU>
    names = {'bilinear_polynomial_multiband_cell_average_oracle', ...
        'cropped_bilinear_integral_and_knot_partition', ...
        'point_grid_malformed_coverage_and_knot_rejection', ...
        'point_conversion_numeric_scale_and_rng_isolation', ...
        'genuine_uniform_scene_optics_and_native_sensor', ...
        'genuine_ramp_scene_optics_and_native_sensor', ...
        'genuine_checker_scene_optics_and_native_sensor', ...
        'genuine_edge_scene_optics_and_native_sensor', ...
        'nonuniform_coarse_controls_and_two_refinement_sequences', ...
        'physical_binding_spectral_units_and_no_second_optics', ...
        'existing_session_preferences_rng_success_and_failure', ...
        'absent_session_preferences_restored_on_success_and_failure', ...
        'unsupported_arguments_and_missing_dependency_fail_explicitly', ...
        'exposure_linearity_and_seeded_repeatability'};

    point_error = testPointAverages();
    testPointCrop();
    testPointRejection();
    testPointScaleAndRng();
    assert(isequal(rng,previous_rng));

    global vcSESSION;
    vcSESSION = struct('NAME','phase3-caller-sentinel', ...
        'SELECTED',struct('SCENE',4),'SCENE',{{struct('owned',[3 5 8])}}, ...
        'opaque',struct('matrix',[2 -7; 9 1]));
    setpref('ISET','waitbar',1);
    setpref('ISET','phase3StateSentinel',struct('value',[1 4 9]));
    sentinel = captureState();
    unrelated = unrelatedPreferences();
    kinds = {'uniform','ramp','checker','edge'};
    fixtures = struct();
    first = [];
    first_cfg = [];
    for k = 1:numel(kinds)
        [spatial,cfg,native] = alev4.isetSpatialFixture(kinds{k},83,1e-3);
        fixtures.(kinds{k}) = verifyFixture(spatial,cfg,native,kinds{k});
        assert(isequal(rng,previous_rng),'Successful ISET fixture changed caller RNG.');
        requireState(sentinel);
        assert(isequal(unrelated,unrelatedPreferences()));
        if k == 1, first = spatial; first_cfg = cfg; end
    end
    for kind = {'checker','edge'}
        f = fixtures.(kind{1});
        assert(f.native_relative_errors(1) > 1e-2, ...
            'Coarse native control no longer distinguishes point from area sampling.');
        assert(f.source_refinement_relative_errors(1) > 1e-2);
        assert(f.native_relative_errors(end) < f.native_relative_errors(1)/10);
        assert(f.source_refinement_relative_errors(end) < f.source_refinement_relative_errors(1)/10);
    end

    expectError(@() alev4.isetSpatialFixture('checker',83,1e6),'ALEV4:ISETClippedFixture');
    requireState(sentinel);
    assert(isequal(rng,previous_rng));
    testArgumentsAndMissingDependency();
    requireState(sentinel);
    assert(isequal(rng,previous_rng));

    [repeat,repeat_cfg] = alev4.isetSpatialFixture('uniform',83,1e-3);
    assert(isequal(repeat,first) && isequal(repeat_cfg,first_cfg), ...
        'Identical same-runtime fixture calls must be exactly repeatable.');
    [twice,twice_cfg,twice_report] = alev4.isetSpatialFixture('uniform',83,2e-3);
    assert(isequal(twice_cfg,first_cfg));
    scale = max(first.readout.expected_electrons(:));
    linearity = max(abs(twice.readout.expected_electrons(:)- ...
        2*first.readout.expected_electrons(:)))/(2*scale);
    assert(linearity <= 2e-14);
    native_linearity = max(abs(twice_report.native_expected_electrons(:)- ...
        2*fixtures.uniform.native_expected_electrons(:)))/(2*scale);
    assert(native_linearity <= 5e-5);
    requireState(sentinel);
    assert(isequal(rng,previous_rng));

    clear global vcSESSION;
    if ispref('ISET'), rmpref('ISET'); end
    absent = captureState();
    alev4.isetSpatialFixture('uniform',83,1e-3);
    requireState(absent);
    expectError(@() alev4.isetSpatialFixture('uniform',83,1e6),'ALEV4:ISETClippedFixture');
    requireState(absent);
    assert(isequal(rng,previous_rng));
    assert(isequal(unrelated,unrelatedPreferences()));

    tests = repmat(struct('name','','status','passed','passed',true),1,numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    metrics = struct('point_polynomial_maximum_absolute_error',point_error, ...
        'exposure_linearity_relative_error',linearity, ...
        'native_exposure_linearity_relative_error',native_linearity, ...
        'fixtures',fixtures,'native_matlab_executed',exist('OCTAVE_VERSION','builtin') == 0, ...
        'synthetic',true,'calibrated_alev4',false);
    report = struct('suite','phase3_iset','status','passed','passed',true, ...
        'test_count',numel(names),'tests',tests,'metrics',metrics);
    fprintf('PASS: Phase 3 restricted ISET spatial comparison, %d test groups.\n',numel(names));
end

function compact = verifyFixture(spatial,cfg,report,kind)
    assert(strcmp(report.status,'passed') && report.passed);
    assert(strcmp(report.fixture_kind,kind) && report.synthetic && ~report.calibrated_alev4);
    assert(strcmp(report.source,'pinned ISETCam genuine scene-oiCompute-sensorCompute'));
    assert(strcmp(report.reference_method,'independent_scalar_piecewise_bilinear_footprint_integral'));
    reference = report.reference_expected_electrons;
    native = report.native_expected_electrons;
    assert(isequal(size(reference),[16 16]) && isequal(size(native),[16 16]));
    assert(all(isfinite(reference(:))) && all(reference(:) > 0));
    assert(all(isfinite(native(:))) && all(native(:) >= 0));
    scale = max(reference(:));
    observed_project = max(abs(spatial.readout.expected_electrons(:)-reference(:)))/scale;
    observed_native = max(abs(native(:)-reference(:)))/scale;
    assert(abs(observed_project-report.max_project_relative_error) <= 8*eps(observed_project));
    assert(abs(observed_native-report.native_relative_errors(end)) <= 8*eps(observed_native));
    assert(report.project_relative_tolerance == 5e-12 && observed_project <= 5e-12);
    assert(report.native_relative_tolerance == 5e-5 && observed_native <= 5e-5);
    assert(isequal(report.native_samples_per_axis,[1 3 9 27]));
    assert(isequal(report.source_refinement_factors,[1 2 4 8 16]));
    assert(numel(report.native_relative_errors) == 4 && numel(report.source_refinement_relative_errors) == 5);
    assert(all(isfinite(report.native_relative_errors)) && all(report.native_relative_errors >= 0));
    assert(all(isfinite(report.source_refinement_relative_errors)) && ...
        all(report.source_refinement_relative_errors >= 0));
    if strcmp(kind,'uniform')
        assert(report.oi_spatial_variation < 2e-5);
    else
        assert(report.oi_spatial_variation > 0.05, ...
            'A supposedly nonuniform optical field was silently replaced by a flat field.');
    end
    assert(strcmp(spatial.input_stage,'post_optics') && isempty(spatial.psf));
    assert(isequal(spatial.operation_order, ...
        {'area_overlap_average','spectral_integration','single_gain_readout'}));
    assert(isequal(spatial.input_irradiance,spatial.optical_irradiance));
    assert(isequal(spatial.input_grid,spatial.optical_grid));
    assert(strcmp(report.source_semantics,'point_samples'));
    assert(strcmp(report.reconstruction,'piecewise_bilinear'));
    assert(strcmp(report.conversion.method,'bilinear_point_reconstruction_exact_cell_average'));
    assert(report.conversion.all_native_knots_retained);
    assert(strcmp(spatial.input_grid.sample_semantics,'cell_average'));
    assert(strcmp(spatial.spatial_provenance.fixture_kind,kind));
    assert(spatial.spatial_provenance.optics_already_applied && ...
        ~spatial.spatial_provenance.extra_psf_applied && ~report.extra_psf_applied);
    assert(spatial.spatial_provenance.scene_hfov_degrees == 3);
    assert(strcmp(spatial.spatial_provenance.oi_padding,'mean'));
    assert(strcmp(spatial.spatial_provenance.offaxis_method,'skip'));
    assert(strcmp(spatial.spatial_provenance.reference_source,'ISET-PINNED-SPATIAL'));
    assert(isequal(report.native_prefilter_size_yx,[1 1]));
    assert(all(report.native_spacing_yx_m >= cfg.pixel_pitch_m));
    assert(isequal(cfg.image_size,[16 16]) && cfg.pixel_pitch_m == 5e-6 && cfg.fill_factor == 1);
    assert(strcmp(cfg.cfa_pattern,'RGGB') && strcmp(report.cfa_pattern,'RGGB'));
    assert(isequal(spatial.geometry.active_roi,[1 1 16 16]));
    assert(isequal(spatial.geometry.origin_xy_m,[-40e-6 -40e-6]));
    assert(isequal(spatial.geometry.parameter_sources,{'ISET-PINNED-SPATIAL'}));
    assert(isequal(cfg.wavelength_nm,report.wavelength_nm));
    assert(isequal(cfg.qe,report.effective_rgb_qe));
    assert(all(cfg.bin_width_nm == report.bin_width_nm));
    assert(size(spatial.sampled_irradiance,3) == numel(cfg.wavelength_nm));
    assert(~cfg.shot_noise && cfg.read_noise_e == 0 && cfg.gain_dn_per_e == 1);
    assert(~any(spatial.readout.full_well_saturated(:)) && ...
        ~any(spatial.readout.adc_low_clipped(:)) && ~any(spatial.readout.adc_high_clipped(:)));
    % Independent scalar spectral integration on retained sampled density.
    expected = zeros(16);
    colors = [1 2;2 3];
    for r = 1:16
        for c = 1:16
            channel = colors(mod(r-1,2)+1,mod(c-1,2)+1);
            total = 0;
            for band = 1:numel(cfg.wavelength_nm)
                total = total+spatial.sampled_irradiance(r,c,band)* ...
                    cfg.qe(band,channel)*cfg.bin_width_nm(band);
            end
            expected(r,c) = total*cfg.pixel_pitch_m^2*cfg.fill_factor*report.exposure_s;
        end
    end
    assert(max(abs(expected(:)-spatial.readout.expected_electrons(:)))/scale <= 5e-14);
    assert(isequal(spatial.readout.raw_dn,uint16(round(expected+cfg.black_level_dn))));
    assert(strcmp(report.provenance.isetcam_head,'3e0253421752eb72f2d1353327dffd0d433abdaf'));
    assert(strcmp(report.provenance.isethdrsensor_head,'ee2dacceb456516de3ecefadd72955154cf3cabe'));
    compact = struct('fixture_kind',kind,'image_size',cfg.image_size, ...
        'input_stage',spatial.input_stage,'extra_psf_applied',false, ...
        'project_relative_error',observed_project,'native_relative_error',observed_native, ...
        'source_refinement_factors',report.source_refinement_factors, ...
        'source_refinement_relative_errors',report.source_refinement_relative_errors, ...
        'native_samples_per_axis',report.native_samples_per_axis, ...
        'native_relative_errors',report.native_relative_errors, ...
        'native_spacing_yx_m',report.native_spacing_yx_m, ...
        'oi_spatial_variation',report.oi_spatial_variation, ...
        'reference_expected_electrons',reference,'native_expected_electrons',native, ...
        'provenance',report.provenance);
end

function largest_error = testPointAverages()
    x = [0 1 2]; y = [0 1.5 3];
    xe = [0 .25 1 1.4 2]; ye = [0 .3 1.5 2 3];
    coefficients = [2 3 4 5;7 2 1 .25];
    points = polynomialPoints(x,y,coefficients);
    [averages,grid,report] = alev4.isetPointGrid(points,x,y,xe,ye);
    expected = polynomialPoints((xe(1:end-1)+xe(2:end))/2, ...
        (ye(1:end-1)+ye(2:end))/2,coefficients);
    largest_error = max(abs(averages(:)-expected(:)));
    assert(largest_error <= 2e-13);
    assert(isequal(grid.x_edges_m,xe) && isequal(grid.y_edges_m,ye));
    assert(strcmp(report.source_semantics,'point_samples') && strcmp(report.output_semantics,'cell_average'));
    assert(isequal(report.cell_shape,[4 4 2]) && report.all_native_knots_retained);
    areas = diff(ye).'*diff(xe);
    for k = 1:2
        observed = sum(sum(averages(:,:,k).*areas));
        a = coefficients(k,1); b = coefficients(k,2);
        c = coefficients(k,3); d = coefficients(k,4);
        exact = a*2*3+b*(2^2/2)*3+c*(3^2/2)*2+d*(2^2/2)*(3^2/2);
        assert(abs(observed-exact) <= 3e-13);
    end
end

function testPointCrop()
    x = [0 1 2]; y = [0 1.5 3];
    xe = [.25 1 1.75]; ye = [.5 1.5 2.2];
    coefficients = [2 3 4 5;7 2 1 .25];
    points = polynomialPoints(x,y,coefficients);
    values = alev4.isetPointGrid(points,x,y,xe,ye);
    expected = polynomialPoints((xe(1:end-1)+xe(2:end))/2, ...
        (ye(1:end-1)+ye(2:end))/2,coefficients);
    assert(max(abs(values(:)-expected(:))) <= 2e-13);
    areas = diff(ye).'*diff(xe);
    for k = 1:2
        dx = xe(end)-xe(1); dy = ye(end)-ye(1);
        ix = (xe(end)^2-xe(1)^2)/2; iy = (ye(end)^2-ye(1)^2)/2;
        c = coefficients(k,:);
        exact = c(1)*dx*dy+c(2)*ix*dy+c(3)*iy*dx+c(4)*ix*iy;
        assert(abs(sum(sum(values(:,:,k).*areas))-exact) <= 3e-13);
    end
end

function values = polynomialPoints(x,y,coefficients)
    values = zeros(numel(y),numel(x),size(coefficients,1));
    for k = 1:size(coefficients,1)
        a = coefficients(k,:);
        for r = 1:numel(y)
            for c = 1:numel(x)
                values(r,c,k) = a(1)+a(2)*x(c)+a(3)*y(r)+a(4)*x(c)*y(r);
            end
        end
    end
end

function testPointRejection()
    p = ones(3); x = [0 1 2]; y = [0 1 2];
    expectError(@() alev4.isetPointGrid(p,x,y,[-.1 0 1 2],y),'ALEV4:ISETPointCoverage');
    expectError(@() alev4.isetPointGrid(p,x,y,x,[0 1 2.1]),'ALEV4:ISETPointCoverage');
    expectError(@() alev4.isetPointGrid(p,x,y,[0 2],y),'ALEV4:ISETPointKnots');
    expectError(@() alev4.isetPointGrid(p,x,y,x,[0 2]),'ALEV4:ISETPointKnots');
    expectError(@() alev4.isetPointGrid(p,[0 0 2],y,x,y),'ALEV4:ISETPointSamples');
    expectError(@() alev4.isetPointGrid(p,[0 NaN 2],y,x,y),'ALEV4:ISETPointSamples');
    expectError(@() alev4.isetPointGrid(p,[0 2 1],y,x,y),'ALEV4:ISETPointSamples');
    expectError(@() alev4.isetPointGrid(p,x,[],x,y),'ALEV4:ISETPointSamples');
    expectError(@() alev4.isetPointGrid(-p,x,y,x,y),'ALEV4:ISETPointSamples');
    expectError(@() alev4.isetPointGrid(p+1i,x,y,x,y),'ALEV4:ISETPointSamples');
    expectError(@() alev4.isetPointGrid(true(3),x,y,x,y),'ALEV4:ISETPointSamples');
    bad = p; bad(1) = Inf;
    expectError(@() alev4.isetPointGrid(bad,x,y,x,y),'ALEV4:ISETPointSamples');
    expectError(@() alev4.isetPointGrid(ones(2),x,y,x,y),'ALEV4:ISETPointSamples');
    expectError(@() alev4.isetPointGrid(p,x,y,[0 1 1 2],y),'ALEV4:InvalidSpatialGrid');
    expectError(@() alev4.isetPointGrid(p,x,y,x),'ALEV4:ISETPointGridArguments');
end

function testPointScaleAndRng()
    state = rng;
    x = [0 1]; y = [0 1]; edges = [0 .5 1];
    for scale = [0 realmin realmax 3*eps(0)]
        values = alev4.isetPointGrid(scale*ones(2),x,y,edges,edges);
        assert(all(values(:) == scale),'Constant field conversion changed a representable extreme scale.');
    end
    values = alev4.isetPointGrid(sparse([1 2;3 4]),x,y,edges,edges);
    assert(isa(values,'double') && ~issparse(values));
    assert(max(abs(values(:)-[1.75;2.75;2.25;3.25])) <= 8*eps(4));
    expectError(@() alev4.isetPointGrid([realmax eps(0);realmax realmax],x,y,edges,edges), ...
        'ALEV4:ISETPointNumericRange');
    assert(isequal(state,rng));
end

function testArgumentsAndMissingDependency()
    expectError(@() alev4.isetSpatialFixture('arbitrary'),'ALEV4:UnsupportedISETSpatialFixture');
    expectError(@() alev4.isetSpatialFixture('UNIFORM'),'ALEV4:UnsupportedISETSpatialFixture');
    expectError(@() alev4.isetSpatialFixture('uniform',-1),'ALEV4:InvalidSeed');
    expectError(@() alev4.isetSpatialFixture('uniform',NaN),'ALEV4:InvalidSeed');
    expectError(@() alev4.isetSpatialFixture('uniform',true),'ALEV4:InvalidSeed');
    expectError(@() alev4.isetSpatialFixture('uniform',1,0),'ALEV4:InvalidExposure');
    expectError(@() alev4.isetSpatialFixture('uniform',1,Inf),'ALEV4:InvalidExposure');
    expectError(@() alev4.isetSpatialFixture('uniform',1,true),'ALEV4:InvalidExposure');
    original_path = path;
    cleanup = onCleanup(@() path(original_path)); %#ok<NASGU>
    implementation = which('sensorCompute');
    assert(~isempty(implementation),'Missing ISET cannot count as a passed test.');
    rmpath(fileparts(implementation));
    clear sensorCompute;
    assert(exist('sensorCompute','file') ~= 2,'Missing-dependency fixture did not actually remove its dependency.');
    expectError(@() alev4.isetSpatialFixture('uniform'),'ALEV4:MissingISETCam');
end

function expectError(action,identifier)
    caught = false;
    try
        action();
    catch err
        caught = true;
        assert(strcmp(err.identifier,identifier), ...
            ['Expected ' identifier ', received ' err.identifier ': ' err.message]);
    end
    assert(caught,['Expected rejection: ' identifier]);
end

function state = captureState()
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

function requireState(expected)
    assert(isequal(captureState(),expected),'ISET caller state was not restored.');
end

function prefs = unrelatedPreferences()
    prefs = getpref();
    if isfield(prefs,'ISET'), prefs = rmfield(prefs,'ISET'); end
end

function restoreCaller(state,previous_rng)
    rng(previous_rng);
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
