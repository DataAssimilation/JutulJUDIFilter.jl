
using Random: Random
using ProgressLogging: @progress
using Ensembles: assimilate_data, split_clean_noisy

function filter_loop(
    ensemble,
    t0,
    estimator,
    transitioner,
    observers,
    observations_gt;
    name="Time",
)
    logs = []
    ensembles = []
    name_orig = name
    progress_name = name * ": "
    @time begin
        push!(ensembles, (; ensemble=deepcopy(ensemble), t=t0))
        @progress name = progress_name for ((t, observer_options), y_obs) in
                                           zip(observers.times_observers, observations_gt)
            ## Advance ensemble to time t.
            if t0 != t
                ensemble = transitioner(ensemble, t0, t; inplace=true)
                t0 = t
            end

            Random.seed!(0xabceabd47cada8f4 ⊻ hash(t))
            observer = get_observer(observer_options)
            xor_seed!(observer, UInt64(0xabc2fe2e546a031c) ⊻ hash(t))

            ## Take observation at time t.
            ensemble_obs = observer(ensemble)
            ensemble_obs_clean, ensemble_obs_noisy = split_clean_noisy(
                observer, ensemble_obs
            )

            ## Record.
            push!(
                ensembles, (; ensemble=deepcopy(ensemble), ensemble_obs_clean, ensemble_obs_noisy, t)
            )

            if !isnothing(estimator)

                ## Assimilate observation
                log_data = Dict{Symbol,Any}()
                (ensemble, timing...) = @timed assimilate_data(
                    estimator,
                    ensemble,
                    ensemble_obs_clean,
                    ensemble_obs_noisy,
                    y_obs,
                    log_data,
                )
                log_data[:timing] = timing

                ## Record.
                push!(logs, log_data)
                push!(ensembles, (; ensemble=deepcopy(ensemble), t))
            end
        end
    end
    println("  ^ timing for running filter loop ($name_orig)")

    data = Dict("ensembles" => ensembles, "logs" => logs, "ensemble" => ensembles[end])
    return data
end
