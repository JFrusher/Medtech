function out = plotStakeholderHero(projectRoot)
% plotStakeholderHero
% Purpose:
%   Create a single stakeholder-ready hero figure from saved artifacts,
%   without rerunning full train/tune workflows.
% Inputs:
%   projectRoot - Optional repository root path.
% Outputs:
%   out - Struct with figure handle and computed summary metrics.
% Author:
%   J Frusher

    if nargin < 1 || strlength(string(projectRoot)) == 0
        projectRoot = fileparts(fileparts(mfilename('fullpath')));
    end

    dataDir = fullfile(projectRoot, 'data');
    figDir = fullfile(projectRoot, 'figures');
    testPath = fullfile(dataDir, 'testPatients.csv');
    trainPath = fullfile(dataDir, 'trainPatients.csv');
    penaltyPath = fullfile(dataDir, 'penaltySensitivity.csv');
    tuningPath = fullfile(dataDir, 'trainingBufferTuning.csv');

    if ~exist(testPath, 'file')
        error('plotStakeholderHero:MissingTestPatients', ...
            'Missing %s. Run main once to generate artifacts.', testPath);
    end

    testTable = readtable(testPath);

    targetWakeDelayMin = 3.75;
    earlyPenaltyWeight = 12;
    if exist(penaltyPath, 'file')
        p = readtable(penaltyPath);
        if ismember('SelectedTargetWakeDelayMin', p.Properties.VariableNames)
            v = p.SelectedTargetWakeDelayMin(find(isfinite(p.SelectedTargetWakeDelayMin), 1, 'last'));
            if ~isempty(v)
                targetWakeDelayMin = v;
            end
        end
        if ismember('PenaltyWeight', p.Properties.VariableNames)
            w = p.PenaltyWeight(find(isfinite(p.PenaltyWeight), 1, 'last'));
            if ~isempty(w)
                earlyPenaltyWeight = w;
            end
        end
    end

    emergenceThreshold = 1.2;
    simDtMin = 0.1;
    uncertainty = model.defaultUncertaintyConfig('moderate');
    if exist(trainPath, 'file')
        trainTable = readtable(trainPath);
        uncertainty = model.calibrateUncertaintyModel(trainTable, emergenceThreshold, simDtMin, uncertainty);
    end

    policy = model.defaultPolicyConfig(targetWakeDelayMin);
    policy.ConservativeMode = true;
    policy.OptimizerMode = 'robust-explainable';
    policy.UseParallel = false;
    policy.ShowProgress = true;
    policy.ProgressLabel = 'Hero plot (test-only eval)';

    metrics = model.evaluateStrategy( ...
        testTable, targetWakeDelayMin, emergenceThreshold, simDtMin, ...
        earlyPenaltyWeight, policy, uncertainty);

    standard = metrics.StandardTTW;
    optimized = metrics.OptimizedTTW;
    maxDisplay = 40;

    standardClipped = min(standard, maxDisplay);
    optimizedClipped = min(optimized, maxDisplay);

    meanStandard = mean(standard);
    meanOptimized = mean(optimized);
    ttwGain = max(meanStandard - meanOptimized, 0);
    reductionPct = 100 * ttwGain / max(meanStandard, eps);

    orCostPerMinuteUSD = 50;
    annualCases = 3000;
    annualSavingsUSD = ttwGain * orCostPerMinuteUSD * annualCases;

    fig = viz.createFigure('Color', 'w', 'Name', 'Stakeholder Hero: Emergence Impact');
    ax = axes(fig);
    hold(ax, 'on');
    grid(ax, 'on');

    localHalfViolin(ax, standardClipped, 2, [0.62 0.62 0.62], 'left');
    localHalfViolin(ax, optimizedClipped, 1, [0.10 0.45 0.85], 'right');

    localQuartileBar(ax, standardClipped, 2, [0.35 0.35 0.35]);
    localQuartileBar(ax, optimizedClipped, 1, [0.07 0.30 0.60]);

    xline(ax, targetWakeDelayMin, '--k', 'Target wake delay', 'LineWidth', 1.2, ...
        'LabelHorizontalAlignment', 'left', 'LabelVerticalAlignment', 'middle');

    xlim(ax, [0 maxDisplay]);
    ylim(ax, [0.4 2.6]);
    yticks(ax, [1 2]);
    yticklabels(ax, {'Our solution', 'Standard care'});
    xlabel(ax, 'Time to wake after surgery end (min)');
    title(ax, 'Anesthesia stop-time optimization improves wake timing with safety constraints');

    clipStdN = sum(standard > maxDisplay);
    clipOptN = sum(optimized > maxDisplay);
    subtitle(ax, sprintf(['N=%d test cases | Mean TTW %.2f -> %.2f min (%.1f%% faster) | ', ...
        'Early wake %.1f%% | Annual OR savings ~$%.0fk | Clipped >%dmin: Std=%d, Opt=%d'], ...
        numel(standard), meanStandard, meanOptimized, reductionPct, ...
        metrics.EarlyWakeRatePct, annualSavingsUSD / 1000, maxDisplay, clipStdN, clipOptN));

    infoText = sprintf([ ...
        'Target delay: %.2f min\n', ...
        'Penalty weight: %.1f\n', ...
        'Uncertainty: %s\n', ...
        'Optimizer: %s\n', ...
        'Conservative mode: %s\n', ...
        'Generated: %s'], ...
        targetWakeDelayMin, earlyPenaltyWeight, string(uncertainty.ProfileName), ...
        string(policy.OptimizerMode), string(mat2str(policy.ConservativeMode)), ...
        string(datestr(now, 'yyyy-mm-dd HH:MM')));
    viz.addMetadataBox(fig, infoText, [0.71 0.62 0.27 0.30]);

    if exist(tuningPath, 'file')
        tuning = readtable(tuningPath);
        if ismember('BufferMin', tuning.Properties.VariableNames)
            bestBuffer = NaN;
            if ismember('PenalizedLoss', tuning.Properties.VariableNames)
                finiteLoss = isfinite(tuning.PenalizedLoss);
                if any(finiteLoss)
                    [~, idx] = min(tuning.PenalizedLoss(finiteLoss));
                    finiteIdx = find(finiteLoss);
                    bestBuffer = tuning.BufferMin(finiteIdx(idx));
                end
            end
            if ~isfinite(bestBuffer)
                bestBuffer = targetWakeDelayMin - 3;
            end
            text(ax, 0.7 * maxDisplay, 0.55, sprintf('Safety buffer used: %.2f min', bestBuffer), ...
                'Color', [0.25 0.25 0.25], 'FontSize', 9);
        end
    end

    if ~exist(figDir, 'dir')
        mkdir(figDir);
    end
    stamp = datestr(now, 'yyyymmdd_HHMMSS');
    outDir = fullfile(figDir, sprintf('hero_%s', stamp));
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    pngPath = fullfile(outDir, 'stakeholder_hero_plot.png');
    figPath = fullfile(outDir, 'stakeholder_hero_plot.fig');
    try
        exportgraphics(fig, pngPath, 'Resolution', 300);
    catch
        saveas(fig, pngPath);
    end
    savefig(fig, figPath);

    out = struct();
    out.Figure = fig;
    out.OutputDirectory = outDir;
    out.PNGPath = pngPath;
    out.FIGPath = figPath;
    out.MeanStandardTTW = meanStandard;
    out.MeanOptimizedTTW = meanOptimized;
    out.ReductionPct = reductionPct;
    out.EarlyWakeRatePct = metrics.EarlyWakeRatePct;
    out.AnnualSavingsUSD = annualSavingsUSD;

    utils.logger('INFO', sprintf('Saved stakeholder hero plot to: %s', outDir));
