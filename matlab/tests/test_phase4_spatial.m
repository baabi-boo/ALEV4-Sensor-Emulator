function report = test_phase4_spatial()
%TEST_PHASE4_SPATIAL Independent structured optics/geometry integration.
%   Scalar convolution, overlap, CFA, charge and signed electronics below
%   are independent of the production optics/integration/readout helpers.
    caller_rng=rng;
    guard=onCleanup(@()rng(caller_rng)); %#ok<NASGU>
    rng(832611,'twister'); rand(1,5); randn(1,7);
    [input,grid,geometry,single,dual,model,psf]=fixture();
    saved={input,grid,geometry,single,dual,model,psf};
    names={'disabled_single_dual_whole_result_identity_with_nontrivial_psf', ...
        'enabled_spatial_result_matches_core_on_sampled_input', ...
        'full_crop_fixed_maps_and_readouts_all_parities_and_cfas', ...
        'independent_multiband_optics_geometry_and_signed_noise_oracle', ...
        'wrong_cfa_blur_and_pre_well_electronics_controls', ...
        'post_optics_identity_nonuniform_sampling_and_duplicate_psf_rejection', ...
        'retained_spatial_baseline_is_unchanged_valid_legacy_context', ...
        'new_result_identity_exact_bundle_roundtrip_and_old_schema_rejection', ...
        'exact_coordinate_coverage_and_declared_psf_support', ...
        'strict_options_binding_and_rng_cleanup_after_legacy_baseline'};
    metrics=struct();
    metrics.disabled=disabledIdentity(input,grid,geometry,single,dual,model,psf);
    metrics.core_equality=coreEquality(input,grid,geometry,single,dual,model,psf);
    metrics.crops=cropIdentity();
    [metrics.analytical,example]=analyticalPipeline(input,grid,geometry,single,dual,model,psf);
    metrics.wrong_models=wrongStages();
    metrics.post_optics=postOptics(input,grid,geometry,dual,model,psf);
    metrics.legacy_baseline=retainedBaseline(input,grid,geometry,single,dual,model,psf);
    metrics.artifact_identity=artifactIdentity(example);
    metrics.support=exactSupport();
    metrics.cleanup=strictAndCleanup(input,grid,geometry,single,dual,model,psf);
    assert(isequal(saved,{input,grid,geometry,single,dual,model,psf}));
    metrics.runtime_version=version(); metrics.synthetic=true; metrics.calibrated_alev4=false;
    tests=repmat(struct('name','','status','passed','passed',true),1,numel(names));
    for k=1:numel(names), tests(k).name=names{k}; end
    report=struct('suite','phase4_spatial','status','passed','passed',true, ...
        'test_count',numel(names),'tests',tests,'metrics',metrics);
    fprintf('PASS: Phase 4 spatial integration, %d test groups.\n',numel(names));
end

function metrics=disabledIdentity(input,grid,g,single,dual,model,psf)
    model.enabled=false; single.shot_noise=true; dual.sensor.shot_noise=true;
    configs={single,dual}; options=struct('psf',psf); comparisons=0;
    for mode=1:2
        cfg=configs{mode};
        old=alev4.simulateSpatialExposure(input,grid,g,cfg,.125,4294967295,options);
        actual=alev4.simulateStructuredSpatialExposure(input,grid,g,cfg,.125,4294967295,model,options);
        assert(isequal(actual,old));
        assert(~isfield(actual,'format') && ~isfield(actual,'noise_model'));
        assert(any(old.readout.collected_electrons(:)~=old.readout.expected_electrons(:)));
        post_options=struct('input_stage','post_optics');
        old_post=alev4.simulateSpatialExposure(old.optical_irradiance,old.optical_grid,g,cfg,.125,9181,post_options);
        actual_post=alev4.simulateStructuredSpatialExposure(old.optical_irradiance,old.optical_grid,g,cfg,.125,9181,model,post_options);
        assert(isequal(actual_post,old_post)); comparisons=comparisons+2;
    end
    metrics=struct('whole_legacy_result_equalities',comparisons,'nontrivial_spectral_psf',true, ...
        'photo_and_pixel_noise_active',true,'input_stages',{{'pre_psf','post_optics'}});
end

function metrics=coreEquality(input,grid,g,single,dual,model,psf)
    configs={single,dual}; fields_checked=0;
    for mode=1:2
        cfg=configs{mode};
        spatial=alev4.simulateStructuredSpatialExposure(input,grid,g,cfg,.125,491,model,struct('psf',psf));
        core=alev4.simulateStructuredExposure(spatial.spatial_baseline.sampled_irradiance,cfg,.125,491,model,g);
        stripped=rmfield(spatial,{'spatial_baseline','spatial_baseline_role','spatial_operation_order'});
        stripped.result_kind='exposure';
        assert(isequal(stripped,core)); fields_checked=fields_checked+numel(fieldnames(core));
        expected_order=[{'optical_psf','area_overlap_average'},core.operation_order];
        assert(isequal(spatial.spatial_operation_order,expected_order));
        assert(isequal(spatial.input_irradiance,spatial.spatial_baseline.sampled_irradiance));
    end
    metrics=struct('complete_core_equalities',2,'compared_core_fields',fields_checked, ...
        'optics_and_sampling_precede_structured_operation_order',true);
