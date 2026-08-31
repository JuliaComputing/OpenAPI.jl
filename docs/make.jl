# Build locally with:
#   julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
#   julia --project=docs docs/make.jl

using Documenter
using OpenAPI

# MIGRATION.md at the repository root is the single source for migration
# guidance; mirror it into the built site so the two cannot drift.
cp(
    normpath(@__DIR__, "..", "MIGRATION.md"),
    joinpath(@__DIR__, "src", "migration.md");
    force = true,
)

makedocs(
    sitename = "OpenAPI.jl",
    modules = [OpenAPI],
    checkdocs = :public,
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://juliacomputing.github.io/OpenAPI.jl",
        edit_link = "main",
    ),
    pages = [
        "Home" => "index.md",
        "Migrating from 0.2.x" => "migration.md",
        "Manual" => [
            "Generating clients" => "clients.md",
            "Streaming and codecs" => "streaming.md",
            "Security" => "security.md",
            "Generating servers" => "servers.md",
            "Documents from Julia code" => "documents.md",
            "Pipeline and diagnostics" => "pipeline.md",
            "Generated models" => "models.md",
            "Generated modules and the runtime contract" => "artifacts.md",
            "Support boundary" => "boundary.md",
        ],
        "API reference" => "reference.md",
    ],
)

deploydocs(
    repo = "github.com/JuliaComputing/OpenAPI.jl.git",
    devbranch = "main",
    push_preview = true,
)
