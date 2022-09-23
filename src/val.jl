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
])

function validate_param(param, operation_or_model, rule, value, args...)
    # do not validate missing values
    (value === nothing) && return

    VAL_API_PARAM[rule](value, args...) && return

    msg = string("Invalid value ($value) of parameter ", param, " for ", operation_or_model, ", ", MSG_INVALID_API_PARAM[rule](args...))
    throw(ValidationException(msg))
end

validate_property(::Type{T}, name::Symbol, val) where {T<:APIModel} = nothing
