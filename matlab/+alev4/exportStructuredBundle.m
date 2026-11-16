function files = exportStructuredBundle(result, directory)
%EXPORTSTRUCTUREDBUNDLE Archive one complete, validated enabled result.
%   FILES = alev4.exportStructuredBundle(RESULT,DIRECTORY) requires a fresh
%   destination and an existing ordinary parent directory. All result fields,
%   including legacy spatial analog history, retain their types and shapes.
%   Numeric arrays use contiguous little-endian C row-major payloads. The
%   manifest is written last, native readback verifies the owned stage, and a
%   directory rename publishes it. Concurrent writers are unsupported.
    if nargin~=2
        error('ALEV4:StructuredExportArguments','Complete result and directory are required.');
    end
    caller_rng=rng;
    rng_guard=onCleanup(@()rng(caller_rng)); %#ok<NASGU>
    directory=alev4.structuredBundleUtil('path',directory);
    refuseExisting(directory);
    result=alev4.structuredValidateResult(result);
    [tree,leaves,byte_count,sample_count]=alev4.structuredBundleUtil('encode',result);
    meta=struct('format','ALEV4-SYNTHETIC-STRUCTURED-NOISE','schema_version','1.0', ...
        'wire_version','typed-tree-v1','byte_order','little-endian','array_order','row-major', ...
        'synthetic',true,'calibrated_alev4',false,'authentic_arriraw',false, ...
        'parameter_classification','assumed','provenance',alev4.sourceProvenance(), ...
        'payload',struct('name','data.bin','byte_count',byte_count, ...
            'sample_count',sample_count,'sha256',repmat('0',1,64)), ...
        'result',tree);
    % Check portable JSON, size and descriptor syntax before creating files.
    [checked,kinds]=alev4.spatialDecodeJson(alev4.encodeBundleJson(meta));
    alev4.structuredBundleUtil('manifest',checked,kinds);
    parent=fileparts(directory);
    staging=[tempname(parent) '.structured-stage'];
    refuseExisting(staging);
    [ok,message]=mkdir(staging);
    if ~ok || ~isempty(message)
        error('ALEV4:StructuredWrite','Cannot create an owned stage: %s',message);
    end
    identity=alev4.structuredBundleUtil('identity',staging,'directory');
    owned_names={}; owned_identities={};
    cleanup_path=staging;
    fid=-1;
    % A nested onCleanup callback can retain its own shared workspace in
    % Octave, delaying both handle closure and stage removal indefinitely.
    % Keep ownership values local and perform failure cleanup explicitly.
    try
        payload_path=fullfile(staging,'data.bin');
        [fid,file_identity]=openOwned(staging,identity,'data.bin');
        owned_names{end+1}='data.bin'; owned_identities{end+1}=file_identity;
        total=0;
        for k=1:numel(leaves)
            values=leaves{k}; precision=class(values);
            if strcmp(precision,'logical'), precision='uint8'; end
            total=total+fwrite(fid,permute(values,ndims(values):-1:1),precision);
        end
        [message,status]=ferror(fid);
        closed=fclose(fid); if closed==0, fid=-1; end
        if total~=sample_count || status~=0 || closed~=0
            error('ALEV4:StructuredWrite','Incomplete numerical payload write: %s',message);
        end
        [meta.payload.sha256,actual_bytes]=alev4.spatialBundleUtil('hash',payload_path,byte_count);
        if actual_bytes~=byte_count
            error('ALEV4:StructuredWrite','Payload bytes disagree with its typed descriptors.');
        end
        manifest_bytes=unicode2native([alev4.encodeBundleJson(meta) sprintf('\n')],'UTF-8');
        if numel(manifest_bytes)>2000000
            error('ALEV4:StructuredWrite','Manifest exceeds 2,000,000 bytes.');
        end
        [fid,file_identity]=openOwned(staging,identity,'structured.json');
        owned_names{end+1}='structured.json'; owned_identities{end+1}=file_identity;
        count=fwrite(fid,manifest_bytes,'uint8');
        [message,status]=ferror(fid); closed=fclose(fid); if closed==0, fid=-1; end
        if count~=numel(manifest_bytes) || status~=0 || closed~=0
            error('ALEV4:StructuredWrite','Incomplete manifest write: %s',message);
        end
        decoded=alev4.readStructuredBundle(staging);
        if ~isequal(decoded,result)
            error('ALEV4:StructuredWrite','Complete structured result failed exact staged readback.');
        end
        alev4.structuredBundleUtil('path',directory);
        refuseExisting(directory);
        [ok,message]=movefile(staging,directory);
        if ~ok, error('ALEV4:StructuredWrite','Cannot publish structured bundle: %s',message); end
        [~,stem,ext]=fileparts(staging);
        nested=fullfile(directory,[stem ext]);
        if alev4.bundlePathExists(nested)
            alev4.structuredBundleUtil('removeowned',nested,identity,owned_names,owned_identities);
            error('ALEV4:StructuredWrite','A concurrent destination caused nested publication.');
        end
        cleanup_path=directory;
        if alev4.bundlePathExists(staging) || ...
                ~isequal(alev4.structuredBundleUtil('identity',directory,'directory'),identity)
            error('ALEV4:StructuredWrite','Publication did not preserve the owned directory.');
        end
        alev4.structuredBundleUtil('inventory',directory);
        files=struct('directory',directory,'metadata',fullfile(directory,'structured.json'), ...
            'payload',fullfile(directory,'data.bin'));
    catch observed
        closeQuietly(fid);
        try
            alev4.structuredBundleUtil('removeowned',cleanup_path,identity,owned_names,owned_identities);
        catch
            % A cleanup warning promoted to an error must not hide the
            % original failure or permit removal of an unverified identity.
        end
        rethrow(observed);
    end
end

function [fid,file_identity]=openOwned(staging,identity,name)
    if ~isequal(alev4.structuredBundleUtil('identity',staging,'directory'),identity)
        error('ALEV4:StructuredWrite','Staging directory identity changed.');
    end
    path=fullfile(staging,name); refuseExisting(path);
    [fid,message]=fopen(path,'wb','ieee-le');
    if fid<0, error('ALEV4:StructuredWrite','Cannot create owned file: %s',message); end
    try
        file_identity=alev4.structuredBundleUtil('identity',path,'regular');
    catch observed
        closeQuietly(fid);
        rethrow(observed);
    end
end

function refuseExisting(path)
    if alev4.bundlePathExists(path)
        error('ALEV4:StructuredAlreadyExists','Refusing to overwrite an existing structured bundle path.');
    end
end

function closeQuietly(fid)
    try, fclose(fid); catch, end
end
