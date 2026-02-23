function vitalTable = loadVitalDBData(csvPath)
% loadVitalDBData
% Purpose:
%   Load VitalDB cohort export and standardize it for emergence modeling.
% Inputs:
%   csvPath - Path to VitalDB-derived cohort CSV.
% Outputs:
%   vitalTable - Standardized table ready for train/test splitting.
% Author:
%   GitHub Copilot (GPT-5.3-Codex)

    if nargin < 1 || isempty(csvPath)
        error('VitalDB CSV path is required.');
    end

    raw = readtable(csvPath);
    vitalTable = emulator.standardizeClinicalSchema(raw, 'VitalDB');
end
