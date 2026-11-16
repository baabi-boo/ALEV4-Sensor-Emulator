function [result, metadata] = readStructuredBundle(directory)
%READSTRUCTUREDBUNDLE Read and verify a complete enabled Phase 4 result.
%   The first output is the original result, including all retained spatial
%   baseline fields and native double/uint16/logical classes and orientations.
%   Validation checks deterministic equations and observed-channel merging;
%   it neither recreates analog history nor resamples stochastic streams.
    if nargin~=1
        error('ALEV4:StructuredReadArguments','One bundle directory is required.');
    end
    caller_rng=rng;
    rng_guard=onCleanup(@()rng(caller_rng)); %#ok<NASGU>
    directory=alev4.structuredBundleUtil('path',directory);
    alev4.structuredBundleUtil('inventory',directory);
    identity=alev4.structuredBundleUtil('identity',directory,'directory');
    manifest_path=fullfile(directory,'structured.json');
    payload_path=fullfile(directory,'data.bin');
    before_manifest=alev4.structuredBundleUtil('snapshot',manifest_path);
    before_payload=alev4.structuredBundleUtil('snapshot',payload_path);
    [metadata,kinds]=alev4.spatialBundleUtil('readjson',manifest_path);
    alev4.structuredBundleUtil('manifest',metadata,kinds);
    [digest,byte_count]=alev4.spatialBundleUtil('hash',payload_path,metadata.payload.byte_count);
    if byte_count~=metadata.payload.byte_count || ~strcmp(digest,metadata.payload.sha256)
        error('ALEV4:StructuredHashMismatch','Payload size or SHA-256 differs from the manifest.');
    end
    [fid,message]=fopen(payload_path,'rb','ieee-le');
    if fid<0, error('ALEV4:StructuredRead','Cannot read payload: %s',message); end
    guard=onCleanup(@()closeQuietly(fid)); %#ok<NASGU>
    result=alev4.structuredBundleUtil('decode',metadata.result,kinds.result,fid,metadata.payload);
    if fclose(fid)~=0, error('ALEV4:StructuredRead','Closing the payload read failed.'); end
    result=alev4.structuredValidateResult(result);
    alev4.structuredBundleUtil('inventory',directory);
    if ~isequal(alev4.structuredBundleUtil('identity',directory,'directory'),identity) || ...
            ~isequal(alev4.structuredBundleUtil('snapshot',manifest_path),before_manifest) || ...
            ~isequal(alev4.structuredBundleUtil('snapshot',payload_path),before_payload)
        error('ALEV4:StructuredRead','Bundle identity or files changed during validation.');
    end
end

function closeQuietly(fid)
    try, fclose(fid); catch, end
end
