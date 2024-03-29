# User Guide

## Code Generation

Use [instructions](https://openapi-generator.tech/docs/generators) provided for the Julia OpenAPI code generator plugin to generate Julia code.

Requires version [6.3.0](https://github.com/OpenAPITools/openapi-generator/releases/tag/v6.3.0) or later of [openapi-generator](https://github.com/OpenAPITools/openapi-generator).

## Models

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

## Validations

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

## Client APIs

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
    escape_path_params::Union{Nothing,Bool}=nothing,
    chunk_reader_type::Union{Nothing,Type{<:AbstractChunkReader}}=nothing,
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
- `escape_path_params`: Whether the path parameters should be escaped before being used in the URL (true by default). This is useful if the path parameters contain characters that are not allowed in URLs or contain path separators themselves.
- `chunk_reader_type`: The type of chunk reader to be used for streaming responses.
- `verbose`: whether to enable verbose logging

The `pre_request_hook` must provide the following two implementations:
- `pre_request_hook(ctx::OpenAPI.Clients.Ctx) -> ctx`
- `pre_request_hook(resource_path::AbstractString, body::Any, headers::Dict{String,String}) -> (resource_path, body, headers)`

The `chunk_reader_type` can be one of `LineChunkReader`, `JSONChunkReader` or `RFC7464ChunkReader`. If not specified, then the type is automatically determined based on the return type of the API call. Refer to the [Streaming Responses](#Streaming-Responses) section for more details.

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

## Server APIs

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

## Responses

The server APIs can return the Julia type that is specified in the OpenAPI specification. The response is serialized as JSON and sent back to the client. The default HTTP response code used in this case is 200.

To return a custom HTTP response code, the server API can return a `HTTP.Response` instance directly. The OpenAPI package provides a overridden constructor for `HTTP.Response` that takes the desired HTTP code and the Julia struct that needs to be serialized as JSON and sent back to the client. It also sets the `Content-Type` header to `application/json`.

```julia
HTTP.Response(code::Integer, o::APIModel)
```

Structured error messages can also be returned in similar fashion. Any uncaught exception thrown by the server API is caught and converted into a `HTTP.Response` instance with the HTTP code set to 500 and the exception message as the response body.

## Streaming Responses

Some OpenAPI implementations implement streaming of responses by sending more than one items in the response, each of which is of the type declared as the return type in the specification. E.g. the [Twitter OpenAPI specification](https://api.twitter.com/2/openapi.json) that keeps sending tweets in JSON like this forever:

```json
{"data":{"id":"1800000000000000000","text":"mmm i like a sandwich"},"matching_rules":[{"id":1800000000000000000,"tag":"\"sandwich\""}]}
{"data":{"id":"1800000000000000001","text":"lets have a sandwich"},"matching_rules":[{"id":1800000000000000001,"tag":"\"sandwich\""}]}
```

OpenAPI.jl handles such responses through "chunk readers" which are engaged only with the streaming API endpoints. There can be multiple implementations of chunk readers, each of which must be of type `AbstractChunkReader`. The following are the chunk readers provided, each with a different chunk detection strategy. They are selected based on some heuristics based on the response data type.

- `LineChunkReader`: Chunks delimited by newline. This is the default when the response type is detected to be not of `OpenAPI.APIModel` type.
- `JSONChunkReader`: Each chunk is a JSON. Whitespaces between JSONs are ignored. This is the default when the response type is detected to be a `OpenAPI.APIModel`.
- `RFC7464ChunkReader`: A reader based on [RFC 7464](https://www.rfc-editor.org/rfc/rfc7464.html). Available for use by overriding through `Client` or `Ctx`.

The `OpenAPI.Clients.Client` and `OpenAPI.Clients.Ctx` constructors take an additional `chunk_reader_type` keyword parameter. This can be one of `OpenAPI.Clients.LineChunkReader`, `OpenAPI.Clients.JSONChunkReader` or `OpenAPI.Clients.RFC7464ChunkReader`. If not specified, then the type is automatically determined as described above.
