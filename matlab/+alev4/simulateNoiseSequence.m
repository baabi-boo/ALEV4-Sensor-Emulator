function result = simulateNoiseSequence(input, readout, exposures_s, sequence_seed, model, geometry, options)
%SIMULATENOISESEQUENCE Explicit independent frames without hidden state.
%   EXPOSURES_S is a nonempty vector with one physical exposure per frame.
%   A scalar means one frame; exposures are never implicitly replicated.
%   OPTIONS fields are frame_indices, start_frame, and ei_label only.
%   frame_indices is a strictly increasing integer vector in [1,2^26], with
%   one absolute index per exposure; gaps are allowed. Alternatively,
%   start_frame (default 1) selects consecutive absolute indices. Supplying
%   both selectors rejects. Frame i uses mod(sequence_seed+64*(i-1),2^32).
%   ei_label is [] (absent), a positive finite numeric scalar, or a positive
%   finite numeric vector with one label per frame. It changes metadata only.
%   The same input, configuration and fixed model apply to every frame.
%
%   All frames call simulateStructuredExposure. Enabled models produce its
%   structured result; disabled models produce unchanged legacy frame results
%   inside the explicitly disabled sequence envelope. No sequence envelope is
%   an earlier-phase artifact. Reset/continuation requires only the same
%   arguments and absolute indices, with no mutable sequence state. Identical
%   random streams are promised only within one runtime and version.
%   Retained numeric/logical values across the sequence are bounded at 1e8;
%   this is a supported-size limit, not a practical memory guarantee.
    if nargin < 6 || nargin > 7
        error('ALEV4:NoiseSequenceArguments', ...
            'Six arguments and optional sequence options are required.');
    end
    if nargin < 7, options = struct(); end
    caller_rng = rng;
    rng_guard = onCleanup(@() rng(caller_rng)); %#ok<NASGU>
    options = validateOptions(options);
    exposures_s = exposureVector(exposures_s);
    frame_count = numel(exposures_s);
    sequence_seed = sequenceSeed(sequence_seed);
    frame_indices = absoluteIndices(options,frame_count);
    ei_label = eiLabels(options,frame_count);
    geometry = alev4.createSensorGeometry(geometry);
    configuration = alev4.bindSensorGeometry(readout,geometry,'validate');
    model = alev4.createStructuredNoise(geometry.full_grid_size,model);

    % This inexpensive lower bound rejects obviously unsupported requests
    % before producing even one retained frame. Exact shapes are checked by
    % the structured API, including its disabled legacy dispatch.
    maximum_samples = 1e8;
    minimum_frame_samples = numel(input)+prod(geometry.active_roi(3:4));
    if frame_count > maximum_samples/max(1,minimum_frame_samples)
        error('ALEV4:NoiseSequenceSize', ...
            'A sequence supports at most 100 million retained numeric/logical values.');
    end
    % All intermediate integers are below 2^33 and are exact in binary64.
    % Convert accepted seeds/indices before modular arithmetic, since native
    % integer arithmetic can saturate instead of wrapping in MATLAB/Octave.
    frame_seeds = mod(sequence_seed+64*(frame_indices-1),4294967296);
    first_frame = alev4.simulateStructuredExposure(input,configuration, ...
        exposures_s(1),frame_seeds(1),model,geometry);
    metadata_samples = storedSamples(configuration)+storedSamples(geometry)+ ...
        storedSamples(model)+numel(frame_indices)+numel(frame_seeds)+ ...
        numel(exposures_s)+numel(ei_label)+16;
    if metadata_samples > maximum_samples || ...
            frame_count > (maximum_samples-metadata_samples)/storedSamples(first_frame)
        error('ALEV4:NoiseSequenceSize', ...
            'A sequence supports at most 100 million retained numeric/logical values.');
    end
    frames = cell(1,frame_count);
    frames{1} = first_frame;
    for k = 2:frame_count
        frames{k} = alev4.simulateStructuredExposure(input,configuration, ...
            exposures_s(k),frame_seeds(k),model,geometry);
    end
    if strcmp(configuration.schema_version,'2.0')
        readout_mode = 'dual';
    else
        readout_mode = 'single';
    end
    if model.enabled
        frame_result_kind = 'structured_exposure';
    else
        frame_result_kind = ['legacy_' readout_mode '_gain_exposure'];
    end
    result = struct('format','ALEV4-SYNTHETIC-STRUCTURED-NOISE', ...
        'schema_version','1.0','result_kind','independent_frame_sequence', ...
        'structured_noise_enabled',model.enabled,'readout_mode',readout_mode, ...
        'configuration',configuration,'geometry',geometry,'noise_model',model, ...
        'sequence_seed',sequence_seed,'frame_count',frame_count, ...
        'frame_indices',frame_indices,'frame_seeds',frame_seeds, ...
        'exposures_s',exposures_s,'ei_label',ei_label, ...
        'frame_result_kind',frame_result_kind,'frames',{frames}, ...
        'temporal_policy','independent_frames', ...
        'continuation_policy','pure_function_of_arguments_and_absolute_frame_indices', ...
        'ei_policy','metadata_only_no_exposure_or_gain_mapping', ...
        'seed_schedule',struct('stride',64,'modulus',4294967296, ...
            'minimum_frame_index',1,'maximum_frame_index',67108864, ...
            'expression','mod(sequence_seed + 64*(absolute_frame_index-1), 2^32)'), ...
        'rng_generator','twister','runtime',runtimeInfo(), ...
        'reproducibility','same_runtime_and_version_only', ...
        'synthetic',true,'calibrated_alev4',false);
