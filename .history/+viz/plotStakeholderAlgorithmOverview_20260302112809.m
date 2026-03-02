function out = plotStakeholderAlgorithmOverview(projectRoot)
% plotStakeholderAlgorithmOverview
% Purpose:
%   Create a non-technical, slide-ready figure that explains how the
%   algorithm selects a safety-aware operating point using cached tuning
%   artifacts.
% Inputs:
%   projectRoot - Optional repository root path.
% Outputs:
%   out - Struct with figure handle, output paths, and selected metrics.
% Author:
%   GitHub Copilot (GPT-5.3-Codex)

    if nargin < 1 || strlength(string(projectRoot)) == 0
        projectRoot = fileparts(fileparts(mfilename('fullpath')));
    end

    dataDir = fullfile(projectRoot, 'data');
    figDir = fullfile(projectRoot, 'figures');

    [tuningTable, selectedBufferMin, selectedTargetWakeDelayMin, sourceLabel] = ...
        localLoadTuningArtifacts(dataDir);

    fig = viz.createFigure('Color', 'w', 'Name', 'Stakeholder Algorithm Overview');
    tiled = tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

    annotation(fig, 'textbox', [0.02 0.94 0.96 0.05], ...
        'String', 'How the algorithm chooses stop timing: safest fast option', ...
        'EdgeColor', 'none', 'FontWeight', 'bold', 'FontSize', 13, ...
        'HorizontalAlignment', 'center');

    ax1 = nexttile(tiled, 1);
    localPlotDecisionFlow(ax1);

    ax2 = nexttile(tiled, 2);
    [selectedEarlyWakePct, selectedMeanTTW] = localPlotTradeoff(ax2, tuningTable, selectedBufferMin);

    ax3 = nexttile(tiled, 3);
    localPlotOutcomePanel(ax3, selectedBufferMin, selectedTargetWakeDelayMin, selectedEarlyWakePct, selectedMeanTTW);

    metaText = sprintf([ ...
        'Data source: %s\n', ...
        'Buffers tested: %d\n', ...
        'Selected buffer: %.2f min\n', ...
        'Target wake delay: %.2f min\n', ...
        'Generated: %s'], ...
        sourceLabel, height(tuningTable), selectedBufferMin, selectedTargetWakeDelayMin, ...
        string(datestr(now, 'yyyy-mm-dd HH:MM')));
    viz.addMetadataBox(fig, metaText, [0.70 0.74 0.28 0.22]);

    if ~exist(figDir, 'dir')
        mkdir(figDir);
    end
    stamp = datestr(now, 'yyyymmdd_HHMMSS');
    outDir = fullfile(figDir, sprintf('posthero_%s', stamp));
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    pngPath = fullfile(outDir, 'stakeholder_algorithm_overview.png');
    figPath = fullfile(outDir, 'stakeholder_algorithm_overview.fig');

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
    out.Source = sourceLabel;
    out.SelectedBufferMin = selectedBufferMin;
    out.SelectedTargetWakeDelayMin = selectedTargetWakeDelayMin;
    out.SelectedEarlyWakeRatePct = selectedEarlyWakePct;
    out.SelectedMeanOptimizedTTW = selectedMeanTTW;

    utils.logger('INFO', sprintf('Saved stakeholder algorithm overview to: %s', outDir));
end

