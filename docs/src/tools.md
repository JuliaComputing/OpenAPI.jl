# Tools

## Code Generator

The [OpenAPI Generator Docker image](https://hub.docker.com/r/openapitools/openapi-generator-cli) is a code generator that can generate client libraries, server stubs, and API documentation from an OpenAPI Specification. OpenAPI.jl includes convenience methods to use the OpenAPI Generator from Julia.

Use `OpenAPI.generate` to generate code from an OpenAPI specification. It can be pointed at a server hosted on the local machine or a remote server. The OpenAPI Generator must be running at the specified `generator_host`. Returns the folder containing generated code.

```julia
OpenAPI.generate(
    spec::Dict{String,Any};
    type::Symbol=:client,
    package_name::AbstractString="APIClient",
    export_models::Bool=false,
    export_operations::Bool=false,
    output_dir::AbstractString="",
    generator_host::AbstractString=GeneratorHost.Local
)
```

Arguments:
- `spec`: The OpenAPI specification as a Dict. It can be obtained by parsing a JSON or YAML file using `JSON.parse` or `YAML.load`.

Optional arguments:
- `type`: The type of code to generate. Must be `:client` or `:server`. Defaults to `:client`.
- `package_name`: The name of the package to generate. Defaults to "APIClient".
- `export_models`: Whether to export models. Defaults to false.
- `export_operations`: Whether to export operations. Defaults to false.
- `output_dir`: The directory to save the generated code. Defaults to a temporary directory. Directory will be created if it does not exist.
- `generator_host`: The host of the OpenAPI Generator. Defaults to `GeneratorHost.Local` (which points to `http://localhost:8080`).

The `generator_host` can be pointed to any other URL where the OpenAPI Generator is running, e.g. `https://openapigen.myorg.com`. Other possible pre-defined values of `generator_host`, which point to the public service hosted by OpenAPI org are:
- `OpenAPI.GeneratorHost.OpenAPIGeneratorTech.Stable`: Runs a stable version of the OpenAPI Generator at <https://api.openapi-generator.tech>.
- `OpenAPI.GeneratorHost.OpenAPIGeneratorTech.Master`: Runs the latest version of the OpenAPI Generator at <https://api-latest-master.openapi-generator.tech>.

A locally hosted generator service is preferred by default for privacy reasons. One can be started on the local machine using `OpenAPI.openapi_generator`. It uses the `openapitools/openapi-generator-online` docker image and requires docker engine to be installed. Use `OpenAPI.stop_openapi_generator` to stop the local generator service after use.

```julia
OpenAPI.openapi_generator(;
    port::Int=8080,         # port to use 
    use_sudo::Bool=false    # whether to use sudo while invoking docker
)

OpenAPI.stop_openapi_generator(;
    use_sudo::Bool=false    # whether to use sudo while invoking docker
)
```

## Swagger UI

[Swagger UI](https://swagger.io/tools/swagger-ui/) allows visualization and interaction with the API’s resources without having any of the implementation logic in place. OpenAPI.jl includes convenience methods to launch Swagger UI from Julia.

Use `OpenAPI.swagger_ui` to open Swagger UI. It uses the standard `swaggerapi/swagger-ui` docker image and requires docker engine to be installed.

```julia
# provide a specification file to start with
OpenAPI.swagger_ui(
    spec::AbstractString;   # the OpenAPI specification to use
    port::Int=8080,         # port to use 
    use_sudo::Bool=false    # whether to use sudo while invoking docker
)

# provide a folder and specification file name to start with
OpenAPI.swagger_ui(
    spec_dir::AbstractString;   # folder containing the specification file
    spec_file::AbstractString;  # the specification file
    port::Int=8080,             # port to use 
    use_sudo::Bool=false        # whether to use sudo while invoking docker
)
```

It returns the URL that should be opened in a browser to access the Swagger UI. Combining it with a tool like [DefaultApplication.jl](https://github.com/tpapp/DefaultApplication.jl) can help open a browser tab directly from Julia.

```julia
DefaultApplication.open(OpenAPI.swagger_ui("/my/openapi/spec.json"))
```

To stop the Swagger UI container, use `OpenAPI.stop_swagger_ui`.

```julia
OpenAPI.stop_swagger_ui(;
    use_sudo::Bool=false    # whether to use sudo while invoking docker
)
```

## Swagger Editor

[Swagger Editor](https://swagger.io/tools/swagger-editor/) allows editing of OpenAPI specifications and simultaneous visualization and interaction with the API’s resources without having any of the client implementation logic in place. OpenAPI.jl includes convenience methods to launch Swagger Editor from Julia.

Use `OpenAPI.swagger_editor` to open Swagger Editor. It uses the standard `swaggerapi/swagger-editor` docker image and requires docker engine to be installed.

```julia
# specify a specification file to start with
OpenAPI.swagger_editor(
    spec::AbstractString;   # the OpenAPI specification to use
    port::Int=8080,         # port to use 
    use_sudo::Bool=false    # whether to use sudo while invoking docker
)

# specify a folder and specification file name to start with
OpenAPI.swagger_editor(
    spec_dir::AbstractString;   # folder containing the specification file
    spec_file::AbstractString;  # the specification file
    port::Int=8080,             # port to use 
    use_sudo::Bool=false        # whether to use sudo while invoking docker
)

# start without specifying any initial specification file
OpenAPI.swagger_editor(
    port::Int=8080,             # port to use 
    use_sudo::Bool=false        # whether to use sudo while invoking docker
)
```

It returns the URL that should be opened in a browser to access the Swagger UI. Combining it with a tool like [DefaultApplication.jl](https://github.com/tpapp/DefaultApplication.jl) can help open a browser tab directly from Julia.

```julia
DefaultApplication.open(OpenAPI.swagger_editor("/my/openapi/spec.json"))
```

To stop the Swagger Editor container, use `OpenAPI.stop_swagger_editor`.

```julia
OpenAPI.stop_swagger_editor(;
    use_sudo::Bool=false    # whether to use sudo while invoking docker
)
```

## Spectral Linter

[Spectral](https://stoplight.io/open-source/spectral) is an open-source API style guide enforcer and linter. OpenAPI.jl includes a convenience method to use the  Spectral OpenAPI linter from Julia.

```julia
# specify a specification file to start with
OpenAPI.lint(
    spec::AbstractString;   # the OpenAPI specification to use
    use_sudo::Bool=false    # whether to use sudo while invoking docker
)

# specify a folder and specification file name to start with
OpenAPI.lint(
    spec_dir::AbstractString;   # folder containing the specification file
    spec_file::AbstractString;  # the specification file
    use_sudo::Bool=false        # whether to use sudo while invoking docker
)
```
