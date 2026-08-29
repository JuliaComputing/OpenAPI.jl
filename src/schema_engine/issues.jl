# Copyright (c) 2026: fredo-dedup, quinnj, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

"""One JSON Schema validation issue."""
struct SingleIssue
    x::Any
    path::String
    reason::String
    val::Any
end

function Base.show(io::IO, issue::SingleIssue)
    return println(
        io,
        """Validation failed:
path:         $(isempty(issue.path) ? "top-level" : issue.path)
instance:     $(issue.x)
schema key:   $(issue.reason)
schema value: $(issue.val)""",
    )
end

# JSON equality differs from Julia equality for booleans and numbers. JSON
# arrays and objects compare recursively with the same rule.
_isequal(x, y) = x == y
_isequal(::Bool, ::Number) = false
_isequal(::Number, ::Bool) = false
_isequal(x::Bool, y::Bool) = x == y

function _isequal(x::AbstractVector, y::AbstractVector)
    return length(x) == length(y) && all(_isequal.(x, y))
end

function _isequal(x::AbstractDict, y::AbstractDict)
    return Set(keys(x)) == Set(keys(y)) &&
           all(_isequal(value, y[key]) for (key, value) in x)
end
