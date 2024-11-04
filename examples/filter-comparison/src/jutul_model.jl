import Ensembles: AbstractOperator, get_state_keys
using ConfigurationsJutulDarcy
using JutulDarcy:
    setup_reservoir_model,
    reservoir_domain,
    reservoir_model,
    setup_well,
    setup_reservoir_state,
    flow_boundary_condition,
    setup_reservoir_forces,
    simulate_reservoir
using JutulDarcy.Jutul: find_enclosing_cells, jutul_output_path

JutulDarcyExt = Base.get_extension(ConfigurationsJutulDarcy, :JutulDarcyExt)
using .JutulDarcyExt: create_field

struct JutulModelTranslator{K} end
JutulModelTranslator(K) = JutulModelTranslator(typeof(K))

JutulModelTranslatorDomainKeys = (Val{:Permeability},)
function modifies_domain(T::JutulModelTranslator{K}) where {K<:Tuple}
    return any(k in fieldtypes(K) for k in JutulModelTranslatorDomainKeys)
end

function JutulModelTranslator(K::Type)
    if !(K <: Tuple)
        error("K must be a tuple")
    end
    for k in fieldtypes(K)
        if !(k <: Val)
            error("expected Val but got $k")
        end
        if length(k.parameters) != 1 || !(k.parameters[1] isa Symbol)
            error("expected Symbol but got $(k.parameters)")
        end
    end
    return JutulModelTranslator{K}()
end


function sim_to_member(::Val{:OverallMoleFraction}, state, domain_params)
    return state[:Reservoir][:OverallMoleFractions][2, :]
end
function sim_to_member(::Val{:Saturation}, state, domain_params)
    return state[:Reservoir][:Saturations][2, :]
end
sim_to_member(::Val{:Pressure}, state, domain_params) = state[:Reservoir][:Pressure]

sim_to_member(::Val{:Permeability}, state, domain_params) = domain_params[:permeability]

function sim_to_member!(
    T::JutulModelTranslator{K}, member, state, domain_params
) where {K<:Tuple}
    for k in fieldtypes(K)
        d = sim_to_member(k(), state, domain_params)
        if haskey(member, k)
            member[k.parameters[1]][:] .= d[:]
        else
            member[k.parameters[1]] = deepcopy(d)
        end
    end
    return member
end

function sim_to_member!(T::JutulModelTranslator{K}, member, state) where {K<:Tuple}
    for k in fieldtypes(K)
        if k in JutulModelTranslatorDomainKeys
            continue
        end
        d = sim_to_member(k(), state, nothing)
        if haskey(member, k)
            member[k.parameters[1]][:] .= d[:]
        else
            member[k.parameters[1]] = deepcopy(d)
        end
    end
    return member
end


function member_to_sim!(M, ::Val{:OverallMoleFraction}, member, state, domain_params)
    state[:Reservoir][:OverallMoleFractions][2, :] .= reshape(member[:OverallMoleFraction], :)
    return state[:Reservoir][:OverallMoleFractions][1, :] .= 1 .- reshape(member[:OverallMoleFraction], :)
end

function member_to_sim!(M, ::Val{:Saturation}, member, state, domain_params)
    state[:Reservoir][:Saturations][2, :] .= reshape(member[:Saturation], :)
    return state[:Reservoir][:Saturations][1, :] .= 1 .- reshape(member[:Saturation], :)
end

function member_to_sim!(M, ::Val{:Pressure}, member, state, domain_params)
    return state[:Reservoir][:Pressure][:] .= reshape(member[:Pressure], :)
end

function member_to_sim!(M, ::Val{:Permeability}, member, state, domain_params)
    perm = member[:Permeability]
    if length(perm) < length(domain_params[:permeability])
        perm = Kto3(member[:Permeability]; kvoverkh=M.options.permeability_v_over_h)
    end
    return domain_params[:permeability][:] .= reshape(perm, :)
end

function member_to_sim!(M, 
    T::JutulModelTranslator{K}, member, state, domain_params
) where {K<:Tuple}
    for k in fieldtypes(K)
        member_to_sim!(M, k(), member, state, domain_params)
    end
end

