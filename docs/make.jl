import Pkg
Pkg.add("Documenter")

using Documenter
using OpenAPI

makedocs(
    sitename = "OpenAPI.jl",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true"
    ),
    pages = [
        "Home" => "index.md",
        "User Guide" => "userguide.md",
        "Reference" => "reference.md",
        "Tools" => "tools.md",
        "TODO" => "todo.md",
    ],
)

deploydocs(
    repo = "github.com/JuliaComputing/OpenAPI.jl.git",
    push_preview = true,
)