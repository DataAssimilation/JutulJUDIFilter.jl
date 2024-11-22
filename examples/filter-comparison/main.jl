# # Digital Shadows in Julia
# 
# This tutorial demonstrates how to create and work with digital shadows for CO₂ storage monitoring using Julia. We'll use ensemble-based data assimilation to combine physical models with real-time observations.
# 
# ## Introduction to digital shadows
# 
# A digital shadow is a virtual representation of a physical system that is updated with real data. In the context of CO₂ storage, our digital shadow will:
# 
# 1. Simulate CO₂ plume migration in the subsurface
# 2. Incorporate seismic monitoring data
# 3. Update predictions based on observations
# 
# ## Setup and Installation
# 
# First, we'll install and load the required packages. This tutorial uses:
# 
# - [JutulDarcy](https://sintefmath.github.io/JutulDarcy.jl): for CO₂ flow simulation
# - [JUDI](https://slimgroup.github.io/JUDI.jl): for seismic modeling
# - [Makie](https://docs.makie.org/): For visualization
# - [JLD2](https://juliaio.github.io/JLD2.jl): for saving data
# - [DrWatson](https://juliadynamics.github.io/DrWatson.jl/stable/): for ease of saving and accessing data
# - Other utility packages
# - Scripts for data assimilation
# 
# But it also uses packages that Grant is currently developing to facilitate our digital twins research:
# 
# - [Ensembles.jl](https://github.com/DataAssimilation/Ensembles.jl)
# - [EnsembleKalmanFilters.jl](https://github.com/DataAssimilation/EnsembleKalmanFilters.jl)
# - [ConfigurationsJutulDarcy.jl](https://github.com/DataAssimilation/ConfigurationsJutulDarcy.jl)
# - [JutulJUDIFilter.jl](https://github.com/DataAssimilation/JutulJUDIFilter.jl)
# 
# Since these unreleased packages are not in the Julia package registry, we here use an `install.jl` script to add them by url.
using Pkg
Pkg.activate("./")
ENV["jutuljudifilter_force_install"] = "true"
include("scripts/install.jl")
ENV["jutuljudifilter_force_install"] = "false";
Base.active_project()
#
include("scripts/generate_ground_truth.jl")
include("scripts/generate_initial_ensemble.jl")
include("scripts/run_estimator.jl")
using CairoMakie
using JutulJUDIFilter
using JLD2

# ## Mathematical framework
# 
# Our digital twin system is based on two key components:
# 
# 1. **State evolution**: The system state $x$ evolves over time according to the transition operator $\mathcal{M}$ such that
#    $x_{t+1} = \mathcal{M}(x_t)$
# 
# 2. **Observations**: We observe the state indirectly through measurements $y$ using the observation operator $\mathcal{H}$ such that
#    $y_t = \mathcal{H}(x_t)$
# 
# ### CO₂ plume physics
# 
# The transition operator $\mathcal{M}$ models:
# - Two-phase flow (CO₂ and water)
# - Pressure evolution
# - Density and viscosity effects
# - Permeability and porosity influences
# 
# See `src/jutul_model.jl` for the interface we use to set up and call JutulDarcy for simulating the fluid flow.
# 
# ### Seismic monitoring
# 
# The observation operator $\mathcal{H}$ represents:
# - Seismic wave propagation
# - Rock physics relationships
# - Acquisition geometry
# 
# See `src/seismic_model.jl` for the interface we use to set up and call JUDI.

# ## Generate ground truth data
# 
# We'll create synthetic data to represent the "true" system we want to monitor. This includes:
# 1. A permeability field
# 2. CO₂ injection scenario
# 3. Resulting seismic observations
# 
# We can print out a readable format of the ground-truth params as YAML.
params = include("params/tutorial-params.jl")
filestem = "tutorial"

params_gt = params.ground_truth

params_file = datadir("ground_truth", "params", "$filestem.jld2")
wsave(params_file; params=params_gt)

params_file = datadir("ground_truth", "params", "$filestem-human.yaml")
YAML.write_file(params_file, to_dict(params_gt, YAMLStyle))