end

function localHalfViolin(ax, data, yCenter, colorVec, side)
    data = data(:);
    data = data(isfinite(data));
    if isempty(data)
        return;
    end

    xRange = linspace(min(data), max(data) + eps, 220);
    if numel(unique(data)) > 1
        density = ksdensity(data, xRange);
    else
        density = ones(size(xRange));
    end
    density = density / max(density + eps) * 0.34;

    switch lower(side)
        case 'left'
            yOuter = yCenter + density;
            yInner = yCenter * ones(size(density));
        otherwise
            yOuter = yCenter - density;
            yInner = yCenter * ones(size(density));
    end

    xp = [xRange, fliplr(xRange)];
    yp = [yOuter, fliplr(yInner)];
    patch(ax, xp, yp, colorVec, 'FaceAlpha', 0.35, 'EdgeColor', colorVec, 'LineWidth', 1.2);
end

function localQuartileBar(ax, data, yCenter, colorVec)
    q1 = quantile(data, 0.25);
    q2 = quantile(data, 0.50);
    q3 = quantile(data, 0.75);
    mn = min(data);
    mx = max(data);

    plot(ax, [mn q1], [yCenter yCenter], '-', 'Color', colorVec, 'LineWidth', 1.1);
    plot(ax, [q3 mx], [yCenter yCenter], '-', 'Color', colorVec, 'LineWidth', 1.1);
    plot(ax, [q1 q3], [yCenter yCenter], '-', 'Color', colorVec, 'LineWidth', 4.0);
    plot(ax, q2, yCenter, 'o', 'MarkerSize', 6, 'MarkerFaceColor', colorVec, 'MarkerEdgeColor', colorVec);
end