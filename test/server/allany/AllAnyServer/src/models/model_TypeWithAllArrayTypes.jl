# This file was generated by the Julia OpenAPI Code Generator
# Do not modify this file directly. Modify the OpenAPI specification instead.


@doc raw"""TypeWithAllArrayTypes

    TypeWithAllArrayTypes(;
        oneofbase=nothing,
        anyofbase=nothing,
        oneofpets=nothing,
        anyofpets=nothing,
    )

    - oneofbase::Vector{OneOfBaseType}
    - anyofbase::Vector{AnyOfBaseType}
    - oneofpets::Vector{OneOfPets}
    - anyofpets::Vector{AnyOfPets}
"""
Base.@kwdef mutable struct TypeWithAllArrayTypes <: OpenAPI.APIModel
    oneofbase::Union{Nothing, Vector} = nothing # spec type: Union{ Nothing, Vector{OneOfBaseType} }
    anyofbase::Union{Nothing, Vector} = nothing # spec type: Union{ Nothing, Vector{AnyOfBaseType} }
    oneofpets::Union{Nothing, Vector} = nothing # spec type: Union{ Nothing, Vector{OneOfPets} }
    anyofpets::Union{Nothing, Vector} = nothing # spec type: Union{ Nothing, Vector{AnyOfPets} }

    function TypeWithAllArrayTypes(oneofbase, anyofbase, oneofpets, anyofpets, )
        OpenAPI.validate_property(TypeWithAllArrayTypes, Symbol("oneofbase"), oneofbase)
        OpenAPI.validate_property(TypeWithAllArrayTypes, Symbol("anyofbase"), anyofbase)
        OpenAPI.validate_property(TypeWithAllArrayTypes, Symbol("oneofpets"), oneofpets)
        OpenAPI.validate_property(TypeWithAllArrayTypes, Symbol("anyofpets"), anyofpets)
        return new(oneofbase, anyofbase, oneofpets, anyofpets, )
    end
end # type TypeWithAllArrayTypes

const _property_types_TypeWithAllArrayTypes = Dict{Symbol,String}(Symbol("oneofbase")=>"Vector{OneOfBaseType}", Symbol("anyofbase")=>"Vector{AnyOfBaseType}", Symbol("oneofpets")=>"Vector{OneOfPets}", Symbol("anyofpets")=>"Vector{AnyOfPets}", )
OpenAPI.property_type(::Type{ TypeWithAllArrayTypes }, name::Symbol) = Union{Nothing,eval(Base.Meta.parse(_property_types_TypeWithAllArrayTypes[name]))}

function check_required(o::TypeWithAllArrayTypes)
    true
end

function OpenAPI.validate_property(::Type{ TypeWithAllArrayTypes }, name::Symbol, val)
end