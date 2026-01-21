# Stress Test for OpenAPI.jl Client

Stress testing suite for the OpenAPI.jl HTTP client.

## Quick Start

Run the stress test with default settings:

```bash
julia runtests.jl
```

## Configuration

Configure via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `STRESS_DURATION` | 30 | Test duration in seconds |
| `STRESS_CONCURRENCY` | 10 | Number of concurrent tasks |
| `STRESS_PAYLOAD_SIZE` | 1024 | POST payload size in bytes |
| `STRESS_HTTPLIB` | http | HTTP backend (`http` or `downloads`) |

## Examples

**Light test:**
```bash
STRESS_DURATION=5 STRESS_CONCURRENCY=5 julia runtests.jl
```

**Test with Downloads.jl backend:**
```bash
STRESS_HTTPLIB=downloads STRESS_DURATION=30 STRESS_CONCURRENCY=100 julia runtests.jl
```