end

function metrics=cropIdentity()
    p=.25; [r,c]=ndgrid(1:6,1:7);
    input=cat(3,8+4*r+2*c,32+2*r+8*c);
    model=alev4.createStructuredNoise([6 7],struct('prnu',.5+r/8+c/16, ...
        'dark_current_e_per_s',r+c/2,'dark_shot_noise',false, ...
        'shared',struct('fixed_offset_e',2*r-c), ...
        'single',struct('fixed_offset_e',r/4-c/2), ...
        'high_gain',struct('fixed_offset_e',r/2-c/4), ...
        'low_gain',struct('fixed_offset_e',-r+c/2)));
    patterns={'RGGB','GRBG','GBRG','BGGR'}; cases=0;
    for pattern=1:4
        g=alev4.createSensorGeometry(struct('full_grid_size',[6 7],'pixel_pitch_m',p, ...
            'origin_xy_m',[-.5 .125],'full_grid_cfa_pattern',patterns{pattern}));
        grid=alev4.createSpatialGrid(struct('x_edges_m',-.5+(0:7)*p,'y_edges_m',.125+(0:6)*p));
        [single,dual]=quietConfigurations(g);
        for mode=1:2
            configs={single,dual}; cfg=configs{mode};
            full=alev4.simulateStructuredSpatialExposure(input,grid,g,cfg,.5,671,model,struct('input_stage','post_optics'));
            for first_r=1:2
                for first_c=1:2
                    crop_g=g; crop_g.active_roi=[first_r first_c 3 4];
                    crop_cfg=alev4.bindSensorGeometry(cfg,crop_g,'derive');
                    crop=alev4.simulateStructuredSpatialExposure(input,grid,crop_g,crop_cfg,.5,671,model,struct('input_stage','post_optics'));
                    rows=first_r:first_r+2; columns=first_c:first_c+3;
                    for field={'prnu','dark_current_e_per_s'}
                        f=field{1}; assert(isequal(crop.active_maps.(f),model.(f)(rows,columns)));
                    end
                    for path={'shared','single','high_gain','low_gain'}
                        name=path{1};
                        assert(isequal(crop.active_maps.(name).fixed_offset_e,model.(name).fixed_offset_e(rows,columns)));
                    end
                    assert(isequal(crop.noise_model,full.noise_model));
                    assert(isequal(crop.input_irradiance,input(rows,columns,:)));
                    assert(isequal(crop.baseline_expected_electrons,full.baseline_expected_electrons(rows,columns)));
                    for field={'expected_photoelectrons','expected_dark_electrons','collected_electrons','charge_electrons'}
                        f=field{1}; assert(isequal(crop.readout.(f),full.readout.(f)(rows,columns)));
                    end
                    paths={'single'}; if mode==2, paths={'high_gain','low_gain'}; end
                    for j=1:numel(paths)
                        if mode==1, a=crop.readout; b=full.readout;
                        else, a=crop.readout.(paths{j}); b=full.readout.(paths{j}); end
                        assert(isequal(a.read_electrons,b.read_electrons(rows,columns)));
                        assert(isequal(a.raw_dn,b.raw_dn(rows,columns)));
                    end
                    if mode==1, active_pattern=crop.configuration.cfa_pattern;
                    else, active_pattern=crop.configuration.sensor.cfa_pattern; end
                    expected_pattern='';
                    for rr=first_r:first_r+1
                        for cc=first_c:first_c+1
                            colors='RGB'; expected_pattern(end+1)=colors(absoluteChannel(rr,cc,patterns{pattern})); %#ok<AGROW>
                        end
                    end
                    assert(strcmp(active_pattern,expected_pattern)); cases=cases+1;
                end
            end
        end
    end
    metrics=struct('full_crop_cases',cases,'full_grid_cfa_patterns',{patterns}, ...
        'start_row_parities',[1 2],'start_column_parities',[1 2], ...
        'fixed_map_identity_and_deterministic_readouts_exact',true);
end

