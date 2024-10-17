
# First, generate and plot the synthetic ground truth.
using Pkg

ENV["jutuljudifilter_force_install"] = "true"

params_file = abspath(joinpath(@__DIR__, "params", "small-params.jl"))
push!(ARGS, params_file)

##include("scripts/plot_ground_truth.jl")
##
##using Markdown
##
##fig_path = relpath(joinpath(savedir, "01.png"))
##
##Markdown.parse("![ground truth states]($fig_path)")
