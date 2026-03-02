function out = makeStakeholderAlgorithmPlot()
% makeStakeholderAlgorithmPlot
% Purpose:
%   Generate a stakeholder-ready algorithm decision slide from cached
%   tuning artifacts without rerunning full training/evaluation.
% Inputs:
%   None.
% Outputs:
%   out - Struct with output file paths and selected operating-point data.
% Author:
%   GitHub Copilot (GPT-5.3-Codex)

    setupProject();
    projectRoot = fileparts(mfilename('fullpath'));
    out = viz.plotStakeholderAlgorithmOverview(projectRoot);
end