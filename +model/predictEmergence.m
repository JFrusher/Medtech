function result = predictEmergence(patient, surgeryEndMin, maintenanceRateMgPerMin, targetWakeDelayMin, emergenceThresholdCe, dtMin, earlyPenaltyWeight, policyConfig)
% predictEmergence
% Purpose:
%   Back-calculate optimal anesthesia stop time so predicted emergence
%   occurs near a desired offset from surgery end time.
% Inputs:
%   patient                 - Struct with Schnider covariates.
%   surgeryEndMin           - Target surgery end time (minutes from t=0).
%   maintenanceRateMgPerMin - Constant maintenance infusion rate (mg/min).
%   targetWakeDelayMin      - Desired wake-up delay after surgery end (min).
%   emergenceThresholdCe    - C_e threshold for emergence proxy (mcg/mL).
%   dtMin                   - Simulation time step (minutes).
%   earlyPenaltyWeight      - Penalty multiplier for waking too early.
%   policyConfig            - Struct with min/max acceptable wake delay.
% Outputs:
%   result - Struct with standard and optimized stop times, wake times,
%            and TTW metrics for direct comparison.
% Author:
%   J Frusher

    if nargin < 7
        earlyPenaltyWeight = 12;
    end
    if nargin < 8 || isempty(policyConfig)
        policyConfig = model.defaultPolicyConfig(targetWakeDelayMin);
    end

    horizonMin = surgeryEndMin + 90;
    timeMin = (0:dtMin:horizonMin)';

    standardStop = surgeryEndMin;
    standardWake = localWakeTime(standardStop);

    targetWakeAbs = surgeryEndMin + targetWakeDelayMin;
    minWakeAbs = surgeryEndMin + policyConfig.MinAcceptableWakeDelayMin;
    maxWakeAbs = surgeryEndMin + policyConfig.MaxAcceptableWakeDelayMin;

    low = 0;
    high = surgeryEndMin;
    bestStop = standardStop;
    bestWake = standardWake;
    bestLoss = localPenalizedLoss(bestWake);

    % Why: Wake time is monotonic with stop time in this simplified setup,
    % so bisection provides stable and fast optimization for real-time use.
    for iter = 1:28
        mid = 0.5 * (low + high);
        wakeMid = localWakeTime(mid);
        err = wakeMid - targetWakeAbs;
        candidateLoss = localPenalizedLoss(wakeMid);

        if candidateLoss < bestLoss
            bestLoss = candidateLoss;
            bestStop = mid;
            bestWake = wakeMid;
        end

        if err > 0
            high = mid;
        else
            low = mid;
        end
    end

    % Safety correction: never accept an early wake if a later stop can
    % satisfy the target delay (clinical-risk-biased behavior).
    while bestWake < minWakeAbs && bestStop < surgeryEndMin
        bestStop = min(bestStop + dtMin, surgeryEndMin);
        bestWake = localWakeTime(bestStop);
        bestLoss = localPenalizedLoss(bestWake);
    end
    while bestWake > maxWakeAbs && bestStop > 0
        bestStop = max(bestStop - dtMin, 0);
        bestWake = localWakeTime(bestStop);
        bestLoss = localPenalizedLoss(bestWake);
    end

    result = struct();
    result.StandardStopTimeMin = standardStop;
    result.StandardWakeTimeMin = standardWake;
    result.StandardTTWMin = max(standardWake - surgeryEndMin, 0);
    result.OptimizedStopTimeMin = bestStop;
    result.OptimizedWakeTimeMin = bestWake;
    result.OptimizedTTWMin = max(bestWake - surgeryEndMin, 0);
    result.TargetWakeTimeMin = targetWakeAbs;
    result.TargetWakeDelayMin = targetWakeDelayMin;
    result.MinWakeTimeMin = minWakeAbs;
    result.MaxWakeTimeMin = maxWakeAbs;
    result.EarlyPenaltyWeight = earlyPenaltyWeight;
    result.IsEarlyWake = bestWake < targetWakeAbs;
    result.WakeErrorMin = bestWake - targetWakeAbs;
    result.PenalizedLoss = bestLoss;

    function wakeTime = localWakeTime(stopTime)
        rate = maintenanceRateMgPerMin * ones(size(timeMin));
        rate(timeMin > stopTime) = 0;

        sim = model.calculateCe(patient, timeMin, rate);
        ce = sim.Ce;

        idx = find(timeMin >= stopTime & ce <= emergenceThresholdCe, 1, 'first');
        if isempty(idx)
            wakeTime = timeMin(end);
        else
            wakeTime = timeMin(idx);
        end
    end

    function loss = localPenalizedLoss(wakeTime)
        earlyWakeMin = max(targetWakeAbs - wakeTime, 0);
        lateWakeMin = max(wakeTime - targetWakeAbs, 0);
        belowMinWindow = max(minWakeAbs - wakeTime, 0);
        aboveMaxWindow = max(wakeTime - maxWakeAbs, 0);

        % Why: Early wake-up is clinically riskier than late wake-up, so
        % this asymmetric objective strongly discourages early emergence.
        loss = earlyPenaltyWeight * (earlyWakeMin ^ 2) + (lateWakeMin ^ 2) ...
            + 4 * earlyPenaltyWeight * (belowMinWindow ^ 2) + 1.5 * (aboveMaxWindow ^ 2);
    end
end
