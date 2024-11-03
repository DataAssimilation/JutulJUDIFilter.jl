
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

plot_data(content_layout, state, t, params, key::Symbol; kwargs...) = plot_data(content_layout, state, t, params, Val(key); kwargs...)

function plot_data(content_layout, state, t, params, key_func; kwargs...)
    data = @lift(key_func($state))
    plot_scalar_field(content_layout, data, t, params; kwargs...)
end

function plot_data(content_layout, state, t, params, ::Val{:Saturation}; threshold=0.0, kwargs...)
    data = @lift let
        # data = $state[:OverallMoleFraction]
        data = $state[:Saturation]
        data_thresholded = ifelse.(abs.(data) .< 0, $threshold, data)
        data_zeros = ifelse.(data_thresholded .<= 0, NaN, data_thresholded)
    end
    plot_scalar_field(content_layout, data, t, params; kwargs...)
end

function plot_data(content_layout, state, t, params, ::Val{:Pressure}; kwargs...)
    data = @lift($state[:Pressure])
    plot_scalar_field(content_layout, data, t, params; kwargs...)
end

function plot_scalar_field(content_layout, data, t, params; grid_2d, heatmap_kwargs=(;))
    heatmap_aspect = get_grid_col_aspect(grid_2d)

    # Plot first saturation.
    ax = Axis(content_layout[1, 1])

    shaped_data = @lift(reshape($data, grid_2d.n))
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
    return ax
end

function plot_time_fields(observation_times, states, params; key=only(keys(states[1])), default_data_range=(0,1), default_colormap=parula, divergent=false)
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

    ctrls, heatmap_kwargs = set_up_time_heatmap_controls(fig, content_size, observation_times, params; fig_scale, default_data_range, default_colormap, divergent)

    onany(fig.scene.viewport, ctrls.hide_controls.active) do v, hide_controls_active
        # Compute content width based on height of figure, controls, and content aspect.
        if hide_controls_active
            content_width = heatmap_aspect * v.widths[2]
        else
            content_width = heatmap_aspect * (v.widths[2] - ctrls.controls_height)
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
    t_idx = ctrls.t_idx
    state = @lift(states[$t_idx])
    t = @lift(observation_times[$t_idx])
    ax = plot_data(content_layout, state, t, params, key; grid_2d, heatmap_kwargs)

    on(ctrls.axis_reset.clicks) do n
        reset_limits!(ax)
    end

    return fig, ctrls
end