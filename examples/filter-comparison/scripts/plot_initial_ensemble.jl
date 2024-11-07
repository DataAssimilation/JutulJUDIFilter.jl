
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

include(srcdir("generate_initial_ensemble.jl"))
include(srcdir("plotting_plumes.jl"))

# Read data.
params = include(params_file)
data_ensemble, _, filestem_ensemble = produce_or_load_initial_ensemble(
    params; loadfile=true, force=false
)

ensemble = data_ensemble["ensemble"]
save_dir_root = plotsdir("initial_ensemble", "states", filestem_ensemble)

with_theme(theme_latexfonts()) do
    update_theme!(; fontsize=30)
    plot_states(
        1:length(ensemble.members), ensemble.members, params.ground_truth; save_dir_root
    )
end

nothing