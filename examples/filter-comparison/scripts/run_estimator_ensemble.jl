if abspath(PROGRAM_FILE) == @__FILE__
    params_file = abspath(ARGS[1])
    obs_t_idx = parse(Int, ARGS[2])
    if obs_t_idx <= 0
        error("Expected obs_t_idx to be >= 1. Found $obs_t_idx")
    end
end

include("install.jl")

using TerminalLoggers: TerminalLogger
using Logging: global_logger
using ProgressLogging: @progress
isinteractive() && global_logger(TerminalLogger())

using DrWatson: wsave, datadir, produce_or_load, srcdir, projectdir, scriptsdir
using Ensembles:
    Ensembles,
    Ensemble,
    get_state_keys,
    get_ensemble_matrix,
    split_clean_noisy,
    xor_seed!,
    get_ensemble_members
using Random: Random

using ConfigurationsJutulDarcy
using Configurations: to_dict, YAMLStyle
using JutulDarcy
using JutulDarcy.Jutul
using Statistics
using LinearAlgebra
using YAML: YAML

using ImageTransformations: ImageTransformations
using JLD2: JLD2

using FilterComparison

include(srcdir("jutul_model.jl"))
include(srcdir("estimator.jl"))
include(srcdir("filter_loop.jl"))

include(scriptsdir("generate_ground_truth.jl"))
include(scriptsdir("generate_initial_ensemble.jl"))

run_estimator_ensemble((params, obs_t_idx)) = run_estimator_ensemble(params, obs_t_idx)

function run_estimator_ensemble(params, obs_t_idx)
    if obs_t_idx <= 0
        error("Expected obs_t_idx to be >= 1. Found $obs_t_idx")
    end
    params_estimator = params.estimator

    ensemble, obs = load_current_ensemble_obs(params, obs_t_idx)

    estimator = get_estimator(params_estimator.algorithm)

    observers = get_multi_time_observer(params_estimator.observation)

    observation_times, _ = get_observation_times(params_estimator.observation)
    if obs_t_idx > length(observation_times)
        error("Expected obs_t_idx to correspond to observation times. obs_t_idx is $(obs_t_idx), and there are $(length(observation_times)) observation times")
    end

    t = observation_times[obs_t_idx]
    name = get_short_name(params_estimator.algorithm)
    assimilation_obs_keys = params_estimator.assimilation_obs_keys

    data_gt, _ = produce_or_load_ground_truth(params; loadfile=true)
    observations_gt = data_gt["observations"][data_gt["observation_times"] .== t]

    @assert obs["t"] == t
    observation_times = obs["observation_times"]
    observations = obs["observations"]
    observations_clean = obs["observations_clean"]

    logs = []
    states = []
    state_means = []
    state_times = []

    name_orig = "$name $(obs_t_idx)"
    progress_name = "$name_orig : "
    state_keys = collect(keys(ensemble.members[1]))
    @time begin
        @withprogress name = progress_name for i = 1:length(observations)
            ensemble_obs_clean = observations_clean[i]
            ensemble_obs_noisy = observations[i]
            y_obs = observations_gt[i]

            if !isnothing(assimilation_obs_keys)
                empty!(ensemble_obs_clean.state_keys)
                append!(ensemble_obs_clean.state_keys, assimilation_obs_keys)

                empty!(ensemble_obs_noisy.state_keys)
                append!(ensemble_obs_noisy.state_keys, assimilation_obs_keys)
            end
            ## Assimilate observation
            log_data = Dict{Symbol,Any}()
            (ensemble, timing...) = @timed assimilate_data(
                estimator,
                ensemble,
                ensemble_obs_clean,
                ensemble_obs_noisy,
                y_obs,
                log_data,
            )
            log_data[:timing] = timing

            ## Record.
            push!(logs, log_data)
            push!(states, deepcopy(ensemble))
            push!(state_means, mean(ensemble; state_keys=state_keys))
            push!(state_times, t)
        end
    end
    println("  ^ timing for $name_orig")

    data = Dict(
        "logs" => logs,
        "states" => states,
        "state_means" => state_means,
        "state_times" => state_times,
        "t" => t,
    )
    return data
end

function load_current_ensemble_obs(params, obs_t_idx)
    filestem = estimator_time_stem(params, obs_t_idx)
    savedir = datadir("estimator", "data")
    file = joinpath(savedir, filestem * ".jld2")
    data = wload(file)
    ensemble = data["ensemble"]

    filestem = estimator_time_stem_obs(params, obs_t_idx)
    savedir = datadir("estimator", "data")
    file = joinpath(savedir, filestem * ".jld2")
    obs = wload(file)
    return ensemble, obs
end

function estimator_time_stem_post(params, obs_t_idx)
    if obs_t_idx <= 0
        error("Expected obs_t_idx to be >= 1. Found $obs_t_idx")
    end
    return ground_truth_stem(params) *
           "-" *
           initial_ensemble_stem(params) *
           "-" *
           string(hash(params.estimator); base=62) *
           "-" *
           "post" *
           "/" *
           string(obs_t_idx)
end

function produce_or_load_run_estimator_ensemble(params, obs_t_idx; filestem=nothing, kwargs...)
    params_estimator = params.estimator
    if isnothing(filestem)
        filestem = estimator_time_stem_post(params, obs_t_idx)
    end

    params_file = datadir("estimator", "params", "$filestem.jld2")
    wsave(params_file; params=params_estimator)

    params_file = datadir("estimator", "params", "$filestem-human.yaml")
    YAML.write_file(params_file, to_dict(params_estimator, YAMLStyle))

    savedir = datadir("estimator", "data")
    data, filepath = produce_or_load(
        run_estimator_ensemble,
        (params, obs_t_idx),
        savedir;
        filename=filestem,
        verbose=true,
        tag=false,
        loadfile=false,
        kwargs...,
    )
    return data, filepath, filestem
end

if abspath(PROGRAM_FILE) == @__FILE__
    params = include(params_file)
    produce_or_load_run_estimator_ensemble(params, obs_t_idx)
end
