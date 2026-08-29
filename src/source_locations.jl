mutable struct JSONLocationCursor
    bytes::Vector{UInt8}
    index::Int
    line::Int
    column::Int
    after_cr::Bool
    locations::Dict{Resources.JSONPointer,SourcePosition}
end

function JSONLocationCursor(bytes::AbstractVector{UInt8})
    copied = Vector{UInt8}(bytes)
    cursor = JSONLocationCursor(
        copied,
        1,
        1,
        1,
        false,
        Dict{Resources.JSONPointer,SourcePosition}(),
    )
    if length(copied) >= 3 && copied[1:3] == UInt8[0xef, 0xbb, 0xbf]
        cursor.index = 4
    end
    return cursor
end

_json_eof(cursor::JSONLocationCursor) = cursor.index > length(cursor.bytes)
_json_peek(cursor::JSONLocationCursor) = cursor.bytes[cursor.index]
_json_position(cursor::JSONLocationCursor) =
    SourcePosition(cursor.line, cursor.column, cursor.index)

function _json_advance!(cursor::JSONLocationCursor)
    byte = _json_peek(cursor)
    cursor.index += 1
    if byte == UInt8('\r')
        cursor.line += 1
        cursor.column = 1
        cursor.after_cr = true
    elseif byte == UInt8('\n')
        cursor.after_cr || (cursor.line += 1)
        cursor.column = 1
        cursor.after_cr = false
    else
        (byte & 0xc0) == 0x80 || (cursor.column += 1)
        cursor.after_cr = false
    end
    return byte
end

function _json_whitespace!(cursor::JSONLocationCursor)
    while !_json_eof(cursor) &&
          _json_peek(cursor) in (UInt8(' '), UInt8('\t'), UInt8('\r'), UInt8('\n'))
        _json_advance!(cursor)
    end
    return
end

function _json_string!(cursor::JSONLocationCursor)
    _json_advance!(cursor) == UInt8('"') ||
        throw(ArgumentError("internal JSON source-location scanner expected a string"))
    while !_json_eof(cursor)
        byte = _json_advance!(cursor)
        byte == UInt8('"') && return
        byte == UInt8('\\') || continue
        _json_eof(cursor) &&
            throw(ArgumentError("internal JSON source-location scanner found an incomplete escape"))
        escape = _json_advance!(cursor)
        if escape == UInt8('u')
            for _ in 1:4
                _json_eof(cursor) && throw(
                    ArgumentError(
                        "internal JSON source-location scanner found an incomplete Unicode escape",
                    ),
                )
                _json_advance!(cursor)
            end
        end
    end
    throw(ArgumentError("internal JSON source-location scanner found an unterminated string"))
end

function _json_scalar!(cursor::JSONLocationCursor)
    if _json_peek(cursor) == UInt8('"')
        _json_string!(cursor)
        return
    end
    while !_json_eof(cursor) &&
          !(_json_peek(cursor) in (
        UInt8(' '),
        UInt8('\t'),
        UInt8('\r'),
        UInt8('\n'),
        UInt8(','),
        UInt8(']'),
        UInt8('}'),
    ))
        _json_advance!(cursor)
    end
    return
end

function _json_value!(
    cursor::JSONLocationCursor,
    pointer::Resources.JSONPointer,
    depth::Int,
    max_depth::Int,
)
    depth <= max_depth ||
        throw(ArgumentError("OpenAPI source exceeds the depth limit"))
    _json_whitespace!(cursor)
    _json_eof(cursor) &&
        throw(ArgumentError("internal JSON source-location scanner reached end of input"))
    get!(cursor.locations, pointer, _json_position(cursor))
    byte = _json_peek(cursor)
    if byte == UInt8('{')
        _json_advance!(cursor)
        _json_whitespace!(cursor)
        if !_json_eof(cursor) && _json_peek(cursor) == UInt8('}')
            _json_advance!(cursor)
            return
        end
        while true
            _json_whitespace!(cursor)
            key_position = _json_position(cursor)
            key_start = cursor.index
            _json_string!(cursor)
            key_end = cursor.index - 1
            key = JSON.parse(
                String(copy(cursor.bytes[key_start:key_end]));
                duplicate_keys = :error,
            )
            child = pointer / key
            cursor.locations[child] = key_position
            _json_whitespace!(cursor)
            _json_advance!(cursor) == UInt8(':') || throw(
                ArgumentError("internal JSON source-location scanner expected ':'"),
            )
            _json_value!(cursor, child, depth + 1, max_depth)
            _json_whitespace!(cursor)
            delimiter = _json_advance!(cursor)
            delimiter == UInt8('}') && return
            delimiter == UInt8(',') || throw(
                ArgumentError("internal JSON source-location scanner expected ',' or '}'"),
            )
        end
    elseif byte == UInt8('[')
        _json_advance!(cursor)
        _json_whitespace!(cursor)
        if !_json_eof(cursor) && _json_peek(cursor) == UInt8(']')
            _json_advance!(cursor)
            return
        end
        index = 0
        while true
            _json_value!(cursor, pointer / string(index), depth + 1, max_depth)
            index += 1
            _json_whitespace!(cursor)
            delimiter = _json_advance!(cursor)
            delimiter == UInt8(']') && return
            delimiter == UInt8(',') || throw(
                ArgumentError("internal JSON source-location scanner expected ',' or ']'"),
            )
        end
    end
    _json_scalar!(cursor)
    return
