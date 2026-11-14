function answer = bundlePathExists(path)
%BUNDLEPATHEXISTS Include dangling symlinks in no-overwrite preflight.
%   Octave exposes lstat. MATLAB with a JVM uses Java NIO to recognize a
%   symlink even when its target is absent. Neither branch follows the link.
    answer = exist(path, 'file') ~= 0;
    if exist('lstat', 'builtin') || exist('lstat', 'file')
        [unused, status] = lstat(path); %#ok<ASGLU>
        answer = answer || status == 0;
    elseif (exist('usejava', 'builtin') || exist('usejava', 'file')) && usejava('jvm')
        java_file = javaObject('java.io.File', path);
        answer = answer || javaMethod('isSymbolicLink', 'java.nio.file.Files', java_file.toPath());
    end
end
