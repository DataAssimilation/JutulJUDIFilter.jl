
using Configurations: @option

function get_observer(options::NoisyObservationOptions)
    NoisyObserver(collect(options.keys); params=options)
end

struct MultiTimeObserver{T}
    times_observers::Vector{Pair{T, Any}}
    times::Vector{T}
    observers::Vector
    unique_times::Vector{T}
end

function MultiTimeObserver(times_observers::Vector{Pair{Float64, Any}})
    sort!(times_observers; by = to->to.first)
    times = [to.first for to in times_observers]
    observers = [to.second for to in times_observers]
    unique_times = unique(times)
    MultiTimeObserver(times_observers, times, observers, unique_times)
end

function get_multi_time_observer(options::MultiTimeObserverOptions)
    MultiTimeObserver(collect(options.observers))
end
