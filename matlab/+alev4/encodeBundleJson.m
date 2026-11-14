function [text, decoded] = encodeBundleJson(value)
%ENCODEBUNDLEJSON Preserve finite binary64 metadata in bounded JSON text.
%   The bundle schema uses scalar structs, finite real double scalars,
%   vectors/matrices, scalar logicals and character-row strings. Numeric
%   values use 17 significant decimal digits rather than native jsonencode:
%   some Octave versions otherwise silently serialize tiny positives as 0.
%   Native jsonencode is used only for escaping strings, never numbers.
%   JSON vectors have no row/column orientation; genuine matrices keep rows.
%   Correctly rounded JSON readers recover the original binary64 numbers.
%   Native decoding is checked before return: integers within flintmax and
%   zero are exact; other values may differ by four ULPs at their OWN scale.
%   Nonzero values must never become zero or change sign. This permits a
%   documented small native-parser rounding error, not lost tiny metadata.
%   Unsupported types, nonfinite values and larger precision loss are errors.
    text = encodeValue(value, 0);
    if numel(unicode2native(text, 'UTF-8')) > 2000000
        invalid('Manifest exceeds the 2,000,000-byte format limit.');
    end
    decoded = alev4.decodeBundleJson(text);
    requireRoundtrip(value, decoded);
end

function text = encodeValue(value, depth)
    if isstruct(value) && isscalar(value)
        requireDepth(depth + 1);
        names = fieldnames(value);
        if numel(names) > 256, invalid('JSON object exceeds 256 fields.'); end
        parts = cell(1, numel(names));
        length_so_far = 2;
        for k = 1:numel(names)
            name = names{k};
            if isempty(regexp(name, '^[A-Za-z][A-Za-z0-9_]*$', 'once')) || ...
                    ~isvarname(name) || numel(name) > namelengthmax
                invalid('JSON keys must retain their exact portable spelling.');
            end
            parts{k} = [jsonencode(name) ':' encodeValue(value.(name), depth + 1)];
            length_so_far = length_so_far + numel(parts{k}) + 1;
            if length_so_far > 2000001, invalid('Manifest exceeds the JSON text size bound.'); end
        end
        text = ['{' strjoin(parts, ',') '}'];
    elseif isa(value, 'double') && isreal(value) && ismatrix(value)
        if any(~isfinite(value(:))), invalid('JSON numbers must be finite.'); end
        value = full(value);
        if isscalar(value)
            text = sprintf('%.17g', value);
        elseif isempty(value)
            requireDepth(depth + 1);
            text = '[]';
        elseif isvector(value)
            requireDepth(depth + 1);
            text = encodeRow(value(:).');
        else
            requireDepth(depth + 2);
            rows = cell(1, size(value, 1));
            length_so_far = 2;
            for k = 1:size(value, 1)
                rows{k} = encodeRow(value(k, :));
                length_so_far = length_so_far + numel(rows{k}) + 1;
                if length_so_far > 2000001, invalid('Manifest exceeds the JSON text size bound.'); end
            end
            text = ['[' strjoin(rows, ',') ']'];
        end
    elseif islogical(value) && isscalar(value)
        if value, text = 'true'; else, text = 'false'; end
    elseif ischar(value) && (isempty(value) || isrow(value))
        text = jsonencode(value);
    else
        invalid('Unsupported bundle JSON value type or shape.');
    end
    if numel(text) > 2000000
        invalid('Manifest exceeds the JSON text size bound.');
    end
end

function text = encodeRow(values)
    % One vectorized native formatting call avoids per-sample interpreter
    % overhead for long wavelength vectors; exponent syntax and -0 survive.
    numbers = sprintf('%.17g,', values);
    text = ['[' numbers(1:end-1) ']'];
end

function requireRoundtrip(original, decoded)
    if isstruct(original)
        if ~isstruct(decoded) || ~isscalar(decoded) || ...
                ~isequal(sort(fieldnames(original)), sort(fieldnames(decoded)))
            invalid('Encoded metadata changed its object fields.');
        end
        names = fieldnames(original);
        for k = 1:numel(names)
            requireRoundtrip(original.(names{k}), decoded.(names{k}));
        end
    elseif isa(original, 'double')
        if ~isnumeric(decoded) || ~isreal(decoded)
            invalid('Encoded metadata changed a numeric value type.');
        end
        % Native JSON decoders normalize vectors to either rows or columns.
        if isempty(original)
            equal = isempty(decoded);
        elseif isvector(original)
            equal = isvector(decoded) && numel(original) == numel(decoded);
        else
            equal = isequal(size(original), size(decoded));
        end
        if ~equal, invalid('Encoded metadata changed a numeric shape.'); end
        source = original(:); observed = double(decoded(:));
        % All schema counts, sizes, seeds and bit depths are in the exact
        % integer range. Larger values can be continuous physical scales:
        % binary64 has no fractional spacing above flintmax.
        discrete = source == fix(source) & abs(source) <= flintmax;
        if any(~isfinite(observed)) || any(source(discrete) ~= observed(discrete)) || ...
                any(sign(source) ~= sign(observed)) || ...
                any(abs(source - observed) > 4 * eps(abs(source)))
            invalid('Encoded metadata lost numeric precision, sign, or a nonzero value.');
        end
    elseif ~isequal(original, decoded)
        invalid('Encoded metadata changed a string or logical value.');
    end
end

function requireDepth(depth)
    if depth > 64, invalid('JSON nesting exceeds 64 containers.'); end
end

function invalid(message)
    error('ALEV4:InvalidDualGainMetadata', '%s', message);
end
