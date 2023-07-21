module FormsV3Server

using HTTP

include("FormsServer/src/FormsServer.jl")

using .FormsServer
using Base64

const server = Ref{Any}(nothing)

function post_urlencoded_form(req::HTTP.Request, form_id::Int64; additional_metadata=nothing, file=nothing,)
    str_file_contents = file
    return FormsServer.TestResponse(; message="success, form_id=$form_id, metadata=$additional_metadata, file=$str_file_contents", )
end

function upload_binary_file(req::HTTP.Request, file_id::Int64; additional_metadata=nothing, file=nothing,)
    str_file_contents = String(copy(file))
    return FormsServer.TestResponse(; message="success, file_id=$file_id, metadata=$additional_metadata, file=$str_file_contents", )
end

function upload_text_file(req::HTTP.Request, file_id::Int64; additional_metadata=nothing, file=nothing,)
    str_file_contents = String(copy(Base64.base64decode(file)))
    return FormsServer.TestResponse(; message="success, file_id=$file_id, metadata=$additional_metadata, file=$str_file_contents", )
end

function stop(::HTTP.Request)
    HTTP.close(server[])
    return HTTP.Response(200, "")
end

function ping(::HTTP.Request)
    return HTTP.Response(200, "")
end

function run_server(port=8081)
    try
        router = HTTP.Router()
        router = FormsServer.register(router, @__MODULE__)
        HTTP.register!(router, "GET", "/stop", stop)
        HTTP.register!(router, "GET", "/ping", ping)
        server[] = HTTP.serve!(router, port)
        wait(server[])
    catch ex
        @error("Server error", exception=(ex, catch_backtrace()))
    end
end

end # module FormsV3Server

FormsV3Server.run_server()