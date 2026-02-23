function policy = defaultPolicyConfig(targetWakeDelayMin)
% defaultPolicyConfig
% Purpose:
%   Provide default safety policy settings for emergence optimization.
% Inputs:
%   targetWakeDelayMin - Nominal target wake delay after surgery end.
% Outputs:
%   policy - Struct containing policy and safety constraints.
% Author:
%   GitHub Copilot (GPT-5.3-Codex)

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
end
