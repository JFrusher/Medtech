function retroTable = loadRetrospectiveData(csvPath)
% loadRetrospectiveData
% Purpose:
%   Load de-identified retrospective anesthesia cases from CSV and validate
%   required fields for model use.
% Inputs:
%   csvPath - Path to retrospective CSV file.
% Outputs:
%   retroTable - Validated retrospective case table.
% Author:
%   GitHub Copilot (GPT-5.3-Codex)

    if nargin < 1 || isempty(csvPath)
        error('CSV path is required for retrospective data loading.');
    end

    retroTable = readtable(csvPath);

    requiredVars = {'Age','Sex','WeightKg','BMI','HeightCm','LBM','SurgeryDurationMin','InfusionRateMgPerMin'};
    missing = setdiff(requiredVars, retroTable.Properties.VariableNames);
    if ~isempty(missing)
        error('Retrospective CSV missing required columns: %s', strjoin(missing, ', '));
    end

    if ~ismember('PatientID', retroTable.Properties.VariableNames)
        retroTable.PatientID = (1:height(retroTable))';
    end

    % Why: Keep the schema consistent for downstream model functions.
    ordered = {'PatientID','Age','Sex','WeightKg','BMI','HeightCm','LBM','SurgeryDurationMin','InfusionRateMgPerMin'};
    optional = {'ObservedWakeDelayMin'};
    keep = [ordered, intersect(optional, retroTable.Properties.VariableNames, 'stable')];
    retroTable = retroTable(:, keep);
end
