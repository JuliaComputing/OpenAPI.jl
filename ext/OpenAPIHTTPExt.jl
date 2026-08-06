# Lets OpenAPI.read fetch documents over HTTP (e.g. a running app's
# /openapi.json). Loads automatically when both OpenAPI and HTTP are loaded.
module OpenAPIHTTPExt

using OpenAPI, HTTP

function OpenAPI.fetchresource(id::OpenAPI.Resources.ResourceId, max_bytes::Integer)
    body = Vector{UInt8}(undef, max_bytes)
    response = try
        HTTP.get(
            string(id);
            status_exception = false,
            redirect = false,
            retry = false,
            response_stream = body,
            max_decompressed_size = max_bytes,
            request_timeout = 60,
            read_idle_timeout = 15,
        )
    catch error
        message = sprint(showerror, error)
        if occursin("response stream", message) ||
           occursin("DecompressionLimitError", message)
            throw(
                OpenAPI.Resources.RetrievalError(
                    id,
                    "HTTP response exceeds the $max_bytes-byte limit",
                ),
            )
        end
        throw(
            OpenAPI.Resources.RetrievalError(
                id,
                "HTTP request failed: $message",
            ),
        )
    end
    200 <= response.status < 300 || throw(
        OpenAPI.Resources.RetrievalError(
            id,
            "HTTP request returned status $(response.status)",
        ),
    )
    bytes = copy(body)
    media_type = HTTP.header(response, "Content-Type", "")
    return OpenAPI.Resources.RetrievedResource(
        id,
        bytes;
        media_type = isempty(media_type) ? nothing : media_type,
    )
end

OpenAPI.fetchurl(url::AbstractString) = String(
    getfield(
        OpenAPI.fetchresource(OpenAPI.Resources.ResourceId(url), 16 * 1024 * 1024),
        :bytes,
    ),
)

end # module
