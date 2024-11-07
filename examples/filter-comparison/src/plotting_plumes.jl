
using DrWatson: srcdir, datadir, plotsdir, produce_or_load, wsave
# using CairoMakie: Label, @L_str, Axis, scatterlines!, ylims!, Legend
using Format: cfmt
# using Ensembles
# using Lorenz63Filter
# using ImageFiltering: ImageFiltering, imfilter
using ProgressLogging: @withprogress, @logprogress

using GLMakie
using CairoMakie
using .Makie: latexstring

include(srcdir("plotting_utils.jl"))
include(srcdir("parula.jl"))

my_year = 3600 * 24 * 365.2425
mD_to_m2 = 9.869233e-16

function plot_data(content_layout, state, params, key::Symbol; kwargs...)
    return plot_data(content_layout, state, params, Val(key); kwargs...)
end

function plot_data(content_layout, state, params, key_func; kwargs...)
    data = @lift(key_func($state))
    return plot_scalar_field(content_layout, data, params; kwargs...)
end

function plot_data(
    content_layout, state, params, ::Val{:Saturation}; threshold=0.0, kwargs...
)
    data = @lift let
        data = $state[:Saturation]
        data_thresholded = ifelse.(abs.(data) .< 0, $threshold, data)
        data_zeros = ifelse.(data_thresholded .<= 0, NaN, data_thresholded)
    end
    return plot_scalar_field(content_layout, data, params; kwargs...)
end

function plot_data(
    content_layout, state, params, ::Val{:Pressure}; heatmap_kwargs, kwargs...
)
    # Convert data to MPa.
    data = @lift($state[:Pressure] ./ 1e6)
    if haskey(heatmap_kwargs, :colorrange)
        colorrange = @lift($(heatmap_kwargs[:colorrange]) ./ 1e6)
        heatmap_kwargs = (; heatmap_kwargs..., colorrange)
    end
    return plot_scalar_field(content_layout, data, params; heatmap_kwargs, kwargs...)
end

function plot_data(
    content_layout, state, params, ::Val{:Permeability}; heatmap_kwargs, kwargs...
)
    data = @lift begin
        s = size($state[:Permeability])
        if s[1] == 3 && length(s) > 1
            $state[:Permeability][1, :] ./ mD_to_m2
        else
            $state[:Permeability] ./ mD_to_m2
        end
    end
    if haskey(heatmap_kwargs, :colorrange)
        colorrange = @lift($(heatmap_kwargs[:colorrange]) ./ mD_to_m2)
        heatmap_kwargs = (; heatmap_kwargs..., colorrange)
    end
    return plot_scalar_field(content_layout, data, params; heatmap_kwargs, kwargs...)
end

