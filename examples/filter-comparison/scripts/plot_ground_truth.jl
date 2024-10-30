
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

include(srcdir("generate_ground_truth.jl"))
include(srcdir("plotting_plumes.jl"))

# Read data.
params = include(params_file)
data_gt, _, filestem_gt = produce_or_load_ground_truth(params; loadfile=true)

states = data_gt["states"]
observations = data_gt["observations"]
observation_times = data_gt["observation_times"]
save_dir = plotsdir("ground_truth", "states", filestem_gt)

params_gt = params.ground_truth
with_theme(theme_latexfonts()) do
    update_theme!(fontsize=30)
    plot_plume_data(observation_times, states, save_dir, params_gt)
end
