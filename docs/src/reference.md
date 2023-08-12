```@contents
Pages = ["reference.md"]
Depth = 3
```

```@meta
CurrentModule = OpenAPI
```

# API Reference

## Client

```@docs
Clients.Client
Clients.set_user_agent
Clients.set_cookie
Clients.set_header
Clients.set_timeout
```

## Examining Models

```@docs
hasproperty
getproperty
setproperty!
Clients.getpropertyat
Clients.haspropertyat
```

## Examining Client API Response

```@docs
Clients.ApiResponse
```

```@docs
Clients.is_longpoll_timeout
```

```@docs
Clients.is_request_interrupted
```

```@docs
Clients.storefile
```

## Server

The server code is generated as a package. It contains API stubs and validations of API inputs. It requires the caller to
have implemented the APIs, the signatures of which are provided in the generated package module docstring.

Refer to the User Guide section for mode details of the API that is generated.

## Tools

```@docs
swagger_ui
stop_swagger_ui
swagger_editor
stop_swagger_editor
lint
```