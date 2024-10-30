
using CairoMakie: Figure, Axis, Colorbar, colsize!, Aspect, resize_to_layout!, xlims!, ylims!, contourf

function plot_heatmap_from_grid!(ax, a, grid; kwargs...)
    plot_heatmap_from_grid!(ax, a; dims=grid.n, deltas=grid.d, origin=grid.origin, kwargs...)
end

function plot_heatmap_from_grid(args...; make_colorbar=false, kwargs...)
    fig = Figure()
    ax = Axis(fig[1,1], yreversed=true)
    hm = plot_heatmap_from_grid!(ax, args...; kwargs...)
    if make_colorbar
        Colorbar(fig[:, end+1], hm)
    end
    return fig, ax, hm
end

function rescale_heatmap_to_grid!(fig; dims, deltas=(1, 1), origin=(0, 0))
    aspect = (dims[1] * deltas[1]) / (dims[end] * deltas[end])
    colsize!(fig.layout, 1, Aspect(1, aspect))
    resize_to_layout!(fig)
end

function get_coordinate_corners(; dims, deltas, origin)
    xs = range(0; length = dims[1]+1, step = deltas[1]) .- origin[1]
    ys = range(0; length = dims[end]+1, step = deltas[end]) .- origin[end]
    return xs, ys
end

function get_coordinates_cells(; dims, deltas, origin)
    xs = deltas[1]/2 .+ range(0; length = dims[1], step = deltas[1]) .- origin[1]
    ys = deltas[end]/2 .+ range(0; length = dims[end], step = deltas[end]) .- origin[end]
    return xs, ys
end

function plot_heatmap_from_grid!(ax, a; dims, deltas=(1, 1), origin=(0, 0), colorrange=nothing, fix_colorrange=true, make_divergent=false, make_heatmap = false, kwargs...)
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
        hm = heatmap!(ax, xs, ys, a; colorrange, kwargs...)
    else
        levels = pop!(Dict(kwargs), :levels, 10)
        mode = pop!(Dict(kwargs), :normal, 10)
        if isa(levels, Int)
            # TODO: this doesn't work because colorrange may be an Observable.
            levels_orig = levels
            levels = @lift(range($colorrange[1], $colorrange[2], levels_orig))
        elseif mode == :relative
            levels_orig = levels
            levels = @lift(levels_orig .* ($colorrange[2] - $colorrange[1]) .+ $colorrange[1])
        end
        hm = contourf!(ax, xs, ys, a; levels, kwargs...)
    end
    xlims!(ax, - origin[1], dims[1] * deltas[1] - origin[1])
    ylims!(ax, dims[end] * deltas[end] - origin[end], - origin[end])
    rescale_heatmap_to_grid!(ax.parent; dims, deltas, origin)
    return hm
end
