function testRegressionSnapshot()
% testRegressionSnapshot
% Purpose:
%   Check deterministic metric snapshot stability under a fixed seed.
% Inputs:
%   None.
% Outputs:
%   None. Throws assertion error on failure.
% Author:
%   J Frusher

    rng(777, 'twister');
    data = emulator.generatePatientData(60);
    train = data(1:45,:);

    policy = model.defaultPolicyConfig(3);
    uncertainty = model.defaultUncertaintyConfig('moderate');
    tuning = model.tuneSafetyBuffer(train, 3, 0:0.5:2, 1.2, 0.1, 12, policy, uncertainty);

    metrics = model.evaluateStrategy(train, tuning.SelectedTargetWakeDelayMin, 1.2, 0.1, 12, policy, uncertainty);

    snapshotPath = fullfile(fileparts(mfilename('fullpath')), 'regression_snapshot.mat');
    if exist(snapshotPath, 'file') ~= 2
        snapshot = struct('MeanStandardTTW', metrics.MeanStandardTTW, ...
            'MeanOptimizedTTW', metrics.MeanOptimizedTTW, ...
            'EarlyWakeRatePct', metrics.EarlyWakeRatePct);
        save(snapshotPath, 'snapshot');
        return;
    end

    s = load(snapshotPath, 'snapshot');
    snap = s.snapshot;

    assert(abs(metrics.MeanStandardTTW - snap.MeanStandardTTW) < 0.35, 'Snapshot drift: MeanStandardTTW');
    assert(abs(metrics.MeanOptimizedTTW - snap.MeanOptimizedTTW) < 0.35, 'Snapshot drift: MeanOptimizedTTW');
    assert(abs(metrics.EarlyWakeRatePct - snap.EarlyWakeRatePct) < 4.0, 'Snapshot drift: EarlyWakeRatePct');
end
