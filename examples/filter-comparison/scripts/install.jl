
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
    using Pkg: Pkg, PackageSpec

    if basename(dirname(Base.active_project())) != "filter-comparison"
        Pkg.activate(joinpath(@__DIR__, ".."))
    end
    @assert basename(dirname(Base.active_project())) == "filter-comparison"

    function ensure_installed(pkg; dev=false)
        deps = Pkg.dependencies()
        a = dev ? Pkg.develop : Pkg.add
        uuid = pkg.uuid
        dep = get(deps, uuid, nothing)
        if isnothing(dep) || isnothing(dep.version)
            a(pkg)
        elseif !dep.is_direct_dep
            a(pkg.name)
        else
            @info "Already installed: $dep"
        end
        @assert Pkg.dependencies()[uuid].is_direct_dep
    end

    required_dependencies = Dict{Symbol,Any}()
    required_dependencies[:ConfigurationsJutulDarcy] = 
        PackageSpec(;
            name = "ConfigurationsJutulDarcy",
            url="https://github.com/DataAssimilation/ConfigurationsJutulDarcy.jl",
            rev="v0.0.5",
            uuid="8c1f6541-c3b1-479a-a223-9e83eb45f3f9",
        )
    required_dependencies[:ConfigurationsJUDI] =
        PackageSpec(;
            name = "ConfigurationsJUDI",
            url="https://github.com/tmp398243/tmp3117499",
            rev="main",
            uuid="2c8b6cec-2da9-47bf-8bb4-83702df661de",
        )
    required_dependencies[:NormalizingFlowFilters] =
        PackageSpec(;
            name = "NormalizingFlowFilters",
            url="https://github.com/DataAssimilation/NormalizingFlowFilters.jl",
            rev="main",
            uuid="bdff3154-b03d-49d9-ae6e-73db1909c910",
        )
    required_dependencies[:EnsembleKalmanFilters] =
        PackageSpec(;
            name = "EnsembleKalmanFilters",
            url="https://github.com/DataAssimilation/EnsembleKalmanFilters.jl",
            rev="main",
            uuid="489b957c-0289-4703-8989-7a2007538216",
        )
    required_dependencies[:Ensembles] =
        PackageSpec(;
            name = "Ensembles",
            url="https://github.com/DataAssimilation/Ensembles.jl",
            rev="main",
            uuid="6e62b0a0-f6e2-496f-914a-544f223f57d3",
        )
    required_dependencies[:JutulJUDIFilter] =
        PackageSpec(;
            name = "JutulJUDIFilter",
            path = get(ENV, "jutuljudifilter_path", joinpath(@__DIR__, "..", "..", "..")),
            uuid="80fb201b-9edf-4eaa-a47c-dccd168d6cca",
        )

    ensure_installed(required_dependencies[:JutulJUDIFilter]; dev=true)
    ensure_installed(required_dependencies[:Ensembles])
    ensure_installed(required_dependencies[:ConfigurationsJutulDarcy])
    ensure_installed(required_dependencies[:EnsembleKalmanFilters])

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
