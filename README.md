# OpenAPI

[![Build Status](https://github.com/JuliaComputing/OpenAPI.jl/workflows/CI/badge.svg)](https://github.com/JuliaComputing/OpenAPI.jl/actions?query=workflow%3ACI+branch%3Amain)
[![codecov.io](http://codecov.io/github/JuliaComputing/OpenAPI.jl/coverage.svg?branch=main)](http://codecov.io/github/JuliaComputing/OpenAPI.jl?branch=main)

This Julia package contains documentation and code to create server stubs and consumer client from an OpenAPI specification.

[OpenAPI Generator](https://openapi-generator.tech/) is an external dependency needed for this package to work.

> Note: This package supersedes the [Swagger.jl](https://github.com/JuliaComputing/Swagger.jl) package. OpenAPI.jl and the associated generator can address both OpenAPI 2.x (Swagger) and OpenAPI 3.x specifications. Code dependent on Swagger.jl would not directly work with OpenAPI.jl, but migration should not be too difficult.

---
## Table of Contents

1. [What is OpenApi ?](#what-is-openapi)
2. [Code Generation](#code-generation)
3. [Generated Code Structure](#generated-code-structure)
    - [Models](#models)
    - [Validations](#validations)
    - [Client APIs](#client-apis)
    - [Server APIs](#server-apis)
4. [Examples](#examples)
5. [Tools](#tools)
    - [Swagger UI](#swagger-ui)
    - [Swagger Editor](#swagger-editor)
6. [TODO](#todo)
---

## What is OpenAPI ?

The OpenAPI project (previously called Swagger) works on defining a stardard to describe HTTP API's in a language agnostic document. For example consider a Pet Store service that allows customers to browse pets and the store employees to update the dabase on new pets. The full document can be found [here]()

```yaml
paths:
    '/pet/{petId}':
        get:
            tags:
                - pet
            summary: Find pet by ID
            description: Returns a single pet
            operationId: getPetById
            parameters:
                - name: petId
                in: path
                description: ID of pet to return
                required: true
                schema:
                    type: integer
                    format: int64
            responses:
                '200':
                description: successful operation
                content:
                    application/xml:
                    schema:
                        $ref: '#/components/schemas/Pet'
                    application/json:
                    schema:
                        $ref: '#/components/schemas/Pet'
                '400':
                description: Invalid ID supplied
                '404':
                description: Pet not found
            security:
                - api_key: []
                - petstore_auth:
                    - 'write:pets'
                    - 'read:pets'
```

Defines the path `/pet/{petId}` along with a variety of attributes including references to the structure of the response. Given below is the Pet object defined in the same document.
```yaml
Pet:
      required:
        - name
        - photoUrls
      properties:
        id:
          type: integer
          format: int64
          example: 10
        name:
          type: string
          example: doggie
        category:
          $ref: '#/components/schemas/Category'
        photoUrls:
          type: array
          xml:
            wrapped: true
          items:
            type: string
            xml:
              name: photoUrl
        tags:
          type: array
          xml:
            wrapped: true
          items:
            $ref: '#/components/schemas/Tag'
            xml:
              name: tag
        status:
          type: string
          description: pet status in the store
          enum:
            - available
            - pending
            - sold
```

## Code Generation

[OpenApi generator](https://openapi-generator.tech/) is used to generate Julia code from an OpenAPI document. The generator is available via multiple software channels like npm, homebrew, docker, jar,.etc [Choose any appropriate channel for your system](https://openapi-generator.tech/docs/installation). This package requires version 6.3.0 or above to work.


## Generated Code Structure

To illustrate usage let's try making a [PetStore.jl]() package out of the spec.

#### 1. Initialize the package

See the pkg docs on [creating a new package](https://pkgdocs.julialang.org/v1/creating-packages/) or as recommended by them(and us!) use [PkgTemplates](https://github.com/JuliaCI/PkgTemplates.jl) to easily configure many aspects such as license, git,.etc

Hit the `]` mode to enter package mode

```julia-repl
(@v1.9) pkg> generate PetStore.jl
  Generating  project PetStore:
    PetStore.jl/Project.toml
    PetStore.jl/src/PetStore.jl
```

Which generates the following files
```console
$ tree
.
└── PetStore.jl
    ├── Project.toml
    └── src
        └── PetStore.jl

3 directories, 2 files
```

#### 2. Download the OpenAPI spec

```bash
SPEC_SRC=https://raw.githubusercontent.com/swagger-api/swagger-petstore/master/src/main/resources/openapi.yaml
curl ${SPEC_SRC} \                              
    --create-dirs -o PetStore.jl/spec/openapi.yaml
```

#### 3. Generate the Julia code

As mentioned previously, the openapi generator has many software channels available. We will choose `docker` to illustrate but all other options are equivalent.

```bash
docker run --rm \              
  -v ${PWD}:/local openapitools/openapi-generator-cli generate --additional-properties=packageName=PetStore\
  -i /local/PetStore.jl/spec/openapi.yaml \
  -g julia-client \
  -o /local/PetStore.jl
```

There should be some new files in the package.

```console
$ tree PetStore.jl 
PetStore.jl
├── docs
│   ├── Address.md
│   ├── ApiResponse.md
│   ├── Category.md
│   ├── Customer.md
│   ├── Order.md
│   ├── PetApi.md
│   ├── Pet.md
│   ├── StoreApi.md
│   ├── Tag.md
│   ├── UserApi.md
│   └── User.md
├── README.md
├── spec
│   └── openapi.yaml
└── src
    ├── apis
    │   ├── api_PetApi.jl
    │   ├── api_StoreApi.jl
    │   └── api_UserApi.jl
    ├── modelincludes.jl
    ├── models
    │   ├── model_Address.jl
    │   ├── model_ApiResponse.jl
    │   ├── model_Category.jl
    │   ├── model_Customer.jl
    │   ├── model_Order.jl
    │   ├── model_Pet.jl
    │   ├── model_Tag.jl
    │   └── model_User.jl
    └── PetStore.jl

6 directories, 26 files
```

### Models

Each model from the specification is generated into a file named `model_<modelname>.jl`. It is represented as a `mutable struct` that is a subtype of the abstract type `APIModel`. Models have the following methods defined:

- constructor that takes keyword arguments to fill in values for all model properties.
- [`propertynames`](https://docs.julialang.org/en/v1/base/base/#Base.propertynames)
- [`hasproperty`](https://docs.julialang.org/en/v1/base/base/#Base.hasproperty)
- [`getproperty`](https://docs.julialang.org/en/v1/base/base/#Base.getproperty)
- [`setproperty!`](https://docs.julialang.org/en/v1/base/base/#Base.setproperty!)

In addition to these standard Julia methods, these convenience methods are also generated that help in checking value at a hierarchical path of the model.

- `function haspropertyat(o::T, path...) where {T<:APIModel}`
- `function getpropertyat(o::T, path...) where {T<:APIModel}`

E.g:

```julia
# access o.field.subfield1.subfield2
if haspropertyat(o, "field", "subfield1", "subfield2")
    getpropertyat(o, "field", "subfield1", "subfield2")
end

# access nested array elements, e.g. o.field2.subfield1[10].subfield2
if haspropertyat(o, "field", "subfield1", 10, "subfield2")
    getpropertyat(o, "field", "subfield1", 10, "subfield2")
end
```

### Validations

Following validations are incorporated into models:

- maximum value: must be a numeric value less than or equal to a specified value
- minimum value: must be a numeric value greater than or equal to a specified value
- maximum length: must be a string value of length less than or equal to a specified value
- minimum length: must be a string value of length greater than or equal to a specified value
- maximum item count: must be a list value with number of items less than or equal to a specified value
- minimum item count: must be a list value with number of items greater than or equal to a specified value
- unique items: items must be unique
- maximum properties count: number of properties must be less than or equal to a specified value
- minimum properties count: number of properties must be greater than or equal to a specified value
- pattern: must match the specified regex pattern
- format: must match the specified format specifier (see subsection below for details)
- enum: value must be from a list of allowed values
- multiple of: must be a multiple of a specified value

Validations are imposed in the constructor and `setproperty!` methods of models.

#### Validations for format specifiers

String, number and integer data types can have an optional format modifier that serves as a hint at the contents and format of the string. Validations for the following OpenAPI defined formats are built in:

| Data Type | Format    | Description |
|-----------|-----------|-------------|
| number    | float     | Floating-point numbers. |
| number    | double    | Floating-point numbers with double precision. |
| integer   | int32     | Signed 32-bit integers (commonly used integer type). |
| integer   | int64     | Signed 64-bit integers (long type). |
| string    | date      | full-date notation as defined by RFC 3339, section 5.6, for example, 2017-07-21 |
| string    | date-time | the date-time notation as defined by RFC 3339, section 5.6, for example, 2017-07-21T17:32:28Z |
| string    | byte      | base64-encoded characters, for example, U3dhZ2dlciByb2Nrcw== |

Validations for custom formats can be plugged in by overloading the `OpenAPI.val_format` method.

E.g.:

```julia
# add a new validation named `custom` for the number type
function OpenAPI.val_format(val::AbstractFloat, ::Val{:custom})
    return true # do some validations and return result
end
# add a new validation named `custom` for the integer type
function OpenAPI.val_format(val::Integer, ::Val{:custom})
    return true # do some validations and return result
end
# add a new validation named `custom` for the string type
function OpenAPI.val_format(val::AbstractString, ::Val{:custom})
    return true # do some validations and return result
end
```

### Client APIs

Each client API set is generated into a file named `api_<apiname>.jl`. It is represented as a `struct` and the APIs under it are generated as methods. An API set can be constructed by providing the OpenAPI client instance that it can use for communication.

The required API parameters are generated as regular function arguments. Optional parameters are generated as keyword arguments. Method documentation is generated with description, parameter information and return value. Two variants of the API are generated. The first variant is suitable for calling synchronously. It returns a tuple of the result struct and the HTTP response.

```julia
# example synchronous API that returns an Order instance
getOrderById(api::StoreApi, orderId::Int64) -> (result, http_response)
```

The second variant is suitable for asynchronous calls to methods that return chunked transfer encoded responses, where in the API streams the response objects into an output channel.

```julia
# example asynchronous API that streams matching Pet instances into response_stream
findPetsByStatus(
    api::PetApi,
    response_stream::Channel,
    status::Vector{String}) -> (response_stream, http_response)
```

The HTTP response returned from the API calls, have these properties:
- `status`: integer status code
- `message`: http message corresponding to status code
- `headers`: http response headers as `Vector{Pair{String,String}}`

A client context holds common information to be used across APIs. It also holds a connection to the server and uses that across API calls.
The client context needs to be passed as the first parameter of all API calls. It can be created as:

```julia
Client(root::String;
    headers::Dict{String,String}=Dict{String,String}(),
    get_return_type::Function=(default,data)->default,
    timeout::Int=DEFAULT_TIMEOUT_SECS,
    long_polling_timeout::Int=DEFAULT_LONGPOLL_TIMEOUT_SECS,
    pre_request_hook::Function,
    verbose::Union{Bool,Function}=false,
)
```

Where:

- `root`: the root URI where APIs are hosted (should not end with a `/`)
- `headers`: any additional headers that need to be passed along with all API calls
- `get_return_type`: optional method that can map a Julia type to a return type other than what is specified in the API specification by looking at the data (this is used only in special cases, for example when models are allowed to be dynamically loaded)
- `timeout`: optional timeout to apply for server methods (default `OpenAPI.Clients.DEFAULT_TIMEOUT_SECS`)
- `long_polling_timeout`: optional timeout to apply for long polling methods (default `OpenAPI.Clients.DEFAULT_LONGPOLL_TIMEOUT_SECS`)
- `pre_request_hook`: user provided hook to modify the request before it is sent
- `verbose`: whether to enable verbose logging

The `pre_request_hook` must provide the following two implementations:
- `pre_request_hook(ctx::OpenAPI.Clients.Ctx) -> ctx`
- `pre_request_hook(resource_path::AbstractString, body::Any, headers::Dict{String,String}) -> (resource_path, body, headers)`

The `verbose` option can be one of:
- `false`: the default, no verbose logging
- `true`: enables curl verbose logging to stderr
- a function that accepts two arguments - type and message (available on Julia version >= 1.7)
    - a default implementation of this that uses `@info` to log the arguments is provided as `OpenAPI.Clients.default_debug_hook`

In case of any errors an instance of `ApiException` is thrown. It has the following fields:

- `status::Int`: HTTP status code
- `reason::String`: Optional human readable string
- `resp::Downloads.Response`: The HTTP Response for this call
- `error::Union{Nothing,Downloads.RequestError}`: The HTTP error on request failure

An API call involves the following steps:
- If a pre request hook is provided, it is invoked with an instance of `OpenAPI.Clients.Ctx` that has the request attributes. The hook method is expected to make any modifications it needs to the request attributes before the request is prepared, and return the modified context.
- The URL to be invoked is prepared by replacing placeholders in the API URL template with the supplied function parameters.
- If this is a POST request, serialize the instance of `APIModel` provided as the `body` parameter as a JSON document.
- If a pre request hook is provided, it is invoked with the prepared resource path, body and request headers. The hook method is expected to modify and return back a tuple of resource path, body and headers which will be used to make the request.
- Make the HTTP call to the API endpoint and collect the response.
- Determine the response type / model, invoke the optional user specified mapping function if one was provided.
- Convert (deserialize) the response data into the return type and return.
- In case of any errors, throw an instance of `ApiException`

### Server APIs

The server code is generated as a package. It contains API stubs and validations of API inputs. It requires the caller to
have implemented the APIs, the signatures of which are provided in the generated package module docstring.

A `register` function is made available that when provided with a `Router` instance, registers handlers
for all the APIs.

`register(router, impl; path_prefix="", optional_middlewares...) -> HTTP.Router`

Paramerets:
- `router`: `HTTP.Router` to register handlers in, the same instance is also returned
- `impl`: module that implements the server APIs

Optional parameters:
- `path_prefix`: prefix to be applied to all paths
- `optional_middlewares`: Register one or more optional middlewares to be applied to all requests.

Optional middlewares can be one or more of:
- `init`: called before the request is processed
- `pre_validation`: called after the request is parsed but before validation
- `pre_invoke`: called after validation but before the handler is invoked
- `post_invoke`: called after the handler is invoked but before the response is sent

The order in which middlewares are invoked is:
`init |> read |> pre_validation |> validate |> pre_invoke |> invoke |> post_invoke`

## Examples

The Petstore is a common example that most OpenAPI implementations use to test and demonstrate. Clients and servers generated from both version 2 and 3 specifications are included in this repo.

- Petstore v2:
    - Client: [docs](test/client/petstore_v2/petstore/README.md), [implementation](test/client/petstore_v2)
    - Server: [docs](test/server/petstore_v2/petstore/README.md), [implementation](test/server/petstore_v2)
- Petstore v3:
    - Client: [docs](test/client/petstore_v3/petstore/README.md), [implementation](test/client/petstore_v3)
    - Server: [docs](test/server/petstore_v3/petstore/README.md), [implementation](test/server/petstore_v3)

## Tools

### Swagger UI

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

### Swagger Editor

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

## TODO

Not all OpenAPI features are supported yet, e.g.:
- [`not`](https://swagger.io/docs/specification/data-models/oneof-anyof-allof-not/)
- [inheritance and polymorphism](https://swagger.io/docs/specification/data-models/inheritance-and-polymorphism/)
- [some of the JSON schema keywords](https://swagger.io/docs/specification/data-models/keywords/)
- some [subtler data types](https://swagger.io/docs/specification/data-models/data-types/)
    - native representaion of some of the string formats, e.g. uuid, url
    - read-only and write-only properties
- authentication schemes
- [`deepObject`](https://swagger.io/docs/specification/serialization/)s in query parameters

There could be more unsupported features than what is listed above.
