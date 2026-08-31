# Streaming and codecs

## Streaming responses

Pass `stream_to = Channel(n)` to any operation to consume the response body
incrementally, e.g. long-running watch endpoints or large exports:

```julia
events = Channel{Any}(16)
ExampleClient.watch_pods(; client, stream_to = events)  # returns at the response head
for event in events
    # each item is decoded to the documented response type
end
```

The call returns as soon as the response head arrives (the channel itself, or
an `ApiResponse` whose body is the channel with `with_http_info = true`), and a
background task decodes items onto the channel. `application/json` bodies split
into consecutive JSON documents, each decoded against the documented response
schema — the convention used by Kubernetes-style watch endpoints. JSON Lines
and NDJSON bodies decode each line to the documented array's element type, and
JSON text sequences split on RFC 7464 record separators. `text/*` yields lines
and any other media type yields raw byte chunks. The channel closes when the
response ends, closes with the error when decoding or validation fails, and
closing it from the consumer side aborts the transfer. Error statuses still
throw `ApiError` with the fully buffered error body.

## Custom codecs

For a custom media type, register an encoder or decoder on the client:

```julia
ExampleClient.codec!(
    client,
    "application/cbor";
    encode = (value, media_type) -> encode_cbor(value),
    decode = (bytes, media_type) -> decode_cbor(bytes),
)
```

XML metadata is retained in the schema but does not generate an XML codec.
Register a custom codec for XML or another non-built-in representation.

## Codecs on streaming calls

A registered response decoder also applies to streaming calls. The runtime
calls it once for each framed item and puts its return value directly on the
channel. This is an escape hatch for deployed APIs whose streaming wire format
does not match the response schema. Register the full parameterized media type
and select it with `accept` to limit the override to those calls:

```julia
ExampleClient.codec!(
    client,
    "application/json;stream=watch";
    decode = (bytes, media_type) -> JSON.parse(String(bytes)),
)
events = Channel{Any}(16)
ExampleClient.watch_pods(;
    client,
    accept = "application/json;stream=watch",
    stream_to = events,
)
```

This decoder does not replace the decoder for plain `application/json`.
Codecs are matched against the received Content-Type first, and streaming
calls fall back to the media type the call requested via `accept`: deployed
servers such as the Kubernetes apiserver reply with the bare
`application/json` even when the request selected the parameterized variant,
so passing `accept` is what scopes the override to the watch calls.
