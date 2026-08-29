const Resources = SchemaEngine.Resources

@testset "JSON Pointer" begin
    pointer = Resources.JSONPointer("/a~1b/m~0n//0")
    @test collect(pointer) == ["a/b", "m~n", "", "0"]
    @test string(pointer) == "/a~1b/m~0n//0"
    @test string(Resources.JSONPointer() / "a/b" / "m~n") == "/a~1b/m~0n"
    @test isempty(Resources.JSONPointer(""))
    @test_throws Resources.PointerError Resources.JSONPointer("a")
    @test_throws Resources.PointerError Resources.JSONPointer("/~")
    @test_throws Resources.PointerError Resources.JSONPointer("/~2")

    document = Dict(
        "a/b" => Dict("m~n" => 1),
        "array" => Any["zero", Dict("" => "empty")],
    )
    @test Resources.resolve(document, Resources.JSONPointer("/a~1b/m~0n")) == 1
    @test Resources.resolve(document, Resources.JSONPointer("/array/0")) ==
          "zero"
    @test Resources.resolve(document, Resources.JSONPointer("/array/1/")) ==
          "empty"
    @test collect(Resources.JSONPointer("/")) == [""]
    @test_throws Resources.PointerError Resources.resolve(
        document,
        Resources.JSONPointer("/array/01"),
    )
    @test_throws Resources.PointerError Resources.resolve(
        document,
        Resources.JSONPointer("/array/+1"),
    )
    @test_throws Resources.PointerError Resources.resolve(
        document,
        Resources.JSONPointer("/array/ 1"),
    )
    @test_throws Resources.PointerError Resources.resolve(
        document,
        Resources.JSONPointer("/array/-"),
    )
    @test_throws Resources.PointerError Resources.resolve(
        document,
        Resources.JSONPointer("/array/2"),
    )
    @test_throws Resources.PointerError Resources.resolve(
        document,
        Resources.JSONPointer("/missing"),
    )
end

@testset "Frozen JSON values" begin
    source = Dict("object" => Dict("value" => 1), "array" => Any[true, nothing])
    frozen = Resources.freeze(source)
    source["object"]["value"] = 2
    push!(source["array"], false)
    @test frozen isa Resources.FrozenObject
    @test frozen["object"] isa Resources.FrozenObject
    @test frozen["array"] isa Resources.FrozenArray
    @test frozen["object"]["value"] == 1
    @test frozen["array"] == Any[true, nothing]
    @test_throws MethodError setindex!(frozen, 2, "object")
    @test_throws Base.CanonicalIndexError setindex!(frozen["array"], false, 1)
    @test Resources.freeze(frozen) === frozen
    @test_throws ArgumentError Resources.freeze(Dict(1 => "invalid"))
end

@testset "Resource identifiers and references" begin
    id = Resources.ResourceId("HTTPS://EXAMPLE.COM:443/schemas/root.json")
    @test string(id) == "https://example.com/schemas/root.json"
    @test_throws ArgumentError Resources.ResourceId(
        "https://example.com/root#part",
    )

    reference = Resources.Reference(id, "../common.json#/a%20b/~0value")
    @test string(reference.resource) == "https://example.com/common.json"
    @test reference.fragment isa Resources.PointerFragment
    @test collect(reference.fragment.pointer) == ["a b", "~value"]

    anchor = Resources.Reference(id, "#named%2Danchor")
    @test anchor.fragment == Resources.AnchorFragment("named-anchor")
    @test Resources.Reference(id, "#").fragment isa Resources.RootFragment
    @test Resources.ResourceId("https://EXAMPLE.com:443/a/../b/%7euser") ==
          Resources.ResourceId("https://example.com/b/~user")
    @test Resources.ResourceId("https://example.com") ==
          Resources.ResourceId("https://example.com/")
    @test Resources.ResourceId("https://example.com/%2f") ==
          Resources.ResourceId("https://example.com/%2F")
    @test string(Resources.ResourceId("urn:openapi:inline")) ==
          "urn:openapi:inline"
    @test string(Resources.ResourceId("MAILTO:user@example.com")) ==
          "mailto:user@example.com"
    @test string(Resources.ResourceId("custom://EXAMPLE.com/schema")) ==
          "custom://example.com/schema"
    @test string(Resources.ResourceId("https://[::1]:443/schema")) ==
          "https://[::1]/schema"
    @test Resources.ResourceId(
        string(Resources.ResourceId("urn:test:a%2fb")),
    ) == Resources.ResourceId("urn:test:a%2Fb")
