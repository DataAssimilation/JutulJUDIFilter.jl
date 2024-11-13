using Makie: scatterlines!, scatterlines, @L_str, Figure, Axis

export get_next_jump_idx
export plot_disjoint_lines, plot_disjoint_lines!
export plot_state_over_time, plot_error_metric_over_time

"""Advance idx until two consecutive times are not strictly increasing.

Specifically, `times[idx:get_next_jump_idx(times, idx)]` is strictly increasing.

# Examples
```jldoctest
julia> get_next_jump_idx([1, 2, 3])
3
julia> get_next_jump_idx([1, 2, 3, 1])
3
julia> get_next_jump_idx([1, 2, 3, 3])
3
julia> get_next_jump_idx([1, 2, 3, 1, 2, 3, 4, 5])
3
julia> get_next_jump_idx([1, 2, 3, 1, 2, 3, 4, 5, 1, 2], 4)
8
```
"""
function get_next_jump_idx(times, idx=1)
    jump_idx = idx + 1
    while jump_idx <= length(times) && times[jump_idx] > times[jump_idx - 1]
        jump_idx += 1
    end
    return jump_idx - 1
end

function plot_disjoint_lines!(
    ax, times, ys; disjoint=true, do_colors=false, connect=nothing, kwargs...
)
    if !disjoint
        scatterlines!(ax, times, ys; kwargs...)
        return nothing
    end

    end_idx = 0
    color = get(kwargs, :color, nothing)
    if do_colors && !isnothing(color)
        @warn "do_colors=true so ignoring color argument: $(color)"
    end
    while end_idx + 1 <= length(times)
        start_idx = end_idx + 1
        if !isnothing(connect) && end_idx > 0
            sc = scatterlines!(
                ax,
                [times[end_idx], times[start_idx]],
                [ys[end_idx], ys[start_idx]];
                connect...,
            )
        end
        end_idx = get_next_jump_idx(times, start_idx)
        if do_colors
            color = 1:(end_idx - start_idx + 1)
        end
        if isnothing(color)
            sc = scatterlines!(
                ax, times[start_idx:end_idx], ys[start_idx:end_idx]; kwargs...
            )
            color = sc.color
        else
            sc = scatterlines!(
                ax, times[start_idx:end_idx], ys[start_idx:end_idx]; kwargs..., color
            )
        end
        color = sc.color
    end
end

function plot_disjoint_lines(times, ys; disjoint=true, kwargs...)
    if !disjoint
        return scatterlines(times, ys; kwargs...)
    end

    start_idx = 1
    end_idx = get_next_jump_idx(times, start_idx)
    fig, ax, sc = scatterlines(times[start_idx:end_idx], ys[start_idx:end_idx]; kwargs...)
    plot_disjoint_lines!(
        ax, times[(end_idx + 1):end], ys[(end_idx + 1):end]; color=sc.color, kwargs...
    )
    return fig, ax, sc
end

function plot_state_over_time(
    ts, data; make_positive=false, max_dt=nothing, handler=nothing, plot_kwargs...
)
    return error("Not implemented")
end

function plot_error_metric_over_time(
    ts, metrics; max_dt=nothing, handler=nothing, plot_kwargs...
)
    function plot_this_thing(; xlims=(; low=nothing, high=nothing))
        fig = Figure()
        ax = Axis(fig)
        fig[1, 1] = ax
        plot_disjoint_lines!(ax, ts, metrics; plot_kwargs...)

        ax.xlabel = L"\text{time}"
        ax.ylabel = L"\text{metric}"
        ax.ylabelrotation = 0.0
        xlims!(ax; xlims...)

        if !isnothing(handler)
            handler(fig)
        end
        return fig
    end

    fig = plot_this_thing()
    figs = [fig]
    if !isnothing(max_dt) && ts[1] + max_dt < ts[end]
        high = ts[1]
        for low in ts[1]:max_dt:(ts[end] - max_dt)
            high = min(low + max_dt, ts[end])
            fig = plot_this_thing(; xlims=(; low, high))
            push!(figs, fig)
        end
        if high < ts[end]
            high = ts[end]
            low = high - max_dt
            fig = plot_this_thing(; xlims=(; low, high))
            push!(figs, fig)
        end
    end
    return figs
end
