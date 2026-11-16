function varargout = structuredBundleUtil(action, varargin)
%STRUCTUREDBUNDLEUTIL Strict Phase 4 typed-tree wire and owned-file helpers.
%   The scientific schema belongs to structuredValidateResult. This helper
%   preserves every native field without resampling any random stream.
    switch action
        case 'path', varargout{1}=bundlePath(varargin{1});
        case 'identity', varargout{1}=fileIdentity(varargin{:});
        case 'snapshot', varargout{1}=fileSnapshot(varargin{1});
        case 'inventory', requireInventory(varargin{1});
        case 'removeowned', removeOwned(varargin{:});
        case 'encode', [varargout{1:nargout}]=encodeTree(varargin{1});
        case 'decode', varargout{1}=decodeTree(varargin{:});
        case 'manifest', validateManifest(varargin{:});
        case 'units', varargout{1}=leafUnits(varargin{:});
        otherwise, invalid('Unknown structured bundle utility action.');
    end
end

function path=bundlePath(path)
    if ~ischar(path) || ~isrow(path) || isempty(path) || ...
            any(path==char(0) | path==char(10) | path==char(13))
        invalid('Bundle directory must be a nonempty character row path.');
    end
    pieces=regexp(path,'[\\/]','split');
    if any(strcmp(pieces,'.') | strcmp(pieces,'..')) || ...
            any(cellfun(@isempty,pieces(2:end)))
        invalid('Dot segments and repeated or trailing separators are forbidden.');
    end
    absolute=path(1)==filesep || ~isempty(regexp(path,'^[A-Za-z]:[\\/]','once'));
    if ~absolute, path=fullfile(pwd,path); end
    [parent,stem,ext]=fileparts(path);
    if isempty([stem ext]), invalid('A named bundle directory is required.'); end
    while ~isempty(parent)
        alev4.spatialBundleUtil('directory',parent);
        next=fileparts(parent);
        if strcmp(next,parent), break; end
        parent=next;
    end
end

function identity=fileIdentity(path,kind)
    if strcmp(kind,'directory'), marker='d'; else, marker='-'; end
    alev4.spatialBundleUtil(kind,path);
    if exist('lstat','builtin') || exist('lstat','file')
        [info,status]=lstat(path);
        if status~=0 || isempty(info.modestr) || info.modestr(1)~=marker
            invalid('Cannot observe the declared ordinary file identity.');
        end
        if marker=='-' && info.nlink~=1
            invalid('Bundle files must have exactly one hard link.');
        end
        identity=struct('kind','lstat','device',info.dev,'inode',info.ino);
    elseif (exist('usejava','builtin') || exist('usejava','file')) && usejava('jvm')
        file=javaObject('java.io.File',path);
        options=javaArray('java.nio.file.LinkOption',1);
        options(1)=javaMethod('valueOf','java.nio.file.LinkOption','NOFOLLOW_LINKS');
        attributes=javaMethod('readAttributes','java.nio.file.Files',file.toPath(), ...
            'basic:fileKey',options);
        key=attributes.get('fileKey');
        if isempty(key), invalid('Filesystem does not expose a stable file identity.'); end
        if marker=='-'
            try
                links=javaMethod('getAttribute','java.nio.file.Files',file.toPath(), ...
                    'unix:nlink',options);
                link_count=double(links);
            catch
                invalid('This filesystem cannot verify single-link payload ownership.');
            end
            if link_count~=1, invalid('Bundle files must have exactly one hard link.'); end
        end
        identity=struct('kind','java_file_key','key',char(key.toString()));
    else
        invalid('Bundle identity checks require Octave lstat or a JVM file key.');
    end
end

function snapshot=fileSnapshot(path)
    snapshot=struct('identity',fileIdentity(path,'regular'));
    if exist('lstat','builtin') || exist('lstat','file')
        [info,status]=lstat(path);
        if status~=0, invalid('Bundle file disappeared.'); end
        snapshot.bytes=info.size; snapshot.modified=info.mtime;
        snapshot.changed=info.ctime;
    else
        file=javaObject('java.io.File',path);
        snapshot.bytes=double(file.length());
        snapshot.modified=double(file.lastModified());
    end
end

function requireInventory(directory)
    fileIdentity(directory,'directory');
    entries=dir(directory);
    names={entries.name}; names=names(~ismember(names,{'.','..'}));
    if ~isequal(sort(names),sort({'structured.json','data.bin'}))
        invalid('A structured bundle must contain exactly structured.json and data.bin.');
    end
    paths={fullfile(directory,'structured.json'),fullfile(directory,'data.bin')};
    for k=1:2, fileIdentity(paths{k},'regular'); end
    alev4.spatialBundleUtil('distinct',paths);
