
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

function plot_plume_data(observation_times, states, save_dir_root, params)
    @info "Plotting plume data to $save_dir_root"

    # Get mesh parameters in kilometers.
    grid = params.transition.mesh
    grid = MeshOptions(grid; d=grid.d ./ 1e3, origin=grid.origin ./ 1e3)
    grid_2d = MeshOptions(
        grid; d=grid.d[[1, end]], origin=grid.origin[[1, end]], n=grid.n[[1, end]]
    )

    # Plot first saturation.
    fig_scale = 96
    heatmap_aspect = get_grid_col_aspect(grid_2d)
    content_height = round(Int, 6*fig_scale)
    content_size = (round(Int, content_height * heatmap_aspect), content_height)
    fig = Figure(; size=content_size)
    content_grid_position = fig[1, 1]
    content_layout = GridLayout(content_grid_position)

    ax = Axis(content_layout[1, 1])

    year = 3600 * 24 * 365.2425
    previous_num_blocks = length(fig.content)

    controls_height = 4*fig_scale
    resize!(fig, content_size[1], content_size[2] + controls_height)
    controls_layout_size = (; width = Auto(), height=Fixed(controls_height))
    controls_layout = GridLayout(fig[2, 1]; controls_layout_size...)
    colsize!(controls_layout, 1, Relative(1))


    controls_time_position = controls_layout[1, 1]
    controls_time_layout = get_padding_layout(controls_time_position)
    add_box(controls_time_position; cornerradius = 10, color = (:yellow, 0.1), strokecolor = :transparent)

    slider_grid = SliderGrid(
        controls_time_layout[1,1],
        (
            label = "Time",
            range = 1:length(states),
            format = i -> "$(observation_times[i]/year) years",
            startvalue = 6
        ),
    )

    controls_colormap_position = controls_layout[2, 1]
    controls_colormap_layout = get_padding_layout(controls_colormap_position; top=0f0)
    add_box(controls_colormap_position; cornerradius = 10, color = (:blue, 0.1), strokecolor = :transparent)

    Label(controls_colormap_layout[1, 1], "Colorbar options", halign = :center, valign = :center)

    colormap_selector = let layout = controls_colormap_layout[1, 2]
        function colormap_validator(colormap)
            return colormap == "" || isnothing(colormap) || colormap == "parula" || colormap in Makie.all_gradient_names
        end
        colormap_selector = Textbox(layout[1, 1],
            placeholder = "colormap",
            validator = colormap_validator,
            boxcolor = RGBf(0.94, 0.94, 0.94),
            boxcolor_focused = RGBf(0.94, 0.94, 0.94),
            boxcolor_focused_invalid = RGBf(0.94, 0.94, 0.94),
            width = 200,
        )
    end

    colormap_reversor = let layout = controls_colormap_layout[1, 3]
        Button(layout[1,1], label = "Reverse colormap")
    end

    colorscale_options = [("linear", identity), ("log10", log10)]
    colorscale_menu = let layout = controls_colormap_layout[1, 4]
        Menu(layout[1, 1]; options = colorscale_options, default = "linear")
    end

    colorrange_slider = IntervalSlider(controls_colormap_layout[2, :];
        range = LinRange(0, 1, 1000),
        startvalues = (0.0, 1.0),
        horizontal = true,
    )

    controls_other_position = controls_layout[3, 1]
    controls_other_layout = get_padding_layout(controls_other_position; top=0f0)
    add_box(controls_other_position; cornerradius = 10, color = (:green, 0.1), strokecolor = :transparent)

    axis_reset = Button(controls_other_layout[:, 1], label = "Reset view")

    interactive_savor = let layout = controls_other_layout[1, 2]
        Label(layout[1, 1], "Save images after closing", halign = :center, valign = :center)
        Toggle(layout[1, 2], active = false)
    end

    hide_controls = let layout = controls_other_layout[2, 2]
        Label(layout[1, 1], "Hide controls (toggle with 'k')", halign = :center, valign = :center)
        Toggle(layout[1,2], active=false)
    end

    t_idx = slider_grid.sliders[1].value
    colorscale = colorscale_menu.selection
    colormap = Observable{Any}(parula)
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
    interactive_blocks = copy(fig.content[previous_num_blocks+1:end])

    notify(colorscale_menu.selection)

    state = @lift(states[$t_idx])
    t = @lift(observation_times[$t_idx])

    data = @lift($state[:Saturation])
    data_thresholded = @lift(ifelse.(abs.($data) .< 0, 0, $data))
    data_zeros = @lift(ifelse.($data_thresholded .<= 0, NaN, $data_thresholded))
    shaped_data = @lift(reshape($data_zeros, grid_2d.n))
    colorrange = @lift begin
        interval = $(colorrange_slider.interval)
        if $colorscale == log10
            # Map [0,1] to [1e-6, 1e0] logarithmically
            maxrange = (-6.0, 0.0)
            if interval[1] >= interval[2]
                return 1e1 .^ maxrange
            end
            return 1e1 .^ (maxrange[1] .+ (interval .* (maxrange[2] .- maxrange[1])))
        else
            if interval[1] >= interval[2]
                return (0, 1)
            end
            return interval
        end
    end
    lowclip = Observable{Any}(nothing)
    onany(colorrange, colormap) do colorrange, colormap
        if colorrange[1] > 0
            lowclip[] = resample_cmap(colormap, 2; alpha=0.3)[1]
        else
            lowclip[] = nothing
        end
    end
    highclip = Observable{Any}(nothing)
    onany(colorrange, colormap) do colorrange, colormap
        if colorrange[2] < 1
            highclip[] = resample_cmap(colormap, 2; alpha=0.3)[2]
        else
            highclip[] = nothing
        end
    end
    hm = plot_heatmap_from_grid!(ax, shaped_data, grid_2d; make_heatmap=true,
        colormap,
        lowclip,
        highclip,
        colorscale,
        colorrange
    )

    time_str = @lift(latexstring("\$t\$ = ", cfmt("%.3g", $t/year), " years"))
    Colorbar(content_layout[1, 2], hm)
    Label(content_layout[1, 1, Top()], time_str, halign = :center, valign = :bottom, font = :bold)
    ax.xlabel = "Horizontal (km)"
    ax.ylabel = "Depth (km)"

    colsize!(content_layout, 1, Aspect(1, heatmap_aspect))
    hidespines!(ax) 

    on(axis_reset.clicks) do n
        reset_limits!(ax)
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

    on(events(fig.scene).keyboardbutton) do event
        if event.action == Keyboard.press || event.action == Keyboard.repeat
            if event.key == Keyboard.k
                hide_controls.active[] = !hide_controls.active.val
            end
        end
    end


    onany(fig.scene.viewport, hide_controls.active) do v, hide_controls_active
        # Compute content width based on height of figure, controls, and content aspect.
        if hide_controls_active
            content_width = heatmap_aspect * v.widths[2]
        else
            content_width = heatmap_aspect * (v.widths[2] - controls_height)
        end
        if v.widths[1] < content_width
            colsize!(content_layout, 1, Auto())
            rowsize!(content_layout, 1, Aspect(1, 1/heatmap_aspect))
        else
            rowsize!(content_layout, 1, Auto())
            colsize!(content_layout, 1, Aspect(1, heatmap_aspect))
        end
    end

    if isinteractive()
        screen = display(fig)
        if hasmethod(wait, Tuple{typeof(screen)})
            wait(screen)
            if !interactive_savor.active.val
                return fig
            end
        end
        println("Press enter to continue. Type c to skip saving plots.")
        r = readline(stdin)
        if strip(r) == "c"
            return fig
        end
    end
    hide_controls.active[] = true

    # Save all the saturation figures.
    @withprogress name = "state vs t" begin
        save_dir = joinpath(save_dir_root, "plume")
        mkpath(save_dir)
        for i in 1:length(states)
            t_idx[] = i
            file_path = joinpath(save_dir, "$(cfmt("%02d", i)).png")
            wsave(file_path, fig)
            @logprogress i / length(states)
        end
    end

    @withprogress name = "log state vs t" begin
        save_dir = joinpath(save_dir_root, "plume_log")
        mkpath(save_dir)
        colorscale[] = log10
        for i in 1:length(states)
            t_idx[] = i
            file_path = joinpath(save_dir, "$(cfmt("%02d", i)).png")
            wsave(file_path, fig)
            @logprogress i / length(states)
        end
    end
end
