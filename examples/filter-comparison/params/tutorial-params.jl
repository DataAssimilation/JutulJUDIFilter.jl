# Define parameters.

using ConfigurationsJutulDarcy
using ConfigurationsJutulDarcy: @option
using ConfigurationsJutulDarcy: SVector
using JutulDarcy.Jutul

using DrWatson
using FilterComparison

Darcy, bar, kg, meter, day, yr = si_units(:darcy, :bar, :kilogram, :meter, :day, :year)
mD_to_meters2 = 1e-3 * Darcy

injection_well_trajectory = (
    SVector(1875.0, 50.0, 1775.0),  # First point
    SVector(1875.0, 50.0, 1775.0 + 37.5),  # Second point
)

# complex_system = CO2BrineOptions(; co2_physics=:immiscible, thermal=false)

simple_system = CO2BrineSimpleOptions(;
    viscosity_CO2=1e-4,
    viscosity_H2O=1e-3,
    density_CO2=501.9,
    density_H2O=1053.0,
    reference_pressure=1.5e7,
    compressibility_CO2=8e-9,
    compressibility_H2O=3.6563071e-10,
)

params_transition = JutulOptions(;
    mesh=MeshOptions(; n=(75, 1, 75), d=(55, 1e2, 25)),
    # system=complex_system,
    system=simple_system,
    porosity=FieldOptions(0.25),
    # permeability=FieldOptions(0.1Darcy),
    permeability=FieldOptions(;
        suboptions=FieldFileOptions(;
            file="compass_small/75x75.jld2", key="K", scale=mD_to_meters2, resize=true
        ),
    ),
    permeability_v_over_h=0.36,
    temperature=FieldOptions(convert_to_si(30.0, :Celsius)),
    rock_density=FieldOptions(30.0),
    rock_heat_capacity=FieldOptions(900.0),
    rock_thermal_conductivity=FieldOptions(3),
    fluid_thermal_conductivity=FieldOptions(0.6),
    component_heat_capacity=FieldOptions(4184.0),
    injection=WellOptions(; trajectory=injection_well_trajectory, name=:Injector),
    time=(
        TimeDependentOptions(;
            years=5.0,
            controls=(
                WellRateOptions(;
                    type="injector",
                    name=:Injector,
                    fluid_density=501.9,
                    rate_mtons_year=0.8,
                ),
            ),
        ),
        TimeDependentOptions(; years=475.0, controls=()),
    ),
)

# observer_options = NoisyObservationOptions(;
#     noise_scale=1.0,
#     keys=(:Saturation,),
# )

observer_options = SeismicCO2ObserverOptions(;
    seismic=SeismicObserverOptions(;
        velocity=(;
            type=:squared_slowness,
            field=FieldOptions(;
                suboptions=FieldFileOptions(;
                    file="compass_small/75x75.jld2", key="m", scale=1e-6, resize=true
                ),
            ),
        ),
        density=FieldOptions(;
            suboptions=FieldFileOptions(;
                file="compass_small/75x75.jld2", key="rho", scale=1e3, resize=true
            ),
        ),
        background_velocity=BackgroundBlurOptions(; cells=10.0),
        background_density=BackgroundBlurOptions(; cells=10.0),
        mesh=MeshOptions(; n=(75, 75), d=(55, 25)),
        source_receiver_geometry=SourceReceiverGeometryOptions(;
            nsrc=3, nrec=50, setup_type=:surface
        ),
        timeR=1800.0,
        dtR=4.0,
        f0=0.024,
        seed=0xb874e67219a0aba4,
        depth_scaling_exponent=1,
        snr=20.0,
    ),
    rock_physics=RockPhysicsModelOptions(; porosity=FieldOptions(0.25)),
    # save_intermediate=true,
)

ground_truth = ModelOptions(;
    transition=params_transition,
    observation=MultiTimeObserverOptions(;
        observers=(
            0yr => observer_options, 1yr => observer_options, 2yr => observer_options
        ),
    ),
    # max_transition_step = 0.1yr,
)

params = JutulJUDIFilterOptions(;
    ground_truth,
    ensemble=EnsembleOptions(;
        size=4,
        seed=9347215,
        mesh=params_transition.mesh,
        permeability_v_over_h=0.36,
        prior=(;
            Saturation=GaussianPriorOptions(; mean=0, std=0),
            Permeability=FieldOptions(;
                suboptions=FieldFileOptions(;
                    file="compass_small/75x75.jld2",
                    key="Ks",
                    scale=mD_to_meters2,
                    resize=true,
                ),
            ),
        ),
    ),
    estimator=EstimatorOptions(;
        transition=ground_truth.transition,
        observation=ground_truth.observation,
        # algorithm=nothing,
        assimilation_state_keys=(:Saturation,),
        assimilation_obs_keys=(:rtm,),
        algorithm=EnKFOptions(;
            noise=NoiseOptions(; std=3e15, type=:diagonal),
            include_noise_in_obs_covariance=false,
            rho=0,
        ),
        # max_transition_step = 0.1yr,
    ),
)
