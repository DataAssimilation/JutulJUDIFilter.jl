# Define parameters.

using ConfigurationsJutulDarcy
using ConfigurationsJutulDarcy: @option
using ConfigurationsJutulDarcy: SVector
using JutulDarcy.Jutul
using Ensembles

Darcy, bar, kg, meter, day, yr = si_units(:darcy, :bar, :kilogram, :meter, :day, :year)
injection_well_trajectory = (
    SVector(64.50, 0.5, 25.0),  # First point
    SVector(66.00, 0.5, 35.0),  # Second point
    SVector(71.00, 0.5, 40.0),  # Third point
)

DType = Dict{String,Any}

params_transition = JutulOptions(;
    mesh=MeshOptions(; n=(10, 1, 50), d=(1e1, 1e0, 1e0)),
    system=CO2BrineOptions(; co2_physics=:immiscible, thermal=false),
    porosity=FieldOptions(0.2),
    permeability=FieldOptions(1.0Darcy),
    temperature=FieldOptions(convert_to_si(30.0, :Celsius)),
    rock_density=FieldOptions(30.0),
    rock_heat_capacity=FieldOptions(900.0),
    rock_thermal_conductivity=FieldOptions(3.0),
    fluid_thermal_conductivity=FieldOptions(0.6),
    component_heat_capacity=FieldOptions(4184.0),
    injection=WellOptions(; trajectory=injection_well_trajectory, name=:Injector),
    time=(
        TimeDependentOptions(;
            years=1.0,
            steps=1,
            controls=(
                WellRateOptions(;
                    type="injector",
                    name=:Injector,
                    fluid_density=9e2,
                    rate_mtons_year=1e-2,
                ),
            ),
        ),
        # TimeDependentOptions(; years=475.0, steps=475, controls=[]),
    ),
)

@option struct NoisyObservationOptions
    noise_scale = 2
    timestep_size = 0.1
    num_timesteps = 600
    seed = 0
    only_noisy = false
end

@option struct ModelOptions
    version = "v0.2"
    transition::JutulOptions
    observation::NoisyObservationOptions
end

@option struct JutulJUDIFilterOptions
    version = "v0.3"
    ground_truth::ModelOptions
end

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

params = JutulJUDIFilterOptions(;
    ground_truth=ModelOptions(;
        transition=params_transition, observation=NoisyObservationOptions(; timestep_size=1e-2yr, num_timesteps=5)
    ),
)
