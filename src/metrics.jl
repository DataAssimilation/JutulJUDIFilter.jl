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
