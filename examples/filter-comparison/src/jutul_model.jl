import Ensembles: AbstractOperator, get_state_keys
using ConfigurationsJutulDarcy
using JutulDarcy: setup_reservoir_model, reservoir_domain, reservoir_model, setup_well, setup_reservoir_state
using JutulDarcy.Jutul: find_enclosing_cells, jutul_output_path



mesh = CartesianMesh(options.mesh)
domain = reservoir_domain(mesh, options)
model, parameters = setup_reservoir_model(mesh, options)
rmodel = reservoir_model(model)
state0 = setup_reservoir_state(model,
    Pressure = 120bar,
    Saturations = [1.0, 0.0]
)
# contacts is the length of the number of phases minus one.
# For each non-reference phase i, contacts[i] is the datum_depth for that phase-pressure table.
contacts = [0.0]
state0 = equilibriate_state(model, contacts; 
    datum_depth = 0.0,
    datum_pressure = JutulDarcy.DEFAULT_MINIMUM_PRESSURE
)
ENV["JUTUL_OUTPUT_PATH"] = "."
jutul_output_path("mycase", subfolder = "ensemble_name")





struct JutulModel <: AbstractOperator
    kwargs
end

function JutulModel(; params)
    kwargs = (;
        σ=Float64(params["transition"]["sigma"]),
        ρ=Float64(params["transition"]["rho"]),
        β=Float64(params["transition"]["beta"]),
        s=Float64(params["transition"]["scaling"]),
        Δt=Float64(params["transition"]["ministep_dt"]),
        N=params["transition"]["ministep_nt"],
    )
    return JutulModel(kwargs)
end
get_state_keys(M::JutulModel) = [:state]

function (M::JutulModel)(member::Dict, args...; kwargs...)
    return Dict{Symbol,Any}(:state => M(member[:state], args...; kwargs...))
end
function (M::JutulModel)(state::AbstractArray, t0, t; kwargs...)
    Δt = t - t0
    if Δt == 0
        return state
    end
    ministeps = ceil(Int, Δt / M.kwargs.Δt)
    mini_Δt = Δt / ministeps
    states = L63(; M.kwargs..., kwargs..., Δt=mini_Δt, N=ministeps, xyz=state)
    return states[:, end]
end
