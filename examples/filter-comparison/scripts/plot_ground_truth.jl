
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
data_gt, _, filestem_gt = produce_or_load_ground_truth(params; loadfile=true, force=false)

states = data_gt["states"]
observations = data_gt["observations"]
observation_times = data_gt["observation_times"]
save_dir_root = plotsdir("ground_truth", "states", filestem_gt)

params_gt = params.ground_truth
with_theme(theme_latexfonts()) do
    update_theme!(; fontsize=30)

    # Do all the saturation figures.
    global fig, controls = plot_time_fields(observation_times, states, params_gt; key=:Saturation)

    controls.interactive_savor.active[] = true
    show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting saturation data to $save_dir_root"

        @withprogress name = "saturation vs t" begin
            save_dir = joinpath(save_dir_root, "saturation")
            mkpath(save_dir)
            for i in 1:length(states)
                controls.t_idx[] = i
                file_path = joinpath(save_dir, "$(cfmt("%02d", i)).png")
                wsave(file_path, fig)
                @logprogress i / length(states)
            end
        end
        @withprogress name = "log saturation vs t" begin
            save_dir = joinpath(save_dir_root, "saturation_log")
            mkpath(save_dir)
            controls.colorscale[] = log10
            for i in 1:length(states)
                controls.t_idx[] = i
                file_path = joinpath(save_dir, "$(cfmt("%02d", i)).png")
                wsave(file_path, fig)
                @logprogress i / length(states)
            end
        end
    end

    # Do all the pressure figures.
    # default_data_range = (0e0, 5e7)
    default_data_range = extrema(Iterators.flatten(extrema.(s[:Pressure] for s in states)))
    @show default_data_range
    fig, controls = plot_time_fields(observation_times, states, params_gt; key=:Pressure, default_data_range)
    cb = content(fig[1,1][1,2])
    cb.label = "Pa"

    controls.interactive_savor.active[] = true
    show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting pressure data to $save_dir_root"
        @withprogress name = "pressure vs t" begin
            save_dir = joinpath(save_dir_root, "pressure")
            mkpath(save_dir)
            for i in 1:length(states)
                controls.t_idx[] = i
                file_path = joinpath(save_dir, "$(cfmt("%02d", i)).png")
                wsave(file_path, fig)
                @logprogress i / length(states)
            end
        end
    end

    # Do all the pressure difference figures.
    function pressure_diff(state)
        state[:Pressure] .- states[1][:Pressure]
    end
    # default_data_range = (-2e6, 2e6)
    max_diff = maximum(maximum.(maximum.(abs.(s[:Pressure] .- states[1][:Pressure]) for s in states)))
    default_data_range = (-max_diff, max_diff)
    fig, controls = plot_time_fields(observation_times, states, params_gt;
        key=pressure_diff,
        default_data_range,
        default_colormap=Reverse(:RdBu),
        divergent=true,
    )
    cb = content(fig[1,1][1,2])
    cb.label = "Pa"

    controls.interactive_savor.active[] = true
    show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting pressure diff to $save_dir_root"
        @withprogress name = "pressure diff vs t" begin
            save_dir = joinpath(save_dir_root, "pressure_diff")
            mkpath(save_dir)
            for i in 1:length(states)
                controls.t_idx[] = i
                file_path = joinpath(save_dir, "$(cfmt("%02d", i)).png")
                wsave(file_path, fig)
                @logprogress i / length(states)
            end
        end
    end
end

nothing
