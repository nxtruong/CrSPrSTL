classdef System < handle
    % class: System: We define a dynamical system
    % properties: dt,x,u,y, dynamics, constraints, objective
    % methods: signals: returns x,u,y
    %          set_objective: returns sum of a given function
    %          set_dynamics: used for setting the dynamics if already
    %                        given.
    %          set_lti_dynamics: sets A,B,C,D and dimensions and translates
    %                            them to constraints.
    %          add_constraint: Allows adding additional constraints.
    %          add_dyn_constraint: Allows creating constraints that get
    %                              updated at every time step.
    %          create_plotter: Adds signals to be plotted.
    %          run_open_loop: Optimizes the objective for one horizon.
    %          run_closed_loop: MPC optimization of objective for horizon L
    %                           from time t1 to t2.
    
    properties
        history
        movie
    end
    
    properties
        dt
        x
        u
        y
        dynamics
        constraints
        dyn_constraints
        objective
    end
    
    methods
        function [x, u, y] = signals(self)
            x = self.x;
            u = self.u;
            y = self.y;
        end
        
        function self = System(dt)
            self.dt = dt;
            self.constraints = {};
            self.dyn_constraints = {};
            self.dynamics = AndPredicate();
            self.objective = Sum();
        end
        
        function set_objective(self, objective)
            if isa(objective, 'Objective')
                self.objective = objective;
            else
                self.objective = Sum(objective);
            end
        end
        
        function set_dyn_objective(self, objective)
            self.objective = objective;
        end
        
        function set_dynamics(self, dyn)
            self.dynamics = dyn;
            if isa(dyn, 'Dynamics')
                self.x = Signal(self.dt, length(dyn.x));
                self.u = Signal(self.dt, length(dyn.u));
                self.y = Signal(self.dt, length(dyn.g));
            end
        end
        
        function set_dimensions(self, nx, nu, ny)
            if nargin <= 3
                ny = 0;
            end
            self.x = Signal(self.dt, nx);
            self.u = Signal(self.dt, nu);
            self.y = Signal(self.dt, ny);
        end
        
        function set_lti_dynamics(self, varargin)
            switch numel(varargin)
                case 2
                    A = varargin{1};
                    Bu = varargin{2};
                    C = [];
                    Du = [];
                case 3
                    A = varargin{1};
                    Bu = varargin{2};
                    C = varargin{3};
                case 4
                    A = varargin{1};
                    Bu = varargin{2};
                    C = varargin{3};
                    Du = varargin{4};
                otherwise
                    error('Invalid initialization');
            end
            nx = max([size(A, 1), size(Bu, 1)]);
            nu = max([size(Bu, 2), size(Du, 2)]);
            if nu == 0
                error('We need at least one control variable')
            end
            ny = max([size(C, 1), size(Du, 1)]);
            if isempty(A)
                A = zeros(nx, nx);
            end
            if isempty(Bu)
                Bu = zeros(nx, nu);
            end
            if isempty(C)
                C = zeros(ny, nx);
            end
            if isempty(Du)
                Du = zeros(ny, nu);
            end
            dyn = Dynamics(nx, nu);
            [x, u, ~] = dyn.symbols(); %#ok<PROP>
            dyn.set_f(A*x+Bu*u); %#ok<PROP>
            dyn.set_g(C*x+Du*u); %#ok<PROP>
            self.set_dynamics(dyn);
