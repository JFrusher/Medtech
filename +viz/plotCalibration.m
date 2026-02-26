function plotCalibration(predictedDelayMin, observedDelayMin, plotTitle, meta)
% plotCalibration
% Purpose:
%   Visualize predicted vs observed wake delays for calibration review.
% Inputs:
%   predictedDelayMin - Predicted wake delay vector (minutes).
%   observedDelayMin  - Observed wake delay vector (minutes).
%   plotTitle         - Figure title string.
%   meta              - Optional run-context metadata struct.
% Outputs:
%   None. Generates a calibration figure.
% Author:
%   GitHub Copilot (GPT-5.3-Codex)

    if nargin < 3
        plotTitle = 'Wake Delay Calibration';
    end
    if nargin < 4
        meta = struct();
    end

    mask = ~isnan(predictedDelayMin) & ~isnan(observedDelayMin) & predictedDelayMin >= 0 & observedDelayMin >= 0;
    pred = predictedDelayMin(mask);
    obs = observedDelayMin(mask);

    if isempty(pred)
        return;
    end

    fig = figure('Color','w','Name','Calibration: Predicted vs Observed','WindowStyle','docked');
    scatter(pred, obs, 28, [0.15 0.45 0.80], 'filled', 'MarkerFaceAlpha', 0.5);
    hold on;
    maxV = max([pred; obs]) * 1.05;
    plot([0 maxV],[0 maxV],'--','Color',[0.4 0.4 0.4],'LineWidth',1.2);
    xlabel('Predicted Wake Delay (min)');
    ylabel('Observed Wake Delay (min)');
    title('Predicted vs Observed');
    axis([0 maxV 0 maxV]);
    axis square;
    grid on;

    fig2 = figure('Color','w','Name','Calibration: Binned Curve','WindowStyle','docked');
    edges = quantile(pred, linspace(0,1,6));
    edges = unique(edges);
    if numel(edges) < 3
        edges = linspace(min(pred), max(pred)+eps, 6);
    end

    binId = discretize(pred, edges);
    binCenters = zeros(max(binId),1);
    meanObs = zeros(max(binId),1);
    meanPred = zeros(max(binId),1);

    for i = 1:max(binId)
        m = binId == i;
        binCenters(i) = mean(pred(m));
        meanObs(i) = mean(obs(m));
        meanPred(i) = mean(pred(m));
    end

    plot(binCenters, meanObs, '-o', 'LineWidth', 1.8, 'Color', [0.2 0.55 0.2]);
    hold on;
    plot(binCenters, meanPred, '--', 'LineWidth', 1.5, 'Color', [0.4 0.4 0.4]);
    xlabel('Predicted Delay Bin Center (min)');
    ylabel('Mean Delay (min)');
    title('Binned Calibration Curve');
    legend({'Observed', 'Ideal'}, 'Location', 'northwest');
    grid on;

    annotation(fig, 'textbox', [0.05 0.93 0.90 0.05], ...
        'String', plotTitle, 'EdgeColor', 'none', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    annotation(fig2, 'textbox', [0.05 0.93 0.90 0.05], ...
        'String', plotTitle, 'EdgeColor', 'none', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

    if ~isempty(fieldnames(meta))
        numCases = localField(meta, 'NumCases', numel(pred));
        numCasesTest = localField(meta, 'NumCasesTest', numel(pred));
        uncertaintyProfile = string(localField(meta, 'UncertaintyProfile', 'n/a'));
        dataSource = string(localField(meta, 'DataSource', 'n/a'));
        conservativeMode = string(mat2str(logical(localField(meta, 'ConservativeMode', false))));
        earlyPenaltyWeight = localField(meta, 'EarlyPenaltyWeight', NaN);
        targetWakeDelayMin = localField(meta, 'TargetWakeDelayMin', NaN);
        runTimestamp = string(localField(meta, 'RunTimestamp', datestr(now, 'yyyy-mm-dd HH:MM')));

        metaText = sprintf([ ...
            'Cal Cases/Test: %d/%d\n', ...
            'Data: %s | Uncertainty: %s\n', ...
            'Target Delay: %.2f min | Penalty: %.1f\n', ...
            'Conservative: %s\n', ...
            'Run: %s'], ...
            numCases, numCasesTest, dataSource, uncertaintyProfile, ...
            targetWakeDelayMin, earlyPenaltyWeight, conservativeMode, runTimestamp);

        viz.addMetadataBox(fig, metaText, [0.73 0.67 0.25 0.28]);
        viz.addMetadataBox(fig2, metaText, [0.73 0.67 0.25 0.28]);
    end
end

function value = localField(s, fieldName, defaultValue)
    if isfield(s, fieldName)
        value = s.(fieldName);
    else
        value = defaultValue;
    end
end
