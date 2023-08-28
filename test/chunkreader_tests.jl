module ChunkReaderTests
using Test
using JSON
using OpenAPI
using OpenAPI.Clients: AbstractChunkReader, JSONChunkReader, LineChunkReader, RFC7464ChunkReader

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
end

end # module ChunkReaderTests