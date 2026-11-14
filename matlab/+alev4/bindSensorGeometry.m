function bound = bindSensorGeometry(readout, geometry, mode)
%BINDSENSORGEOMETRY Derive spatial fields or validate an existing binding.
%   MODE is explicitly 'derive' or 'validate'. Input must be a complete
%   validated single-gain (1.0) or dual-gain (2.0) configuration. Callers keep
%   their original structures; only size, pitch, and CFA can be replaced.
    if nargin ~= 3 || ~ischar(mode) || ~isrow(mode) || ...
            ~any(strcmp(mode, {'derive','validate'}))
        error('ALEV4:InvalidGeometryBinding', 'Explicit derive or validate mode is required.');
    end
    geometry = alev4.createSensorGeometry(geometry);
    if ~isstruct(readout) || ~isscalar(readout) || ~isfield(readout,'schema_version')
        error('ALEV4:InvalidGeometryBinding', 'Readout must identify its existing schema.');
    end
    if isequal(readout.schema_version,'1.0')
        requireComplete(readout, alev4.createBaselineSensor());
        bound = alev4.createBaselineSensor(readout);
        sensor = bound;
        dual = false;
    elseif isequal(readout.schema_version,'2.0')
        requireComplete(readout, alev4.createDualGainSensor());
        bound = alev4.createDualGainSensor(readout);
        sensor = bound.sensor;
        dual = true;
    else
        error('ALEV4:InvalidGeometryBinding', 'Unknown readout schema.');
    end
    % Binding needs only the validated ROI dimensions and Bayer parity.
    % Do not construct coordinate vectors for a descriptor-only operation.
    roi = geometry.active_roi;
    image_size = roi(3:4);
    tile = reshape(geometry.full_grid_cfa_pattern,2,2).';
    active_tile = tile(mod(roi(1)-1+(0:1),2)+1,mod(roi(2)-1+(0:1),2)+1);
    cfa_pattern = reshape(active_tile.',1,[]);
    if strcmp(mode,'validate')
        if ~isequal(sensor.image_size,image_size) || ...
                sensor.pixel_pitch_m ~= geometry.pixel_pitch_m || ...
                ~strcmp(sensor.cfa_pattern,cfa_pattern)
            error('ALEV4:GeometryBindingConflict', 'Readout size, pitch, or CFA conflicts with geometry.');
        end
        return;
    end
    sensor.image_size = image_size;
    sensor.pixel_pitch_m = geometry.pixel_pitch_m;
    sensor.cfa_pattern = cfa_pattern;
    if dual
        bound.sensor = sensor;
        bound = alev4.createDualGainSensor(bound);
    else
        bound = alev4.createBaselineSensor(sensor);
    end
end

function requireComplete(actual, reference)
    if ~isstruct(actual) || ~isscalar(actual) || ...
            ~isequal(sort(fieldnames(actual)), sort(fieldnames(reference)))
        error('ALEV4:InvalidGeometryBinding', 'Binding requires a complete validated readout configuration.');
    end
    names = fieldnames(reference);
    for k = 1:numel(names)
        if isstruct(reference.(names{k}))
            requireComplete(actual.(names{k}), reference.(names{k}));
        end
    end
end
