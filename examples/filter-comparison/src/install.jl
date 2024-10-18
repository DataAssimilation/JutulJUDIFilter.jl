
if get(ENV, "jutuljudifilter_force_install", "false") == "true" ||
    basename(dirname(Base.active_project())) in ["v1.11", "v1.10"]
    using Pkg: Pkg

    Pkg.activate(joinpath(@__DIR__, ".."))
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
        "JutulDarcy",
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
