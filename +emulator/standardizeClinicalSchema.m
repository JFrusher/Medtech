function clinicalTable = standardizeClinicalSchema(rawTable, sourceName)
% standardizeClinicalSchema
% Purpose:
%   Standardize source-specific clinical tables (MIMIC-IV, VitalDB, etc.)
%   to the schema required by the emergence model.
% Inputs:
%   rawTable   - Source table with source-native column names.
%   sourceName - Source label for diagnostics.
% Outputs:
%   clinicalTable - Standardized table with required model fields.
% Author:
%   J Frusher

    if nargin < 2
        sourceName = 'unknown';
    end

    t = rawTable;

    patientID = pickNumeric(t, {'PatientID','patient_id','caseid','case_id','subject_id','stay_id','hadm_id'});
    age = pickNumeric(t, {'Age','age','anchor_age'});
    sexRaw = pickAny(t, {'Sex','sex','gender'});
    weightKg = pickNumeric(t, {'WeightKg','weightkg','weight_kg','weight','admission_weight_kg'});
    heightCm = pickNumeric(t, {'HeightCm','heightcm','height_cm','height'});
    bmi = pickNumeric(t, {'BMI','bmi'});
    lbm = pickNumeric(t, {'LBM','lbm','lean_body_mass','lean_body_mass_kg'});
    surgeryDurationMin = pickNumeric(t, {'SurgeryDurationMin','surgery_duration_min','anesthesia_duration_min','case_duration_min','duration_min'});
    infusionRateMgPerMin = pickNumeric(t, {'InfusionRateMgPerMin','infusion_rate_mg_per_min','propofol_infusion_mg_per_min','propofol_rate_mg_min'});
    observedWakeDelayMin = pickNumeric(t, {'ObservedWakeDelayMin','observed_wake_delay_min','wake_delay_min','ttw_observed_min'});

    n = height(t);

    if isempty(patientID)
        patientID = (1:n)';
    end

    if isempty(surgeryDurationMin)
        startTime = pickAny(t, {'SurgeryStartTime','surgery_start_time','starttime','start_time','opstart'});
        endTime = pickAny(t, {'SurgeryEndTime','surgery_end_time','endtime','end_time','opend'});
        if ~isempty(startTime) && ~isempty(endTime)
            surgeryDurationMin = deriveDurationMinutes(startTime, endTime);
        end
    end

    if isempty(infusionRateMgPerMin)
        totalDoseMg = pickNumeric(t, {'PropofolTotalDoseMg','propofol_total_dose_mg','total_propofol_mg','propofol_dose_mg','intraop_ppf'});
        if ~isempty(totalDoseMg) && ~isempty(surgeryDurationMin)
            infusionRateMgPerMin = totalDoseMg ./ max(surgeryDurationMin, 1);
        end
    end

    if isempty(observedWakeDelayMin)
        surgeryEndTime = pickAny(t, {'SurgeryEndTime','surgery_end_time','endtime','end_time','opend'});
        anesthesiaEndTime = pickAny(t, {'AnesthesiaEndTime','anesthesia_end_time','aneend'});
        if ~isempty(surgeryEndTime) && ~isempty(anesthesiaEndTime)
            observedWakeDelayMin = deriveDurationMinutes(surgeryEndTime, anesthesiaEndTime);
        end
    end

    if isempty(bmi) && ~isempty(weightKg) && ~isempty(heightCm)
        bmi = weightKg ./ (max(heightCm, 1) / 100) .^ 2;
    end

    sex = normalizeSex(sexRaw, n);

    if isempty(lbm) && ~isempty(weightKg) && ~isempty(bmi)
        lbm = zeros(n, 1);
        maleIdx = sex == "M";
        femaleIdx = ~maleIdx;
        lbm(maleIdx) = (9270 .* weightKg(maleIdx)) ./ (6680 + 216 .* bmi(maleIdx));
        lbm(femaleIdx) = (9270 .* weightKg(femaleIdx)) ./ (8780 + 244 .* bmi(femaleIdx));
    end

    requiredNames = {'Age','WeightKg','BMI','HeightCm','LBM','SurgeryDurationMin','InfusionRateMgPerMin'};
    requiredValues = {age, weightKg, bmi, heightCm, lbm, surgeryDurationMin, infusionRateMgPerMin};
    missing = requiredNames(cellfun(@isempty, requiredValues));
    if ~isempty(missing)
        error('Source %s missing required fields after mapping: %s', sourceName, strjoin(missing, ', '));
    end

    clinicalTable = table(patientID(:), age(:), sex(:), weightKg(:), bmi(:), heightCm(:), lbm(:), ...
        surgeryDurationMin(:), infusionRateMgPerMin(:), ...
        'VariableNames', {'PatientID','Age','Sex','WeightKg','BMI','HeightCm','LBM','SurgeryDurationMin','InfusionRateMgPerMin'});

    if ~isempty(observedWakeDelayMin)
        clinicalTable.ObservedWakeDelayMin = observedWakeDelayMin(:);
    end
end

function values = pickNumeric(t, aliases)
    values = [];
    for i = 1:numel(aliases)
        idx = strcmpi(t.Properties.VariableNames, aliases{i});
        if any(idx)
            raw = t{:, find(idx, 1, 'first')};
            values = toNumeric(raw);
            return;
        end
    end
end

function values = pickAny(t, aliases)
    values = [];
    for i = 1:numel(aliases)
        idx = strcmpi(t.Properties.VariableNames, aliases{i});
        if any(idx)
            values = t{:, find(idx, 1, 'first')};
            return;
        end
    end
end

function x = toNumeric(raw)
    if isnumeric(raw)
        x = raw;
    elseif islogical(raw)
        x = double(raw);
    elseif iscell(raw)
        x = str2double(string(raw));
    elseif isstring(raw) || ischar(raw) || iscategorical(raw)
        x = str2double(string(raw));
    else
        x = [];
    end
end

function dt = toDatetime(raw)
    if isdatetime(raw)
        dt = raw;
        return;
    end

    if isnumeric(raw)
        dt = NaT(size(raw));
        return;
    end

    sx = string(raw);
    dt = NaT(size(sx));
    for i = 1:numel(sx)
        token = strtrim(sx(i));
        if token == "" || lower(token) == "nan" || token == "0"
            continue;
        end
        try
            dt(i) = datetime(token, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'Format', 'yyyy-MM-dd HH:mm:ss');
        catch
            try
                dt(i) = datetime(token);
            catch
                dt(i) = NaT;
            end
        end
    end
end

function durationMin = deriveDurationMinutes(startRaw, endRaw)
    startNum = toNumeric(startRaw);
    endNum = toNumeric(endRaw);

    if ~isempty(startNum) && ~isempty(endNum)
        delta = endNum - startNum;
        positive = delta(isfinite(delta) & delta > 0);
        if isempty(positive)
            durationMin = delta;
        else
            if median(positive, 'omitnan') > 500
                durationMin = delta ./ 60;
            else
                durationMin = delta;
            end
        end
        durationMin(durationMin < 0) = NaN;
        return;
    end

    startDt = toDatetime(startRaw);
    endDt = toDatetime(endRaw);
    durationMin = minutes(endDt - startDt);
    durationMin(durationMin < 0) = NaN;
end

function sex = normalizeSex(sexRaw, n)
    if isempty(sexRaw)
        sex = repmat("F", n, 1);
        return;
    end

    sx = upper(string(sexRaw));
    sex = repmat("F", n, 1);
    sex(startsWith(sx, "M")) = "M";
    sex(startsWith(sx, "F")) = "F";
end
