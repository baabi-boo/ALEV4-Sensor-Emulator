addpath('matlab'); setup_project(false);
output='outputs/phase4-development/w08_f';
report=test_phase4_numerical_edges(); assert(report.passed && report.test_count==14);
encoded=jsonencode(report); decoded=jsondecode(encoded);
assert(strcmp(decoded.metrics.groups{3}.smallest_normal_accepted_decimal,'2.2250738585072014e-308'));
assert(str2double(decoded.metrics.groups{3}.smallest_normal_accepted_decimal)==realmin);
assert(strcmp(decoded.metrics.groups{6}.first_representable_mean_above_limit_decimal,'1000000000.0000001'));
assert(str2double(decoded.metrics.groups{6}.first_representable_mean_above_limit_decimal)==1e9+eps(1e9));
numeric_audit={};
for k=1:numel(report.metrics.groups)
  group=report.metrics.groups{k}; names=fieldnames(group);
  for j=1:numel(names)
    value=group.(names{j});
    if isnumeric(value)
      for n=1:numel(value)
        assert(isequal(value(n),jsondecode(jsonencode(value(n)))), ...
          'A remaining numeric edge diagnostic changed during JSON roundtrip.');
        numeric_audit{end+1}=struct('group',k,'field',names{j},'index',n, ...
          'decimal',sprintf('%.17g',value(n)),'ieee754_hex',num2hex(value(n)));
      end
    end
  end
end
for item={{'numerical-edges.json',encoded},{'numeric-metric-audit.json',jsonencode(numeric_audit)}}
  pair=item{1}; path=fullfile(output,pair{1});
  fid=fopen(path,'wb'); assert(fid>=0); assert(fwrite(fid,pair{2},'char')==numel(pair{2})); assert(fclose(fid)==0);
end
fprintf('PASS: complete-report JSON retains both decimal-text boundaries; %d remaining numeric edge values roundtrip exactly.\n',numel(numeric_audit));
