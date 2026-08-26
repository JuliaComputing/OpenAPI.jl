@testset "adversarial schema models" begin
    response(reference) = OpenAPI.obj(
        "description" => "value",
        "content" => OpenAPI.obj(
            "application/json" => OpenAPI.obj(
                "schema" => OpenAPI.obj("\$ref" => reference),
            ),
        ),
    )
    paths = OpenAPI.obj()
    for name in (
        "TrueValue",
        "FalseValue",
        "ConstSeven",
        "ForbiddenString",
        "MixedEnum",
        "AmbiguousOne",
        "AnyChoice",
        "NullableValue",
        "Record",
        "ClosedRecord",
        "ConditionalRecord",
        "NumericChoice",
    )
        id = lowercase(name)
        paths["/" * id] = OpenAPI.obj(
            "get" => OpenAPI.obj(
                "operationId" => id,
                "responses" => OpenAPI.obj(
                    "200" => response("#/components/schemas/" * name),
                ),
            ),
        )
    end
    document = minimal_openapi("3.1.1", paths)
    document["components"] = OpenAPI.obj(
        "schemas" => OpenAPI.obj(
            "TrueValue" => true,
            "FalseValue" => false,
            "ConstSeven" => OpenAPI.obj("const" => 7),
            "ForbiddenString" => OpenAPI.obj(
                "not" => OpenAPI.obj("type" => "string"),
            ),
            "MixedEnum" => OpenAPI.obj(
                "enum" => Any["x", 2, true, nothing],
            ),
            "AmbiguousOne" => OpenAPI.obj(
                "oneOf" => Any[
                    OpenAPI.obj("type" => "integer"),
                    OpenAPI.obj("type" => "number"),
                ],
            ),
            "AnyChoice" => OpenAPI.obj(
                "anyOf" => Any[
                    OpenAPI.obj("type" => "integer"),
                    OpenAPI.obj("type" => "string"),
                ],
            ),
            "NullableValue" => OpenAPI.obj(
                "type" => ["string", "null"],
            ),
            "NumericChoice" => OpenAPI.obj(
                "type" => ["integer", "number"],
            ),
            "Record" => OpenAPI.obj(
                "type" => "object",
                "required" => ["fixed"],
                "properties" => OpenAPI.obj(
                    "fixed" => OpenAPI.obj("const" => "yes"),
                    "annotated-default" => OpenAPI.obj(
                        "type" => "string",
                        "default" => "server-side",
                    ),
                ),
                "propertyNames" => OpenAPI.obj("pattern" => "^[a-z-]+\$"),
                "additionalProperties" => OpenAPI.obj("type" => "integer"),
            ),
            "ClosedRecord" => OpenAPI.obj(
                "type" => "object",
                "properties" => OpenAPI.obj(
                    "known" => OpenAPI.obj("type" => "string"),
                ),
                "additionalProperties" => false,
            ),
            "ConditionalRecord" => OpenAPI.obj(
                "type" => "object",
                "required" => ["kind"],
                "properties" => OpenAPI.obj(
                    "kind" => OpenAPI.obj("type" => "string"),
                    "detail" => OpenAPI.obj("type" => "string"),
                ),
                "if" => OpenAPI.obj(
                    "properties" => OpenAPI.obj(
                        "kind" => OpenAPI.obj("const" => "detailed"),
                    ),
                ),
                "then" => OpenAPI.obj("required" => ["detail"]),
                "additionalProperties" => false,
            ),
            # These names would otherwise collide with Julia bindings or each
            # other after identifier normalization.
            "String" => OpenAPI.obj(
                "type" => "object",
                "additionalProperties" => false,
            ),
            "module" => OpenAPI.obj("enum" => ["value"]),
            "123-item" => OpenAPI.obj(
                "type" => "object",
                "additionalProperties" => false,
            ),
            "-" => OpenAPI.obj(
                "type" => "object",
                "additionalProperties" => false,
            ),
            "_" => OpenAPI.obj(
                "type" => "object",
                "additionalProperties" => false,
            ),
            "." => OpenAPI.obj(
                "type" => "object",
                "additionalProperties" => false,
            ),
        ),
    )

    plan = OpenAPI.plan(document; name = "SchemaEdgeClient")
    names = Set(model.name for model in plan.models)
    @test "StringModel" in names
    @test "ModuleModel" in names
    @test "Model123Item" in names
    @test "Model" in names
    @test "Model2" in names
    @test "Model3" in names
    @test length(names) == length(plan.models)

    source = OpenAPI.client(plan)
    host = Module(:SchemaEdgeClientHost)
    Base.include_string(host, source, "SchemaEdgeClient.jl")
    C = Base.invokelatest(getfield, host, :SchemaEdgeClient)
    call(name, args...) = Base.invokelatest(getfield(C, name), args...)

    media(name) = only(only(getfield(C, Symbol("_OP_", name)).responses).media)
    @test call(:_schema_valid, C._SPEC, media("truevalue").schema, Dict("anything" => 1))
    @test !call(:_schema_valid, C._SPEC, media("falsevalue").schema, nothing)
    @test call(:_schema_valid, C._SPEC, media("constseven").schema, 7)
    @test !call(:_schema_valid, C._SPEC, media("constseven").schema, 8)
    @test call(:_schema_valid, C._SPEC, media("forbiddenstring").schema, 1)
    @test !call(:_schema_valid, C._SPEC, media("forbiddenstring").schema, "no")

    @test call(:_decode, C.MixedEnum, "x").value == "x"
    @test call(:_decode, C.MixedEnum, nothing).value === nothing
    @test_throws C.SchemaValidationError call(:_decode, C.MixedEnum, "bad")
    @test_throws C.SchemaValidationError call(:_decode, C.AmbiguousOne, 1)
    @test call(:_decode, C.AnyChoice, 2).value == 2
    @test call(:_decode, C.NullableValue, nothing) === nothing
    @test call(:_decode, C.NullableValue, "ok") == "ok"
    @test call(:_decode, C.NumericChoice, 3) === Int64(3)
    @test call(:_decode, C.NumericChoice, 3.5) === 3.5

    record = call(
        :_decode,
        C.Record,
        Dict("fixed" => "yes", "extra" => 3),
    )
    @test record.fixed == "yes"
    @test record.annotated_default isa C.Absent
    @test record.additional_properties == Dict("extra" => 3)
    @test call(:_encode, record) == Dict("fixed" => "yes", "extra" => 3)
    @test_throws C.SchemaValidationError call(
        :_decode,
        C.Record,
        Dict("fixed" => "yes", "extra" => "wrong"),
    )
    @test_throws C.SchemaValidationError call(
        :_decode,
        C.Record,
        Dict("fixed" => "yes", "BAD" => 1),
    )
    @test_throws C.SchemaValidationError call(
        :_decode,
        C.ClosedRecord,
        Dict("unknown" => 1),
    )
    @test_throws C.SchemaValidationError call(
        :_decode,
        C.ConditionalRecord,
        Dict("kind" => "detailed"),
    )
    @test call(
        :_decode,
        C.ConditionalRecord,
        Dict("kind" => "simple"),
    ).kind == "simple"

    conflicting = Base.invokelatest(
        C.Record;
        fixed = "yes",
        additional_properties = Dict("fixed" => 1),
    )
    @test_throws ArgumentError call(:_encode, conflicting)
