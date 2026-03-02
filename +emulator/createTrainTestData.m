function [trainTable, testTable, fullTable] = createTrainTestData(totalPatients, trainRatio)
% createTrainTestData
% Purpose:
%   Generate a larger synthetic cohort and split into training and testing
%   datasets to avoid evaluating on the same cases used for tuning.
% Inputs:
%   totalPatients - Total synthetic patients to generate (default: 300).
%   trainRatio    - Fraction assigned to training set (default: 0.8).
% Outputs:
%   trainTable - Training dataset table.
%   testTable  - Testing dataset table.
%   fullTable  - Full generated cohort before split.
% Author:
%   J Frusher

    if nargin < 1
        totalPatients = 300;
    end
    if nargin < 2
        trainRatio = 0.8;
    end

    fullTable = emulator.generatePatientData(totalPatients);

    idx = randperm(totalPatients);
    nTrain = max(1, min(totalPatients - 1, round(trainRatio * totalPatients)));

    trainIdx = idx(1:nTrain);
    testIdx = idx(nTrain + 1:end);

    trainTable = fullTable(trainIdx, :);
    testTable = fullTable(testIdx, :);
end
