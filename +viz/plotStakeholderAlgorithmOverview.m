function out = plotStakeholderAlgorithmOverview(projectRoot)
% plotStakeholderAlgorithmOverview
% Purpose:
%   Create a non-technical, slide-ready figure that explains how the
%   algorithm estimates surgery finish timing and selects a safe stop-time
%   strategy using cached tuning artifacts.
% Inputs:
%   projectRoot - Optional repository root path.
% Outputs:
%   out - Struct with figure handle, output paths, and selected metrics.
% Author:
%   J Frusher

    if nargin < 1 || strlength(string(projectRoot)) == 0
        projectRoot = fileparts(fileparts(mfilename('fullpath')));
    end

    dataDir = fullfile(projectRoot, 'data');
    figDir = fullfile(projectRoot, 'figures');

    [tuningTable, selectedBufferMin, selectedTargetWakeDelayMin, sourceLabel] = ...
        localLoadTuningArtifacts(dataDir);

    fig = viz.createFigure('Color', 'w', 'Name', 'Stakeholder Algorithm Decision');

    annotation(fig, 'textbox', [0.02 0.94 0.96 0.05], ...
        'String', 'How the tool predicts surgery finish and chooses when to stop anesthetic', ...
        'EdgeColor', 'none', 'FontWeight', 'bold', 'FontSize', 13, ...
        'HorizontalAlignment', 'center');

    localAddProcessFlow(fig);

    exampleCase = localBuildExampleCase(dataDir, selectedTargetWakeDelayMin);
    axTimeline = axes(fig, 'Position', [0.08 0.50 0.60 0.20]);
    localPlotExampleTimeline(axTimeline, exampleCase, selectedTargetWakeDelayMin);

    axTradeoff = axes(fig, 'Position', [0.08 0.14 0.60 0.28]);
    [selectedEarlyWakePct, selectedMeanTTW] = localPlotSimpleTradeoff(axTradeoff, tuningTable, selectedBufferMin);

    localAddNarrativeBox(fig, selectedBufferMin, selectedTargetWakeDelayMin, selectedEarlyWakePct, selectedMeanTTW, exampleCase);

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

    xlabel(ax, 'Safety margin option tested (minutes)');
    title(ax, 'What happened when we tested safer vs faster options', 'FontWeight', 'bold');
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

