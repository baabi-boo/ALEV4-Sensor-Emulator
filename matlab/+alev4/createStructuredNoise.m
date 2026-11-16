function model = createStructuredNoise(full_grid_size, overrides)
%CREATESTRUCTUREDNOISE Validate explicit full-grid structured-noise settings.
%   MODEL = alev4.createStructuredNoise([ROWS COLUMNS], OVERRIDES) creates a
%   separate schema; it does not modify existing sensor or geometry fields.
%   OVERRIDES is optional and accepts partial named electronic components.
%   Passing a canonical MODEL as OVERRIDES validates it against the explicit
%   full-grid size. A conflicting stored full_grid_size is always an error,
%   including when enabled is false.
%
%   PRNU is an achromatic, nonnegative response multiplier, with neutral
%   value one. dark_current_e_per_s is a nonnegative rate per photosite.
%   Each shared/single/high_gain/low_gain component contains a signed
%   fixed_offset_e map and nonnegative row/column/frame RMS noise in
%   electrons. A fixed map is either one scalar for a uniform full grid or
%   a matrix matching that full grid exactly; no map is silently normalized.
%   Numeric settings become dense doubles, while logical switches remain
%   logical. Explicit scalar maps remain compact until ROI extraction.
%   The complete model supports at most 100 million numeric/logical values;
%   the descriptor inventory rejects before any sparse map becomes dense.
%
%   Defaults and supplied maps are assumed synthetic settings, not measured
%   ALEV4 calibration. The default reference temperature is 293.15 K; it
%   declares applicability only and supplies no temperature law. Supplied
%   maps define the persistent realization. Its ID is a label, not a map
%   hash; fixed maps have no seed and this constructor consumes no randomness.

    if nargin < 1 || nargin > 2
        error('ALEV4:StructuredNoiseArguments', ...
            'A full-grid size and optional structured-noise overrides are required.');
    end
    dims = gridSize(full_grid_size);
    path = struct('fixed_offset_e', 0, 'row_noise_e', 0, ...
        'column_noise_e', 0, 'frame_noise_e', 0);
    model = struct('schema_version', '1.0', 'enabled', true, ...
        'full_grid_size', dims, 'realization_id', 'ASSUMED-P4-DEFAULT', ...
        'reference_temperature_K', 293.15, 'prnu', 1, ...
        'dark_current_e_per_s', 0, 'dark_shot_noise', true, ...
        'shared', path, 'single', path, 'high_gain', path, 'low_gain', path, ...
        'parameter_sources', {{'ASSUMED-P4-PRNU', 'ASSUMED-P4-DARK-RATE', ...
            'ASSUMED-P4-CHARGE', 'ASSUMED-P4-OFFSET', 'ASSUMED-P4-ROW', ...
            'ASSUMED-P4-COLUMN', 'ASSUMED-P4-FRAME', 'ASSUMED-P4-IDENTITY'}});
    if nargin < 2, overrides = struct(); end
    requireStruct(overrides, 'Structured-noise overrides');
    path_names = {'shared', 'single', 'high_gain', 'low_gain'};
    names = fieldnames(overrides);
    for k = 1:numel(names)
        name = names{k};
        if ~isfield(model, name)
            error('ALEV4:UnknownStructuredNoiseField', ...
                'Unknown structured-noise field: %s.', name);
        end
        if any(strcmp(name, path_names))
            model.(name) = mergePath(path, overrides.(name), name);
        else
            model.(name) = overrides.(name);
        end
    end

    % Full-grid maps can be sparse descriptors with enormous represented
    % sizes. Bound their aggregate before validation converts even the first
    % map to dense storage. This also bounds explicitly disabled models.
    if alev4.structuredNumericSamples(model) > 1e8
        error('ALEV4:StructuredNoiseSize', ...
            'A structured model supports at most 100 million numeric/logical values.');
    end

    if ~ischar(model.schema_version) || ~isrow(model.schema_version) || ...
            ~strcmp(model.schema_version, '1.0')
        error('ALEV4:InvalidStructuredNoise', ...
            'Structured-noise schema_version must be the character row vector ''1.0''.');
    end
    stored_dims = gridSize(model.full_grid_size);
    if ~isequal(stored_dims, dims)
        error('ALEV4:StructuredNoiseGridMismatch', ...
            'The stored full_grid_size must exactly match the requested full grid.');
    end
    model.full_grid_size = dims;
    model.enabled = requireLogical(model.enabled, 'enabled');
    model.dark_shot_noise = requireLogical(model.dark_shot_noise, 'dark_shot_noise');
    requireIdentifier(model.realization_id, 'realization_id');
    model.reference_temperature_K = requireScalar( ...
        model.reference_temperature_K, 'reference_temperature_K');
    if model.reference_temperature_K <= 0
        error('ALEV4:InvalidStructuredNoise', ...
            'reference_temperature_K must be positive.');
    end
    model.prnu = fixedMap(model.prnu, dims, 'prnu', true);
    model.dark_current_e_per_s = fixedMap( ...
        model.dark_current_e_per_s, dims, 'dark_current_e_per_s', true);
    rms_names = {'row_noise_e', 'column_noise_e', 'frame_noise_e'};
    for k = 1:numel(path_names)
        name = path_names{k};
        component = model.(name);
        component.fixed_offset_e = fixedMap(component.fixed_offset_e, ...
            dims, [name '.fixed_offset_e'], false);
        for j = 1:numel(rms_names)
            field = rms_names{j};
            value = requireScalar(component.(field), [name '.' field]);
            if value < 0
                error('ALEV4:InvalidStructuredNoise', ...
                    '%s.%s must be nonnegative RMS electrons.', name, field);
            end
            component.(field) = value;
        end
        model.(name) = component;
    end

    sources = model.parameter_sources;
    if ~iscell(sources) || ~isvector(sources) || isempty(sources) || numel(sources) > 32
        error('ALEV4:InvalidStructuredNoise', ...
            'parameter_sources must be a nonempty cell vector of at most 32 source IDs.');
    end
    for k = 1:numel(sources)
        requireIdentifier(sources{k}, 'parameter_sources entry');
    end
    if numel(unique(sources)) ~= numel(sources)
        error('ALEV4:InvalidStructuredNoise', 'Parameter source IDs must be unique.');
    end
    model.parameter_sources = reshape(sources, 1, []);
