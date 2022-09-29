# This file was generated by the Julia OpenAPI Code Generator
# Do not modify this file directly. Modify the OpenAPI specification instead.

struct UserApi <: OpenAPI.APIClientImpl
    client::OpenAPI.Clients.Client
end

function _oacinternal_create_user(_api::UserApi, body::User; _mediaType=nothing)
    return_types = Dict{Regex,Type}()
    return_types[Regex("^" * replace("0", "x"=>".") * "\$")] = Nothing

    _ctx = OpenAPI.Clients.Ctx(_api.client, "POST", return_types, "/user", [], body)
    OpenAPI.Clients.set_header_accept(_ctx, [])
    OpenAPI.Clients.set_header_content_type(_ctx, (_mediaType === nothing) ? ["application/json", ] : [_mediaType])
    return _ctx
end

@doc raw"""Create user

This can only be done by the logged in user.

Params:
- body::User (required)

Return: Nothing
"""
function create_user(_api::UserApi, body::User; _mediaType=nothing)
    _ctx = _oacinternal_create_user(_api, body; _mediaType=_mediaType)
    return OpenAPI.Clients.exec(_ctx)
end

function create_user(_api::UserApi, response_stream::Channel, body::User; _mediaType=nothing)
    _ctx = _oacinternal_create_user(_api, body; _mediaType=_mediaType)
    return OpenAPI.Clients.exec(_ctx, response_stream)
end

function _oacinternal_create_users_with_array_input(_api::UserApi, body::Vector{User}; _mediaType=nothing)
    return_types = Dict{Regex,Type}()
    return_types[Regex("^" * replace("0", "x"=>".") * "\$")] = Nothing

    _ctx = OpenAPI.Clients.Ctx(_api.client, "POST", return_types, "/user/createWithArray", [], body)
    OpenAPI.Clients.set_header_accept(_ctx, [])
    OpenAPI.Clients.set_header_content_type(_ctx, (_mediaType === nothing) ? ["application/json", ] : [_mediaType])
    return _ctx
end

@doc raw"""Creates list of users with given input array

Params:
- body::Vector{User} (required)

Return: Nothing
"""
function create_users_with_array_input(_api::UserApi, body::Vector{User}; _mediaType=nothing)
    _ctx = _oacinternal_create_users_with_array_input(_api, body; _mediaType=_mediaType)
    return OpenAPI.Clients.exec(_ctx)
end

function create_users_with_array_input(_api::UserApi, response_stream::Channel, body::Vector{User}; _mediaType=nothing)
    _ctx = _oacinternal_create_users_with_array_input(_api, body; _mediaType=_mediaType)
    return OpenAPI.Clients.exec(_ctx, response_stream)
end

function _oacinternal_create_users_with_list_input(_api::UserApi, body::Vector{User}; _mediaType=nothing)
    return_types = Dict{Regex,Type}()
    return_types[Regex("^" * replace("0", "x"=>".") * "\$")] = Nothing

    _ctx = OpenAPI.Clients.Ctx(_api.client, "POST", return_types, "/user/createWithList", [], body)
    OpenAPI.Clients.set_header_accept(_ctx, [])
    OpenAPI.Clients.set_header_content_type(_ctx, (_mediaType === nothing) ? ["application/json", ] : [_mediaType])
    return _ctx
end

@doc raw"""Creates list of users with given input array

Params:
- body::Vector{User} (required)

Return: Nothing
"""
function create_users_with_list_input(_api::UserApi, body::Vector{User}; _mediaType=nothing)
    _ctx = _oacinternal_create_users_with_list_input(_api, body; _mediaType=_mediaType)
    return OpenAPI.Clients.exec(_ctx)
end

function create_users_with_list_input(_api::UserApi, response_stream::Channel, body::Vector{User}; _mediaType=nothing)
    _ctx = _oacinternal_create_users_with_list_input(_api, body; _mediaType=_mediaType)
    return OpenAPI.Clients.exec(_ctx, response_stream)
end

function _oacinternal_delete_user(_api::UserApi, username::String; _mediaType=nothing)
    return_types = Dict{Regex,Type}()
    return_types[Regex("^" * replace("400", "x"=>".") * "\$")] = Nothing
    return_types[Regex("^" * replace("404", "x"=>".") * "\$")] = Nothing

    _ctx = OpenAPI.Clients.Ctx(_api.client, "DELETE", return_types, "/user/{username}", [])
    OpenAPI.Clients.set_param(_ctx.path, "username", username)  # type String
    OpenAPI.Clients.set_header_accept(_ctx, [])
    OpenAPI.Clients.set_header_content_type(_ctx, (_mediaType === nothing) ? [] : [_mediaType])
    return _ctx
end

@doc raw"""Delete user

This can only be done by the logged in user.

Params:
- username::String (required)

Return: Nothing
"""
function delete_user(_api::UserApi, username::String; _mediaType=nothing)
    _ctx = _oacinternal_delete_user(_api, username; _mediaType=_mediaType)
    return OpenAPI.Clients.exec(_ctx)
end

function delete_user(_api::UserApi, response_stream::Channel, username::String; _mediaType=nothing)
    _ctx = _oacinternal_delete_user(_api, username; _mediaType=_mediaType)
    return OpenAPI.Clients.exec(_ctx, response_stream)
end

