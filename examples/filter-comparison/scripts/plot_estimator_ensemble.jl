
params_file = abspath(ARGS[1])
include("../src/install.jl")

using TerminalLoggers: TerminalLogger
using Logging: global_logger
isinteractive() && global_logger(TerminalLogger())
using ProgressLogging: @withprogress, @logprogress

using DrWatson: srcdir, datadir, plotsdir, produce_or_load, wsave
using CairoMakie: Label
using Format: cfmt
using JutulJUDIFilter
using Statistics: mean, std

include(srcdir("generate_initial_ensemble.jl"))
include(srcdir("run_estimator.jl"))
include(srcdir("plotting_plumes.jl"))

# Read data.
params = include(params_file)
data_ensemble, _, filestem_ensemble = produce_or_load_run_estimator(params; loadfile=true, force=false)

ensembles = data_ensemble["ensembles"]
save_dir_root = plotsdir("estimator_ensemble", "states", filestem_ensemble)
with_theme(theme_latexfonts()) do
    update_theme!(; fontsize=30)

    state_keys = collect(keys(ensembles[1].ensemble.members[1]))

    ensemble_times = [e.t for e in ensembles]
    states = [mean(e.ensemble; state_keys=state_keys) for e in ensembles]
    plot_states(ensemble_times, states, params.estimator; save_dir_root=joinpath(save_dir_root, "mean"))

    states = [std(e.ensemble; state_keys=state_keys) for e in ensembles]
    plot_states(ensemble_times, states, params.estimator; save_dir_root=joinpath(save_dir_root, "var"))

    ensemble_times = [e.t for e in ensembles]
    for i = 1:min(length(ensembles[1].ensemble.members), 2)
        states = [e.ensemble.members[i] for e in ensembles]
        plot_states(ensemble_times, states, params.estimator; save_dir_root=joinpath(save_dir_root, "e$i"), try_interactive=false)
    end
    # for (i, ensemble_info) in enumerate(ensembles)
    #     ensemble = ensemble_info.ensemble
    #     plot_states(1:length(ensemble.members), ensemble.members, params.estimator; save_dir_root=joinpath(save_dir_root, string(i)))
    # end
end

nothing
