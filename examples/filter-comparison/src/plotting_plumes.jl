
using DrWatson: srcdir, datadir, plotsdir, produce_or_load, wsave
# using CairoMakie: Label, @L_str, Axis, scatterlines!, ylims!, Legend
using Format: cfmt
# using Ensembles
# using Lorenz63Filter
# using ImageFiltering: ImageFiltering, imfilter
using ProgressLogging: @withprogress, @logprogress

using CairoMakie

include(srcdir("plotting_utils.jl"))

function plot_plume_data(observation_times, states, save_dir_root, params)
    @withprogress name = "state vs t" let
        # Get mesh parameters in kilometers.
        grid = params.transition.mesh
        grid = MeshOptions(grid; d=grid.d./1e3, origin=grid.origin./1e3)
        grid_2d = MeshOptions(grid; d=grid.d[[1,end]], origin=grid.origin[[1,end]], n=grid.n[[1,end]])

        save_dir = joinpath(save_dir_root, "plume")
        mkpath(save_dir)

        t_index = Observable(1)

        # Plot first saturation.
        fig = Figure()
        ax = Axis(fig[1, 1])

        state = @lift(states[$t_index])
        t = @lift(observation_times[$t_index])

        data = @lift($state[:Saturation])
        data_zeros = @lift(ifelse.($data .== 0, NaN, $data))
        shaped_data = @lift(reshape($data_zeros, grid_2d.n))
        hm = plot_heatmap_from_grid!(ax, shaped_data, grid_2d; make_heatmap=true, colorrange=(0,1))

        time_str = @lift(string(L"t = ", cfmt("%.3g", $t), " seconds"))
        Label(fig[1, 1, Top()], time_str, halign = :center, valign = :bottom, font = :bold)
        Colorbar(fig[:, end+1], hm)

        ax.xlabel = "Horizontal (km)"
        ax.ylabel = "Depth (km)"

        # Save all the saturation figures.
        for i in 1:length(states)
            if i != 1
                t_index[] = i
            end
            file_path = joinpath(save_dir, "$(cfmt("%02d", i)).png")
            wsave(file_path, fig)
            @logprogress i / length(states)
        end
    end
end

