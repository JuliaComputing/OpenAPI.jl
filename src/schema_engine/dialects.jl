# Copyright (c) 2026: fredo-dedup, quinnj, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

struct UnsupportedDialectError <: Exception
    dialect::String
end

function Base.showerror(io::IO, err::UnsupportedDialectError)
    return print(io, "unsupported JSON Schema dialect ", repr(err.dialect))
end

"""The keyword and evaluation rules for a JSON Schema dialect."""
struct Dialect
    name::Symbol
    uri::String
    id_keyword::String
    ref_siblings::Bool
    modern_items::Bool
    unevaluated::Bool
    dynamic_refs::Bool
    recursive_refs::Bool
    applicator::Bool
    validation::Bool
end

const DRAFT4 = Dialect(
    :draft4,
    "http://json-schema.org/draft-04/schema",
    "id",
    false,
    false,
    false,
    false,
    false,
    true,
    true,
)
const DRAFT6 = Dialect(
    :draft6,
    "http://json-schema.org/draft-06/schema",
    "\$id",
    false,
    false,
    false,
    false,
    false,
    true,
    true,
)
const DRAFT7 = Dialect(
    :draft7,
    "http://json-schema.org/draft-07/schema",
    "\$id",
    false,
    false,
    false,
    false,
    false,
    true,
    true,
)
const DRAFT201909 = Dialect(
    :draft201909,
    "https://json-schema.org/draft/2019-09/schema",
    "\$id",
    true,
    false,
    true,
    false,
    true,
    true,
    true,
)
const DRAFT202012 = Dialect(
    :draft202012,
    "https://json-schema.org/draft/2020-12/schema",
    "\$id",
    true,
    true,
    true,
    true,
    false,
    true,
    true,
)

const DIALECTS = Dict(
    DRAFT4.name => DRAFT4,
    DRAFT6.name => DRAFT6,
    DRAFT7.name => DRAFT7,
    DRAFT201909.name => DRAFT201909,
    DRAFT202012.name => DRAFT202012,
)

const COMMON_APPLICATOR_KEYWORDS = Set([
    "allOf",
    "anyOf",
    "oneOf",
    "not",
    "items",
    "additionalProperties",
    "properties",
    "patternProperties",
])

const COMMON_VALIDATION_KEYWORDS = Set([
    "type",
    "enum",
    "multipleOf",
    "maximum",
    "exclusiveMaximum",
    "minimum",
    "exclusiveMinimum",
    "maxLength",
    "minLength",
    "pattern",
    "maxItems",
    "minItems",
    "uniqueItems",
    "maxProperties",
    "minProperties",
    "required",
])

function keyword_applies(schema_dialect::Dialect, keyword::AbstractString)
    name = schema_dialect.name
    keyword in ("\$ref", "\$schema", schema_dialect.id_keyword) && return true
    keyword == "\$defs" && return name in (:draft201909, :draft202012)
    keyword == "definitions" && return name in (:draft4, :draft6, :draft7)
    keyword == "\$anchor" && return name in (:draft201909, :draft202012)
    keyword == "\$dynamicAnchor" && return schema_dialect.dynamic_refs
    keyword == "\$dynamicRef" && return schema_dialect.dynamic_refs
    keyword == "\$recursiveAnchor" && return schema_dialect.recursive_refs
    keyword == "\$recursiveRef" && return schema_dialect.recursive_refs
    keyword == "contentSchema" && return name in (:draft201909, :draft202012)
    if schema_dialect.unevaluated &&
       keyword in ("unevaluatedItems", "unevaluatedProperties")
        return true
    end
    if schema_dialect.applicator
        keyword in COMMON_APPLICATOR_KEYWORDS && return true
        keyword == "additionalItems" && return !schema_dialect.modern_items
        keyword == "prefixItems" && return schema_dialect.modern_items
        keyword in ("contains", "propertyNames") && return name != :draft4
        keyword in ("if", "then", "else") &&
            return name in (:draft7, :draft201909, :draft202012)
        keyword == "dependencies" && return name in (:draft4, :draft6, :draft7)
        keyword == "dependentSchemas" &&
            return name in (:draft201909, :draft202012)
    end
    if schema_dialect.validation
        keyword in COMMON_VALIDATION_KEYWORDS && return true
        keyword == "const" && return name != :draft4
        keyword == "dependentRequired" &&
            return name in (:draft201909, :draft202012)
        keyword in ("minContains", "maxContains") &&
            return name in (:draft201909, :draft202012)
    end
    return false
