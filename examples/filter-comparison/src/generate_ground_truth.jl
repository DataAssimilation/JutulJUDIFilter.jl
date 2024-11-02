
include("install.jl")

using TerminalLoggers: TerminalLogger
using Logging: global_logger
using ProgressLogging: @progress
isinteractive() && global_logger(TerminalLogger())

using DrWatson: wsave, datadir, produce_or_load
using Ensembles:
    Ensembles,
    NoisyObserver,
    get_state_keys,
    get_ensemble_matrix,
    split_clean_noisy,
    xor_seed!
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

include("jutul_model.jl")

include("../params/small-params.jl")

# Generate synthetic ground-truth observations.
function generate_ground_truth(params)
    K = (Val(:Saturation), Val(:Pressure))
    # K = (Val(:OverallMoleFraction), Val(:Pressure))
    state_keys = (:Saturation, :Pressure)
    # state_keys = (:OverallMoleFraction, :Pressure)
    JMT = JutulModelTranslator(K)

    options = params.transition
    options = JutulOptions(
        options; time=(TimeDependentOptions(options.time[1]; years=1.0, steps=1),)
    )
    M = JutulModel(; translator=JMT, options)

    observation_times = let
        step = params.observation.timestep_size
        length = params.observation.num_timesteps + 1
        range(; start=0, length, step)
    end

    ## Make operators.
    # transitioner = JutulModel(; params)
    observer = NoisyObserver(state_keys; params=params.observation)

    ## Set seed for ground-truth simulation.
    Random.seed!(0xfee55e45)
    xor_seed!(observer, UInt64(0x243ecae5))

    ground_truth = @time let
        state = Dict{Symbol,Any}()
        sim_to_member!(JMT, state, M.state0, M.domain)

        ## Set seed for ground-truth simulation.
        Random.seed!(0xfee55e45)
        xor_seed!(observer, UInt64(0x243ecae5))

        ## Generate states and observations.
        t0 = 0.0
        states = Vector{Dict{Symbol,Any}}(undef, length(observation_times))
        observations = Vector{Dict{Symbol,Any}}(undef, length(observation_times))
        states[1] = deepcopy(state)
        observations[1] = observer(state)
        @progress "Ground-truth" for (i, t) in enumerate(observation_times[2:end])
            state = M(state, t0, t)
            obs = observer(state)
            states[i + 1] = deepcopy(state)
            observations[i + 1] = split_clean_noisy(observer, obs)[2]
            t0 = t
        end
        (; states, observations)
    end
    println("  ^ timing for making ground truth data")
    return data = Dict(
        "states" => ground_truth.states,
        "observations" => ground_truth.observations,
        "observation_times" => observation_times,
    )
end

function ground_truth_stem(params)
    return string(hash(params.ground_truth); base=62)
end

function produce_or_load_ground_truth(params::JutulJUDIFilterOptions; kwargs...)
    params_gt = params.ground_truth
    filestem = ground_truth_stem(params)

    params_file = datadir("ground_truth", "params", "$filestem.jld2")
    wsave(params_file; params=params_gt)

    params_file = datadir("ground_truth", "params", "$filestem-human.yaml")
    YAML.write_file(params_file, to_dict(params_gt, YAMLStyle))

    savedir = datadir("ground_truth", "data")
    data, filepath = produce_or_load(
        generate_ground_truth,
        params_gt,
        savedir;
        filename=filestem,
        verbose=false,
        tag=false,
        loadfile=false,
        kwargs...,
    )
    return data, filepath, filestem
end

if abspath(PROGRAM_FILE) == @__FILE__
    params_file = abspath(ARGS[1])
    params = include(params_file)
    produce_or_load_ground_truth(params)
end
