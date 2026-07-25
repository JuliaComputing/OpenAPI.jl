module StreamingLatencyTests

using Test
using Sockets

import OpenAPI
import OpenAPI.Clients: Client, Ctx, exec, LineChunkReader

# Streamed chunks must be forwarded to the consumer as soon as they arrive,
# not held back until an internal read buffer fills. Regression test for the
# :http backend stalling small chunks: `readbytes!(io, buf)` blocks until the
# whole 8KB buffer is filled, so a chunk smaller than that (e.g. a Kubernetes
# watch event) was only delivered once enough later data accumulated — on a
# quiet stream, effectively never.
#
# The server is a minimal raw-TCP chunked HTTP/1.1 responder so that the test
# controls exactly when bytes hit the wire, independent of HTTP.jl's server
# API (which differs between 1.x and 2.x). Two endpoints:
#   /quick - both chunks back to back (used to warm up/compile the client path)
#   /stall - first chunk immediately, second only after `delay` seconds

# JSON string literals: in the streaming path the client parses each chunk as
# JSON (no response object to take a content-type from), so a quoted string
# round-trips to a `String` return value.
const CHUNK1 = "\"tick-1\"\n"
const CHUNK2 = "\"tick-2\"\n"

function write_chunk(sock, data)
    write(sock, string(sizeof(data), base=16), "\r\n", data, "\r\n")
    flush(sock)
end

function handle_connection(sock, delay)
    try
        request_line = readline(sock)
        path = split(request_line, ' ')[2]
        while true
            line = readline(sock)
            (isempty(line) || line == "\r") && break
        end
        # `connection: close` so the client does not try to reuse the socket,
        # which this bare-bones server closes after each response
        write(sock, "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\nconnection: close\r\ntransfer-encoding: chunked\r\n\r\n")
        flush(sock)
        write_chunk(sock, CHUNK1)
        endswith(path, "/stall") && sleep(delay)
        write_chunk(sock, CHUNK2)
        write(sock, "0\r\n\r\n")
        flush(sock)
    catch
        # client went away; nothing to do
    finally
        close(sock)
    end
end

function start_server(delay)
    listener = Sockets.listen(Sockets.localhost, 0)
    _, port = Sockets.getsockname(listener)
    @async begin
        while true
            sock = try
                accept(listener)
            catch
                break # listener closed
            end
            @async handle_connection(sock, delay)
        end
    end
    listener, Int(port)
end

# Run a streaming GET and return (first chunk, seconds until it arrived,
# remaining chunks).
function first_chunk_latency(httplib, port, path)
    client = Client("http://127.0.0.1:$port"; httplib=httplib)
    return_types = Dict{Regex,Type}(Regex("^200\$") => String)
    ctx = Ctx(client, "GET", return_types, path, String[]; chunk_reader_type=LineChunkReader)
    events = Channel{Any}(64)
    t0 = time()
    task = @async exec(ctx, events)
    first = take!(events)
    latency = time() - t0
    remaining = collect(events)
    wait(task)
    (first, latency, remaining)
end

function runtests()
    delay = 4.0
    listener, port = start_server(delay)
    try
        @testset "first chunk not delayed until buffer fills ($httplib)" for httplib in values(OpenAPI.Clients.HTTPLib)
            # warm up: compile the full streaming request path so the timing
            # below measures I/O behavior, not JIT
            first_chunk_latency(httplib, port, "/quick")

            first, latency, remaining = first_chunk_latency(httplib, port, "/stall")
            @test first == "tick-1"
            # the first chunk must arrive while the server is still stalling
            # before the second chunk, not when the response completes
            @test latency < delay / 2
            @test remaining == ["tick-2"]
        end
    finally
        close(listener)
    end
end

end # module StreamingLatencyTests
