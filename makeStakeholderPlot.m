function out = makeStakeholderPlot()
% makeStakeholderPlot
% Purpose:
%   Generate a single stakeholder-ready hero figure from existing artifacts
%   without running the full pipeline again.
% Inputs:
%   None.
% Outputs:
%   out - Struct with output file paths and key metrics.
% Author:
%   J Frusher

    setupProject();
    rng(42, 'twister');
    projectRoot = fileparts(mfilename('fullpath'));
    out = viz.plotStakeholderHero(projectRoot);
end