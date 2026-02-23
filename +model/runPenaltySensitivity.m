function sensitivityTable = runPenaltySensitivity(trainTable, baseTargetWakeDelayMin, candidateBufferMin, emergenceThresholdCe, dtMin, penaltyWeights, policyConfig, uncertaintyConfig)
% runPenaltySensitivity
% Purpose:
%   Analyze impact of early wake penalty weight on strategy outcomes.
% Inputs:
%   trainTable             - Training cohort table.
%   baseTargetWakeDelayMin - Baseline target wake delay.
%   candidateBufferMin     - Candidate safety buffers.
%   emergenceThresholdCe   - Emergence threshold.
%   dtMin                  - Simulation time step.
%   penaltyWeights         - Vector of early penalty weights.
%   policyConfig           - Safety policy struct.
%   uncertaintyConfig      - Uncertainty profile struct.
% Outputs:
%   sensitivityTable - Table of selected buffer and metrics by penalty.
% Author:
%   GitHub Copilot (GPT-5.3-Codex)

    n = numel(penaltyWeights);
    bestBuffer = zeros(n,1);
    selectedTarget = zeros(n,1);
    meanLoss = zeros(n,1);
    earlyRate = zeros(n,1);

    for i = 1:n
        tuning = model.tuneSafetyBuffer( ...
            trainTable, baseTargetWakeDelayMin, candidateBufferMin, emergenceThresholdCe, ...
            dtMin, penaltyWeights(i), policyConfig, uncertaintyConfig);

        metrics = model.evaluateStrategy( ...
            trainTable, tuning.SelectedTargetWakeDelayMin, emergenceThresholdCe, ...
            dtMin, penaltyWeights(i), policyConfig, uncertaintyConfig);

        bestBuffer(i) = tuning.BestBufferMin;
        selectedTarget(i) = tuning.SelectedTargetWakeDelayMin;
        meanLoss(i) = metrics.MeanPenalizedLoss;
        earlyRate(i) = metrics.EarlyWakeRatePct;
    end

    sensitivityTable = table(penaltyWeights(:), bestBuffer, selectedTarget, meanLoss, earlyRate, ...
        'VariableNames', {'PenaltyWeight','BestBufferMin','SelectedTargetWakeDelayMin','MeanPenalizedLoss','EarlyWakeRatePct'});
end
