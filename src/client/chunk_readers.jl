struct LineChunkReader <: AbstractChunkReader
    buffered_input::Base.BufferStream
end

function Base.iterate(iter::LineChunkReader, _state=nothing)
    if eof(iter.buffered_input)
        return nothing
    else
        out = IOBuffer()
        while !eof(iter.buffered_input)
            byte = read(iter.buffered_input, UInt8)
            (byte == codepoint('\n')) && break
            write(out, byte)
        end
        return (take!(out), iter)
    end
end

struct JSONChunkReader <: AbstractChunkReader
    buffered_input::Base.BufferStream
end

function _read_json_chunk(io::IO)
    out = IOBuffer()
    first_byte = peek(io, UInt8)

    if first_byte == UInt8('{') || first_byte == UInt8('[')
        close_byte = first_byte == UInt8('{') ? UInt8('}') : UInt8(']')
        depth = 0
        in_string = false
        escaped = false

        while !eof(io)
            byte = read(io, UInt8)
            write(out, byte)

            if escaped
                escaped = false
                continue
            end

            if in_string
                if byte == UInt8('\\')
                    escaped = true
                elseif byte == UInt8('"')
                    in_string = false
                end
            else
                if byte == UInt8('"')
                    in_string = true
                elseif byte == first_byte
                    depth += 1
                elseif byte == close_byte
                    depth -= 1
                    depth == 0 && break
                end
            end
        end
    elseif first_byte == UInt8('"')
        escaped = false
        read(io, UInt8)  # consume opening quote
        write(out, UInt8('"'))
        while !eof(io)
            byte = read(io, UInt8)
            write(out, byte)
            if escaped
                escaped = false
            elseif byte == UInt8('\\')
                escaped = true
            elseif byte == UInt8('"')
                break
            end
        end
    else
        # number / true / false / null: read until delimiter
        while !eof(io)
            byte = peek(io, UInt8)
            if isspace(Char(byte)) || byte == UInt8(',') || byte == UInt8(']') || byte == UInt8('}')
                break
            end
            write(out, read(io, UInt8))
        end
    end

    take!(out)
end

function Base.iterate(iter::JSONChunkReader, _state=nothing)
    if eof(iter.buffered_input)
        return nothing
    else
        # read all whitespaces
        while !eof(iter.buffered_input)
            byte = peek(iter.buffered_input, UInt8)
            if isspace(Char(byte))
                read(iter.buffered_input, UInt8)
            else
                break
            end
        end
        eof(iter.buffered_input) && return nothing
        chunk_bytes = _read_json_chunk(iter.buffered_input)
        isempty(chunk_bytes) && return nothing
        valid_json = _json_parse(String(chunk_bytes))
        bytes = convert(Vector{UInt8}, codeunits(JSON.json(valid_json)))
        return (bytes, iter)
    end
end

# Ref: https://www.rfc-editor.org/rfc/rfc7464.html
const RFC7464_RECORD_SEPARATOR = UInt8(0x1E)
struct RFC7464ChunkReader <: AbstractChunkReader
    buffered_input::Base.BufferStream
end

function Base.iterate(iter::RFC7464ChunkReader, _state=nothing)
    if eof(iter.buffered_input)
        return nothing
    else
        out = IOBuffer()
        while !eof(iter.buffered_input)
            byte = read(iter.buffered_input, UInt8)
            if byte == RFC7464_RECORD_SEPARATOR
                bytes = take!(out)
                if isnothing(_state) || !isempty(bytes)
                    return (bytes, iter)
                end
            else
                write(out, byte)
            end
        end
        bytes = take!(out)
        return (bytes, iter)
    end
end