end

function removeOwned(directory,identity,paths,identities)
% Never recurse into unknown content or remove a substituted file/directory.
    if ~alev4.bundlePathExists(directory), return; end
    try
        if ~isequal(fileIdentity(directory,'directory'),identity), return; end
        for k=1:numel(paths)
            path=fullfile(directory,paths{k});
            if alev4.bundlePathExists(path) && ...
                    isequal(fileIdentity(path,'regular'),identities{k})
                delete(path);
            end
        end
        entries=dir(directory); names={entries.name};
        if all(ismember(names,{'.','..'}))
            [ok,message]=rmdir(directory);
            if ~ok, warning('ALEV4:StructuredCleanup','Owned cleanup failed: %s',message); end
        else
            warning('ALEV4:StructuredCleanup','Unknown or changed stage entries were preserved.');
        end
    catch observed
        warning('ALEV4:StructuredCleanup','Owned cleanup could not proceed: %s',observed.message);
    end
end

function [tree,leaves,byte_count,sample_count]=encodeTree(value)
    leaves={}; byte_count=0; sample_count=0; nodes=0;
    tree=encodeNode(value,'result',0);
    function node=encodeNode(item,path,depth)
        nodes=nodes+1; requireTreeBound(depth,nodes);
        if isstruct(item) && isscalar(item)
            names=fieldnames(item);
            if numel(names)>256, invalid('Typed structs support at most 256 fields.'); end
            fields=struct();
            for j=1:numel(names)
                fields.(names{j})=encodeNode(item.(names{j}),[path '.' names{j}],depth+1);
            end
            node=struct('kind','struct','fields',fields);
        elseif iscell(item)
            shape=double(size(item)); validateShape(shape);
            if numel(item)>256, invalid('Typed cells support at most 256 items.'); end
            items=struct();
            for j=1:numel(item)
                key=sprintf('i%06d',j);
                items.(key)=encodeNode(item{j},[path '.' key],depth+1);
            end
            node=struct('kind','cell','shape',shape,'items',items);
        elseif ischar(item) && (isempty(item) || isrow(item)) && ismatrix(item)
            if any(item==char(0)), invalid('Character data must not contain NUL.'); end
            node=struct('kind','char','shape',double(size(item)),'value',item);
        elseif any(strcmp(class(item),{'double','uint16','logical'})) && ...
                isreal(item) && ~issparse(item)
            shape=double(size(item)); count=validateShape(shape);
            if any(~isfinite(item(:))), invalid('Numerical data must be finite.'); end
            sample_count=sample_count+count;
            if sample_count>1e8, invalid('Bundle exceeds 100 million numerical samples.'); end
            bytes=count*classBytes(class(item));
            node=struct('kind','numeric','class',class(item),'shape',shape, ...
                'offset',byte_count,'byte_count',bytes,'units',leafUnits(path,class(item)));
            byte_count=byte_count+bytes;
            leaves{end+1}=item;
        else
            invalid('Typed tree contains an unsupported native type or shape.');
        end
    end
end

