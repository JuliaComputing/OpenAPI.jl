"""
OpenAPI.jl: build OpenAPI documents from declared endpoints, and generate Julia
clients from OpenAPI documents.

Three pieces:

1. **Document generation** — describe endpoints as [`OpenAPI.Operation`](@ref)s
   and get a valid OpenAPI 3.2.0 document. Framework packages can add router
   adapters through the `operations` and `register!` extension seams.
2. **Client generation** — [`OpenAPI.client`](@ref) turns an OpenAPI 3.0, 3.1,
   or 3.2 document (built in-process, read from JSON or YAML, or fetched from a
   running app) into a deterministic single-file Julia client. Generated
   modules use HTTP.jl for transport and JSON.jl plus OpenAPI's provisional
   schema engine for typed, validated request and response handling.
3. **Server generation** — [`OpenAPI.server`](@ref) turns the same documents
   into a deterministic single-file server-stub module: typed request decoding,
   response validation and encoding, and a `register!(router, impl)` entry
   point that mounts handler functions you implement onto a framework router
   (`HTTP.Router` through the HTTP extension; other frameworks through the
   [`OpenAPI.server_source`](@ref) seam).
"""
module OpenAPI

using Dates, JSON, SHA
import YAML

const OPENAPI_VERSION = "3.2.0"

include("schema_engine/SchemaEngine.jl")

include("schemas.jl")
include("document.jl")
include("diagnostics.jl")
include("source_locations.jl")
include("loading.jl")
include("references.jl")
include("normalize.jl")
include("planning.jl")
include("read.jl")
include("runtime.jl")
include("client.jl")
include("servergen.jl")

# ── extension seams ─────────────────────────────────────────────────────────

"""
    OpenAPI.register!(integration; kwargs...)

Extension seam for downstream server frameworks that expose a generated OpenAPI
document. OpenAPI.jl itself does not depend on a server framework.
"""
function register! end

"""Extension seam for converting framework routes to `Vector{Operation}`."""
function operations end

# implemented by OpenAPIHTTPExt (loaded with the HTTP package)
function fetchurl end
function fetchresource end

public ClientPlan,
    Diagnostic,
    DocumentVersion,
    NormalizedAPI,
    OpenAPIError,
    Operation,
    Param,
    Resources,
    SchemaEngine,
    SchemaRegistry,
    ServerPlan,
    SourceDocument,
    SourceLocation,
    SourcePosition,
    check,
    client,
    document,
    load,
    location,
    normalize,
    oas_family,
    obj,
    operations,
    parse,
    plan,
    read,
    register!,
    schemaof,
    server,
    server_source,
    serverplan,
    validate

end # module
