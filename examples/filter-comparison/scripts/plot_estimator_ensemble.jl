
params_file = abspath(ARGS[1])
include("install.jl")

using TerminalLoggers: TerminalLogger
using Logging: global_logger
isinteractive() && global_logger(TerminalLogger())
using ProgressLogging: @withprogress, @logprogress

using DrWatson: srcdir, datadir, plotsdir, produce_or_load, wsave, projectdir, scriptsdir
using CairoMakie: Label
using Format: cfmt
using JutulJUDIFilter
using Statistics: mean, std

using FilterComparison

include(scriptsdir("generate_initial_ensemble.jl"))
include(scriptsdir("run_estimator.jl"))

# Read data.
params = include(params_file)
data_ensemble, _, filestem_ensemble = produce_or_load_run_estimator(
    params; loadfile=true, force=false
)


state_means = data_ensemble["state_means"]
state_stds = data_ensemble["state_stds"]
state_times = data_ensemble["state_times"]
observation_means = data_ensemble["observation_means"]
observation_stds = data_ensemble["observation_stds"]
observation_clean_means = data_ensemble["observation_clean_means"]
observation_clean_stds = data_ensemble["observation_clean_stds"]
observation_times = data_ensemble["observation_times"]
observations_clean = data_ensemble["observations_clean"]
observations = data_ensemble["observations"]
logs = data_ensemble["logs"]

save_dir_root = plotsdir("estimator_ensemble", "states", filestem_ensemble)
with_theme(theme_latexfonts()) do
    update_theme!(; fontsize=30)

    state_keys = collect(keys(ensembles[1].ensemble.members[1]))

    state_times = [e.t for e in ensembles]
    states = [mean(e.ensemble; state_keys=state_keys) for e in ensembles]
    plot_states(
        state_times,
        states,
        params.estimator;
        save_dir_root=joinpath(save_dir_root, "mean"),
    )

    states = [std(e.ensemble; state_keys=state_keys) for e in ensembles]
    plot_states(
        state_times,
        states,
        params.estimator;
        save_dir_root=joinpath(save_dir_root, "var"),
    )

    state_times = [e.t for e in ensembles]
    for i in 1:min(length(ensembles[1].ensemble.members), 2)
        states = [e.ensemble.members[i] for e in ensembles]
        plot_states(
            state_times,
            states,
            params.estimator;
            save_dir_root=joinpath(save_dir_root, "e$i"),
            try_interactive=false,
        )
    end

    states = data_ensemble["states"]
    for (i, ensemble) in enumerate(states)
        ensemble = ensemble_info.ensemble
        plot_states(1:length(ensemble.members), ensemble.members, params.estimator; save_dir_root=joinpath(save_dir_root, string(i)))
        if i > 1
            break
        end
    end
end

nothing
