function sim = calculateCe(patient, timeMin, infusionRateMgPerMin)
% calculateCe
% Purpose:
%   Simulate Propofol concentrations using a Schnider-based 3-compartment
%   PK model with effect-site link model to obtain C_e over time.
% Inputs:
%   patient              - Struct with fields Age, WeightKg, HeightCm, LBM.
%   timeMin              - Time vector in minutes (monotonic increasing).
%   infusionRateMgPerMin - Infusion profile (mg/min), same length as timeMin.
% Outputs:
%   sim - Struct containing Cp (central), Ce (effect-site), C2, C3, and
%         model constants used in the simulation.
% Author:
%   J Frusher

    validateattributes(timeMin, {'numeric'}, {'vector', 'nonempty', 'increasing'});
    validateattributes(infusionRateMgPerMin, {'numeric'}, {'vector', 'numel', numel(timeMin)});

    timeMin = timeMin(:);
    infusionRateMgPerMin = infusionRateMgPerMin(:);

    age = patient.Age;
    weight = patient.WeightKg;
    height = patient.HeightCm;
    lbm = patient.LBM;

    % Schnider model parameterization (propofol; units in L and L/min).
    V1 = 4.27;
    V2 = 18.9 - 0.391 * (age - 53);
    V3 = 238;
    Cl1 = 1.89 + 0.0456 * (weight - 77) - 0.0681 * (lbm - 59) + 0.0264 * (height - 177);
    Cl2 = 1.29 - 0.024 * (age - 53);
    Cl3 = 0.836;
    ke0 = 0.456;

    % Clamp physiologically implausible values for numerical robustness.
    V2 = max(V2, 6);
    Cl1 = max(Cl1, 0.6);
    Cl2 = max(Cl2, 0.2);

    k10 = Cl1 / V1;
    k12 = Cl2 / V1;
    k13 = Cl3 / V1;
    k21 = Cl2 / V2;
    k31 = Cl3 / V3;

    n = numel(timeMin);
    C1 = zeros(n, 1);
    C2 = zeros(n, 1);
    C3 = zeros(n, 1);
    Ce = zeros(n, 1);

    % Why: Explicit finite-difference updates allow fast repeated
    % optimization calls while preserving core compartment dynamics.
    for i = 2:n
        dt = timeMin(i) - timeMin(i-1);
        u = infusionRateMgPerMin(i-1);

        dC1 = (u / V1) - (k10 + k12 + k13) * C1(i-1) + k21 * C2(i-1) + k31 * C3(i-1);
        dC2 = k12 * C1(i-1) - k21 * C2(i-1);
        dC3 = k13 * C1(i-1) - k31 * C3(i-1);
        dCe = ke0 * (C1(i-1) - Ce(i-1));

        C1(i) = max(C1(i-1) + dt * dC1, 0);
        C2(i) = max(C2(i-1) + dt * dC2, 0);
        C3(i) = max(C3(i-1) + dt * dC3, 0);
        Ce(i) = max(Ce(i-1) + dt * dCe, 0);
    end

    sim = struct();
    sim.TimeMin = timeMin;
    sim.Cp = C1;
    sim.C2 = C2;
    sim.C3 = C3;
    sim.Ce = Ce;
    sim.Constants = struct( ...
        'V1', V1, 'V2', V2, 'V3', V3, ...
        'Cl1', Cl1, 'Cl2', Cl2, 'Cl3', Cl3, ...
        'k10', k10, 'k12', k12, 'k13', k13, ...
        'k21', k21, 'k31', k31, 'ke0', ke0);
end
