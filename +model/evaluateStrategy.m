function metrics = evaluateStrategy(patientTable, targetWakeDelayMin, emergenceThresholdCe, dtMin, earlyPenaltyWeight, policyConfig, uncertaintyConfig)
% evaluateStrategy
% Purpose:
%   Evaluate the emergence strategy over a cohort and compute asymmetric
%   safety-aware metrics that heavily penalize early wake-up.
% Inputs:
%   patientTable         - Cohort table with patient covariates.
%   targetWakeDelayMin   - Desired wake delay after surgery end (minutes).
%   emergenceThresholdCe - Effect-site concentration threshold for emergence.
%   dtMin                - Simulation time step (minutes).
%   earlyPenaltyWeight   - Multiplier for early wake penalty in loss.
%   policyConfig         - Safety policy settings and conservative mode.
%   uncertaintyConfig    - Evaluation uncertainty profile parameters.
% Outputs:
%   metrics - Struct containing TTW arrays and summary performance metrics.
% Author:
%   J Frusher

    if nargin < 5
        earlyPenaltyWeight = 12;
    end
    if nargin < 6 || isempty(policyConfig)
        policyConfig = model.defaultPolicyConfig(targetWakeDelayMin);
    end
    if nargin < 7 || isempty(uncertaintyConfig)
        uncertaintyConfig = model.defaultUncertaintyConfig('moderate');
    end

    n = height(patientTable);
    standardTTW = zeros(n, 1);
    optimizedTTW = zeros(n, 1);
    optimizedStopLead = zeros(n, 1);
    penalizedLoss = zeros(n, 1);
    isEarlyWake = false(n, 1);
    isAlarmEarlyWake = false(n, 1);
    predictedStandardTTW = zeros(n, 1);
    predictedOptimizedTTW = zeros(n, 1);
    perPatientTarget = zeros(n, 1);

    useParallel = false;
    if isfield(policyConfig, 'UseParallel')
        useParallel = logical(policyConfig.UseParallel);
    end

    parallelMinCases = 700;
    if isfield(policyConfig, 'ParallelMinCases')
        parallelMinCases = max(1, round(policyConfig.ParallelMinCases));
    end

    showProgress = false;
    if isfield(policyConfig, 'ShowProgress')
        showProgress = logical(policyConfig.ShowProgress);
    end
    progressStepFrac = 0.10;
    if isfield(policyConfig, 'ProgressUpdateStepPct')
        progressStepFrac = max(0.01, min(0.50, policyConfig.ProgressUpdateStepPct));
    end
    progressLabel = 'EvaluateStrategy';
    if isfield(policyConfig, 'ProgressLabel')
        progressLabel = char(string(policyConfig.ProgressLabel));
    end

    progressCompleted = 0;
    progressLastFrac = 0;
    progressStart = tic;
    if showProgress
        utils.logger('INFO', sprintf('%s started (%d cases).', progressLabel, n));
    end

    patients = table2struct(patientTable);

    if useParallel && n >= parallelMinCases
        dq = [];
        if showProgress
            dq = parallel.pool.DataQueue;
            afterEach(dq, @localProgressTick);
        end

        parfor i = 1:n
            [standardTTW(i), optimizedTTW(i), optimizedStopLead(i), penalizedLoss(i), ...
                isEarlyWake(i), isAlarmEarlyWake(i), predictedStandardTTW(i), predictedOptimizedTTW(i), ...
                perPatientTarget(i)] = localEvaluatePatient( ...
                patients(i), targetWakeDelayMin, emergenceThresholdCe, dtMin, ...
                earlyPenaltyWeight, policyConfig, uncertaintyConfig);
            if showProgress
                send(dq, 1);
            end
        end
    else
        for i = 1:n
            [standardTTW(i), optimizedTTW(i), optimizedStopLead(i), penalizedLoss(i), ...
                isEarlyWake(i), isAlarmEarlyWake(i), predictedStandardTTW(i), predictedOptimizedTTW(i), ...
                perPatientTarget(i)] = localEvaluatePatient( ...
                patients(i), targetWakeDelayMin, emergenceThresholdCe, dtMin, ...
                earlyPenaltyWeight, policyConfig, uncertaintyConfig);
            if showProgress
                localProgressTick(1);
            end
        end
    end

    if showProgress && progressCompleted < n
        progressCompleted = n;
        localMaybePrintProgress(true);
    end

    earlyWakeMin = max(perPatientTarget - optimizedTTW, 0);
    lateWakeMin = max(optimizedTTW - perPatientTarget, 0);

    metrics = struct();
    metrics.StandardTTW = standardTTW;
    metrics.OptimizedTTW = optimizedTTW;
    metrics.OptimizedStopLead = optimizedStopLead;
    metrics.PenalizedLoss = penalizedLoss;
    metrics.EarlyWakeMin = earlyWakeMin;
    metrics.LateWakeMin = lateWakeMin;
    metrics.IsEarlyWake = isEarlyWake;
    metrics.IsAlarmEarlyWake = isAlarmEarlyWake;
    metrics.PredictedStandardTTW = predictedStandardTTW;
    metrics.PredictedOptimizedTTW = predictedOptimizedTTW;
    metrics.TargetWakeDelayByPatient = perPatientTarget;

    metrics.MeanStandardTTW = mean(standardTTW);
    metrics.MeanOptimizedTTW = mean(optimizedTTW);
    metrics.MeanLeadTime = mean(optimizedStopLead);
    metrics.MeanPenalizedLoss = mean(penalizedLoss);
    metrics.EarlyWakeRatePct = 100 * mean(isEarlyWake);
    metrics.EarlyWakeAlarmRatePct = 100 * mean(isAlarmEarlyWake);

    function localProgressTick(~)
        progressCompleted = progressCompleted + 1;
        localMaybePrintProgress(false);
    end

    function localMaybePrintProgress(forceFinal)
        if n <= 0
            return;
        end
        frac = progressCompleted / n;
        shouldPrint = forceFinal || progressCompleted == 1 || (frac - progressLastFrac >= progressStepFrac);
        if ~shouldPrint
            return;
        end

        elapsedSec = toc(progressStart);
        if progressCompleted > 0
            etaSec = max((elapsedSec / progressCompleted) * (n - progressCompleted), 0);
        else
            etaSec = NaN;
        end
        utils.logger('INFO', sprintf('%s %3.0f%%%% (%d/%d), ETA %s', ...
            progressLabel, 100 * frac, progressCompleted, n, localFormatDuration(etaSec)));
        progressLastFrac = frac;
    end
