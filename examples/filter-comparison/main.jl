
# First, generate and plot the synthetic ground truth.
using Pkg

ENV["jutuljudifilter_force_install"] = "true"

params_file = abspath(joinpath(@__DIR__, "params", "small-params.jl"))
push!(ARGS, params_file)

include("scripts/plot_ground_truth.jl")

using Markdown

fig_path = Markdown.parse("""
![ground truth state 1]($(relpath(joinpath(save_dir, "plume", "01.png"))))
![ground truth state 2]($(relpath(joinpath(save_dir, "plume", "02.png"))))
![ground truth state 3]($(relpath(joinpath(save_dir, "plume", "03.png"))))
![ground truth state 4]($(relpath(joinpath(save_dir, "plume", "04.png"))))
![ground truth state 5]($(relpath(joinpath(save_dir, "plume", "05.png"))))
""")
