function report = test_phase3_optics()
%TEST_PHASE3_OPTICS Independent finite-PSF, physical-crop and transfer oracles.
%   Synthetic kernels establish mathematics, not measured camera optics.
    caller_rng = rng;
    guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    names = {'configuration_normalization_and_stable_coefficients', ...
        'exact_identity_and_seeded_single_dual_readouts', ...
        'scalar_convolution_even_asymmetric_origins_and_physical_crops', ...
        'impulse_orientation_translation_and_complete_support_mass', ...
        'finite_crop_energy_loss_and_declared_zero_border_support', ...
        'exact_per_wavelength_kernel_mapping', ...
        'flat_field_preservation_and_linearity', ...
        'independent_complex_two_dimensional_dft', ...
        'binomial_cosine_dc_and_nyquist_oracles', ...
        'origin_phase_and_separate_continuous_aperture_reference', ...
        'cell_average_sinusoid_through_optics_sampling_and_charge', ...
        'edge_blur_before_cfa_and_collection_factors_once', ...
        'malformed_kernel_frequency_and_metadata_rejection', ...
        'uniform_grid_support_and_numeric_range_rejection', ...
        'caller_rng_and_inputs_preserved_on_success_and_failure'};
    testConfiguration();
    testIdentity();
    testScalarConvolution();
    testImpulse();
    testFiniteSupport();
    testSpectralBank();
    testFlatLinearity();
    dft_error = testDirectDft();
    testBinomial();
    testOriginAperture();
    sinusoid_error = testSinusoidPipeline();
    edge_error = testEdgePipeline();
    testMalformed();
    testGridAndRange();
    testCallerState();
    tests = repmat(struct('name','','status','passed','passed',true),1,numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    metrics = struct('maximum_scalar_dft_error',dft_error, ...
        'maximum_sinusoid_electron_error',sinusoid_error, ...
        'maximum_edge_electron_error',edge_error, ...
        'model','explicit_finite_synthetic_kernel', ...
        'calibrated_alev4',false);
    report = struct('suite','phase3_optics','status','passed','passed',true, ...
        'test_count',numel(names),'tests',tests,'metrics',metrics);
    fprintf('PASS: Phase 3 optics, %d test groups.\n',numel(names));
end

function testConfiguration()
    p = alev4.createOpticalPsf(struct('kernel',sparse([0.25 0.75]), ...
        'origin_rc',uint8([1 2]),'spacing_yx_m',single([0.5 0.25])));
    assert(isa(p.kernel,'double') && ~issparse(p.kernel));
    assert(isequal(p.kernel,[0.25 0.75]));
    assert(isequal(p.origin_rc,[1 2]));
    assert(isequal(p.spacing_yx_m,[0.5 0.25]));
    assert(isequal(alev4.createOpticalPsf(p),p));
    assert(strcmp(p.boundary_policy,'valid'));
    assert(isequal(p.parameter_sources,{'ASSUMED-DISCRETE-PSF'}));
    % The documented summation tolerance does not silently modify metadata.
    near_unit = 1+eps(1);
    q = alev4.createOpticalPsf(struct('kernel',near_unit));
    assert(q.kernel == near_unit);
    assert(isequal(alev4.createOpticalPsf(q),q));
end

function testIdentity()
    pitch = 2e-6;
    geometry = alev4.createSensorGeometry(struct('full_grid_size',[5 7], ...
        'pixel_pitch_m',pitch));
    grid = uniformGrid([5 7],[pitch pitch],[0 0]);
    input = reshape((1:70).^2,[5 7 2])*1e12;
    psf = makePsf(1,[1 1],[pitch pitch]);
    [observed,g,r] = alev4.applyOpticalPsf(input,grid,psf,[480 650]);
    assert(isequal(observed,input) && isequal(g,grid));
    assert(isequal(r.required_halo_top_bottom_left_right,[0 0 0 0]));
    single = alev4.createBaselineSensor(struct('image_size',[5 7], ...
        'pixel_pitch_m',pitch,'wavelength_nm',[480;650], ...
        'bin_width_nm',[10;20],'qe',[0.4 0.7 0.2;0.8 0.3 0.1]));
    a = alev4.simulateSpatialExposure(input,grid,geometry,single,1e-3,31415);
    b = alev4.simulateExposure(input,single,1e-3,31415);
    assert(isequal(a.readout,b), 'Identity optics changed seeded single-gain observations.');
    dual = alev4.createDualGainSensor(struct('sensor',single));
    c = alev4.simulateSpatialExposure(input,grid,geometry,dual,1e-3,31416);
    d = alev4.simulateDualGainExposure(input,dual,1e-3,31416);
    assert(isequal(c.readout,d), 'Identity optics changed seeded simultaneous readout.');
    assert(isequal(a.sampled_irradiance,input) && isequal(c.sampled_irradiance,input));
end

function testScalarConvolution()
    input = reshape(mod((1:70)*13,31)+0.25,[7 10]);
    kernel = [1 2 3;4 5 1]/16;
    grid = uniformGrid([7 10],[0.5 0.25],[-2 -1]);
    for origin_r = 1:2
        for origin_c = 1:3
            psf = makePsf(kernel,[origin_r origin_c],[0.5 0.25]);
            [observed,out_grid,report] = alev4.applyOpticalPsf(input,grid,psf);
            expected = scalarConvolution(input,kernel,[origin_r origin_c]);
            assertClose(observed,expected,64*eps(max(expected(:))));
            first = [3-origin_r 4-origin_c];
            last = [8-origin_r 11-origin_c];
            assert(isequal(out_grid.y_edges_m,grid.y_edges_m(first(1):last(1)+1)));
            assert(isequal(out_grid.x_edges_m,grid.x_edges_m(first(2):last(2)+1)));
            assert(isequal(report.retained_row_indices,[first(1) last(1)]));
            assert(isequal(report.retained_column_indices,[first(2) last(2)]));
            assert(isequal(report.required_halo_top_bottom_left_right, ...
                [2-origin_r origin_r-1 3-origin_c origin_c-1]));
        end
    end
end

function testImpulse()
    kernel = [1 2 3;4 5 1]/16;
    origin = [1 2];
    psf = makePsf(kernel,origin,[1 1]);
    grid = uniformGrid([11 14],[1 1],[0 0]);
    for shift = [0 1]
        input = zeros(11,14);
        location = [5+shift 7+shift];
        input(location(1),location(2)) = 1;
        observed = alev4.applyOpticalPsf(input,grid,psf);
        expected = zeros(10,12);
        first = [2 2];
        for r = 1:2
            for c = 1:3
                physical_index = location+[r c]-origin;
                output_index = physical_index-first+1;
                expected(output_index(1),output_index(2)) = kernel(r,c);
            end
        end
        assert(isequal(observed,expected), 'Impulse orientation or coordinate shift is reversed.');
        assert(sum(observed(:)) == 1, 'Complete interior support must retain impulse mass.');
        if shift == 0, unshifted = observed; else
            assert(isequal(observed(2:end,2:end),unshifted(1:end-1,1:end-1)));
        end
    end
end

function testFiniteSupport()
    grid = uniformGrid([1 9],[1 1],[0 0]);
    psf = makePsf([0.25 0.5 0.25],[1 2],[1 1]);
    input = zeros(1,9); input(1) = 1;
    [observed,g] = alev4.applyOpticalPsf(input,grid,psf);
    assert(isequal(observed,[0.25 0 0 0 0 0 0]));
    assert(sum(observed(:)) == 0.25, 'Boundary loss was hidden by renormalizing the crop.');
    assert(isequal(g.x_edges_m,1:8));
    delta = makePsf([0 1 0],[1 2],[1 1]);
    [observed,g] = alev4.applyOpticalPsf(1:9,grid,delta);
    assert(isequal(observed,2:8));
    assert(isequal(g.x_edges_m,1:8), 'Declared zero borders must still require complete support.');
end

function testSpectralBank()
    input = cat(3,reshape(1:30,[5 6]),reshape(31:60,[5 6]));
    kernels = cat(3,[0.5 0;0 0.5],[0 0.25;0.75 0]);
    psf = makePsf(kernels,[2 1],[1 1],[500;650]);
    grid = uniformGrid([5 6],[1 1],[0 0]);
    observed = alev4.applyOpticalPsf(input,grid,psf,[500 650]);
    for k = 1:2
        expected = scalarConvolution(input(:,:,k),kernels(:,:,k),[2 1]);
        assert(isequal(observed(:,:,k),expected));
    end
    transfer = alev4.opticalMtf(psf,[-0.25 0 0.25],[-0.2 0.2]);
    for k = 1:2
        expected = scalarDft(kernels(:,:,k),[2 1],[1 1],[-0.25 0 0.25],[-0.2 0.2]);
        assertClose(transfer.optical_otf(:,:,k),expected,32*eps(1));
    end
    expectError(@() alev4.applyOpticalPsf(input,grid,psf),'ALEV4:OpticalSpectralMapping');
    expectError(@() alev4.applyOpticalPsf(input,grid,psf,[500 651]),'ALEV4:OpticalSpectralMapping');
    expectError(@() alev4.applyOpticalPsf(input,grid,psf,[650 500]),'ALEV4:OpticalSpectralMapping');
    shared = makePsf(kernels(:,:,1),[2 1],[1 1]);
    expectError(@() alev4.applyOpticalPsf(input,grid,shared,500),'ALEV4:OpticalSpectralMapping');
end

function testFlatLinearity()
    kernel = [1 2 1;2 4 2;1 2 1]/16;
    psf = makePsf(kernel,[2 2],[0.5 0.25]);
    grid = uniformGrid([8 9],[0.5 0.25],[-0.5 -1]);
    input = cat(3,ones(8,9)*7,ones(8,9)*1e20);
    output = alev4.applyOpticalPsf(input,grid,psf,[500 600]);
    first_plane = output(:,:,1);
    assert(all(first_plane(:) == 7));
    assertClose(output(:,:,2),ones(6,7)*1e20,32*eps(1e20));
    a = reshape(mod(1:72,11),[8 9]);
    b = reshape(mod((1:72)*7,17),[8 9]);
    one = alev4.applyOpticalPsf(2*a+3*b,grid,psf);
    two = 2*alev4.applyOpticalPsf(a,grid,psf)+3*alev4.applyOpticalPsf(b,grid,psf);
    assert(isequal(one,two));
    assert(all(one(:) >= 0));
end

function maximum_error = testDirectDft()
    kernel = [1 2 3;4 5 1]/16;
    fx = [-1.5 -0.7 0 0.3 1.5];
    fy = [-0.8 0 0.6];
    maximum_error = 0;
    for r0 = 1:2
        for c0 = 1:3
            psf = makePsf(kernel,[r0 c0],[0.5 0.25]);
            report = alev4.opticalMtf(psf,fx,fy);
            expected = scalarDft(kernel,[r0 c0],[0.5 0.25],fx,fy);
            maximum_error = max(maximum_error,max(abs(report.optical_otf(:)-expected(:))));
            assertClose(report.optical_otf,expected,64*eps(1));
            assertClose(report.optical_mtf,abs(expected),64*eps(1));
            assert(strcmp(report.frequency_units,'cycles m^-1'));
            assert(isequal(report.nyquist_yx_cycles_per_m,[1 2]));
            assert(strcmp(report.model,'finite_discrete_synthetic_kernel'));
            assert(report.synthetic && ~report.calibrated_alev4);
        end
    end
end

function testBinomial()
    row = [0.25 0.5 0.25];
    kernel = row.'*row;
    spacing = [2e-6 3e-6];
    fx = [0 0.125 0.25 0.5]/spacing(2);
    fy = [0 0.125 0.25 0.5]/spacing(1);
    psf = makePsf(kernel,[2 2],spacing);
    report = alev4.opticalMtf(psf,fx,fy);
    expected = (0.5+0.5*cos(2*pi*fy(:)*spacing(1)))* ...
        (0.5+0.5*cos(2*pi*fx(:).'*spacing(2)));
    assertClose(report.optical_otf,expected,64*eps(1));
    assert(report.optical_otf(1,1) == 1);
    assert(max(report.optical_mtf(end,:)) < 64*eps(1));
    assert(max(report.optical_mtf(:,end)) < 64*eps(1));
end

function testOriginAperture()
    psf = makePsf([0 1],[1 1],[2 1]);
    fx = [0 0.125 0.25 0.5];
    fy = [0 0.125 0.25];
    first = alev4.opticalMtf(psf,fx,fy,2);
    assertClose(first.optical_otf,repmat(exp(-2*pi*1i*fx),numel(fy),1),32*eps(1));
    assertClose(first.optical_mtf,ones(numel(fy),numel(fx)),32*eps(1));
    psf.origin_rc = [1 2];
    second = alev4.opticalMtf(psf,fx,fy,2);
    assertClose(second.optical_otf,ones(numel(fy),numel(fx)),32*eps(1));
    assertClose(second.optical_mtf,first.optical_mtf,32*eps(1));
    expected_aperture = independentSinc(2*fy(:))*independentSinc(2*fx(:).');
    assertClose(first.pixel_aperture_otf,expected_aperture,32*eps(1));
    assertClose(first.optical_times_continuous_aperture_mtf,abs(expected_aperture),32*eps(1));
    assert(strcmp(first.aperture_model,'ideal_continuous_square_analytical_reference'));
    assert(~isempty(strfind(first.aperture_caveat,'do not apply averaging twice'))); %#ok<STREMP>
    no_aperture = alev4.opticalMtf(psf,fx,fy);
    assert(~isfield(no_aperture,'pixel_aperture_otf'));
end

function maximum_error = testSinusoidPipeline()
    d = 1e-6;
    pitch = 2*d;
    frequency = 1/(8*d);
    grid = uniformGrid([8 48],[d d],[0 0]);
    xcentre = ((1:48)-0.5)*d;
    base = 1e16; amplitude = 0.4*base;
    % Exact averages of a continuous cosine over each input cell.
    input_row = base+amplitude*independentSinc(frequency*d)*cos(2*pi*frequency*xcentre);
    input = repmat(input_row,8,1);
    psf = makePsf([0.25 0.5 0.25],[1 2],[d d]);
    geometry = alev4.createSensorGeometry(struct('full_grid_size',[3 20], ...
        'pixel_pitch_m',pitch,'origin_xy_m',[3*d d]));
    cfg = oneBinConfig([3 20],pitch,[0.6 0.6 0.6],0.4,10);
    exposure = 0.01;
    result = alev4.simulateSpatialExposure(input,grid,geometry,cfg,exposure,817,struct('psf',psf));
    target_centres = 3*d+((1:20)-0.5)*pitch;
    optical_attenuation = 0.5+0.5*cos(2*pi*frequency*d);
    expected_density = base+amplitude*optical_attenuation* ...
        independentSinc(frequency*pitch)*cos(2*pi*frequency*target_centres);
    expected_density = repmat(expected_density,3,1);
    assertClose(result.sampled_irradiance,expected_density,512*eps(base));
    expected_electrons = expected_density*pitch^2*0.4*0.6*10*exposure;
    maximum_error = max(abs(result.readout.expected_electrons(:)-expected_electrons(:)));
    assertClose(result.readout.expected_electrons,expected_electrons,2048*eps(max(expected_electrons(:))));
    expected_raw = uint16(floor(expected_electrons*cfg.gain_dn_per_e+cfg.black_level_dn+0.5));
    assert(isequal(result.readout.raw_dn,expected_raw));
    mtf = alev4.opticalMtf(psf,frequency,0,pitch);
    assertClose(mtf.optical_mtf,optical_attenuation,16*eps(1));
    assertClose(mtf.optical_times_continuous_aperture_mtf, ...
        optical_attenuation*independentSinc(frequency*pitch),32*eps(1));
    assert(isequal(result.operation_order, ...
        {'optical_psf','area_overlap_average','spectral_integration','single_gain_readout'}));
end

function maximum_error = testEdgePipeline()
    d = 1e-6;
    grid = uniformGrid([4 10],[d d],[0 0]);
    input = repmat([0 0 0 0 1 1 1 1 1 1]*1e15,4,1);
    psf = makePsf([0.25 0.5 0.25],[1 2],[d d]);
    geometry = alev4.createSensorGeometry(struct('full_grid_size',[2 3], ...
        'pixel_pitch_m',2*d,'origin_xy_m',[2*d 0],'full_grid_cfa_pattern','BGGR'));
    cfg = oneBinConfig([2 3],2*d,[0.3 0.6 0.9],0.75,30);
    cfg.cfa_pattern = 'BGGR';
    result = alev4.simulateSpatialExposure(input,grid,geometry,cfg,0.02,818,struct('psf',psf));
    expected_density = repmat([0.125 0.875 1]*1e15,2,1);
    assertClose(result.sampled_irradiance,expected_density,32*eps(1e15));
    expected_qe = [0.9 0.6 0.9;0.6 0.3 0.6];
    expected_electrons = expected_density.*expected_qe*(2*d)^2*0.75*30*0.02;
    maximum_error = max(abs(result.readout.expected_electrons(:)-expected_electrons(:)));
    assertClose(result.readout.expected_electrons,expected_electrons,256*eps(max(expected_electrons(:))));
    assert(all(result.readout.expected_electrons(:) >= 0));
    assert(~any(result.readout.full_well_saturated(:)));
    % No extra optical operation is legal on input that already has optics.
    expectError(@() alev4.simulateSpatialExposure(input,grid,geometry,cfg,0.02,818, ...
        struct('input_stage','post_optics','psf',psf)),'ALEV4:DuplicateOptics');
end

function testMalformed()
    bad = {struct('kernel',0),struct('kernel',NaN),struct('kernel',Inf), ...
        struct('kernel',-1),struct('kernel',1+1i),struct('kernel',[]), ...
        struct('kernel',[0.5 0.5]),struct('kernel',ones(64)/4096,'origin_rc',[1 1]), ...
        struct('kernel',[0.5 0.5],'origin_rc',[1 1.5]), ...
        struct('kernel',[0.5 0.5],'origin_rc',[0 1]), ...
        struct('kernel',[0.5 0.5],'origin_rc',[1 3]), ...
        struct('origin_rc',[1 1 1]),struct('boundary_policy','same'), ...
        struct('schema_version','2.0'),struct('mispelled',1), ...
        struct('parameter_sources',{}), ...
        struct('parameter_sources',{{'ID','ID'}}), ...
        struct('parameter_sources',{{sprintf('ID\n')}}), ...
        struct('spacing_yx_m',[1 NaN]),struct('spacing_yx_m',[1 -1])};
    for k = 1:numel(bad), expectError(@() alev4.createOpticalPsf(bad{k}),'ALEV4:'); end
    banks = cat(3,1,1);
    expectError(@() alev4.createOpticalPsf(struct('kernel',banks)),'ALEV4:OpticalSpectralMapping');
    expectError(@() alev4.createOpticalPsf(struct('kernel',banks,'wavelength_nm',[600 500])), ...
        'ALEV4:OpticalSpectralMapping');
    expectError(@() alev4.createOpticalPsf(struct('kernel',banks,'wavelength_nm',500)), ...
        'ALEV4:OpticalSpectralMapping');
    psf = makePsf(1,[1 1],[1 1]);
    invalid_frequency = {[],NaN,Inf,1i,'0',ones(2)};
    for k = 1:numel(invalid_frequency)
        expectError(@() alev4.opticalMtf(psf,invalid_frequency{k},0),'ALEV4:InvalidOpticalFrequency');
    end
    expectError(@() alev4.opticalMtf(psf,0.5+eps(1),0),'ALEV4:OpticalFrequencyRange');
    expectError(@() alev4.opticalMtf(psf,0,-0.5-eps(1)),'ALEV4:OpticalFrequencyRange');
    for pitch = [0 -1 Inf NaN]
        expectError(@() alev4.opticalMtf(psf,0,0,pitch),'ALEV4:InvalidOpticalAperture');
    end
    expectError(@() alev4.opticalMtf(psf,zeros(1,1001),zeros(1,1000)), ...
        'ALEV4:OpticalNumericRange');
end

function testGridAndRange()
    grid = uniformGrid([3 4],[1 1],[0 0]);
    input = ones(3,4);
    psf = makePsf(1,[1 1],[1 1]);
    bad = grid; bad.x_edges_m = [0 1 2.1 3 4];
    expectError(@() alev4.applyOpticalPsf(input,bad,psf),'ALEV4:OpticalGridMismatch');
    bad = grid; bad.y_edges_m = (0:3)*1.01;
    expectError(@() alev4.applyOpticalPsf(input,bad,psf),'ALEV4:OpticalGridMismatch');
    mismatch = psf; mismatch.spacing_yx_m = [1 2];
    expectError(@() alev4.applyOpticalPsf(input,grid,mismatch),'ALEV4:OpticalGridMismatch');
    wide = makePsf(ones(1,5)/5,[1 3],[1 1]);
    expectError(@() alev4.applyOpticalPsf(input,grid,wide),'ALEV4:OpticalSupport');
    tall = makePsf(ones(4,1)/4,[2 1],[1 1]);
    expectError(@() alev4.applyOpticalPsf(input,grid,tall),'ALEV4:OpticalSupport');
    expectError(@() alev4.createOpticalPsf(struct('spacing_yx_m',[realmin*eps(1) 1])), ...
        'ALEV4:OpticalNumericRange');
    tiny = realmin*eps(1);
    two = uniformGrid([1 2],[1 1],[0 0]);
    average = makePsf([0.5 0.5],[1 1],[1 1]);
    expectError(@() alev4.applyOpticalPsf([tiny 0],two,average),'ALEV4:OpticalNumericRange');
    larger = makePsf(1+eps(1),[1 1],[1 1]);
    expectError(@() alev4.applyOpticalPsf(realmax,uniformGrid([1 1],[1 1],[0 0]),larger), ...
        'ALEV4:OpticalNumericRange');
    narrow = makePsf(1,[1 1],[1e-100 1e-100]);
    expectError(@() alev4.opticalMtf(narrow,1e99,0,1e300),'ALEV4:OpticalNumericRange');
end

function testCallerState()
    rng(781,'twister');
    saved = rng;
    input = reshape(1:30,[5 6]);
    grid = uniformGrid([5 6],[1 1],[-1 2]);
    psf = makePsf([0.25 0.5 0.25],[1 2],[1 1]);
    original_input = input; original_grid = grid; original_psf = psf;
    alev4.createOpticalPsf(psf);
    alev4.applyOpticalPsf(input,grid,psf);
    alev4.opticalMtf(psf,[0 0.25],[-0.25 0],2);
    assert(isequal(rng,saved));
    expectError(@() alev4.applyOpticalPsf(input,grid,makePsf(1,[1 1],[2 1])), ...
        'ALEV4:OpticalGridMismatch');
    expectError(@() alev4.opticalMtf(psf,1,0),'ALEV4:OpticalFrequencyRange');
    assert(isequal(rng,saved));
    assert(isequal(input,original_input) && isequal(grid,original_grid) && isequal(psf,original_psf));
end

function psf = makePsf(kernel,origin,spacing,wave)
    if nargin < 4, wave = []; end
    psf = alev4.createOpticalPsf(struct('kernel',kernel,'origin_rc',origin, ...
        'spacing_yx_m',spacing,'wavelength_nm',wave));
end

function grid = uniformGrid(sz,spacing,origin)
    grid = alev4.createSpatialGrid(struct( ...
        'x_edges_m',origin(1)+(0:sz(2))*spacing(2), ...
        'y_edges_m',origin(2)+(0:sz(1))*spacing(1)));
end

function cfg = oneBinConfig(sz,pitch,qe,fill,width)
    cfg = alev4.createBaselineSensor(struct('image_size',sz, ...
        'pixel_pitch_m',pitch,'wavelength_nm',550,'bin_width_nm',width, ...
        'qe',qe,'fill_factor',fill,'read_noise_e',0,'shot_noise',false, ...
        'gain_dn_per_e',0.5));
end

function expected = scalarConvolution(input,kernel,origin)
    height = size(input,1); width = size(input,2);
    kh = size(kernel,1); kw = size(kernel,2);
    first = [kh-origin(1)+1 kw-origin(2)+1];
    expected = zeros(height-kh+1,width-kw+1);
    for r = 1:size(expected,1)
        for c = 1:size(expected,2)
            ri = first(1)+r-1; ci = first(2)+c-1;
            value = 0;
            for kr = 1:kh
                for kc = 1:kw
                    value = value+kernel(kr,kc)*input(ri-(kr-origin(1)),ci-(kc-origin(2)));
                end
            end
            expected(r,c) = value;
        end
    end
end

function expected = scalarDft(kernel,origin,spacing,fx,fy)
    expected = complex(zeros(numel(fy),numel(fx)));
    for y = 1:numel(fy)
        for x = 1:numel(fx)
            value = 0;
            for r = 1:size(kernel,1)
                for c = 1:size(kernel,2)
                    cycles = fy(y)*(r-origin(1))*spacing(1)+fx(x)*(c-origin(2))*spacing(2);
                    value = value+kernel(r,c)*(cos(2*pi*cycles)-1i*sin(2*pi*cycles));
                end
            end
            expected(y,x) = value;
        end
    end
end

function value = independentSinc(argument)
    value = ones(size(argument));
    for k = 1:numel(argument)
        if argument(k) ~= 0, value(k) = sin(pi*argument(k))/(pi*argument(k)); end
    end
end

function assertClose(actual,expected,tolerance)
    assert(isequal(size(actual),size(expected)));
    assert(all(isfinite(actual(:))) && all(abs(actual(:)-expected(:)) <= tolerance));
end

function expectError(action,prefix)
    caught = false;
    try
        action();
    catch err
        caught = true;
        assert(strncmp(err.identifier,prefix,numel(prefix)), ...
            'Unexpected exception %s, expected %s.',err.identifier,prefix);
    end
    assert(caught,'Required rejection did not occur: %s.',prefix);
end