end

@testset "Resource registry" begin
    retrieval = Resources.ResourceId("file:///tmp/schema.json")
    canonical = Resources.ResourceId("https://example.com/schema")
    document = Dict("defs" => Dict("thing" => Dict("type" => "string")))
    item_pointer = Resources.JSONPointer("/defs/thing")
    item = Resources.Resource(
        canonical,
        document;
        retrieval,
        media_type = "application/schema+json",
    )
    registry = Resources.Registry()
    @test isempty(registry)
    Resources.register!(registry, item; anchors = ["thing" => item_pointer])
    @test length(registry) == 1
    @test !isempty(Resources.freeze(registry))

    by_pointer = Resources.resolve(
        registry,
        Resources.Reference(retrieval, "#/defs/thing"),
    )
    @test by_pointer.id == Resources.NodeId(canonical, item_pointer)
    @test by_pointer.value["type"] == "string"

    by_anchor =
        Resources.resolve(registry, Resources.Reference(canonical, "#thing"))
    @test by_anchor.id == by_pointer.id
    @test by_anchor.value === by_pointer.value
    dynamic = Resources.register_anchor!(
        registry,
        canonical,
        "dynamic",
        item_pointer;
        dynamic = true,
    )
    @test registry.dynamic_anchors[(canonical, "dynamic")] == dynamic
    @test_throws Resources.MissingAnchorError Resources.resolve(
        registry,
        Resources.Reference(canonical, "#missing"),
    )
    @test_throws Resources.MissingResourceError Resources.resource(
        registry,
        Resources.ResourceId("https://example.com/missing"),
    )
    @test_throws Resources.DuplicateResourceError Resources.register!(
        registry,
        item,
    )

    invalid_registry = Resources.Registry()
    @test_throws Resources.PointerError Resources.register!(
        invalid_registry,
        item;
        anchors = ["invalid" => Resources.JSONPointer("/missing")],
    )
    @test isempty(invalid_registry.resources)
    @test isempty(invalid_registry.aliases)
    @test isempty(invalid_registry.anchors)
    @test isempty(invalid_registry.dynamic_anchors)
end

@testset "Bounded resource retrieval" begin
    id = Resources.ResourceId("https://example.com/schema.json")
    memory =
        Resources.MemoryRetriever(Dict(string(id) => "{\"type\":\"string\"}"))
    retrieved = Resources.retrieve(memory, id)
    @test String(copy(retrieved.bytes)) == "{\"type\":\"string\"}"
    retrieved.bytes[1] = UInt8('!')
    @test String(copy(Resources.retrieve(memory, id).bytes)) ==
          "{\"type\":\"string\"}"
    stored = Resources.RetrievedResource(id, Vector{UInt8}(codeunits("{}")))
    aliased = Resources.MemoryRetriever(Dict(id => stored))
    stored.bytes[1] = UInt8('!')
    @test String(Resources.retrieve(aliased, id).bytes) == "{}"
    @test_throws Resources.RetrievalError Resources.retrieve(
        Resources.DisabledRetriever(),
        id,
    )

    root = mktempdir()
    file = joinpath(root, "schema.json")
    write(file, "{}")
    file_id = Resources.ResourceId("file://" * file)
    @test String(
        copy(Resources.retrieve(Resources.FileRetriever(root), file_id).bytes),
    ) == "{}"
    @test_throws Resources.RetrievalError Resources.retrieve(
        Resources.FileRetriever(root; max_bytes = 1),
        file_id,
    )
    outside = tempname()
    write(outside, "{}")
    outside_id = Resources.ResourceId("file://" * outside)
    @test_throws Resources.RetrievalError Resources.retrieve(
        Resources.FileRetriever(root),
        outside_id,
    )
    if Sys.isunix()
        link = joinpath(root, "linked-schema.json")
        symlink(outside, link)
        @test_throws Resources.RetrievalError Resources.retrieve(
            Resources.FileRetriever(root),
            Resources.ResourceId("file://" * link),
        )
    end
    missing_id =
        Resources.ResourceId("file://" * joinpath(root, "missing.json"))
    @test_throws Resources.RetrievalError Resources.retrieve(
        Resources.FileRetriever(root),
        missing_id,
    )
    directory_id = Resources.ResourceId("file://" * root)
    @test_throws Resources.RetrievalError Resources.retrieve(
        Resources.FileRetriever(root),
        directory_id,
    )
end
