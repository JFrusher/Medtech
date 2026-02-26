function outputDir = saveOpenFigures(projectRoot)
% saveOpenFigures
% Purpose:
%   Save all currently open MATLAB figures as both PNG and FIG into a
%   timestamped folder under the project-level figures directory.
% Inputs:
%   projectRoot - Root path of the project (optional).
% Outputs:
%   outputDir - Absolute path to the timestamped figure output directory.

    if nargin < 1 || isempty(projectRoot)
        projectRoot = pwd;
    end

    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    outputDir = fullfile(projectRoot, 'figures', ['run_' timestamp]);
    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    figHandles = findall(groot, 'Type', 'figure');
    if isempty(figHandles)
        utils.logger('INFO', sprintf('No open figures found to save. Output folder: %s', outputDir));
        return;
    end

    nums = arrayfun(@(h) h.Number, figHandles);
    [~, idx] = sort(nums);
    figHandles = figHandles(idx);

    usedNames = strings(0, 1);

    for i = 1:numel(figHandles)
        h = figHandles(i);
        try
            name = string(h.Name);
        catch
            name = string(missing);
        end

        if ismissing(name) || strlength(strtrim(name)) == 0
            base = sprintf('figure_%02d', i);
        else
            base = char(name);
            base = regexprep(base, '[^a-zA-Z0-9_\- ]', '');
            base = strtrim(base);
            base = regexprep(base, '\s+', '_');
            if isempty(base)
                base = sprintf('figure_%02d', i);
            end
        end

        candidate = string(base);
        suffix = 1;
        while any(strcmpi(usedNames, candidate))
            candidate = string(sprintf('%s_%02d', base, suffix));
            suffix = suffix + 1;
        end
        usedNames(end+1, 1) = candidate;

        pngPath = fullfile(outputDir, char(candidate) + ".png");
        figPath = fullfile(outputDir, char(candidate) + ".fig");

        try
            exportgraphics(h, pngPath, 'Resolution', 150);
        catch
            saveas(h, pngPath);
        end

        savefig(h, figPath);
    end

    utils.logger('INFO', sprintf('Saved %d figures to %s', numel(figHandles), outputDir));
end