function [metrics,example]=analyticalPipeline(input,grid,g,single,dual,model,psf)
    exposure=.125; seed=4294967281; configs={single,dual}; maximum_error=0;
    for mode=1:2
        cfg=configs{mode}; sensor=cfg; if mode==2, sensor=cfg.sensor; end
        result=alev4.simulateStructuredSpatialExposure(input,grid,g,cfg,exposure,seed,model,struct('psf',psf));
        [optical,sampled,baseline,incident]=scalarPipeline(input,grid,g,sensor,psf,exposure);
        near(result.spatial_baseline.optical_irradiance,optical,256);
        near(result.input_irradiance,sampled,256);
        near(result.baseline_expected_electrons,baseline,256);
        near(result.readout.expected_incident_photons,incident,256);
        roi=g.active_roi; rows=roi(1):roi(1)+roi(3)-1; columns=roi(2):roi(2)+roi(4)-1;
        photo=model.prnu(rows,columns).*baseline;
        dark=model.dark_current_e_per_s(rows,columns)*exposure;
        collected=photo+dark; stored=min(collected,sensor.full_well_e);
        near(result.components.photo_electrons,photo,256); near(result.components.dark_electrons,dark,256);
        near(result.readout.collected_electrons,collected,256);
        near(result.readout.charge_electrons,stored,256);
        assert(isequal(result.readout.full_well_saturated,collected>=sensor.full_well_e));
        shared=electronicOracle(model.shared,rows,columns,0,seed,[10 11 12 0]);
        near(result.components.shared.total_e,shared,256);
        if mode==1
            paths={'single'}; tags={[20 21 22 23]};
        else
            paths={'high_gain','low_gain'}; tags={[30 31 32 33],[40 41 42 43]};
        end
        for j=1:numel(paths)
            name=paths{j}; pathcfg=cfg; observed=result.readout;
            if mode==2, pathcfg=cfg.(name); observed=result.readout.(name); end
            path=electronicOracle(model.(name),rows,columns,pathcfg.read_noise_e,seed,tags{j});
            expected=(stored+shared)+path;
            near(result.components.(name).total_e,path,256);
            near(observed.read_electrons,expected,256);
            assert(isequal(observed.raw_dn,adcOracle(expected,pathcfg)));
            maximum_error=max(maximum_error,max(abs(observed.read_electrons(:)-expected(:))));
        end
        assert(any(result.readout.full_well_saturated(:)));
        assert(any(photo(:)==0) && any(photo(:)>0));
        if mode==2
            assert(any(result.readout.high_gain.read_electrons(:)<0));
            assert(~isequal(result.readout.high_gain.read_electrons,result.readout.low_gain.read_electrons));
            example=result;
        end
    end
    metrics=struct('spectral_planes',2,'psf_shape',[2 3 2],'active_shape',g.active_roi(3:4), ...
        'pixel_pitch_to_cell_spacing',g.pixel_pitch_m/psf.spacing_yx_m(1), ...
        'readout_paths_checked',3,'maximum_signed_electron_error',maximum_error, ...
        'independent_gaussian_seed_oracle',true,'area_fill_exposure_qe_and_width_once',true);
end

function metrics=wrongStages()
    p=.5; g=alev4.createSensorGeometry(struct('full_grid_size',[4 4],'pixel_pitch_m',p));
    grid=alev4.createSpatialGrid(struct('x_edges_m',(-1:5)*p,'y_edges_m',(-1:5)*p));
    [cfg,~]=quietConfigurations(g); cfg.qe=[1 .125 .0625;.0625 .25 1];
    cfg.full_well_e=1000;
    input=cat(3,32*ones(6),64*ones(6));
    kernel=[1 2 1;2 4 2;1 2 1]/16;
    psf=alev4.createOpticalPsf(struct('kernel',kernel,'origin_rc',[2 2],'spacing_yx_m',[p p]));
    model=alev4.createStructuredNoise([4 4],struct('dark_shot_noise',false));
    actual=alev4.simulateStructuredSpatialExposure(input,grid,g,cfg,1,101,model,struct('psf',psf));
    mosaic=zeros(6);
    for r=1:6
        for c=1:6
            channel=absoluteChannel(r-1,c-1,'RGGB');
            for b=1:2
                mosaic(r,c)=mosaic(r,c)+input(r,c,b)*cfg.qe(b,channel)*cfg.bin_width_nm(b);
            end
        end
    end
    wrong=zeros(4);
    for r=1:4
        for c=1:4
            for a=1:3
                for b=1:3, wrong(r,c)=wrong(r,c)+kernel(a,b)*mosaic(r+3-a,c+3-b); end
            end
        end
    end
    wrong=wrong*p^2*cfg.fill_factor;
    spectral_gap=max(abs(wrong(:)-actual.baseline_expected_electrons(:)));
    assert(spectral_gap>.2*max(actual.baseline_expected_electrons(:)), ...
        'Post-CFA blur must fail the independent spectral-order oracle.');
    % A separate two-pixel case distinguishes signed readout from placing
    % offsets before the physical well, at both the zero and saturated ends.
    g2=alev4.createSensorGeometry(struct('full_grid_size',[1 2],'pixel_pitch_m',1));
    grid2=alev4.createSpatialGrid(struct('x_edges_m',[0 1 2],'y_edges_m',[0 1]));
    cfg2=alev4.createBaselineSensor(struct('image_size',[1 2],'pixel_pitch_m',1, ...
        'wavelength_nm',550,'bin_width_nm',1,'qe',[1 1 1],'fill_factor',1, ...
        'full_well_e',10,'shot_noise',false,'read_noise_e',0));
    model2=alev4.createStructuredNoise([1 2],struct('dark_shot_noise',false, ...
        'shared',struct('fixed_offset_e',[-3 2]),'single',struct('fixed_offset_e',[-1 4])));
    r2=alev4.simulateStructuredSpatialExposure([0 30],grid2,g2,cfg2,1,102,model2,struct('input_stage','post_optics'));
    assert(isequal(r2.readout.charge_electrons,[0 10]) && isequal(r2.readout.read_electrons,[-4 16]));
    prewell=min(max([0 30]+[-3 2]+[-1 4],0),10);
    electronic_gap=max(abs(prewell-r2.readout.read_electrons));
    assert(electronic_gap==6);
    metrics=struct('post_cfa_blur_maximum_gap_e',spectral_gap, ...
        'pre_well_electronics_maximum_gap_e',electronic_gap,'wrong_models_rejected',2);
