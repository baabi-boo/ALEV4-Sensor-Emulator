function paths = setup_project(require_upstream)
%SETUP_PROJECT Configure the core and optional pinned research dependencies.
%   setup_project() enables ISETCam/ISETHdrsensor without opening any GUI.
%   setup_project(false) enables only the standalone numerical core/tests.
%   No ARRI sensor calibration is performed by this function.
    if nargin < 1, require_upstream = true; end
    if ~islogical(require_upstream) || ~isscalar(require_upstream)
        error('ALEV4:InvalidSetupMode', 'require_upstream must be a logical scalar.');
    end
    root = fileparts(fileparts(mfilename('fullpath')));
    isetcam = fullfile(root, 'third_party', 'isetcam');
    hdrsensor = fullfile(root, 'third_party', 'isethdrsensor');

    if require_upstream && (~isfolder(fullfile(isetcam, 'sensor')) || ~isfolder(fullfile(hdrsensor, 'scripts')))
        error('ALEV4:MissingSubmodules', [ ...
            'Missing Git submodules. Run: git submodule update --init --recursive --depth 1']);
    end

    if require_upstream
        addpath(genpath(isetcam), '-end');
        addpath(genpath(hdrsensor), '-end');
    end
    addpath(fullfile(root, 'matlab'));
    addpath(fullfile(root, 'matlab', 'tests'));
    addpath(fullfile(root, 'matlab', 'examples'));

    if require_upstream && exist('ieInitSession', 'file') ~= 2
        error('ALEV4:ISETCamNotOnPath', 'ISETCam ieInitSession was not found on the path.');
    end
    if require_upstream
        required = {'ieInitSession', 'ieSessionSet', 'sceneCreate', 'sceneGet', ...
            'sceneSet', 'oiCreate', 'oiSet', 'oiCompute', 'oiGet', ...
            'pixelCreate', 'pixelGet', 'sensorCreate', 'sensorSet', ...
            'sensorGet', 'sensorCompute'};
        prefix = [isetcam filesep];
        for k = 1:numel(required)
            resolved = which(required{k});
            if ~strncmp(resolved, prefix, numel(prefix))
                error('ALEV4:ISETPathConflict', ...
                    '%s resolves outside the pinned ISETCam checkout: %s', required{k}, resolved);
            end
        end
    end

    paths = struct('root', root, 'isetcam', isetcam, 'isethdrsensor', hdrsensor, ...
        'upstream_enabled', require_upstream);
end

