using LinearAlgebra: Diagonal
using EnsembleKalmanFilters: EnKF
using NormalizingFlowFilters:
    cpu,
    ConditionalGlowOptions,
    NetworkConditionalGlow,
    OptimizerOptions,
    create_optimizer,
    TrainingOptions,
    NormalizingFlowFilter
using Configurations: from_dict

function Ensembles.assimilate_data(
    filter::NormalizingFlowFilter,
    ensemble,
    ensemble_obs_clean,
    ensemble_obs_noisy,
    y_obs,
    log_data,
)
    X_matrix = NormalizingFlowFilters.assimilate_data(
        filter,
        Float64.(get_ensemble_matrix(ensemble)),
        Float64.(get_ensemble_matrix(ensemble_obs_noisy)),
        get_member_vector(ensemble_obs_clean, y_obs),
        log_data,
    )
    members = get_ensemble_dicts(ensemble, X_matrix)
    posterior = Ensemble(members, ensemble.state_keys)
    return posterior
end

function get_noise_covariance(params::NoiseOptions, n)
    type = params.type
    if type == :diagonal
        R = Diagonal(fill(Float64(params.std)^2, n))
        return R
    end
    throw(ArgumentError("Unknown noise type: $type"))
end

function get_estimator(params_estimator::EnKFOptions, n)
    R = get_noise_covariance(params_estimator.noise, n)
    estimator = EnKF(
        R,
        params_estimator.include_noise_in_obs_covariance,
        params_estimator.rho,
    )
    return estimator
end

get_estimator(params_estimator::Nothing, n) = nothing
