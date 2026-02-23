function calibrated = calibrateUncertaintyModel(trainTable, emergenceThresholdCe, dtMin, baseUncertainty)
% calibrateUncertaintyModel
% Purpose:
%   Calibrate uncertainty parameters from retrospective observed wake delays
%   using residuals between model-predicted and observed standard-care TTW.
% Inputs:
%   trainTable           - Training table containing ObservedWakeDelayMin.
%   emergenceThresholdCe - Emergence threshold used by simulator.
%   dtMin                - Simulation time step.
%   baseUncertainty      - Baseline uncertainty configuration.
% Outputs:
%   calibrated - Updated uncertainty configuration.
% Author:
%   GitHub Copilot (GPT-5.3-Codex)

    calibrated = baseUncertainty;

    if ~ismember('ObservedWakeDelayMin', trainTable.Properties.VariableNames)
        return;
    end

    observed = trainTable.ObservedWakeDelayMin;
    validMask = ~isnan(observed) & observed >= 0;
    if sum(validMask) < 10
        return;
    end

    trainValid = trainTable(validMask, :);
    observed = observed(validMask);

    n = height(trainValid);
    predictedStandardTTW = zeros(n, 1);

    for i = 1:n
        p = table2struct(trainValid(i, :));
        result = model.predictEmergence( ...
            p, p.SurgeryDurationMin, p.InfusionRateMgPerMin, 3.0, emergenceThresholdCe, dtMin, 12);
        predictedStandardTTW(i) = result.StandardTTWMin;
    end

    residual = observed - predictedStandardTTW;
    calibrated.ResidualDelayMeanMin = max(0, mean(residual, 'omitnan'));
    calibrated.ResidualDelayStdMin = max(0.15, std(residual, 'omitnan'));

    robustSpread = iqr(residual) / 1.349;
    if isfinite(robustSpread) && robustSpread > 0
        calibrated.ThresholdBiasSigmaFrac = min(0.20, max(0.05, 0.08 + 0.02 * robustSpread));
        calibrated.InfusionBiasSigmaFrac = min(0.20, max(0.05, 0.08 + 0.02 * robustSpread));
    end
end
