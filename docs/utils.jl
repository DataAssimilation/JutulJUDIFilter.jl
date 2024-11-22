function add_extra_info(content, pth; build_notebooks, build_scripts)
    links = []
    if build_notebooks
        push!(links, "[Jupyter notebook](main.ipynb)")
    end
    if build_scripts
        push!(links, "[plain script](main.jl)")
    end
    if length(links) == 0
        return content
    end
    project_link = "[Project.toml](Project.toml)"
    return content * """
        # # Alternative format
        # This can also be accessed as a $(join(links, ", a", ", or a ")).
        #
        # Notebook viewer may work [here](https://nbviewer.org/urls/dataassimilation.github.io/JutulJUDIFilter.jl/$(joinpath("examples", pth, "main.ipynb")))
    """
end