# ### Transition parameters
println(YAML.write(to_dict(params_gt.transition, YAMLStyle)))

# ### Observation parameters
println(
    "Observation times (seconds): $([o.first for o in params_gt.observation.observers])"
)
println()
println(YAML.write(to_dict(params_gt.observation.observers[1].second, YAMLStyle)))

# ### Simulate ground-truth transitions and observations
# 
# This code uses DrWatson's `produce_or_load` functionality. It checks the given `filename`
# for the data, and if it doesn't exist, the data is generated with
# `generate_ground_truth` defined in `scripts/generate_ground_truth.jl`.
savedir = datadir("ground_truth", "data")
data_gt, filepath = produce_or_load(
    generate_ground_truth, params_gt, savedir; filename=filestem, verbose=true, force=false
)
states = data_gt["states"]
observations = data_gt["observations"]
observations_clean = data_gt["observations_clean"]
state_times = data_gt["state_times"]
observation_times = data_gt["observation_times"];

# ## Visualize ground-truth data
# 
# Let's look at the generated data. First, we'll check some basic information about the data.
@show length(states)
println()
@show length(state_times)
println()
@show keys(states[1])
println()
@show keys(observations[1])
println()
@show length(observations)
println()
@show length(observation_times);

# ### Prepare to plot.
# This sets up the plotting library and gets mesh information we can use for plotting.
CairoMakie.activate!()
update_theme!(; fontsize=24)
function Makie.resize_to_layout!(fig, content_layout)
    Makie.update_state_before_display!(fig)
    bbox = Makie.GridLayoutBase.tight_bbox(content_layout)
    new_size = (widths(bbox)...,)
    return resize!(fig.scene, widths(bbox)...)
end
grid_2d = get_2d_plotting_mesh(params_gt.transition.mesh)

# ### Show ground-truth permeability
# 
# The permeability is a second-order diagonal tensor field. Here, we plot the lateral component of the permeability.
fig = Figure()
data = states[1][:Permeability]
@show size(data)
content_layout = GridLayout(fig[1, 1])
plot_scalar_field(
    content_layout,
    Observable(data[1, :]);
    grid_2d,
    heatmap_kwargs=(; colormap=Reverse(:Purples)),
)
resize_to_layout!(fig, content_layout)
fig

# ### Show ground-truth plume over time
# Here I use Makie.jl to easily visualize the time-dependent stats over time.
fig = Figure()
t_idx = Observable(1)
data = @lift(states[$t_idx][:Saturation])
content_layout = GridLayout(fig[1, 1])
ax = plot_scalar_field(
    content_layout, data; grid_2d, heatmap_kwargs=(; colorrange=(0, 1), colormap=parula)
)

label = lift(t_idx -> "Saturation at time step $(t_idx)", t_idx)
Label(fig[1, 1, Top()], label)
resize_to_layout!(fig, content_layout)

Record(fig, 1:length(states); framerate=1) do i
    t_idx[] = i
end

#
fig = Figure()
t_idx = Observable(1)
data = @lift(states[$t_idx][:Pressure] .- states[1][:Pressure])
content_layout = GridLayout(fig[1, 1])
plot_scalar_field(
    content_layout,
    data;
    grid_2d,
    heatmap_kwargs=(; make_divergent=true, colormap=Reverse(:RdBu)),
)

label = lift(t_idx -> "Pressure difference at time step $(t_idx)", t_idx)
Label(fig[1, 1, Top()], label)
resize_to_layout!(fig, content_layout)

Record(fig, 1:length(states); framerate=1) do i
    t_idx[] = i
end

#
fig = Figure()
t_idx = Observable(1)
data = @lift(observations[$t_idx][:rtm] .- observations[1][:rtm])
content_layout = GridLayout(fig[1, 1])
plot_scalar_field(
    content_layout,
    data;
    grid_2d,
    heatmap_kwargs=(; make_divergent=true, colormap=Reverse(:RdBu)),
)

label = lift(t_idx -> "Time-lapse RTM at time step $(t_idx)", t_idx)
Label(fig[1, 1, Top()], label)
resize_to_layout!(fig, content_layout)

