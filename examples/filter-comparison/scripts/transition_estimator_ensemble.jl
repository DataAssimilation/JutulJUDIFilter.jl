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

transition_estimator_ensemble((params, obs_t_idx)) = transition_estimator_ensemble(params, obs_t_idx)

function transition_estimator_ensemble(params, obs_t_idx)
    if obs_t_idx <= 0
        error("Expected obs_t_idx to be >= 1. Found $obs_t_idx")
    end
    params_estimator = params.estimator

    K = (Val(:Saturation), Val(:Pressure), Val(:Permeability))
    JMT = JutulModelTranslator(K)

    M = JutulModel(;
        translator=JMT, options=params_estimator.transition, kwargs=(; info_level=-1)
    )

    ensemble = load_previous_ensemble(params, obs_t_idx)
    if obs_t_idx == 1
        # Initialize member for all primary variables in simulation.
        @progress "Initialize ensemble states" for member in get_ensemble_members(ensemble)
            initialize_member!(M, member)
        end
    end

    observation_times, _ = get_observation_times(params_estimator.observation)
    if obs_t_idx > length(observation_times)
        error("Expected obs_t_idx to correspond to observation times. obs_t_idx is $(obs_t_idx), and there are $(length(observation_times)) observation times")
    end

    if obs_t_idx == 1
        t0 = 0.0
    else
        t0 = observation_times[obs_t_idx-1]
    end
    tf = observation_times[obs_t_idx]
    Δt = tf - t0

    max_transition_step = params_estimator.max_transition_step

    ## Advance ensemble to time t.
    transitioner = M
    states = []
    state_means = []
    state_times = []

    state_keys = collect(keys(ensemble.members[1]))
    name_orig = "Transition $(obs_t_idx-1) to $(obs_t_idx)"
    progress_name = "$name_orig : "
    @time begin
        t = t0
        push!(states, deepcopy(ensemble))
        push!(state_means, mean(ensemble; state_keys=state_keys))
        push!(state_times, t)
        @withprogress name = progress_name begin
            if !isnothing(max_transition_step)
                while t + max_transition_step < tf
                    ensemble = transitioner(
                        ensemble, t, t + max_transition_step; inplace=true
                    )
                    t += max_transition_step
                    @logprogress (tf - t) / Δt
                    push!(states, deepcopy(ensemble))
                    push!(state_means, mean(ensemble; state_keys=state_keys))
                    push!(state_times, t)
                end
            end
            ensemble = transitioner(ensemble, t, tf, inplace=true)
        end
    end
    println("  ^ timing for transitioning ($name_orig)")
    push!(states, deepcopy(ensemble))
    push!(state_means, mean(ensemble; state_keys=state_keys))
    push!(state_times, t)

    data = Dict(
        "states" => states,
        "state_means" => state_means,
        "state_times" => state_times,
        "ensemble" => states[end],
        "t" => state_times[end],
    )
    return data
end

function load_previous_ensemble(params, obs_t_idx)
    if obs_t_idx == 1
        # Read initial ensemble.
        data_initial, _ = produce_or_load_initial_ensemble(params; loadfile=true)
        ensemble = data_initial["ensemble"]
        return ensemble
    end
    filestem = estimator_time_stem(params, obs_t_idx-1)
    savedir = datadir("estimator", "data")
    file = joinpath(savedir, filestem * ".jld2")
    data = wload(file)
    return data["ensemble"]
end

function estimator_time_stem(params, obs_t_idx)
    if obs_t_idx <= 0
        error("Expected obs_t_idx to be >= 1. Found $obs_t_idx")
    end
    return ground_truth_stem(params) *
           "-" *
           initial_ensemble_stem(params) *
           "-" *
           string(hash(params.estimator); base=62) *
           "/" *
           string(obs_t_idx)
end

function produce_or_load_transition_estimator_ensemble(params, obs_t_idx; filestem=nothing, kwargs...)
    params_estimator = params.estimator
    if isnothing(filestem)
        filestem = estimator_time_stem(params, obs_t_idx)
    end

    params_file = datadir("estimator", "params", "$filestem.jld2")
    wsave(params_file; params=params_estimator)

    params_file = datadir("estimator", "params", "$filestem-human.yaml")
    YAML.write_file(params_file, to_dict(params_estimator, YAMLStyle))

    savedir = datadir("estimator", "data")
    data, filepath = produce_or_load(
        transition_estimator_ensemble,
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
    produce_or_load_transition_estimator_ensemble(params, obs_t_idx)
end
