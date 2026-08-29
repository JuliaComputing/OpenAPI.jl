import Downloads
import SHA

const OPENAPI_CORPUS_CASES = (
    (
        name = "Petstore",
        url = "https://raw.githubusercontent.com/swagger-api/swagger-petstore/8f0dd286987880b4af7bce552aca3813166f3049/src/main/resources/openapi.yaml",
        sha256 = "0d810997f6409d5cff6f0cf2c1466814ba52250a784cd841cacb93514c7a8502",
        strict = true,
        operations = 19,
        schemas = 6,
        models = 10,
        warning_codes = Set{Symbol}(),
        large = false,
    ),
    (
        name = "Discord",
        url = "https://raw.githubusercontent.com/discord/discord-api-spec/74fda0fad044407ea280043a03ffc9bc64c4e49e/specs/openapi.json",
        sha256 = "8c1d0707ccdf8e380a86dfba04058820a66435c1b69d5ed82e04dd8c0520dd73",
        strict = true,
        operations = 242,
        schemas = 539,
        models = 952,
        warning_codes = Set{Symbol}(),
        large = false,
    ),
    (
        name = "Stripe",
        url = "https://raw.githubusercontent.com/stripe/openapi/8da624f9b4f65178eb2e2c2b6fc80162a6c0dceb/latest/openapi.spec3.json",
        sha256 = "6f3623aece40493eec2f5e3e631219f8c6bffa4f477e3807a4bf785ad377f237",
        strict = false,
        operations = 621,
        schemas = 1596,
        models = 13406,
        warning_codes = Set([
            :invalid_deep_object_schema,
            :legacy_nullable_without_type,
        ]),
        large = true,
    ),
    (
        name = "GitHub",
        url = "https://raw.githubusercontent.com/github/rest-api-description/5e28810649ba41b5483753ba74f976f83856a504/descriptions/api.github.com/api.github.com.json",
        sha256 = "04a2597b999c6d13d5269334d0c105252b8b58321c9fcdade40ddc50302220fb",
        strict = false,
        operations = 1216,
        schemas = 967,
        models = 7125,
        warning_codes = Set([
            :ambiguous_path_template,
            :ignored_content_type_header,
            :legacy_nullable_without_type,
        ]),
        large = true,
    ),
)

function run_corpus_case(case)
    started = time()
    directory = mktempdir()
    path = joinpath(directory, lowercase(case.name) * ".openapi")
    Downloads.download(case.url, path)
    @test bytes2hex(SHA.sha256(read(path))) == case.sha256
    downloaded = time()

    # Use the public resource ceilings. This keeps the corpus test honest for
    # callers that point OpenAPI.jl at these documents without tuning options.
    api = OpenAPI.normalize(path; strict = case.strict)
    @test length(api.operations) == case.operations
    @test length(api.schemas) == case.schemas
    normalized = time()

    plan = OpenAPI.plan(api; name = case.name * "CorpusClient", strict = case.strict)
    @test length(plan.operations) == case.operations
    @test length(plan.models) == case.models
    @test Set(
        diagnostic.code for diagnostic in plan.diagnostics if
        diagnostic.severity === :warning
    ) == case.warning_codes
    planned = time()

    source = OpenAPI.client(plan)
    generated_at = time()
    parsed = Meta.parseall(source; filename = case.name * "CorpusClient.jl")
    @test parsed isa Expr
    parsed = nothing
    case.large && GC.gc(false)
    host = Module(Symbol(case.name, :CorpusHost))
    Base.include_string(host, source, case.name * "CorpusClient.jl")
    generated = Base.invokelatest(
        getfield,
        host,
        Symbol(case.name, :CorpusClient),
    )
    operation = Base.invokelatest(
        getfield,
        generated,
        Symbol(first(plan.operations).name),
    )
    @test operation isa Function
    finished = time()
    @info "OpenAPI corpus case compiled" name = case.name download_seconds =
        round(downloaded - started; digits = 2) normalize_seconds =
        round(normalized - downloaded; digits = 2) plan_seconds =
        round(planned - normalized; digits = 2) generate_seconds =
        round(generated_at - planned; digits = 2) compile_seconds =
        round(finished - generated_at; digits = 2) source_megabytes =
        round(sizeof(source) / 1024^2; digits = 2)
    return nothing
end

@testset "pinned real-world OpenAPI corpus" begin
    mode = lowercase(get(ENV, "OPENAPI_CORPUS_TESTS", "small"))
    mode in ("small", "all") ||
        throw(ArgumentError("OPENAPI_CORPUS_TESTS must be `small` or `all`"))
    selected = lowercase(strip(get(ENV, "OPENAPI_CORPUS_CASE", "")))
    names = Set(lowercase(case.name) for case in OPENAPI_CORPUS_CASES)
    isempty(selected) || selected in names || throw(
        ArgumentError(
            "OPENAPI_CORPUS_CASE must name one of " *
            join(sort!(collect(names)), ", "),
        ),
    )
    for case in OPENAPI_CORPUS_CASES
        isempty(selected) || lowercase(case.name) == selected || continue
        isempty(selected) && mode == "small" && case.large && continue
        @testset "$(case.name)" begin
            run_corpus_case(case)
        end
    end
end
