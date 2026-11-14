function varargout = spatialBundleUtil(action, varargin)
%SPATIALBUNDLEUTIL Internal strict, bounded I/O for the Phase 3 wire format.
%   File identity requires Octave lstat or a MATLAB JVM. Missing support is
%   an explicit error. Existing Phase 1/2 serialization is not modified.
    switch action
        case 'fields'
            requireFields(varargin{:});
        case 'text'
            requireText(varargin{:});
        case 'boolean'
            requireBoolean(varargin{:});
        case 'scalar'
            requireScalar(varargin{:});
        case 'shape'
            varargout{1} = validateShape(varargin{:});
        case 'path'
            varargout{1} = validatePath(varargin{1});
        case 'regular'
            requireEntry(varargin{1}, '-');
        case 'directory'
            requireEntry(varargin{1}, 'd');
        case 'distinct'
            requireDistinct(varargin{1});
        case 'readjson'
            [varargout{1:nargout}] = readJson(varargin{1});
        case 'writejson'
            writeJson(varargin{:});
        case 'readplane'
            varargout{1} = readPlane(varargin{:});
        case 'writeplane'
            writePlane(varargin{:});
        case 'hash'
            [varargout{1:nargout}] = hashFile(varargin{:});
        case 'listencode'
            varargout{1} = listEncode(varargin{:});
        case 'listdecode'
            varargout{1} = listDecode(varargin{:});
        case 'close'
            assertClose(varargin{:});
        case 'equalmeta'
            equalMetadata(varargin{:});
        case 'runtime'
            if exist('OCTAVE_VERSION','builtin')
                varargout{1}=struct('name','GNU Octave','version',OCTAVE_VERSION);
            else
                varargout{1}=struct('name','MATLAB','version',version);
            end
        otherwise
            error('ALEV4:SpatialInternal', 'Unknown spatial utility action.');
    end
end

function requireFields(value,names,label)
    if ~isstruct(value) || ~isscalar(value) || ...
            ~isequal(sort(fieldnames(value)),sort(names(:)))
        error('ALEV4:InvalidSpatialMetadata','%s must have exactly the declared fields.',label);
    end
end

function requireText(value,expected,label)
    if ~ischar(value) || ~isrow(value) || ~strcmp(value,expected)
        error('ALEV4:InvalidSpatialMetadata','Invalid %s.',label);
    end
end

function requireBoolean(value,expected,label)
    if ~islogical(value) || ~isscalar(value) || value~=expected
        error('ALEV4:InvalidSpatialMetadata','Invalid %s.',label);
    end
end

function requireScalar(value,low,high,integer,label)
    if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
            ~isfinite(value) || value<low || value>high || ...
            (integer && value~=fix(value))
        error('ALEV4:InvalidSpatialMetadata','Invalid %s.',label);
    end
end

