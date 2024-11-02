
using DrWatson: srcdir, datadir, plotsdir, produce_or_load, wsave
# using CairoMakie: Label, @L_str, Axis, scatterlines!, ylims!, Legend
using Format: cfmt
# using Ensembles
# using Lorenz63Filter
# using ImageFiltering: ImageFiltering, imfilter
using ProgressLogging: @withprogress, @logprogress

using GLMakie
# using CairoMakie
using .Makie: latexstring

include(srcdir("plotting_utils.jl"))
include(srcdir("parula.jl"))

my_year = 3600 * 24 * 365.2425

function plot_saturation(content_layout, observation_times, states, params; p, grid_2d, heatmap_kwargs=(;))
    t_idx = p.t_idx

    heatmap_aspect = get_grid_col_aspect(grid_2d)

    # Plot first saturation.
    ax = Axis(content_layout[1, 1])

    state = @lift(states[$t_idx])
    t = @lift(observation_times[$t_idx])

    # data = @lift($state[:OverallMoleFraction])
    data = @lift($state[:Saturation])
    data_thresholded = @lift(ifelse.(abs.($data) .< 0, 0, $data))
    data_zeros = @lift(ifelse.($data_thresholded .<= 0, NaN, $data_thresholded))
    shaped_data = @lift(reshape($data_zeros, grid_2d.n))
    hm = plot_heatmap_from_grid!(
        ax,
        shaped_data,
        grid_2d;
        make_heatmap=true,
        heatmap_kwargs...
    )

    time_str = @lift(latexstring("\$t\$ = ", cfmt("%.3g", $t / my_year), " years"))
    cb = Colorbar(content_layout[1, 2], hm)
    on(heatmap_kwargs.colorscale; priority=10) do scale
        # There's a bug in the propagation of the scale, so when switching from log scale to linear scale,
        # we need to set the axis scale to linear first, before it tries to compute tick values.
        if scale == log10
        else
            cb.scale.val = scale
            cb.axis.attributes.scale.val = scale
            cb.axis.attributes.scale[] = scale
            cb.scale[] = scale
        end
    end

    Label(content_layout[1, 1, Top()], time_str; halign=:center, valign=:bottom, font=:bold)
    ax.xlabel = "Horizontal (km)"
    ax.ylabel = "Depth (km)"

    colsize!(content_layout, 1, Aspect(1, heatmap_aspect))
    hidespines!(ax)

    on(p.axis_reset.clicks) do n
        reset_limits!(ax)
    end
end

function plot_saturations(observation_times, states, save_dir_root, params)
    # Get mesh parameters in kilometers.
    grid = params.transition.mesh
    grid = MeshOptions(grid; d=grid.d ./ 1e3, origin=grid.origin ./ 1e3)
    grid_2d = MeshOptions(
        grid; d=grid.d[[1, end]], origin=grid.origin[[1, end]], n=grid.n[[1, end]]
    )

    # Set up the figure with controls.
    fig_scale = 96
    heatmap_aspect = get_grid_col_aspect(grid_2d)
    content_height = round(Int, 6 * fig_scale)
    content_size = (round(Int, content_height * heatmap_aspect), content_height)
    fig = Figure(; size=content_size)
    content_grid_position = fig[1, 1]
    content_layout = GridLayout(content_grid_position)

    p, heatmap_kwargs = set_up_time_heatmap_controls(fig, content_size, observation_times, params; fig_scale)

    onany(fig.scene.viewport, p.hide_controls.active) do v, hide_controls_active
        # Compute content width based on height of figure, controls, and content aspect.
        if hide_controls_active
            content_width = heatmap_aspect * v.widths[2]
        else
            content_width = heatmap_aspect * (v.widths[2] - p.controls_height)
        end
        if v.widths[1] < content_width
            colsize!(content_layout, 1, Auto())
            rowsize!(content_layout, 1, Aspect(1, 1 / heatmap_aspect))
        else
            rowsize!(content_layout, 1, Auto())
            colsize!(content_layout, 1, Aspect(1, heatmap_aspect))
        end
    end

    # Plot the data.
    plot_saturation(content_layout, observation_times, states, params; p, grid_2d, heatmap_kwargs)

    # Show interactively.
    if isinteractive()
        screen = display(fig)
        if hasmethod(wait, Tuple{typeof(screen)})
            wait(screen)
            if !p.interactive_savor.active.val
                return fig
            end
        end
        println("Press enter to continue. Type c to skip saving plots.")
        r = readline(stdin)
        if strip(r) == "c"
            return fig
        end
    end

    # Hide controls.
    p.hide_controls.active[] = true

    # Save all the saturation figures.
    @info "Plotting saturation data to $save_dir_root"

    @withprogress name = "state vs t" begin
        save_dir = joinpath(save_dir_root, "saturation")
        mkpath(save_dir)
        for i in 1:length(states)
            p.t_idx[] = i
            file_path = joinpath(save_dir, "$(cfmt("%02d", i)).png")
            wsave(file_path, fig)
            @logprogress i / length(states)
        end
    end

    @withprogress name = "log state vs t" begin
        save_dir = joinpath(save_dir_root, "saturation_log")
        mkpath(save_dir)
        p.colorscale[] = log10
        for i in 1:length(states)
            p.t_idx[] = i
            file_path = joinpath(save_dir, "$(cfmt("%02d", i)).png")
            wsave(file_path, fig)
            @logprogress i / length(states)
        end
    end

    return fig
end