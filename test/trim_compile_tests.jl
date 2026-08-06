using Test
import Pkg

include(joinpath(@__DIR__, "trim", "fixture.jl"))

const _OPENAPI_TRIM_SUPPORTED = VERSION >= v"1.12.0-rc1"
const _OPENAPI_JULIAC_ENTRYPOINT =
    "using JuliaC; if isdefined(JuliaC, :main); JuliaC.main(ARGS); else JuliaC._main_cli(ARGS); end"
const _OPENAPI_TRIM_COMPILE_TIMEOUT_S = 600.0
const _OPENAPI_TRIM_RUN_TIMEOUT_S = 60.0

_openapi_package_root(package) = normpath(joinpath(dirname(pathof(package)), ".."))

function _prepare_openapi_trim_project(trim_project::String)::Nothing
    mkpath(trim_project)
    cp(joinpath(@__DIR__, "trim", "Project.toml"), joinpath(trim_project, "Project.toml"))
    package_specs = Pkg.PackageSpec[
        Pkg.PackageSpec(path = _openapi_package_root(OpenAPI)),
        Pkg.PackageSpec(path = _openapi_package_root(OpenAPI.JSON)),
    ]
    original_project = Base.active_project()
    try
        Pkg.activate(trim_project)
        Pkg.develop(package_specs)
        Pkg.instantiate()
    finally
        original_project === nothing || Pkg.activate(dirname(original_project))
    end

    # Generate from the full fixture before JuliaC runs. This keeps the trim
    # workload tied to the current generator instead of a checked-in snapshot.
    OpenAPI.client(
        TRIM_OPENAPI_JSON;
        name = "TrimClient",
        path = joinpath(trim_project, "TrimClient.jl"),
    )
    cp(
        joinpath(@__DIR__, "openapi_trim_workload.jl"),
        joinpath(trim_project, "openapi_trim_workload.jl"),
    )
    return nothing
end

function _run_openapi_command(cmd::Cmd; timeout_s::Float64, label::String)
    output_path = tempname()
    output_stream = open(output_path, "w")
    exit_code = -1
    timed_out = false
    try
        process = run(
            pipeline(ignorestatus(cmd), stdout = output_stream, stderr = output_stream);
            wait = false,
        )
        started = time()
        next_update = started + 10.0
        while Base.process_running(process)
            now = time()
            if now - started >= timeout_s
                try
                    kill(process)
                catch
                end
                timed_out = true
                break
            end
            if now >= next_update
                println("[trim] $label WAIT $(round(now - started; digits = 1))s")
                flush(stdout)
                next_update = now + 10.0
            end
            sleep(0.1)
        end
        try
            wait(process)
        catch
        end
        exit_code = something(process.exitcode, -1)
    finally
        close(output_stream)
    end
    output = try
        read(output_path, String)
    finally
        rm(output_path; force = true)
    end
    return exit_code, output, timed_out
end

function _openapi_trim_totals(output::String)
    summary = match(
        r"Trim verify finished with\s+(\d+)\s+errors,\s+(\d+)\s+warnings\.",
        output,
    )
    if summary === nothing
        errors = length(collect(eachmatch(r"Verifier error #\d+:", output)))
        warnings = length(collect(eachmatch(r"Verifier warning #\d+:", output)))
        return errors, warnings
    end
    return parse(Int, summary.captures[1]), parse(Int, summary.captures[2])
end

function _run_openapi_trim_case(trim_project::String)::Nothing
    julia = joinpath(Sys.BINDIR, Base.julia_exename())
    script = joinpath(trim_project, "openapi_trim_workload.jl")
    println("[trim] compile START openapi_trim_workload.jl")
    started = time()
    mktempdir() do output_dir
        output_name = "openapi_trim_workload"
        compile = `$julia --startup-file=no --history-file=no --code-coverage=none --project=$trim_project -e $(_OPENAPI_JULIAC_ENTRYPOINT) -- --output-exe $output_name --project=$trim_project --experimental --trim=safe $script`
        exit_code, output, timed_out = cd(output_dir) do
            _run_openapi_command(
                compile;
                timeout_s = _OPENAPI_TRIM_COMPILE_TIMEOUT_S,
                label = "compile",
            )
        end
        timed_out && error("JuliaC trim compile timed out\n$output")
        errors, warnings = _openapi_trim_totals(output)
        if exit_code != 0 || errors != 0 || warnings != 0
            println("---- trim compile output ----")
            println(output)
            println("---- end trim compile output ----")
        end
        @test errors == 0
        @test warnings == 0
        @test exit_code == 0

        executable = joinpath(
            output_dir,
            Sys.iswindows() ? output_name * ".exe" : output_name,
        )
        @test isfile(executable)
        run_exit, run_output, run_timed_out = _run_openapi_command(
            `$(abspath(executable))`;
            timeout_s = _OPENAPI_TRIM_RUN_TIMEOUT_S,
            label = "run",
        )
        if run_timed_out || run_exit != 0
            println("---- trim executable output ----")
            println(run_output)
            println("---- end trim executable output ----")
        end
        @test !run_timed_out
        @test run_exit == 0
    end
    println(
        "[trim] compile DONE openapi_trim_workload.jl ($(round(time() - started; digits = 2))s)",
    )
    return nothing
end

@testset "JuliaC trim compile" begin
    if Sys.iswindows()
        println("[trim] skip Windows: JuliaC trim compilation is not stable in package CI")
        @test true
    elseif Sys.WORD_SIZE != 64
        println("[trim] skip 32-bit Julia: JuliaC trim compilation is covered on 64-bit jobs")
        @test true
    elseif !_OPENAPI_TRIM_SUPPORTED
        println("[trim] skip Julia < 1.12: JuliaC trim compilation is unavailable")
        @test true
    else
        mktempdir() do directory
            trim_project = joinpath(directory, "trim_project")
            _prepare_openapi_trim_project(trim_project)
            _run_openapi_trim_case(trim_project)
        end
    end
end
