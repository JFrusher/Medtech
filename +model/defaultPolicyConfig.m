function policy = defaultPolicyConfig(targetWakeDelayMin)
% defaultPolicyConfig
% Purpose:
%   Provide default safety policy settings for emergence optimization.
% Inputs:
%   targetWakeDelayMin - Nominal target wake delay after surgery end.
% Outputs:
%   policy - Struct containing policy and safety constraints.
% Author:
%   J Frusher

    if nargin < 1
        targetWakeDelayMin = 3;
    end

    policy = struct();
    policy.MinAcceptableWakeDelayMin = max(0, targetWakeDelayMin - 0.5);
    policy.MaxAcceptableWakeDelayMin = targetWakeDelayMin + 6.0;
    policy.ConservativeMode = false;
    policy.ConservativeTargetBufferMin = 0.75;
    policy.HighRiskAgeMin = 70;
    policy.HighRiskBMIMin = 35;
    policy.HighRiskSurgeryDurationMin = 180;
    policy.EarlyAlarmThresholdMin = 1.0;

    % Optimizer mode: 'legacy-bisection' (default) or 'robust-explainable'.
    policy.OptimizerMode = 'legacy-bisection';
    policy.EarlyPenaltyWeight = 12;
    policy.RobustNumStopCandidates = 80;
    policy.RobustNumScenarios = 120;
    policy.RobustCVaRAlpha = 0.85;
    policy.RobustCVaRWeight = 0.75;
    policy.RobustEarlyProbWeight = 35;

    % Parallel settings (adaptive): only parallelize sufficiently large cohorts.
    policy.ParallelMinCases = 700;

    % Progress reporting settings.
    policy.ShowProgress = true;
    policy.ProgressUpdateStepPct = 0.10;
    policy.ProgressLabel = 'EvaluateStrategy';
end
