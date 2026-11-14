function [value, kinds] = spatialDecodeJson(text)
%SPATIALDECODEJSON Preserve numeric lexemes and JSON types in Phase 3 metadata.
%   Original strings and portable field spellings are checked before native
%   decoding can truncate an escaped NUL or accept a nonportable identifier.
%   The shared strict decoder still validates grammar, duplicates and bounds.
%   Numbers are then converted from their original lexemes with str2double.
%   KINDS retains scalar versus vector/matrix wire types for schema checks;
%   singleton containers must not silently turn a numeric array into a scalar.
    if ~ischar(text) || ~isrow(text) || ...
            numel(unicode2native(text,'UTF-8'))>2000000
        error('ALEV4:InvalidSpatialMetadata','Spatial JSON must be bounded character-row text.');
    end
    validateOriginalStrings(text);
    alev4.decodeBundleJson(text);
    position=1;
    last=numel(text);
    [value,kinds]=parseValue();
    skipSpace();
    if position<=last
        error('ALEV4:InvalidSpatialMetadata','Unexpected text after spatial JSON.');
    end

    function skipSpace()
        while position<=last && any(text(position)==[char(9) char(10) char(13) ' '])
            position=position+1;
        end
    end

    function [result,kind]=parseValue()
        skipSpace();
        if position>last, error('ALEV4:InvalidSpatialMetadata','Missing spatial JSON value.'); end
        token=text(position);
        if token=='{'
            position=position+1; skipSpace(); result=struct(); kind=struct();
            if text(position)=='}', position=position+1; return; end
            while true
                name=parseString(); skipSpace();
                if text(position)~=':', error('ALEV4:InvalidSpatialMetadata','Missing object separator.'); end
                position=position+1;
                [result.(name),kind.(name)]=parseValue();
                skipSpace();
                if text(position)=='}', position=position+1; break; end
                if text(position)~=',', error('ALEV4:InvalidSpatialMetadata','Missing object comma.'); end
                position=position+1; skipSpace();
            end
        elseif token=='['
            position=position+1; skipSpace(); items={}; item_kinds={};
            if text(position)==']', position=position+1; result=[]; kind='empty'; return; end
            while true
                [items{end+1},item_kinds{end+1}]=parseValue(); %#ok<AGROW>
                skipSpace();
                if text(position)==']', position=position+1; break; end
                if text(position)~=',', error('ALEV4:InvalidSpatialMetadata','Missing array comma.'); end
                position=position+1;
            end
            if all(cellfun(@(x)isequal(x,'number'),item_kinds))
                result=[items{:}]; kind='vector';
            elseif all(cellfun(@(x)isequal(x,'vector'),item_kinds)) && ...
                    all(cellfun(@numel,items)==numel(items{1}))
                result=vertcat(items{:}); kind='matrix';
            else
                error('ALEV4:InvalidSpatialMetadata', ...
                    'JSON arrays must be numeric vectors or rectangular numeric matrices.');
            end
        elseif token=='"'
            result=parseString(); kind='text';
        elseif token=='t'
            position=position+4; result=true; kind='boolean';
        elseif token=='f'
            position=position+5; result=false; kind='boolean';
        elseif token=='n'
            error('ALEV4:InvalidSpatialMetadata','Null is not a Phase 3 metadata value.');
        else
            first=position;
            while position<=last && any(text(position)=='-+0123456789.eE')
                position=position+1;
            end
            lexeme=text(first:position-1);
            result=str2double(lexeme); kind='number';
            if isempty(lexeme) || ~isscalar(result) || ~isfinite(result)
                error('ALEV4:InvalidSpatialMetadata','Unsupported numeric JSON range.');
            end
            exponent=find(lexeme=='e' | lexeme=='E',1);
            if isempty(exponent), mantissa=lexeme; else, mantissa=lexeme(1:exponent-1); end
            if result==0 && any(mantissa>='1' & mantissa<='9')
                error('ALEV4:InvalidSpatialMetadata','A nonzero JSON number underflows binary64.');
            end
        end
    end

    function result=parseString()
        skipSpace();
        if position>last || text(position)~='"'
            error('ALEV4:InvalidSpatialMetadata','A JSON string is required.');
        end
        first=position; position=position+1;
        while position<=last
            if text(position)==char(92)
                position=position+2;
            elseif text(position)=='"'
                position=position+1;
                decoded=jsondecode(['{"value":' text(first:position-1) '}']);
                result=decoded.value;
                return;
            else
                position=position+1;
            end
        end
        error('ALEV4:InvalidSpatialMetadata','Unterminated spatial JSON string.');
    end
