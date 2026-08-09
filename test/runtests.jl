using Test, OpenAPI, JSON, Dates
import Downloads, HTTP, Sockets, TimeZones

const SchemaEngine = OpenAPI.SchemaEngine

# ── domain types used across the tests ──────────────────────────────────────

struct TWidget
    id::Int
    tags::Vector{String}
end

struct TOrder
    widget::TWidget
    count::Int
    note::Union{Nothing,String}
    placed::Date
end

@enum TColor tred tgreen tblue

struct TNode
    value::Int
    next::Union{Nothing,TNode}
end

getschema(reg, T) = OpenAPI.schemaof(reg, T)

@testset "OpenAPI" begin

    @testset "public API uses the package namespace" begin
        for name in (
            :Operation,
            :Param,
            :check,
            :client,
            :document,
            :load,
            :normalize,
            :plan,
            :server,
            :server_source,
            :serverplan,
            :validate,
        )
            @test Base.ispublic(OpenAPI, name)
            @test !Base.isexported(OpenAPI, name)
        end
    end

    @testset "Julia types -> JSON Schema" begin
        reg = OpenAPI.SchemaRegistry()
        @test getschema(reg, Int)["type"] == "integer"
        @test getschema(reg, Int)["format"] == "int64"
        @test getschema(reg, Float64) ==
              OpenAPI.obj("type" => "number", "format" => "double")
        @test getschema(reg, Bool)["type"] == "boolean"
        @test getschema(reg, String)["type"] == "string"
        @test getschema(reg, Symbol)["type"] == "string"
        @test getschema(reg, Date) == OpenAPI.obj("type" => "string", "format" => "date")
        @test getschema(reg, DateTime)["format"] == "date-time"
        @test getschema(reg, Any) == OpenAPI.obj()
        @test getschema(reg, Vector{Int}) == OpenAPI.obj(
            "type" => "array",
            "items" => OpenAPI.obj("type" => "integer", "format" => "int64"),
        )
        @test getschema(reg, Dict{String,Bool})["additionalProperties"]["type"] == "boolean"
        @test getschema(reg, TColor)["enum"] == ["tred", "tgreen", "tblue"]

        nullable = getschema(reg, Union{Nothing,Int})
        @test haskey(nullable, "oneOf")
        @test OpenAPI.obj("type" => "null") in nullable["oneOf"]

        # named tuples become inline object schemas
        nt = getschema(reg, typeof((; ok = true, n = 1)))
        @test nt["type"] == "object"
        @test nt["required"] == ["ok", "n"]

        # structs register once and are referenced
        @test getschema(reg, TWidget) ==
              OpenAPI.obj("\$ref" => "#/components/schemas/TWidget")
        @test getschema(reg, TWidget) ==
              OpenAPI.obj("\$ref" => "#/components/schemas/TWidget")
        tw = reg.schemas["TWidget"]
        @test tw["properties"]["id"]["type"] == "integer"
        @test tw["properties"]["tags"]["type"] == "array"
        @test tw["required"] == ["id", "tags"]

        # nested refs, optional (Union{Nothing}) fields, date formats
        getschema(reg, TOrder)
        to = reg.schemas["TOrder"]
        @test to["properties"]["widget"]["\$ref"] == "#/components/schemas/TWidget"
        @test to["properties"]["placed"]["format"] == "date"
        @test to["required"] == ["widget", "count", "placed"]  # note is optional

        # self-referential types terminate
        getschema(reg, TNode)
        @test haskey(reg.schemas, "TNode")
    end

    ops = [
        OpenAPI.Operation(;
            id = "getwidget",
            method = :GET,
            path = "/w/{id}",
            summary = "Get a widget",
            params = [
                OpenAPI.Param("id", :path, Int),
                OpenAPI.Param("owner", :query, String),
                OpenAPI.Param("verbose", :query, Bool; required = false),
            ],
            responsetype = TWidget,
        ),
        OpenAPI.Operation(;
            id = "neworder",
            method = :POST,
            path = "/orders",
            bodytype = TOrder,
            responsetype = TOrder,
            secured = true,
        ),
        OpenAPI.Operation(;
            id = "rmorder",
            method = :DELETE,
            path = "/orders/{id}",
            params = [OpenAPI.Param("id", :path, Int)],
            responsetype = Nothing,
        ),
        OpenAPI.Operation(;
            id = "getwidget",
            method = :GET,
            path = "/w2/{id}",
            params = [OpenAPI.Param("id", :path, Int)],
        ),
    ]
    doc = OpenAPI.document(
        ops;
        title = "Test API",
        version = "1.2.3",
        description = "a test api",
        servers = ["http://api.example"],
    )

    @testset "document generation" begin
        @test doc["openapi"] == "3.2.0"
        @test doc["info"]["title"] == "Test API"
        @test doc["info"]["version"] == "1.2.3"
        @test doc["servers"][1]["url"] == "http://api.example"

        get1 = doc["paths"]["/w/{id}"]["get"]
        @test get1["operationId"] == "getwidget"
        @test get1["summary"] == "Get a widget"
        p1, p2, p3 = get1["parameters"]
        @test p1["name"] == "id" && p1["in"] == "path" && p1["required"] === true
        @test p2["name"] == "owner" && p2["in"] == "query" && p2["required"] === true
        @test p3["name"] == "verbose" && p3["required"] === false
        @test get1["responses"]["200"]["content"]["application/json"]["schema"]["\$ref"] ==
              "#/components/schemas/TWidget"
        @test haskey(get1["responses"], "default")

        post = doc["paths"]["/orders"]["post"]
        @test post["requestBody"]["required"] === true
        @test post["requestBody"]["content"]["application/json"]["schema"]["\$ref"] ==
              "#/components/schemas/TOrder"
        @test post["security"] == [OpenAPI.obj("bearerAuth" => String[])]

        del = doc["paths"]["/orders/{id}"]["delete"]
        @test haskey(del["responses"], "204")
        @test !haskey(del["responses"], "200")

        # duplicate operationIds are deduped
        @test doc["paths"]["/w2/{id}"]["get"]["operationId"] == "getwidget_2"

        @test haskey(doc["components"]["schemas"], "TWidget")
        @test haskey(doc["components"]["schemas"], "TOrder")
        @test doc["components"]["securitySchemes"]["bearerAuth"]["scheme"] == "bearer"

        @test OpenAPI.validate(doc) === doc

        # invalid operations fail at construction
        @test_throws ArgumentError OpenAPI.Operation(;
            id = "x",
            method = :FETCH,
            path = "/x",
        )
        @test_throws ArgumentError OpenAPI.Operation(;
            id = "x",
            method = :GET,
            path = "nope",
        )
        @test_throws ArgumentError OpenAPI.Operation(;
            id = "x",
            method = :GET,
            path = "/a/{b}",
        )
        @test_throws ArgumentError OpenAPI.Operation(;
            id = "x",
            method = :GET,
            path = "/a",
            params = [OpenAPI.Param("b", :path, Int)],
        )
        @test_throws ArgumentError OpenAPI.Param("x", :header)
        @test_throws ArgumentError OpenAPI.Param("x", :path; required = false)
    end

    @testset "read & validate" begin
        # JSON string round trip
        doc2 = OpenAPI.read(JSON.json(doc))
        @test doc2["info"]["title"] == "Test API"
        @test doc2["paths"]["/w/{id}"]["get"]["operationId"] == "getwidget"

        # file round trip
        dir = mktempdir()
        file = joinpath(dir, "api.json")
        write(file, JSON.json(doc; pretty = 2))
        @test OpenAPI.read(file)["info"]["version"] == "1.2.3"

        @test_throws ArgumentError OpenAPI.read("""{"openapi": "2.0", "info": {}}""")
        @test_throws ArgumentError OpenAPI.read("""{"openapi": "3.1.0"}""")
        @test_throws ArgumentError OpenAPI.read("definitely not a document")
        response_optional = OpenAPI.obj(
            "openapi" => "3.2.0",
            "info" => OpenAPI.obj("title" => "t", "version" => "1"),
            "paths" => OpenAPI.obj("/x" => OpenAPI.obj("get" => OpenAPI.obj())),
        )
        @test OpenAPI.validate(response_optional) === response_optional
        error = @test_throws ArgumentError OpenAPI.validate(
            OpenAPI.obj(
                "openapi" => "3.1.0",
                "info" => OpenAPI.obj("title" => "t", "version" => "1"),
                "paths" => OpenAPI.obj("/x" => OpenAPI.obj("get" => OpenAPI.obj())),
            ),
        )
        @test occursin("responses", sprint(showerror, error.value))
    end

    @testset "client generation (static)" begin
        src = OpenAPI.client(doc; name = "TestClient")
        @test occursin("module TestClient", src)
        host = Module(:TestClientHost)
        Base.include_string(host, src, "TestClient.jl")
        C = Base.invokelatest(getfield, host, :TestClient)

        @test C.SERVER[] == "http://api.example"
        for f in (:getwidget, :neworder, :rmorder, :getwidget_2, :server!, :authorization!)
            @test isdefined(C, f)
        end
        # generated structs mirror the schemas
        @test fieldnames(C.TWidget) == (:id, :tags)
        @test fieldtype(C.TWidget, :id) == Int64
        @test fieldtype(C.TWidget, :tags) == Vector{String}
        @test fieldtype(C.TOrder, :note) == Union{C.Absent,Nothing,String}
        @test fieldtype(C.TOrder, :placed) == Dates.Date
        @test fieldtype(C.TOrder, :widget) == C.TWidget

        # required query params are required keywords; optional default to nothing
        m = only(methods(C.getwidget))
        @test Base.kwarg_decl(m) isa Vector
        @test :owner in Base.kwarg_decl(m)
    end

end # @testset "OpenAPI"

include("schema_engine/resources.jl")
include("schema_engine/compiled.jl")
include("schema_engine/rebase.jl")
if get(ENV, "OPENAPI_SCHEMA_SUITE", "") == "all"
    include("schema_engine/official.jl")
end
include("normalization.jl")
include("models.jl")
include("discriminators.jl")
include("references.jl")
include("semantics.jl")
include("runtime.jl")
include("runtime_integration.jl")
include("servergen.jl")
include("trim_compile_tests.jl")
if haskey(ENV, "OPENAPI_CORPUS_TESTS")
    include("corpus.jl")
end
