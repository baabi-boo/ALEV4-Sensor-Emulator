function channels = cfaMap(image_size, pattern)
%CFAMAP Return Bayer channel indices: 1=red, 2=green, 3=blue.
%   The first pattern character describes array element (1,1), the next
%   character (1,2), then (2,1), then (2,2). Odd dimensions crop the repeating
%   2-by-2 tile without moving the CFA origin. Output is height-by-width.
%   Dimensions are bounded to the RAW format's 100-million-pixel limit
%   before allocating any index or output array.
    if ~isnumeric(image_size) || ~isreal(image_size) || ...
            ~isvector(image_size) || numel(image_size) ~= 2 || ...
            any(~isfinite(image_size(:))) || any(image_size(:) < 1) || ...
            any(image_size(:) ~= fix(image_size(:)))
        error('ALEV4:InvalidImageSize', ...
            'image_size must contain two positive finite integer dimensions.');
    end
    image_size = full(double(image_size(:).'));
    maximum_pixels = 1e8;
    if any(image_size > maximum_pixels) || ...
            image_size(1) > maximum_pixels / image_size(2)
        error('ALEV4:InvalidImageSize', ...
            'image_size must not exceed 100 million pixels.');
    end
    if ~ischar(pattern) || ~isrow(pattern)
        error('ALEV4:InvalidCFA', 'CFA pattern must be a character row vector.');
    end
    switch upper(pattern)
        case 'RGGB'
            tile = [1 2; 2 3];
        case 'BGGR'
            tile = [3 2; 2 1];
        case 'GRBG'
            tile = [2 1; 3 2];
        case 'GBRG'
            tile = [2 3; 1 2];
        otherwise
            error('ALEV4:InvalidCFA', ...
                'CFA pattern must be RGGB, BGGR, GRBG, or GBRG.');
    end
    row_indices = mod((0:image_size(1)-1)', 2) + 1;
    col_indices = mod(0:image_size(2)-1, 2) + 1;
    channels = tile(row_indices, col_indices);
end
