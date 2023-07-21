module FormsV3Client

include("FormsClient/src/FormsClient.jl")
using .FormsClient
using Test
using OpenAPI
using OpenAPI.Clients
import OpenAPI.Clients: Client
using Base64

const server = "http://127.0.0.1:8081"

function test(uri)
    @info("FormsClient.DefaultApi")
    client = Client(uri)
    api = FormsClient.DefaultApi(client)

    mktemp() do test_file_path, test_file_io
        file_contents = "file contents"
        print(test_file_io, file_contents)
        close(test_file_io)

        api_return, http_resp = FormsClient.post_urlencoded_form(api, 1, file_contents; additional_metadata="my metadata")
        @test isa(api_return, FormsClient.TestResponse)
        @test api_return.message == "success, form_id=1, metadata=my metadata, file=file contents"
        @test http_resp.status == 200

        api_return, http_resp = FormsClient.upload_binary_file(api, 1; additional_metadata="my metadata", file=test_file_path)
        @test isa(api_return, FormsClient.TestResponse)
        @test api_return.message == "success, file_id=1, metadata=my metadata, file=file contents"
        @test http_resp.status == 200
        
        api_return, http_resp = FormsClient.upload_text_file(api, 1; additional_metadata="my metadata", file=Base64.base64encode(file_contents))
        @test isa(api_return, FormsClient.TestResponse)
        @test api_return.message == "success, file_id=1, metadata=my metadata, file=file contents"
        @test http_resp.status == 200
    end

    return nothing
end

function runtests()
    @testset "Forms and File Uploads" begin
        test(server)
    end
end

end # module FormsV3Client