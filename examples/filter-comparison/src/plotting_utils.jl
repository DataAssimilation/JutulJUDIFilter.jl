
using Makie:
    Figure, Axis, Colorbar, colsize!, Aspect, resize_to_layout!, xlims!, ylims!, contourf

function plot_heatmap_from_grid!(ax, a, grid; kwargs...)
    return plot_heatmap_from_grid!(
        ax, a; dims=grid.n, deltas=grid.d, origin=grid.origin, kwargs...
    )
end

function plot_heatmap_from_grid(args...; make_colorbar=false, kwargs...)
    fig = Figure()
    ax = Axis(fig[1, 1]; yreversed=true)
    hm = plot_heatmap_from_grid!(ax, args...; kwargs...)
    if make_colorbar
        Colorbar(fig[:, end + 1], hm)
    end
    return fig, ax, hm
end

get_grid_col_aspect(grid) = get_grid_col_aspect(grid.n, grid.d)
get_grid_col_aspect(dims, deltas) = (dims[1] * deltas[1]) / (dims[end] * deltas[end])

get_grid_row_aspect(grid) = get_grid_row_aspect(grid.n, grid.d)
get_grid_row_aspect(dims, deltas) = (dims[end] * deltas[end]) / (dims[1] * deltas[1])

function get_coordinate_corners(; dims, deltas, origin)
    xs = range(0; length=dims[1] + 1, step=deltas[1]) .- origin[1]
    ys = range(0; length=dims[end] + 1, step=deltas[end]) .- origin[end]
    return xs, ys
end

function get_coordinates_cells(; dims, deltas, origin)
    xs = deltas[1] / 2 .+ range(0; length=dims[1], step=deltas[1]) .- origin[1]
    ys = deltas[end] / 2 .+ range(0; length=dims[end], step=deltas[end]) .- origin[end]
    return xs, ys
end

function plot_heatmap_from_grid!(
    ax,
    a;
    dims,
    deltas=(1, 1),
    origin=(0, 0),
    colorrange=nothing,
    fix_colorrange=true,
    make_divergent=false,
    make_heatmap=false,
    kwargs...,
)
    if make_heatmap
        xs, ys = get_coordinate_corners(; dims, deltas, origin)
    else
        xs, ys = get_coordinates_cells(; dims, deltas, origin)
    end

    if isnothing(colorrange)
        m1 = @lift(minimum(x -> isfinite(x) ? x : Inf, $a))
        m2 = @lift(maximum(x -> isfinite(x) ? x : -Inf, $a))
        colorrange = @lift(($m1, $m2))
    end
    # if fix_colorrange
    #     colorrange = get_colorrange(colorrange; make_divergent)
    # end

    if make_heatmap
        hm = heatmap!(ax, xs, ys, a; rasterize=true, colorrange, kwargs...)
    else
        levels = pop!(Dict(kwargs), :levels, 10)
        mode = pop!(Dict(kwargs), :normal, 10)
        if isa(levels, Int)
            # TODO: this doesn't work because colorrange may be an Observable.
            levels_orig = levels
            levels = @lift(range($colorrange[1], $colorrange[2], levels_orig))
        elseif mode == :relative
            levels_orig = levels
            levels = @lift(
                levels_orig .* ($colorrange[2] - $colorrange[1]) .+ $colorrange[1]
            )
        end
        hm = contourf!(ax, xs, ys, a; levels, kwargs...)
    end
    xlims!(ax, -origin[1], dims[1] * deltas[1] - origin[1])
    ylims!(ax, dims[end] * deltas[end] - origin[end], -origin[end])
    return hm
end

function get_padding_layout(grid_position; left=5.0f0, top=5.0f0, right=5.0f0, bottom=5.0f0)
    padding_layout = GridLayout(grid_position, 3, 3)
    rowsize!(padding_layout, 1, Fixed(top))
    rowsize!(padding_layout, 3, Fixed(bottom))
    colsize!(padding_layout, 1, Fixed(left))
    colsize!(padding_layout, 3, Fixed(right))
    return GridLayout(padding_layout[2, 2])
end

function add_box(grid_position; z=-100, kwargs...)
    b = Box(grid_position; kwargs...)
    Makie.translate!(b.blockscene, 0, 0, z)
    return b
end

