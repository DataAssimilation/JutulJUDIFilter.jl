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

observe_estimator_ensemble((params, obs_t_idx)) = observe_estimator_ensemble(params, obs_t_idx)

function observe_estimator_ensemble(params, obs_t_idx)
    if obs_t_idx <= 0
        error("Expected obs_t_idx to be >= 1. Found $obs_t_idx")
    end
    params_estimator = params.estimator

    ensemble = load_current_ensemble(params, obs_t_idx)

    observers = get_multi_time_observer(params_estimator.observation)

    observation_times, _ = get_observation_times(params_estimator.observation)
    if obs_t_idx > length(observation_times)
        error("Expected obs_t_idx to correspond to observation times. obs_t_idx is $(obs_t_idx), and there are $(length(observation_times)) observation times")
    end

    t = observation_times[obs_t_idx]

    observations = []
    observations_clean = []
    observation_times = []
    observation_means = []
    observation_clean_means = []
    name_orig = "Observe $(obs_t_idx)"
    progress_name = "$name_orig : "
    @time begin
        @withprogress name = progress_name for observer_options in observers.times_observers_dict[t]
            Random.seed!(0xabceabd47cada8f4 ⊻ hash(t))
            observer = get_observer(observer_options)
            xor_seed!(observer, UInt64(0xabc2fe2e546a031c) ⊻ hash(t))

            ## Take observation at time t.
            ensemble_obs = observer(ensemble)
            ensemble_obs_clean, ensemble_obs_noisy = split_clean_noisy(
                observer, ensemble_obs
            )

            ## Record.
            push!(observation_means, mean(ensemble_obs))
            push!(observation_clean_means, mean(ensemble_obs_clean))
            push!(observation_times, t)
            push!(observations_clean, deepcopy(ensemble_obs_clean))
            push!(observations, deepcopy(ensemble_obs_noisy))
        end
    end
    println("  ^ timing for observing ($name_orig)")

    data = Dict(
        "observation_means" => observation_means,
        "observation_clean_means" => observation_clean_means,
        "observation_times" => observation_times,
        "observations_clean" => observations_clean,
        "observations" => observations,
        "t" => t,
    )
    return data
end

function load_current_ensemble(params, obs_t_idx)
    filestem = estimator_time_stem(params, obs_t_idx)
    savedir = datadir("estimator", "data")
    file = joinpath(savedir, filestem * ".jld2")
    data = wload(file)
    return data["ensemble"]
end

function estimator_time_stem_obs(params, obs_t_idx)
    if obs_t_idx <= 0
        error("Expected obs_t_idx to be >= 1. Found $obs_t_idx")
    end
    return ground_truth_stem(params) *
           "-" *
           initial_ensemble_stem(params) *
           "-" *
           string(hash(params.estimator); base=62) *
           "-" *
           "obs" *
           "/" *
           string(obs_t_idx)
end

function produce_or_load_observe_estimator_ensemble(params, obs_t_idx; filestem=nothing, kwargs...)
    params_estimator = params.estimator
    if isnothing(filestem)
        filestem = estimator_time_stem_obs(params, obs_t_idx)
    end

    params_file = datadir("estimator", "params", "$filestem.jld2")
    wsave(params_file; params=params_estimator)

    params_file = datadir("estimator", "params", "$filestem-human.yaml")
    YAML.write_file(params_file, to_dict(params_estimator, YAMLStyle))

    savedir = datadir("estimator", "data")
    data, filepath = produce_or_load(
        observe_estimator_ensemble,
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
    produce_or_load_observe_estimator_ensemble(params, obs_t_idx)
end
