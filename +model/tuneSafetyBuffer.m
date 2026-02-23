function tuning = tuneSafetyBuffer(trainTable, baseTargetWakeDelayMin, candidateBufferMin, emergenceThresholdCe, dtMin, earlyPenaltyWeight, policyConfig, uncertaintyConfig)
% tuneSafetyBuffer
% Purpose:
%   Learn a safety buffer (extra target wake delay) on training data that
%   minimizes asymmetric loss with strong early wake penalties.
% Inputs:
%   trainTable             - Training cohort table.
%   baseTargetWakeDelayMin - Baseline desired wake delay (minutes).
%   candidateBufferMin     - Vector of candidate buffer values (minutes).
%   emergenceThresholdCe   - Effect-site threshold for emergence.
%   dtMin                  - Simulation step (minutes).
%   earlyPenaltyWeight     - Penalty multiplier for early wake-up.
%   policyConfig           - Safety policy configuration.
%   uncertaintyConfig      - Evaluation uncertainty configuration.
% Outputs:
%   tuning - Struct containing selected buffer and tuning metrics table.
% Author:
%   GitHub Copilot (GPT-5.3-Codex)

    if nargin < 7 || isempty(policyConfig)
        policyConfig = model.defaultPolicyConfig(baseTargetWakeDelayMin);
    end
    if nargin < 8 || isempty(uncertaintyConfig)
        uncertaintyConfig = model.defaultUncertaintyConfig('moderate');
    end

    numCandidates = numel(candidateBufferMin);
    score = zeros(numCandidates, 1);
    earlyRatePct = zeros(numCandidates, 1);
    meanTTW = zeros(numCandidates, 1);

    for i = 1:numCandidates
        testTargetDelay = baseTargetWakeDelayMin + candidateBufferMin(i);
        metrics = model.evaluateStrategy( ...
            trainTable, testTargetDelay, emergenceThresholdCe, dtMin, earlyPenaltyWeight, policyConfig, uncertaintyConfig);

        score(i) = metrics.MeanPenalizedLoss;
        earlyRatePct(i) = metrics.EarlyWakeRatePct;
        meanTTW(i) = metrics.MeanOptimizedTTW;
    end

    [~, bestIdx] = min(score);

    tuning = struct();
    tuning.BestBufferMin = candidateBufferMin(bestIdx);
    tuning.BaseTargetWakeDelayMin = baseTargetWakeDelayMin;
    tuning.SelectedTargetWakeDelayMin = baseTargetWakeDelayMin + candidateBufferMin(bestIdx);
    tuning.CandidateBufferMin = candidateBufferMin(:);
    tuning.Score = score;
    tuning.EarlyWakeRatePct = earlyRatePct;
    tuning.MeanOptimizedTTW = meanTTW;
    tuning.Table = table(candidateBufferMin(:), score, earlyRatePct, meanTTW, ...
        'VariableNames', {'BufferMin', 'PenalizedLoss', 'EarlyWakeRatePct', 'MeanOptimizedTTW'});
end
