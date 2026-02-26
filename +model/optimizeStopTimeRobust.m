function result = optimizeStopTimeRobust(patient, surgeryEndMin, maintenanceRateMgPerMin, targetWakeDelayMin, emergenceThresholdCe, dtMin, policyConfig, uncertaintyConfig)
% optimizeStopTimeRobust
% Purpose:
%   Optimize stop time with an explainable, scenario-based robust objective
%   balancing mean performance and tail-risk of early emergence.
% Inputs:
%   patient                 - Struct with PK covariates.
%   surgeryEndMin           - Surgery end time in minutes.
%   maintenanceRateMgPerMin - Baseline maintenance infusion (mg/min).
%   targetWakeDelayMin      - Desired wake delay after surgery end.
%   emergenceThresholdCe    - Emergence threshold proxy for C_e.
%   dtMin                   - Simulation step in minutes.
%   policyConfig            - Policy config incl. robust optimizer weights.
%   uncertaintyConfig       - Uncertainty profile for scenario generation.
% Outputs:
%   result - Struct with robust stop decision and explainability fields.

    targetWakeAbs = surgeryEndMin + targetWakeDelayMin;
    minWakeAbs = surgeryEndMin + policyConfig.MinAcceptableWakeDelayMin;
    maxWakeAbs = surgeryEndMin + policyConfig.MaxAcceptableWakeDelayMin;

    if isfield(policyConfig, 'RobustNumStopCandidates')
        nCandidates = max(10, round(policyConfig.RobustNumStopCandidates));
    else
        nCandidates = 80;
    end
    if isfield(policyConfig, 'RobustNumScenarios')
        nScenarios = max(20, round(policyConfig.RobustNumScenarios));
    else
        nScenarios = 120;
    end

    stopCandidates = linspace(0, surgeryEndMin, nCandidates)';
    wakeScenario = zeros(nCandidates, nScenarios);
    lossScenario = zeros(nCandidates, nScenarios);

    for s = 1:nScenarios
        [realPatient, infusionBias, thresholdBias, residualDelayMin] = localSampleScenario(patient, uncertaintyConfig);
        for c = 1:nCandidates
            stopTime = stopCandidates(c);
            wakeTime = localWakeTimeRealized( ...
                stopTime, surgeryEndMin, dtMin, maintenanceRateMgPerMin, ...
                infusionBias, realPatient, emergenceThresholdCe, thresholdBias, residualDelayMin);

            wakeScenario(c, s) = wakeTime;

            earlyWakeMin = max(targetWakeAbs - wakeTime, 0);
            lateWakeMin = max(wakeTime - targetWakeAbs, 0);
            belowMinWindow = max(minWakeAbs - wakeTime, 0);
            aboveMaxWindow = max(wakeTime - maxWakeAbs, 0);

            lossScenario(c, s) = policyConfig.EarlyPenaltyWeight * (earlyWakeMin ^ 2) + (lateWakeMin ^ 2) ...
                + 4 * policyConfig.EarlyPenaltyWeight * (belowMinWindow ^ 2) + 1.5 * (aboveMaxWindow ^ 2);
        end
    end

    alpha = policyConfig.RobustCVaRAlpha;
    lambdaCvar = policyConfig.RobustCVaRWeight;
    earlyProbWeight = policyConfig.RobustEarlyProbWeight;

    meanLoss = mean(lossScenario, 2);
    sortedLoss = sort(lossScenario, 2, 'ascend');
    tailStart = max(1, floor(alpha * nScenarios));
    cvarLoss = mean(sortedLoss(:, tailStart:end), 2);

    ttwScenario = wakeScenario - surgeryEndMin;
    earlyProb = mean(ttwScenario < targetWakeDelayMin, 2);
    objective = meanLoss + lambdaCvar * cvarLoss + earlyProbWeight * (earlyProb .^ 2);

    [~, bestIdx] = min(objective);
    bestStop = stopCandidates(bestIdx);

    bestWakeScenario = wakeScenario(bestIdx, :)';
    bestLossScenario = lossScenario(bestIdx, :)';

    result = struct();
    result.StandardStopTimeMin = surgeryEndMin;
    result.StandardWakeTimeMin = localWakeTimeRealized( ...
        surgeryEndMin, surgeryEndMin, dtMin, maintenanceRateMgPerMin, ...
        1, patient, emergenceThresholdCe, 1, 0);
    result.StandardTTWMin = max(result.StandardWakeTimeMin - surgeryEndMin, 0);

    result.OptimizedStopTimeMin = bestStop;
    result.OptimizedWakeTimeMin = median(bestWakeScenario);
    result.OptimizedTTWMin = max(result.OptimizedWakeTimeMin - surgeryEndMin, 0);
    result.TargetWakeTimeMin = targetWakeAbs;
    result.TargetWakeDelayMin = targetWakeDelayMin;
    result.MinWakeTimeMin = minWakeAbs;
    result.MaxWakeTimeMin = maxWakeAbs;
    result.IsEarlyWake = result.OptimizedWakeTimeMin < targetWakeAbs;
    result.WakeErrorMin = result.OptimizedWakeTimeMin - targetWakeAbs;
    result.PenalizedLoss = mean(bestLossScenario);

    result.Explainability = struct();
    result.Explainability.Mode = 'robust-explainable';
    result.Explainability.StopCandidatesMin = stopCandidates;
    result.Explainability.ExpectedLossByCandidate = meanLoss;
    result.Explainability.CVaRLossByCandidate = cvarLoss;
    result.Explainability.EarlyProbabilityByCandidate = earlyProb;
    result.Explainability.ObjectiveByCandidate = objective;
    result.Explainability.SelectedCandidateIndex = bestIdx;
    result.Explainability.SelectedScenarioTTW = bestWakeScenario - surgeryEndMin;
    result.Explainability.SelectedScenarioLoss = bestLossScenario;
    result.Explainability.SelectedEarlyProbability = mean(bestWakeScenario - surgeryEndMin < targetWakeDelayMin);
    result.Explainability.SelectedTTWMedian = median(bestWakeScenario - surgeryEndMin);
    result.Explainability.SelectedTTWP90 = prctile(bestWakeScenario - surgeryEndMin, 90);
    result.Explainability.SelectedTTWP10 = prctile(bestWakeScenario - surgeryEndMin, 10);
