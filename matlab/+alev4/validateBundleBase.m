function [parent, stem] = validateBundleBase(base)
%VALIDATEBUNDLEBASE Validate the shared native/Python bundle basename policy.
%   Only the extracted stem is restricted for portable payload associations;
%   parent directories retain their platform separators and drive prefixes.
    if nargin ~= 1 || ~ischar(base) || isempty(base) || size(base, 1) ~= 1 || ...
            any(double(base) < 32)
        error('ALEV4:InvalidDualGainPath', ...
            'Bundle base must be a nonempty character row without control characters.');
    end
    [parent, name, extension] = fileparts(base);
    stem = [name extension];
    if isempty(stem) || any(strcmp(stem, {'.', '..'})) || ...
            any(stem == ':' | stem == char(92) | stem == '/')
        error('ALEV4:InvalidDualGainPath', ...
            'Bundle stem must not contain a colon, backslash, or directory separator.');
    end
    if isempty(parent), parent = '.'; end
end
