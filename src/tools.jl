const SwaggerImage = (
    UI="swaggerapi/swagger-ui",
    Editor="swaggerapi/swagger-editor",
)
const OpenAPIImage = (
    GeneratorOnline="openapitools/openapi-generator-online",
    GeneratorCLI="openapitools/openapi-generator-cli",
)

const GeneratorHost = (
    OpenAPIGeneratorTech = (
        Stable = "https://api.openapi-generator.tech",
        Master = "https://api-latest-master.openapi-generator.tech",
    ),
    Local="http://localhost:8080",
)

const GeneratorHeaders = [
    "Content-Type" => "application/json",
    "Accept" => "application/json",
]

docker_cmd(; use_sudo::Bool=false) = use_sudo ? `sudo docker` : `docker`

function _start_docker(cmd, port)
    run(cmd)
    return "http://localhost:$port"
end

function _stop_docker(image_name::AbstractString, image_type::AbstractString; use_sudo::Bool=false)
    docker = docker_cmd(; use_sudo=use_sudo)
    find_cmd = `$docker ps -a -q -f ancestor=$image_name`
    container_id = strip(String(read(find_cmd)))

    if !isempty(container_id)
        stop_cmd = `$docker stop $container_id`
        stop_res = strip(String(read(stop_cmd)))

        if stop_res == container_id
            @debug("Stopped $(image_type) container")
        elseif isempty(stop_res)
            @debug("$(image_type) container not running")
        else
            @error("Failed to stop $(image_type) container: $stop_res")
            return false
        end

        sleep(5)
        container_id = strip(String(read(find_cmd)))
        if !isempty(container_id)
            rm_cmd = `$docker rm $container_id`
            rm_res = strip(String(read(rm_cmd)))

            if rm_res == container_id
                @debug("Removed $(image_type) container")
            elseif isempty(rm_res)
                @debug("$(image_type) container not found")
            else
                @error("Failed to remove $(image_type) container: $rm_res")
                return false
            end
        end

        return true
    else
        @debug("$(image_type) container not found")
    end

    return false
end

"""
    stop_openapi_generator(; use_sudo=false)

Stop and remove the OpenAPI Generator container, if it is running.
Returns true if the container was stopped and removed, false otherwise.
"""
stop_openapi_generator(; use_sudo::Bool=false) = _stop_docker(OpenAPIImage.GeneratorOnline, "OpenAPI Generator"; use_sudo=use_sudo)

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

_stop_swagger(image_name::AbstractString; use_sudo::Bool=false) = _stop_docker(image_name, "Swagger", use_sudo=use_sudo)
_start_swagger(cmd, port) = _start_docker(cmd, port)

"""
    openapi_generator(; port=8080, use_sudo=false)

Start an OpenAPI Generator Online container. Returns the URL of the OpenAPI Generator.

Optional arguments:
- `port`: The port to use for the OpenAPI Generator. Defaults to 8080.
- `use_sudo`: Whether to use `sudo` to run Docker commands. Defaults to false.
"""
function openapi_generator(; port::Int=8080, use_sudo::Bool=false)
    docker = docker_cmd(; use_sudo=use_sudo)
    cmd = `$docker run -d --rm -p $port:8080 $(OpenAPIImage.GeneratorOnline)`
    return _start_docker(cmd, port)
end

function _strip_trailing_pathsep(path::AbstractString)
    if endswith(path, '/')
        return path[1:end-1]
    end
    return path
end

"""
    generate(
        spec::Dict{String,Any};
        type::Symbol=:client,
        package_name::AbstractString="APIClient",
        export_models::Bool=false,
        export_operations::Bool=false,
        output_dir::AbstractString="",
        generator_host::AbstractString=GeneratorHost.Local
    )

Generate client or server code from an OpenAPI spec using the OpenAPI Generator.
The OpenAPI Generator must be running at the specified `generator_host`.

Returns the path to the generated code.

Optional arguments:
- `type`: The type of code to generate. Must be `:client` or `:server`. Defaults to `:client`.
- `package_name`: The name of the package to generate. Defaults to "APIClient".
- `export_models`: Whether to export models. Defaults to false.
- `export_operations`: Whether to export operations. Defaults to false.
- `output_dir`: The directory to save the generated code. Defaults to a temporary directory. Directory will be created if it does not exist.
- `generator_host`: The host of the OpenAPI Generator. Defaults to `GeneratorHost.Local`.
    Other possible values are `GeneratorHost.OpenAPIGeneratorTech.Stable` or `GeneratorHost.OpenAPIGeneratorTech.Master`, which point to
    the service hosted by OpenAPI org. It can also be any other URL where the OpenAPI Generator is running.

A locally hosted generator service is preferred by default for privacy reasons. 
Use `openapi_generator` to start a local container.
Use `stop_openapi_generator` to stop the local generator service after use.
"""
function generate(
    spec::Dict{String,Any};
    type::Symbol=:client,
    package_name::AbstractString="APIClient",
    export_models::Bool=false,
    export_operations::Bool=false,
    output_dir::AbstractString="",
    generator_host::AbstractString=GeneratorHost.Local,
)
    if type === :client
        generator_path = "clients/julia-client"
    elseif type === :server
        generator_path = "servers/julia-server"
    else
        throw(ArgumentError("Invalid generator type: $type. Must be :client or :server"))
    end

    if isempty(output_dir)
        output_dir = mktempdir()
    end

    url = _strip_trailing_pathsep(generator_host) * "/api/gen/" * generator_path
    post_json = Dict{String,Any}(
        "spec" => spec,
        "options" => Dict{String,Any}(
            "packageName" => package_name,
            "exportModels" => string(export_models),
            "exportOperations" => string(export_operations),
        )
    )

    out = PipeBuffer()
    inp = PipeBuffer()
    JSON.print(inp, post_json, 4)
    closewrite(inp)
    Downloads.request(url; method="POST", headers=GeneratorHeaders, input=inp, output=out, throw=true)
    res = JSON.parse(out)

    url = res["link"]
    mktempdir() do extracted_dir
        mktempdir() do download_dir
            output_file = joinpath(download_dir, "generated.zip")
            open(output_file, "w") do out
                Downloads.request(url; method="GET", output=out)
            end

            p7zip = p7zip_jll.p7zip()
            run(`$p7zip x -o$extracted_dir $output_file`)

            # we expect a single containing root directory in the extrated zip, the contents of which we move to the output directory
            root_dir = only(readdir(extracted_dir))
            mkpath(output_dir)
            for entry in readdir(joinpath(extracted_dir, root_dir))
                mv(joinpath(extracted_dir, root_dir, entry), joinpath(output_dir, entry); force=true)
            end
        end
    end

    return output_dir
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