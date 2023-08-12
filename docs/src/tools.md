# Tools

## Swagger UI

[Swagger UI](https://swagger.io/tools/swagger-ui/) allows visualization and interaction with the API’s resources without having any of the implementation logic in place. OpenAPI.jl includes convenience methods to launch Swagger UI from Julia.

Use `OpenAPI.swagger_ui` to open Swagger UI. It uses the standard `swaggerapi/swagger-ui` docker image and requires docker engine to be installed.

```julia
# specify a specification file to start with
OpenAPI.swagger_ui(
    spec::AbstractString;   # the OpenAPI specification to use
    port::Int=8080,         # port to use 
    use_sudo::Bool=false    # whether to use sudo while invoking docker
)

# specify a folder and specification file name to start with
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