end

function txt = localFormatDuration(sec)
    if ~isfinite(sec)
        txt = 'n/a';
        return;
    end

    totalSec = max(0, round(sec));
    hh = floor(totalSec / 3600);
    mm = floor(mod(totalSec, 3600) / 60);
    ss = mod(totalSec, 60);

    if hh > 0
        txt = sprintf('%02d:%02d:%02d', hh, mm, ss);
    else
        txt = sprintf('%02d:%02d', mm, ss);
    end
end

function [standardTTW_i, optimizedTTW_i, optimizedStopLead_i, penalizedLoss_i, isEarlyWake_i, isAlarmEarlyWake_i, predictedStandardTTW_i, predictedOptimizedTTW_i, patientTargetDelay] = localEvaluatePatient(patient, targetWakeDelayMin, emergenceThresholdCe, dtMin, earlyPenaltyWeight, policyConfig, uncertaintyConfig)
    surgeryEndMin = patient.SurgeryDurationMin;
    maintenanceRateMgPerMin = patient.InfusionRateMgPerMin;

    isHighRisk = (patient.Age >= policyConfig.HighRiskAgeMin) || ...
        (patient.BMI >= policyConfig.HighRiskBMIMin) || ...
        (surgeryEndMin >= policyConfig.HighRiskSurgeryDurationMin);

    patientTargetDelay = targetWakeDelayMin;
    patientPenalty = earlyPenaltyWeight;
    patientPolicy = policyConfig;
    if policyConfig.ConservativeMode && isHighRisk
        patientTargetDelay = targetWakeDelayMin + policyConfig.ConservativeTargetBufferMin;
        patientPenalty = earlyPenaltyWeight * 1.5;
        patientPolicy.MinAcceptableWakeDelayMin = patientTargetDelay;
        patientPolicy.MaxAcceptableWakeDelayMin = patientTargetDelay + 7;
    end

    mode = 'legacy-bisection';
    if isfield(patientPolicy, 'OptimizerMode')
        mode = char(lower(string(patientPolicy.OptimizerMode)));
    end

    if strcmpi(mode, 'robust-explainable')
        patientPolicy.EarlyPenaltyWeight = patientPenalty;
        result = model.optimizeStopTimeRobust( ...
            patient, ...
            surgeryEndMin, ...
            maintenanceRateMgPerMin, ...
            patientTargetDelay, ...
            emergenceThresholdCe, ...
            dtMin, ...
            patientPolicy, ...
            uncertaintyConfig);
    else
        result = model.predictEmergence( ...
            patient, ...
            surgeryEndMin, ...
            maintenanceRateMgPerMin, ...
            patientTargetDelay, ...
            emergenceThresholdCe, ...
            dtMin, ...
            patientPenalty, ...
            patientPolicy);
    end

    predictedStandardTTW_i = result.StandardTTWMin;
    predictedOptimizedTTW_i = result.OptimizedTTWMin;

    realPatient = patient;
    realPatient.WeightKg = max(40, patient.WeightKg * (1 + uncertaintyConfig.WeightSigmaFrac * randn()));
    realPatient.HeightCm = max(140, patient.HeightCm + uncertaintyConfig.HeightSigmaCm * randn());
    realPatient.LBM = max(30, patient.LBM * (1 + uncertaintyConfig.LBMSigmaFrac * randn()));

    infusionBias = max(uncertaintyConfig.InfusionBiasMin, min(uncertaintyConfig.InfusionBiasMax, ...
        1 + uncertaintyConfig.InfusionBiasSigmaFrac * randn()));
    emergenceThresholdBias = max(uncertaintyConfig.ThresholdBiasMin, min(uncertaintyConfig.ThresholdBiasMax, ...
        1 + uncertaintyConfig.ThresholdBiasSigmaFrac * randn()));
    residualClinicalDelayMin = max(0, uncertaintyConfig.ResidualDelayMeanMin + uncertaintyConfig.ResidualDelayStdMin * randn());

    standardWake = localWakeTimeRealized( ...
        result.StandardStopTimeMin, surgeryEndMin, dtMin, maintenanceRateMgPerMin, ...
        infusionBias, realPatient, emergenceThresholdCe, emergenceThresholdBias, residualClinicalDelayMin);
    optimizedWake = localWakeTimeRealized( ...
        result.OptimizedStopTimeMin, surgeryEndMin, dtMin, maintenanceRateMgPerMin, ...
        infusionBias, realPatient, emergenceThresholdCe, emergenceThresholdBias, residualClinicalDelayMin);

    standardTTW_i = max(standardWake - surgeryEndMin, 0);
    optimizedTTW_i = max(optimizedWake - surgeryEndMin, 0);
    optimizedStopLead_i = result.StandardStopTimeMin - result.OptimizedStopTimeMin;

    earlyWakeMin_i = max(patientTargetDelay - optimizedTTW_i, 0);
    lateWakeMin_i = max(optimizedTTW_i - patientTargetDelay, 0);
    penalizedLoss_i = patientPenalty * (earlyWakeMin_i ^ 2) + (lateWakeMin_i ^ 2);
    isEarlyWake_i = optimizedTTW_i < patientTargetDelay;
    isAlarmEarlyWake_i = optimizedTTW_i < (patientTargetDelay - policyConfig.EarlyAlarmThresholdMin);
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