function shape=validateShape(shape,rank)
    if ~isnumeric(shape) || ~isreal(shape) || ~isvector(shape) || ...
            numel(shape)~=rank || any(~isfinite(shape(:))) || ...
            any(shape(:)<1 | shape(:)~=fix(shape(:)))
        error('ALEV4:InvalidSpatialMetadata','Invalid payload shape.');
    end
    shape=full(double(shape(:).'));
    count=1;
    for k=1:numel(shape)
        if shape(k)>1e8/count
            error('ALEV4:InvalidSpatialMetadata','Spatial payload exceeds 100 million samples.');
        end
        count=count*shape(k);
    end
end

function path=validatePath(path)
    if ~ischar(path) || ~isrow(path) || isempty(path) || any(path==char(0))
        error('ALEV4:InvalidSpatialPath','Bundle directory must be a nonempty character row.');
    end
    while numel(path)>1 && (path(end)=='/' || path(end)==filesep)
        path(end)=[];
    end
    [parent,stem,ext]=fileparts(path);
    stem=[stem ext];
    if isempty(stem) || any(strcmp(stem,{'.','..'}))
        error('ALEV4:InvalidSpatialPath','A named bundle directory is required.');
    end
    if isempty(parent), path=fullfile('.',path); end
end

function tf=hasLstat()
    tf=exist('lstat','builtin')~=0 || exist('lstat','file')~=0;
end

function tf=hasJava()
    tf=(exist('usejava','builtin')~=0 || exist('usejava','file')~=0) && usejava('jvm');
end

function requireEntry(path,kind)
    if hasLstat()
        [info,status]=lstat(path);
        if status~=0 || isempty(info.modestr) || info.modestr(1)~=kind
            error('ALEV4:SpatialBundleMissing','Bundle entries must have their declared regular type, never symlinks.');
        end
    elseif hasJava()
        f=javaObject('java.io.File',path);
        if javaMethod('isSymbolicLink','java.nio.file.Files',f.toPath()) || ...
                (kind=='-' && ~f.isFile()) || (kind=='d' && ~f.isDirectory())
            error('ALEV4:SpatialBundleMissing','Bundle entries must have their declared regular type, never symlinks.');
        end
    else
        error('ALEV4:SpatialFileIdentityUnsupported','Spatial bundle I/O needs lstat or a JVM for explicit file identity checks.');
    end
end

function requireDistinct(paths)
    for k=1:numel(paths)
        requireEntry(paths{k},'-');
        if hasLstat()
            [info,status]=lstat(paths{k});
            if status~=0, error('ALEV4:SpatialBundleMissing','Payload disappeared.'); end
            for j=1:k-1
                [other,status]=lstat(paths{j});
                if status~=0 || (isequal(info.dev,other.dev) && isequal(info.ino,other.ino))
                    error('ALEV4:InvalidSpatialMetadata','Spatial bundle files must not alias.');
                end
            end
        else
            current=javaObject('java.io.File',paths{k});
            for j=1:k-1
                other=javaObject('java.io.File',paths{j});
                if javaMethod('isSameFile','java.nio.file.Files',current.toPath(),other.toPath())
                    error('ALEV4:InvalidSpatialMetadata','Spatial bundle files must not alias.');
                end
            end
        end
    end
end

function [value,kinds]=readJson(path)
    requireEntry(path,'-');
    [fid,message]=fopen(path,'rb');
    if fid<0, error('ALEV4:SpatialReadFailed','Cannot open manifest: %s',message); end
    guard=onCleanup(@()closeQuietly(fid)); %#ok<NASGU>
    bytes=fread(fid,2000001,'*uint8');
    [message,err]=ferror(fid);
    if err~=0 || numel(bytes)<2 || numel(bytes)>2000000
        error('ALEV4:InvalidSpatialMetadata','Invalid manifest size/read: %s',message);
    end
    closeRead(fid);
    value_text=native2unicode(bytes.','UTF-8');
    restored=unicode2native(value_text,'UTF-8');
    if ~isequal(restored(:),bytes(:))
        error('ALEV4:InvalidSpatialMetadata','Manifest must contain valid UTF-8.');
    end
    [value,kinds]=alev4.spatialDecodeJson(value_text);
end

function writeJson(path,value)
    text=alev4.encodeBundleJson(value);
    bytes=unicode2native([text sprintf('\n')],'UTF-8');
    if numel(bytes)>2000000
        error('ALEV4:InvalidSpatialMetadata','Manifest exceeds 2,000,000 bytes.');
    end
    writePlane(path,bytes(:).','uint8');
end

function values=readPlane(path,shape,type)
    rank=numel(shape);
    shape=validateShape(shape,rank);
    if ~any(rank==[2 3]), error('ALEV4:InvalidSpatialMetadata','Payload rank must be two or three.'); end
    switch type
        case 'float64', precision='*double'; bytes=8;
        case 'uint16', precision='*uint16'; bytes=2;
        case 'uint8', precision='*uint8'; bytes=1;
        otherwise, error('ALEV4:InvalidSpatialMetadata','Unsupported payload type.');
    end
    requireEntry(path,'-');
    [fid,message]=fopen(path,'rb','ieee-le');
    if fid<0, error('ALEV4:SpatialReadFailed','Cannot read payload: %s',message); end
    guard=onCleanup(@()closeQuietly(fid)); %#ok<NASGU>
    n=prod(shape);
    if fseek(fid,0,'eof')~=0 || ftell(fid)~=n*bytes || fseek(fid,0,'bof')~=0
        error('ALEV4:SpatialSizeMismatch','Payload length differs from the declared shape.');
    end
    [flat,count]=fread(fid,n,precision);
    trailing=fread(fid,1,'*uint8');
    [message,err]=ferror(fid);
    if count~=n || ~isempty(trailing) || err~=0
        error('ALEV4:SpatialSizeMismatch','Incomplete or changed payload: %s',message);
    end
    closeRead(fid);
    if rank==2
        values=reshape(flat,shape(2),shape(1)).';
    else
        values=permute(reshape(flat,shape(2),shape(1),shape(3)),[2 1 3]);
    end
end

function writePlane(path,values,type)
    [fid,message]=fopen(path,'wb','ieee-le');
    if fid<0, error('ALEV4:SpatialWriteFailed','Cannot create payload: %s',message); end
    guard=onCleanup(@()closeQuietly(fid)); %#ok<NASGU>
    total=0;
    for k=1:size(values,3)
        plane=values(:,:,k);
        total=total+fwrite(fid,plane.',type);
    end
    [message,err]=ferror(fid);
    status=fclose(fid);
    if total~=numel(values) || err~=0 || status~=0
        error('ALEV4:SpatialWriteFailed','Incomplete payload write: %s',message);
    end
end

function [digest,count]=hashFile(path,limit)
    if nargin<2, limit=800000000; end
    requireScalar(limit,0,800000000,true,'hash byte limit');
    requireEntry(path,'-');
    [fid,message]=fopen(path,'rb');
    if fid<0, error('ALEV4:SpatialReadFailed','Cannot hash payload: %s',message); end
    guard=onCleanup(@()closeQuietly(fid)); %#ok<NASGU>
    if exist('hash','builtin')~=0
        bytes=fread(fid,limit+1,'*uint8');
        count=numel(bytes);
        if count>limit, error('ALEV4:SpatialSizeMismatch','Payload exceeds its bounded hash read.'); end
        digest=lower(hash('sha256',char(bytes.')));
    elseif hasJava()
        md=javaMethod('getInstance','java.security.MessageDigest','SHA-256');
        count=0;
        while true
            bytes=fread(fid,min(1048576,limit-count+1),'*uint8');
            count=count+numel(bytes);
            if count>limit, error('ALEV4:SpatialSizeMismatch','Payload exceeds its bounded hash read.'); end
            if isempty(bytes), break; end
            md.update(typecast(bytes(:),'int8'));
        end
        raw=typecast(int8(md.digest()),'uint8');
        digest=lower(reshape(dec2hex(raw,2).',1,[]));
    else
        error('ALEV4:SpatialHashUnsupported','SHA-256 needs Octave hash or a JVM.');
    end
    [message,err]=ferror(fid);
    if err~=0, error('ALEV4:SpatialReadFailed','Hash read failed: %s',message); end
    closeRead(fid);
end

function result=listEncode(list,prefix)
    if ~iscell(list) || ~isvector(list) || isempty(list) || numel(list)>256
        error('ALEV4:InvalidSpatialMetadata','A nonempty bounded list is required.');
    end
    result=struct();
    for k=1:numel(list)
        value=list{k};
        if ~ischar(value) || ~isrow(value) || isempty(value) || any(value==char(0))
            error('ALEV4:InvalidSpatialMetadata','List entries must be nonempty strings.');
        end
        result.(sprintf('%s%03d',prefix,k))=value;
    end
end

function result=listDecode(value,prefix)
    if ~isstruct(value) || ~isscalar(value) || isempty(fieldnames(value))
        error('ALEV4:InvalidSpatialMetadata','A nonempty keyed list is required.');
    end
    names=fieldnames(value);
    result=cell(1,numel(names));
    expected=cell(size(names));
    for k=1:numel(names)
        expected{k}=sprintf('%s%03d',prefix,k);
        if ~isfield(value,expected{k})
            error('ALEV4:InvalidSpatialMetadata','Keyed lists must have contiguous declared keys.');
        end
        text=value.(expected{k});
        if ~ischar(text) || ~isrow(text) || isempty(text) || any(text==char(0))
            error('ALEV4:InvalidSpatialMetadata','Keyed list values must be nonempty strings.');
        end
        result{k}=text;
    end
    if ~isequal(sort(names),sort(expected)) || numel(unique(result))~=numel(result)
        error('ALEV4:InvalidSpatialMetadata','Keyed list contains foreign keys or duplicate values.');
    end
end

function assertClose(actual,expected,operations,label)
    if ~isnumeric(actual) || ~isreal(actual) || ~isequal(size(actual),size(expected)) || ...
            any(~isfinite(actual(:))) || any(sign(actual(:))~=sign(expected(:)))
        error('ALEV4:SpatialSemanticMismatch','Invalid %s shape, sign, or numerical values.',label);
    end
    % The reference alone sets the bound; modified payload magnitude cannot
    % widen it. Exact zero and positive/nonzero association remain exact.
    tolerance=64*max(1,operations)*eps(abs(expected));
    if any(abs(double(actual(:))-expected(:))>tolerance(:))
        error('ALEV4:SpatialSemanticMismatch','%s disagrees with recomputed values.',label);
    end
end

function equalMetadata(actual,expected,label)
    if isstruct(expected)
        requireFields(actual,fieldnames(expected),label);
        names=fieldnames(expected);
        for k=1:numel(names), equalMetadata(actual.(names{k}),expected.(names{k}),label); end
    elseif isnumeric(expected)
        if ~isnumeric(actual) || ~isreal(actual) || any(~isfinite(actual(:))) || ...
                numel(actual)~=numel(expected) || ...
                (~isvector(expected) && ~isempty(expected) && ~isequal(size(actual),size(expected))) || ...
                any(sign(actual(:))~=sign(expected(:))) || ...
                any(abs(double(actual(:))-double(expected(:)))>8*eps(abs(double(expected(:)))))
            error('ALEV4:InvalidSpatialMetadata','%s metadata disagree.',label);
        end
    elseif iscell(expected)
        if ~iscell(actual) || ~isequal(actual,expected)
            error('ALEV4:InvalidSpatialMetadata','%s list metadata disagree.',label);
        end
    elseif ~isequal(actual,expected)
        error('ALEV4:InvalidSpatialMetadata','%s metadata disagree.',label);
    end
end

function closeQuietly(fid)
    try, fclose(fid); catch, end
end

function closeRead(fid)
    if fclose(fid)~=0
        error('ALEV4:SpatialReadFailed','Closing a spatial bundle read failed.');
    end
end
