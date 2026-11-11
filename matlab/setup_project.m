function paths = setup_project()
%SETUP_PROJECT Put the two pinned ISET research dependencies on MATLAB's path.
% This only sets up dependencies; it does not emulate an ALEV4 sensor.
    root = fileparts(fileparts(mfilename('fullpath')));
    isetcam = fullfile(root, 'third_party', 'isetcam');
    hdrsensor = fullfile(root, 'third_party', 'isethdrsensor');

    if ~isfolder(fullfile(isetcam, 'sensor')) || ~isfolder(fullfile(hdrsensor, 'scripts'))
        error('ALEV4:MissingSubmodules', [ ...
            'Missing Git submodules. Run: git submodule update --init --recursive --depth 1']);
    end

    addpath(genpath(isetcam));
    addpath(genpath(hdrsensor));

    if exist('ieInit', 'file') ~= 2
        error('ALEV4:ISETCamNotOnPath', 'ISETCam ieInit was not found on the MATLAB path.');
    end

    paths = struct('root', root, 'isetcam', isetcam, 'isethdrsensor', hdrsensor);
    fprintf('ALEV4 research dependencies configured. No ALEV4 model has been calibrated.\n');
end
