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

using Base.Filesystem: isdir, checkfor_mv_cp_cptree, mkdir, readdir, islink, symlink, readlink, sendfile
function cptree_hidden(src::String, dst::String; force::Bool=false,
                                          follow_symlinks::Bool=false,
                                          include_hidden::Bool=true)
    isdir(src) || throw(ArgumentError("'$src' is not a directory. Use `cp(src, dst)`"))
    checkfor_mv_cp_cptree(src, dst, "copying"; force=force)
    mkdir(dst)
    for name in readdir(src)
        srcname = joinpath(src, name)
        if !follow_symlinks && islink(srcname)
            symlink(readlink(srcname), joinpath(dst, name))
        elseif !include_hidden && name[1] == '.'
        elseif isdir(srcname)
            cptree_hidden(srcname, joinpath(dst, name); force=force,
                                                 follow_symlinks=follow_symlinks)
        else
            sendfile(srcname, joinpath(dst, name))
        end
    end
end
cptree_hidden(src::AbstractString, dst::AbstractString; kwargs...) =
    cptree_hidden(String(src)::String, String(dst)::String; kwargs...)
