# Define parameters.

using ConfigurationsJutulDarcy
using ConfigurationsJutulDarcy: @option
using ConfigurationsJutulDarcy: SVector
using JutulDarcy.Jutul
using Ensembles

using DrWatson: srcdir
include(srcdir("options.jl"))

Darcy, bar, kg, meter, day, yr = si_units(:darcy, :bar, :kilogram, :meter, :day, :year)
injection_well_trajectory = (
    SVector(64.50, 0.5, 25.0),  # First point
    SVector(66.00, 0.5, 35.0),  # Second point
    SVector(71.00, 0.5, 40.0),  # Third point
)

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
                    type="injector", name=:Injector, fluid_density=9e2, rate_mtons_year=1e-2
                ),
            ),
        ),
        # TimeDependentOptions(; years=475.0, steps=475, controls=[]),
    ),
)

ground_truth = ModelOptions(;
    transition=params_transition,
    observation=NoisyObservationOptions(; timestep_size=1e-2yr, num_timesteps=5),
)

params = JutulJUDIFilterOptions(;
    ground_truth,
    ensemble=EnsembleOptions(;
        size=10,
        seed=9347215,
        mesh=params_transition.mesh,
        permeability_v_over_h=0.36,
        prior=(; Saturation=GaussianPriorOptions(; mean=0, std=0),),
    ),
    estimator=EstimatorOptions(;
        transition=ground_truth.transition,
        observation=ground_truth.observation,
        algorithm=EnKFOptions(;
            noise=NoiseOptions(; std=1, type=:diagonal),
            include_noise_in_obs_covariance=false,
            rho=0,
        ),
    ),
)