end

function metrics=postOptics(input,grid,g,cfg,model,psf)
    pre=alev4.simulateStructuredSpatialExposure(input,grid,g,cfg,.125,621,model,struct('psf',psf));
    baseline=pre.spatial_baseline; options=struct('input_stage','post_optics');
    post=alev4.simulateStructuredSpatialExposure(baseline.optical_irradiance,baseline.optical_grid,g,cfg,.125,621,model,options);
    assert(isequal(pre.readout,post.readout) && isequal(pre.components,post.components));
    assert(isequal(pre.input_irradiance,post.input_irradiance));
    assert(isequal(post.spatial_baseline.psf,[]));
    assert(isequal(post.spatial_baseline.optical_irradiance,baseline.optical_irradiance));
    assert(isequal(post.spatial_operation_order,[{'area_overlap_average'},post.operation_order]));
    rejected=0;
    for enabled=[true false]
        selected=model; selected.enabled=enabled;
        expectError(@() alev4.simulateStructuredSpatialExposure(baseline.optical_irradiance, ...
            baseline.optical_grid,g,cfg,.125,621,selected,struct('input_stage','post_optics','psf',psf)), ...
            'ALEV4:DuplicateOptics'); rejected=rejected+1;
    end
    nonuniform=alev4.createSpatialGrid(struct('x_edges_m',[0 .25 1],'y_edges_m',[0 .75 1]));
    one_g=alev4.createSensorGeometry(struct('full_grid_size',[1 1],'pixel_pitch_m',1));
    one=alev4.createBaselineSensor(struct('image_size',[1 1],'pixel_pitch_m',1, ...
        'wavelength_nm',550,'bin_width_nm',4,'qe',[1 1 1],'fill_factor',.5, ...
        'full_well_e',25,'shot_noise',false,'read_noise_e',0));
    one_model=alev4.createStructuredNoise([1 1],struct('prnu',2,'dark_current_e_per_s',3, ...
        'dark_shot_noise',false,'shared',struct('fixed_offset_e',-4),'single',struct('fixed_offset_e',1)));
    sampled=alev4.simulateStructuredSpatialExposure([1 2;3 4],nonuniform,one_g,one,2,3,one_model,options);
    assert(sampled.input_irradiance==2.25 && sampled.baseline_expected_electrons==9);
    assert(sampled.readout.expected_photoelectrons==18 && sampled.readout.expected_dark_electrons==6);
    assert(sampled.readout.read_electrons==21);
    expectError(@() alev4.simulateStructuredSpatialExposure([1 2;3 4],nonuniform,one_g,one,2,3,one_model), ...
        'ALEV4:OpticalGridMismatch'); rejected=rejected+1;
    metrics=struct('pre_post_complete_readout_and_component_identity',true, ...
        'nonuniform_sampled_density',2.25,'independent_signed_electrons',21,'rejected_calls',rejected);
end