function member_to_sim!(M, T::JutulModelTranslator{K}, member, state) where {K<:Tuple}
    for k in fieldtypes(K)
        if k in JutulModelTranslatorDomainKeys
            continue
        end
        member_to_sim!(M, k(), member, state, nothing)
    end
end

# macro build_state_setter(member_keys)
#     esc(quote
#         function (state, domain_params)
#             for k in $member_keys
#                 set_sim_state!(Val(k), member, state, domain_params)
#             end
#         end
#     end)
# end

# get_state_keys(M::JutulModel) = [:state]

# function (M::JutulModel)(member::Dict, args...; kwargs...)
#     return Dict{Symbol,Any}(:state => M(member[:state], args...; kwargs...))
# end
# function (M::JutulModel)(state::AbstractArray, t0, t; kwargs...)
#     Δt = t - t0
#     if Δt == 0
#         return state
#     end
#     ministeps = ceil(Int, Δt / M.kwargs.Δt)
#     mini_Δt = Δt / ministeps
#     states = L63(; M.kwargs..., kwargs..., Δt=mini_Δt, N=ministeps, xyz=state)
#     return states[:, end]
# end

mutable struct JutulModel6{K} <: AbstractOperator
    translator::JutulModelTranslator{K}
    options
    kwargs
    state0
    mesh
    domain
    wells
    bc
    dt
    forces
    model
    parameters
end
JutulModel = JutulModel6

function JutulDarcy.setup_reservoir_state(model, options::CO2BrineSimpleOptions; kwargs...)
    return state0 = setup_reservoir_state(model; kwargs...)
end

function JutulModel6(; options, translator, kwargs=(;))
    mesh = CartesianMesh(options.mesh)
    domain = reservoir_domain(mesh, options)
    wells = setup_well(domain, options.injection)
    if get_label(options.system) == :co2brine
        model = setup_reservoir_model(domain, options.system; wells, extra_out=false)
        parameters = setup_parameters(model)
    else
        model, parameters = setup_reservoir_model(
            domain, options.system; wells, extra_out=true
        )
    end

    nc = number_of_cells(mesh)
    depth = domain[:cell_centroids][3, :]
    g = Jutul.gravity_constant
    p0 = 200bar .+ depth .* g .* 1000.0
    # p0 = ρH2O * g * (Z .+ M.h) # rho * g * h

    state0 = setup_reservoir_state(
        model, options.system; Pressure=p0, Saturations=[1.0, 0.0]
    )
    # # contacts is the length of the number of phases minus one.
    # # For each non-reference phase i, contacts[i] is the datum_depth for that phase-pressure table.
    # contacts = [0.0]
    # state0 = equilibriate_state(model, contacts; 
    #     datum_depth = 0.0,
    #     datum_pressure = JutulDarcy.DEFAULT_MINIMUM_PRESSURE
    # )

    boundary = Int[]
    for cell in 1:number_of_cells(mesh)
        I, J, K = cell_ijk(mesh, cell)
        if I == 1 || I == options.mesh.n[1]
            push!(boundary, cell)
        end
    end
    temperatures = create_field(mesh, options.temperature)
    if isa(temperatures, Array)
        temperatures = temperatures[boundary]
    end
    bc = flow_boundary_condition(
        boundary, domain, p0[boundary], temperatures; fractional_flow=[1.0, 0.0]
    )
    dt, forces = setup_reservoir_forces(model, options.time; bc)
    dt = dt[1:1]
    forces = forces[1:1]

    # Create a new translator from the primary vars.
    K = []
    for model_key in keys(model.models)
        vars = Jutul.get_primary_variables(model.models[model_key])
        for var_key in keys(vars)
            if model_key == :Reservoir
                if string(var_key)[end] == 's'
                    push!(K, Symbol(string(var_key)[1:end-1]))
                else
                    push!(K, var_key)
                end
            else
                push!(K, Symbol(model_key, :_, var_key))
            end
            k = K[end]
            if length(methods(member_to_sim!, (Any, Val{k}, Any, Any, Any))) == 0
                println(quote
                    function member_to_sim!(M, ::Val{$(Meta.quot(k))}, member, state, domain_params)
                        state[$(Meta.quot(model_key))][$(Meta.quot(var_key))] .= member[$(Meta.quot(k))]
                    end
                end)
            end
            if length(methods(sim_to_member, (Val{k}, Any, Any))) == 0
                println(quote
                    function sim_to_member(::Val{$(Meta.quot(k))}, state, domain_params)
                        state[$(Meta.quot(model_key))][$(Meta.quot(var_key))]
                    end
                end)
            end
        end
    end
    K = vcat(Val.(K), collect(p() for p in typeof(translator).parameters[1].parameters))
    unique!(K)
    translator = JutulModelTranslator(tuple(K...))

    return JutulModel(
        translator,
        options,
        kwargs,
        state0,
        mesh,
        domain,
        wells,
        bc,
        dt,
        forces,
        model,
        parameters,
    )
