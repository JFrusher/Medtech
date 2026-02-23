function logger(level, message)
% logger
% Purpose:
%   Standardized console logging utility for simulation progress, metrics,
%   and demo reliability checks.
% Inputs:
%   level   - Log level string (e.g., 'INFO', 'WARN', 'ERROR').
%   message - Message text to print.
% Outputs:
%   None. Writes formatted text to console.
% Author:
%   GitHub Copilot (GPT-5.3-Codex)

    if nargin < 2
        error('utils.logger requires level and message inputs.');
    end

    ts = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    fprintf('[%s] [%s] %s\n', ts, upper(string(level)), string(message));
end