function plot_data(
    content_layout, state, params, ::Val{:dshot}; timeR, dtR, nsrc, heatmap_kwargs
)
    data = @lift begin
        if isa($state, Dict)
            $state[:dshot] ./ 1e6
        else
            $state ./ 1e6
        end
    end

    if haskey(heatmap_kwargs, :colorrange)
        colorrange = @lift($(heatmap_kwargs[:colorrange]) ./ 1e6)
        heatmap_kwargs = (; heatmap_kwargs..., colorrange)
    end

    grid = if nsrc <= 4
        (nsrc, 1)
    else
        (4, 2)
    end
    CI = CartesianIndices(grid)
    layer1 = GridLayout(content_layout[1, 1])
    layout = GridLayout(layer1[2, 1])
    rowsize!(layer1, 1, Fixed(0))

    local hm
    times = @lift(range(start=0, stop=$timeR / 1e3, step=$dtR / 1e3))
    src_range = StepRange(1, max(1, nsrc ÷ prod(grid)), nsrc)
    @show src_range
    for (i, ci) in zip(src_range, CI)
        println("Plotting source $i at $ci")
        grid_ci = (ci.I[2], ci.I[1])

        layout_ci = layout[grid_ci...]
        ax = Axis(layout_ci[1, 1]; yreversed=true)
        colsize!(layout, grid_ci[2], Aspect(1, 0.75))

        # layout_ci = GridLayout(layout[grid_ci...])
        # ax = Axis(layout_ci, yreversed=true)
        # colsize!(layout_ci, 1, Aspect(1, 1))

        Label(layout_ci[1, 1, Top()], "Source $i"; halign=:center, valign=:bottom)

        xs = @lift(1:size($data[i], 2))
        ys = times
        a = @lift($data[i]')
        hm = heatmap!(ax, xs, ys, a; rasterize=true, heatmap_kwargs...)
        if grid_ci[1] == grid[2]
            # Show x label on bottom row.
            ax.xlabel = "receiver index"
        else
            # Hide x ticks everywhere else.
            ax.xticklabelsvisible = false
        end
        if grid_ci[2] == 1
            # Show y label on left column.
            ax.ylabel = "time (seconds)"
        else
            # Hide y ticks everywhere else.
            ax.yticklabelsvisible = false
        end
        hidespines!(ax)
    end
    rowgap!(layout, 35)
    rowgap!(layer1, 0)
    colgap!(layout, 0)
    return Colorbar(layout[:, end + 1], hm; label="amplitude (Pa)")
end

function plot_data(content_layout, state, params, ::Val{:rtm}; heatmap_kwargs, kwargs...)
    data = @lift begin
        if isa($state, Dict)
            $state[:rtm] ./ 1e6
        else
            $state ./ 1e6
        end
    end
    if haskey(heatmap_kwargs, :colorrange)
        colorrange = @lift($(heatmap_kwargs[:colorrange]) ./ 1e6)
        heatmap_kwargs = (; heatmap_kwargs..., colorrange)
    end
    return plot_scalar_field(content_layout, data, params; heatmap_kwargs, kwargs...)
end

function plot_scalar_field(content_layout, data, params; grid_2d, heatmap_kwargs=(;), colorbar_kwargs=(;))
    heatmap_aspect = get_grid_col_aspect(grid_2d)

    # Plot first saturation.
    ax = Axis(content_layout[1, 1])

    shaped_data = @lift(reshape($data, grid_2d.n))
    hm = plot_heatmap_from_grid!(
        ax, shaped_data, grid_2d; make_heatmap=true, heatmap_kwargs...
    )

    if !isnothing(colorbar_kwargs)
        cb = Colorbar(content_layout[1, 2], hm)
        if haskey(heatmap_kwargs, :colorscale)
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
        end
    end

    ax.xlabel = "Horizontal (km)"
    ax.ylabel = "Depth (km)"

    colsize!(content_layout, 1, Aspect(1, heatmap_aspect))
    hidespines!(ax)
    return ax
end

function make_time_domain_figure_with_controls(state_times, states, params; kwargs...)
    content_aspect = get_grid_col_aspect(params.transition.mesh)
    return make_time_figure_with_controls(state_times, states; content_aspect, kwargs...)
end

function make_time_figure_with_controls(
    state_times,
    states;
    default_data_range=(0, 1),
    default_colormap=parula,
    divergent=false,
    fig_scale=96,
    content_aspect=1.0,
    content_height=round(Int, 6 * fig_scale),
)
    # Set up the figure with controls.
    content_size = (round(Int, content_height * content_aspect), content_height)
    fig = Figure(; size=content_size)
    content_grid_position = fig[1, 1]
    content_layout = GridLayout(content_grid_position)
    if divergent
        s = maximum(abs.(default_data_range))
        default_data_range = (-s, s)
    end

    ctrls, heatmap_kwargs = set_up_time_heatmap_controls(
        fig,
        content_size,
        state_times;
        fig_scale,
        default_data_range,
        default_colormap,
        divergent,
    )

    onany(fig.scene.viewport, ctrls.hide_controls.active) do v, hide_controls_active
        # Compute content width based on height of figure, controls, and content aspect.
        if hide_controls_active
            content_width = content_aspect * v.widths[2]
        else
            content_width = content_aspect * (v.widths[2] - ctrls.controls_height)
        end
        if v.widths[1] < content_width
            colsize!(content_layout, 1, Auto())
            rowsize!(content_layout, 1, Aspect(1, 1 / content_aspect))
        else
            rowsize!(content_layout, 1, Auto())
            colsize!(content_layout, 1, Aspect(1, content_aspect))
        end
    end

    return fig, content_layout, ctrls, heatmap_kwargs
end

function add_top_label(state_times, content_layout, t_idx)
    if eltype(state_times) == Int
        top_label = @lift(string($t_idx))
        Label(
            content_layout[1, 1, Top()],
            top_label;
            halign=:center,
            valign=:bottom,
            font=:bold,
        )
    else
        t = @lift(state_times[$t_idx])
        top_label = @lift(latexstring("\$t\$ = ", cfmt("%.3g", $t / my_year), " years"))
        Label(
            content_layout[1, 1, Top()],
            top_label;
            halign=:center,
            valign=:bottom,
            font=:bold,
        )
    end
end

function get_2d_plotting_mesh(grid)
    # Get mesh parameters in kilometers.
    grid = MeshOptions(grid; d=grid.d ./ 1e3, origin=grid.origin ./ 1e3)
    return grid_2d = MeshOptions(
        grid; d=grid.d[[1, end]], origin=grid.origin[[1, end]], n=grid.n[[1, end]]
    )
end

function plot_states(state_times, states, params; save_dir_root, try_interactive=false)
    @show length(states) state_times
    @assert length(states) == length(state_times)

    if haskey(states[1], :Saturation)
        plot_states(
            state_times, states, params, Val(:Saturation); save_dir_root, try_interactive
        )
    end

    if haskey(states[1], :Pressure)
        plot_states(
            state_times, states, params, Val(:Pressure); save_dir_root, try_interactive
        )
        plot_states(
            state_times, states, params, Val(:Pressure_diff); save_dir_root, try_interactive
        )
    end

    if haskey(states[1], :Permeability)
        plot_states(
            state_times, states, params, Val(:Permeability); save_dir_root, try_interactive
        )
    end
end

function plot_states(
    state_times, states, params, ::Val{:Saturation}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(
        state_times, states, params
    )

    add_top_label(state_times, content_layout, controls.t_idx)
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

function plot_states(
    state_times, states, params, ::Val{:Saturation_Permeability}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(
        state_times, states, params
    )

    default_data_range = extrema(
        Iterators.flatten(extrema.(s[:Permeability] for s in states))
    )

    add_top_label(state_times, content_layout, controls.t_idx)
    state = @lift(states[$(controls.t_idx)])

    ax = plot_data(content_layout, state, params, :Permeability;
        grid_2d,
        heatmap_kwargs=(;colorrange = default_data_range, colormap=Reverse(:Purples)),
        colorbar_kwargs=nothing,
    )

    data = @lift let
        data = $state[:Saturation]
        data_thresholded = ifelse.(abs.(data) .< 0, 0.0, data)
        data_zeros = ifelse.(data_thresholded .<= 0, NaN, data_thresholded)
    end
    shaped_data = @lift(reshape($data, grid_2d.n))
    hm = plot_heatmap_from_grid!(
        ax, shaped_data, grid_2d; make_heatmap=true, heatmap_kwargs...
    )

    controls.interactive_savor.active[] = true
    try_interactive && show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting saturation_permeability data to $save_dir_root"
        @withprogress name = "saturation_permeability" begin
            save_dir = joinpath(save_dir_root, "saturation_permeability")
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

function plot_states(
    state_times, states, params, ::Val{:Pressure}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    # default_data_range = (0e0, 5e7)
    default_data_range = extrema(Iterators.flatten(extrema.(s[:Pressure] for s in states)))
    fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(
        state_times, states, params; default_data_range
    )

    add_top_label(state_times, content_layout, controls.t_idx)
    state = @lift(states[$(controls.t_idx)])
    ax = plot_data(content_layout, state, params, :Pressure; grid_2d, heatmap_kwargs)

    cb = content(fig[1, 1][1, 2])
    cb.label = "MPa"

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
end

function plot_states(
    state_times, states, params, ::Val{:Pressure_diff}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    function pressure_diff(state)
        return state[:Pressure] .- states[1][:Pressure]
    end
    # default_data_range = (-2e6, 2e6)
    max_diff = maximum(
        maximum.(maximum.(abs.(s[:Pressure] .- states[1][:Pressure]) for s in states))
    )
    if max_diff == 0
        println("pressure is constant at $(states[1][:Pressure][1])")
        return nothing
    end
    default_data_range = (-max_diff, max_diff)
    fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(
        state_times,
        states,
        params;
        default_data_range,
        default_colormap=Reverse(:RdBu),
        divergent=true,
    )

    add_top_label(state_times, content_layout, controls.t_idx)
    state = @lift(states[$(controls.t_idx)])
    ax = plot_data(content_layout, state, params, pressure_diff; grid_2d, heatmap_kwargs)

    cb = content(fig[1, 1][1, 2])
    cb.label = "MPa"

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

function plot_states(
    state_times, states, params, ::Val{:Permeability}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    default_data_range = extrema(
        Iterators.flatten(extrema.(s[:Permeability] for s in states))
    )
    if default_data_range[1] == default_data_range[2]
        println("permeability is constant at ", states[1][:Permeability][1])
        return nothing
    end
    fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(
        state_times, states, params; default_data_range, default_colormap=Reverse(:Purples)
    )

    add_top_label(state_times, content_layout, controls.t_idx)
    state = @lift(states[$(controls.t_idx)])
    ax = plot_data(content_layout, state, params, :Permeability; grid_2d, heatmap_kwargs)

    cb = content(fig[1, 1][1, 2])
    cb.label = "millidarcy"

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

function plot_states(
    state_times, states, params, ::Val{:rtm}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    default_data_range = extrema(Iterators.flatten(extrema.(s[:rtm] for s in states)))
    if default_data_range[1] == default_data_range[2]
        println("rtm is constant at ", states[1][:rtm][1])
        return nothing
    end
    fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(
        state_times,
        states,
        params;
        default_data_range,
        default_colormap=Reverse(:RdBu),
        divergent=true,
    )

    add_top_label(state_times, content_layout, controls.t_idx)
    state = @lift(states[$(controls.t_idx)])

    ax = plot_data(content_layout, state, params, :rtm; grid_2d, heatmap_kwargs)

    cb = content(fig[1, 1][1, 2])
    cb.label = L"SI RTM / $10^6$"

    controls.interactive_savor.active[] = true
    try_interactive && show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting rtm data to $save_dir_root"
        @withprogress name = "rtm" begin
            save_dir = joinpath(save_dir_root, "rtm")
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

function plot_states(
    state_times, states, params, ::Val{:rtm_diff}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    function rtm_diff(state)
        return state[:rtm] .- states[1][:rtm]
    end
    # default_data_range = (-2e6, 2e6)
    max_diff = maximum(maximum.(maximum.(abs.(s) for s in rtm_diff.(states))))
    if max_diff == 0
        println("rtm is constant at $(states[1][:rtm][1])")
        return nothing
    end
    default_data_range = (-max_diff, max_diff)
    fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(
        state_times,
        states,
        params;
        default_data_range,
        default_colormap=Reverse(:RdBu),
        divergent=true,
    )

    add_top_label(state_times, content_layout, controls.t_idx)
    state = @lift(rtm_diff(states[$(controls.t_idx)]))

    ax = plot_data(content_layout, state, params, :rtm; grid_2d, heatmap_kwargs)

    cb = content(fig[1, 1][1, 2])
    cb.label = L"SI RTM / $10^6$"

    controls.interactive_savor.active[] = true
    try_interactive && show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting rtm_diff data to $save_dir_root"
        @withprogress name = "rtm_diff" begin
            save_dir = joinpath(save_dir_root, "rtm_diff")
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

function get_shot_extrema(data)
    # Combine extrema from all shots.
    es = extrema.(data)
    cr = collect(es[1])
    for e in es
        cr[1] = min(cr[1], e[1])
        cr[2] = max(cr[2], e[2])
    end
    return cr
end

function plot_states(
    state_times, states, params, ::Val{:dshot}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    max_diff = maximum(
        abs.(extrema(Iterators.flatten(get_shot_extrema.(s[:dshot] for s in states))))
    )
    if max_diff == 0
        println("dshot is constant at ", states[1][:dshot][1][1])
        return nothing
    end
    default_data_range = (-max_diff, max_diff)

    content_aspect = 16 / 9
    global fig, content_layout, controls, heatmap_kwargs = make_time_figure_with_controls(
        state_times,
        states;
        default_data_range,
        content_aspect,
        default_colormap=Reverse(:balance),
        divergent=true,
        content_height=900,
    )

    add_top_label(state_times, content_layout, controls.t_idx)
    state = @lift(states[$(controls.t_idx)])

    timeR = @lift(params.observation.observers[$(controls.t_idx)].second.seismic.timeR)
    dtR = @lift(params.observation.observers[$(controls.t_idx)].second.seismic.dtR)
    nsrc = params.observation.observers[1].second.seismic.source_receiver_geometry.nsrc

    ax = plot_data(content_layout, state, params, :dshot; heatmap_kwargs, nsrc, timeR, dtR)

    cb = fig.content[end]
    cb.label = "MPa"

    controls.interactive_savor.active[] = true
    try_interactive && show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting dshot data to $save_dir_root"
        @withprogress name = "dshot" begin
            save_dir = joinpath(save_dir_root, "dshot")
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

function plot_states(
    state_times, states, params, ::Val{:dshot_diff}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    function dshot_diff(state)
        return [d .- d0 for (d0, d) in zip(states[1][:dshot], state[:dshot])]
    end
    max_diff = maximum(
        abs.(extrema(Iterators.flatten(get_shot_extrema.(dshot_diff.(states)))))
    )
    if max_diff == 0
        println("dshot is constant at ", states[1][:dshot][1])
        return nothing
    end
    default_data_range = (-max_diff, max_diff)

    content_aspect = 16 / 9
    fig, content_layout, controls, heatmap_kwargs = make_time_figure_with_controls(
        state_times,
        states;
        default_data_range,
        content_aspect,
        default_colormap=Reverse(:balance),
        divergent=true,
        content_height=900,
    )

    add_top_label(state_times, content_layout, controls.t_idx)
    state = @lift(dshot_diff(states[$(controls.t_idx)]))

    timeR = @lift(params.observation.observers[$(controls.t_idx)].second.seismic.timeR)
    dtR = @lift(params.observation.observers[$(controls.t_idx)].second.seismic.dtR)
    nsrc = params.observation.observers[1].second.seismic.source_receiver_geometry.nsrc

    ax = plot_data(content_layout, state, params, :dshot; heatmap_kwargs, nsrc, timeR, dtR)

    cb = fig.content[end]
    cb.label = "MPa"

    controls.interactive_savor.active[] = true
    try_interactive && show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting dshot_diff data to $save_dir_root"
        @withprogress name = "dshot_diff" begin
            save_dir = joinpath(save_dir_root, "dshot_diff")
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

function plot_states(
    state_times, states, params, ::Val{:velocity}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    default_data_range = extrema(Iterators.flatten(extrema.(s for s in states))) ./ 1e3
    if default_data_range[1] == default_data_range[2]
        println("velocity is constant at ", states[1][1])
        return nothing
    end
    fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(
        state_times, states, params; default_data_range, default_colormap=:YlOrRd
    )

    state = @lift(states[$(controls.t_idx)] ./ 1e3)
    ax = plot_scalar_field(content_layout, state, params; grid_2d, heatmap_kwargs)

    cb = content(fig[1, 1][1, 2])
    cb.label = "km/s"

    controls.interactive_savor.active[] = true
    try_interactive && show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting velocity data to $save_dir_root"
        @withprogress name = "velocity" begin
            save_dir = joinpath(save_dir_root, "velocity")
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

function plot_states(
    state_times, states, params, ::Val{:velocity0}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    default_data_range = extrema(Iterators.flatten(extrema.(s for s in states))) ./ 1e3
    if default_data_range[1] == default_data_range[2]
        println("velocity0 is constant at ", states[1][1])
        return nothing
    end
    fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(
        state_times, states, params; default_data_range, default_colormap=:YlOrRd
    )

    state = @lift(states[$(controls.t_idx)] ./ 1e3)
    ax = plot_scalar_field(content_layout, state, params; grid_2d, heatmap_kwargs)

    cb = content(fig[1, 1][1, 2])
    cb.label = "km/s"

    controls.interactive_savor.active[] = true
    try_interactive && show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting velocity0 data to $save_dir_root"
        @withprogress name = "velocity0" begin
            save_dir = joinpath(save_dir_root, "velocity0")
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

function plot_states(
    state_times, states, params, ::Val{:density}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    default_data_range = extrema(Iterators.flatten(extrema.(s for s in states))) ./ 1e3
    if default_data_range[1] == default_data_range[2]
        println("density is constant at ", states[1][1])
        return nothing
    end
    fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(
        state_times, states, params; default_data_range, default_colormap=:YlOrBr
    )

    state = @lift(states[$(controls.t_idx)] ./ 1e3)
    ax = plot_scalar_field(content_layout, state, params; grid_2d, heatmap_kwargs)

    cb = content(fig[1, 1][1, 2])
    cb.label = "g/mL"

    controls.interactive_savor.active[] = true
    try_interactive && show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting density data to $save_dir_root"
        @withprogress name = "density" begin
            save_dir = joinpath(save_dir_root, "density")
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

function plot_states(
    state_times, states, params, ::Val{:density0}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    default_data_range = extrema(Iterators.flatten(extrema.(s for s in states))) ./ 1e3
    if default_data_range[1] == default_data_range[2]
        println("density0 is constant at ", states[1][1])
        return nothing
    end
    fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(
        state_times, states, params; default_data_range, default_colormap=:YlOrBr
    )

    state = @lift(states[$(controls.t_idx)] ./ 1e3)
    ax = plot_scalar_field(content_layout, state, params; grid_2d, heatmap_kwargs)

    cb = content(fig[1, 1][1, 2])
    cb.label = "g/mL"

    controls.interactive_savor.active[] = true
    try_interactive && show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting density0 data to $save_dir_root"
        @withprogress name = "density0" begin
            save_dir = joinpath(save_dir_root, "density0")
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