end


# function (M::JutulModel)(member::Dict)
#     state0 = get_state0(member)
#     model = get_model(M, member)
#     parameters = get_parameters(M, member)
#     forces = setup_forces(M)
#     result = simulate_reservoir(
#         state0, model, dt; parameters, forces, M.kwargs...
#     )
#     member_new = process_result(member, result)
#     return member_new
# end

# function (M::JutulModel)()
#     state0 = M.state0
#     model = M.model
#     parameters = M.parameters
#     forces = M.forces
#     result = simulate_reservoir(
#         state0, model, M.dt; parameters, forces, M.kwargs...
#     )
#     full_final_state = result.result.states[end]
#     full_parameters = copy(M.domain.data)
#     modified_param_keys = [:permeability]
#     full_parameters = Dict(k => M.domain[k] for k in modified_param_keys)
#     return Dict(:state=>full_final_state, :parameters=>full_parameters)
# end

# function (M::JutulModel{K})(member::Dict) where K
#     state0 = M.state0
#     parameters = M.parameters
#     model = M.model
#     forces = M.forces

#     member_to_sim!(M, JMT, member, M.state0, M.domain)
#     if modifies_domain(JMT)
#         parameters = setup_parameters(model)
#     end
#     result = simulate_reservoir(
#         state0, model, M.dt; parameters, forces, M.kwargs...
#     )
#     final_state = result.result.states[end]
#     sim_to_member!(JMT, member, final_state)
#     return member
# end

function (M::JutulModel{K})(member::Dict, t0::Float64, t::Float64) where {K}
    state0 = M.state0
    parameters = M.parameters
    model = M.model

    # TODO: forces should change based on time.
    forces = M.forces
    dt = Float64[t - t0]

    member_to_sim!(M, M.translator, member, M.state0, M.domain)
    if modifies_domain(M.translator)
        println("MODIFIED domain")
        parameters = setup_parameters(model)
    end
    result = simulate_reservoir(state0, model, dt; parameters, forces, M.kwargs...)
    final_state = result.result.states[end]
    sim_to_member!(M.translator, member, final_state)
    return member
end

function member_to_sim!(M, ::Val{:Injector_Pressure}, member, state, domain_params)
    (state[:Injector])[:Pressure] .= member[:Injector_Pressure]
end

function sim_to_member(::Val{:Injector_Pressure}, state, domain_params)
    (state[:Injector])[:Pressure]
end

function member_to_sim!(M, ::Val{:Injector_Saturations}, member, state, domain_params)
    (state[:Injector])[:Saturations] .= member[:Injector_Saturations]
end

function sim_to_member(::Val{:Injector_Saturations}, state, domain_params)
    (state[:Injector])[:Saturations]
end

function member_to_sim!(M, ::Val{:Facility_TotalSurfaceMassRate}, member, state, domain_params)
    (state[:Facility])[:TotalSurfaceMassRate] .= member[:Facility_TotalSurfaceMassRate]
end

function sim_to_member(::Val{:Facility_TotalSurfaceMassRate}, state, domain_params)
    (state[:Facility])[:TotalSurfaceMassRate]
end


function initialize_member!(M::JutulModel, member)
    state = deepcopy(M.state0)
    for k in keys(member)
        # if Val{k} in JutulModelTranslatorDomainKeys
        #     continue
        # end
        member_to_sim!(M, Val(k), member, state, M.domain)
    end
    sim_to_member!(M.translator, member, state, M.domain)
end