function metrics=retainedBaseline(input,grid,g,single,dual,model,psf)
    configs={single,dual}; comparisons=0;
    for mode=1:2
        cfg=configs{mode};
        if mode==1, cfg.shot_noise=true; else, cfg.sensor.shot_noise=true; end
        options=struct('psf',psf,'spatial_provenance',struct('source','independent_test','classification','assumed'));
        legacy=alev4.simulateSpatialExposure(input,grid,g,cfg,.125,153,options);
        result=alev4.simulateStructuredSpatialExposure(input,grid,g,cfg,.125,153,model,options);
        assert(isequal(result.spatial_baseline,legacy));
        validated=alev4.spatialValidateResult(result.spatial_baseline,true);
        assert(isequal(validated,legacy));
        assert(strcmp(result.spatial_baseline_role,'verification_context_only'));
        assert(isequal(result.readout.collected_electrons, ...
            result.components.photo_electrons+result.components.dark_electrons));
        doubled=result.readout.collected_electrons+legacy.readout.collected_electrons;
        assert(any(doubled(:)~=result.readout.collected_electrons(:)));
        comparisons=comparisons+1;
    end
    metrics=struct('whole_legacy_baselines_and_replays',comparisons, ...
        'baseline_charge_excluded_from_structured_exposure',true);
end

function metrics=artifactIdentity(result)
    before=rng;
    checked=alev4.structuredValidateResult(result); assert(isequal(checked,result));
    assert(strcmp(result.format,'ALEV4-SYNTHETIC-STRUCTURED-NOISE') && strcmp(result.result_kind,'spatial_exposure'));
    expectError(@() alev4.spatialValidateResult(result,true),'ALEV4:InvalidSpatialResult');
    parent=tempname(); [ok,message]=mkdir(parent); assert(ok && isempty(message));
    cleanup=onCleanup(@()removeTemporary(parent)); %#ok<NASGU>
    old_path=fullfile(parent,'wrong_legacy_schema');
    expectError(@() alev4.exportSpatialBundle(old_path,result),'ALEV4:InvalidSpatialResult');
    assert(~exist(old_path,'dir') && ~exist(old_path,'file'));
    path=fullfile(parent,'structured_multiband_crop');
    files=alev4.exportStructuredBundle(result,path);
    [decoded,metadata]=alev4.readStructuredBundle(path);
    assert(isequal(decoded,result));
    assert(isequal(decoded.spatial_baseline,result.spatial_baseline));
    assert(strcmp(metadata.format,'ALEV4-SYNTHETIC-STRUCTURED-NOISE'));
    assert(isequal(decoded.geometry.origin_xy_m,result.geometry.origin_xy_m));
    assert(isequal(decoded.spatial_baseline.input_grid,result.spatial_baseline.input_grid));
    assert(isequal(decoded.spatial_baseline.psf.kernel,result.spatial_baseline.psf.kernel));
    payload=dir(files.payload); assert(numel(payload)==1 && payload.bytes>0);
    assert(isequal(before,rng));
    metrics=struct('exact_complete_native_roundtrips',1,'payload_bytes',payload.bytes, ...
        'spectral_psf_crop_coordinates_and_signed_components_preserved',true, ...
        'old_schema_validator_and_exporter_rejections',2);
end

function metrics=exactSupport()
    p=6.075e-6;
    g=alev4.createSensorGeometry(struct('full_grid_size',[3 4],'active_roi',[2 3 1 1], ...
        'pixel_pitch_m',p,'origin_xy_m',[.7e-6 -1.1e-6]));
    grid=alev4.createSpatialGrid(struct('x_edges_m',g.origin_xy_m(1)+[2 3]*p, ...
        'y_edges_m',g.origin_xy_m(2)+[1 2]*p));
    cfg=alev4.createBaselineSensor(struct('image_size',[1 1],'pixel_pitch_m',p, ...
        'wavelength_nm',550,'bin_width_nm',1,'qe',[1 1 1],'fill_factor',1, ...
        'shot_noise',false,'read_noise_e',0));
    cfg=alev4.bindSensorGeometry(cfg,g,'derive');
    model=alev4.createStructuredNoise([3 4],struct('dark_shot_noise',false));
    options=struct('input_stage','post_optics');
    exact=alev4.simulateStructuredSpatialExposure(123,grid,g,cfg,1,17,model,options);
    assert(exact.input_irradiance==123 && exact.spatial_baseline.sampling_report.identity);
    for edge=1:4
        bad=grid;
        if edge==1, bad.x_edges_m(1)=bad.x_edges_m(1)+eps(abs(bad.x_edges_m(1)));
        elseif edge==2, bad.x_edges_m(end)=bad.x_edges_m(end)-eps(abs(bad.x_edges_m(end)));
        elseif edge==3, bad.y_edges_m(1)=bad.y_edges_m(1)+eps(abs(bad.y_edges_m(1)));
        else, bad.y_edges_m(end)=bad.y_edges_m(end)-eps(abs(bad.y_edges_m(end))); end
        expectError(@() alev4.simulateStructuredSpatialExposure(123,bad,g,cfg,1,17,model,options), ...
            'ALEV4:SpatialCoverage');
    end
    expanded=grid;
    expanded.x_edges_m=grid.x_edges_m+[-eps(abs(grid.x_edges_m(1))) eps(abs(grid.x_edges_m(end)))];
    expanded.y_edges_m=grid.y_edges_m+[-eps(abs(grid.y_edges_m(1))) eps(abs(grid.y_edges_m(end)))];
    wider=alev4.simulateStructuredSpatialExposure(123,expanded,g,cfg,1,17,model,options);
    near(wider.input_irradiance,123,16);
    assert(isequal(wider.spatial_baseline.input_grid,expanded));
    assert(~wider.spatial_baseline.sampling_report.identity);
    % Zero-valued border coefficients still declare finite PSF support.
    g2=alev4.createSensorGeometry(struct('full_grid_size',[3 4],'pixel_pitch_m',.5));
    grid2=alev4.createSpatialGrid(struct('x_edges_m',(0:4)*.5,'y_edges_m',(0:3)*.5));
    cfg2=alev4.bindSensorGeometry(cfg,g2,'derive'); model2=alev4.createStructuredNoise([3 4]);
    kernel=zeros(3); kernel(2,2)=1;
    psf=alev4.createOpticalPsf(struct('kernel',kernel,'origin_rc',[2 2],'spacing_yx_m',[.5 .5]));
    expectError(@() alev4.simulateStructuredSpatialExposure(ones(3,4),grid2,g2,cfg2,1,18,model2,struct('psf',psf)), ...
        'ALEV4:SpatialCoverage');
    identity=alev4.simulateStructuredSpatialExposure(ones(3,4),grid2,g2,cfg2,1,18,model2);
    assert(isequal(identity.input_irradiance,ones(3,4)));
    metrics=struct('one_ulp_boundary_shortages_rejected',4, ...
        'expanded_coordinates_retained_exactly',true,'zero_border_psf_support_rejected',true, ...
        'physical_pitch_m',p);
