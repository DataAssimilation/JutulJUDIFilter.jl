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

using Base.Filesystem:
    checkfor_mv_cp_cptree, mkdir, readdir, islink, symlink, readlink, sendfile
function cptree_regex(
    src::String,
    dst::String;
    follow_symlinks::Bool=false,
    ignore_hidden::Bool=false,
    match::Union{Nothing,Regex}=nothing,
)
    isdir(src) || throw(ArgumentError("'$src' is not a directory. Use `cp(src, dst)`"))
    for name in readdir(src)
        if ignore_hidden && name[1] == '.'
            continue
        end
        srcname = joinpath(src, name)
        if !follow_symlinks && islink(srcname)
            if isnothing(match) || occursin(match, srcname)
                mkpath(dst)
                symlink(readlink(srcname), joinpath(dst, name))
            end
        elseif isdir(srcname)
            cptree_regex(
                srcname, joinpath(dst, name); follow_symlinks, ignore_hidden, match
            )
        else
            check = isnothing(match) || occursin(match, srcname)
            if check
                mkpath(dst)
                sendfile(srcname, joinpath(dst, name))
            end
        end
    end
end
function cptree_regex(src::AbstractString, dst::AbstractString; kwargs...)
    return cptree_regex(String(src)::String, String(dst)::String; kwargs...)
end
