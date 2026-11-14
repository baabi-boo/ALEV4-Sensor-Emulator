function value = decodeBundleJson(text)
%DECODEBUNDLEJSON Reject ambiguous original object keys before native decoding.
%   Native jsondecode may normalize invalid field names and discard duplicate
%   keys. Scan original strings and container scopes first, comparing decoded
%   key escapes within each object. Equal keys in distinct objects are legal.
%   Native jsondecode still performs the complete JSON grammar validation.
%   The format bounds nesting to 64 containers and 256 keys per object.
    if ~ischar(text) || size(text, 1) ~= 1
        error('ALEV4:InvalidDualGainMetadata', 'Manifest JSON must be character-row text.');
    end
    % Index structural characters once. Whitespace and long numeric arrays
    % need no interpreted per-character loop; strings still use escape-aware
    % scanning, and native decoding validates every omitted grammar token.
    events = regexp(text, '["{}\[\]:]');
    last = numel(text);
    event = 1;
    kinds = repmat(' ', 1, 64);
    keys = cell(1, 64);
    depth = 0;
    while event <= numel(events)
        position = events(event);
        token = text(position);
        if token == '"'
            start = position;
            position = position + 1;
            closed = false;
            while position <= last
                if text(position) == char(92)
                    position = position + 2;
                elseif text(position) == '"'
                    closed = true;
                    break;
                else
                    position = position + 1;
                end
            end
            if ~closed
                error('ALEV4:InvalidDualGainMetadata', 'Unterminated JSON string.');
            end
            following = event + 1;
            while following <= numel(events) && events(following) <= position
                following = following + 1;
            end
            is_key = following <= numel(events) && text(events(following)) == ':';
            if is_key
                gap = text(position+1:events(following)-1);
                is_key = all(ismember(gap, [char(9) char(10) char(13) ' ']));
            end
            if is_key
                if depth == 0 || kinds(depth) ~= '{'
                    error('ALEV4:InvalidDualGainMetadata', 'Object key outside a JSON object.');
                end
                % Decode the key as a VALUE under one known-safe ASCII key.
                % This exposes escaped aliases without normalizing the name.
                decoded = decodeNative(['{"key":' text(start:position) '}']);
                key = decoded.key;
                if ~ischar(key) || ~isrow(key) || ...
                        isempty(regexp(key, '^[A-Za-z][A-Za-z0-9_]*$', 'once')) || ...
                        ~isvarname(key) || numel(key) > namelengthmax
                    error('ALEV4:InvalidDualGainMetadata', ...
                        'JSON keys must retain their exact portable field spelling.');
                end
                if any(strcmp(keys{depth}, key))
                    error('ALEV4:InvalidDualGainMetadata', 'Duplicate JSON object key: %s.', key);
                end
                if numel(keys{depth}) >= 256
                    error('ALEV4:InvalidDualGainMetadata', 'JSON object exceeds the field-count bound.');
                end
                keys{depth}{end+1} = key;
            end
            event = following;
        elseif token == '{' || token == '['
            if depth == numel(kinds)
                error('ALEV4:InvalidDualGainMetadata', 'JSON nesting exceeds 64 containers.');
            end
            depth = depth + 1;
            kinds(depth) = token;
            keys{depth} = {};
            event = event + 1;
        elseif token == '}' || token == ']'
            if depth == 0 || (token == '}' && kinds(depth) ~= '{') || ...
                    (token == ']' && kinds(depth) ~= '[')
                error('ALEV4:InvalidDualGainMetadata', 'Mismatched JSON container.');
            end
            keys{depth} = {};
            depth = depth - 1;
            event = event + 1;
        else
            event = event + 1;
        end
    end
    if depth ~= 0
        error('ALEV4:InvalidDualGainMetadata', 'Unterminated JSON container.');
    end
    value = decodeNative(text);
    requireFiniteNumbers(value);
end

function value = decodeNative(text)
    try
        value = jsondecode(text);
    catch err
        error('ALEV4:InvalidDualGainMetadata', 'Invalid JSON syntax or numeric range: %s', err.message);
    end
end

function requireFiniteNumbers(value)
    if isnumeric(value)
        if any(~isfinite(value(:)))
            error('ALEV4:InvalidDualGainMetadata', 'Manifest JSON contains nonfinite numbers.');
        end
    elseif isstruct(value)
        fields = fieldnames(value);
        for element = 1:numel(value)
            for k = 1:numel(fields)
                requireFiniteNumbers(value(element).(fields{k}));
            end
        end
    elseif iscell(value)
        for k = 1:numel(value), requireFiniteNumbers(value{k}); end
    end
end
