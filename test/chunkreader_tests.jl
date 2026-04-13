module ChunkReaderTests
using Test
using JSON
using OpenAPI
using OpenAPI.Clients: AbstractChunkReader, JSONChunkReader, LineChunkReader, RFC7464ChunkReader, _read_json_chunk

function linechunk1()
    buff = Base.BufferStream()
    reader = LineChunkReader(buff)
    results = String[]
    readertask = @async begin
        for line in reader
            push!(results, String(line))
        end
    end
    write(buff, "hello\nworld\n")
    write(buff, "goodbye\n")
    close(buff)
    wait(readertask)
    @test results == ["hello", "world", "goodbye"]
end

function linechunk2()
    buff = Base.BufferStream()
    reader = LineChunkReader(buff)
    results = String[]
    readertask = @async begin
        for line in reader
            push!(results, String(line))
        end
    end
    write(buff, "\nhello\nworld\n")
    write(buff, "goodbye\n")
    close(buff)
    wait(readertask)
    @test results == ["", "hello", "world", "goodbye"]
end

function linechunk3()
    buff = Base.BufferStream()
    reader = LineChunkReader(buff)
    results = String[]
    readertask = @async begin
        for line in reader
            push!(results, String(line))
        end
    end
    write(buff, "hello\nworld\n")
    write(buff, "goodbye")
    close(buff)
    wait(readertask)
    @test results == ["hello", "world", "goodbye"]
end

function jsonchunk1()
    buff = Base.BufferStream()
    reader = JSONChunkReader(buff)
    results = String[]
    readertask = @async begin
        for json in reader
            push!(results, String(json))
        end
    end

    write(buff, "{\"hello\": \"world\"}")
    write(buff, "{\"hello\": \"world\"}")
    close(buff)
    wait(readertask)
    for result in results
        json = JSON.parse(result)
        @test json["hello"] == "world"
    end
    @test length(results) == 2
end

function jsonchunk2()
    buff = Base.BufferStream()
    reader = JSONChunkReader(buff)
    results = String[]
    readertask = @async begin
        for json in reader
            push!(results, String(json))
        end
    end

    write(buff, "{\"hello\": \"world\"}\n")
    write(buff, "{\"hello\": \"world\"}\n")
    close(buff)
    wait(readertask)
    for result in results
        json = JSON.parse(result)
        @test json["hello"] == "world"
    end
    @test length(results) == 2
end

function jsonchunk3()
    buff = Base.BufferStream()
    reader = JSONChunkReader(buff)
    results = String[]
    readertask = @async begin
        for json in reader
            push!(results, String(json))
        end
    end

    write(buff, "\n\n{\"hello\": \"world\"}\n\n")
    write(buff, "{\"hello\": \"world\"}\n")
    close(buff)
    wait(readertask)
    for result in results
        json = JSON.parse(result)
        @test json["hello"] == "world"
    end
    @test length(results) == 2
end

function jsonchunk4()
    buff = Base.BufferStream()
    reader = JSONChunkReader(buff)
    results = String[]
    readertask = @async begin
        for json in reader
            push!(results, String(json))
        end
    end

    write(buff, "\n\n{\"hello\": \"world\"}\n\n")
    write(buff, "{\"hello\": \"world\"\n")
    close(buff)
    @test_throws TaskFailedException wait(readertask)
    @test length(results) == 1
end

function rfc7464chunk1()
    buff = Base.BufferStream()
    reader = RFC7464ChunkReader(buff)
    results = String[]
    readertask = @async begin
        for chunk in reader
            push!(results, String(chunk))
        end
    end

    write(buff, OpenAPI.Clients.RFC7464_RECORD_SEPARATOR)
    write(buff, "{\"hello\": \"world\"}")
    write(buff, OpenAPI.Clients.RFC7464_RECORD_SEPARATOR)
    write(buff, "{\"hello\": \"world\"}")
    close(buff)
    wait(readertask)
    for result in results
        if !isempty(result)
            json = JSON.parse(result)
            @test json["hello"] == "world"
        end
    end
    @test length(results) == 3
end

