abstract type APIModel end
abstract type APIClientImpl end
struct OpenAPIException <: Exception
    reason::String
end
struct ValidationException <: Exception
    reason::String
end
struct InvocationException <: Exception
    reason::String
end

property_type(::Type{T}, name::Symbol) where {T<:APIModel} = error("invalid type $T")