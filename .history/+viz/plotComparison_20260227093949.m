function plotComparison(summary)
% plotComparison
% Purpose:
%   Generate pitch-ready visuals comparing Standard Care versus optimized
%   anesthesia emergence, including safety diagnostics and cost impact.
% Inputs:
%   summary - Struct containing TTW arrays and financial assumptions.
% Outputs:
%   None. Creates multiple MATLAB figures (docked windows).
% Author:
%   GitHub Copilot (GPT-5.3-Codex)

    standard = summary.StandardTTW;
    optimized = summary.OptimizedTTW;
    targetDelay = summary.TargetWakeDelayMin;
    maxDisplayTTWMin = summary.MaxDisplayTTWMin;

    standardClipped = min(standard, maxDisplayTTWMin);
    optimizedClipped = min(optimized, maxDisplayTTWMin);
    clippedStandardN = sum(standard > maxDisplayTTWMin);
    clippedOptimizedN = sum(optimized > maxDisplayTTWMin);

    pooled = [standardClipped; optimizedClipped];
    xMin = max(0, floor(min(pooled)));
    xMax = ceil(max(pooled));
    if xMax <= xMin
        xMax = xMin + 1;
    end
    binEdges = linspace(xMin, xMax, 18);

    fig = viz.createFigure('Color', 'w', 'Name', 'TTW Box Comparison (Test Set)');
    boxchart(categorical(repmat("Standard", numel(standardClipped), 1)), standardClipped, ...
        'BoxFaceColor', [0.65 0.65 0.65]);
    hold on;
    boxchart(categorical(repmat("Optimized", numel(optimizedClipped), 1)), optimizedClipped, ...
        'BoxFaceColor', [0.10 0.45 0.85]);
    ylabel('Time to Wake (min)');
    title('TTW Box Comparison (Test Set)');
    ylim([0 maxDisplayTTWMin]);
    grid on;
    viz.addMetadataBox(fig, localMetaText(summary), [0.72 0.66 0.26 0.30]);

    fig = viz.createFigure('Color', 'w', 'Name', 'Normalized Histogram (Shared Bins)');
    histogram(standardClipped, 'BinEdges', binEdges, 'Normalization', 'probability', ...
        'FaceColor', [0.7 0.7 0.7], 'FaceAlpha', 0.55, 'EdgeColor', 'none');
    hold on;
    histogram(optimizedClipped, 'BinEdges', binEdges, 'Normalization', 'probability', ...
        'FaceColor', [0.1 0.45 0.85], 'FaceAlpha', 0.55, 'EdgeColor', 'none');
    xline(targetDelay, '--k', 'Target', 'LabelVerticalAlignment', 'bottom');
    xlabel('Time to Wake (min)');
    ylabel('Probability');
    title('Normalized Histogram (Shared Bins)');
    legend({'Standard Care', 'Our Solution'}, 'Location', 'northeast');
    text(maxDisplayTTWMin * 0.52, max(ylim) * 0.92, ...
        sprintf('Clipped >%d min: Std=%d, Opt=%d', maxDisplayTTWMin, clippedStandardN, clippedOptimizedN), ...
        'FontSize', 8.5, 'Color', [0.25 0.25 0.25]);
    grid on;
    viz.addMetadataBox(fig, localMetaText(summary), [0.72 0.66 0.26 0.30]);

    fig = viz.createFigure('Color', 'w', 'Name', 'Stacked Violin Plot');
    localStackedViolin(standardClipped, optimizedClipped);
    xline(targetDelay, '--k', 'Target', 'LabelVerticalAlignment', 'middle');
    xlabel('Time to Wake (min)');
    ylabel('Group');
    title('Stacked Violin Plot');
    yticks([1 2]);
    yticklabels({'Standard', 'Optimized'});
    grid on;
    viz.addMetadataBox(fig, localMetaText(summary), [0.72 0.66 0.26 0.30]);

    fig = viz.createFigure('Color', 'w', 'Name', 'Mean TTW (Test Set)');
    barData = [mean(standard), mean(optimized)];
    b = bar(barData, 0.6);
    b.FaceColor = 'flat';
    b.CData = [0.65 0.65 0.65; 0.10 0.45 0.85];
    xticklabels({'Standard Care', 'Our Solution'});
    ylabel('Mean Time to Wake (min)');
    title('Mean TTW (Test Set)');
    grid on;

    reductionPct = 100 * max(mean(standard) - mean(optimized), 0) / max(mean(standard), eps);
    text(1.05, max(barData) * 0.85, sprintf('Reduction: %.1f%%', reductionPct), ...
        'FontWeight', 'bold', 'Color', [0.1 0.45 0.85]);
    viz.addMetadataBox(fig, localMetaText(summary), [0.72 0.66 0.26 0.30]);

    fig = viz.createFigure('Color', 'w', 'Name', 'Per-Patient Sanity Check');
    scatter(standardClipped, optimizedClipped, 24, [0.2 0.45 0.8], 'filled', 'MarkerFaceAlpha', 0.55);
    hold on;
    maxAxis = maxDisplayTTWMin;
    plot([0 maxAxis], [0 maxAxis], '--', 'Color', [0.4 0.4 0.4], 'LineWidth', 1.2);
    xlabel('Standard TTW (min)');
    ylabel('Optimized TTW (min)');
    title('Per-Patient Sanity Check');
    text(maxAxis * 0.04, maxAxis * 0.90, ...
        sprintf('Early wake rate: %.1f%%', summary.TestEarlyWakeRatePct), ...
        'FontWeight', 'bold', 'Color', [0.75 0.1 0.1]);
    axis([0 maxAxis 0 maxAxis]);
    axis square;
    grid on;
    viz.addMetadataBox(fig, localMetaText(summary), [0.72 0.66 0.26 0.30]);

    fig = viz.createFigure('Color', 'w', 'Name', 'OR Cost Impact');
    savingsAssumptionK = summary.AnnualSavingsAssumptionUSD / 1000;
    savingsCohortK = summary.CohortAnnualSavingsUSD / 1000;
    bar([savingsAssumptionK, savingsCohortK], 0.6, 'FaceColor', [0.2 0.65 0.3]);
    xticklabels({'12->3 min Assumption', 'Simulation Estimate'});
    ylabel('Annual Savings (kUSD)');
    title(sprintf('OR Cost Impact ($%d/min, %d cases/year)', ...
        summary.ORCostPerMinuteUSD, summary.AnnualCases));
    grid on;

    annotation(fig, 'textbox', [0.06 0.02 0.90 0.11], ...
        'String', sprintf(['Key Message: Earlier stop-time guidance reduces TTW and can unlock annual OR savings. ', ...
        'Test-set performance includes uncertainty and early-wake safety penalty. Assumption model (12->3 min) = $%.2fM/year.'], ...
        summary.AnnualSavingsAssumptionUSD / 1e6), ...
        'EdgeColor', 'none', 'FontSize', 11, 'FontWeight', 'bold', 'Color', [0.1 0.1 0.1]);
    viz.addMetadataBox(fig, localMetaText(summary), [0.72 0.66 0.26 0.30]);

    function localStackedViolin(dataA, dataB)
        hold on;
        colors = [0.65 0.65 0.65; 0.10 0.45 0.85];
        centers = [1, 2];
        allData = {dataA(:), dataB(:)};

        for k = 1:2
            d = allData{k};
            d = d(~isnan(d));
            if numel(unique(d)) < 2
                yi = linspace(min(d) - 0.1, max(d) + 0.1, 100);
                fi = ones(size(yi));
            else
                try
                    [fi, yi] = ksdensity(d, 'NumPoints', 200);
                catch
                    yi = linspace(min(d), max(d), 120);
                    counts = histcounts(d, [yi, yi(end) + eps], 'Normalization', 'pdf');
                    fi = interp1(yi(1:end-1), counts, yi, 'linear', 'extrap');
                end
            end

            fi = fi / max(fi + eps) * 0.32;
            xp = [yi, fliplr(yi)];
            yp = [centers(k) + fi, fliplr(centers(k) - fi)];
            patch(xp, yp, colors(k, :), ...
                'FaceAlpha', 0.42, 'EdgeColor', colors(k, :), 'LineWidth', 1.0);

            med = median(d);
            plot([med med], [centers(k) - 0.33, centers(k) + 0.33], ...
                '-', 'Color', colors(k, :), 'LineWidth', 2.0);
        end

        ylim([0.5 2.5]);
    end
end

function textOut = localMetaText(summary)
    textOut = sprintf([ ...
        'Cases(Total/Train/Test): %d/%d/%d\n', ...
        'Data: %s | Uncertainty: %s\n', ...
        'Optimizer: %s\n', ...
        'Target Delay: %.2f min | Penalty: %.1f\n', ...
        'Conservative: %s | Early Alarm: %.2f%%\n', ...
        'Display Cap: %.1f min\n', ...
        'Run: %s'], ...
        summary.NumCasesTotal, summary.NumCasesTrain, summary.NumCasesTest, ...
        string(summary.DataSource), string(summary.UncertaintyProfile), ...
        localField(summary, 'OptimizerMode', 'legacy-bisection'), ...
        summary.TargetWakeDelayMin, summary.EarlyPenaltyWeight, ...
        string(mat2str(summary.ConservativeMode)), summary.TestEarlyWakeAlarmRatePct, ...
        summary.MaxDisplayTTWMin, ...
        string(summary.RunTimestamp));
end

function value = localField(s, fieldName, defaultValue)
    if isfield(s, fieldName)
        value = s.(fieldName);
    else
        value = defaultValue;
    end
end