end

@testset "schema descriptions follow reference semantics" begin
    function referenced_field_description(version, property)
        document = minimal_openapi(version, OpenAPI.obj())
        document["components"] = OpenAPI.obj(
            "schemas" => OpenAPI.obj(
                "BaseDescription" => OpenAPI.obj(
                    "type" => "string",
                    "description" => "Description from the reference target.",
                ),
                "IntermediateDescription" => OpenAPI.obj(
                    "\$ref" => "#/components/schemas/BaseDescription",
                ),
                "DescriptionContainer" => OpenAPI.obj(
                    "type" => "object",
                    "properties" => OpenAPI.obj("value" => property),
                ),
            ),
        )
        generated = OpenAPI.plan(document; name = "DescriptionClient")
        model = only(filter(
            item -> item.name == "DescriptionContainer",
            generated.models,
        ))
        return only(model.fields).description
    end

    local_description = OpenAPI.obj(
        "\$ref" => "#/components/schemas/IntermediateDescription",
        "description" => "Description next to the reference.",
    )
    @test referenced_field_description("3.0.3", local_description) ==
          "Description from the reference target."
    @test referenced_field_description("3.1.1", local_description) ==
          "Description next to the reference."
    @test referenced_field_description(
        "3.1.1",
        OpenAPI.obj(
            "\$ref" => "#/components/schemas/IntermediateDescription",
            "maxLength" => 64,
        ),
    ) == "Description from the reference target."
    @test referenced_field_description(
        "3.1.1",
        OpenAPI.obj(
            "\$ref" => "#/components/schemas/IntermediateDescription",
            "description" => "",
        ),
    ) === nothing
end