end

function _json_locations(bytes::AbstractVector{UInt8}, max_depth::Int)
    cursor = JSONLocationCursor(bytes)
    _json_value!(cursor, Resources.JSONPointer(), 0, max_depth)
    _json_whitespace!(cursor)
    _json_eof(cursor) || throw(
        ArgumentError("internal JSON source-location scanner found trailing input"),
    )
    return cursor.locations
end

function _line_starts(text::AbstractString)
    starts = Int[firstindex(text)]
    for index in eachindex(text)
        text[index] == '\n' || continue
        push!(starts, nextind(text, index))
    end
    return starts
end

function _byte_at_column(
    text::AbstractString,
    starts::Vector{Int},
    line::Int,
    column::Int,
)
    1 <= line <= length(starts) || return ncodeunits(text) + 1
    index = starts[line]
    stop = line < length(starts) ? starts[line + 1] - 1 : ncodeunits(text) + 1
    for _ in 1:column
        index >= stop && return stop
        index = nextind(text, index)
    end
    return index
end

function _yaml_position(text, starts, mark)
    line = Int(mark.line)
    column = Int(mark.column)
    return SourcePosition(
        line,
        column + 1,
        _byte_at_column(text, starts, line, column),
    )
end

function _yaml_locations!(
    locations,
    node,
    pointer,
    text,
    starts,
    active::IdDict{Any,Nothing},
)
    mark = getproperty(node, :start_mark)
    mark === nothing || get!(locations, pointer, _yaml_position(text, starts, mark))
    node isa YAML.ScalarNode && return
    haskey(active, node) && return
    active[node] = nothing
    try
        if node isa YAML.MappingNode
            for (key_node, value_node) in node.value
                key_node isa YAML.ScalarNode || continue
                child = pointer / String(key_node.value)
                key_mark = key_node.start_mark
                key_mark === nothing ||
                    (locations[child] = _yaml_position(text, starts, key_mark))
                _yaml_locations!(
                    locations,
                    value_node,
                    child,
                    text,
                    starts,
                    active,
                )
            end
        elseif node isa YAML.SequenceNode
            for (index, child_node) in enumerate(node.value)
                _yaml_locations!(
                    locations,
                    child_node,
                    pointer / string(index - 1),
                    text,
                    starts,
                    active,
                )
            end
        end
    finally
        delete!(active, node)
    end
    return
end

function _yaml_locations(text::AbstractString)
    token_stream = YAML.TokenStream(IOBuffer(text))
    node = YAML.compose(YAML.EventStream(token_stream), YAML.Resolver())
    node isa YAML.MissingDocument &&
        return Dict{Resources.JSONPointer,SourcePosition}()
    locations = Dict{Resources.JSONPointer,SourcePosition}()
    _yaml_locations!(
        locations,
        node,
        Resources.JSONPointer(),
        text,
        _line_starts(text),
        IdDict{Any,Nothing}(),
    )
    return locations
end

function _position_at_byte(bytes::AbstractVector{UInt8}, byte::Integer)
    target = clamp(Int(byte), 1, length(bytes) + 1)
    cursor = JSONLocationCursor(bytes)
    while cursor.index < target && !_json_eof(cursor)
        _json_advance!(cursor)
    end
    return _json_position(cursor)
end

function _parse_error_position(error, bytes::AbstractVector{UInt8})
    if error isa JSON.DuplicateKeyError
        return _position_at_byte(bytes, error.position)
    end
    if hasproperty(error, :problem_mark)
        mark = getproperty(error, :problem_mark)
        if mark !== nothing
            text = String(copy(bytes))
            isvalid(text) || return nothing
            return _yaml_position(text, _line_starts(text), mark)
        end
    end
    matched = match(r"byte position (\d+)", sprint(showerror, error))
    matched === nothing && return nothing
    return _position_at_byte(bytes, parse(Int, matched.captures[1]))
end
