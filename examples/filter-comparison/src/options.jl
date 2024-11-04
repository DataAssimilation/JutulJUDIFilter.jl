using Configurations
using ConfigurationsJutulDarcy

using ConfigurationsJutulDarcy: @option
using ConfigurationsJutulDarcy: SVector

@option struct NoisyObservationOptions
    noise_scale = 2
    timestep_size
    num_timesteps = 6
    seed = 0
    only_noisy = false
end

@option struct ModelOptions
    version = "v0.2"
    transition::JutulOptions
    observation::NoisyObservationOptions
end

@option struct GaussianPriorOptions
    mean = 0
    std = 1
end

@option struct EnsembleOptions
    version::String = "v0.1"
    size::Int64
    seed::UInt64
    mesh::MeshOptions
    permeability_v_over_h::Float64
    prior::NamedTuple
end

@option struct EstimatorOptions
    version = "v0.1"
    transition::JutulOptions
    observation::NoisyObservationOptions
    algorithm
end

@option struct NoiseOptions
    std
    type
end

@option struct EnKFOptions
    noise
    rho = 0
    include_noise_in_obs_covariance = false
end

get_short_name(::T) where T = string(T)
get_short_name(::EnKFOptions) = "EnKF"

@option struct JutulJUDIFilterOptions
    version::String = "v0.3"
    ground_truth::ModelOptions
    ensemble::EnsembleOptions
    estimator::EstimatorOptions
end

using Ensembles: Ensembles
function Ensembles.NoisyObserver(op::Ensembles.AbstractOperator; params)
    noise_scale = params.noise_scale
    seed = params.seed
    rng = Random.MersenneTwister(seed)
    if seed == 0
        seed = Random.rand(UInt64)
    end
    Random.seed!(rng, seed)
    state_keys = get_state_keys(op)
    if !params.only_noisy
        state_keys = append!(
            [Symbol(key, :_noisy) for key in get_state_keys(op)], state_keys
        )
    end

    return NoisyObserver(op, state_keys, noise_scale, rng, seed, params.only_noisy)
end
