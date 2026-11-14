function summary = phase3_demo(output_dir, include_iset)
%PHASE3_DEMO Retain eight small spatial fixtures and unchanged readout payloads.
%   Call setup_project(true) first for complete execution. include_iset=false
%   produces seven development fixtures and explicitly leaves demo_complete
%   false. Existing destinations are never overwritten. All data are synthetic.
    if nargin < 1
        output_dir = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), ...
            'outputs','phase3','demo');
    end
    if nargin < 2, include_iset = true; end
    if ~islogical(include_iset) || ~isscalar(include_iset)
        error('ALEV4:InvalidSetupMode','include_iset must be a logical scalar.');
    end
    if ~ischar(output_dir) || isempty(output_dir) || ~isrow(output_dir) || any(output_dir==char(0))
        error('ALEV4:InvalidOutputPath','Output must be a nonempty character path.');
    end
    if alev4.bundlePathExists(output_dir)
        error('ALEV4:OutputExists','Phase 3 demo refuses an existing output path.');
    end
    [ok,message] = mkdir(output_dir);
    if ~ok, error('ALEV4:OutputDirectory','%s',message); end
    caller_rng = rng;
    guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    names = {'identity_single','flat_binomial','shifted_impulse','edge', ...
        'sinusoid','crop_cfa','dual_spatial'};
    if include_iset, names{end+1} = 'iset_checker'; end
    frames = repmat(struct('name','','readout_mode','','input_stage','', ...
        'image_size',[], 'seed',0,'exposure_s',0,'minimum_expected_e',0, ...
        'maximum_expected_e',0,'sum_expected_e',0),1,numel(names));
    for k = 1:numel(names)
        name = names{k};
        if strcmp(name,'iset_checker')
            spatial = alev4.isetSpatialFixture('checker',8308,1e-3);
        else
            spatial = fixture(name,8300+k);
        end
        alev4.exportSpatialBundle(fullfile(output_dir,name),spatial);
        electrons = spatial.readout.expected_electrons;
        frames(k) = struct('name',name,'readout_mode',spatial.readout_mode, ...
            'input_stage',spatial.input_stage,'image_size',size(electrons), ...
            'seed',spatial.readout.seed,'exposure_s',spatial.readout.exposure_s, ...
            'minimum_expected_e',min(electrons(:)), ...
            'maximum_expected_e',max(electrons(:)),'sum_expected_e',sum(electrons(:)));
    end
    if exist('OCTAVE_VERSION','builtin'), runtime = 'GNU Octave'; else, runtime = 'MATLAB'; end
    summary = struct('schema_version','1.0','phase',3,'synthetic',true, ...
        'calibrated_alev4',false,'demo_complete',include_iset, ...
        'iset_included',include_iset,'frame_count',numel(names),'frames',frames, ...
        'runtime',struct('name',runtime,'version',version), ...
        'provenance',alev4.sourceProvenance());
    bytes = unicode2native(jsonencode(summary),'UTF-8');
    destination = fullfile(output_dir,'phase3-demo-summary.json');
    fid = fopen(destination,'wb');
    if fid < 0, error('ALEV4:ReportWrite','Cannot write Phase 3 demo summary.'); end
    cleanup = onCleanup(@() closeQuietly(fid)); %#ok<NASGU>
    count = fwrite(fid,bytes,'uint8');
    status = fclose(fid);
    if count ~= numel(bytes) || status ~= 0
        error('ALEV4:ReportWrite','Incomplete Phase 3 demo summary.');
    end
    fprintf('Phase 3 demo wrote %d spatial fixtures; complete=%d.\n',numel(names),include_iset);
end

function spatial = fixture(name,seed)
    p = 6e-6;
    geometry = alev4.createSensorGeometry(struct('full_grid_size',[6 8]));
    sensor = alev4.createBaselineSensor(struct('image_size',[6 8], ...
        'wavelength_nm',[500;600],'bin_width_nm',[20;20], ...
        'qe',[.1 .8 .2;.7 .2 .05],'shot_noise',false,'read_noise_e',0));
    options = struct('input_stage','pre_psf');
    binomial = [.25;.5;.25]*[.25 .5 .25];
    psf = alev4.createOpticalPsf(struct('kernel',binomial, ...
        'origin_rc',[2 2],'spacing_yx_m',[p p]));
    halo = [0 0 0 0]; % top bottom left right
    grid_step = p;
    switch name
        case 'identity_single'
        case {'flat_binomial','edge','dual_spatial'}
            halo = [1 1 1 1]; options.psf = psf;
        case 'shifted_impulse'
            geometry = alev4.createSensorGeometry(struct('full_grid_size',[7 9]));
            halo = [1 0 1 1];
            options.psf = alev4.createOpticalPsf(struct('kernel',[0 .25 .25;.125 .25 .125], ...
                'origin_rc',[1 2],'spacing_yx_m',[p p]));
        case 'sinusoid'
            grid_step = p/2;
            halo = [1 1 1 1];
            options.psf = alev4.createOpticalPsf(struct('kernel',binomial, ...
                'origin_rc',[2 2],'spacing_yx_m',[grid_step grid_step]));
        case 'crop_cfa'
            geometry = alev4.createSensorGeometry(struct('full_grid_size',[8 10], ...
                'active_roi',[2 2 5 7]));
            options.input_stage = 'post_optics';
        otherwise
            error('ALEV4:DemoFixture','Unknown internal spatial fixture.');
    end
    factor = p/grid_step;
    dims = geometry.full_grid_size;
    xedges = (-halo(3):dims(2)*factor+halo(4))*grid_step;
    yedges = (-halo(1):dims(1)*factor+halo(2))*grid_step;
    grid = alev4.createSpatialGrid(struct('x_edges_m',xedges,'y_edges_m',yedges));
    [x,y] = meshgrid((xedges(1:end-1)+xedges(2:end))/2, ...
        (yedges(1:end-1)+yedges(2:end))/2);
    base = 1e14;
    switch name
        case 'flat_binomial', field = base*ones(size(x));
        case 'shifted_impulse'
            field = zeros(size(x)); field(4,5) = base*20;
        case 'edge', field = base*(.2+.8*(x >= 4*p));
        case 'sinusoid'
            f = 1/(8*p); z = f*grid_step;
            field = base*(1+.4*sin(2*pi*f*x)*(sin(pi*z)/(pi*z)));
        case 'dual_spatial'
            field = base*(2+25*x/(dims(2)*p));
        otherwise
            field = base*(.25+x/(dims(2)*p)+.5*y/(dims(1)*p));
    end
    input = cat(3,field,.6*field);
    if strcmp(name,'dual_spatial')
        % Keep shared Phase 1 electronics canonical inside the dual schema.
        common = rmfield(sensor,{'read_noise_e','gain_dn_per_e','black_level_dn','adc_bits'});
        common.shot_noise = true;
        configuration = alev4.createDualGainSensor(struct('sensor',common));
    else
        configuration = sensor;
    end
    configuration = alev4.bindSensorGeometry(configuration,geometry,'derive');
    spatial = alev4.simulateSpatialExposure(input,grid,geometry,configuration,.01,seed,options);
end

function closeQuietly(fid)
    try, fclose(fid); catch, end
end
