import ZipFile

const OPENAPI_SCHEMA_SUITE_REVISION = "be54236db6e8e6bb2e098ed16fb4c61e73f5a9ac"
const OPENAPI_SCHEMA_SUITE_URL =
    "https://github.com/json-schema-org/JSON-Schema-Test-Suite/archive/$(OPENAPI_SCHEMA_SUITE_REVISION).zip"

function _official_schema_suite_dir()
    directory = mktempdir()
    archive = joinpath(directory, "suite.zip")
    destination = joinpath(directory, "suite")
    mkpath(destination)
    Downloads.download(OPENAPI_SCHEMA_SUITE_URL, archive)
    reader = ZipFile.Reader(archive)
    try
        for entry in reader.files
            relative = normpath(entry.name)
            (relative == ".." || startswith(relative, ".." * Base.Filesystem.path_separator)) &&
                error("schema suite archive contains an unsafe path")
            target = joinpath(destination, relative)
            if endswith(entry.name, "/")
                mkpath(target)
            else
                mkpath(dirname(target))
                write(target, read(entry))
            end
        end
    finally
        close(reader)
    end
    return joinpath(
        destination,
        "JSON-Schema-Test-Suite-$(OPENAPI_SCHEMA_SUITE_REVISION)",
        "tests",
    )
end

function _test_compiled_draft(directory, retriever, schema_dialect, base_uri)
    files = sort(filter(name -> endswith(name, ".json"), readdir(directory)))
    @testset "$(file)" for file in files
        groups = JSON.parsefile(joinpath(directory, file))
        @testset "$(group["description"])" for group in groups
            compiled = SchemaEngine.CompiledSchema(
                group["schema"];
                dialect = schema_dialect,
                base_uri,
                retriever,
            )
            @testset "$(case["description"])" for case in group["tests"]
                valid = case["valid"]
                @test isvalid(compiled, case["data"]) == valid
                @test isempty(
                    SchemaEngine.validate(
                        compiled,
                        case["data"];
                        fail_fast = false,
                    ),
                ) == valid
            end
        end
    end
end

@testset "Official JSON Schema suite" begin
    suite = _official_schema_suite_dir()
    remotes = normpath(suite, "..", "remotes")
    retriever = SuiteRetriever(remotes)
    for (name, schema_dialect) in (
        "draft2020-12" => SchemaEngine.DRAFT202012,
        "draft2019-09" => SchemaEngine.DRAFT201909,
        "draft7" => SchemaEngine.DRAFT7,
        "draft6" => SchemaEngine.DRAFT6,
        "draft4" => SchemaEngine.DRAFT4,
    )
        @testset "$name" begin
            _test_compiled_draft(
                joinpath(suite, name),
                retriever,
                schema_dialect,
                "http://localhost:1234/$name/root",
            )
        end
    end
end
