function patientTable = generatePatientData(numPatients)
% generatePatientData
% Purpose:
%   Create a synthetic perioperative cohort with covariates required by the
%   Schnider Propofol PK model (Age, Weight, BMI, Height, LBM).
% Inputs:
%   numPatients - Number of synthetic patients to generate (default: 50).
% Outputs:
%   patientTable - MATLAB table of patient characteristics and case details.
% Author:
%   J Frusher

    if nargin < 1
        numPatients = 50;
    end

    patientID = (1:numPatients)';

    age = max(18, min(85, round(normrnd(52, 14, [numPatients, 1]))));
    sexFlag = rand(numPatients, 1) > 0.5;
    sex = repmat("F", numPatients, 1);
    sex(sexFlag) = "M";

    weightKg = max(45, min(140, normrnd(78, 16, [numPatients, 1])));
    bmi = max(18, min(40, normrnd(27, 4.5, [numPatients, 1])));

    % Why: Height is needed because Schnider clearance includes a height term.
    heightCm = sqrt(weightKg ./ bmi) * 100;
    heightCm = max(145, min(205, heightCm));

    lbm = zeros(numPatients, 1);
    maleIdx = sex == "M";
    femaleIdx = ~maleIdx;

    % Janmahasatian equation, commonly used for clinical PK covariate work.
    lbm(maleIdx) = (9270 .* weightKg(maleIdx)) ./ (6680 + 216 .* bmi(maleIdx));
    lbm(femaleIdx) = (9270 .* weightKg(femaleIdx)) ./ (8780 + 244 .* bmi(femaleIdx));

    surgeryDurationMin = round(60 + rand(numPatients, 1) * 180);   % 60 to 240 min

    % Practical maintenance infusion assumption for emulation (mg/kg/h).
    maintenanceMgPerKgPerHr = 6 + randn(numPatients, 1) * 0.8;
    maintenanceMgPerKgPerHr = max(4.5, min(8.0, maintenanceMgPerKgPerHr));
    infusionRateMgPerMin = weightKg .* maintenanceMgPerKgPerHr / 60;

    patientTable = table( ...
        patientID, age, sex, weightKg, bmi, heightCm, lbm, ...
        surgeryDurationMin, infusionRateMgPerMin, ...
        'VariableNames', { ...
        'PatientID', 'Age', 'Sex', 'WeightKg', 'BMI', 'HeightCm', 'LBM', ...
        'SurgeryDurationMin', 'InfusionRateMgPerMin'});
end
