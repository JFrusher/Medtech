function uncertainty = defaultUncertaintyConfig(profileName)
% defaultUncertaintyConfig
% Purpose:
%   Return uncertainty profile parameters used in evaluation-time mismatch.
% Inputs:
%   profileName - 'low', 'moderate', or 'high' uncertainty profile.
% Outputs:
%   uncertainty - Struct with perturbation scales and residual delay model.
% Author:
%   GitHub Copilot (GPT-5.3-Codex)

    if nargin < 1
        profileName = 'moderate';
    end

    switch lower(string(profileName))
        case "low"
            scale = 0.65;
        case "high"
            scale = 1.45;
        otherwise
            scale = 1.0;
            profileName = 'moderate';
    end

    uncertainty = struct();
    uncertainty.ProfileName = char(profileName);
    uncertainty.WeightSigmaFrac = 0.08 * scale;
    uncertainty.HeightSigmaCm = 2.5 * scale;
    uncertainty.LBMSigmaFrac = 0.10 * scale;
    uncertainty.InfusionBiasSigmaFrac = 0.10 * scale;
    uncertainty.InfusionBiasMin = 0.80;
    uncertainty.InfusionBiasMax = 1.20;
    uncertainty.ThresholdBiasSigmaFrac = 0.10 * scale;
    uncertainty.ThresholdBiasMin = 0.80;
    uncertainty.ThresholdBiasMax = 1.35;
    uncertainty.ResidualDelayMeanMin = 0.4;
    uncertainty.ResidualDelayStdMin = 0.8 * scale;
end