function set_up_time_heatmap_controls(
    fig,
    content_size,
    state_times;
    fig_scale,
    divergent=false,
    default_data_range,
    default_colormap,
)
    previous_num_blocks = length(fig.content)

    controls_height = 4 * fig_scale
    resize!(fig, content_size[1], content_size[2] + controls_height)
    controls_layout_size = (; width=Auto(), height=Fixed(controls_height))
    controls_layout = GridLayout(fig[2, 1]; controls_layout_size...)
    colsize!(controls_layout, 1, Relative(1))

    controls_time_position = controls_layout[1, 1]
    controls_time_layout = get_padding_layout(controls_time_position)
    add_box(
        controls_time_position;
        cornerradius=10,
        color=(:yellow, 0.1),
        strokecolor=:transparent,
    )

    if eltype(state_times) == Int
        label = "Index"
        format = i -> "$i"
    else
        label = "Time"
        format = i -> "$(state_times[i]/my_year) years"
    end
    slider_grid = SliderGrid(
        controls_time_layout[1, 1],
        (label, range=1:length(state_times), format, startvalue=length(state_times)),
    )

    controls_colormap_position = controls_layout[2, 1]
    controls_colormap_layout = get_padding_layout(controls_colormap_position; top=0.0f0)
    add_box(
        controls_colormap_position;
        cornerradius=10,
        color=(:blue, 0.1),
        strokecolor=:transparent,
    )

    Label(controls_colormap_layout[1, 1], "Colorbar"; halign=:center, valign=:center)

    colormap_selector = let layout = controls_colormap_layout[1, 2]
        function colormap_validator(colormap)
            return colormap == "" ||
                   isnothing(colormap) ||
                   colormap == "parula" ||
                   colormap in Makie.all_gradient_names
        end
        colormap_selector = Textbox(
            layout[1, 1];
            placeholder="colormap",
            validator=colormap_validator,
            boxcolor=RGBf(0.94, 0.94, 0.94),
            boxcolor_focused=RGBf(0.94, 0.94, 0.94),
            boxcolor_focused_invalid=RGBf(0.94, 0.94, 0.94),
            width=200,
        )
    end

    colormap_reversor = let layout = controls_colormap_layout[1, 3]
        Button(layout[1, 1]; label="Reverse colormap")
    end

    colorscale_options = [("linear", identity), ("log10", log10)]
    colorscale_menu = let layout = controls_colormap_layout[1, 4]
        Menu(layout[1, 1]; options=colorscale_options, default="linear")
    end

    colorrange_slider_layout = GridLayout(controls_colormap_layout[2, :])
    colorscale = colorscale_menu.selection

    function validator(s)
        val = tryparse(Float64, s)
        return !isnothing(val) && (colorscale[] != log10 || val > 0)
    end
    colorrange_min_selector = Textbox(
        colorrange_slider_layout[1, 1];
        stored_string=string(default_data_range[1]),
        validator=validator,
        boxcolor=RGBf(0.94, 0.94, 0.94),
        boxcolor_focused=RGBf(0.94, 0.94, 0.94),
        boxcolor_focused_invalid=RGBf(0.94, 0.94, 0.94),
        width=90,
    )
    colorrange_slider = IntervalSlider(
        colorrange_slider_layout[1, 2];
        range=LinRange(0, 1, 1000),
        startvalues=(0.0, 1.0),
        horizontal=true,
    )
    colorrange_max_selector = Textbox(
        colorrange_slider_layout[1, 3];
        stored_string=string(default_data_range[2]),
        validator=validator,
        boxcolor=RGBf(0.94, 0.94, 0.94),
        boxcolor_focused=RGBf(0.94, 0.94, 0.94),
        boxcolor_focused_invalid=RGBf(0.94, 0.94, 0.94),
        width=90,
    )
    colorrange_min_max = @lift begin
        m1 = tryparse(Float64, $(colorrange_min_selector.stored_string))
        m2 = tryparse(Float64, $(colorrange_max_selector.stored_string))
        extrema((m1, m2))
    end

    if divergent
        on(colorrange_min_selector.stored_string) do s
            max_s_target = string(-parse(Float64, s))
            max_s = colorrange_max_selector.stored_string[]
            if max_s != max_s_target
                colorrange_max_selector.stored_string[] = max_s_target
                colorrange_max_selector.displayed_string[] = max_s_target
            end
        end
        on(colorrange_max_selector.stored_string) do s
            min_s_target = string(-parse(Float64, s))
            min_s = colorrange_min_selector.stored_string[]
            if min_s != min_s_target
                colorrange_min_selector.stored_string[] = min_s_target
                colorrange_min_selector.displayed_string[] = min_s_target
            end
        end
        let
            previous_indices = collect(colorrange_slider.selected_indices[])
            function update_idx(indices; previous_indices=previous_indices)
                d = previous_indices[1] == indices[1]
                N = length(colorrange_slider.range[])
                if d
                    # Second index was dragged, so update first index accordingly
                    i_ctrl = indices[2]
                    if i_ctrl <= N / 2
                        i_ctrl = ceil(Int, N / 2)
                    end
                    # Map [1, N] to [-(N-1)/2, (N-1)/2], then negate and map back to [1, N].
                    i_target = N + 1 - i_ctrl
                    new_indices = (i_target, i_ctrl)
                else
                    # First index was dragged, so update second index accordingly
                    i_ctrl = indices[1]
                    if i_ctrl >= N / 2
                        i_ctrl = floor(Int, N / 2)
                    end
                    # Map [1, N] to [-(N-1)/2, (N-1)/2], then negate and map back to [1, N].
                    i_target = N + 1 - i_ctrl
                    new_indices = (i_ctrl, i_target)
                end
                previous_indices .= new_indices
                if indices != new_indices
                    colorrange_slider.selected_indices[] = new_indices
                end
            end
            on(update_idx, colorrange_slider.selected_indices)
        end
    end

    controls_other_position = controls_layout[3, 1]
    controls_other_layout = get_padding_layout(controls_other_position; top=0.0f0)
    add_box(
        controls_other_position;
        cornerradius=10,
        color=(:green, 0.1),
        strokecolor=:transparent,
    )

    interactive_savor = let layout = controls_other_layout[1, 2]
        Label(layout[1, 1], "Save images after closing"; halign=:center, valign=:center)
        Toggle(layout[1, 2]; active=false)
    end

    hide_controls = let layout = controls_other_layout[2, 2]
        Label(layout[1, 1], "Hide controls (toggle with 'k')"; halign=:center, valign=:center)
        Toggle(layout[1, 2]; active=false)
    end

    t_idx = slider_grid.sliders[1].value
    colormap = Observable{Any}(default_colormap)
    on(colormap_selector.stored_string) do s
        colormap[] = if s == "parula" || s == "" || isnothing(s)
            parula
        else
            s
        end
    end
    on(colormap_reversor.clicks) do _
        if isa(colormap.val, Reverse)
            colormap[] = colormap.val.data
        else
            colormap[] = Reverse(colormap.val)
        end
    end
    interactive_blocks = copy(fig.content[(previous_num_blocks + 1):end])

    notify(colorscale_menu.selection)

    on(colorscale) do scale
        if scale == log10
            if colorrange_min_max[][1] <= 0
                colorrange_min_selector.displayed_string[] = "1e-6"
                colorrange_min_selector.stored_string[] = "1e-6"
            end
            if colorrange_min_max[][2] <= 0
                colorrange_max_selector.displayed_string[] = "1e0"
                colorrange_max_selector.stored_string[] = "1e0"
            end
        end
    end

    colorrange = @lift begin
        interval = $(colorrange_slider.interval)
        user_range = $colorrange_min_max
        if $colorscale == log10
            if interval[1] >= interval[2]
                return user_range
            end
            # Map [0,1] to user_range logarithmically
            maxrange = log10.(user_range)
            return 1e1 .^ (maxrange[1] .+ (interval .* (maxrange[2] .- maxrange[1])))
        else
            if interval[1] >= interval[2]
                return user_range
            end
            # Map interval from [0,1] to user_range.
            return user_range[1] .+ interval .* (user_range[2] - user_range[1])
        end
    end
    lowclip = Observable{Any}(nothing)
    onany(colorrange, colormap) do colorrange, colormap
        if colorrange[1] > default_data_range[1]
            lowclip[] = resample_cmap(colormap, 2; alpha=0.3)[1]
        else
            lowclip[] = nothing
        end
    end
    highclip = Observable{Any}(nothing)
    onany(colorrange, colormap) do colorrange, colormap
        if colorrange[2] < default_data_range[2]
            highclip[] = resample_cmap(colormap, 2; alpha=0.3)[2]
        else
            highclip[] = nothing
        end
    end

    on(events(fig.scene).keyboardbutton) do event
        if event.action == Keyboard.press || event.action == Keyboard.repeat
            if event.key == Keyboard.k
                hide_controls.active[] = !hide_controls.active.val
            end
        end
    end

    on(hide_controls.active) do a
        if a
            foreach(b -> b.blockscene.visible[] = false, interactive_blocks)
            content(fig[2, 1]).height[] = Fixed(0)
            resize!(fig, content_size[1], content_size[2])
        else
            content(fig[2, 1]).height[] = controls_layout_size[2]
            foreach(b -> b.blockscene.visible[] = true, interactive_blocks)
            resize!(fig, content_size[1], content_size[2] + controls_height)
        end
    end

    heatmap_kwargs = (; colormap, lowclip, highclip, colorscale, colorrange)
    p = (; t_idx, colorscale, hide_controls, interactive_savor, controls_height)
    return p, heatmap_kwargs
end

function show_interactive_preview(fig, controls)
    # Show interactively.
    if isinteractive()
        screen = display(fig)
        if hasmethod(wait, Tuple{typeof(screen)})
            glfw_screen = GLMakie.to_native(screen)
            on(events(fig.scene).keyboardbutton) do _
                if ispressed(fig.scene, Keyboard.escape)
                    GLMakie.GLFW.SetWindowShouldClose(glfw_screen, true)
                end
            end
            wait(screen)
        else
            println("Press enter to continue. Type c to skip saving plots.")
            r = readline(stdin)
            controls.interactive_savor.active[] = !(strip(r) == "c")
        end
    end
end
