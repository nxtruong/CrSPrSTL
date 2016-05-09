dt = 3.;
f0mean = 2;
f0std = 1;
beta = [0.2; 0.];
v = [0.7; 0.7];
w = [0.2; 0.2];
% nbar = [20.; 20.];
fbar = [3.; 3.];
nbar = fbar./v + fbar./w;
rbar = [1.5; 1.5];
dmean = [2.; 2.];
dstd = [2; 2];
T = 20;
sys = Freeway_approx(dt, f0mean, f0std, beta, v, w, fbar, nbar, rbar, dmean, dstd, T);
sys.set_objective(Sum(@(t, dt) -sum(sys.x(t, 3:4))+sum(sys.x(t, 1:2))));
sys.run_closed_loop(20, 0., 60.);