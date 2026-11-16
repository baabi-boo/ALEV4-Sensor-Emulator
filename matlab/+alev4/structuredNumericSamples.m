function count = structuredNumericSamples(value)
%STRUCTUREDNUMERICSAMPLES Internal Phase 4 retained-value inventory.
%   Count represented numeric/logical elements without converting sparse
%   arrays or visiting their individual samples. Repeated retained fields
%   count separately, independently of a runtime's copy-on-write storage.
    if isnumeric(value) || islogical(value)
        count = numel(value);
    elseif isstruct(value)
        count = 0;
        names = fieldnames(value);
        for j = 1:numel(value)
            for k = 1:numel(names)
                count = count + alev4.structuredNumericSamples(value(j).(names{k}));
            end
        end
    elseif iscell(value)
        count = 0;
        for k = 1:numel(value)
            count = count + alev4.structuredNumericSamples(value{k});
        end
    else
        count = 0;
    end
end