end

function _normalized_dialect_uri(uri::AbstractString)
    return rstrip(String(uri), '#')
end

function dialect(value::Dialect)
    return value
end

function dialect(value::Symbol)
    return get(
        () -> throw(UnsupportedDialectError(String(value))),
        DIALECTS,
        value,
    )
end

function dialect(value::AbstractString)
    normalized = _normalized_dialect_uri(value)
    for candidate in values(DIALECTS)
        _normalized_dialect_uri(candidate.uri) == normalized && return candidate
    end
    return throw(UnsupportedDialectError(String(value)))
end

function dialect(schema::AbstractDict; default::Dialect = DRAFT7)
    declared = get(schema, "\$schema", nothing)
    declared === nothing && return default
    declared isa AbstractString ||
        throw(UnsupportedDialectError(repr(declared)))
    return dialect(declared)
end

dialect(::Bool; default::Dialect = DRAFT7) = default

const ECMA_GENERAL_CATEGORIES = Dict(
    "Cased_Letter" => "L&",
    "Close_Punctuation" => "Pe",
    "Connector_Punctuation" => "Pc",
    "Control" => "Cc",
    "Currency_Symbol" => "Sc",
    "Dash_Punctuation" => "Pd",
    "Decimal_Number" => "Nd",
    "Enclosing_Mark" => "Me",
    "Final_Punctuation" => "Pf",
    "Format" => "Cf",
    "Initial_Punctuation" => "Pi",
    "Letter" => "L",
    "Letter_Number" => "Nl",
    "Line_Separator" => "Zl",
    "Lowercase_Letter" => "Ll",
    "Mark" => "M",
    "Math_Symbol" => "Sm",
    "Modifier_Letter" => "Lm",
    "Modifier_Symbol" => "Sk",
    "Nonspacing_Mark" => "Mn",
    "Number" => "N",
    "Open_Punctuation" => "Ps",
    "Other" => "C",
    "Other_Letter" => "Lo",
    "Other_Number" => "No",
    "Other_Punctuation" => "Po",
    "Other_Symbol" => "So",
    "Paragraph_Separator" => "Zp",
    "Private_Use" => "Co",
    "Punctuation" => "P",
    "Separator" => "Z",
    "Space_Separator" => "Zs",
    "Spacing_Mark" => "Mc",
    "Surrogate" => "Cs",
    "Symbol" => "S",
    "Titlecase_Letter" => "Lt",
    "Unassigned" => "Cn",
    "Uppercase_Letter" => "Lu",
)

function _ecma_property(property::AbstractString)
    parts = split(property, '='; limit = 2)
    if length(parts) == 1
        return get(ECMA_GENERAL_CATEGORIES, String(property), String(property))
    end
    name, value = parts
    if name in ("General_Category", "gc")
        return get(ECMA_GENERAL_CATEGORIES, value, value)
    elseif name in ("Script", "sc")
        return "sc=$value"
    elseif name in ("Script_Extensions", "scx")
        return "scx=$value"
    end
    return String(property)
end

function _ecma_pattern(pattern::AbstractString)
    io = IOBuffer()
    i = firstindex(pattern)
    stop = lastindex(pattern)
    while i <= stop
        if pattern[i] != '\\'
            write(io, pattern[i])
            i = nextind(pattern, i)
            continue
        end
        slashes = 0
        while i <= stop && pattern[i] == '\\'
            slashes += 1
            i = nextind(pattern, i)
        end
        for _ in 1:slashes
            write(io, '\\')
        end
        isodd(slashes) || continue
        i <= stop && pattern[i] in ('p', 'P') || continue
        property_type = pattern[i]
        brace = nextind(pattern, i)
        brace <= stop && pattern[brace] == '{' || continue
        closing = findnext('}', pattern, nextind(pattern, brace))
        closing === nothing && continue
        property = SubString(
            pattern,
            nextind(pattern, brace),
            prevind(pattern, closing),
        )
        seek(io, position(io) - 1)
        truncate(io, position(io))
        write(io, '\\', property_type, '{', _ecma_property(property), '}')
        i = nextind(pattern, closing)
    end
    return String(take!(io))
end

_ecma_regex(pattern::AbstractString) = Regex(_ecma_pattern(pattern))
