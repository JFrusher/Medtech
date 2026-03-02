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

    fig = viz.createFigure('Color', 'w', 'Name', 'Stakeholder Algorithm Decision');

    annotation(fig, 'textbox', [0.02 0.94 0.96 0.05], ...
        'String', 'How the algorithm chooses stop timing: safest fast option', ...
        'EdgeColor', 'none', 'FontWeight', 'bold', 'FontSize', 13, ...
        'HorizontalAlignment', 'center');

    ax = axes(fig, 'Position', [0.08 0.14 0.60 0.74]);
    [selectedEarlyWakePct, selectedMeanTTW] = localPlotSimpleTradeoff(ax, tuningTable, selectedBufferMin);
    localAddNarrativeBox(fig, selectedBufferMin, selectedTargetWakeDelayMin, selectedEarlyWakePct, selectedMeanTTW);

    metaText = sprintf([ ...
        'Data source: %s\n', ...
        'Options tested: %d\n', ...
        'Generated: %s'], ...
        sourceLabel, height(tuningTable), ...
        string(datestr(now, 'yyyy-mm-dd HH:MM')));
    viz.addMetadataBox(fig, metaText, [0.73 0.12 0.24 0.10]);

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

function [selectedEarlyWakePct, selectedMeanTTW] = localPlotSimpleTradeoff(ax, tuningTable, selectedBufferMin)
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
    plot(ax, xSorted, yRisk, '-o', 'Color', [0.78 0.20 0.18], 'LineWidth', 1.8, 'MarkerSize', 4, 'MarkerFaceColor', [0.95 0.55 0.50]);
    ylabel(ax, 'Early wake risk (%)');

    yyaxis(ax, 'right');
    plot(ax, xSorted, yDelay, '-s', 'Color', [0.10 0.45 0.85], 'LineWidth', 1.8, 'MarkerSize', 4, 'MarkerFaceColor', [0.55 0.75 0.95]);
    ylabel(ax, 'Expected wake delay (min)');

    xline(ax, selectedBufferMin, '--k', sprintf('Chosen: %.2f min', selectedBufferMin), ...
        'LineWidth', 1.2, 'LabelVerticalAlignment', 'middle', 'LabelHorizontalAlignment', 'left');

    xlabel(ax, 'Safety buffer option (min)');
    title(ax, 'Trade-off from tuning data: safety vs speed', 'FontWeight', 'bold');
    legend(ax, {'Early wake risk', 'Wake delay'}, 'Location', 'northoutside', 'Orientation', 'horizontal');

    selectedEarlyWakePct = NaN;
    selectedMeanTTW = NaN;

    if any(isfinite(xSorted))
        [~, iBest] = min(abs(xSorted - selectedBufferMin));
        if iBest >= 1 && iBest <= numel(yRisk)
            selectedEarlyWakePct = yRisk(iBest);
            selectedMeanTTW = yDelay(iBest);

            yyaxis(ax, 'left');
            if isfinite(selectedEarlyWakePct)
                plot(ax, selectedBufferMin, selectedEarlyWakePct, 'o', ...
                    'MarkerSize', 9, 'MarkerFaceColor', [0.78 0.20 0.18], ...
                    'MarkerEdgeColor', [0.35 0.10 0.10], 'LineWidth', 1.2);
            end

            yyaxis(ax, 'right');
            if isfinite(selectedMeanTTW)
                plot(ax, selectedBufferMin, selectedMeanTTW, 'o', ...
                    'MarkerSize', 9, 'MarkerFaceColor', [0.10 0.45 0.85], ...
                    'MarkerEdgeColor', [0.05 0.20 0.45], 'LineWidth', 1.2);
            end
        end
    end
end

function localAddNarrativeBox(fig, selectedBufferMin, selectedTargetWakeDelayMin, selectedEarlyWakePct, selectedMeanTTW)
    riskTxt = 'Early wake risk at chosen point: n/a';
    delayTxt = 'Wake delay at chosen point: n/a';
    if isfinite(selectedEarlyWakePct)
        riskTxt = sprintf('Early wake risk at chosen point: %.2f%%', selectedEarlyWakePct);
    end
    if isfinite(selectedMeanTTW)
        delayTxt = sprintf('Wake delay at chosen point: %.2f min', selectedMeanTTW);
    end

    narrative = sprintf([ ...
        'How to read this\n', ...
        '• Each x-value is a safety buffer option tested on training data.\n', ...
        '• Red line = safety risk, Blue line = wake speed outcome.\n\n', ...
        'Decision used\n', ...
        '• Chosen buffer: %.2f min\n', ...
        '• Target wake delay: %.2f min\n', ...
        '• %s\n', ...
        '• %s\n\n', ...
        'Takeaway\n', ...
        'The algorithm chooses a balanced point: low risk with practical speed.'], ...
        selectedBufferMin, selectedTargetWakeDelayMin, riskTxt, delayTxt);

    annotation(fig, 'textbox', [0.72 0.28 0.26 0.58], ...
        'String', narrative, ...
        'EdgeColor', [0.72 0.72 0.72], ...
        'BackgroundColor', [1 1 1], ...
        'FontSize', 9.8, ...
        'FontName', 'Helvetica', ...
        'HorizontalAlignment', 'left', ...
        'VerticalAlignment', 'top', ...
        'Interpreter', 'none', ...
        'Color', [0.15 0.15 0.15]);
end