
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

plot_data(content_layout, state, params, key::Symbol; kwargs...) = plot_data(content_layout, state, params, Val(key); kwargs...)

function plot_data(content_layout, state, params, key_func; kwargs...)
    data = @lift(key_func($state))
    plot_scalar_field(content_layout, data, params; kwargs...)
end

function plot_data(content_layout, state, params, ::Val{:Saturation}; threshold=0.0, kwargs...)
    data = @lift let
        # data = $state[:OverallMoleFraction]
        data = $state[:Saturation]
        data_thresholded = ifelse.(abs.(data) .< 0, $threshold, data)
        data_zeros = ifelse.(data_thresholded .<= 0, NaN, data_thresholded)
    end
    plot_scalar_field(content_layout, data, params; kwargs...)
end

function plot_data(content_layout, state, params, ::Val{:Pressure}; kwargs...)
    # Convert data to MPa.
    data = @lift($state[:Pressure])
    plot_scalar_field(content_layout, data, params; kwargs...)
end

function plot_data(content_layout, state, params, ::Val{:Permeability}; kwargs...)
    data = @lift begin
        s = size($state[:Permeability])
        if s[1] == 3 && length(s) > 1
            $state[:Permeability][1, :]
        else
            $state[:Permeability]
        end
    end
    plot_scalar_field(content_layout, data, params; kwargs...)
end

function plot_scalar_field(content_layout, data, params; grid_2d, heatmap_kwargs=(;))
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

    ax.xlabel = "Horizontal (km)"
    ax.ylabel = "Depth (km)"

    colsize!(content_layout, 1, Aspect(1, heatmap_aspect))
    hidespines!(ax)
    return ax
end

function make_time_domain_figure_with_controls(observation_times, states, params; default_data_range=(0,1), default_colormap=parula, divergent=false)
    # Set up the figure with controls.
    fig_scale = 96
    heatmap_aspect = get_grid_col_aspect(params.transition.mesh)
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

    return fig, content_layout, ctrls, heatmap_kwargs
end

function plot_states(observation_times, states, params; save_dir_root, try_interactive=true)
    # Get mesh parameters in kilometers.
    grid = params.transition.mesh
    grid = MeshOptions(grid; d=grid.d ./ 1e3, origin=grid.origin ./ 1e3)
    grid_2d = MeshOptions(
        grid; d=grid.d[[1, end]], origin=grid.origin[[1, end]], n=grid.n[[1, end]]
    )

    function add_top_label(content_layout, t_idx)
        if eltype(observation_times) == Int
            top_label = @lift(string($t_idx))
            Label(content_layout[1, 1, Top()], top_label; halign=:center, valign=:bottom, font=:bold)
        else
            t = @lift(observation_times[$t_idx])
            top_label = @lift(latexstring("\$t\$ = ", cfmt("%.3g", $t / my_year), " years"))
            Label(content_layout[1, 1, Top()], top_label; halign=:center, valign=:bottom, font=:bold)
        end
    end

    # Do all the saturation figures.
    if haskey(states[1], :Saturation)
        fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(observation_times, states, params)

        add_top_label(content_layout, controls.t_idx)
        state = @lift(states[$(controls.t_idx)])
        ax = plot_data(content_layout, state, params, :Saturation; grid_2d, heatmap_kwargs)

        controls.interactive_savor.active[] = true
        try_interactive && show_interactive_preview(fig, controls)
        controls.hide_controls.active[] = true

        if controls.interactive_savor.active[]
            @info "Plotting saturation data to $save_dir_root"
            @withprogress name = "saturation" begin
                save_dir = joinpath(save_dir_root, "saturation")
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

    # Do all the pressure figures.
    if haskey(states[1], :Pressure)
        # default_data_range = (0e0, 5e7)
        default_data_range = extrema(Iterators.flatten(extrema.(s[:Pressure] for s in states)))
        fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(observation_times, states, params; default_data_range)

        add_top_label(content_layout, controls.t_idx)
        state = @lift(states[$(controls.t_idx)])
        ax = plot_data(content_layout, state, params, :Pressure; grid_2d, heatmap_kwargs)

        cb = content(fig[1,1][1,2])
        cb.label = "Pa"

        controls.interactive_savor.active[] = true
        try_interactive && show_interactive_preview(fig, controls)
        controls.hide_controls.active[] = true

        if controls.interactive_savor.active[]
            @info "Plotting pressure data to $save_dir_root"
            @withprogress name = "pressure" begin
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
        if max_diff == 0
            println("pressure is constant at $(states[1][:Pressure][1])")
        else
            default_data_range = (-max_diff, max_diff)
            fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(observation_times, states, params; 
                default_data_range,
                default_colormap=Reverse(:RdBu),
                divergent=true,
            )

            add_top_label(content_layout, controls.t_idx)
            state = @lift(states[$(controls.t_idx)])
            ax = plot_data(content_layout, state, params, pressure_diff; grid_2d, heatmap_kwargs)

            cb = content(fig[1,1][1,2])
            cb.label = "Pa"

            controls.interactive_savor.active[] = true
            try_interactive && show_interactive_preview(fig, controls)
            controls.hide_controls.active[] = true

            if controls.interactive_savor.active[]
                @info "Plotting pressure diff to $save_dir_root"
                @withprogress name = "pressure diff" begin
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
    end

    if haskey(states[1], :Permeability)
        default_data_range = extrema(Iterators.flatten(extrema.(s[:Permeability] for s in states)))
        if default_data_range[1] == default_data_range[2]
            println("permeability is constant at ", states[1][:Permeability][1])
        else
            fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(observation_times, states, params; default_data_range)

            add_top_label(content_layout, controls.t_idx)
            state = @lift(states[$(controls.t_idx)])
            ax = plot_data(content_layout, state, params, :Permeability; grid_2d, heatmap_kwargs)

            cb = content(fig[1,1][1,2])
            cb.label = "SI permeability"

            controls.interactive_savor.active[] = true
            try_interactive && show_interactive_preview(fig, controls)
            controls.hide_controls.active[] = true

            if controls.interactive_savor.active[]
                @info "Plotting permeability data to $save_dir_root"
                @withprogress name = "permeability" begin
                    save_dir = joinpath(save_dir_root, "permeability")
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
    end
end