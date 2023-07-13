const opts = Base.JLOptions()
const inline_flag = opts.can_inline == 1 ? `` : `--inline=no`
const cov_flag = (opts.code_coverage == 1) ? `--code-coverage=user` :
                 (opts.code_coverage == 2) ? `--code-coverage=all` :
                 ``
const startup_flag = `--startup-file=no`

# can run servers only on linux for now
const run_tests_with_servers = get(ENV, "RUNNER_OS", "") == "Linux"

# can only run a subset of tests when running on openapi-generator repo
const openapi_generator_env = get(ENV, "OPENAPI_GENERATOR", "false") == "true"

function run_server(script, flags=``)
    use_pkgimages = VERSION >= v"1.9" ? `--pkgimages=no` : ``
    srvrcmd = `$(joinpath(Sys.BINDIR, "julia")) $use_pkgimages $startup_flag $cov_flag $inline_flag $script $flags`
    srvrcmd = addenv(srvrcmd,
        "JULIA_DEPOT_PATH"=>join(DEPOT_PATH, Sys.iswindows() ? ';' : ':'),
        "JULIA_LOAD_PATH"=>join(LOAD_PATH, Sys.iswindows() ? ';' : ':'),
    )
    iob = IOBuffer()
    pipelined_cmd = pipeline(srvrcmd, stdout=iob, stderr=iob)
    @info("Launching ", script, srvrcmd)
    ret = run(pipelined_cmd, wait=false)

    return ret, iob
end

function wait_server(port)
    @info("Waiting for server", port)
    is_ok = timedwait(20.0; pollint=2.0) do
        try
            resp = HTTP.request("GET", "http://127.0.0.1:$port/ping")
            return resp.status == 200
        catch
            return false
        end
    end

    timed_out = is_ok === :timed_out
    if timed_out
        @warn("Timed out waiting for server", port)
    else
        @info("Server is ready", port)
    end

    return !timed_out
end

function stop_server(port, proc, iob)
    @info("Stopping server", port)

    try
        HTTP.request("GET", "http://127.0.0.1:$port/stop")
    catch
        # ignore
    end

    try
        wait(proc)
        @info("Stopped server", port)
    catch ex
        server_logs = isnothing(iob) ? "" : String(take!(iob))
        @warn("Error waiting for server", port, server_logs, exception=(ex, catch_backtrace()))
        return false
    end

    return true
end
