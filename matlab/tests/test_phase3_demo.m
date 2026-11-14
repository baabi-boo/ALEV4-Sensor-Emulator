function report = test_phase3_demo()
%TEST_PHASE3_DEMO Verify retained core fixtures, bytes and completion scope.
%   No native ISET execution is required here. A missing-dependency failure
%   exercises the full-demo completion gate after seven real core exports.
%   Byte repetition here is within one process; independent fresh-process
%   repetition and the genuine ISET fixture remain separate acceptance gates.
    caller = captureCaller();
    restore_caller = onCleanup(@() restoreCaller(caller)); %#ok<NASGU>
    folder = tempname;
    [ok,message] = mkdir(folder); assert(ok,message);
    remove_folder = onCleanup(@() removeOwnedFolder(folder)); %#ok<NASGU>
    primary = fullfile(folder,'primary');
    repeated = fullfile(folder,'repeat');
    fixture_names = {'identity_single','flat_binomial','shifted_impulse', ...
        'edge','sinusoid','crop_cfa','dual_spatial'};
    names = {'core_only_summary_cannot_claim_complete_demo_or_phase', ...
        'seven_fixed_names_seeds_exposure_and_complete_configurations', ...
        'exact_file_inventory_lengths_order_and_native_readback', ...
        'summary_statistics_reconstructed_from_actual_expected_bytes', ...
        'identity_and_binomial_flat_independent_charge_and_adc', ...
        'asymmetric_shifted_impulse_location_orientation_and_mass', ...
        'edge_transition_and_cell_average_sinusoid_attenuation', ...
        'cropped_absolute_bayer_phase_and_spectral_charge', ...
        'noisy_dual_fixture_observable_merge_flags_and_charge_constraints', ...
        'same_process_repeat_independent_of_caller_rng', ...
        'existing_files_directories_and_complete_outputs_never_overwritten', ...
        'malformed_output_paths_and_include_flags_rejected', ...
        'late_required_iset_failure_refuses_completion_marker', ...
        'caller_rng_path_directory_handles_and_iset_state_restored'};

    rng(9411,'twister');
    before = captureCaller();
    summary = phase3_demo(primary,false);
    requireCaller(before);
    checkSummaryScope(summary,fixture_names);
    persisted = jsondecode(native2unicode(readBytes(fullfile(primary, ...
        'phase3-demo-summary.json')).','UTF-8'));
    checkSummaryScope(persisted,fixture_names);
    assert(isequal(summary.runtime,persisted.runtime));
    assert(isequal(summary.provenance,persisted.provenance));
    assert(isequal(directoryNames(primary),sort([fixture_names {'phase3-demo-summary.json'}])));

    files = {'phase3-demo-summary.json'};
    maximum_charge_error = 0;
    maximum_density_error = 0;
    sinusoid_wrong_model_gap = 0;
    crop_wrong_phase_gap = 0;
    for k = 1:numel(fixture_names)
        name = fixture_names{k};
        directory = fullfile(primary,name);
        [decoded,meta] = alev4.readSpatialBundle(directory);
        oracle = fixtureOracle(name);
        checkConfiguration(decoded,meta,oracle,k,summary);
        expected_files = bundleFiles(k);
        assert(isequal(directoryNames(directory),expected_files));
        for j = 1:numel(expected_files)
            files{end+1} = fullfile(name,expected_files{j}); %#ok<AGROW>
        end

        % Shapes and order come from fixed fixture mathematics, rather than
        % trusting manifest dimensions or a producer's reported success.
        input = readPlane(fullfile(directory,'input.f64'),size(oracle.input),'double');
        optical = readPlane(fullfile(directory,'optical.f64'),size(oracle.optical),'double');
        sampled = readPlane(fullfile(directory,'sampled.f64'),size(oracle.sampled),'double');
        expected = readPlane(fullfile(directory,'expected.f64'),oracle.image_size,'double');
        assert(isequal(input,decoded.input_irradiance));
        assert(isequal(optical,decoded.optical_irradiance));
        assert(isequal(sampled,decoded.sampled_irradiance));
        assert(isequal(expected,decoded.readout.expected_electrons));
        near(input,oracle.input); near(optical,oracle.optical);
        near(sampled,oracle.sampled); near(expected,oracle.expected);
        maximum_charge_error = max(maximum_charge_error,max(abs(expected(:)-oracle.expected(:))));
        maximum_density_error = max(maximum_density_error,max(abs(sampled(:)-oracle.sampled(:))));
        if k ~= 6
            kernel = readPlane(fullfile(directory,'psf.f64'),size(oracle.kernel),'double');
            assert(isequal(kernel,oracle.kernel) && isequal(kernel,decoded.psf.kernel));
        end
        checkSummaryFrame(summary.frames(k),expected,k,oracle);
        checkSummaryFrame(persisted.frames(k),expected,k,oracle);
        if k < 7
            raw = readPlane(fullfile(directory,'readout.raw'),oracle.image_size,'uint16');
            expected_raw = uint16(min(65535,max(0,floor(0.5*min(oracle.expected,30000)+64+0.5))));
            assert(isequal(raw,expected_raw) && isequal(raw,decoded.readout.raw_dn), ...
                'Deterministic demo RAW disagrees with independent charge/ADC arithmetic.');
        else
            checkDual(directory,decoded,oracle.expected);
        end
        if k == 3
            assert(isequal(sampled==0,oracle.sampled==0), ...
                'The shifted impulse leaked outside its declared asymmetric support.');
            near(sum(sum(sampled(:,:,1))),20e14);
            near(sum(sum(sampled(:,:,2))),12e14);
            assert(sampled(3,3,1)==0 && sampled(3,5,1)>0 && sampled(4,3,1)>0, ...
                'The even asymmetric kernel was flipped or placed at the wrong origin.');
        elseif k == 5
            x = ((1:8)-0.5)*6e-6;
            z = 1/8;
            no_psf = 1e14*(1+0.4*sin(2*pi*x/(8*6e-6))*sin(pi*z)/(pi*z));
            sinusoid_wrong_model_gap = max(abs(oracle.sampled(1,:,1)-no_psf));
            assert(sinusoid_wrong_model_gap>1e12, ...
                'The sinusoid oracle must distinguish omitted optical blur.');
        elseif k == 6
            wrong_phase = chargeOracle(oracle.sampled,[1 1]);
            crop_wrong_phase_gap = max(abs(oracle.expected(:)-wrong_phase(:)));
            assert(crop_wrong_phase_gap>100, ...
                'The cropped fixture must expose an incorrectly restarted Bayer tile.');
        end
    end
    assert(numel(files)==59,'The seven fixed bundles and one summary must contain 59 files.');
    requireCaller(before);

    % A different caller RNG state must neither change seeded output bytes
    % nor be consumed by the demo's deterministic helpers and native I/O.
    rng(9412,'twister');
    before_repeat = captureCaller();
    second = phase3_demo(repeated,false);
    requireCaller(before_repeat);
    assert(isequal(second,summary));
    for k = 1:numel(files)
        assert(isequal(readBytes(fullfile(primary,files{k})), ...
            readBytes(fullfile(repeated,files{k}))), ...
            'Identical same-runtime fixtures produced different retained bytes.');
    end

    testNoOverwrite(folder,primary,files);
    testMalformed(folder);
    testFailedCompletion(folder,fixture_names);
    requireCaller(before_repeat);
    tests = repmat(struct('name','','status','passed','passed',true),1,numel(names));
    for k = 1:numel(names), tests(k).name = names{k}; end
    report = struct('suite','phase3_demo','status','passed','passed',true, ...
        'test_count',numel(names),'tests',tests,'metrics',struct( ...
        'fixture_frame_count',7,'fixture_file_count',numel(files), ...
        'maximum_expected_electron_error',maximum_charge_error, ...
        'maximum_sampled_density_error',maximum_density_error, ...
        'sinusoid_omitted_psf_wrong_model_gap',sinusoid_wrong_model_gap, ...
        'crop_wrong_cfa_maximum_gap_e',crop_wrong_phase_gap, ...
        'repeat_scope','same process only','iset_executed_by_this_suite',false, ...
        'fixture_is_full_phase3_evidence',false,'synthetic',true,'calibrated_alev4',false));
    fprintf('PASS: Phase 3 demonstration contract, %d test groups (core fixtures only).\n',numel(names));
end

function checkSummaryScope(summary,names)
    assert(isstruct(summary) && isscalar(summary));
    assert(strcmp(summary.schema_version,'1.0') && summary.phase==3);
    assert(isequal(summary.synthetic,true) && isequal(summary.calibrated_alev4,false));
    assert(isequal(summary.demo_complete,false) && isequal(summary.iset_included,false), ...
        'A core-only demo must not publish a complete-demo marker.');
    assert(summary.frame_count==7 && numel(summary.frames)==7);
    assert(isequal(reshape({summary.frames.name},1,[]),names));
    assert(~isfield(summary,'phase3_passed') || isequal(summary.phase3_passed,false), ...
        'A demo cannot claim complete Phase 3 acceptance.');
    assert(~isfield(summary,'authentic_arriraw') || isequal(summary.authentic_arriraw,false));
    if exist('OCTAVE_VERSION','builtin'), runtime='GNU Octave'; else, runtime='MATLAB'; end
    assert(strcmp(summary.runtime.name,runtime) && strcmp(summary.runtime.version,version));
end

function checkConfiguration(decoded,meta,o,index,summary)
    if index==7, cfg=decoded.configuration.sensor; else, cfg=decoded.configuration; end
    assert(isequal(cfg.image_size,o.image_size));
    assert(isequal(decoded.geometry.full_grid_size,o.full_size));
    assert(isequal(decoded.geometry.active_roi,o.roi));
    assert(isequal(decoded.geometry.origin_xy_m,[0 0]));
    assert(strcmp(decoded.geometry.full_grid_cfa_pattern,'RGGB'));
    assert(isequal(decoded.geometry.parameter_sources, ...
        {'ASSUMED-GENERIC-GEOMETRY','ASSUMED-CFA-ORIGIN'}));
    near(decoded.geometry.pixel_pitch_m,6e-6,4);
    near(cfg.pixel_pitch_m,6e-6,4);
    near(cfg.fill_factor,0.8,4);
    assert(cfg.full_well_e==30000);
    assert(isequal(cfg.wavelength_nm,[500;600]) && isequal(cfg.bin_width_nm,[20;20]));
    near(cfg.qe,[0.1 0.8 0.2;0.7 0.2 0.05],4);
    assert(strcmp(cfg.cfa_pattern,o.pattern));
    assert(isequal(cfg.shot_noise,index==7));
    assert(meta.seed==8300+index && decoded.readout.seed==8300+index);
    assert(meta.exposure_s==0.01 && decoded.readout.exposure_s==0.01);
    assert(isequal(meta.runtime,summary.runtime) && isequal(meta.provenance,summary.provenance));
    assert(strcmp(meta.format,'ALEV4-SYNTHETIC-SPATIAL'));
    assert(strcmp(meta.array_order,'plane-major-row-major') && strcmp(meta.byte_order,'little-endian'));
    assert(meta.synthetic && ~meta.calibrated_alev4 && ~meta.authentic_arriraw);
    assert(strcmp(decoded.readout_mode,o.mode) && strcmp(decoded.input_stage,o.stage));
    near(decoded.input_grid.x_edges_m,o.xedges);
    near(decoded.input_grid.y_edges_m,o.yedges);
    near(decoded.optical_grid.x_edges_m,o.optical_xedges);
    near(decoded.optical_grid.y_edges_m,o.optical_yedges);
    order = {'area_overlap_average','spectral_integration',[o.mode '_gain_readout']};
    if index==6
        assert(isequal(decoded.psf,[]) && ~isfield(meta.files,'psf'));
    else
        order = [{'optical_psf'} order];
        assert(isequal(decoded.psf.origin_rc,o.origin));
        near(decoded.psf.spacing_yx_m,[o.step o.step],4);
        assert(isequal(decoded.psf.parameter_sources,{'ASSUMED-DISCRETE-PSF'}));
        assert(strcmp(decoded.psf.boundary_policy,'valid') && isempty(decoded.psf.wavelength_nm));
    end
    assert(isequal(decoded.operation_order,order) && isequal(meta.operation_order,order));
    if index<7
        assert(cfg.read_noise_e==0 && cfg.gain_dn_per_e==0.5);
        assert(cfg.black_level_dn==64 && cfg.adc_bits==16);
    else
        dual=decoded.configuration;
        assert(dual.high_gain.gain_dn_per_e==4 && dual.low_gain.gain_dn_per_e==0.1);
        assert(dual.high_gain.read_noise_e==1 && dual.low_gain.read_noise_e==5);
        assert(dual.high_gain.adc_bits==12 && dual.low_gain.adc_bits==12);
        assert(dual.high_gain.black_level_dn==64 && dual.low_gain.black_level_dn==64);
        assert(dual.merge.start_e==600 && dual.merge.end_e==900);
    end
end

function checkSummaryFrame(frame,expected,index,o)
    assert(frame.seed==8300+index && frame.exposure_s==0.01);
    assert(isequal(frame.image_size(:).',o.image_size));
    assert(strcmp(frame.readout_mode,o.mode) && strcmp(frame.input_stage,o.stage));
    near(frame.minimum_expected_e,min(expected(:)));
    near(frame.maximum_expected_e,max(expected(:)));
    near(frame.sum_expected_e,sum(expected(:)));
end

function o = fixtureOracle(name)
    % Closed-form spatial expectations. These do not call the production
    % PSF, overlap, CFA, integration, readout or merge implementations.
    p=6e-6; base=1e14;
    o=struct('full_size',[6 8],'roi',[1 1 6 8],'image_size',[6 8], ...
        'pattern','RGGB','mode','single','stage','pre_psf','step',p, ...
        'origin',[2 2],'kernel',[1 2 1;2 4 2;1 2 1]/16);
    o.xedges=(-1:9)*p; o.yedges=(-1:7)*p;
    o.optical_xedges=(0:8)*p; o.optical_yedges=(0:6)*p;
    switch name
        case 'identity_single'
            o.kernel=1; o.origin=[1 1];
            o.xedges=(0:8)*p; o.yedges=(0:6)*p;
            field=ramp(6,8); filtered=field; sampled=field;
        case 'flat_binomial'
            field=base*ones(8,10); filtered=base*ones(6,8); sampled=filtered;
        case 'shifted_impulse'
            o.full_size=[7 9]; o.roi=[1 1 7 9]; o.image_size=[7 9];
            o.origin=[1 2]; o.kernel=[0 0.25 0.25;0.125 0.25 0.125];
            o.xedges=(-1:10)*p; o.yedges=(-1:7)*p;
            o.optical_xedges=(0:9)*p; o.optical_yedges=(0:7)*p;
            field=zeros(8,11); field(4,5)=20*base;
            filtered=zeros(7,9); filtered(3:4,3:5)=20*base*o.kernel; sampled=filtered;
        case 'edge'
            field=base*repmat([0.2 0.2 0.2 0.2 0.2 1 1 1 1 1],8,1);
            filtered=base*repmat([0.2 0.2 0.2 0.4 0.8 1 1 1],6,1); sampled=filtered;
        case 'sinusoid'
            o.step=p/2; o.xedges=(-1:17)*o.step; o.yedges=(-1:13)*o.step;
            o.optical_xedges=(0:16)*o.step; o.optical_yedges=(0:12)*o.step;
            f=1/(8*p); z=f*o.step;
            source_aperture=sin(pi*z)/(pi*z);
            optical_transfer=0.5+0.5*cos(2*pi*z);
            source_x=((1:18)-1.5)*o.step;
            optical_x=((1:16)-0.5)*o.step;
            target_x=((1:8)-0.5)*p;
            field=base*repmat(1+0.4*source_aperture*sin(2*pi*f*source_x),14,1);
            filtered=base*repmat(1+0.4*source_aperture*optical_transfer*sin(2*pi*f*optical_x),12,1);
            % Averaging adjacent half-pixel cells contributes cos(pi*f*step).
            % Its product with source sinc(f*step) is sinc(f*pixel_pitch).
            aperture=sin(pi*f*p)/(pi*f*p);
            sampled=base*repmat(1+0.4*optical_transfer*aperture*sin(2*pi*f*target_x),6,1);
        case 'crop_cfa'
            o.full_size=[8 10]; o.roi=[2 2 5 7]; o.image_size=[5 7];
            o.pattern='BGGR'; o.stage='post_optics'; o.kernel=[]; o.origin=[];
            o.xedges=(0:10)*p; o.yedges=(0:8)*p;
            o.optical_xedges=o.xedges; o.optical_yedges=o.yedges;
            field=ramp(8,10); filtered=field; sampled=field(2:6,2:8);
        case 'dual_spatial'
            o.mode='dual';
            field=base*repmat(2+25*((1:10)-1.5)/8,8,1);
            filtered=base*repmat(2+25*((1:8)-0.5)/8,6,1); sampled=filtered;
        otherwise
            error('ALEV4:TestFixture','Unknown fixed demo fixture.');
    end
    o.input=cat(3,field,0.6*field);
    o.optical=cat(3,filtered,0.6*filtered);
    o.sampled=cat(3,sampled,0.6*sampled);
    o.expected=chargeOracle(o.sampled,o.roi(1:2));
end

function field = ramp(rows,columns)
    field=zeros(rows,columns);
    for r=1:rows
        for c=1:columns
            field(r,c)=1e14*(0.25+(c-0.5)/columns+0.5*(r-0.5)/rows);
        end
    end
end

function expected = chargeOracle(sampled,first)
    expected=zeros(size(sampled,1),size(sampled,2));
    tile=[1 2;2 3]; qe=[0.1 0.8 0.2;0.7 0.2 0.05];
    for r=1:size(sampled,1)
        for c=1:size(sampled,2)
            channel=tile(mod(r+first(1)-2,2)+1,mod(c+first(2)-2,2)+1);
            spectral=20*sampled(r,c,1)*qe(1,channel)+20*sampled(r,c,2)*qe(2,channel);
            expected(r,c)=spectral*0.01*(6e-6)^2*0.8;
        end
    end
end

function checkDual(directory,decoded,expected)
    high=readPlane(fullfile(directory,'readout.high.raw'),[6 8],'uint16');
    low=readPlane(fullfile(directory,'readout.low.raw'),[6 8],'uint16');
    merged=readPlane(fullfile(directory,'readout.merged.f64'),[6 8],'double');
    flags=readPlane(fullfile(directory,'readout.flags.u8'),[6 8],'uint8');
    assert(isequal(high,decoded.readout.high_gain.raw_dn));
    assert(isequal(low,decoded.readout.low_gain.raw_dn));
    assert(isequal(merged,decoded.readout.merged.electrons));
    assert(isequal(flags,decoded.readout.flags));
    high_e=(double(high)-64)/4; low_e=(double(low)-64)/0.1;
    high_usable=high>0 & high<4095; low_usable=low>0 & low<4095;
    assert(any(high_usable(:)) && any(high(:)==4095) && all(low_usable(:)));
    assert(~any(decoded.readout.full_well_saturated(:)) && all(decoded.readout.reconstruction_valid(:)));
    assert(~any(decoded.readout.high_gain.adc_low_clipped(:)));
    assert(~any(decoded.readout.low_gain.adc_low_clipped(:) | decoded.readout.low_gain.adc_high_clipped(:)));
    assert(any(decoded.readout.high_gain.adc_high_clipped(:)));
    assert(all(high(decoded.readout.high_gain.adc_high_clipped)==4095));
    independently_merged=zeros(6,8); weights=zeros(6,8);
    for r=1:6
        for c=1:8
            t=min(1,max(0,(low_e(r,c)-600)/300));
            w=1-3*t*t+2*t*t*t;
            if ~high_usable(r,c), w=0; elseif ~low_usable(r,c), w=1; end
            weights(r,c)=w;
            independently_merged(r,c)=w*high_e(r,c)+(1-w)*low_e(r,c);
        end
    end
    near(merged,independently_merged);
    near(decoded.readout.merged.weight_high,weights);
    assert(isequal(decoded.readout.merged.high_usable,high_usable));
    assert(isequal(decoded.readout.merged.low_usable,low_usable));
    expected_flags=4*uint8(decoded.readout.high_gain.adc_high_clipped)+ ...
        32*uint8(high_usable)+64*uint8(low_usable)+128*uint8(high_usable|low_usable);
    assert(isequal(flags,expected_flags));
    % A fixed 48-pixel noisy fixture is not a noise-distribution experiment.
    % Eight predicted RMS deviations plus half an ADC step are conservative
    % per-pixel sanity bounds; large-sample covariance gates live elsewhere.
    assert(all(abs(low_e(:)-expected(:))<=8*sqrt(expected(:)+25)+5));
    assert(all(abs(high_e(high_usable)-expected(high_usable))<= ...
        8*sqrt(expected(high_usable)+1)+0.125));
    assert(any(low(1,:)~=low(3,:)), ...
        'Equal-expectation rows must retain stochastic low-gain variation.');
    assert(numel(unique(high(2:2:6,2)))>1, ...
        'The unsaturated equal-expectation high-gain sites must retain noise.');
    quiet_low=uint16(floor(0.1*expected+64+0.5));
    assert(any(low(:)~=quiet_low(:)),'The noisy fixture was silently made deterministic.');
end

function testNoOverwrite(folder,primary,files)
    before=captureCaller();
    original=cell(size(files));
    for k=1:numel(files), original{k}=readBytes(fullfile(primary,files{k})); end
    for output={primary,[primary filesep],fullfile(primary,'.')}
        expectError(@() phase3_demo(output{1},false),'ALEV4:OutputExists');
    end
    for k=1:numel(files)
        assert(isequal(readBytes(fullfile(primary,files{k})),original{k}));
    end
    sentinel=uint8([0 80 72 65 83 69 51 255].');
    file=fullfile(folder,'existing-file'); writeBytes(file,sentinel);
    empty=fullfile(folder,'empty'); mkdir(empty);
    occupied=fullfile(folder,'occupied'); mkdir(occupied);
    writeBytes(fullfile(occupied,'keep.bin'),sentinel);
    for output={file,empty,occupied}
        expectError(@() phase3_demo(output{1},false),'ALEV4:OutputExists');
    end
    assert(isequal(readBytes(file),sentinel) && isempty(directoryNames(empty)));
    assert(isequal(directoryNames(occupied),{'keep.bin'}));
    assert(isequal(readBytes(fullfile(occupied,'keep.bin')),sentinel));
    expectError(@() phase3_demo(fullfile(file,'child'),false),'ALEV4:OutputDirectory');
    assert(isequal(readBytes(file),sentinel));
    requireCaller(before);
end

function testMalformed(folder)
    before=captureCaller();
    invalid_paths={[],7,true,struct(),{},'', ['a';'b'],['a' char(0) 'b'],{'path'}};
    for k=1:numel(invalid_paths)
        expectError(@() phase3_demo(invalid_paths{k},false),'ALEV4:InvalidOutputPath');
    end
    invalid_flags={0,1,NaN,[],[true false],'false',struct(),{false},1i};
    for k=1:numel(invalid_flags)
        output=fullfile(folder,sprintf('invalid-flag-%d',k));
        expectError(@() phase3_demo(output,invalid_flags{k}),'ALEV4:InvalidSetupMode');
        assert(exist(output,'file')==0 && exist(output,'dir')==0);
    end
    requireCaller(before);
end

function testFailedCompletion(folder,names)
    original_path=path;
    restore_path=onCleanup(@() path(original_path)); %#ok<NASGU>
    % Remove only the session-initializer path if upstream happens to be
    % enabled by a full runner. The same test also works under core setup.
    while exist('ieInitSession','file')==2
        implementation=which('ieInitSession');
        assert(~isempty(implementation));
        rmpath(fileparts(implementation));
        clear ieInitSession;
    end
    assert(exist('ieInitSession','file')~=2);
    before=captureCaller();
    output=fullfile(folder,'failed-full-demo');
    % Omitted include_iset must default to the required, truthful full gate.
    expectError(@() phase3_demo(output),'ALEV4:MissingISETCam');
    requireCaller(before);
    assert(isequal(directoryNames(output),sort(names)), ...
        'A late ISET failure must retain only its seven completed core bundles.');
    assert(exist(fullfile(output,'phase3-demo-summary.json'),'file')==0, ...
        'A failed required fixture published a completion summary.');
    assert(exist(fullfile(output,'iset_checker'),'file')==0);
    for k=1:numel(names)
        assert(isequal(directoryNames(fullfile(output,names{k})),bundleFiles(k)));
    end
    [last,meta]=alev4.readSpatialBundle(fullfile(output,'dual_spatial'));
    assert(strcmp(last.readout_mode,'dual') && meta.seed==8307);
    expectError(@() phase3_demo(output,false),'ALEV4:OutputExists');
    assert(exist(fullfile(output,'phase3-demo-summary.json'),'file')==0);
    requireCaller(before);
end

function files = bundleFiles(index)
    files={'input.f64','optical.f64','sampled.f64','expected.f64','readout.json','spatial.json'};
    if index~=6, files{end+1}='psf.f64'; end
    if index==7
        files=[files {'readout.high.raw','readout.low.raw','readout.merged.f64','readout.flags.u8'}];
    else
        files{end+1}='readout.raw';
    end
    files=sort(files);
end

function values = readPlane(filename,shape,type)
    shape(end+1:3)=1;
    [fid,message]=fopen(filename,'rb','ieee-le'); assert(fid>=0,message);
    close_file=onCleanup(@() fclose(fid)); %#ok<NASGU>
    [linear,count]=fread(fid,prod(shape),['*' type]);
    assert(count==prod(shape) && isempty(fread(fid,1,'*uint8')), ...
        'Payload byte length differs from the independently known fixture shape.');
    [~,error_number]=ferror(fid); assert(error_number==0,'Payload read failed.');
    values=zeros(shape,type);
    for band=1:shape(3)
        for row=1:shape(1)
            offset=((band-1)*shape(1)+(row-1))*shape(2);
            values(row,:,band)=linear(offset+(1:shape(2))).';
        end
    end
end

function near(actual,expected,ulps)
    if nargin<3, ulps=256; end
    assert(isequal(size(actual),size(expected)) && all(isfinite(actual(:))));
    scale=max(abs(expected(:)));
    if isempty(scale) || scale==0
        assert(isequal(actual,expected));
    else
        assert(all(abs(actual(:)-expected(:))<=ulps*eps(scale)), ...
            'Retained data disagree with the independent fixed-fixture expectation.');
    end
end

function expectError(callback,identifier)
    caught=false;
    try
        callback();
    catch err
        caught=true;
        assert(strcmp(err.identifier,identifier), ...
            ['Expected ' identifier ', received ' err.identifier ': ' err.message]);
    end
    assert(caught,['Expected rejection: ' identifier]);
end

function names = directoryNames(folder)
    entries=dir(folder);
    names=sort({entries.name}); names=names(~ismember(names,{'.','..'}));
end

function bytes = readBytes(filename)
    fid=fopen(filename,'rb'); assert(fid>=0,'Missing demo artifact.');
    close_file=onCleanup(@() fclose(fid)); %#ok<NASGU>
    bytes=fread(fid,Inf,'*uint8');
    [~,error_number]=ferror(fid); assert(error_number==0);
end

function writeBytes(filename,bytes)
    fid=fopen(filename,'wb'); assert(fid>=0,'Cannot create owned test fixture.');
    close_file=onCleanup(@() fclose(fid)); %#ok<NASGU>
    assert(fwrite(fid,bytes,'uint8')==numel(bytes));
end

function state = captureCaller()
    state=struct('rng',rng,'path',path,'directory',pwd,'handles',fopen('all'));
    globals=who('global'); state.had_session=any(strcmp(globals,'vcSESSION'));
    if state.had_session
        global vcSESSION;
        state.session=vcSESSION;
    else
        state.session=[];
    end
    state.had_preferences=ispref('ISET');
    if state.had_preferences, state.preferences=getpref('ISET');
    else, state.preferences=struct(); end
end

function requireCaller(expected)
    assert(isequal(captureCaller(),expected), ...
        'Demo execution changed caller RNG, path, directory, handles or ISET state.');
end

function restoreCaller(state)
    rng(state.rng); path(state.path);
    if ~strcmp(pwd,state.directory), cd(state.directory); end
    if state.had_session
        global vcSESSION;
        vcSESSION=state.session;
    else
        clear global vcSESSION;
    end
    current_had=ispref('ISET');
    if current_had, current=getpref('ISET'); else, current=struct(); end
    if current_had~=state.had_preferences || ~isequal(current,state.preferences)
        if current_had, rmpref('ISET'); end
        if state.had_preferences
            names=fieldnames(state.preferences);
            for k=1:numel(names), setpref('ISET',names{k},state.preferences.(names{k})); end
        end
    end
end

function removeOwnedFolder(folder)
    if exist(folder,'dir')==7, rmdir(folder,'s'); end
end