function localAddProcessFlow(fig)
    boxes = [ ...
        0.06 0.76 0.16 0.13; ...
        0.25 0.76 0.16 0.13; ...
        0.44 0.76 0.16 0.13; ...
        0.63 0.76 0.16 0.13; ...
        0.82 0.76 0.14 0.13];

    labels = { ...
        '1) Read patient and infusion data', ...
        '2) Estimate likely surgery finish time', ...
        '3) Simulate many possible stop times', ...
        '4) Score each option for safety and speed', ...
        '5) Recommend safest practical stop time'};

    for i = 1:size(boxes, 1)
        annotation(fig, 'textbox', boxes(i, :), ...
            'String', labels{i}, ...
            'BackgroundColor', [0.96 0.98 1.00], ...
            'EdgeColor', [0.45 0.62 0.86], ...
            'LineWidth', 1.0, ...
            'FontSize', 9.3, ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle');
    end

    for i = 1:(size(boxes, 1) - 1)
        x1 = boxes(i, 1) + boxes(i, 3);
        y = boxes(i, 2) + boxes(i, 4) / 2;
        x2 = boxes(i + 1, 1);
        annotation(fig, 'arrow', [x1 x2], [y y], 'Color', [0.25 0.35 0.50], 'LineWidth', 1.2);
    end
end

function exampleCase = localBuildExampleCase(dataDir, selectedTargetWakeDelayMin)
    exampleCase = struct();
    exampleCase.HasData = false;
    exampleCase.SurgeryEndMin = NaN;
    exampleCase.OptimizedStopTimeMin = NaN;
    exampleCase.OptimizedWakeTimeMin = NaN;
    exampleCase.OptimizedTTWMin = NaN;
    exampleCase.StopLeadMin = NaN;
    exampleCase.PatientSummary = 'Example case unavailable';

    candidates = {fullfile(dataDir, 'testPatients.csv'), fullfile(dataDir, 'trainPatients.csv')};
    tablePath = '';
    for i = 1:numel(candidates)
        if exist(candidates{i}, 'file')
            tablePath = candidates{i};
            break;
        end
    end

    if strlength(string(tablePath)) == 0
        return;
    end

    try
        cases = readtable(tablePath);
        needed = {'Age','WeightKg','BMI','HeightCm','LBM','SurgeryDurationMin','InfusionRateMgPerMin'};
        if ~all(ismember(needed, cases.Properties.VariableNames)) || isempty(cases)
            return;
        end

        finiteMask = isfinite(cases.SurgeryDurationMin) & isfinite(cases.InfusionRateMgPerMin);
        if ~any(finiteMask)
            return;
        end
        valid = cases(finiteMask, :);

        targetDuration = median(valid.SurgeryDurationMin);
        [~, idx] = min(abs(valid.SurgeryDurationMin - targetDuration));
        row = valid(idx, :);

        patient = struct();
        patient.Age = row.Age;
        patient.WeightKg = row.WeightKg;
        patient.BMI = row.BMI;
        patient.HeightCm = row.HeightCm;
        patient.LBM = row.LBM;

        surgeryEndMin = row.SurgeryDurationMin;
        infusionRate = max(row.InfusionRateMgPerMin, 0);

        policy = model.defaultPolicyConfig(selectedTargetWakeDelayMin);
        result = model.predictEmergence( ...
            patient, surgeryEndMin, infusionRate, selectedTargetWakeDelayMin, 1.2, 0.1, 12, policy);

        exampleCase.HasData = true;
        exampleCase.SurgeryEndMin = surgeryEndMin;
        exampleCase.OptimizedStopTimeMin = result.OptimizedStopTimeMin;
        exampleCase.OptimizedWakeTimeMin = result.OptimizedWakeTimeMin;
        exampleCase.OptimizedTTWMin = result.OptimizedTTWMin;
        exampleCase.StopLeadMin = max(result.StandardStopTimeMin - result.OptimizedStopTimeMin, 0);
        exampleCase.PatientSummary = sprintf('Typical case in dataset: age %.0f, BMI %.1f', row.Age, row.BMI);
    catch
        exampleCase.HasData = false;
    end
end

function localPlotExampleTimeline(ax, exampleCase, selectedTargetWakeDelayMin)
    cla(ax);
    hold(ax, 'on');
    grid(ax, 'on');

    if ~isfield(exampleCase, 'HasData') || ~exampleCase.HasData
        axis(ax, [0 1 0 1]);
        axis(ax, 'off');
        text(ax, 0.02, 0.70, 'Example timeline unavailable (run main to generate patient tables).', ...
            'FontSize', 10, 'Color', [0.2 0.2 0.2]);
        title(ax, 'Example patient timeline', 'FontWeight', 'bold');
        return;
    end

    surgeryEnd = exampleCase.SurgeryEndMin;
    stopTime = exampleCase.OptimizedStopTimeMin;
    wakeTime = exampleCase.OptimizedWakeTimeMin;
    axisMax = max([surgeryEnd + selectedTargetWakeDelayMin + 10, wakeTime + 5, 60]);

    plot(ax, [0 axisMax], [0 0], '-', 'Color', [0.4 0.4 0.4], 'LineWidth', 2.0);
    xline(ax, stopTime, '--', 'Color', [0.00 0.45 0.74], 'LineWidth', 1.8, ...
        'Label', sprintf('Recommended stop (%.1f min)', stopTime), ...
        'LabelVerticalAlignment', 'bottom', 'LabelHorizontalAlignment', 'left');
    xline(ax, surgeryEnd, '--', 'Color', [0.85 0.33 0.10], 'LineWidth', 1.8, ...
        'Label', sprintf('Predicted surgery end (%.1f min)', surgeryEnd), ...
        'LabelVerticalAlignment', 'bottom', 'LabelHorizontalAlignment', 'left');
    xline(ax, wakeTime, '--', 'Color', [0.20 0.60 0.20], 'LineWidth', 1.8, ...
        'Label', sprintf('Predicted wake (%.1f min)', wakeTime), ...
        'LabelVerticalAlignment', 'bottom', 'LabelHorizontalAlignment', 'left');

    text(ax, 0.02 * axisMax, -0.20, exampleCase.PatientSummary, ...
        'FontSize', 9.2, 'Color', [0.2 0.2 0.2]);

    ylim(ax, [-0.35 0.35]);
    yticks(ax, []);
    xlabel(ax, 'Case timeline (minutes from case start)');
    title(ax, sprintf('Example prediction: stop %.1f min before expected finish to target ~%.1f min wake delay', ...
        exampleCase.StopLeadMin, selectedTargetWakeDelayMin), 'FontWeight', 'bold');
end

function localAddNarrativeBox(fig, selectedBufferMin, selectedTargetWakeDelayMin, selectedEarlyWakePct, selectedMeanTTW, exampleCase)
    riskTxt = 'Early wake risk at chosen point: n/a';
    delayTxt = 'Wake delay at chosen point: n/a';
    stopLeadTxt = 'Typical stop lead time: n/a';
    if isfinite(selectedEarlyWakePct)
        riskTxt = sprintf('Early wake risk at chosen option: %.2f%%', selectedEarlyWakePct);
    end
    if isfinite(selectedMeanTTW)
        delayTxt = sprintf('Average wake delay at chosen option: %.2f min', selectedMeanTTW);
    end
    if isfield(exampleCase, 'HasData') && exampleCase.HasData && isfinite(exampleCase.StopLeadMin)
        stopLeadTxt = sprintf('Typical stop lead time: %.2f min before surgery end', exampleCase.StopLeadMin);
    end

    narrative = sprintf([ ...
        'How to read this\n', ...
        '• Top row shows the 5-step logic in plain language.\n', ...
        '• Middle timeline shows one typical case prediction.\n', ...
        '• Bottom chart compares tested safety margins.\n\n', ...
        'Decision used\n', ...
        '• Chosen safety margin: %.2f min\n', ...
        '• Target wake delay after surgery: %.2f min\n', ...
        '• %s\n', ...
        '• %s\n', ...
        '• %s\n\n', ...
        'Takeaway\n', ...
        'The recommendation aims for smooth wake-up while reducing early-wake risk.'], ...
        selectedBufferMin, selectedTargetWakeDelayMin, stopLeadTxt, riskTxt, delayTxt);

    annotation(fig, 'textbox', [0.71 0.24 0.27 0.62], ...
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