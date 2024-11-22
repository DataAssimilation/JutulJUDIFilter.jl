using Pkg: Pkg
using JutulJUDIFilter
using Test
using TestReports
using TestReports.EzXML
using Aqua
using Documenter

errs = Vector{String}()
examples_dir = joinpath(@__DIR__, "..", "examples")

report_testsets = @testset ReportingTestSet "" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(JutulJUDIFilter; ambiguities=false)
        Aqua.test_ambiguities(JutulJUDIFilter)
    end

    @info "Running package tests."
    @test true

    # Set metadata for doctests.
    @info "Running doctests."
    DocMeta.setdocmeta!(
        JutulJUDIFilter, :DocTestSetup, :(using JutulJUDIFilter, Test); recursive=true
    )
    doctest(JutulJUDIFilter; manual=true)
end

xml_all = report(report_testsets)
outputfilename = joinpath(@__DIR__, "..", "report.xml")
open(outputfilename, "w") do fh
    print(fh, xml_all)
end
exit(any_problems(report_testsets) || length(errs) > 0)
