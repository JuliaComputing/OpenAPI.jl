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
        valid_json = JSON.parse(iter.buffered_input)
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
