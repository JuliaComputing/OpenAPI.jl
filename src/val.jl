val_max(val, lim, excl) = (excl ? (val < lim) : (val <= lim))
val_min(val, lim, excl) = (excl ? (val > lim) : (val >= lim))
val_max_length(val, lim) = (length(val) <= lim)
val_min_length(val, lim) = (length(val) >= lim)
val_enum(val, lst) = (val in lst)
function val_enum(val::Vector, lst)
    for v in val
        (v in lst) || return false
    end
    true
end
function val_enum(val::Dict, lst)
    for v in keys(val)
        (v in lst) || return false
    end
    true
end
function val_unique_items(val::Vector, is_unique)
    is_unique || return true
    return length(Set(val)) == length(val)
end
function val_pattern(val::AbstractString, pattern::Regex)
    return !isnothing(match(pattern, val))
end
val_format(val, format) = true   # accept any unhandled format
val_format(val, format::AbstractString) = val_format(val, Val(Symbol(format)))
val_format(val::AbstractString, ::Val{:date}) = str2date(val) isa Date
val_format(val::AbstractString, ::Val{Symbol("date-time")}) = str2datetime(val) isa DateTime
val_format(val::AbstractString, ::Val{:byte}) = try
    base64decode(val)
    true
catch
    false
end
val_format(val::Integer, ::Val{:int32}) = (typemin(Int32) <= val <= typemax(Int32))
val_format(val::Integer, ::Val{:int64}) = (typemin(Int64) <= val <= typemax(Int64))
val_format(val::AbstractFloat, ::Val{:float}) = (typemin(Float32) <= Float32(val) <= typemax(Float32))
val_format(val::AbstractFloat, ::Val{:double}) = (typemin(Float64) <= Float64(val) <= typemax(Float64))

function val_multiple_of(val::Real, multiple_of::Real)
    return isinteger(val / multiple_of)
end

const MSG_INVALID_API_PARAM = Dict{Symbol,Function}([
    :maximum => (val,excl)->string("must be a value less than ", excl ? "or equal to " : "", val),
    :minimum => (val,excl)->string("must be a value greater than ", excl ? "or equal to " : "", val),
    :maxLength => (len)->string("length must be less than or equal to ", len),
    :minLength => (len)->string("length must be greater than or equal to ", len),
    :maxItems => (val)->string("number of items must be less than or equal to ", val),
    :minItems => (val)->string("number of items must be greater than or equal to ", val),
    :uniqueItems => (val)->string("items must be unique"),
    :maxProperties => (val)->string("number of properties must be less than or equal to ", val),
    :minProperties => (val)->string("number of properties must be greater than or equal to ", val),
    :enum => (lst)->string("value is not from the allowed values ", lst),
    :pattern => (val)->string("value does not match required pattern"),
    :format => (val)->string("value does not match required format"),
    :multipleOf => (val)->string("value must be a multiple of ", val),
])

const VAL_API_PARAM = Dict{Symbol,Function}([
    :maximum => val_max,
    :minimum => val_min,
    :maxLength => val_max_length,
    :minLength => val_min_length,
    :maxItems => val_max_length,
    :minItems => val_min_length,
    :uniqueItems => val_unique_items,
    :maxProperties => val_max_length,
    :minProperties => val_min_length,
    :pattern => val_pattern,
    :enum => val_enum,
    :format => val_format,
    :multipleOf => val_multiple_of,
])

function validate_param(parameter, operation_or_model, rule, value, args...)
    # do not validate missing values
    (value === nothing) && return

    VAL_API_PARAM[rule](value, args...) && return

    reason = string("Invalid value ($value) of parameter ", parameter, ", ", MSG_INVALID_API_PARAM[rule](args...))
    throw(ValidationException(;reason, operation_or_model, value, parameter, rule, args))
end

validate_property(::Type{T}, name::Symbol, val) where {T<:APIModel} = nothing
