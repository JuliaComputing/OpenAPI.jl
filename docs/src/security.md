# Security

Generated clients implement OpenAPI security requirement alternatives and
combinations. Supported credentials include:

- API keys in headers, query parameters, or cookies;
- HTTP Basic and Bearer authentication;
- other HTTP authentication values;
- OAuth 2.0 and OpenID Connect bearer tokens with documented scope checks;
- mutual TLS through HTTP request options.

```julia
ExampleClient.credential!(
    client,
    "bearerAuth",
    ExampleClient.BearerCredential("token"; scopes = ["widgets:read"]),
)
```

`authorization!(client, token)` is a convenience for every bearer-compatible
scheme in a document. The generated client does not acquire or refresh OAuth or
OpenID Connect tokens. The caller owns that lifecycle.

By default, a secured operation fails before network access when no documented
credential alternative can be satisfied. Set `require_credentials=false` only
when an external HTTP layer supplies authentication.

## Externally declared schemes

A document loaded with `strict=false` may name security schemes in operation
`security` that its own `components` never declare — a common production shape
where authentication lives in a gateway and the schemes are declared by an
umbrella document. Strict mode rejects such documents (the Security Requirement
name rule is normative); permissive mode warns and treats the scheme as
externally declared. Generation then excludes it from operation security
descriptors — the runtime cannot construct credentials for a scheme it cannot
see — and the caller supplies gateway authentication explicitly, for example
through `request_headers`:

```julia
ExampleClient.get_widget("widget-123";
    client,
    request_headers = ["Authorization" => "Bearer $(gateway_token)"],
)
```

Generated **servers** never authenticate or authorize requests; see
[Generating servers](servers.md).
