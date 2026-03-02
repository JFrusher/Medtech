function setupProject()
% setupProject
% Purpose:
%   Configure MATLAB path for the Anesthesia Emergence Predictor project.
% Inputs:
%   None.
% Outputs:
%   None. Adds project root and all subfolders to MATLAB path.
% Author:
%   J Frusher

    projectRoot = fileparts(mfilename('fullpath'));
    addpath(genpath(projectRoot));

    % Why: A deterministic startup path avoids package-resolution errors
    % during demos and keeps the pitch workflow reproducible.
    utils.logger('INFO', sprintf('Project path configured: %s', projectRoot));
end