end

function [realPatient, infusionBias, thresholdBias, residualDelayMin] = localSampleScenario(patient, uncertaintyConfig)
    realPatient = patient;
    realPatient.WeightKg = max(40, patient.WeightKg * (1 + uncertaintyConfig.WeightSigmaFrac * randn()));
    realPatient.HeightCm = max(140, patient.HeightCm + uncertaintyConfig.HeightSigmaCm * randn());
    realPatient.LBM = max(30, patient.LBM * (1 + uncertaintyConfig.LBMSigmaFrac * randn()));

    infusionBias = max(uncertaintyConfig.InfusionBiasMin, min(uncertaintyConfig.InfusionBiasMax, ...
        1 + uncertaintyConfig.InfusionBiasSigmaFrac * randn()));
    thresholdBias = max(uncertaintyConfig.ThresholdBiasMin, min(uncertaintyConfig.ThresholdBiasMax, ...
        1 + uncertaintyConfig.ThresholdBiasSigmaFrac * randn()));
    residualDelayMin = max(0, uncertaintyConfig.ResidualDelayMeanMin + uncertaintyConfig.ResidualDelayStdMin * randn());
end

function wakeTime = localWakeTimeRealized(stopTime, surgeryEndMin, dtMin, maintenanceRateMgPerMin, infusionBias, realPatient, emergenceThresholdCe, emergenceThresholdBias, residualClinicalDelayMin)
    horizonMin = surgeryEndMin + 120;
    timeMin = (0:dtMin:horizonMin)';
    rate = maintenanceRateMgPerMin * infusionBias * ones(size(timeMin));
    rate(timeMin > stopTime) = 0;

    sim = model.calculateCe(realPatient, timeMin, rate);
    realizedThreshold = emergenceThresholdCe * emergenceThresholdBias;

    idx = find(timeMin >= stopTime & sim.Ce <= realizedThreshold, 1, 'first');
    if isempty(idx)
        wakeBase = timeMin(end);
    else
        wakeBase = timeMin(idx);
    end

    wakeTime = wakeBase + residualClinicalDelayMin;
end
