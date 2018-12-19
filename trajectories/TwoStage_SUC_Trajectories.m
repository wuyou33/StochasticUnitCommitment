% Author: Luis Badesa

%%
clearvars
clc 

%% Inputs
load('Data\InputData.mat')
load('Data\SystemParameters.mat')
% The units are GW, k�/GW and k� to keep the range of variables closer

%% Define the optimisation model:
Load_balance = [];
Aux_constraints = [];
Constraints_Gen_limits = [];
Constraints_Ramp_limits = [];
Cost_node = [];

scenarios = size(Wind_scenarios,1);

% Create some matrices of DVs:
Wind_curtailed = sdpvar(scenarios,time_steps);
Load_curtailed = sdpvar(scenarios,time_steps);

% And some matrices of constraints:
Aux_constraints = [Aux_constraints,...
                           0 <= Wind_curtailed <= Wind_scenarios,...
                           0 <= Load_curtailed <= ones(scenarios,1)*Demand];

for k=1:time_steps

    %% Define DVs

    x{k} = sdpvar(scenarios,num_gen);
    % x{k} = [x1 x2 x3... (scenario 1)
    %         x1 x2 x3... (scenario 2)]; % Power generated by each Gen. in each scenario

    y{k} = binvar(scenarios,num_gen);
    % y{k} = [y1 y2 y3... (scenario 1)
    %         y1 y2 y3... (scenario 2)]; % ommitment decision for each Gen. in each scenario

% NO INITIAL COMMITMENT        
%         if k==1
%             Aux_constraints = [Aux_constraints,...
%                                y{n,k}==Initial_commitment];
%         end


    % Fix commitment decision of inflexible_gen to be same as in the first 
    % scenario in this time-step "k"
    Aux_constraints = [Aux_constraints,...
        (ones(scenarios,1)*inflexible).*y{k} == ones(scenarios,1)*(inflexible.*y{k}(1,:))];
        
    % Define DVs for generators started up
    startup_DV{k} = sdpvar(scenarios,num_gen);
    if k==1
        Aux_constraints = [Aux_constraints,...
                           startup_DV{k} == y{k}];
    else
        % These 2 constraints model the startup, it's easy to verify
        % that they indeed do:
        Aux_constraints = [Aux_constraints,...
                           startup_DV{k} >= y{k} - y{k-1},...
                           startup_DV{k} >= zeros(scenarios,num_gen)];
    end

    %% Constraints:
    Load_balance = [Load_balance,...
        sum(x{k},2)+Wind_scenarios(:,k)-Wind_curtailed(:,k) == ones(scenarios,1)*Demand(k)-Load_curtailed(:,k)];

   % Generation limits:
    for i=1:num_gen
        Constraints_Gen_limits = [Constraints_Gen_limits,...
                                  y{k}.*(ones(scenarios,1)*Gen_limits(:,1)') <= x{k} <= y{k}.*(ones(scenarios,1)*Gen_limits(:,2)')];
    end

%         % Ramp limits:
%         if k>1
% 
%                 Constraints_Ramp_limits = [Constraints_Ramp_limits,...
%                                            -tau*(ones(scenarios,1)*Ramp_limits(:,1)') <= x{k}-x{k-1} <= tau*(ones(scenarios,1)*Ramp_limits(:,2)')];
% 
%         end

    %% Finally, define the nodal costs:
    Cost_node = horzcat(Cost_node,...
        sum((ones(scenarios,1)*stc').*startup_DV{k},2)... % Startup costs
        + tau*(sum((ones(scenarios,1)*NLHR').*y{k},2)... % fixed generation costs
        + sum((ones(scenarios,1)*HRS').*x{k},2)... % variable generation costs
        + VOLL*Load_curtailed(:,k))); % load shed cost

end
 
Objective = sum(sum(prob_nodes.*Cost_node));

Constraints = [Aux_constraints,...
               Load_balance,...
               Constraints_Gen_limits
               Constraints_Ramp_limits];

options = sdpsettings('solver','gurobi','gurobi.MIPGap',0.5e-2,'gurobi.NodeLimit',5000);

solution = optimize(Constraints,Objective,options)


%% Analyse results


sol.Wind_curtailed = value(Wind_curtailed);
sol.Load_curtailed = value(Load_curtailed);
sol.Cost = [];
sol.Cost_StartUp = [];
sol.Cost_NLHR = [];
sol.Cost_HRS = [];
sol.Cost_VOLL = [];
sol.Check_Load_balance(scenarios,time_steps) = 0;

for k=1:time_steps
    sol.x{k} = value(x{k});
    sol.y{k} = value(y{k});
    sol.startup_DV{k} = value(startup_DV{k});
    sol.Cost = horzcat(sol.Cost,...
        sum((ones(scenarios,1)*stc').*sol.startup_DV{k},2)... % Startup costs
        + tau*(sum((ones(scenarios,1)*NLHR').*sol.y{k},2)... % fixed generation costs
        + sum((ones(scenarios,1)*HRS').*sol.x{k},2)... % variable generation costs
        + VOLL*sol.Load_curtailed(:,k)));
    sol.Cost_StartUp = horzcat(sol.Cost_StartUp,...
        sum((ones(scenarios,1)*stc').*sol.startup_DV{k},2));
    sol.Cost_NLHR = horzcat(sol.Cost_NLHR,...
        tau*(sum((ones(scenarios,1)*NLHR').*sol.y{k},2)));
    sol.Cost_HRS = horzcat(sol.Cost_HRS,...
        tau*(sum((ones(scenarios,1)*HRS').*sol.x{k},2)));
    sol.Cost_VOLL = horzcat(sol.Cost_VOLL,...
        tau*(VOLL*sol.Load_curtailed(:,k)));

    sol.Check_Load_balance(:,k) = sum(sol.x{k},2)+Wind_scenarios(:,k)-sol.Wind_curtailed(:,k)-(ones(scenarios,1)*Demand(k)-sol.Load_curtailed(:,k));
end

clearvars -except Wind_scenarios Demand options sol solution

save('Solution.mat')

