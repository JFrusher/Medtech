function subgroupTable = subgroupPerformance(patientTable, optimizedTTW, targetWakeDelayMin, earlyAlarmThresholdMin)
% subgroupPerformance
% Purpose:
%   Compute subgroup safety/performance metrics across age, BMI, and case
%   duration strata.
% Inputs:
%   patientTable            - Cohort table.
%   optimizedTTW            - Optimized TTW vector.
%   targetWakeDelayMin      - Operational target wake delay.
%   earlyAlarmThresholdMin  - Alarm threshold below target.
% Outputs:
%   subgroupTable - Summary table with stratum metrics.
% Author:
%   GitHub Copilot (GPT-5.3-Codex)

    if nargin < 4
        earlyAlarmThresholdMin = 1.0;
    end

    rows = {};

    ageBins = {patientTable.Age < 50, 'Age<50'; patientTable.Age >= 50 & patientTable.Age < 70, 'Age50-69'; patientTable.Age >= 70, 'Age>=70'};
    bmiBins = {patientTable.BMI < 25, 'BMI<25'; patientTable.BMI >= 25 & patientTable.BMI < 35, 'BMI25-34'; patientTable.BMI >= 35, 'BMI>=35'};
    durBins = {patientTable.SurgeryDurationMin < 120, 'Dur<120'; patientTable.SurgeryDurationMin >= 120 & patientTable.SurgeryDurationMin < 180, 'Dur120-179'; patientTable.SurgeryDurationMin >= 180, 'Dur>=180'};

    rows = [rows; localMetrics('Age', ageBins); localMetrics('BMI', bmiBins); localMetrics('Duration', durBins)];

    subgroupTable = cell2table(rows, 'VariableNames', ...
        {'Category','Stratum','N','MeanOptimizedTTW','EarlyWakeRatePct','EarlyAlarmRatePct'});

    function outRows = localMetrics(category, binDefs)
        outRows = cell(size(binDefs,1), 6);
        for j = 1:size(binDefs,1)
            mask = binDefs{j,1};
            n = sum(mask);
            if n == 0
                outRows(j,:) = {category, binDefs{j,2}, 0, NaN, NaN, NaN};
                continue;
            end

            ttw = optimizedTTW(mask);
            earlyRate = 100 * mean(ttw < targetWakeDelayMin);
            alarmRate = 100 * mean(ttw < (targetWakeDelayMin - earlyAlarmThresholdMin));
            outRows(j,:) = {category, binDefs{j,2}, n, mean(ttw), earlyRate, alarmRate};
        end
    end
end
