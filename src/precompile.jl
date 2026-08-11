using PrecompileTools: @compile_workload

# Client generation is normally a one-time startup operation. Exercise a small,
# representative document while OpenAPI precompiles so users do not pay the
# compiler cost when they generate their first client in a new Julia process.
const _PRECOMPILE_CLIENT_DOCUMENT = raw"""
{
  "openapi": "3.2.0",
  "info": {"title": "Precompile API", "version": "1.0.0"},
  "components": {
    "securitySchemes": {
      "BearerAuth": {"type": "http", "scheme": "bearer"}
    },
    "schemas": {
      "MonthlySummary": {
        "type": "object",
        "required": ["month", "energy"],
        "properties": {
          "month": {"type": "integer", "format": "int64"},
          "energy": {"type": "number", "format": "double"}
        },
        "additionalProperties": false
      },
      "Summary": {
        "type": "object",
        "required": ["best_day", "monthly"],
        "properties": {
          "best_day": {"type": "string", "format": "date"},
          "monthly": {
            "type": "array",
            "items": {"$ref": "#/components/schemas/MonthlySummary"}
          }
        },
        "additionalProperties": false
      }
    }
  },
  "paths": {
    "/simulate/{latitude}": {
      "get": {
        "operationId": "simulate",
        "security": [{"BearerAuth": []}],
        "parameters": [
          {
            "name": "latitude",
            "in": "path",
            "required": true,
            "schema": {"type": "number", "format": "double"}
          },
          {
            "name": "capacity",
            "in": "query",
            "schema": {"type": "number", "format": "double"}
          }
        ],
        "responses": {
          "200": {
            "description": "success",
            "content": {
              "application/json": {
                "schema": {"$ref": "#/components/schemas/Summary"}
              }
            }
          },
          "default": {
            "description": "unexpected error",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {"message": {"type": "string"}}
                }
              }
            }
          }
        }
      }
    }
  }
}
"""

@compile_workload begin
    precompile_source = read(
        _PRECOMPILE_CLIENT_DOCUMENT;
        base_uri = "https://precompile.openapi.invalid/openapi.json",
    )
    null_path = Sys.iswindows() ? "NUL" : "/dev/null"
    client(precompile_source; name = "PrecompileClient", path = null_path)
end