function rfc7464chunk2()
    buff = Base.BufferStream()
    reader = RFC7464ChunkReader(buff)
    results = String[]
    readertask = @async begin
        for chunk in reader
            push!(results, String(chunk))
        end
    end

    write(buff, "{\"hello\": \"world\"}")
    write(buff, OpenAPI.Clients.RFC7464_RECORD_SEPARATOR)
    write(buff, "{\"hello\": \"world\"}")
    write(buff, OpenAPI.Clients.RFC7464_RECORD_SEPARATOR)
    close(buff)
    wait(readertask)
    for result in results
        if !isempty(result)
            json = JSON.parse(result)
            @test json["hello"] == "world"
        end
    end
    @test length(results) == 2
end

function read_json_chunk_object()
    io = IOBuffer("{\"key\": \"value\"}")
    @test String(_read_json_chunk(io)) == "{\"key\": \"value\"}"
    @test eof(io)
end

function read_json_chunk_nested_object()
    io = IOBuffer("{\"a\": {\"b\": 1}}")
    @test String(_read_json_chunk(io)) == "{\"a\": {\"b\": 1}}"
    @test eof(io)
end

function read_json_chunk_array()
    io = IOBuffer("[1, 2, 3]")
    @test String(_read_json_chunk(io)) == "[1, 2, 3]"
    @test eof(io)
end

function read_json_chunk_nested_array()
    io = IOBuffer("[[1,2],[3,4]]")
    @test String(_read_json_chunk(io)) == "[[1,2],[3,4]]"
    @test eof(io)
end

function read_json_chunk_string()
    io = IOBuffer("\"hello\"")
    @test String(_read_json_chunk(io)) == "\"hello\""
    @test eof(io)
end

function read_json_chunk_string_escaped_quote()
    # embedded escaped quote: "say \"hi\""
    io = IOBuffer("\"say \\\"hi\\\"\"")
    @test String(_read_json_chunk(io)) == "\"say \\\"hi\\\"\""
    @test eof(io)
end

function read_json_chunk_string_escaped_backslash()
    # embedded escaped backslash: "path\\file"
    io = IOBuffer("\"path\\\\file\"")
    @test String(_read_json_chunk(io)) == "\"path\\\\file\""
    @test eof(io)
end

function read_json_chunk_integer()
    io = IOBuffer("42")
    @test String(_read_json_chunk(io)) == "42"
    @test eof(io)
end

function read_json_chunk_float()
    io = IOBuffer("3.14")
    @test String(_read_json_chunk(io)) == "3.14"
    @test eof(io)
end

function read_json_chunk_true()
    io = IOBuffer("true")
    @test String(_read_json_chunk(io)) == "true"
    @test eof(io)
end

function read_json_chunk_false()
    io = IOBuffer("false")
    @test String(_read_json_chunk(io)) == "false"
    @test eof(io)
end

function read_json_chunk_null()
    io = IOBuffer("null")
    @test String(_read_json_chunk(io)) == "null"
    @test eof(io)
end

function read_json_chunk_stops_at_boundary()
    # reads exactly one chunk and leaves the stream positioned at the next value
    io = IOBuffer("{\"a\":1}{\"b\":2}")
    @test String(_read_json_chunk(io)) == "{\"a\":1}"
    @test String(_read_json_chunk(io)) == "{\"b\":2}"
    @test eof(io)
end

function read_json_chunk_braces_in_string()
    # braces inside a string value must not affect depth tracking
    io = IOBuffer("{\"key\": \"value{nested}\"}")
    @test String(_read_json_chunk(io)) == "{\"key\": \"value{nested}\"}"
    @test eof(io)
end

function read_json_chunk_brackets_in_string()
    # brackets inside a string value must not affect depth tracking
    io = IOBuffer("{\"key\": \"[not an array]\"}")
    @test String(_read_json_chunk(io)) == "{\"key\": \"[not an array]\"}"
    @test eof(io)
end

function runtests()
    linechunk1()
    linechunk2()
    linechunk3()
    jsonchunk1()
    jsonchunk2()
    jsonchunk3()
    jsonchunk4()
    rfc7464chunk1()
    rfc7464chunk2()
    read_json_chunk_object()
    read_json_chunk_nested_object()
    read_json_chunk_array()
    read_json_chunk_nested_array()
    read_json_chunk_string()
    read_json_chunk_string_escaped_quote()
    read_json_chunk_string_escaped_backslash()
    read_json_chunk_integer()
    read_json_chunk_float()
    read_json_chunk_true()
    read_json_chunk_false()
    read_json_chunk_null()
    read_json_chunk_stops_at_boundary()
    read_json_chunk_braces_in_string()
    read_json_chunk_brackets_in_string()
end

end # module ChunkReaderTests