end

function dims = gridSize(value)
    if ~isnumeric(value) || ~isreal(value) || ~isvector(value) || ...
            numel(value) ~= 2 || any(~isfinite(value(:)))
        error('ALEV4:InvalidStructuredNoise', ...
            'full_grid_size must contain two finite real numeric dimensions.');
    end
    dims = full(double(value(:).'));
    if any(dims < 1 | dims ~= fix(dims)) || ...
            any(dims > 1e8) || dims(1) > 1e8/dims(2)
        error('ALEV4:InvalidStructuredNoise', ...
            'The full grid must contain 1 through 100 million pixels.');
    end
end

function requireStruct(value, name)
    if ~isstruct(value) || ~isscalar(value)
        error('ALEV4:InvalidStructuredNoise', '%s must be a scalar struct.', name);
    end
end

function value = mergePath(defaults, overrides, name)
    requireStruct(overrides, name);
    value = defaults;
    names = fieldnames(overrides);
    for k = 1:numel(names)
        field = names{k};
        if ~isfield(defaults, field)
            error('ALEV4:UnknownStructuredNoiseField', ...
                'Unknown structured-noise field: %s.%s.', name, field);
        end
        value.(field) = overrides.(field);
    end
end

function value = requireLogical(value, name)
    if ~islogical(value) || ~isscalar(value)
        error('ALEV4:InvalidStructuredNoise', ...
            '%s must be a scalar logical true or false.', name);
    end
    value = full(value);
end

function value = requireScalar(value, name)
    if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ~isfinite(value)
        error('ALEV4:InvalidStructuredNoise', ...
            '%s must be a finite real numeric scalar.', name);
    end
    value = full(double(value));
end

function value = fixedMap(value, dims, name, nonnegative)
    if ~isnumeric(value) || ~isreal(value) || ~ismatrix(value) || ...
            (~isscalar(value) && ~isequal(size(value), dims)) || ...
            any(~isfinite(value(:)))
        error('ALEV4:InvalidStructuredNoise', ...
            '%s must be a finite real scalar or a matrix matching full_grid_size.', name);
    end
    if nonnegative && any(value(:) < 0)
        error('ALEV4:InvalidStructuredNoise', '%s must be nonnegative.', name);
    end
    value = full(double(value));
end

function requireIdentifier(value, name)
    if ~ischar(value) || ~isrow(value) || isempty(value) || numel(value) > 128 || ...
            any(double(value) < 33 | double(value) > 126) || ...
            isempty(regexp(value, '^[A-Za-z0-9][A-Za-z0-9_.-]*\z', 'once'))
        error('ALEV4:InvalidStructuredNoise', ...
            '%s must be a source-style identifier of 1 through 128 characters.', name);
    end
end
