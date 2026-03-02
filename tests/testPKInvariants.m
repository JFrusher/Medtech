function testPKInvariants()
% testPKInvariants
% Purpose:
%   Validate basic PK numerical invariants for model.calculateCe.
% Inputs:
%   None.
% Outputs:
%   None. Throws assertion error on failure.
% Author:
%   J Frusher

    p = struct('Age',55,'WeightKg',80,'HeightCm',175,'LBM',58);

    t = (0:0.1:60)';
    u = zeros(size(t));
    sim0 = model.calculateCe(p, t, u);

    assert(all(sim0.Cp == 0) && all(sim0.Ce == 0), 'Zero infusion invariant failed.');

    u2 = 8 * ones(size(t));
    u2(t > 25) = 0;
    sim = model.calculateCe(p, t, u2);

    assert(all(sim.Cp >= 0) && all(sim.C2 >= 0) && all(sim.C3 >= 0) && all(sim.Ce >= 0), ...
        'Non-negativity invariant failed.');

    % After sufficient post-stop time, central concentration should wash out.
    idxPost = find(t >= 35);
    cpPost = sim.Cp(idxPost);
    d = diff(cpPost);
    assert(all(d <= 1e-6), 'Washout monotonicity failed for post-stop central compartment.');
end
