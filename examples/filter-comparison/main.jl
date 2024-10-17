
# First, generate and plot the synthetic ground truth.
using Pkg

ENV["jutuljudifilter_force_install"] = "true"

params_file = abspath(joinpath(@__DIR__, "params", "small-params.jl"))
push!(ARGS, params_file)
