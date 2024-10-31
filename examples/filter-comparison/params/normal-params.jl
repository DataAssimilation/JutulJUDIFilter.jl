# Define parameters.

using ConfigurationsJutulDarcy
using ConfigurationsJutulDarcy: @option
using ConfigurationsJutulDarcy: SVector
using JutulDarcy.Jutul

Darcy, bar, kg, meter, day, yr = si_units(:darcy, :bar, :kilogram, :meter, :day, :year)
mD_to_meters2 = 1e-3 * Darcy

injection_well_trajectory = (
    SVector(1875.0, 50.0, 1775.0),  # First point
    SVector(1875.0, 50.0, 1775.0+37.5),  # Second point
)

DType = Dict{String, Any}

complex_system = CO2BrineOptions(; co2_physics=:immiscible, thermal=false)

simple_system = CO2BrineSimpleOptions(;
    viscosity_CO2 = 1e-4,
    viscosity_H2O = 1e-3,
    density_CO2 = 501.9,
    density_H2O = 1053.0,
    reference_pressure = 1.5e7,
    compressibility_CO2 = 8e-9,
    compressibility_H2O = 3.6563071e-10,
)

params_transition = JutulOptions(;
    mesh=MeshOptions(; n=(325, 1, 341), d=(12.5, 1e2, 6.25)),
    system=simple_system,
    porosity=FieldOptions(0.25),
    permeability=FieldOptions(; suboptions=FieldFileOptions(; file="compass/broad&narrow_perm_models_new.jld2", key="K", scale=mD_to_meters2, resize=true)),
    permeability_v_over_h=0.36,
    temperature=FieldOptions(convert_to_si(30.0, :Celsius)),
    rock_density=FieldOptions(30.0),
    rock_heat_capacity=FieldOptions(900.0),
    rock_thermal_conductivity=FieldOptions(3.00000001),
    fluid_thermal_conductivity=FieldOptions(0.6),
    component_heat_capacity=FieldOptions(4184.0),
    injection=WellOptions(; trajectory=injection_well_trajectory, name=:Injector),
    time=(
        TimeDependentOptions(;
            years=1.0,
            steps=5,
            controls=(
                WellRateOptions(;
                    type="injector",
                    name=:Injector,
                    fluid_density=501.9,
                    rate_mtons_year=0.8,
                ),
            ),
        ),
        # TimeDependentOptions(; years=475.0, steps=475, controls=[]),
    ),
)


@option struct NoisyObservationOptions
    noise_scale = 2
    timestep_size = 1yr
    num_timesteps = 6
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
    ground_truth = ModelOptions(;
        transition = params_transition,
        observation = NoisyObservationOptions(
            num_timesteps = 5,
        )
    )
)
