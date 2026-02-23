function main()
% main
% Purpose:
%   Run full train/test simulation with safety-constrained optimization,
%   uncertainty-aware evaluation, and Phase 1-3 validation outputs.
% Inputs:
%   None.
% Outputs:
%   Prints key performance and cost-savings metrics; generates figures.
% Author:
%   GitHub Copilot (GPT-5.3-Codex)

    clc;
    setupProject();

    rng(42, 'twister');
    utils.logger('INFO', 'Starting Anesthesia Emergence Predictor simulation.');

    projectRoot = fileparts(mfilename('fullpath'));
    dataDir = fullfile(projectRoot, 'data');
    if ~exist(dataDir, 'dir')
        mkdir(dataDir);
    end

    dataSourcePreference = getenv('AEP_DATA_SOURCE');
    if isempty(dataSourcePreference)
        dataSourcePreference = 'synthetic';
    end
    dataSourceUsed = lower(string(dataSourcePreference));
    retrospectiveCsvPath = fullfile(dataDir, 'retrospective_cases.csv');
    vitaldbCsvPath = fullfile(dataDir, 'vitaldb_cases.csv');
    mimicivCsvPath = fullfile(dataDir, 'mimiciv_cases.csv');
    totalPatients = 1000;
    trainRatio = 0.8;

    switch lower(string(dataSourcePreference))
        case "retrospective"
            if exist(retrospectiveCsvPath, 'file')
                fullTable = emulator.loadRetrospectiveData(retrospectiveCsvPath);
                [trainTable, testTable] = localSplit(fullTable, trainRatio);
                utils.logger('INFO', sprintf('Loaded retrospective dataset: %d total (%d train / %d test).', ...
                    height(fullTable), height(trainTable), height(testTable)));
            else
                dataSourceUsed = "synthetic";
                [trainTable, testTable, fullTable] = emulator.createTrainTestData(totalPatients, trainRatio);
                utils.logger('WARN', sprintf(['Retrospective file not found at %s. ', ...
                    'Using synthetic cohort for this run.'], retrospectiveCsvPath));
            end

        case "vitaldb"
            if exist(vitaldbCsvPath, 'file')
                fullTable = emulator.loadVitalDBData(vitaldbCsvPath);
                [trainTable, testTable] = localSplit(fullTable, trainRatio);
                utils.logger('INFO', sprintf('Loaded VitalDB cohort: %d total (%d train / %d test).', ...
                    height(fullTable), height(trainTable), height(testTable)));
            else
                dataSourceUsed = "synthetic";
                [trainTable, testTable, fullTable] = emulator.createTrainTestData(totalPatients, trainRatio);
                utils.logger('WARN', sprintf(['VitalDB file not found at %s. ', ...
                    'Using synthetic cohort for this run.'], vitaldbCsvPath));
            end

        case {"mimic-iv", "mimiciv", "mimic"}
            if exist(mimicivCsvPath, 'file')
                fullTable = emulator.loadMimicIVData(mimicivCsvPath);
                [trainTable, testTable] = localSplit(fullTable, trainRatio);
                dataSourceUsed = "mimic-iv";
                utils.logger('INFO', sprintf('Loaded MIMIC-IV cohort: %d total (%d train / %d test).', ...
                    height(fullTable), height(trainTable), height(testTable)));
            else
                dataSourceUsed = "synthetic";
                [trainTable, testTable, fullTable] = emulator.createTrainTestData(totalPatients, trainRatio);
                utils.logger('WARN', sprintf(['MIMIC-IV file not found at %s. ', ...
                    'Using synthetic cohort for this run.'], mimicivCsvPath));
            end

        otherwise
            dataSourceUsed = "synthetic";
            [trainTable, testTable, fullTable] = emulator.createTrainTestData(totalPatients, trainRatio);
            utils.logger('INFO', sprintf('Generated synthetic cohort: %d total (%d train / %d test).', ...
                height(fullTable), height(trainTable), height(testTable)));
    end

    if ~exist('fullTable', 'var')
        fullTable = [trainTable; testTable];
    end

    emergenceThreshold = 1.2;      % mcg/mL target for clinical emergence proxy
    baseTargetWakeDelayMin = 3;    % desired minutes after surgery end
    simDtMin = 0.1;                % simulation step in minutes
    earlyPenaltyWeight = 12;       % strong penalty for early emergence risk
    uncertaintyProfile = 'moderate';
    maxDisplayTTWMin = 40;         % figure x/y cap to improve readability
    policy = model.defaultPolicyConfig(baseTargetWakeDelayMin);
    policy.ConservativeMode = true;

    uncertainty = model.defaultUncertaintyConfig(uncertaintyProfile);
    uncertainty = model.calibrateUncertaintyModel(trainTable, emergenceThreshold, simDtMin, uncertainty);
    utils.logger('INFO', sprintf('Uncertainty profile active: %s', uncertainty.ProfileName));

    candidateSafetyBufferMin = 0:0.25:3;
    tuning = model.tuneSafetyBuffer( ...
        trainTable, ...
        baseTargetWakeDelayMin, ...
        candidateSafetyBufferMin, ...
        emergenceThreshold, ...
        simDtMin, ...
        earlyPenaltyWeight, ...
        policy, ...
        uncertainty);

    selectedTargetWakeDelayMin = tuning.SelectedTargetWakeDelayMin;
    utils.logger('INFO', sprintf('Selected safety buffer from training: %.2f min', tuning.BestBufferMin));
    utils.logger('INFO', sprintf('Operational wake target used on test set: %.2f min', selectedTargetWakeDelayMin));

    penaltyWeights = [6 8 10 12 15 18]';
    penaltySensitivity = model.runPenaltySensitivity( ...
        trainTable, baseTargetWakeDelayMin, candidateSafetyBufferMin, ...
        emergenceThreshold, simDtMin, penaltyWeights, policy, uncertainty);

    trainMetrics = model.evaluateStrategy( ...
        trainTable, selectedTargetWakeDelayMin, emergenceThreshold, simDtMin, ...
        earlyPenaltyWeight, policy, uncertainty);
    testMetrics = model.evaluateStrategy( ...
        testTable, selectedTargetWakeDelayMin, emergenceThreshold, simDtMin, ...
        earlyPenaltyWeight, policy, uncertainty);

    seedSweepCount = 20;
    seedSweepMeanTTW = zeros(seedSweepCount, 1);
    seedSweepSavings = zeros(seedSweepCount, 1);
    seedSweepEarlyAlarm = zeros(seedSweepCount, 1);

    for s = 1:seedSweepCount
        rng(500 + s, 'twister');
        metricsSweep = model.evaluateStrategy( ...
            testTable, selectedTargetWakeDelayMin, emergenceThreshold, simDtMin, ...
            earlyPenaltyWeight, policy, uncertainty);
        seedSweepMeanTTW(s) = metricsSweep.MeanOptimizedTTW;
        seedSweepSavings(s) = max(metricsSweep.MeanStandardTTW - metricsSweep.MeanOptimizedTTW, 0) * 50 * 3000;
        seedSweepEarlyAlarm(s) = metricsSweep.EarlyWakeAlarmRatePct;
    end

    ciTTW = localMeanCI(seedSweepMeanTTW);
    ciSavings = localMeanCI(seedSweepSavings);
    ciAlarm = localMeanCI(seedSweepEarlyAlarm);

    meanStandard = testMetrics.MeanStandardTTW;
    meanOptimized = testMetrics.MeanOptimizedTTW;
    meanLead = testMetrics.MeanLeadTime;

    % Pitch assumption block (explicitly requested in brief)
    orCostPerMinuteUSD = 50;
    standardWakeAssumptionMin = 12;
    optimizedWakeAssumptionMin = 3;
    annualCases = 3000;
    annualSavingsAssumptionUSD = (standardWakeAssumptionMin - optimizedWakeAssumptionMin) ...
        * orCostPerMinuteUSD * annualCases;

    % Cohort-derived view from simulation
    cohortPerCaseSavingsUSD = max(meanStandard - meanOptimized, 0) * orCostPerMinuteUSD;
    cohortAnnualSavingsUSD = cohortPerCaseSavingsUSD * annualCases;

    subgroupTable = model.subgroupPerformance( ...
        testTable, testMetrics.OptimizedTTW, selectedTargetWakeDelayMin, policy.EarlyAlarmThresholdMin);

    writetable(trainTable, fullfile(dataDir, 'trainPatients.csv'));
    writetable(testTable, fullfile(dataDir, 'testPatients.csv'));
    writetable(tuning.Table, fullfile(dataDir, 'trainingBufferTuning.csv'));
    writetable(penaltySensitivity, fullfile(dataDir, 'penaltySensitivity.csv'));
    writetable(subgroupTable, fullfile(dataDir, 'subgroupPerformance.csv'));

    summary = struct();
    summary.StandardTTW = testMetrics.StandardTTW;
    summary.OptimizedTTW = testMetrics.OptimizedTTW;
    summary.OptimizedStopLead = testMetrics.OptimizedStopLead;
    summary.MeanStandardTTW = meanStandard;
    summary.MeanOptimizedTTW = meanOptimized;
    summary.MeanLeadTime = meanLead;
    summary.ORCostPerMinuteUSD = orCostPerMinuteUSD;
    summary.AnnualCases = annualCases;
    summary.AnnualSavingsAssumptionUSD = annualSavingsAssumptionUSD;
    summary.CohortAnnualSavingsUSD = cohortAnnualSavingsUSD;
    summary.SelectedTargetWakeDelayMin = selectedTargetWakeDelayMin;
    summary.EarlyPenaltyWeight = earlyPenaltyWeight;
    summary.TargetWakeDelayMin = selectedTargetWakeDelayMin;
    summary.TestEarlyWakeRatePct = testMetrics.EarlyWakeRatePct;
    summary.TestMeanPenalizedLoss = testMetrics.MeanPenalizedLoss;
    summary.TestEarlyWakeMin = testMetrics.EarlyWakeMin;
    summary.TestLateWakeMin = testMetrics.LateWakeMin;
    summary.TestEarlyWakeAlarmRatePct = testMetrics.EarlyWakeAlarmRatePct;
    summary.NumCasesTotal = height(fullTable);
    summary.NumCasesTrain = height(trainTable);
    summary.NumCasesTest = height(testTable);
    summary.UncertaintyProfile = uncertainty.ProfileName;
    summary.DataSource = char(dataSourceUsed);
    summary.ConservativeMode = policy.ConservativeMode;
    summary.EarlyAlarmThresholdMin = policy.EarlyAlarmThresholdMin;
    summary.RunTimestamp = datestr(now, 'yyyy-mm-dd HH:MM');
    summary.MaxDisplayTTWMin = maxDisplayTTWMin;

    utils.logger('INFO', sprintf('TRAIN Mean TTW (Optimized): %.2f min | Early wake rate: %.2f%%', ...
        trainMetrics.MeanOptimizedTTW, trainMetrics.EarlyWakeRatePct));
    utils.logger('INFO', sprintf('TEST Mean TTW (Standard): %.2f min', meanStandard));
    utils.logger('INFO', sprintf('TEST Mean TTW (Optimized): %.2f min', meanOptimized));
    utils.logger('INFO', sprintf('TEST TTW StdDev (Standard/Optimized): %.2f / %.2f min', ...
        std(testMetrics.StandardTTW), std(testMetrics.OptimizedTTW)));
    utils.logger('INFO', sprintf('TEST TTW IQR (Standard/Optimized): %.2f / %.2f min', ...
        iqr(testMetrics.StandardTTW), iqr(testMetrics.OptimizedTTW)));
    utils.logger('INFO', sprintf('TEST Early wake rate: %.2f%% (penalty weight %.1f)', ...
        testMetrics.EarlyWakeRatePct, earlyPenaltyWeight));
    utils.logger('INFO', sprintf('TEST Early wake alarm rate (<target-%.1fmin): %.2f%%', ...
        policy.EarlyAlarmThresholdMin, testMetrics.EarlyWakeAlarmRatePct));
    utils.logger('INFO', sprintf('TEST Mean optimized stop lead time: %.2f min', meanLead));
    utils.logger('INFO', sprintf('Seed sweep MeanOptimizedTTW 95%% CI: [%.2f, %.2f] min', ciTTW(1), ciTTW(2)));
    utils.logger('INFO', sprintf('Seed sweep AnnualSavings 95%% CI: [$%.0f, $%.0f]', ciSavings(1), ciSavings(2)));
    utils.logger('INFO', sprintf('Seed sweep EarlyAlarmRate 95%% CI: [%.2f%%, %.2f%%]', ciAlarm(1), ciAlarm(2)));
    utils.logger('INFO', sprintf('Assumption-based annual savings (12->3 min): $%.0f', annualSavingsAssumptionUSD));
    utils.logger('INFO', sprintf('Cohort-derived annual savings estimate: $%.0f', cohortAnnualSavingsUSD));
    utils.logger('INFO', sprintf('Saved datasets in: %s', dataDir));

    viz.plotComparison(summary);

    if ismember('ObservedWakeDelayMin', testTable.Properties.VariableNames)
        observedMask = ~isnan(testTable.ObservedWakeDelayMin) & testTable.ObservedWakeDelayMin >= 0;
        if any(observedMask)
            calibrationMeta = struct();
            calibrationMeta.NumCases = sum(observedMask);
            calibrationMeta.NumCasesTest = height(testTable);
            calibrationMeta.UncertaintyProfile = uncertainty.ProfileName;
            calibrationMeta.DataSource = char(dataSourceUsed);
            calibrationMeta.ConservativeMode = policy.ConservativeMode;
            calibrationMeta.EarlyPenaltyWeight = earlyPenaltyWeight;
            calibrationMeta.TargetWakeDelayMin = selectedTargetWakeDelayMin;
            calibrationMeta.RunTimestamp = datestr(now, 'yyyy-mm-dd HH:MM');

            viz.plotCalibration( ...
                testMetrics.PredictedStandardTTW(observedMask), ...
                testTable.ObservedWakeDelayMin(observedMask), ...
                'Calibration: Predicted Standard TTW vs Observed Wake Delay', ...
                calibrationMeta);
        end
    end

    utils.logger('INFO', 'Simulation complete. Visuals generated.');
end

function ci = localMeanCI(x)
    mu = mean(x);
    sem = std(x) / sqrt(numel(x));
    ci = [mu - 1.96 * sem, mu + 1.96 * sem];
end

function [trainTable, testTable] = localSplit(fullTable, trainRatio)
    idx = randperm(height(fullTable));
    nTrain = max(1, min(height(fullTable) - 1, round(trainRatio * height(fullTable))));
    trainTable = fullTable(idx(1:nTrain), :);
    testTable = fullTable(idx(nTrain + 1:end), :);
end
