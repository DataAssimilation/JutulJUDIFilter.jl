
using Pkg: Pkg
_dependencies = Dict{Symbol,Any}()
_dependencies[:ConfigurationsJutulDarcy] =
    () -> Pkg.add(; url="https://github.com/gbruer15/ConfigurationsJutulDarcy.jl")
_dependencies[:ConfigurationsJUDI] =
    () -> Pkg.add(; url="https://github.com/tmp398243/tmp3117499")
_dependencies[:Ensembles] =
    () -> Pkg.add(; url="https://github.com/DataAssimilation/Ensembles.jl")

function install(pkg::Symbol)
    if !(pkg in keys(_dependencies))
        error("Unknown package: $pkg")
    end
    return _dependencies[pkg]()
end