%             sysc = ss(A, Bu, C, Du);
%             sysd = c2d(sysc, self.dt);
%             self.x = Signal(self.dt, nx);
%             self.u = Signal(self.dt, nu);
%             self.y = Signal(self.dt, ny);
%             if nx>0
%                 dyn1 = P(@(t, dt) self.x(t+dt)==sysd.A*self.x(t)+sysd.B*self.u(t));
%             else
%                 dyn1 = AndPredicate();
%             end
%             if ny>0
%                 dyn2 = P(@(t, dt) self.y(t)==sysd.C*self.x(t)+sysd.D*self.u(t));
%             else
%                 dyn2 = AndPredicate();
%             end
%             self.dynamics = dyn1&dyn2;
        end
        
        function add_constraint(self, constraint)
            self.constraints = [self.constraints, {constraint}];
        end
        
        function add_dyn_constraint(self, constraint)
            if isa(constraint, 'function_handle')
                switch nargin(constraint)
                    case 0
                        f = @(x0, t, dt) constraint();
                    case 1
                        f = @(x0, t, dt) constraint(x0);
                    case 2
                        f = @(x0, t, dt) constraint(x0, t);
                    case 3
                        f = constraint;
                    otherwise
                        error('Invalid number of input arguments');
                end
            elseif isa(constraint, 'char')
                f = evalin('caller', ['@(x0, t, dt) ' constraint]);
            else
                f = @(x0, t, dt) constraint;
            end
            self.dyn_constraints = [self.dyn_constraints {f}];
        end
        
        %function plotter = create_plotter(self)
        %    plotter = Plotter();
        %    plotter.add_signal('x', self.x);
        %    plotter.add_signal('u', self.u);
        %    plotter.add_signal('y', self.y);
        %end
        
        
        function run_open_loop(self, t1, t2)
            ts = t1:self.dt:t2;
            %plotter = self.create_plotter();
            if isa(self.dynamics, 'Predicate')
                self.objective.minimize(ts, self.dt, AndPredicate(always(self.dynamics), self.constraints{:}));
            else
                self.objective.minimize(t1, self.dt, AndPredicate(self.constraints{:}));
                x0 = value(self.x(t1));
                u0 = value(self.u(t1));
                local_dynamics = self.dynamics.local_dynamics(self.dt, x0, u0, t1, self.x, self.u, self.y);
                self.objective.minimize(ts, self.dt, AndPredicate(always(local_dynamics), self.constraints{:}));
            end
            %plotter.capture_future(ts);
        end
        
        function initialize(self, t)
            self.history = struct('t', [], 'x', [], 'u', [], 'y', []);
            Sum().minimize(t, self.dt, AndPredicate(self.constraints{:}));
            self.history.x(:, end+1) = value(self.x(t));
            self.history.t(:, end+1) = t;
        end
        
        function find_control(self, L, t)
            x0 = self.history.x(:, end);
            u0 = value(self.u(t));
            if size(self.history.u, 2)>0
                u0 = self.history.u(:, end);
            end
            T1 = max(t-self.dt*L, self.history.t(1));
            T2 = t+self.dt*L;
            past = T1:self.dt:t-self.dt;
            past_ind = max(length(self.history.t)-L, 1):length(self.history.t)-1;
            x_past = self.history.x(:, [past_ind length(self.history.t)]);
            u_past = self.history.u(:, past_ind);
            y_past = self.history.y(:, past_ind);
            keep_past = P(@(tprime, dt) self.x([past t])==x_past);
            if ~isempty(past)
                keep_past = AndPredicate(keep_past, P(@(t, dt) self.u(past)==u_past), P(@(t, dt) self.y(past)==y_past));
            end
            if isa(self.dynamics, 'Predicate')
                dynamics = self.dynamics; 
            else
                dynamics = self.dynamics.local_dynamics(self.dt, x0, u0, t, self.x, self.u, self.y); %#ok<PROP>
            end
            dynamic_constraints = {};
            for i = 1:length(self.dyn_constraints)
                dynamic_constraints{i} = self.dyn_constraints{i}(x0, t, self.dt); %#ok<AGROW>
            end
            dyn_constraint = always(AndPredicate(dynamic_constraints{:}), t-T1, t-T1);
            if isa(self.objective, 'Objective')
                objective = self.objective;
            else
                objective = self.objective(x0, t, self.dt);
            end
            diag = objective.minimize(T1:self.dt:T2, self.dt, AndPredicate(self.constraints{:}, always(dynamics, t-T1, inf), keep_past, dyn_constraint)); %#ok<PROP>
            if diag.problem
                error('Model is infeasible at time %0.2f', t);
            end
            self.history.u(:, end+1) = value(self.u(t));
            self.history.y(:, end+1) = value(self.y(t));
        end
        
        function advance(self, t)
            if isa(self.dynamics, 'Predicate')
                self.history.x(:, end+1) = value(self.x(t+self.dt));
            else
                x0 = self.history.x(:, end);
                u0 = self.history.u(:, end);
                t0 = t;
                self.history.x(:, end+1) = self.dynamics.x_next(self.dt, x0, u0, t0);
            end
            self.history.t(:, end+1) = t+self.dt;
        end
        
        function run_closed_loop(self, L, t1, t2)
            env = Environment(self);
            env.run_closed_loop(L, t1, t2);
        end
        
        function plotter_hook(self, plotter)
        end
    end
    
end

