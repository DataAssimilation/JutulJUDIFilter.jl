function show_interactive(fig)
    if Base.is_interactive
        display(fig)
    else
        fig
    end
end

function get_ground_truth_iterator(ensembles_ts, observation_times)
    gt_index = 1
    gt_indices = Int64[]
    post_assim_indices = Int64[]
    for (i, t) in enumerate(ensembles_ts)
        while gt_index <= length(observation_times) && observation_times[gt_index] < t
            gt_index += 1
        end
        if gt_index > length(observation_times)
            error(
                "Comparing at time $(t) is impossible because final ground-truth observation is at time $(observation_times[end])",
            )
        end
        if observation_times[gt_index] != t
            error(
                "No observation at time $(t). Closest are $(observation_times[gt_index-1]) and $(observation_times[gt_index])",
            )
        end
        push!(gt_indices, gt_index)
        if i == length(ensembles_ts) || t < ensembles_ts[i + 1]
            push!(post_assim_indices, i)
        end
    end
    return gt_indices, post_assim_indices
end
