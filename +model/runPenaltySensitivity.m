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

    policyLocal = policyConfig;
    policyLocal.ShowProgress = false;
    loopStart = tic;

    for i = 1:n
        tuning = model.tuneSafetyBuffer( ...
            trainTable, baseTargetWakeDelayMin, candidateBufferMin, emergenceThresholdCe, ...
            dtMin, penaltyWeights(i), policyLocal, uncertaintyConfig);

        metrics = model.evaluateStrategy( ...
            trainTable, tuning.SelectedTargetWakeDelayMin, emergenceThresholdCe, ...
            dtMin, penaltyWeights(i), policyLocal, uncertaintyConfig);

        bestBuffer(i) = tuning.BestBufferMin;
        selectedTarget(i) = tuning.SelectedTargetWakeDelayMin;
        meanLoss(i) = metrics.MeanPenalizedLoss;
        earlyRate(i) = metrics.EarlyWakeRatePct;

        if i == 1 || i == n || mod(i, max(1, ceil(n / 4))) == 0
            elapsedSec = toc(loopStart);
            etaSec = max((elapsedSec / i) * (n - i), 0);
            utils.logger('INFO', sprintf('Penalty sensitivity %3.0f%%%% (%d/%d), ETA %s', ...
                100 * i / n, i, n, localFmtDuration(etaSec)));
        end
    end

    sensitivityTable = table(penaltyWeights(:), bestBuffer, selectedTarget, meanLoss, earlyRate, ...
        'VariableNames', {'PenaltyWeight','BestBufferMin','SelectedTargetWakeDelayMin','MeanPenalizedLoss','EarlyWakeRatePct'});
end

function txt = localFmtDuration(sec)
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
