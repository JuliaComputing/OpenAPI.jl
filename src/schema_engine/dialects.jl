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
    # Keep construction name-based at the type boundary. Mapping through
    # `fieldnames` makes a declaration reorder safe, and defining only this
    # inner constructor makes old positional generated literals fail loudly.
    function Dialect(;
        name::Symbol,
        uri::AbstractString,
        id_keyword::AbstractString,
        ref_siblings::Bool,
        modern_items::Bool,
        unevaluated::Bool,
        dynamic_refs::Bool,
        recursive_refs::Bool,
        applicator::Bool,
        validation::Bool,
    )
        values = (;
            name,
            uri = String(uri),
            id_keyword = String(id_keyword),
            ref_siblings,
            modern_items,
            unevaluated,
            dynamic_refs,
            recursive_refs,
            applicator,
            validation,
        )
        ordered = map(field -> getproperty(values, field), fieldnames(Dialect))
        return new(ordered...)
    end
end

const DRAFT4 = Dialect(;
    name = :draft4,
    uri = "http://json-schema.org/draft-04/schema",
    id_keyword = "id",
    ref_siblings = false,
    modern_items = false,
    unevaluated = false,
    dynamic_refs = false,
    recursive_refs = false,
    applicator = true,
    validation = true,
)
const DRAFT6 = Dialect(;
    name = :draft6,
    uri = "http://json-schema.org/draft-06/schema",
    id_keyword = "\$id",
    ref_siblings = false,
    modern_items = false,
    unevaluated = false,
    dynamic_refs = false,
    recursive_refs = false,
    applicator = true,
    validation = true,
)
const DRAFT7 = Dialect(;
    name = :draft7,
    uri = "http://json-schema.org/draft-07/schema",
    id_keyword = "\$id",
    ref_siblings = false,
    modern_items = false,
    unevaluated = false,
    dynamic_refs = false,
    recursive_refs = false,
    applicator = true,
    validation = true,
)
const DRAFT201909 = Dialect(;
    name = :draft201909,
    uri = "https://json-schema.org/draft/2019-09/schema",
    id_keyword = "\$id",
    ref_siblings = true,
    modern_items = false,
    unevaluated = true,
    dynamic_refs = false,
    recursive_refs = true,
    applicator = true,
    validation = true,
)
const DRAFT202012 = Dialect(;
    name = :draft202012,
    uri = "https://json-schema.org/draft/2020-12/schema",
    id_keyword = "\$id",
    ref_siblings = true,
    modern_items = true,
    unevaluated = true,
    dynamic_refs = true,
    recursive_refs = false,
    applicator = true,
    validation = true,
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

# Long names and Unicode's extra aliases (`digit`, `cntrl`, `punct`, `Combining_Mark`) of
# the General_Category values. PCRE knows only the short names.
const ECMA_GENERAL_CATEGORIES = Dict(
    "Cased_Letter" => "L&",
    "Combining_Mark" => "M",
    "cntrl" => "Cc",
    "digit" => "Nd",
    "punct" => "P",
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

# ECMA-262 `\s`: WhiteSpace (tab, vertical tab, form feed, U+FEFF, and the Unicode 16
# Zs code points) and LineTerminator (LF, CR, U+2028, U+2029). PCRE without UCP knows
# only the ASCII ones, and cannot remove a set inside a class, so `\s` and `\S` are
# written as explicit ranges that work inside and outside a class.
const ECMA_WHITESPACE_RANGES = (
    0x09 => 0x0d,
    0x20 => 0x20,
    0xa0 => 0xa0,
    0x1680 => 0x1680,
    0x2000 => 0x200a,
    0x2028 => 0x2029,
    0x202f => 0x202f,
    0x205f => 0x205f,
    0x3000 => 0x3000,
    0xfeff => 0xfeff,
)

function _ecma_complement(ranges)
    output = Pair{UInt32,UInt32}[]
    first_free = UInt32(0)
    for (low, high) in ranges
        low > first_free && push!(output, first_free => UInt32(low - 1))
        first_free = UInt32(high + 1)
    end
    push!(output, first_free => UInt32(0x10ffff))
    return output
end

# Julia compiles with ALT_BSUX, so BMP code points use the JavaScript `\uhhhh` form.
# PCRE has no escape for an astral code point there, so it is written as a literal.
function _ecma_code_point(code::Integer)
    if code <= 0xff
        return "\\x" * string(code; base = 16, pad = 2)
    elseif code <= 0xffff
        return "\\u" * string(code; base = 16, pad = 4)
    end
    return string(Char(code))
end

function _ecma_class_body(ranges)
    io = IOBuffer()
    for (low, high) in ranges
        write(io, _ecma_code_point(low))
        low == high || write(io, '-', _ecma_code_point(high))
    end
    return String(take!(io))
end

const ECMA_WHITESPACE = _ecma_class_body(ECMA_WHITESPACE_RANGES)
const ECMA_NON_WHITESPACE = _ecma_class_body(_ecma_complement(ECMA_WHITESPACE_RANGES))
# ECMA-262 `.` matches any code point except a LineTerminator.
const ECMA_DOT = "[^\\n\\r\\u2028\\u2029]"

function _ecma_write_set(io::IO, body::AbstractString, in_class::Bool)
    if in_class
        write(io, body)
    else
        write(io, '[', body, ']')
    end
    return
end

function _ecma_property_escape!(io::IO, pattern::AbstractString, i::Int)
    property_type = pattern[i]
    brace = nextind(pattern, i)
    if brace > lastindex(pattern) || pattern[brace] != '{'
        write(io, '\\', property_type)
        return brace
    end
    closing = findnext('}', pattern, nextind(pattern, brace))
    if closing === nothing
        write(io, '\\', property_type)
        return brace
    end
    property = SubString(pattern, nextind(pattern, brace), prevind(pattern, closing))
    write(io, '\\', property_type, '{', _ecma_property(property), '}')
    return nextind(pattern, closing)
end

# `i` is the index of the escaped character. The pair is consumed here, so an escaped
# `[`, `]`, or `.` never reaches the class tracking in `_ecma_pattern`.
function _ecma_escape!(io::IO, pattern::AbstractString, i::Int, in_class::Bool)
    escaped = pattern[i]
    if escaped == 's'
        _ecma_write_set(io, ECMA_WHITESPACE, in_class)
    elseif escaped == 'S'
        _ecma_write_set(io, ECMA_NON_WHITESPACE, in_class)
    elseif escaped == 'p' || escaped == 'P'
        return _ecma_property_escape!(io, pattern, i)
    else
        write(io, '\\', escaped)
    end
    return nextind(pattern, i)
end

# ECMA-262 reads a `]` right after `[` or `[^` as the end of the class: `[]` matches
# nothing and `[^]` matches any code point. PCRE reads that `]` as a literal.
function _ecma_class_start!(io::IO, pattern::AbstractString, i::Int)
    stop = lastindex(pattern)
    after = i
    empty_class = "(?!)"
    if i <= stop && pattern[i] == '^'
        after = nextind(pattern, i)
        empty_class = "(?s:.)"
    end
    if after <= stop && pattern[after] == ']'
        write(io, empty_class)
        return nextind(pattern, after), false
    end
    write(io, '[')
    return i, true
end

# PCRE reads `[:name:]` in a class as a POSIX class. Copy it as one unit, so its `]` does
# not end the class tracking. `i` is the index after the `[`.
function _ecma_posix_class!(io::IO, pattern::AbstractString, i::Int)
    if i > lastindex(pattern) || pattern[i] != ':'
        return i
    end
    closing = findnext(":]", pattern, nextind(pattern, i))
    bracket = findnext(']', pattern, i)
    if closing === nothing || last(closing) != bracket
        return i
    end
    write(io, SubString(pattern, i, bracket))
    return nextind(pattern, bracket)
end

function _ecma_pattern(pattern::AbstractString)
    io = IOBuffer()
    in_class = false
    i = firstindex(pattern)
    stop = lastindex(pattern)
    while i <= stop
        char = pattern[i]
        i = nextind(pattern, i)
        if char == '\\' && i <= stop
            i = _ecma_escape!(io, pattern, i, in_class)
        elseif in_class
            in_class = char != ']'
            write(io, char)
            if char == '['
                i = _ecma_posix_class!(io, pattern, i)
            end
        elseif char == '['
            i, in_class = _ecma_class_start!(io, pattern, i)
        elseif char == '.'
            write(io, ECMA_DOT)
        else
            write(io, char)
        end
    end
    return String(take!(io))
end

# ECMA-262 semantics on PCRE: `$` matches only at the very end, never before a trailing
# newline (DOLLAR_ENDONLY), and `\d`, `\w`, `\b` are ASCII (no UCP). `\p{...}` still
# matches Unicode properties, which needs only UTF mode.
const ECMA_COMPILE_OPTIONS = (Base.DEFAULT_COMPILER_OPTS & ~Base.PCRE.UCP) | Base.PCRE.DOLLAR_ENDONLY

function _ecma_regex(pattern::AbstractString)
    return Regex(_ecma_pattern(pattern), ECMA_COMPILE_OPTIONS, Base.DEFAULT_MATCH_OPTS)
end
