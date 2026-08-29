"""
Internal JSON Schema resource, compilation, rebasing, and validation support.

This module is isolated from OpenAPI-specific semantics so it can move to
JSONSchema.jl after the implementation and API have hardened. Generated clients
use it through `OpenAPI.SchemaEngine`; it is not a general-purpose exported API.
"""
module SchemaEngine

import JSON
import URIs

include("resources.jl")
include("dialects.jl")
include("issues.jl")
include("compiled.jl")
include("rebase.jl")
include("compiled_validation.jl")

end