Record(fig, 1:length(states); framerate=1) do i
    t_idx[] = i
end

#
fig = Figure(; size=(1000, 520))
t_idx = Observable(1)
function dshot_diff(state)
    return [d .- d0 for (d0, d) in zip(observations[1][:dshot], state[:dshot])]
end
data = @lift(dshot_diff(observations[$t_idx]))
content_layout = GridLayout(fig[1, 1])
timeR = @lift(params_gt.observation.observers[$t_idx].second.seismic.timeR)
dtR = @lift(params_gt.observation.observers[$t_idx].second.seismic.dtR)
nsrc = params_gt.observation.observers[1].second.seismic.source_receiver_geometry.nsrc
plot_data(
    content_layout,
    data,
    nothing,
    :dshot;
    heatmap_kwargs=(; make_divergent=true, colormap=Reverse(:RdBu)),
    nsrc,
    timeR,
    dtR,
)

label = lift(t_idx -> "Time-lapse shot data at time step $(t_idx)", t_idx)
Label(fig[1, 1, Top()], label)
resize_to_layout!(fig, content(content_layout[1, 1][2, 1]))

Record(fig, 1:length(states); framerate=1) do i
    t_idx[] = i
end

# ## Generate initial ensemble
# 
# First, we'll look at the parameters for this script.
params_file = datadir("initial_ensemble", "params", "$filestem.jld2")
wsave(params_file; params=params.ensemble)

params_file = datadir("initial_ensemble", "params", "$filestem-human.yaml")
YAML.write_file(params_file, to_dict(params.ensemble, YAMLStyle))

println(YAML.write(to_dict(params.ensemble, YAMLStyle)))

# ### Run generation code
# This code again uses DrWatson's `produce_or_load` functionality to avoid building the ensemble unnecessarily.
savedir = datadir("initial_ensemble", "data")
data_initial, filepath = produce_or_load(
    generate_initial_ensemble,
    params.ensemble,
    savedir;
    filename=filestem,
    verbose=false,
    loadfile=true,
)
ensemble = data_initial["ensemble"];

# ## Visualize initial ensemble data
# 
# Let's look at the generated data. First, we'll check some basic information about the data.
@show length(ensemble.members)
println()
@show keys(ensemble.members[1]);

# ### Visualize ensemble permeabilities
fig = Figure()
e_idx = Observable(1)
data = @lift(ensemble.members[$e_idx][:Permeability][1, :])
content_layout = GridLayout(fig[1, 1])
plot_scalar_field(
    content_layout, data; grid_2d, heatmap_kwargs=(; colormap=Reverse(:Purples))
)

label = lift(e_idx -> "Permeability sample $(e_idx)", e_idx)
Label(fig[1, 1, Top()], label)
resize_to_layout!(fig, content_layout)

Record(fig, 1:min(length(ensemble.members), 64); framerate=2) do i
    e_idx[] = i
end

# ### Visualize ensemble saturations
fig = Figure()
e_idx = Observable(1)
data = @lift(ensemble.members[$e_idx][:Saturation])
content_layout = GridLayout(fig[1, 1])
ax = plot_scalar_field(
    content_layout, data; grid_2d, heatmap_kwargs=(; colorrange=(0, 1), colormap=parula)
)

label = lift(e_idx -> "Saturation sample $(e_idx)", e_idx)
Label(fig[1, 1, Top()], label)
resize_to_layout!(fig, content_layout)

Record(fig, 1:min(length(ensemble.members), 64); framerate=2) do i
    e_idx[] = i
end

# ## Run estimator
# 
# We'll start out by printing out the parameters again.
# 
# The parameters for the estimator include:
# 
# - transition parameters
# - observation parameters
# - assimilation parameters
params_file = datadir("estimator", "params", "$filestem.jld2")
wsave(params_file; params=params.estimator)

params_file = datadir("estimator", "params", "$filestem-human.yaml")
YAML.write_file(params_file, to_dict(params.estimator, YAMLStyle))

# ### Transition parameters
if params.estimator.transition == params.ground_truth.transition
    println("Same transition parameters as ground truth.")
