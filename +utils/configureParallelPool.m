function cfg = configureParallelPool()
% configureParallelPool
% Purpose:
%   Auto-detect CPU capacity and configure a local parallel pool when
%   Parallel Computing Toolbox is available.
% Inputs:
%   None.
% Outputs:
%   cfg - Struct with fields Enabled, NumWorkers, DetectedCores,
%         ToolboxAvailable.

    cfg = struct();
    cfg.Enabled = false;
    cfg.NumWorkers = 1;
    cfg.DetectedCores = localDetectCores();
    cfg.ToolboxAvailable = license('test', 'Distrib_Computing_Toolbox');
    cfg.RecommendedWorkers = 1;

    if ~cfg.ToolboxAvailable
        utils.logger('INFO', 'Parallel toolbox not available. Running in serial mode.');
        return;
    end

    try
        cluster = parcluster('local');
        maxWorkers = cluster.NumWorkers;

        envWorkers = str2double(getenv('AEP_PARALLEL_WORKERS'));
        if isfinite(envWorkers) && envWorkers >= 0
            desiredWorkers = floor(envWorkers);
        elseif isnan(cfg.DetectedCores) || cfg.DetectedCores < 1
            desiredWorkers = maxWorkers;
        else
            desiredWorkers = max(1, cfg.DetectedCores - 1);
        end
        desiredWorkers = min(maxWorkers, max(1, desiredWorkers));
        cfg.RecommendedWorkers = desiredWorkers;

        if desiredWorkers <= 1
            pool = gcp('nocreate');
            if ~isempty(pool)
                delete(pool);
            end
            cfg.NumWorkers = 1;
            cfg.Enabled = false;
            utils.logger('INFO', 'Parallel configured to 1 worker; running serial to avoid overhead.');
            return;
        end

        pool = gcp('nocreate');
        if isempty(pool)
            pool = parpool(cluster, desiredWorkers);
        elseif pool.NumWorkers ~= desiredWorkers
            delete(pool);
            pool = parpool(cluster, desiredWorkers);
        end

        cfg.NumWorkers = pool.NumWorkers;
        cfg.Enabled = pool.NumWorkers > 1;

        if cfg.Enabled
            utils.logger('INFO', sprintf('Parallel pool active: %d workers (detected cores: %d).', ...
                cfg.NumWorkers, cfg.DetectedCores));
        else
            utils.logger('INFO', 'Parallel pool available but using 1 worker; running effectively serial.');
        end
    catch ME
        utils.logger('WARN', sprintf('Parallel pool setup failed (%s). Falling back to serial.', ME.message));
        cfg.Enabled = false;
        cfg.NumWorkers = 1;
    end
end

function cores = localDetectCores()
    cores = NaN;
    try
        cores = double(feature('numcores'));
    catch
    end

    if ~isfinite(cores) || cores < 1
        try
            cores = java.lang.Runtime.getRuntime().availableProcessors();
        catch
            cores = NaN;
        end
    end
end
