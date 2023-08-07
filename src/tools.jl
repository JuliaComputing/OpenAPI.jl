const SwaggerImage = (UI="swaggerapi/swagger-ui", Editor="swaggerapi/swagger-editor")

docker_cmd(; use_sudo::Bool=false) = use_sudo ? `sudo docker` : `docker`

"""
    stop_swagger_ui(; use_sudo=false)

Stop and remove the Swagger UI container, if it is running.
Returns true if the container was stopped and removed, false otherwise.
"""
stop_swagger_ui(; use_sudo::Bool=false) = _stop_swagger(SwaggerImage.UI; use_sudo=use_sudo)

"""
    stop_swagger_editor(; use_sudo=false)

Stop and remove the Swagger Editor container, if it is running.
Returns true if the container was stopped and removed, false otherwise.
"""
stop_swagger_editor(; use_sudo::Bool=false) = _stop_swagger(SwaggerImage.Editor; use_sudo=use_sudo)

"""
    stop_swagger(; use_sudo=false)

Stop and remove Swagger UI or Editor containers, if they are running.
Returns true if any container was stopped and removed, false otherwise.    
"""
function stop_swagger(; use_sudo::Bool=false)
    stopped = stop_swagger_ui(; use_sudo=use_sudo)
    stopped |= stop_swagger_editor(; use_sudo=use_sudo)
    return stopped
end

function _stop_swagger(image_name::AbstractString; use_sudo::Bool=false)
    docker = docker_cmd(; use_sudo=use_sudo)
    find_cmd = `$docker ps -a -q -f ancestor=$image_name`
    container_id = strip(String(read(find_cmd)))
    
    if !isempty(container_id)
        stop_cmd = `$docker stop $container_id`
        stop_res = strip(String(read(stop_cmd)))

        if stop_res == container_id
            @debug("Stopped Swagger container")
        elseif isempty(stop_res)
            @debug("Swagger container not running")
        else
            @error("Failed to stop Swagger container: $stop_res")
            return false
        end

        container_id = strip(String(read(find_cmd)))
        if !isempty(container_id)
            rm_cmd = `$docker rm $container_id`
            rm_res = strip(String(read(rm_cmd)))

            if rm_res == container_id
                @debug("Removed Swagger container")
            elseif isempty(rm_res)
                @debug("Swagger container not found")
            else
                @error("Failed to remove Swagger container: $rm_res")
                return false
            end
        end

        return true
    else
        @debug("Swagger container not found")
    end

    return false
end

function _start_swagger(cmd, port)
    run(cmd)
    return "http://localhost:$port"
end

"""
    swagger_ui(spec; port=8080, use_sudo=false)
    swagger_ui(spec_dir, spec_file; port=8080, use_sudo=false)

Start a Swagger UI container for the given OpenAPI spec file. Returns the URL of the Swagger UI.

Optional arguments:
- `port`: The port to use for the Swagger UI. Defaults to 8080.
- `use_sudo`: Whether to use `sudo` to run Docker commands. Defaults to false.
"""
function swagger_ui(spec::AbstractString; port::Int=8080, use_sudo::Bool=false)
    spec = abspath(spec)
    spec_dir = dirname(spec)
    spec_file = basename(spec)
    return swagger_ui(spec_dir, spec_file; port=port, use_sudo=use_sudo)
end

function swagger_ui(spec_dir::AbstractString, spec_file::AbstractString; port::Int=8080, use_sudo::Bool=false)
    docker = docker_cmd(; use_sudo=use_sudo)
    cmd = `$docker run -d --rm -p $port:8080 -e SWAGGER_JSON=/spec/$spec_file -v $spec_dir:/spec $(SwaggerImage.UI)`
    return _start_swagger(cmd, port)
end

"""
    swagger_editor(; port=8080, use_sudo=false)
    swagger_editor(spec; port=8080, use_sudo=false)
    swagger_editor(spec_dir, spec_file; port=8080, use_sudo=false)

Start a Swagger Editor container with an optional OpenAPI spec file. Returns the URL of the Swagger Editor.

Optional arguments:
- `port`: The port to use for the Swagger Editor. Defaults to 8080.
- `use_sudo`: Whether to use `sudo` to run Docker commands. Defaults to false.
"""
function swagger_editor(spec::AbstractString; port::Int=8080, use_sudo::Bool=false)
    spec = abspath(spec)
    spec_dir = dirname(spec)
    spec_file = basename(spec)
    return swagger_editor(spec_dir, spec_file; port=port, use_sudo=use_sudo)
end

function swagger_editor(spec_dir::AbstractString, spec_file::AbstractString; port::Int=8080, use_sudo::Bool=false)
    docker = docker_cmd(; use_sudo=use_sudo)
    cmd = `$docker run -d --rm -p $port:8080 -e SWAGGER_FILE=/spec/$spec_file -v $spec_dir:/spec $(SwaggerImage.Editor)`
    return _start_swagger(cmd, port)
end

function swagger_editor(; port::Int=8080, use_sudo::Bool=false)
    docker = docker_cmd(; use_sudo=use_sudo)
    cmd = `$docker run -d --rm -p $port:8080 $(SwaggerImage.Editor)`
    return _start_swagger(cmd, port)
end

"""
    lint(spec; use_sudo=false)
    lint(spec_dir, spec_file; use_sudo=false)

Lint an OpenAPI spec file using Spectral.

Optional arguments:
- `use_sudo`: Whether to use `sudo` to run Docker commands. Defaults to false.
"""
function lint(spec::AbstractString; use_sudo::Bool=false)
    spec = abspath(spec)
    spec_dir = dirname(spec)
    spec_file = basename(spec)
    return lint(spec_dir, spec_file; use_sudo=use_sudo)
end

function lint(spec_dir::AbstractString, spec_file::AbstractString; use_sudo::Bool=false)
    docker = docker_cmd(; use_sudo=use_sudo)
    if isfile(joinpath(spec_dir, ".spectral.yaml"))
        @debug("linting with existing configuration")
        cmd = `$docker run --rm -v $spec_dir:/spec:ro -w /spec stoplight/spectral:latest lint /spec/$spec_file`
        run(cmd)
    else
        # generate a default configuration file
        @debug("linting with default configuration")
        mktempdir() do tmpdir
            open(joinpath(tmpdir, ".spectral.yaml"), "w") do f
                write(f, """extends: ["spectral:oas", "spectral:asyncapi"]""")
            end
            cp(joinpath(spec_dir, spec_file), joinpath(tmpdir, spec_file))
            cmd = `$docker run --rm -v $tmpdir:/spec:ro -w /spec stoplight/spectral:latest lint /spec/$spec_file`
            run(cmd)
        end
    end
end