using Statistics: mean, var

export rmse
function rmse(ensemble, y_true)
    return sqrt(mean((ensemble .- y_true) .^ 2))
end

export compute_errors
function compute_errors(gt_indices, ensembles_means_vec, ground_truth_states_vec)
    rmses = Vector{Float64}(undef, length(gt_indices))
    for (i, gt_index) in enumerate(gt_indices)
        rmses[i] = rmse(ensembles_means_vec[:, i], ground_truth_states_vec[:, gt_index])
    end
    return rmses
end

export compute_metrics
function compute_metrics(ensembles; ts_gt=nothing, ground_truth_states_vec=nothing)
    state_keys = ensembles[1].ensemble.state_keys
    means_vec = get_ensemble_matrix(state_keys, mean(e.ensemble) for e in ensembles)
    vars_vec = get_ensemble_matrix(state_keys, var(e.ensemble) for e in ensembles)
    ts = [e.t for e in ensembles]

    if isnothing(ts_gt)
        return (; ts, vars_vec, means_vec)
    end
    gt_indices, post_assim_indices = get_ground_truth_iterator(ts, ts_gt)
    rmses = compute_errors(gt_indices, means_vec, ground_truth_states_vec)

    spread = sqrt.(mean(vars_vec; dims=1)[1, :])
    return (;
        ts,
        vars_vec,
        means_vec,
        gt_indices,
        post_assim_indices,
        rmses,
        spread,
        post_assim_rmses=(rmses[i] for i in post_assim_indices),
        post_assim_spread=(spread[i] for i in post_assim_indices),
    )
end
