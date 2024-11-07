
macro codegen_copy_constructor(T)
    esc(
        quote
            function $T(x::$T; kwargs...)
                default_kwargs = (f => getfield(x, f) for f in fieldnames($T))
                return $T(; default_kwargs..., kwargs...)
            end
        end,
    )
end

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
        "CairoMakie",
        "ChainRulesCore",
        "Configurations",
        "Distributed",
        "DrWatson",
        "Format",
        "ImageFiltering",
        "JLD2",
        "JOLI",
        "JUDI",
        "JutulDarcy",
        "LinearAlgebra",
        "Logging",
        "Makie",
        "Markdown",
        "ProgressLogging",
        "Random",
        "Statistics",
        "TerminalLoggers",
        "WGLMakie",
        "YAML",
    ])

    Pkg.instantiate()

    using ConfigurationsJutulDarcy

    @codegen_copy_constructor ConfigurationsJutulDarcy.JutulOptions
    @codegen_copy_constructor ConfigurationsJutulDarcy.TimeDependentOptions
end
