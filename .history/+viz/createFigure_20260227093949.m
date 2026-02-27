function fig = createFigure(varargin)
% createFigure
% Purpose:
%   Create a MATLAB figure that works in both desktop and headless/HPC runs.
% Inputs:
%   varargin - Name/value pairs forwarded to figure().
% Outputs:
%   fig - Figure handle.

    try
        fig = figure(varargin{:}, 'WindowStyle', 'docked');
        return;
    catch me
        messageText = string(me.message);
        canRetryWithoutDock = contains(messageText, "WindowStyle", 'IgnoreCase', true) || ...
                             contains(messageText, "no display", 'IgnoreCase', true) || ...
                             contains(messageText, "-noFigureWindows", 'IgnoreCase', true);
        if ~canRetryWithoutDock
            rethrow(me);
        end
    end

    try
        fig = figure(varargin{:}, 'Visible', 'off');
    catch me
        if contains(string(me.message), "Visible", 'IgnoreCase', true)
            fig = figure(varargin{:});
        else
            rethrow(me);
        end
    end
end