function _oacinternal_get_user_by_name(_api::UserApi, username::String; _mediaType=nothing)
    return_types = Dict{Regex,Type}()
    return_types[Regex("^" * replace("200", "x"=>".") * "\$")] = User
    return_types[Regex("^" * replace("400", "x"=>".") * "\$")] = Nothing
    return_types[Regex("^" * replace("404", "x"=>".") * "\$")] = Nothing

    _ctx = OpenAPI.Clients.Ctx(_api.client, "GET", return_types, "/user/{username}", [])
    OpenAPI.Clients.set_param(_ctx.path, "username", username)  # type String
    OpenAPI.Clients.set_header_accept(_ctx, ["application/json", "application/xml", ])
    OpenAPI.Clients.set_header_content_type(_ctx, (_mediaType === nothing) ? [] : [_mediaType])
    return _ctx
end

@doc raw"""Get user by user name

Params:
- username::String (required)

Return: User
"""
function get_user_by_name(_api::UserApi, username::String; _mediaType=nothing)
    _ctx = _oacinternal_get_user_by_name(_api, username; _mediaType=_mediaType)
    return OpenAPI.Clients.exec(_ctx)
end

function get_user_by_name(_api::UserApi, response_stream::Channel, username::String; _mediaType=nothing)
    _ctx = _oacinternal_get_user_by_name(_api, username; _mediaType=_mediaType)
    return OpenAPI.Clients.exec(_ctx, response_stream)
end

function _oacinternal_login_user(_api::UserApi, username::String, password::String; _mediaType=nothing)
    return_types = Dict{Regex,Type}()
    return_types[Regex("^" * replace("200", "x"=>".") * "\$")] = String
    return_types[Regex("^" * replace("400", "x"=>".") * "\$")] = Nothing

    _ctx = OpenAPI.Clients.Ctx(_api.client, "GET", return_types, "/user/login", [])
    OpenAPI.Clients.set_param(_ctx.query, "username", username)  # type String
    OpenAPI.Clients.set_param(_ctx.query, "password", password)  # type String
    OpenAPI.Clients.set_header_accept(_ctx, ["application/json", "application/xml", ])
    OpenAPI.Clients.set_header_content_type(_ctx, (_mediaType === nothing) ? [] : [_mediaType])
    return _ctx
end

@doc raw"""Logs user into the system

Params:
- username::String (required)
- password::String (required)

Return: String
"""
function login_user(_api::UserApi, username::String, password::String; _mediaType=nothing)
    _ctx = _oacinternal_login_user(_api, username, password; _mediaType=_mediaType)
    return OpenAPI.Clients.exec(_ctx)
end

function login_user(_api::UserApi, response_stream::Channel, username::String, password::String; _mediaType=nothing)
    _ctx = _oacinternal_login_user(_api, username, password; _mediaType=_mediaType)
    return OpenAPI.Clients.exec(_ctx, response_stream)
end

function _oacinternal_logout_user(_api::UserApi; _mediaType=nothing)
    return_types = Dict{Regex,Type}()
    return_types[Regex("^" * replace("0", "x"=>".") * "\$")] = Nothing

    _ctx = OpenAPI.Clients.Ctx(_api.client, "GET", return_types, "/user/logout", [])
    OpenAPI.Clients.set_header_accept(_ctx, [])
    OpenAPI.Clients.set_header_content_type(_ctx, (_mediaType === nothing) ? [] : [_mediaType])
    return _ctx
end

@doc raw"""Logs out current logged in user session

Params:

Return: Nothing
"""
function logout_user(_api::UserApi; _mediaType=nothing)
    _ctx = _oacinternal_logout_user(_api; _mediaType=_mediaType)
    return OpenAPI.Clients.exec(_ctx)
end

function logout_user(_api::UserApi, response_stream::Channel; _mediaType=nothing)
    _ctx = _oacinternal_logout_user(_api; _mediaType=_mediaType)
    return OpenAPI.Clients.exec(_ctx, response_stream)
end

function _oacinternal_update_user(_api::UserApi, username::String, body::User; _mediaType=nothing)
    return_types = Dict{Regex,Type}()
    return_types[Regex("^" * replace("400", "x"=>".") * "\$")] = Nothing
    return_types[Regex("^" * replace("404", "x"=>".") * "\$")] = Nothing

    _ctx = OpenAPI.Clients.Ctx(_api.client, "PUT", return_types, "/user/{username}", [], body)
    OpenAPI.Clients.set_param(_ctx.path, "username", username)  # type String
    OpenAPI.Clients.set_header_accept(_ctx, [])
    OpenAPI.Clients.set_header_content_type(_ctx, (_mediaType === nothing) ? ["application/json", ] : [_mediaType])
    return _ctx
end

@doc raw"""Updated user

This can only be done by the logged in user.

Params:
- username::String (required)
- body::User (required)

Return: Nothing
"""
function update_user(_api::UserApi, username::String, body::User; _mediaType=nothing)
    _ctx = _oacinternal_update_user(_api, username, body; _mediaType=_mediaType)
    return OpenAPI.Clients.exec(_ctx)
end

function update_user(_api::UserApi, response_stream::Channel, username::String, body::User; _mediaType=nothing)
    _ctx = _oacinternal_update_user(_api, username, body; _mediaType=_mediaType)
    return OpenAPI.Clients.exec(_ctx, response_stream)
end

export create_user
export create_users_with_array_input
export create_users_with_list_input
export delete_user
export get_user_by_name
export login_user
export logout_user
export update_user
