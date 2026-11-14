function geometry = alexa35Geometry(cfa_pattern, active_roi)
%ALEXA35GEOMETRY Published Open Gate geometry with an assumed CFA origin.
%   The explicit CFA_PATTERN is a model choice, not published ARRI ordering.
%   Optional ACTIVE_ROI is an experimental crop, not a camera mode preset.
%   No spectral, electronic, optical, or calibration parameters are supplied.
%   See docs/PHASE3_SOURCES.md for source and rounding consistency.
    if nargin < 1
        error('ALEV4:AssumedCfaRequired', 'Explicitly choose the assumed full-grid Bayer pattern.');
    end
    if nargin < 2, active_roi = [1 1 3164 4608]; end
    geometry = alev4.createSensorGeometry(struct( ...
        'full_grid_size',[3164 4608], 'active_roi',active_roi, ...
        'pixel_pitch_m',6.075e-6, 'origin_xy_m',[0 0], ...
        'full_grid_cfa_pattern',cfa_pattern, ...
        'parameter_sources',{{'ARRI-A35-GEOMETRY','DERIVED-A35-EXTENT','ASSUMED-CFA-ORIGIN'}}));
end