end

function metrics=strictAndCleanup(input,grid,g,single,dual,model,psf)
    options=struct('psf',psf); saved={input,grid,g,single,dual,model,psf,options}; before=rng;
    malformed={[],{},struct([]),struct('unknown',1),struct('input_stage','rgb'), ...
        struct('input_stage',true),struct('spatial_provenance',[]),struct('psf',builtin('single',[])), ...
        struct('psf',false(0,0)),struct('psf',zeros(0,2))};
    count=0;
    for k=1:numel(malformed)
        expectError(@() alev4.simulateStructuredSpatialExposure(input,grid,g,single,.125,37,model,malformed{k}), ...
            'ALEV4:InvalidSpatialOptions'); count=count+1;
    end
    bad=single; bad.image_size=[5 5];
    expectError(@() alev4.simulateStructuredSpatialExposure(input,grid,g,bad,.125,37,model,options), ...
        'ALEV4:GeometryBindingConflict'); count=count+1;
    derived=alev4.simulateStructuredSpatialExposure(input,grid,g,bad,.125,37,model, ...
        struct('psf',psf,'binding_mode','derive'));
    assert(isequal(derived.configuration,single));
    expectError(@() alev4.simulateStructuredSpatialExposure(input,grid,g,single,.125,37,model, ...
        struct('binding_mode','guess')),'ALEV4:InvalidGeometryBinding'); count=count+1;
    bad_model=model; bad_model.full_grid_size=[3 5];
    expectError(@() alev4.simulateStructuredSpatialExposure(input,grid,g,single,.125,37,bad_model,options), ...
        'ALEV4:StructuredNoiseGridMismatch'); count=count+1;
    bad_grid=grid; bad_grid.sample_semantics='point_samples';
    expectError(@() alev4.simulateStructuredSpatialExposure(input,bad_grid,g,single,.125,37,model,options), ...
        'ALEV4:InvalidSpatialGrid'); count=count+1;
    expectError(@() alev4.simulateStructuredSpatialExposure(input(:,:,1),grid,g,single,.125,37,model,options), ...
        'ALEV4:SpatialSpectralMismatch'); count=count+1;
    bad_psf=psf; bad_psf.wavelength_nm=flipud(psf.wavelength_nm);
    expectError(@() alev4.simulateStructuredSpatialExposure(input,grid,g,single,.125,37,model,struct('psf',bad_psf)), ...
        'ALEV4:OpticalSpectralMapping'); count=count+1;
    shifted_psf=psf; shifted_psf.wavelength_nm=psf.wavelength_nm+1;
    expectError(@() alev4.simulateStructuredSpatialExposure(input,grid,g,single,.125,37,model,struct('psf',shifted_psf)), ...
        'ALEV4:OpticalSpectralMapping'); count=count+1;
    expectError(@() alev4.simulateStructuredSpatialExposure(input,grid,g,single,-1,37,model,options), ...
        'ALEV4:InvalidExposure'); count=count+1;
    expectError(@() alev4.simulateStructuredSpatialExposure(input,grid,g,single,.125,NaN,model,options), ...
        'ALEV4:InvalidSeed'); count=count+1;
    late=model; late.shared.fixed_offset_e=realmax; late.high_gain.fixed_offset_e=realmax;
    baseline=alev4.simulateSpatialExposure(input,grid,g,dual,.125,37,options);
    assert(any(baseline.readout.high_gain.read_electrons(:)~=baseline.readout.charge_electrons(:)));
    expectError(@() alev4.simulateStructuredSpatialExposure(input,grid,g,dual,.125,37,late,options), ...
        'ALEV4:StructuredNoiseOverflow'); count=count+1;
    assert(isequal(before,rng) && isequal(saved,{input,grid,g,single,dual,model,psf,options}));
    metrics=struct('rejected_calls',count,'explicit_derive_preserves_caller_config',true, ...
        'legacy_baseline_proved_successful_before_structured_failure',true, ...
        'rng_and_caller_values_preserved',true);
