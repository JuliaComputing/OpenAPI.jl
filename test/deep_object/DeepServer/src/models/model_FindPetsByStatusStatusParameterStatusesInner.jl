# This file was generated by the Julia OpenAPI Code Generator
# Do not modify this file directly. Modify the OpenAPI specification instead.


@doc raw"""
    FindPetsByStatusStatusParameterStatusesInner(;
        type=nothing,
    )

    - type::String
"""
Base.@kwdef mutable struct FindPetsByStatusStatusParameterStatusesInner <: OpenAPI.APIModel
    type::Union{Nothing, String} = nothing

    function FindPetsByStatusStatusParameterStatusesInner(type, )
        OpenAPI.validate_property(FindPetsByStatusStatusParameterStatusesInner, Symbol("type"), type)
        return new(type, )
    end
end # type FindPetsByStatusStatusParameterStatusesInner

const _property_types_FindPetsByStatusStatusParameterStatusesInner = Dict{Symbol,String}(Symbol("type")=>"String", )
OpenAPI.property_type(::Type{ FindPetsByStatusStatusParameterStatusesInner }, name::Symbol) = Union{Nothing,eval(Base.Meta.parse(_property_types_FindPetsByStatusStatusParameterStatusesInner[name]))}

function check_required(o::FindPetsByStatusStatusParameterStatusesInner)
    true
end

function OpenAPI.validate_property(::Type{ FindPetsByStatusStatusParameterStatusesInner }, name::Symbol, val)
end