function value=decodeTree(tree,kinds,fid,payload)
    offset=0; samples=0; nodes=0;
    value=decodeNode(tree,kinds,'result',0);
    if offset~=payload.byte_count || samples~=payload.sample_count
        invalid('Payload totals disagree with the complete typed tree.');
    end
    trailing=fread(fid,1,'*uint8');
    [message,status]=ferror(fid);
    if ~isempty(trailing) || status~=0
        error('ALEV4:StructuredRead','Unexpected payload bytes or read failure: %s',message);
    end
    function item=decodeNode(node,node_kinds,path,depth)
        nodes=nodes+1; requireTreeBound(depth,nodes);
        if ~isstruct(node) || ~isscalar(node) || ~isfield(node,'kind') || ...
                ~isstruct(node_kinds) || ~isfield(node_kinds,'kind') || ...
                ~isequal(node_kinds.kind,'text')
            invalid('Every typed node requires a string kind.');
        end
        switch node.kind
            case 'struct'
                fields(node,{'kind','fields'},'struct node');
                if ~isstruct(node.fields) || ~isscalar(node.fields) || ...
                        ~isstruct(node_kinds.fields)
                    invalid('Struct fields must be a JSON object.');
                end
                names=fieldnames(node.fields);
                if numel(names)>256, invalid('Typed structs support at most 256 fields.'); end
                item=struct();
                for j=1:numel(names)
                    name=names{j};
                    item.(name)=decodeNode(node.fields.(name),node_kinds.fields.(name), ...
                        [path '.' name],depth+1);
                end
            case 'cell'
                fields(node,{'kind','shape','items'},'cell node');
                shape=wireShape(node.shape,node_kinds.shape); count=validateShape(shape);
                if count>256 || ~isstruct(node.items) || ~isscalar(node.items) || ...
                        ~isstruct(node_kinds.items)
                    invalid('Invalid bounded cell items.');
                end
                names=fieldnames(node.items); expected=cell(count,1);
                for j=1:count, expected{j}=sprintf('i%06d',j); end
                if ~isequal(names,expected), invalid('Cell item keys must be contiguous and ordered.'); end
                item=cell(shape);
                for j=1:count
                    key=expected{j};
                    item{j}=decodeNode(node.items.(key),node_kinds.items.(key),[path '.' key],depth+1);
                end
            case 'char'
                fields(node,{'kind','shape','value'},'character node');
                shape=wireShape(node.shape,node_kinds.shape);
                if numel(shape)~=2 || ~isequal(node_kinds.value,'text') || ...
                        numel(node.value)~=prod(shape) || ...
                        (~isempty(node.value) && shape(1)~=1)
                    invalid('Character shape and JSON text disagree.');
                end
                item=reshape(node.value,shape);
            case 'numeric'
                fields(node,{'kind','class','shape','offset','byte_count','units'},'numeric node');
                if ~isequal(node_kinds.class,'text') || ~isequal(node_kinds.units,'text')
                    invalid('Numeric class and units must be JSON strings.');
                end
                shape=wireShape(node.shape,node_kinds.shape); count=validateShape(shape);
                bytes=count*classBytes(node.class);
                integer(node.offset,node_kinds.offset,0,800000000,'offset');
                integer(node.byte_count,node_kinds.byte_count,0,800000000,'byte count');
                if node.offset~=offset || node.byte_count~=bytes || ...
                        offset+bytes>payload.byte_count || samples+count>payload.sample_count
                    invalid('Numerical payload offsets or lengths are inconsistent.');
                end
                textEqual(node.units,leafUnits(path,node.class),'numerical units');
                switch node.class
                    case 'double', precision='*double';
                    case 'uint16', precision='*uint16';
                    case 'logical', precision='*uint8';
                end
                [flat,actual]=fread(fid,count,precision);
                if actual~=count || any(~isfinite(flat))
                    invalid('Numerical payload is truncated or nonfinite.');
                end
                if strcmp(node.class,'logical')
                    if any(flat~=0 & flat~=1), invalid('Logical payload bytes must be zero or one.'); end
                    flat=logical(flat);
                end
                item=permute(reshape(flat,fliplr(shape)),numel(shape):-1:1);
                if ~isequal(size(item),shape) || ~strcmp(class(item),node.class)
                    invalid('Typed reconstruction changed its class or shape.');
                end
                offset=offset+bytes; samples=samples+count;
            otherwise
                invalid('Unknown typed node kind.');
        end
    end
end

function validateManifest(meta,kinds)
    fields(meta,{'format','schema_version','wire_version','byte_order','array_order', ...
        'synthetic','calibrated_alev4','authentic_arriraw','parameter_classification', ...
        'provenance','payload','result'},'manifest');
    literal={'format','ALEV4-SYNTHETIC-STRUCTURED-NOISE';'schema_version','1.0'; ...
        'wire_version','typed-tree-v1';'byte_order','little-endian'; ...
        'array_order','row-major';'parameter_classification','assumed'};
    for k=1:size(literal,1)
        name=literal{k,1};
        if ~isequal(kinds.(name),'text'), invalid('Manifest literals must be JSON strings.'); end
        textEqual(meta.(name),literal{k,2},name);
    end
    flags={'synthetic','calibrated_alev4','authentic_arriraw'}; expected=[true false false];
    for k=1:3
        if ~isequal(kinds.(flags{k}),'boolean') || ~isequal(meta.(flags{k}),expected(k))
            invalid('Synthetic/calibration declarations are inconsistent.');
        end
    end
    fields(meta.provenance,{'repository_head','isetcam_head','isethdrsensor_head','meaning'},'provenance');
    names={'repository_head','isetcam_head','isethdrsensor_head'};
    for k=1:numel(names)
        value=meta.provenance.(names{k});
        if ~isequal(kinds.provenance.(names{k}),'text') || ...
                (~isempty(value) && isempty(regexp(value,'^[0-9a-f]{40}$','once')))
            invalid('Observed source revisions must be empty or lowercase SHA-1 text.');
        end
    end
    meaning=['Observed Git HEADs; an empty value means unavailable. ' ...
        'Uncommitted edits, object existence and agreement with dependency gitlinks ' ...
        'are not established by these metadata observations.'];
    if ~isequal(kinds.provenance.meaning,'text'), invalid('Provenance meaning must be text.'); end
    textEqual(meta.provenance.meaning,meaning,'provenance meaning');
    fields(meta.payload,{'name','byte_count','sample_count','sha256'},'payload');
    if ~isequal(kinds.payload.name,'text') || ~isequal(kinds.payload.sha256,'text')
        invalid('Payload name and hash must be strings.');
    end
    textEqual(meta.payload.name,'data.bin','payload name');
    integer(meta.payload.byte_count,kinds.payload.byte_count,0,800000000,'payload byte count');
    integer(meta.payload.sample_count,kinds.payload.sample_count,0,1e8,'payload sample count');
    if isempty(regexp(meta.payload.sha256,'^[0-9a-f]{64}$','once'))
        invalid('Payload SHA-256 must be lowercase hexadecimal.');
    end
    if ~isstruct(meta.result) || ~isscalar(meta.result)
        invalid('The result must be a typed object.');
    end
