
using DrWatson: wsave

using Makie:
    Makie,
    SliderGrid,
    RGBf,
    Textbox,
    Button,
    Menu,
    IntervalSlider,
    Toggle,
    Observable,
    on,
    onany,
    Label,
    @L_str,
    Axis,
    scatterlines!,
    ylims!,
    Legend,
    latexstring,
    Auto,
    rowsize!,
    colsize!,
    Colorbar,
    rowgap!,
    colgap!,
    Relative,
    Box,
    heatmap!,
    hidespines!,
    content,
    Reverse,
    Top,
    GridLayout,
    Fixed,
    MarkerElement,
    lines!,
    scatter!,
    axislegend

using Format: cfmt
using ProgressLogging: @withprogress, @logprogress

my_year = 3600 * 24 * 365.2425
mD_to_m2 = 9.869233e-16

export plot_data
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

    heatmap_kwargs = Dict{Symbol,Any}(pairs(heatmap_kwargs))
    colorrange = pop!(heatmap_kwargs, :colorrange, nothing)
    if !isnothing(colorrange)
        colorrange = @lift($colorrange ./ 1e6)
    else
        # colorrange = @lift begin
        #     maximum(
        #         abs.(extrema(Iterators.flatten(get_shot_extrema.(dshot_diff.(states)))))
        #     )
        # end
        m1 = @lift(minimum(x -> isfinite(x) ? x : Inf, Iterators.flatten($data)))
        m2 = @lift(maximum(x -> isfinite(x) ? x : -Inf, Iterators.flatten($data)))
        colorrange = @lift(($m1, $m2))
    end

    fix_colorrange = pop!(heatmap_kwargs, :fix_colorrange, nothing)
    make_divergent = pop!(heatmap_kwargs, :make_divergent, false)
    if fix_colorrange == true || isnothing(fix_colorrange) && make_divergent
        colorrange = @lift(get_colorrange($colorrange; make_divergent))
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
    for (i, ci) in zip(src_range, CI)
        @info "Plotting source $i at $ci"
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
        hm = heatmap!(ax, xs, ys, a; rasterize=true, colorrange, heatmap_kwargs...)
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

function plot_data(
    content_layout, state, params, ::Val{:density}; heatmap_kwargs, kwargs...
)
    data = @lift begin
        if isa($state, Dict)
            $state[:density] ./ 1e3
        else
            $state ./ 1e3
        end
    end
    if haskey(heatmap_kwargs, :colorrange)
        colorrange = @lift($(heatmap_kwargs[:colorrange]) ./ 1e3)
        heatmap_kwargs = (; heatmap_kwargs..., colorrange)
    end
    return plot_scalar_field(content_layout, data, params; heatmap_kwargs, kwargs...)
end

function plot_data(
    content_layout, state, params, ::Val{:impedance}; heatmap_kwargs, kwargs...
)
    data = @lift begin
        if isa($state, Dict)
            $state[:velocity] .* $state[:density] ./ 1e6
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

function plot_data(
    content_layout, state, params, ::Val{:velocity}; heatmap_kwargs, kwargs...
)
    data = @lift begin
        if isa($state, Dict)
            $state[:velocity] ./ 1e3
        else
            $state ./ 1e3
        end
    end
    if haskey(heatmap_kwargs, :colorrange)
        colorrange = @lift($(heatmap_kwargs[:colorrange]) ./ 1e3)
        heatmap_kwargs = (; heatmap_kwargs..., colorrange)
    end
    return plot_scalar_field(content_layout, data, params; heatmap_kwargs, kwargs...)
end