else
    println(YAML.write(to_dict(params.estimator.transition, YAMLStyle)))
end

# ### Observation parameters
if params.estimator.observation == params.ground_truth.observation
    println("Same observation parameters as ground truth.")
else
    println(
        "Observation times (seconds): $([o.first for o in params.estimator.observation.observers])",
    )
    println()
    println(
        YAML.write(to_dict(params.estimator.observation.observers[1].second, YAMLStyle))
    )
end

# ### Run assimilation loop
# 
# This could use DrWatson's `produce_or_load`, but I want to show what this code looks like.
## Get the data we need from earlier in the tutorial.
observations_gt = data_gt["observations"]
ensemble = deepcopy(data_initial["ensemble"])

## Set the parameters that can be updated during assimilation.
empty!(ensemble.state_keys)
append!(ensemble.state_keys, params.estimator.assimilation_state_keys)

## Define which parameters will be passed to JutulModel.
K = (Val(:Saturation), Val(:Pressure), Val(:Permeability))
JMT = JutulModelTranslator(K)

## Create transitioner.
M = JutulModel(;
    translator=JMT, options=params.estimator.transition, kwargs=(; info_level=-1)
)

## Create observers.
observers = get_multi_time_observer(params.estimator.observation)
@show observers.times;

#
## Initialize each member for all primary variables in simulation.
@show keys(ensemble.members[1])
@progress "Initialize ensemble states" for member in get_ensemble_members(ensemble)
    initialize_member!(M, member)
end
@show keys(ensemble.members[1]);

#
## Create the object for running the assimilation algorithm.
estimator = get_estimator(params.estimator.algorithm)

## Run the predict-update loop.
t0 = 0.0
data_estimator = filter_loop(
    ensemble,
    t0,
    estimator,
    M,
    observers,
    observations_gt;
    name=get_short_name(params.estimator.algorithm),
    max_transition_step=params.estimator.max_transition_step,
    assimilation_obs_keys=params.estimator.assimilation_obs_keys,
)
savedir = datadir("estimator", "data")
mkpath(savedir)
let data = data_estimator
    data = Dict(Symbol(k) => v for (k, v) in data)
    jldsave(joinpath(savedir, "tutorial-estimator.jld2"); data...)
end

# ## Visualize estimator results
# 
# First, we'll look at the times that the data is collected.
display(keys(data_estimator))
@show data_estimator["observation_times"]
println()
@show data_estimator["state_times"];

# ### Visualize estimated saturation
fig = Figure()
t_idx = Observable(1)
state_times = data_estimator["state_times"]
states_estimator = data_estimator["state_means"]
data = @lift(states_estimator[$t_idx][:Saturation])
content_layout = GridLayout(fig[1, 1])
ax = plot_scalar_field(
    content_layout, data; grid_2d, heatmap_kwargs=(; colorrange=(0, 1), colormap=parula)
)

label = lift(
    t_idx -> "Estimated saturation at year $(state_times[t_idx]/365.2425/24/3600)", t_idx
)
Label(fig[1, 1, Top()], label)
resize_to_layout!(fig, content_layout)

Record(fig, 1:length(states_estimator); framerate=1) do i
    t_idx[] = i
end

# ### Visualize saturation uncertainty
#
# Here, we visualize the standard deviation of the samples.
fig = Figure()
t_idx = Observable(1)
state_estimator_stds = [std(ensemble) for ensemble in data_estimator["states"]]
data = @lift(state_estimator_stds[$t_idx][:Saturation])
content_layout = GridLayout(fig[1, 1])
ax = plot_scalar_field(
    content_layout, data; grid_2d, heatmap_kwargs=(; colorrange=(0, 1), colormap=parula)
)

label = lift(
    t_idx -> "Estimated saturation std at year $(state_times[t_idx]/365.2425/24/3600)",
    t_idx,
)
Label(fig[1, 1, Top()], label)
resize_to_layout!(fig, content_layout)

Record(fig, 1:length(states_estimator); framerate=1) do i
    t_idx[] = i
end