end

function shape=wireShape(shape,kind)
    if ~isequal(kind,'vector'), invalid('Shape must be a JSON numeric vector.'); end
    validateShape(shape); shape=double(shape(:).');
end

function count=validateShape(shape)
    if ~isa(shape,'double') || ~isreal(shape) || ~isvector(shape) || ...
            ~any(numel(shape)==[2 3]) || any(~isfinite(shape(:))) || ...
            any(shape(:)<0 | shape(:)>1e8 | shape(:)~=fix(shape(:))) || ...
            (numel(shape)==3 && shape(end)==1)
        invalid('Shape must be the canonical two- or three-dimensional native size.');
    end
    bound=1;
    for k=1:numel(shape)
        if shape(k)>0
            if shape(k)>1e8/bound, invalid('Array shape exceeds the numerical sample bound.'); end
            bound=bound*shape(k);
        end
    end
    count=prod(shape);
end

function bytes=classBytes(name)
    switch name
        case 'double', bytes=8;
        case 'uint16', bytes=2;
        case 'logical', bytes=1;
        otherwise, invalid('Only double, uint16 and logical numerical classes are supported.');
    end
end

function units=leafUnits(path,native_class)
    pieces=regexp(path,'\.','split'); name=pieces{end};
    if numel(pieces)>1, parent=pieces{end-1}; else, parent=''; end
    if any(strcmp(pieces,'spatial_provenance')), units='metadata';
    elseif strcmp(native_class,'logical'), units='logical';
    elseif any(strcmp(name,{'input_irradiance','optical_irradiance','sampled_irradiance'}))
        units='photons m^-2 s^-1 nm^-1';
    elseif strcmp(name,'expected_incident_photons'), units='photons';
    elseif strcmp(name,'dark_current_e_per_s'), units='electrons s^-1';
    elseif strcmp(name,'gain_dn_per_e'), units='DN electron^-1';
    elseif any(strcmp(name,{'raw_dn','black_level_dn'})), units='DN';
    elseif ~isempty(regexp(name,'(electrons|_e)$','once')), units='electrons';
    elseif ~isempty(regexp(name,'_m$','once')), units='m';
    elseif ~isempty(regexp(name,'_nm$','once')), units='nm';
    elseif strcmp(name,'reference_temperature_K'), units='K';
    elseif strcmp(name,'exposure_s'), units='s';
    elseif strcmp(name,'seed') || strcmp(parent,'seeds'), units='seed';
    elseif strcmp(name,'values') && any(strcmp(parent, ...
            {'source_integral','source_crop_integral','target_integral'}))
        units='photons s^-1 nm^-1';
    elseif strcmp(name,'adc_bits'), units='bits';
    elseif any(strcmp(name,{'image_size','full_grid_size','active_roi', ...
            'source_image_size','output_image_size','origin_rc','retained_row_indices', ...
            'retained_column_indices','required_halo_top_bottom_left_right', ...
            'kernel_shape','input_shape','output_shape','spectral_plane_count', ...
            'x_weight_nonzeros','y_weight_nonzeros'})), units='index/count';
    else, units='dimensionless';
    end
end

function requireTreeBound(depth,nodes)
    if depth>24 || nodes>20000, invalid('Typed tree exceeds its depth or node bound.'); end
end

function fields(value,names,label)
    alev4.spatialBundleUtil('fields',value,names,label);
end

function integer(value,kind,low,high,label)
    if ~isequal(kind,'number'), invalid([label ' must be a JSON number.']); end
    alev4.spatialBundleUtil('scalar',value,low,high,true,label);
end

function textEqual(value,expected,label)
    alev4.spatialBundleUtil('text',value,expected,label);
end

function invalid(message)
    error('ALEV4:InvalidStructuredBundle','%s',message);
end