function [tuningTable, selectedBufferMin, selectedTargetWakeDelayMin, sourceLabel] = localLoadTuningArtifacts(dataDir)
    sourceLabel = 'trainingBufferTuning.csv';
    tuningTable = table();
    selectedTargetWakeDelayMin = NaN;

    cacheDir = fullfile(dataDir, 'tuning_cache');
    if exist(cacheDir, 'dir')
        files = dir(fullfile(cacheDir, 'tuning_*.mat'));
        if ~isempty(files)
            [~, idx] = max([files.datenum]);
            cachePath = fullfile(files(idx).folder, files(idx).name);
            try
                loaded = load(cachePath, 'cacheBundle');
                if isfield(loaded, 'cacheBundle') && isfield(loaded.cacheBundle, 'Tuning')
                    t = loaded.cacheBundle.Tuning;
                    if isfield(t, 'Table') && istable(t.Table)
                        tuningTable = t.Table;
                    end
                    if isfield(t, 'BestBufferMin') && isfinite(t.BestBufferMin)
                        selectedBufferMin = t.BestBufferMin;
                    else
                        selectedBufferMin = NaN;
                    end
                    if isfield(t, 'SelectedTargetWakeDelayMin') && isfinite(t.SelectedTargetWakeDelayMin)
                        selectedTargetWakeDelayMin = t.SelectedTargetWakeDelayMin;
                    end
                    sourceLabel = sprintf('tuning cache (%s)', files(idx).name);
                end
            catch
                tuningTable = table();
            end
        end
    end

    if isempty(tuningTable)
        csvPath = fullfile(dataDir, 'trainingBufferTuning.csv');
        if ~exist(csvPath, 'file')
            error('plotStakeholderAlgorithmOverview:MissingTuningData', ...
                ['Missing tuning artifacts. Expected tuning cache in %s or CSV at %s. ', ...
                 'Run main once to generate artifacts.'], cacheDir, csvPath);
        end
        tuningTable = readtable(csvPath);
        selectedBufferMin = NaN;
    end

    if ~ismember('BufferMin', tuningTable.Properties.VariableNames)
        error('plotStakeholderAlgorithmOverview:InvalidTuningTable', ...
            'Tuning table must contain BufferMin column.');
    end

    if ~exist('selectedBufferMin', 'var') || ~isfinite(selectedBufferMin)
        selectedBufferMin = localInferSelectedBuffer(tuningTable);
    end

    penaltyPath = fullfile(dataDir, 'penaltySensitivity.csv');
    if exist(penaltyPath, 'file')
        p = readtable(penaltyPath);
        if ismember('SelectedTargetWakeDelayMin', p.Properties.VariableNames)
            v = p.SelectedTargetWakeDelayMin(find(isfinite(p.SelectedTargetWakeDelayMin), 1, 'last'));
            if ~isempty(v)
                selectedTargetWakeDelayMin = v;
            end
        end
    end

    if ~isfinite(selectedTargetWakeDelayMin)
        selectedTargetWakeDelayMin = 3 + selectedBufferMin;
    end
end

function selectedBufferMin = localInferSelectedBuffer(tuningTable)
    selectedBufferMin = NaN;
    if ismember('PenalizedLoss', tuningTable.Properties.VariableNames)
        finiteMask = isfinite(tuningTable.PenalizedLoss) & isfinite(tuningTable.BufferMin);
        if any(finiteMask)
            finiteIdx = find(finiteMask);
            [~, idx] = min(tuningTable.PenalizedLoss(finiteMask));
            selectedBufferMin = tuningTable.BufferMin(finiteIdx(idx));
            return;
        end
    end

    finiteBuffer = tuningTable.BufferMin(isfinite(tuningTable.BufferMin));
    if isempty(finiteBuffer)
        selectedBufferMin = 0.75;
    else
        selectedBufferMin = median(finiteBuffer);
    end
end

function localPlotDecisionFlow(ax)
    axis(ax, [0 1 0 1]);
    axis(ax, 'off');
    title(ax, '1) Inputs and checks', 'FontWeight', 'bold');

    boxes = [ ...
        0.08 0.72 0.82 0.18; ...
        0.08 0.45 0.82 0.18; ...
        0.08 0.18 0.82 0.18];
    labels = { ...
        'Patient profile + surgery context', ...
        'Simulate uncertainty scenarios', ...
        'Score each stop-time option'};

    for i = 1:size(boxes, 1)
        rectangle(ax, 'Position', boxes(i, :), ...
            'Curvature', 0.08, ...
            'FaceColor', [0.94 0.97 1.00], ...
            'EdgeColor', [0.45 0.62 0.86], ...
            'LineWidth', 1.2);
        text(ax, 0.49, boxes(i, 2) + boxes(i, 4) / 2, labels{i}, ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', ...
            'FontSize', 10);
    end

    annotation(gcf, 'arrow', [0.17 0.17], [0.74 0.66], 'LineWidth', 1.1, 'Color', [0.3 0.4 0.55]);
    annotation(gcf, 'arrow', [0.17 0.17], [0.48 0.40], 'LineWidth', 1.1, 'Color', [0.3 0.4 0.55]);
end

