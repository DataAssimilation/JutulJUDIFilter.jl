
if isinteractive()
    using Pkg: Pkg
    try
        using Revise
    catch
        Pkg.add("Revise")
        using Revise
    end
end

if get(ENV, "jutuljudifilter_force_install", "false") == "true" ||
    basename(dirname(Base.active_project())) != "filter-comparison"
    using Pkg: Pkg

    if basename(dirname(Base.active_project())) != "filter-comparison"
        Pkg.activate(joinpath(@__DIR__, ".."))
    end
    @assert basename(dirname(Base.active_project())) == "filter-comparison"

    try
        using JutulJUDIFilter: JutulJUDIFilter
    catch
        path = get(ENV, "jutuljudifilter_path", joinpath(@__DIR__, "..", "..", ".."))
        Pkg.develop(; path)
        using JutulJUDIFilter: JutulJUDIFilter
    end

    try
        using Ensembles: Ensembles
    catch
        JutulJUDIFilter.install(:Ensembles)
        using Ensembles: Ensembles
    end

    try
        import ConfigurationsJutulDarcy: ConfigurationsJutulDarcy
    catch
        JutulJUDIFilter.install(:ConfigurationsJutulDarcy)
    end

    try
        using EnsembleKalmanFilters: EnsembleKalmanFilters
    catch
        Ensembles.install(:EnsembleKalmanFilters)
    end

    # try
    #     using NormalizingFlowFilters: NormalizingFlowFilters
    # catch
    #     Ensembles.install(:NormalizingFlowFilters)
    # end

    Pkg.instantiate()
end

using DrWatson: projectdir
if !(projectdir("lib") in LOAD_PATH)
    push!(LOAD_PATH, projectdir("lib"))
end
