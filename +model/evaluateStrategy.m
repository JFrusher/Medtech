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
%   GitHub Copilot (GPT-5.3-Codex)

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

    for i = 1:n
        patient = table2struct(patientTable(i, :));
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
        perPatientTarget(i) = patientTargetDelay;

        result = model.predictEmergence( ...
            patient, ...
            surgeryEndMin, ...
            maintenanceRateMgPerMin, ...
            patientTargetDelay, ...
            emergenceThresholdCe, ...
            dtMin, ...
            patientPenalty, ...
            patientPolicy);

        predictedStandardTTW(i) = result.StandardTTWMin;
        predictedOptimizedTTW(i) = result.OptimizedTTWMin;

        % Why: Planning and evaluation with identical dynamics can make
        % optimization look unrealistically perfect. We emulate test-time
        % uncertainty using a perturbed "real-world" patient realization.
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

        standardTTW(i) = max(standardWake - surgeryEndMin, 0);
        optimizedTTW(i) = max(optimizedWake - surgeryEndMin, 0);
        optimizedStopLead(i) = result.StandardStopTimeMin - result.OptimizedStopTimeMin;

        earlyWakeMin_i = max(perPatientTarget(i) - optimizedTTW(i), 0);
        lateWakeMin_i = max(optimizedTTW(i) - perPatientTarget(i), 0);
        penalizedLoss(i) = patientPenalty * (earlyWakeMin_i ^ 2) + (lateWakeMin_i ^ 2);
        isEarlyWake(i) = optimizedTTW(i) < perPatientTarget(i);
        isAlarmEarlyWake(i) = optimizedTTW(i) < (perPatientTarget(i) - policyConfig.EarlyAlarmThresholdMin);

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