# ## Custom estimator
# 
# This software framework is designed to be extensible. Let's design our own estimator algorithm.
# 
# There are two key ingredients:
# 
# 1. We need to define a struct with any information we need for the filter.
# 2. We need to overload the `assimilate_data` function to do our custom estimator algorithm.

## Struct definitions cannot be changed without restarting the kernel.
## To bypass that restrict, we alias the name of the struct,
## and if we want to change it, we change the struct name while keeping the alias the same.
struct MyEstimator1
    scale
end
MyEstimator = MyEstimator1;

#
using Ensembles:
    Ensembles, Ensemble, get_ensemble_matrix, get_ensemble_dicts, get_member_vector

function Ensembles.assimilate_data(
    estimator::MyEstimator,
    ensemble,
    ensemble_obs_clean,
    ensemble_obs_noisy,
    y_obs,
    log_data,
)
    X = Float64.(get_ensemble_matrix(ensemble))
    Y = Float64.(get_ensemble_matrix(ensemble_obs_noisy))
    y_true = get_member_vector(ensemble_obs_noisy, y_obs)

    X_updated = X .* estimator.scale
    clamp!(X_updated, 0.0, 1.0)

    members = get_ensemble_dicts(ensemble, X_updated)
    posterior = Ensemble(members, ensemble.state_keys)
    return posterior
end

#
custom_estimator = MyEstimator(1.5)
ensemble = deepcopy(data_initial["ensemble"])

# Set the parameters that can be updated during assimilation.
empty!(ensemble.state_keys)
append!(ensemble.state_keys, params.estimator.assimilation_state_keys)

# Initialize each member for all primary variables in simulation.
@progress "Initialize ensemble states" for member in get_ensemble_members(ensemble)
    initialize_member!(M, member)
end

# Run the predict-update loop.
data_custom = filter_loop(
    ensemble,
    t0,
    custom_estimator,
    M,
    observers,
    observations_gt;
    name=string(custom_estimator),
    max_transition_step=params.estimator.max_transition_step,
    assimilation_obs_keys=params.estimator.assimilation_obs_keys,
)
let data = data_custom
    data = Dict(Symbol(k) => v for (k, v) in data)
    jldsave(joinpath(savedir, "tutorial-custom.jld2"); data...)
end

# ### Visualize custom results
fig = Figure()
t_idx = Observable(1)
state_times = data_custom["state_times"]
states_custom = data_custom["state_means"]
data = @lift(states_custom[$t_idx][:Saturation])
content_layout = GridLayout(fig[1, 1])
ax = plot_scalar_field(
    content_layout, data; grid_2d, heatmap_kwargs=(; colorrange=(0, 1), colormap=parula)
)

label = lift(
    t_idx ->
        "$(custom_estimator) saturation at year $(state_times[t_idx]/365.2425/24/3600)",
    t_idx,
)
Label(fig[1, 1, Top()], label)
resize_to_layout!(fig, content_layout)

Record(fig, 1:length(states_custom); framerate=1) do i
    t_idx[] = i
end

#
fig = Figure()
t_idx = Observable(1)
state_custom_stds = [std(ensemble) for ensemble in data_custom["states"]]
data = @lift(state_custom_stds[$t_idx][:Saturation])
content_layout = GridLayout(fig[1, 1])
ax = plot_scalar_field(
    content_layout, data; grid_2d, heatmap_kwargs=(; colorrange=(0, 1), colormap=parula)
)

label = lift(
    t_idx ->
        "$(custom_estimator) saturation std at year $(state_times[t_idx]/365.2425/24/3600)",
    t_idx,
)
Label(fig[1, 1, Top()], label)
resize_to_layout!(fig, content_layout)

Record(fig, 1:length(state_custom_stds); framerate=1) do i
    t_idx[] = i
end

# ## Conclusion
# 
# In this tutorial, we've demonstrated setting up a digital shadow for CO₂ storage.
# 
# The framework can be extended to use other algorithms that update samples based on observations.
# 
# ### Future Improvements
# 1. Documentation
# 2. Interface for easily parallelization
# 3. More parameters and more uncertain parameters
# 4. More estimators (JustObs, NF, ...)
# 5. Joint state-parameter estimation
