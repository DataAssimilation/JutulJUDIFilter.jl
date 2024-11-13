
using Configurations: @option
using Ensembles: Ensembles, AbstractOperator
using DrWatson: projectdir

export get_observer
function get_observer(options::NoisyObservationOptions)
    return NoisyObserverConfigurations(collect(options.keys); params=options)
end

function get_observer(options::Nothing)
    return NothingObserver()
end

export MultiTimeObserver
struct MultiTimeObserver{T}
    times_observers::Vector{Pair{T,Any}}
    times::Vector{T}
    observers::Vector
    unique_times::Vector{T}
end

function MultiTimeObserver(times_observers::Vector{Pair{Float64,Any}})
    sort!(times_observers; by=to -> to.first)
    times = [to.first for to in times_observers]
    observers = [to.second for to in times_observers]
    unique_times = unique(times)
    return MultiTimeObserver(times_observers, times, observers, unique_times)
end

export get_multi_time_observer
function get_multi_time_observer(options::MultiTimeObserverOptions)
    return MultiTimeObserver(collect(options.observers))
end

struct NothingObserver <: AbstractOperator
end

Ensembles.xor_seed!(::NothingObserver, seed_mod::UInt) = nothing
(M::NothingObserver)(member::Dict{Symbol,Any}) = Dict{Symbol, Any}()
Ensembles.split_clean_noisy(::NothingObserver, obs::Dict{Symbol,<:Any}) = (Dict{Symbol, Any}(),  Dict{Symbol, Any}())
