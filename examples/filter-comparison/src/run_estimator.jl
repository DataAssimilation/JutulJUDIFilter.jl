include("install.jl")

using TerminalLoggers: TerminalLogger
using Logging: global_logger
using ProgressLogging: @progress
isinteractive() && global_logger(TerminalLogger())

using DrWatson: wsave, datadir, produce_or_load, srcdir
using Ensembles:
    Ensembles,
    Ensemble,
    NoisyObserver,
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

include("jutul_model.jl")
include("options.jl")
include("observer.jl")
include("estimator.jl")
include("filter_loop.jl")

# include(srcdir("filter.jl"))
include(srcdir("generate_ground_truth.jl"))
include(srcdir("generate_initial_ensemble.jl"))
# include(srcdir("filter_loop.jl"))

function run_estimator(params)
    params_estimator = params.estimator
    data_gt, _ = produce_or_load_ground_truth(params; loadfile=true)

    data_initial, _ = produce_or_load_initial_ensemble(params; loadfile=true)

    states_gt = data_gt["states"]
    observations_gt = data_gt["observations"]

    ensemble = data_initial["ensemble"]

    K = (Val(:Saturation), Val(:Pressure), Val(:Permeability))
    JMT = JutulModelTranslator(K)

    M = JutulModel(; translator=JMT, options=params_estimator.transition)
    observers = get_multi_time_observer(params_estimator.observation)

    # Initialize member for all primary variables in simulation.
    @progress "Initialize ensemble states" for member in get_ensemble_members(ensemble)
        initialize_member!(M, member)
    end

    global estimator = get_estimator(params_estimator.algorithm)

    empty!(ensemble.state_keys)
    append!(ensemble.state_keys, params_estimator.assimilation_keys)

    t0 = 0.0
    return data = filter_loop(
        ensemble,
        t0,
        estimator,
        M,
        observers,
        observations_gt;
        name=get_short_name(params_estimator.algorithm),
    )
end

function filter_stem(params)
    return ground_truth_stem(params) *
           "-" *
           initial_ensemble_stem(params) *
           "-" *
           string(hash(params.estimator); base=62)
end

function produce_or_load_run_estimator(params; kwargs...)
    params_estimator = params.estimator
    filestem = filter_stem(params)

    params_file = datadir("estimator", "params", "$filestem.jld2")
    wsave(params_file; params=params_estimator)

    params_file = datadir("estimator", "params", "$filestem-human.yaml")
    YAML.write_file(params_file, to_dict(params_estimator, YAMLStyle))

    savedir = datadir("estimator", "data")
    data, filepath = produce_or_load(
        run_estimator,
        params,
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
    produce_or_load_run_estimator(params)
end