end

function options = validateOptions(options)
    if ~isstruct(options) || ~isscalar(options)
        error('ALEV4:InvalidNoiseSequenceOptions', 'Sequence options must be a scalar struct.');
    end
    allowed = {'frame_indices','start_frame','ei_label'};
    names = fieldnames(options);
    for k = 1:numel(names)
        if ~any(strcmp(names{k},allowed))
            error('ALEV4:InvalidNoiseSequenceOptions', ...
                'Unknown sequence option: %s.',names{k});
        end
    end
    if isfield(options,'frame_indices') && isfield(options,'start_frame')
        error('ALEV4:InvalidNoiseSequenceOptions', ...
            'Specify frame_indices or start_frame, not both.');
    end
end

function value = exposureVector(value)
    if ~isnumeric(value) || ~isreal(value) || ~isvector(value) || isempty(value) || ...
            any(~isfinite(value(:))) || any(value(:)<0)
        error('ALEV4:InvalidNoiseSequenceExposures', ...
            'exposures_s must be a nonempty finite nonnegative numeric vector.');
    end
    if numel(value)>67108864
        error('ALEV4:InvalidNoiseSequenceIndices', ...
            'A sequence cannot contain more than 2^26 absolute frame indices.');
    end
    value = full(double(value(:).'));
end

function value = sequenceSeed(value)
    if ~isnumeric(value) || ~isreal(value) || ~isscalar(value)
        error('ALEV4:InvalidSeed', 'sequence_seed must be an integer in [0,2^32-1].');
    end
    value = full(double(value));
    if ~isfinite(value) || value<0 || value>4294967295 || value~=fix(value)
        error('ALEV4:InvalidSeed', 'sequence_seed must be an integer in [0,2^32-1].');
    end
end

function indices = absoluteIndices(options,count)
    maximum_index = 67108864;
    if isfield(options,'frame_indices')
        indices = options.frame_indices;
        if ~isnumeric(indices) || ~isreal(indices) || ~isvector(indices) || ...
                numel(indices)~=count || any(~isfinite(indices(:))) || ...
                any(indices(:)<1 | indices(:)>maximum_index | indices(:)~=fix(indices(:)))
            error('ALEV4:InvalidNoiseSequenceIndices', ...
                'frame_indices must contain one integer in [1,2^26] per exposure.');
        end
        indices = full(double(indices(:).'));
        if any(diff(indices)<=0)
            error('ALEV4:InvalidNoiseSequenceIndices', ...
                'frame_indices must be strictly increasing; duplicates and reversed order reject.');
        end
    else
        if isfield(options,'start_frame'), first = options.start_frame; else, first = 1; end
        if ~isnumeric(first) || ~isreal(first) || ~isscalar(first) || ...
                ~isfinite(first) || first<1 || first>maximum_index || first~=fix(first)
            error('ALEV4:InvalidNoiseSequenceIndices', ...
                'start_frame must be an integer in [1,2^26].');
        end
        first = full(double(first));
        if count>maximum_index-first+1
            error('ALEV4:InvalidNoiseSequenceIndices', ...
                'The requested consecutive frames exceed absolute index 2^26.');
        end
        indices = first+(0:count-1);
    end
end

function labels = eiLabels(options,count)
    if ~isfield(options,'ei_label')
        labels = [];
        return;
    end
    labels = options.ei_label;
    if isequal(labels,[]) && isa(labels,'double'), return; end
    if ~isnumeric(labels) || ~isreal(labels) || ~isvector(labels) || isempty(labels) || ...
            (~isscalar(labels) && numel(labels)~=count) || ...
            any(~isfinite(labels(:))) || any(labels(:)<=0)
        error('ALEV4:InvalidNoiseSequenceEi', ...
            'ei_label must be [], a positive finite scalar, or one positive finite number per frame.');
    end
    labels = full(double(labels(:).'));
    if isscalar(labels), labels = repmat(labels,1,count); end
end

function count = storedSamples(value)
% Count retained numeric/logical elements, including fixed maps and metadata.
    if isnumeric(value) || islogical(value)
        count = numel(value);
    elseif isstruct(value)
        count = 0;
        names = fieldnames(value);
        for element = 1:numel(value)
            for k = 1:numel(names)
                count = count+storedSamples(value(element).(names{k}));
            end
        end
    elseif iscell(value)
        count = 0;
        for k = 1:numel(value), count = count+storedSamples(value{k}); end
    else
        count = 0;
    end
end

function info = runtimeInfo()
    if exist('OCTAVE_VERSION','builtin')
        name = 'GNU Octave';
    else
        name = 'MATLAB';
    end
    info = struct('name',name,'version',version());
end
