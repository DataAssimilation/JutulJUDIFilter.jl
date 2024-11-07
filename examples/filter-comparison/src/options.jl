using Configurations
using ConfigurationsJutulDarcy

using ConfigurationsJutulDarcy: @option
using ConfigurationsJutulDarcy: SVector

@option struct NoisyObservationOptions
    noise_scale = 2
    seed = 0
    only_noisy = false
    keys::Tuple{Vararg{Symbol}}
end

@option struct MultiTimeObserverOptions
    observers::Tuple{Vararg{Pair{Float64,Any}}}
end

@option struct SeismicObserverOptions
    velocity
    density
    mesh::MeshOptions
    type = :born_shot_rtm_depth_noise
    background_velocity
    background_density

    nbl = 80 # number of absorbing layers

    timeR = 1800.0  # recording time (ms)
    dtR = 4.0 # recording time sampling rate (ms)
    f0 = 0.024 # source frequency (kHz)

    source_receiver_geometry
    depth_scaling_exponent = 1
    snr = 8.0
    seed::UInt64
end

@option struct SourceReceiverGeometryOptions
    nsrc # num of sources
    nrec # num of receivers
    setup_type
end

@option struct SeismicCO2ObserverOptions
    seismic = SeismicObserverOptions()
    rock_physics = RockPhysicsModelOptions()
end

@option struct RockPhysicsModelOptions
    density_CO2 = 501.9 # kg/m^3
    density_H2O = 1053.0 # kg/m^3 Reference: https://github.com/lidongzh/FwiFlow.jl
    bulk_min = 36.6e9  # Bulk modulus of dry rock.
    bulk_H2O = 2.735e9 # Bulk modulus of water. Reference: https://github.com/lidongzh/FwiFlow.jl
    bulk_CO2 = 0.125e9 # Bulk modulus of carbon dioxide. Reference: https://github.com/lidongzh/FwiFlow.jl
    porosity
end

@option struct BackgroundBlurOptions
    cells
end

@option struct WellObserverOptions
    TODO = true
end

@option struct GaussianPriorOptions
    mean = 0
    std = 1
end

@option struct EstimatorOptions
    version = "v0.1"
    transition::JutulOptions
    observation::MultiTimeObserverOptions
    algorithm
    assimilation_keys::Tuple{Vararg{Symbol}}
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

get_short_name(::T) where {T} = string(T)
get_short_name(::EnKFOptions) = "EnKF"

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

@option struct ModelOptions
    version = "v0.2"
    transition::JutulOptions
    observation::MultiTimeObserverOptions
    max_transition_step::Union{Nothing, Float64} = nothing
end

@option struct EnsembleOptions
    version::String = "v0.1"
    size::Int64
    seed::UInt64
    mesh::MeshOptions
    permeability_v_over_h::Float64
    prior::NamedTuple
end

@option struct JutulJUDIFilterOptions
    version::String = "v0.3"
    ground_truth::ModelOptions
    ensemble::EnsembleOptions
    estimator::EstimatorOptions
end
