# Define parameters.

using ConfigurationsJutulDarcy
using JutulDarcy.Jutul

Darcy, bar, kg, meter, day, yr = si_units(:darcy, :bar, :kilogram, :meter, :day, :year)
injection_well_trajectory = [
    645.0 0.5 25.0  # First point
    660.0 0.5 35.0  # Second point
    710.0 0.5 40.0  # Third point
]

options = JutulOptions(;
    mesh=MeshOptions(; n=(100, 1, 50), d=(1e1, 1e0, 1e0)),
    system=CO2BrineOptions(; co2_physics=:immiscible, thermal=false),
    porosity=FieldOptions(; value=0.2),
    permeability=FieldOptions(; value=1.0Darcy),
    temperature=FieldOptions(; value=convert_to_si(30.0, :Celsius)),
    rock_density=FieldOptions(; value=30.0),
    rock_heat_capacity=FieldOptions(; value=900.0),
    rock_thermal_conductivity=FieldOptions(; value=3.0),
    fluid_thermal_conductivity=FieldOptions(; value=0.6),
    component_heat_capacity=FieldOptions(; value=4184.0),
    injection=WellOptions(; trajectory=injection_well_trajectory, name=:Injector),
    time=[
        TimeDependentOptions(;
            years=25.0,
            steps=25,
            controls=[
                WellRateOptions(;
                    type="injector",
                    name=:Injector,
                    fluid_density=9e2,
                    rate_mtons_year=2.05e-5,
                ),
            ],
        ),
        TimeDependentOptions(; years=475.0, steps=475, controls=[]),
    ],
)

params_transition = DType(
    "sigma" => 10,
    "rho" => 28,
    "beta" => 8 / 3,
    "scaling" => 1,
    "ministep_nt" => missing,
    "ministep_dt" => 0.05,
)

params_exec = DType(
    "workers" => 0,
    "transitioner_distributed_type" => :none,
    "observer_distributed_type" => :none,
)

params = DType(
    "format" => "v0.2",
    "ground_truth" => DType(
        "format" => "v0.1",
        "transition" => params_transition,
        "observation" =>
            DType("noise_scale" => 2, "timestep_size" => 0.1, "num_timesteps" => 600),
    ),
    "ensemble" => DType(
        "size" => 100,
        "seed" => 9347215,
        "prior" => "gaussian",
        "prior_params" => [0.0, 1.0],
        "spinup" => DType(
            "transition" => params_transition,
            "exec" => params_exec,
            "assimilation_type" => "sequential",
            "num_timesteps" => 200,
            "transition_noise_scale" => 1.0,

            ## EnKF params
            "algorithm" => "enkf",
            "include_noise_in_y_covariance" => true,
            "multiplicative_prior_inflation" => 0.0,
            "observation_noise_stddev" => 2.0,
            "observation_noise_type" => "diagonal",
        ),
    ),
    "estimator" => DType(
        "assimilation_type" => "monolithic",
        "num_timesteps" => 400,
        "transition_noise_scale" => 0.0,
        "exec" => params_exec,

        ## EnKF params
        "algorithm" => "enkf",
        "include_noise_in_y_covariance" => true,
        "multiplicative_prior_inflation" => 0.1,
        "observation_noise_stddev" => 2.0,
        "observation_noise_type" => "diagonal",

        # ## NF params
        # "algorithm" => "nf",
        # "glow" => DType(
        #     "L" => 3,
        #     "K" => 9,
        #     "n_hidden" => 8,
        #     "split_scales" => false,
        # ),
        # "training" => DType(
        #     "n_epochs" => 32,
        #     "batch_size" => 50,
        #     "noise_lev_x" => 0.005f0,
        #     "noise_lev_y" => 0.0f0,
        #     "num_post_samples" => 50,
        #     "validation_perc" => 0.5,
        #     "n_condmean" => 0,
        # ),
        # "optimizer" => DType(
        #     "lr" => 1.0f-3,
        #     "clipnorm_val" => 3.0f0,
        # ),
    ),
);
