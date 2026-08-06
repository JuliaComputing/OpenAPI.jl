const TRIM_OPENAPI_JSON = raw"""
{
  "openapi": "3.1.0",
  "info": {"title": "Trim API", "version": "1.0.0"},
  "servers": [{"url": "https://api.example.test/v1"}],
  "components": {
    "securitySchemes": {
      "BearerAuth": {"type": "http", "scheme": "bearer"}
    },
    "schemas": {
      "Widget": {
        "type": "object",
        "required": ["id", "name", "status"],
        "properties": {
          "id": {"type": "integer", "format": "int64"},
          "name": {"type": "string"},
          "status": {"type": "string", "enum": ["active", "disabled"]},
          "note": {"type": ["string", "null"]},
          "tags": {"type": "array", "items": {"type": "string"}}
        },
        "additionalProperties": false
      },
      "CreateWidget": {
        "type": "object",
        "required": ["name"],
        "properties": {
          "name": {"type": "string"},
          "tags": {"type": "array", "items": {"type": "string"}}
        },
        "additionalProperties": false
      },
      "Error": {
        "type": "object",
        "required": ["message"],
        "properties": {"message": {"type": "string"}}
      }
    }
  },
  "paths": {
    "/widgets/{id}": {
      "get": {
        "operationId": "getWidget",
        "parameters": [
          {
            "name": "id",
            "in": "path",
            "required": true,
            "schema": {"type": "integer", "format": "int64"}
          },
          {
            "name": "verbose",
            "in": "query",
            "schema": {"type": "boolean"}
          }
        ],
        "responses": {
          "200": {
            "description": "A widget",
            "content": {
              "application/json": {
                "schema": {"$ref": "#/components/schemas/Widget"}
              }
            }
          },
          "default": {
            "description": "An error",
            "content": {
              "application/json": {
                "schema": {"$ref": "#/components/schemas/Error"}
              }
            }
          }
        }
      }
    },
    "/widgets": {
      "post": {
        "operationId": "createWidget",
        "security": [{"BearerAuth": []}],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {"$ref": "#/components/schemas/CreateWidget"}
            }
          }
        },
        "responses": {
          "201": {
            "description": "Created",
            "content": {
              "application/json": {
                "schema": {"$ref": "#/components/schemas/Widget"}
              }
            }
          }
        }
      }
    },
    "/secret": {
      "get": {
        "operationId": "getSecret",
        "security": [{"BearerAuth": []}],
        "responses": {
          "200": {
            "description": "Secret text",
            "content": {
              "text/plain": {"schema": {"type": "string"}}
            }
          }
        }
      }
    }
  }
}
"""
