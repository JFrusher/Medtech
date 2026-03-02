function mimicTable = loadMimicIVData(csvPath)
% loadMimicIVData
% Purpose:
%   Load MIMIC-IV cohort export and standardize it for emergence modeling.
% Inputs:
%   csvPath - Path to MIMIC-IV-derived cohort CSV.
% Outputs:
%   mimicTable - Standardized table ready for train/test splitting.
% Author:
%   J Frusher

    if nargin < 1 || isempty(csvPath)
        error('MIMIC-IV CSV path is required.');
    end

    raw = readtable(csvPath);
    mimicTable = emulator.standardizeClinicalSchema(raw, 'MIMIC-IV');
end
