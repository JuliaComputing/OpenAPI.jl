"""
    OpenAPI.read(source; options...) -> AbstractDict

Read a JSON or YAML OpenAPI 3.0, 3.1, or 3.2 document. `source` may be inline
text, a local file, or an HTTP(S) URL when HTTP.jl is loaded. The returned
object is recursively read-only.

Use [`OpenAPI.load`](@ref) when source identity, format, and version metadata
are also needed.
"""
function read(source::AbstractString; kwargs...)
    try
        return load(source; kwargs...).resource.contents
    catch error
        error isa OpenAPIError || rethrow()
        throw(ArgumentError(sprint(showerror, error)))
    end
end

"""
    OpenAPI.parse(source; options...) -> AbstractDict

Behaves exactly like [`OpenAPI.read`](@ref); kept for callers that expect a
`parse` name in the namespace.
"""
function parse(source::AbstractString; kwargs...)
    try
        return load(source; kwargs...).resource.contents
    catch error
        error isa OpenAPIError || rethrow()
        throw(ArgumentError(sprint(showerror, error)))
    end
end

"""
    OpenAPI.validate(document) -> document

Validate an in-memory document against the official structural schema for its
declared OAS 3.0, 3.1, or 3.2 minor line. This compatibility API returns the
original object. Use [`OpenAPI.check`](@ref) to collect structured diagnostics.
"""
function validate(document::AbstractDict; kwargs...)
    try
        normalize(document; kwargs...)
    catch error
        error isa OpenAPIError || rethrow()
        throw(ArgumentError(sprint(showerror, error)))
    end
    return document
end
