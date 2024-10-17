
if get(ENV, "jutuljudifilter_force_install", "false") == "true" ||
    basename(dirname(Base.active_project())) in ["v1.10", "v1.9", "v1.8", "v1.7", "v1.6"]
    using Pkg: Pkg

    Pkg.activate(joinpath(@__DIR__, ".."))
    @assert basename(dirname(Base.active_project())) == "filter-comparison"

    try
        using JutulJUDIFilter: JutulJUDIFilter
    catch
        path = get(ENV, "jutuljudifilter_path", joinpath(@__DIR__, "..", "..", ".."))
        Pkg.develop(; path)
    end

    try
        using Ensembles: Ensembles
    catch
        JutulJUDIFilter.install(:Ensembles)
    end

    try
        import ConfigurationsJutulDarcy: ConfigurationsJutulDarcy
    catch
        JutulJUDIFilter.install(:ConfigurationsJutulDarcy)
    end

    try
        import ConfigurationsJUDI: ConfigurationsJUDI
    catch
        JutulJUDIFilter.install(:ConfigurationsJUDI)
    end

    try
        using EnsembleKalmanFilters: EnsembleKalmanFilters
    catch
        Ensembles.install(:EnsembleKalmanFilters)
    end

    try
        using NormalizingFlowFilters: NormalizingFlowFilters
    catch
        Ensembles.install(:NormalizingFlowFilters)
    end

    Pkg.add([
        "DrWatson",
        "LinearAlgebra",
        "Random",
        "CairoMakie",
        "Statistics",
        "ImageFiltering",
        "JLD2",
        "Format",
        "Configurations",
        "TerminalLoggers",
        "ProgressLogging",
        "Logging",
        "Markdown",
        "Distributed",
    ])

    Pkg.instantiate()
end