function [selectedEarlyWakePct, selectedMeanTTW] = localPlotTradeoff(ax, tuningTable, selectedBufferMin)
    hold(ax, 'on');
    grid(ax, 'on');

    x = tuningTable.BufferMin;
    [xSorted, sortIdx] = sort(x);
    yRisk = NaN(size(xSorted));
    yDelay = NaN(size(xSorted));

    if ismember('EarlyWakeRatePct', tuningTable.Properties.VariableNames)
        yRisk = tuningTable.EarlyWakeRatePct(sortIdx);
    end
    if ismember('MeanOptimizedTTW', tuningTable.Properties.VariableNames)
        yDelay = tuningTable.MeanOptimizedTTW(sortIdx);
    end

    yyaxis(ax, 'left');
    plot(ax, xSorted, yRisk, '-o', 'Color', [0.78 0.20 0.18], 'LineWidth', 1.6, 'MarkerSize', 4, 'MarkerFaceColor', [0.95 0.55 0.50]);
    ylabel(ax, 'Early wake risk (%)');

    yyaxis(ax, 'right');
    plot(ax, xSorted, yDelay, '-s', 'Color', [0.10 0.45 0.85], 'LineWidth', 1.6, 'MarkerSize', 4, 'MarkerFaceColor', [0.55 0.75 0.95]);
    ylabel(ax, 'Expected wake delay (min)');

    xline(ax, selectedBufferMin, '--k', sprintf('Chosen: %.2f min', selectedBufferMin), ...
        'LineWidth', 1.2, 'LabelVerticalAlignment', 'middle');

    xlabel(ax, 'Safety buffer option (min)');
    title(ax, '2) Trade-off curve from tuning data', 'FontWeight', 'bold');
    legend(ax, {'Early wake risk', 'Wake delay'}, 'Location', 'best');

    selectedEarlyWakePct = NaN;
    selectedMeanTTW = NaN;

    if any(isfinite(xSorted))
        [~, iBest] = min(abs(xSorted - selectedBufferMin));
        if iBest >= 1 && iBest <= numel(yRisk)
            selectedEarlyWakePct = yRisk(iBest);
            selectedMeanTTW = yDelay(iBest);
        end
    end
end

function localPlotOutcomePanel(ax, selectedBufferMin, selectedTargetWakeDelayMin, selectedEarlyWakePct, selectedMeanTTW)
    axis(ax, [0 1 0 1]);
    axis(ax, 'off');
    title(ax, '3) Chosen operating point', 'FontWeight', 'bold');

    rectangle(ax, 'Position', [0.08 0.62 0.84 0.30], ...
        'Curvature', 0.06, 'FaceColor', [0.93 0.98 0.93], ...
        'EdgeColor', [0.55 0.75 0.55], 'LineWidth', 1.2);
    text(ax, 0.50, 0.84, 'Algorithm decision', 'HorizontalAlignment', 'center', ...
        'FontWeight', 'bold', 'FontSize', 10);
    text(ax, 0.50, 0.76, sprintf('Use safety buffer: %.2f min', selectedBufferMin), ...
        'HorizontalAlignment', 'center', 'FontSize', 10);
    text(ax, 0.50, 0.68, sprintf('Target wake delay: %.2f min', selectedTargetWakeDelayMin), ...
        'HorizontalAlignment', 'center', 'FontSize', 10);

    rectangle(ax, 'Position', [0.08 0.30 0.84 0.25], ...
        'Curvature', 0.06, 'FaceColor', [0.97 0.97 0.97], ...
        'EdgeColor', [0.70 0.70 0.70], 'LineWidth', 1.1);

    riskTxt = 'Risk estimate unavailable';
    delayTxt = 'Delay estimate unavailable';
    if isfinite(selectedEarlyWakePct)
        riskTxt = sprintf('Estimated early wake risk: %.2f%%', selectedEarlyWakePct);
    end
    if isfinite(selectedMeanTTW)
        delayTxt = sprintf('Estimated wake delay: %.2f min', selectedMeanTTW);
    end

    text(ax, 0.50, 0.46, riskTxt, 'HorizontalAlignment', 'center', 'FontSize', 9.8);
    text(ax, 0.50, 0.38, delayTxt, 'HorizontalAlignment', 'center', 'FontSize', 9.8);

    text(ax, 0.50, 0.14, ...
        'Takeaway: chooses the safest practical fast option, not the most aggressive one.', ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'FontSize', 9.8, ...
        'Color', [0.15 0.15 0.15]);
end