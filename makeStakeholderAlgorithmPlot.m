function out = makeStakeholderAlgorithmPlot()
% makeStakeholderAlgorithmPlot
% Purpose:
%   Generate a super-simple stakeholder algorithm slide in plain language.
% Inputs:
%   None.
% Outputs:
%   out - Struct with output file paths and selected operating-point data.
% Author:
%   J Frusher

    setupProject();
    projectRoot = fileparts(mfilename('fullpath'));
    out = viz.plotStakeholderSimpleAlgorithm(projectRoot);
end