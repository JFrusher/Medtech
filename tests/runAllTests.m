function runAllTests()
% runAllTests
% Purpose:
%   Execute project unit and regression checks for Phase 1 quality gates.
% Inputs:
%   None.
% Outputs:
%   None. Prints pass/fail status and throws on failure.
% Author:
%   GitHub Copilot (GPT-5.3-Codex)

    setupProject();
    utils.logger('INFO', 'Running testPKInvariants...');
    testPKInvariants();
    utils.logger('INFO', 'Running testRegressionSnapshot...');
    testRegressionSnapshot();
    utils.logger('INFO', 'All tests passed.');
end
