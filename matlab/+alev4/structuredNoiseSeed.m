function seed = structuredNoiseSeed(frame_seed, component)
%STRUCTUREDNOISESEED Derive one explicitly named Phase 4 component seed.
%   SEED = alev4.structuredNoiseSeed(FRAME_SEED, COMPONENT) implements
%   mod(FRAME_SEED + tag, 2^32), without consuming any random numbers.
%   Names/tags are photo/1, dark/2, shared_row/10, shared_column/11,
%   shared_frame/12; single_row/20, single_column/21, single_frame/22,
%   single_pixel/23; high_row/30, high_column/31, high_frame/32,
%   high_pixel/33; low_row/40, low_column/41, low_frame/42, low_pixel/43.
%   FRAME_SEED is an integer in [0,2^32-1]. Every operation is exact in
%   binary64 over this range. Adjacent seeds are a synthetic PRNG policy,
%   not a proof of independence or a cross-runtime stream identity promise.
    if nargin ~= 2
        error('ALEV4:StructuredNoiseSeedArguments', ...
            'A frame seed and a named structured-noise component are required.');
    end
    if ~isnumeric(frame_seed) || ~isreal(frame_seed) || ~isscalar(frame_seed)
        error('ALEV4:InvalidSeed', 'Seed must be an integer in [0, 2^32-1].');
    end
    % Compare in binary64: a single-precision comparison rounds 2^32-1 up
    % to 2^32 and would admit an out-of-range represented input.
    frame_seed = full(double(frame_seed));
    if ~isfinite(frame_seed) || ...
            frame_seed < 0 || frame_seed > 4294967295 || ...
            frame_seed ~= fix(frame_seed)
        error('ALEV4:InvalidSeed', 'Seed must be an integer in [0, 2^32-1].');
    end
    names = {'photo','dark','shared_row','shared_column','shared_frame', ...
        'single_row','single_column','single_frame','single_pixel', ...
        'high_row','high_column','high_frame','high_pixel', ...
        'low_row','low_column','low_frame','low_pixel'};
    tags = [1 2 10 11 12 20 21 22 23 30 31 32 33 40 41 42 43];
    if ~ischar(component) || ~isrow(component)
        error('ALEV4:InvalidStructuredNoiseComponent', ...
            'The structured-noise component must be a documented character-row name.');
    end
    index = find(strcmp(component, names), 1);
    if isempty(index)
        error('ALEV4:InvalidStructuredNoiseComponent', ...
            'Unknown structured-noise component: %s.', component);
    end
    seed = mod(full(double(frame_seed)) + tags(index), 4294967296);
end
