using OpenAPI

include(joinpath(@__DIR__, "TrimClient.jl"))

function checked(condition::Bool, message::String)::Nothing
    condition || error(message)
    return nothing
end

function exercise_openapi_public_entrypoints()::Nothing
    version = OpenAPI.DocumentVersion("3.1.0")
    checked(version.major == 3, "document version major was wrong")
    checked(OpenAPI.oas_family(version) === :oas31, "document family was wrong")

    parameter = OpenAPI.Param("id", :path, Int)
    checked(parameter.name == "id", "parameter name was lost")
    checked(parameter.required, "path parameter was not required")

    operation = OpenAPI.Operation(;
        id = "getWidget",
        method = :GET,
        path = "/widgets/{id}",
        params = [parameter],
        responsetype = String,
        secured = true,
    )
    checked(operation.method === :GET, "operation method was lost")
    checked(operation.secured, "operation security was lost")

    registry = OpenAPI.SchemaRegistry()
    schema = OpenAPI.schemaof(registry, Int)
    checked(schema isa AbstractDict, "primitive schema type was wrong")
    return nothing
end

function exercise_generated_client()::Nothing
    client = TrimClient.Client("https://override.example.test")
    checked(client.server == "https://override.example.test", "Client server was not set")

    credential = TrimClient.BearerCredential("trim-token")
    checked(credential.token == "trim-token", "generated bearer credential lost token")
    TrimClient.credential!(client, "BearerAuth", credential)
    checked(haskey(client.credentials, "BearerAuth"), "credential! did not set auth")
    TrimClient.clearcredential!(client, "BearerAuth")
    checked(!haskey(client.credentials, "BearerAuth"), "clearcredential! did not clear auth")

    widget = TrimClient.Widget(
        ;
        id = 7,
        name = "trim",
        status = TrimClient.WidgetStatus("active"),
        tags = ["a"],
    )
    checked(widget.id == 7, "generated model constructor lost id")
    checked(widget.name == "trim", "generated model constructor lost name")
    checked(string(widget.status) == "active", "generated enum constructor lost value")
    checked(widget.tags == ["a"], "generated model constructor lost tags")
    return nothing
end

function run_openapi_trim_workload()::Nothing
    exercise_openapi_public_entrypoints()
    exercise_generated_client()
    return nothing
end

function @main(args::Vector{String})::Cint
    _ = args
    run_openapi_trim_workload()
    return 0
end

Base.Experimental.entrypoint(main, (Vector{String},))