export plot_scalar_field
function plot_scalar_field(
    content_layout,
    data,
    params=nothing;
    grid_2d,
    idx_cutoff=(:, :),
    grid_cutoff=grid_2d,
    heatmap_kwargs=(;),
    colorbar_kwargs=(;),
)
    heatmap_aspect = get_grid_col_aspect(grid_2d)

    # Plot first saturation.
    ax = Axis(content_layout[1, 1])

    shaped_data = @lift(reshape($data, grid_2d.n)[idx_cutoff...])
    hm = plot_heatmap_from_grid!(
        ax, shaped_data, grid_cutoff; make_heatmap=true, heatmap_kwargs...
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

export make_time_domain_figure_with_controls
function make_time_domain_figure_with_controls(state_times, states, params; kwargs...)
    content_aspect = get_grid_col_aspect(params.transition.mesh)
    return make_time_figure_with_controls(state_times, states; content_aspect, kwargs...)
end

export make_time_figure_with_controls
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

export add_top_label
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

export get_2d_plotting_mesh
function get_2d_plotting_mesh(grid)
    # Get mesh parameters in kilometers.
    return (;
        d=grid.d[[1, end]] ./ 1e3, origin=grid.origin[[1, end]] ./ 1e3, n=grid.n[[1, end]]
    )
end

export cutoff_mesh
function cutoff_mesh(grid; top)
    cutoff_idx = Int(max(top ÷ grid.d[end], 1))
    top = cutoff_idx * grid.d[end]
    n = grid.n .- (0, cutoff_idx - 1)
    origin = grid.origin .- (0, top)
    return (:, cutoff_idx:grid.n[1]), (; d=grid.d, origin, n)
end

export plot_states
function plot_states(state_times, states, params; save_dir_root, try_interactive=false)
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
    idx_cutoff, grid_cutoff = cutoff_mesh(grid_2d; top=1.2)

    fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(
        state_times, states, params
    )

    add_top_label(state_times, content_layout, controls.t_idx)
    state = @lift(states[$(controls.t_idx)])
    ax = plot_data(
        content_layout,
        state,
        params,
        :Saturation;
        grid_2d,
        heatmap_kwargs,
        grid_cutoff,
        idx_cutoff,
    )

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
    state_times,
    states,
    params,
    ::Val{:Saturation_Permeability};
    save_dir_root,
    try_interactive,
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    idx_cutoff, grid_cutoff = cutoff_mesh(grid_2d; top=1.2)

    fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(
        state_times, states, params
    )

    default_data_range = extrema(
        Iterators.flatten(extrema.(s[:Permeability] for s in states))
    )

    add_top_label(state_times, content_layout, controls.t_idx)
    state = @lift(states[$(controls.t_idx)])

    ax = plot_data(
        content_layout,
        state,
        params,
        :Permeability;
        grid_2d,
        heatmap_kwargs=(; colorrange=default_data_range, colormap=Reverse(:Purples)),
        colorbar_kwargs=nothing,
        grid_cutoff,
        idx_cutoff,
    )

    data = @lift let
        data = $state[:Saturation]
        data_thresholded = ifelse.(abs.(data) .< 0, 0.0, data)
        data_zeros = ifelse.(data_thresholded .<= 0, NaN, data_thresholded)
    end
    shaped_data = @lift(reshape($data, grid_2d.n)[idx_cutoff...])
    hm = plot_heatmap_from_grid!(
        ax, shaped_data, grid_cutoff; make_heatmap=true, heatmap_kwargs...
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
    idx_cutoff, grid_cutoff = cutoff_mesh(grid_2d; top=1.2)

    function pressure_diff(state)
        return state[:Pressure] .- states[1][:Pressure]
    end
    # default_data_range = (-2e6, 2e6)
    max_diff = maximum(
        maximum.(maximum.(abs.(s[:Pressure] .- states[1][:Pressure]) for s in states))
    )
    if max_diff == 0
        @warn "pressure field is constant over time"
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
    ax = plot_data(
        content_layout,
        state,
        params,
        pressure_diff;
        grid_2d,
        heatmap_kwargs,
        grid_cutoff,
        idx_cutoff,
    )

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
    idx_cutoff, grid_cutoff = cutoff_mesh(grid_2d; top=1.2)

    default_data_range = extrema(
        Iterators.flatten(extrema.(s[:Permeability] for s in states))
    )
    if default_data_range[1] == default_data_range[2]
        @warn "permeability is constant at $(states[1][:Permeability][1])"
        return nothing
    end
    fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(
        state_times, states, params; default_data_range, default_colormap=Reverse(:Purples)
    )

    add_top_label(state_times, content_layout, controls.t_idx)
    state = @lift(states[$(controls.t_idx)])
    ax = plot_data(
        content_layout,
        state,
        params,
        :Permeability;
        grid_2d,
        heatmap_kwargs,
        grid_cutoff,
        idx_cutoff,
    )

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
        @warn "rtm is constant at $(states[1][:rtm][1])"
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
        @warn "rtm image is constant over time"
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

function plot_states(
    state_times, states::Vector{<:Dict}, params, ::Val{:velocity}; kwargs...
)
    return plot_states(
        state_times, [s[:velocity] for s in states], params, Val(:velocity); kwargs...
    )
end

function plot_states(
    state_times, states::Vector{<:Dict}, params, ::Val{:density}; kwargs...
)
    return plot_states(
        state_times, [s[:density] for s in states], params, Val(:density); kwargs...
    )
end

function plot_states(
    state_times, states, params, ::Val{:velocity_diff}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    idx_cutoff, grid_cutoff = cutoff_mesh(grid_2d; top=1.2)

    function velocity_diff(state)
        return state[:velocity] .- states[1][:velocity]
    end
    # default_data_range = (-2e6, 2e6)
    max_diff = maximum(maximum.(maximum.(abs.(s) for s in velocity_diff.(states))))
    if max_diff == 0
        @warn "velocity field is constant over time"
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
    state = @lift(velocity_diff(states[$(controls.t_idx)]))

    ax = plot_data(
        content_layout,
        state,
        params,
        :velocity;
        grid_2d,
        heatmap_kwargs,
        grid_cutoff,
        idx_cutoff,
    )

    cb = content(fig[1, 1][1, 2])
    cb.label = "km/s"

    controls.interactive_savor.active[] = true
    try_interactive && show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting velocity_diff data to $save_dir_root"
        @withprogress name = "velocity_diff" begin
            save_dir = joinpath(save_dir_root, "velocity_diff")
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
    state_times, states, params, ::Val{:impedance}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    function impedance(state)
        return state[:density] .* state[:velocity]
    end
    default_data_range = extrema(Iterators.flatten(extrema.(impedance.(states))))
    if default_data_range[1] == default_data_range[2]
        @warn "impedance field is constant at $(states[1][1])"
        return nothing
    end
    fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(
        state_times, states, params; default_data_range, default_colormap=parula
    )

    add_top_label(state_times, content_layout, controls.t_idx)
    state = @lift(impedance(states[$(controls.t_idx)]))

    ax = plot_data(content_layout, state, params, :impedance; grid_2d, heatmap_kwargs)

    cb = content(fig[1, 1][1, 2])
    cb.label = L"g/mL$\cdot$km/s"

    controls.interactive_savor.active[] = true
    try_interactive && show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting impedance data to $save_dir_root"
        @withprogress name = "impedance" begin
            save_dir = joinpath(save_dir_root, "impedance")
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
    state_times, states, params, ::Val{:impedance_diff}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    idx_cutoff, grid_cutoff = cutoff_mesh(grid_2d; top=1.2)

    imp0 = states[1][:density] .* states[1][:velocity]
    function impedance_diff(state)
        return state[:density] .* state[:velocity] .- imp0
    end
    # default_data_range = (-2e6, 2e6)
    max_diff = maximum(maximum.(maximum.(abs.(s) for s in impedance_diff.(states))))
    if max_diff == 0
        @warn "impedance field is constant over time"
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
    state = @lift(impedance_diff(states[$(controls.t_idx)]))

    ax = plot_data(
        content_layout,
        state,
        params,
        :impedance;
        grid_2d,
        heatmap_kwargs,
        grid_cutoff,
        idx_cutoff,
    )

    cb = content(fig[1, 1][1, 2])
    cb.label = L"g/mL$\cdot$km/s"

    controls.interactive_savor.active[] = true
    try_interactive && show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting impedance_diff data to $save_dir_root"
        @withprogress name = "impedance_diff" begin
            save_dir = joinpath(save_dir_root, "impedance_diff")
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
    state_times, states, params, ::Val{:impedance_reldiff}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    idx_cutoff, grid_cutoff = cutoff_mesh(grid_2d; top=1.2)

    imp0 = states[1][:density] .* states[1][:velocity]
    function impedance_diff(state)
        return nothing
    end
    function impedance_reldiff(state)
        return 1e8 .* (state[:density] .* state[:velocity] .- imp0) ./ imp0
    end
    # default_data_range = (-2e6, 2e6)
    max_diff = maximum(maximum.(maximum.(abs.(s) for s in impedance_reldiff.(states))))
    if max_diff == 0
        @warn "impedance field is constant over time"
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
    state = @lift(impedance_reldiff(states[$(controls.t_idx)]))

    ax = plot_data(
        content_layout,
        state,
        params,
        :impedance;
        grid_2d,
        heatmap_kwargs,
        grid_cutoff,
        idx_cutoff,
    )

    cb = content(fig[1, 1][1, 2])
    cb.label = "% change"

    controls.interactive_savor.active[] = true
    try_interactive && show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting impedance_reldiff data to $save_dir_root"
        @withprogress name = "impedance_reldiff" begin
            save_dir = joinpath(save_dir_root, "impedance_reldiff")
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
    state_times, states, params, ::Val{:density_diff}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    idx_cutoff, grid_cutoff = cutoff_mesh(grid_2d; top=1.2)

    function density_diff(state)
        return state[:density] .- states[1][:density]
    end
    # default_data_range = (-2e6, 2e6)
    max_diff = maximum(maximum.(maximum.(abs.(s) for s in density_diff.(states))))
    if max_diff == 0
        @warn "density field is constant over time"
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
    state = @lift(density_diff(states[$(controls.t_idx)]))

    ax = plot_data(
        content_layout,
        state,
        params,
        :density;
        grid_2d,
        heatmap_kwargs,
        grid_cutoff,
        idx_cutoff,
    )

    cb = content(fig[1, 1][1, 2])
    cb.label = "g/mL"

    controls.interactive_savor.active[] = true
    try_interactive && show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting density_diff data to $save_dir_root"
        @withprogress name = "density_diff" begin
            save_dir = joinpath(save_dir_root, "density_diff")
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
    state_times, states, params, ::Val{:density_reldiff}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    idx_cutoff, grid_cutoff = cutoff_mesh(grid_2d; top=1.2)

    function density_reldiff(state)
        return 1e5 .* (state[:density] .- states[1][:density]) ./ states[1][:density]
    end
    # default_data_range = (-2e6, 2e6)
    max_diff = maximum(maximum.(maximum.(abs.(s) for s in density_reldiff.(states))))
    if max_diff == 0
        @warn "density field is constant over time"
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
    state = @lift(density_reldiff(states[$(controls.t_idx)]))

    ax = plot_data(
        content_layout,
        state,
        params,
        :density;
        grid_2d,
        heatmap_kwargs,
        grid_cutoff,
        idx_cutoff,
    )

    cb = content(fig[1, 1][1, 2])
    cb.label = "% change"

    controls.interactive_savor.active[] = true
    try_interactive && show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting density_reldiff data to $save_dir_root"
        @withprogress name = "density_reldiff" begin
            save_dir = joinpath(save_dir_root, "density_reldiff")
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
    state_times, states, params, ::Val{:velocity_reldiff}; save_dir_root, try_interactive
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    idx_cutoff, grid_cutoff = cutoff_mesh(grid_2d; top=1.2)

    function velocity_reldiff(state)
        return 1e5 .* (state[:velocity] .- states[1][:velocity]) ./ states[1][:velocity]
    end
    # default_data_range = (-2e6, 2e6)
    max_diff = maximum(maximum.(maximum.(abs.(s) for s in velocity_reldiff.(states))))
    if max_diff == 0
        @warn "velocity field is constant over time"
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
    state = @lift(velocity_reldiff(states[$(controls.t_idx)]))

    ax = plot_data(
        content_layout,
        state,
        params,
        :velocity;
        grid_2d,
        heatmap_kwargs,
        grid_cutoff,
        idx_cutoff,
    )

    cb = content(fig[1, 1][1, 2])
    cb.label = "% change"

    controls.interactive_savor.active[] = true
    try_interactive && show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting velocity_reldiff data to $save_dir_root"
        @withprogress name = "velocity_reldiff" begin
            save_dir = joinpath(save_dir_root, "velocity_reldiff")
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
        @warn "dshot is constant at $(states[1][:dshot][1][1])"
        return nothing
    end
    default_data_range = (-max_diff, max_diff)

    content_aspect = 16 / 9
    fig, content_layout, controls, heatmap_kwargs = make_time_figure_with_controls(
        state_times,
        states;
        default_data_range,
        content_aspect,
        default_colormap=Reverse(:RdBu),
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
        @warn "dshot is constant over time"
        return nothing
    end
    default_data_range = (-max_diff, max_diff)

    content_aspect = 16 / 9
    fig, content_layout, controls, heatmap_kwargs = make_time_figure_with_controls(
        state_times,
        states;
        default_data_range,
        content_aspect,
        default_colormap=Reverse(:RdBu),
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
        @warn "velocity is constant at $(states[1][1])"
        return nothing
    end
    fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(
        state_times, states, params; default_data_range, default_colormap=:YlOrRd
    )

    state = @lift(states[$(controls.t_idx)] ./ 1e3)
    ax = plot_scalar_field(content_layout, state, params; grid_2d, heatmap_kwargs)

    cb = content(fig[1, 1][1, 2])
    cb.label = "km/s"
    # cb.labelrotation[] = 0.0

    # on(cb.axis.elements[:labeltext].position) do labeltext
    #     Makie.translate!(labeltext, 10f0, - 15 -Makie.widths(Makie.boundingbox(cb.axis.elements[:axisline], :absolute))[2]/2, 0f0)
    #     return Makie.Consume(true)
    # end

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
        @warn "velocity0 is constant at $(states[1][1])"
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
        @warn "density is constant at $(states[1][1])"
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
        @warn "density0 is constant at $(states[1][1])"
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

export plot_points_of_interest, plot_points_of_interest!
function plot_points_of_interest(params, args...; save_dir_root, try_interactive, kwargs...)
    colormap = parula
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    tmp = Observable(zeros(grid_2d.n) .+ NaN)

    fig, content_layout, controls, heatmap_kwargs = make_time_domain_figure_with_controls(
        [0], [tmp], params; default_data_range=(0, 1)
    )

    ax = plot_scalar_field(content_layout, tmp, params; grid_2d, heatmap_kwargs)
    plot_points_of_interest!(ax, params, args...; kwargs...)

    cb = content(fig[1, 1][1, 2])
    delete!(cb)

    controls.interactive_savor.active[] = true
    try_interactive && show_interactive_preview(fig, controls)
    controls.hide_controls.active[] = true

    if controls.interactive_savor.active[]
        @info "Plotting experiment setup to $save_dir_root"
        file_path = joinpath(save_dir_root, "experiment_setup.png")
        mkpath(save_dir_root)
        wsave(file_path, fig)
    end
end

function plot_points_of_interest!(
    ax, params, src_positions, rec_positions; idx_wb, idx_unconformity
)
    grid_2d = get_2d_plotting_mesh(params.transition.mesh)
    ORANGE = "#fc8d62"
    BLUE = "#8da0cb"
    GREEN = "#66c2a5"
    PINK = "#e78ac3"
    LIGHTGREEN = "#a6d854"
    BLACK = "#222"

    xs =
        range(grid_2d.d[1] / 2; length=grid_2d.n[1], step=grid_2d.d[1]) .- grid_2d.origin[1]
    ys =
        range(grid_2d.d[end] / 2; length=grid_2d.n[end], step=grid_2d.d[end]) .-
        grid_2d.origin[end]

    water_layer = zeros(grid_2d.n) .+ NaN
    water_layer[:, 1:idx_wb] .= 0.0
    heatmap!(ax, xs, ys, water_layer; colormap=[BLUE], colorrange=(0, 1))
    le_water_layer = (
        "Water layer", MarkerElement(; color=BLUE, marker=:rect, markersize=30)
    )

    unconformity = zeros(grid_2d.n) .+ NaN
    for (row, col) in enumerate(idx_unconformity)
        unconformity[row, (col - 8):col] .= 1.0
    end
    heatmap!(ax, xs, ys, unconformity; colormap=[BLACK], colorrange=(0, 1))
    le_unconformity = (
        "Reservoir seal", MarkerElement(; color=BLACK, marker=:rect, markersize=24)
    )

    x = collect(t[1] for t in params.transition.injection.trajectory) ./ 1e3
    y = collect(t[3] for t in params.transition.injection.trajectory) ./ 1e3
    lines!(ax, x, y; linewidth=8, color=LIGHTGREEN)
    le_injection = (
        "Injection range", MarkerElement(; color=LIGHTGREEN, marker=:rect, markersize=16)
    )

    # Plot seismic sources.
    sc_sources = scatter!(
        ax,
        src_positions[1] ./ 1e3,
        src_positions[3] ./ 1e3;
        marker=:xcross,
        strokewidth=1,
        markersize=25,
        color=ORANGE,
    )
    le_sources = ("Sources", sc_sources)

    # Plot seismic receivers.
    sc_receivers = scatter!(
        ax,
        rec_positions[1] ./ 1e3,
        rec_positions[3] ./ 1e3;
        marker=:circle,
        strokewidth=1,
        markersize=15,
        color=PINK,
    )
    le_receivers = ("Receivers", sc_receivers)

    # Add some entries to the legend group.
    custom_legend_entries = [
        le_sources, le_water_layer, le_receivers, le_unconformity, le_injection
    ]

    markers = last.(custom_legend_entries)
    labels = first.(custom_legend_entries)
    return leg = axislegend(ax, markers, labels; position=:rc, margin=(10, 10, 10, -80))
end
