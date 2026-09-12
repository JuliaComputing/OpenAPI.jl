@testset "Compiled schema graph rebasing" begin
    R = SchemaEngine.Resources
    root_id = R.ResourceId("file:///private/build/openapi.json")
    external_id = R.ResourceId("file:///private/build/common.json")
    root = R.Resource(
        root_id,
        Dict(
            "schemas" => Dict(
                "Node" => Dict(
                    "\$id" => "models/node.json",
                    "\$dynamicAnchor" => "node",
                    "type" => "object",
                    "required" => ["value"],
                    "properties" => Dict(
                        "value" => Dict("type" => "string"),
                        "child" => Dict("\$dynamicRef" => "#node"),
                    ),
                    "additionalProperties" => false,
                ),
                "Count" => Dict(
                    "\$ref" => "./common.json#/\$defs/Count",
                ),
            ),
        ),
    )
    external = R.Resource(
        external_id,
        Dict("\$defs" => Dict("Count" => Dict("type" => "integer"))),
    )
    node_root = R.NodeId(root_id, R.JSONPointer("/schemas/Node"))
    count_root = R.NodeId(root_id, R.JSONPointer("/schemas/Count"))
    graph = SchemaEngine.CompiledSchemas(
        [root, external],
        [node_root, count_root];
        dialect = SchemaEngine.DRAFT202012,
    )
    ids = sort(
        collect(keys(getfield(graph.template.registry, :resources)));
        by = string,
    )
    mapping = Dict(
        id => R.ResourceId("https://portable.invalid/schema/$index.json") for
        (index, id) in enumerate(ids)
    )
    rebased = SchemaEngine.rebase(graph, mapping)

    samples = Any[
        Dict("value" => "root"),
        Dict("value" => "root", "child" => Dict("value" => "leaf")),
        Dict("value" => "root", "child" => Dict("value" => 1)),
    ]
    original_node = SchemaEngine.select(graph, node_root)
    rebased_node = SchemaEngine.select(rebased, node_root)
    @test [isvalid(original_node, value) for value in samples] ==
          [isvalid(rebased_node, value) for value in samples]
    @test isvalid(SchemaEngine.select(rebased, count_root), 3)
    @test !isvalid(SchemaEngine.select(rebased, count_root), "3")
    @test SchemaEngine.subschema(graph.template, original_node.root).root ==
          original_node.root

    serialized = join(
        JSON.json(resource.contents) * string(resource.id) for
        resource in values(getfield(rebased.template.registry, :resources))
    )
    @test !occursin("file:///private/build", serialized)
    @test occursin("https://portable.invalid/schema/", serialized)

    recursive_id = R.ResourceId("file:///private/build/recursive.json")
    recursive_root = R.NodeId(recursive_id, R.JSONPointer())
    recursive_resource = R.Resource(
        recursive_id,
        Dict(
            "\$recursiveAnchor" => true,
            "type" => "object",
            "properties" => Dict(
                "child" => Dict("\$recursiveRef" => "#"),
            ),
            "additionalProperties" => false,
        ),
    )
    recursive = SchemaEngine.CompiledSchemas(
        [recursive_resource],
        [recursive_root];
        dialect = SchemaEngine.DRAFT201909,
    )
    recursive_mapping = Dict(
        only(keys(getfield(recursive.template.registry, :resources))) =>
            R.ResourceId("https://portable.invalid/recursive.json"),
    )
    portable_recursive = SchemaEngine.rebase(recursive, recursive_mapping)
    recursive_samples = Any[
        Dict(),
        Dict("child" => Dict("child" => Dict())),
        Dict("child" => 1),
    ]
    @test [
        isvalid(SchemaEngine.select(recursive, recursive_root), value) for
        value in recursive_samples
    ] == [
        isvalid(SchemaEngine.select(portable_recursive, recursive_root), value) for
        value in recursive_samples
    ]
end

@testset "Rebasing optional extra references" begin
    R = SchemaEngine.Resources
    root_id = R.ResourceId("file:///private/build/openapi.json")
    common_id = R.ResourceId("file:///private/build/common.json")
    root = R.Resource(
        root_id,
        Dict(
            "schemas" => Dict(
                "Union" => Dict(
                    "oneOf" => Any[Dict("\$ref" => "./common.json#/\$defs/Count")],
                    "x-links" => Dict(
                        "count" => "./common.json#/\$defs/Count",
                        "missing" => "./nothing.json",
                    ),
                ),
            ),
        ),
    )
    common = R.Resource(
        common_id,
        Dict("\$defs" => Dict("Count" => Dict("type" => "integer"))),
    )
    union_root = R.NodeId(root_id, R.JSONPointer("/schemas/Union"))
    links(schema) =
        schema isa AbstractDict && haskey(schema, "x-links") ?
        sort!([("/x-links/" * key, value) for (key, value) in schema["x-links"]]) :
        ()
    graph = SchemaEngine.CompiledSchemas(
        [root, common],
        [union_root];
        dialect = SchemaEngine.DRAFT202012,
        extra_references = links,
    )
    mapping = Dict(
        root_id => R.ResourceId("https://portable.invalid/root.json"),
        common_id => R.ResourceId("https://portable.invalid/common.json"),
    )
    rebased = SchemaEngine.rebase(graph, mapping)
    mapped_union = R.NodeId(mapping[root_id], R.JSONPointer("/schemas/Union"))
    count_node = R.NodeId(mapping[common_id], R.JSONPointer("/\$defs/Count"))

    # Bindings and recorded failures follow the graph onto the new identifiers.
    @test SchemaEngine.reference_target(rebased, mapped_union, "/x-links/count") ==
          count_node
    @test SchemaEngine.reference_target(rebased, mapped_union, "/x-links/missing") ===
          nothing
    failure = SchemaEngine.reference_failure(rebased, mapped_union, "/x-links/missing")
    @test failure isa String
    @test occursin("nothing.json", failure)

    # Serialized resource data uses only replacement identifiers for resolved
    # optional references; unresolved strings are left as written.
    document = R.resource(rebased.template.registry, mapping[root_id]).contents
    rebased_links = document["schemas"]["Union"]["x-links"]
    @test rebased_links["count"] == "https://portable.invalid/common.json#/\$defs/Count"
    @test rebased_links["missing"] == "./nothing.json"
    @test isvalid(SchemaEngine.select(rebased, union_root), 3)
    @test !isvalid(SchemaEngine.select(rebased, union_root), "3")
end
