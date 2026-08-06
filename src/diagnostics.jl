const Resources = SchemaEngine.Resources

"""A one-based source position when a parser can report one."""
struct SourcePosition
    line::Int
    column::Int
    byte::Int
end

"""A resource and JSON Pointer location inside an OpenAPI description."""
struct SourceLocation
    resource::Resources.ResourceId
    pointer::Resources.JSONPointer
    position::Union{Nothing,SourcePosition}
end

function SourceLocation(
    resource::Resources.ResourceId,
    pointer::Resources.JSONPointer = Resources.JSONPointer();
    position::Union{Nothing,SourcePosition} = nothing,
)
    return SourceLocation(resource, pointer, position)
end

function Base.show(io::IO, location::SourceLocation)
    pointer = string(location.pointer)
    print(io, string(location.resource))
    isempty(pointer) || print(io, '#', pointer)
    if location.position !== nothing
        position = location.position
        print(io, ':', position.line, ':', position.column)
    end
    return
end

"""One stable, machine-readable OpenAPI diagnostic."""
struct Diagnostic
    severity::Symbol
    code::Symbol
    message::String
    location::SourceLocation
    context::Tuple{Vararg{Pair{String,String}}}

    function Diagnostic(
        severity::Symbol,
        code::Symbol,
        message::AbstractString,
        location::SourceLocation;
        context = Pair{String,String}[],
    )
        severity in (:error, :warning, :info) ||
            throw(ArgumentError("diagnostic severity must be :error, :warning, or :info"))
        normalized =
            Pair{String,String}[String(key) => String(value) for (key, value) in context]
        return new(severity, code, String(message), location, Tuple(normalized))
    end
end

function Base.show(io::IO, diagnostic::Diagnostic)
    print(
        io,
        uppercase(String(diagnostic.severity)),
        " [",
        diagnostic.code,
        "] ",
        diagnostic.location,
        ": ",
        diagnostic.message,
    )
    return
end

"""An error that contains all diagnostics collected for one operation."""
struct OpenAPIError <: Exception
    summary::String
    diagnostics::Vector{Diagnostic}
end

function Base.showerror(io::IO, error::OpenAPIError)
    print(io, error.summary)
    for diagnostic in error.diagnostics
        print(io, '\n', "  ")
        show(io, diagnostic)
    end
    return
end

mutable struct DiagnosticBag
    diagnostics::Vector{Diagnostic}
    max_diagnostics::Int
end

function DiagnosticBag(max_diagnostics::Integer = 1_000)
    max_diagnostics > 0 || throw(ArgumentError("max_diagnostics must be positive"))
    return DiagnosticBag(Diagnostic[], Int(max_diagnostics))
end

function _emit!(
    bag::DiagnosticBag,
    severity::Symbol,
    code::Symbol,
    message::AbstractString,
    location::SourceLocation;
    context = Pair{String,String}[],
)
    length(bag.diagnostics) < bag.max_diagnostics ||
        throw(OpenAPIError("OpenAPI diagnostic limit reached", copy(bag.diagnostics)))
    push!(bag.diagnostics, Diagnostic(severity, code, message, location; context))
    return last(bag.diagnostics)
end

_error!(bag, code, message, location; kwargs...) =
    _emit!(bag, :error, code, message, location; kwargs...)
_warning!(bag, code, message, location; kwargs...) =
    _emit!(bag, :warning, code, message, location; kwargs...)

haserrors(diagnostics) = any(diagnostic -> diagnostic.severity === :error, diagnostics)

function _throw_on_errors(summary::AbstractString, diagnostics)
    haserrors(diagnostics) || return
    throw(OpenAPIError(String(summary), collect(diagnostics)))
end