end

function [input,grid,g,single,dual,model,psf]=fixture()
    d=2^-20; [r,c]=ndgrid(1:12,1:14);
    input=cat(3,(3+mod(7*r+5*c,17))*2^41,(5+mod(2*r+11*c,23))*2^40);
    grid=alev4.createSpatialGrid(struct('x_edges_m',(-2:12)*d,'y_edges_m',(-2:10)*d));
    g=alev4.createSensorGeometry(struct('full_grid_size',[3 4],'active_roi',[2 2 2 3], ...
        'pixel_pitch_m',2.5*d,'origin_xy_m',[.25*d .125*d],'full_grid_cfa_pattern','GRBG'));
    sensor=struct('wavelength_nm',[470;650],'bin_width_nm',[3;5], ...
        'qe',[.75 .25 .125;.0625 .5 .875],'fill_factor',.375,'full_well_e',20,'shot_noise',false);
    single=alev4.createBaselineSensor(sensor); single=alev4.bindSensorGeometry(single,g,'derive');
    single.read_noise_e=.5; single.gain_dn_per_e=2; single.black_level_dn=8; single.adc_bits=10;
    dual=alev4.createDualGainSensor(struct('sensor',sensor, ...
        'high_gain',struct('gain_dn_per_e',4,'read_noise_e',.5,'black_level_dn',8,'adc_bits',10), ...
        'low_gain',struct('gain_dn_per_e',.5,'read_noise_e',.875,'black_level_dn',16,'adc_bits',10), ...
        'merge',struct('start_e',4,'end_e',8)));
    dual=alev4.bindSensorGeometry(dual,g,'derive');
    [r,c]=ndgrid(1:3,1:4); prnu=1+r/8-c/16; prnu(2,2)=0;
    shared=2*r-3*c; shared(2,2)=-6;
    model=alev4.createStructuredNoise([3 4],struct('realization_id','ASSUMED-P4-SPATIAL-TEST', ...
        'prnu',prnu,'dark_current_e_per_s',2+r+c/2,'dark_shot_noise',false, ...
        'shared',struct('fixed_offset_e',shared,'row_noise_e',.75,'column_noise_e',.5,'frame_noise_e',1), ...
        'single',struct('fixed_offset_e',r/2-c,'row_noise_e',.5,'column_noise_e',.25,'frame_noise_e',.375), ...
        'high_gain',struct('fixed_offset_e',r/2-c,'row_noise_e',.5,'column_noise_e',.25,'frame_noise_e',.375), ...
        'low_gain',struct('fixed_offset_e',-r+c/4,'row_noise_e',.25,'column_noise_e',.75,'frame_noise_e',.5)));
    kernels=cat(3,[1 2 3;4 5 1]/16,[4 1 2;2 3 4]/16);
    psf=alev4.createOpticalPsf(struct('kernel',kernels,'origin_rc',[1 2], ...
        'spacing_yx_m',[d d],'wavelength_nm',[470;650]));
end

function [single,dual]=quietConfigurations(g)
    sensor=struct('wavelength_nm',[470;650],'bin_width_nm',[3;5], ...
        'qe',[.75 .25 .125;.0625 .5 .875],'fill_factor',.5,'full_well_e',1000,'shot_noise',false);
    single=alev4.createBaselineSensor(sensor); single.read_noise_e=0;
    single=alev4.bindSensorGeometry(single,g,'derive');
    dual=alev4.createDualGainSensor(struct('sensor',sensor, ...
        'high_gain',struct('read_noise_e',0),'low_gain',struct('read_noise_e',0), ...
        'merge',struct('start_e',100,'end_e',200)));
    dual=alev4.bindSensorGeometry(dual,g,'derive');
end

