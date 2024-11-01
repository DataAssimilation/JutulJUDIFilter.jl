
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

function get_padding_layout(grid_position; left=5f0, top=5f0, right=5f0, bottom=5f0)
    padding_layout = GridLayout(grid_position, 3, 3)
    rowsize!(padding_layout, 1, Fixed(top))
    rowsize!(padding_layout, 3, Fixed(bottom))
    colsize!(padding_layout, 1, Fixed(left))
    colsize!(padding_layout, 3, Fixed(right))
    return GridLayout(padding_layout[2,2])
end


function add_box(grid_position; z=-100, kwargs...)
    b = Box(grid_position; kwargs...)
    Makie.translate!(b.blockscene, 0, 0, z)
    return b
end
