
# First, generate and plot the synthetic ground truth.
using Pkg

# ENV["jutuljudifilter_force_install"] = "true"

params_file = abspath(joinpath(@__DIR__, "params", "small-params.jl"))
push!(ARGS, params_file)

include("scripts/plot_ground_truth.jl")

using DrWatson

save_dir = relpath(save_dir_root, projectdir())
if abspath(save_dir_root) != abspath(save_dir)
    mv(save_dir_root, save_dir; force=true)
end

using Markdown

# ## Saturation
fig_path = Markdown.parse("""
![ground truth saturation 1]($(joinpath(save_dir, "saturation", "01.png")))
![ground truth saturation 2]($(joinpath(save_dir, "saturation", "02.png")))
![ground truth saturation 3]($(joinpath(save_dir, "saturation", "03.png")))
![ground truth saturation 4]($(joinpath(save_dir, "saturation", "04.png")))
![ground truth saturation 5]($(joinpath(save_dir, "saturation", "05.png")))
![ground truth saturation 6]($(joinpath(save_dir, "saturation", "06.png")))
""")

# ## Pressure
fig_path = Markdown.parse("""
![ground truth pressure 1]($(joinpath(save_dir, "pressure", "01.png")))
![ground truth pressure 2]($(joinpath(save_dir, "pressure", "02.png")))
![ground truth pressure 3]($(joinpath(save_dir, "pressure", "03.png")))
![ground truth pressure 4]($(joinpath(save_dir, "pressure", "04.png")))
![ground truth pressure 5]($(joinpath(save_dir, "pressure", "05.png")))
![ground truth pressure 6]($(joinpath(save_dir, "pressure", "06.png")))
""")

# ## Pressure difference
fig_path = Markdown.parse("""
![ground truth pressure_diff 1]($(joinpath(save_dir, "pressure_diff", "01.png")))
![ground truth pressure_diff 2]($(joinpath(save_dir, "pressure_diff", "02.png")))
![ground truth pressure_diff 3]($(joinpath(save_dir, "pressure_diff", "03.png")))
![ground truth pressure_diff 4]($(joinpath(save_dir, "pressure_diff", "04.png")))
![ground truth pressure_diff 5]($(joinpath(save_dir, "pressure_diff", "05.png")))
![ground truth pressure_diff 6]($(joinpath(save_dir, "pressure_diff", "06.png")))
""")