function [optical,sampled,expected,incident]=scalarPipeline(input,grid,g,cfg,psf,exposure)
    kh=size(psf.kernel,1); kw=size(psf.kernel,2);
    oh=size(input,1)-kh+1; ow=size(input,2)-kw+1; bands=size(input,3);
    optical=zeros(oh,ow,bands);
    for k=1:bands
        for r=1:oh
            for c=1:ow
                for a=1:kh
                    for b=1:kw
                        optical(r,c,k)=optical(r,c,k)+psf.kernel(a,b,k)*input(r+kh-a,c+kw-b,k);
                    end
                end
            end
        end
    end
    first=[kh kw]-psf.origin_rc+1;
    xe=grid.x_edges_m(first(2):first(2)+ow); ye=grid.y_edges_m(first(1):first(1)+oh);
    roi=g.active_roi; p=g.pixel_pitch_m;
    sampled=zeros(roi(3),roi(4),bands); expected=zeros(roi(3:4)); incident=expected;
    for r=1:roi(3)
        fr=roi(1)+r-1; y0=g.origin_xy_m(2)+(fr-1)*p; y1=g.origin_xy_m(2)+fr*p;
        for c=1:roi(4)
            fc=roi(2)+c-1; x0=g.origin_xy_m(1)+(fc-1)*p; x1=g.origin_xy_m(1)+fc*p;
            channel=absoluteChannel(fr,fc,g.full_grid_cfa_pattern);
            for k=1:bands
                integral=0;
                for a=1:oh
                    height=max(0,min(ye(a+1),y1)-max(ye(a),y0));
                    for b=1:ow
                        width=max(0,min(xe(b+1),x1)-max(xe(b),x0));
                        integral=integral+optical(a,b,k)*height*width;
                    end
                end
                sampled(r,c,k)=integral/((x1-x0)*(y1-y0));
                incident(r,c)=incident(r,c)+sampled(r,c,k)*cfg.bin_width_nm(k);
                expected(r,c)=expected(r,c)+sampled(r,c,k)*cfg.qe(k,channel)*cfg.bin_width_nm(k);
            end
        end
    end
    expected=expected*(exposure*p^2*cfg.fill_factor); incident=incident*(exposure*p^2*cfg.fill_factor);
end

function value=electronicOracle(component,rows,columns,pixel_sigma,frame_seed,tags)
    fixed=component.fixed_offset_e; if isscalar(fixed), fixed=repmat(fixed,numel(rows),numel(columns));
    else, fixed=fixed(rows,columns); end
    row=gaussianOracle(component.row_noise_e,[numel(rows) 1],mod(frame_seed+tags(1),2^32));
    column=gaussianOracle(component.column_noise_e,[1 numel(columns)],mod(frame_seed+tags(2),2^32));
    frame=gaussianOracle(component.frame_noise_e,[1 1],mod(frame_seed+tags(3),2^32));
    pixel=gaussianOracle(pixel_sigma,[numel(rows) numel(columns)],mod(frame_seed+tags(4),2^32));
    value=bsxfun(@plus,fixed,row); value=bsxfun(@plus,value,column); value=value+frame; value=value+pixel;
end

function value=gaussianOracle(sigma,dimensions,seed)
    if sigma==0, value=zeros(dimensions); return; end
    previous=rng; guard=onCleanup(@()rng(previous)); %#ok<NASGU>
    rng(seed,'twister'); value=sigma*randn(dimensions);
end

function raw=adcOracle(electrons,cfg)
    analog=electrons*cfg.gain_dn_per_e+cfg.black_level_dn;
    rounded=sign(analog).*floor(abs(analog)+.5);
    raw=uint16(min(max(rounded,0),2^cfg.adc_bits-1));
end

function channel=absoluteChannel(row,column,pattern)
    switch pattern
        case 'RGGB', red=[1 1]; blue=[0 0];
        case 'GRBG', red=[1 0]; blue=[0 1];
        case 'GBRG', red=[0 1]; blue=[1 0];
        case 'BGGR', red=[0 0]; blue=[1 1];
        otherwise, error('Invalid oracle Bayer pattern.');
    end
    channel=2;
    if mod(row,2)==red(1) && mod(column,2)==red(2), channel=1; end
    if mod(row,2)==blue(1) && mod(column,2)==blue(2), channel=3; end
end

function near(actual,expected,multiplier)
    assert(isequal(size(actual),size(expected)));
    scale=max(1,max(abs(expected(:))));
    assert(max(abs(actual(:)-expected(:)))<=multiplier*eps(scale),'Independent spatial oracle mismatch.');
end

function expectError(action,identifier)
    before=rng; caught=false;
    try, action(); catch err
        caught=true;
        assert(strcmp(err.identifier,identifier),'Expected %s, received %s: %s',identifier,err.identifier,err.message);
    end
    assert(caught,'Expected rejection %s.',identifier);
    assert(isequal(before,rng),'A rejected spatial call changed caller RNG.');
end

function removeTemporary(path)
    if exist(path,'dir'), rmdir(path,'s'); end
end
