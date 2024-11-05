include("options.jl")

function get_observer(options::NoisyObservationOptions)
    NoisyObserver(options.observation.keys; params=options.observation)
end


# struct TimeVaryingObserver
#     observers
# end