end

function validateOriginalStrings(text)
% Check original escapes before a native decoder can discard their spelling.
% The identifier set is frozen across supported MATLAB/Octave versions, not
% taken from the executing host's changing isvarname/namelengthmax behavior.
    keywords={'__FILE__','__LINE__','break','case','catch','classdef','continue', ...
        'do','else','elseif','end','end_try_catch','end_unwind_protect', ...
        'endarguments','endclassdef','endenumeration','endevents','endfor', ...
        'endfunction','endif','endmethods','endparfor','endproperties','endspmd', ...
        'endswitch','endwhile','for','function','global','if','otherwise','parfor', ...
        'persistent','return','spmd','switch','try','until','unwind_protect', ...
        'unwind_protect_cleanup','while'};
    if any(text==char(0))
        error('ALEV4:InvalidSpatialMetadata','Spatial JSON strings cannot contain NUL.');
    end
    position=1; last=numel(text);
    while position<=last
        if text(position)~='"', position=position+1; continue; end
        first=position; position=position+1; closed=false;
        while position<=last
            if text(position)==char(92)
                if position+5<=last && text(position+1)=='u' && ...
                        ~isempty(regexp(text(position+2:position+5),'^[0-9A-Fa-f]{4}$','once'))
                    code=hex2dec(text(position+2:position+5));
                    if code==0
                        error('ALEV4:InvalidSpatialMetadata','Spatial JSON strings cannot contain escaped NUL.');
                    elseif code>=hex2dec('D800') && code<=hex2dec('DBFF')
                        if position+11>last || text(position+6)~=char(92) || text(position+7)~='u' || ...
                                isempty(regexp(text(position+8:position+11),'^[0-9A-Fa-f]{4}$','once'))
                            error('ALEV4:InvalidSpatialMetadata','A high Unicode surrogate requires its low surrogate.');
                        end
                        low=hex2dec(text(position+8:position+11));
                        if low<hex2dec('DC00') || low>hex2dec('DFFF')
                            error('ALEV4:InvalidSpatialMetadata','Invalid Unicode surrogate pair.');
                        end
                        position=position+12;
                    elseif code>=hex2dec('DC00') && code<=hex2dec('DFFF')
                        error('ALEV4:InvalidSpatialMetadata','An unpaired low Unicode surrogate is invalid.');
                    else
                        position=position+6;
                    end
                else
                    position=position+2;
                end
            elseif text(position)=='"'
                closed=true; position=position+1; break;
            else
                position=position+1;
            end
        end
        if ~closed
            error('ALEV4:InvalidSpatialMetadata','Unterminated spatial JSON string.');
        end
        following=position;
        while following<=last && any(text(following)==[char(9) char(10) char(13) ' '])
            following=following+1;
        end
        if following<=last && text(following)==':'
            try
                decoded=jsondecode(['{"key":' text(first:position-1) '}']);
            catch err
                error('ALEV4:InvalidSpatialMetadata','Invalid JSON key: %s',err.message);
            end
            key=decoded.key;
            if ~ischar(key) || ~isrow(key) || ...
                    isempty(regexp(key,'^[A-Za-z][A-Za-z0-9_]{0,62}\z','once')) || ...
                    any(strcmp(key,keywords))
                error('ALEV4:InvalidSpatialMetadata','JSON keys must retain their exact portable field spelling.');
            end
        end
    end
end
