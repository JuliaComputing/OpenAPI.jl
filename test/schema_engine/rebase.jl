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
