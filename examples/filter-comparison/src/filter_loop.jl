
using Random: Random
using ProgressLogging: @progress
using Ensembles: assimilate_data, split_clean_noisy

function filter_loop(
    ensemble,
    t0,
    estimator,
    transitioner,
    observer,
    observations_gt,
    observation_times;
    name="Time",
)
    logs = []
    ensembles = []
    name_orig = name
    progress_name = name * ": "
    @time begin
        push!(ensembles, (; ensemble=deepcopy(ensemble), t=t0))
        @progress name = progress_name for (t, y_obs) in
                                           zip(observation_times, observations_gt)
            ## Advance ensemble to time t.
            if t0 != t
                ensemble = transitioner(ensemble, t0, t; inplace=false)
                t0 = t

                for member in get_ensemble_members(ensemble)
                    a = mean(member[:Saturation])
                    println("time $t, mean_sat: $(a)")
                end
            end

            # y_obs1 = y_obs
            # ensemble1 = ensemble

            if !isnothing(estimator)
                ## Take observation at time t.
                ensemble_obs = observer(ensemble)
                ensemble_obs_clean, ensemble_obs_noisy = split_clean_noisy(
                    observer, ensemble_obs
                )

                ## Record.
                push!(
                    ensembles, (; ensemble=deepcopy(ensemble), ensemble_obs_clean, ensemble_obs_noisy, t)
                )

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
            end
            push!(ensembles, (; ensemble=deepcopy(ensemble), t))
        end
    end
    println("  ^ timing for running filter loop ($name_orig)")

    data = Dict("ensembles" => ensembles, "logs" => logs, "ensemble" => ensembles[end])
    return data
end
