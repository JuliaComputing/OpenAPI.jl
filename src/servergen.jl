# Server-stub generation. The framework-neutral request engine below is pasted
# into generated server modules, which import the shared decode/validate
# machinery from OpenAPI.Runtime; framework packages (HTTP.jl through
# OpenAPIHTTPExt, Servo.jl through ServoOpenAPIExt) add `OpenAPI.server_source`
# methods that wrap it with router glue.

# Emitted at the top of every generated server module.
const GENERATED_SERVER_IMPORTS = raw"""
const SchemaEngine = OpenAPI.SchemaEngine
import OpenAPI.Runtime:
    ABSENT, Absent, DecodeError, MultipartPartHeaders, SchemaValidationError,
    UnsupportedMediaType, Upload, _DeepObjectLeaf,
    _base_media_type, _decode, _decode_schema_header, _decode_sequential_json,
    _deep_object_assign!, _deep_object_coerce, _deep_object_path,
    _encode, _encode_sequential_json, _form_fields, _header_atom, _header_scalar,
    _header_type_variant, _header_values, _is_json_media, _is_sequential_json_media,
    _media_type, _object, _parse_json, _required, _safe_header, _schema_valid,
    _select_media, _validate_schema
"""

# Emitted after the schema data constants; packages the document-specific
# validation data for the shared runtime.
const GENERATED_SERVER_SPEC = raw"""
const _SPEC = Runtime.Spec(;
    security_schemes = _SECURITY_SCHEMES,
    resources = _SCHEMA_RESOURCE_DATA,
    roots = _SCHEMA_ROOT_DATA,
    dialects = _SCHEMA_DIALECT_DATA,
    directional_required = _SCHEMA_DIRECTIONAL_REQUIRED,
    default_server = "",
)
"""

const GENERATED_RUNTIME_SERVER = raw"""
struct _RequestFailure <: Exception
    status::Int
    message::String
end
Base.showerror(io::IO, error::_RequestFailure) = print(io, error.message)

_is_hex_byte(byte::UInt8) =
    UInt8('0') <= byte <= UInt8('9') ||
    UInt8('a') <= byte <= UInt8('f') ||
    UInt8('A') <= byte <= UInt8('F')

function _percent_decode(text::AbstractString; plus_space::Bool = false)
    bytes = codeunits(String(text))
    occursin('%', text) || (plus_space && occursin('+', text)) ||
        return String(text)
    io = IOBuffer()
    index = 1
    while index <= length(bytes)
        byte = bytes[index]
        if byte == UInt8('%')
            index + 2 <= length(bytes) &&
                _is_hex_byte(bytes[index + 1]) &&
                _is_hex_byte(bytes[index + 2]) ||
                throw(_RequestFailure(400, "invalid percent-encoding in request"))
            write(io, parse(UInt8, String(Char.(bytes[index + 1:index + 2])); base = 16))
            index += 3
        elseif plus_space && byte == UInt8('+')
            write(io, ' ')
            index += 1
        else
            write(io, byte)
            index += 1
        end
    end
    output = String(take!(io))
    isvalid(output) ||
        throw(_RequestFailure(400, "invalid percent-encoding in request"))
    return output
end

# Pair keys are percent-decoded; values stay raw so style delimiters emitted by
# clients (which escape delimiter characters inside items) survive splitting.
function _wire_pairs(text::AbstractString, pair_delimiters; plus_space::Bool = false)
    output = Pair{String,String}[]
    for token in split(text, char -> char in pair_delimiters)
        stripped = strip(token)
        isempty(stripped) && continue
        raw = split(stripped, '='; limit = 2)
        key = _percent_decode(raw[1]; plus_space)
        push!(output, key => (length(raw) == 2 ? String(raw[2]) : ""))
    end
    return output
end

_query_pairs(query::AbstractString) = _wire_pairs(query, ('&',); plus_space = true)

function _cookie_pairs(headers)
    output = Pair{String,String}[]
    for value in _header_values(headers, "Cookie")
        append!(output, _wire_pairs(value, (';', '&')))
    end
    return output
end

_typed_scalar(type, text) = _header_scalar(_header_type_variant(type, :scalar), text)

function _typed_array(type, items)
    selected = _header_type_variant(type, :array)
    element = selected <: AbstractVector ? eltype(selected) : String
    return Any[_header_scalar(element, item) for item in items]
end

function _object_from_kv_tokens(tokens, context; decode::Bool = false)
    object = JSON.Object{String,Any}()
    for token in tokens
        pair = split(token, '='; limit = 2)
        length(pair) == 2 ||
            throw(_RequestFailure(400, "invalid object value while " * context))
        key = decode ? _percent_decode(String(pair[1])) : String(pair[1])
        item = decode ? _percent_decode(String(pair[2])) : String(pair[2])
        object[key] = _header_atom(item)
    end
    return object
end

function _object_from_alternating(tokens, context; decode::Bool = false)
    iseven(length(tokens)) ||
        throw(_RequestFailure(400, "invalid object value while " * context))
    object = JSON.Object{String,Any}()
    for index in 1:2:length(tokens)
        key = decode ? _percent_decode(String(tokens[index])) : String(tokens[index])
        item = decode ? _percent_decode(String(tokens[index + 1])) : String(tokens[index + 1])
        object[key] = _header_atom(item)
    end
    return object
end

function _finish_parameter(descriptor, value, context)
    # _typed_scalar/_typed_array already construct generated value types (via
    # _header_scalar), so decode from the encoded wire form: decoding the typed
    # value itself would validate a Julia struct against its raw JSON schema.
    encoded = _encode(value)
    _validate_schema(_SPEC, descriptor.schema, encoded, context; direction = :input)
    return _decode(descriptor.type, encoded)
end

function _decode_parameter_content(descriptor, text, context)
    entry = first(descriptor.content)
    media = _base_media_type(entry.media_type)
    if _is_json_media(media)
        value = _parse_json(text, context)
        _validate_schema(_SPEC, entry.schema, value, context; direction = :input)
        return _decode(descriptor.type, value)
    end
    _validate_schema(_SPEC, entry.schema, text, context; direction = :input)
    return _decode(descriptor.type, text)
end

function _decode_path_parameter(descriptor, raw)
    text = String(raw)
    context = string("decoding path parameter ", descriptor.name)
    isempty(descriptor.content) ||
        return _decode_parameter_content(descriptor, _percent_decode(text), context)
    style = descriptor.style
    shape = descriptor.shape
    explode = descriptor.explode
    value = if style === :label
        startswith(text, '.') ||
            throw(_RequestFailure(400, "invalid label value while " * context))
        body = SubString(text, 2)
        if shape === :array
            _typed_array(
                descriptor.type,
                [_percent_decode(String(item)) for item in split(body, explode ? '.' : ',')],
            )
        elseif shape === :object
            explode ? _object_from_kv_tokens(split(body, '.'), context; decode = true) :
            _object_from_alternating(split(body, ','), context; decode = true)
        else
            _typed_scalar(descriptor.type, _percent_decode(String(body)))
        end
    elseif style === :matrix
        startswith(text, ';') ||
            throw(_RequestFailure(400, "invalid matrix value while " * context))
        tokens = split(SubString(text, 2), ';')
        if shape === :array && explode
            items = String[]
            for token in tokens
                pair = split(token, '='; limit = 2)
                _percent_decode(String(pair[1])) == descriptor.name || continue
                push!(items, length(pair) == 2 ? _percent_decode(String(pair[2])) : "")
            end
            _typed_array(descriptor.type, items)
        elseif shape === :object && explode
            _object_from_kv_tokens(tokens, context; decode = true)
        else
            payload = nothing
            for token in tokens
                pair = split(token, '='; limit = 2)
                _percent_decode(String(pair[1])) == descriptor.name || continue
                payload = length(pair) == 2 ? String(pair[2]) : ""
                break
            end
            payload === nothing &&
                throw(_RequestFailure(400, "missing matrix value while " * context))
            if shape === :array
                _typed_array(
                    descriptor.type,
                    [_percent_decode(String(item)) for item in split(payload, ',')],
                )
            elseif shape === :object
                _object_from_alternating(split(payload, ','), context; decode = true)
            else
                _typed_scalar(descriptor.type, _percent_decode(payload))
            end
        end
    else # simple
        if shape === :array
            _typed_array(
                descriptor.type,
                [_percent_decode(String(item)) for item in split(text, ',')],
            )
        elseif shape === :object
            explode ? _object_from_kv_tokens(split(text, ','), context; decode = true) :
            _object_from_alternating(split(text, ','), context; decode = true)
        else
            _typed_scalar(descriptor.type, _percent_decode(text))
        end
    end
    return _finish_parameter(descriptor, value, context)
end

function _first_pair_index(pairs, name)
    for (index, pair) in enumerate(pairs)
        pair.first == name && return index
    end
    return nothing
end

function _decode_form_parameter(descriptor, pairs, consumed, context; plus_space::Bool)
    name = descriptor.name
    decoded(raw) = _percent_decode(String(raw); plus_space)
    if descriptor.shape === :array
        if descriptor.explode
            items = String[]
            for (index, pair) in enumerate(pairs)
                pair.first == name || continue
                consumed[index] = true
                push!(items, decoded(pair.second))
            end
            isempty(items) && return ABSENT
            return _finish_parameter(descriptor, _typed_array(descriptor.type, items), context)
        end
        index = _first_pair_index(pairs, name)
        index === nothing && return ABSENT
        consumed[index] = true
        items = [decoded(item) for item in split(pairs[index].second, ',')]
        return _finish_parameter(descriptor, _typed_array(descriptor.type, items), context)
    elseif descriptor.shape === :object
        # Exploded objects consume the wire names no other parameter claimed;
        # the caller collects them after every named parameter is decoded.
        descriptor.explode && return ABSENT
        index = _first_pair_index(pairs, name)
        index === nothing && return ABSENT
        consumed[index] = true
        tokens = [decoded(item) for item in split(pairs[index].second, ',')]
        return _finish_parameter(
            descriptor,
            _object_from_alternating(tokens, context),
            context,
        )
    end
    index = _first_pair_index(pairs, name)
    index === nothing && return ABSENT
    consumed[index] = true
    return _finish_parameter(
        descriptor,
        _typed_scalar(descriptor.type, decoded(pairs[index].second)),
        context,
    )
end

function _decode_query_parameter(descriptor, pairs, consumed)
    context = string("decoding query parameter ", descriptor.name)
    name = descriptor.name
    if !isempty(descriptor.content)
        index = _first_pair_index(pairs, name)
        index === nothing && return ABSENT
        consumed[index] = true
        return _decode_parameter_content(
            descriptor,
            _percent_decode(String(pairs[index].second); plus_space = true),
            context,
        )
    end
    style = descriptor.style
    if style === :deepObject
        # Bracket paths (`name[a][0][field]=v`, `name[]=v`) build a tree of
        # objects whose JSON shape the parameter schema settles afterwards.
        value = nothing
        found = false
        for (index, pair) in enumerate(pairs)
            path = _deep_object_path(pair.first, name)
            path === nothing && continue
            leaf = _DeepObjectLeaf(_percent_decode(String(pair.second); plus_space = true))
            value = _deep_object_assign!(value, path, leaf)
            consumed[index] = true
            found = true
        end
        found || return ABSENT
        return _finish_parameter(
            descriptor,
            _deep_object_coerce(_SPEC, descriptor.schema, value),
            context,
        )
    elseif style === :spaceDelimited || style === :pipeDelimited
        index = _first_pair_index(pairs, name)
        index === nothing && return ABSENT
        consumed[index] = true
        delimiter = style === :spaceDelimited ? ' ' : '|'
        tokens = split(
            _percent_decode(String(pairs[index].second); plus_space = true),
            delimiter,
        )
        if descriptor.shape === :object
            return _finish_parameter(
                descriptor,
                _object_from_alternating(String.(tokens), context),
                context,
            )
        end
        return _finish_parameter(
            descriptor,
            _typed_array(descriptor.type, String.(tokens)),
            context,
        )
    end
    return _decode_form_parameter(descriptor, pairs, consumed, context; plus_space = true)
end

function _decode_cookie_parameter(descriptor, pairs, consumed)
    context = string("decoding cookie parameter ", descriptor.name)
    if !isempty(descriptor.content)
        index = _first_pair_index(pairs, descriptor.name)
        index === nothing && return ABSENT
        consumed[index] = true
        return _decode_parameter_content(
            descriptor,
            _percent_decode(String(pairs[index].second)),
            context,
        )
    end
    return _decode_form_parameter(descriptor, pairs, consumed, context; plus_space = false)
end

function _decode_header_parameter(descriptor, headers)
    values = _header_values(headers, descriptor.name)
    isempty(values) && return ABSENT
    context = string("decoding header parameter ", descriptor.name)
    isempty(descriptor.content) ||
        return _decode_parameter_content(descriptor, join(values, ','), context)
    return _decode_schema_header(_SPEC, 
        descriptor.type,
        values,
        descriptor.shape,
        descriptor.explode === true,
        descriptor.schema;
        direction = :input,
        context,
    )
end

function _collect_exploded_object(descriptor, pairs, consumed, context; plus_space::Bool)
    object = JSON.Object{String,Any}()
    for (index, pair) in enumerate(pairs)
        consumed[index] && continue
        object[pair.first] =
            _header_atom(_percent_decode(String(pair.second); plus_space))
        consumed[index] = true
    end
    isempty(object) && !descriptor.required && return ABSENT
    return _finish_parameter(descriptor, object, context)
end

function _encoding_for(encodings, name)
    for encoding in encodings
        encoding.name == name && return encoding
    end
    return nothing
end

function _field_shape(fields, name)
    for field in fields
        field.name == name && return field.shape
    end
    return :scalar
end

function _field_value_kind(fields, name)
    for field in fields
        field.name == name || continue
        return field.shape === :array ? field.item_kind : field.kind
    end
    return :default
end

function _form_field_value(fields, name, text, context)
    kind = _field_value_kind(fields, name)
    kind === :object && return _parse_json(text, context)
    kind in (:string, :bytes) && return String(text)
    return _header_atom(text)
end

function _push_form_value!(object, fields, name, value)
    if haskey(object, name)
        existing = object[name]
        object[name] = existing isa Vector{Any} ? push!(existing, value) :
                       Any[existing, value]
    elseif _field_shape(fields, name) === :array && !(value isa Vector{Any})
        object[name] = Any[value]
    else
        object[name] = value
    end
    return object
end

function _form_body_object(body, encodings, fields)
    object = JSON.Object{String,Any}()
    text = String(copy(body))
    isvalid(text) ||
        throw(_RequestFailure(400, "form request body is not valid UTF-8"))
    for pair in _wire_pairs(text, ('&',); plus_space = true)
        name = pair.first
        encoding = _encoding_for(encodings, name)
        media = encoding === nothing ? "" :
                _base_media_type(something(encoding.content_type, ""))
        value = if !isempty(media) && _is_json_media(media)
            _parse_json(
                _percent_decode(String(pair.second); plus_space = true),
                "decoding form field " * name,
            )
        elseif encoding !== nothing && encoding.explode === false
            delimiter = encoding.style === :spaceDelimited ? ' ' :
                        encoding.style === :pipeDelimited ? '|' : ','
            Any[
                _header_atom(_percent_decode(String(item); plus_space = true))
                for item in split(pair.second, delimiter)
            ]
        else
            _form_field_value(
                fields,
                name,
                _percent_decode(String(pair.second); plus_space = true),
                "decoding form field " * name,
            )
        end
        _push_form_value!(object, fields, name, value)
    end
    return object
end

function _multipart_body_object(parts, encodings, fields)
    object = JSON.Object{String,Any}()
    for part in parts
        name = String(part.name)
        encoding = _encoding_for(encodings, name)
        declared = something(part.content_type, "")
        media = _base_media_type(
            !isempty(declared) ? declared :
            encoding === nothing ? "" : something(encoding.content_type, ""),
        )
        kind = _field_value_kind(fields, name)
        value = if _is_json_media(media)
            _parse_json(part.data, "decoding multipart field " * name)
        elseif kind === :object
            _parse_json(part.data, "decoding multipart field " * name)
        elseif kind === :bytes
            Base64.base64encode(part.data)
        elseif kind === :string
            isvalid(String, part.data) ||
                throw(_RequestFailure(400, "multipart string field is not valid UTF-8"))
            String(copy(part.data))
        elseif isvalid(String, part.data)
            _header_atom(String(copy(part.data)))
        else
            Base64.base64encode(part.data)
        end
        _push_form_value!(object, fields, name, value)
    end
    return object
end

function _decode_request_body(operation, headers, body, parts)
    request = operation.request
    request === nothing && return (false, nothing)
    content_values = _header_values(headers, "Content-Type")
    content_type = isempty(content_values) ? "" : first(content_values)
    if isempty(body) && parts === nothing && isempty(content_type)
        request.required &&
            throw(_RequestFailure(400, "missing required request body"))
        return (false, nothing)
    end
    entry = isempty(content_type) ? first(request.media) :
            _select_media(request.media, content_type)
    entry === nothing &&
        throw(UnsupportedMediaType(String(content_type), :request))
    media = _base_media_type(
        isempty(content_type) ? entry.media_type : content_type,
    )
    type = entry.type
    schema = entry.schema
    encodings = entry.encodings
    fields = entry.fields
    context = "decoding the request body"
    if media == "multipart/form-data"
        parts === nothing &&
            throw(_RequestFailure(400, "invalid multipart request body"))
        value = _multipart_body_object(parts, encodings, fields)
        _validate_schema(_SPEC, schema, _encode(value), context; direction = :input)
        return (true, _decode(type, value))
    elseif media == "application/x-www-form-urlencoded"
        value = _form_body_object(body, encodings, fields)
        _validate_schema(_SPEC, schema, value, context; direction = :input)
        return (true, _decode(type, value))
    elseif _is_json_media(media)
        if isempty(body)
            request.required &&
                throw(_RequestFailure(400, "missing required request body"))
            return (false, nothing)
        end
        value = _parse_json(body, context)
        _validate_schema(_SPEC, schema, value, context; direction = :input)
        return (true, _decode(type, value))
    elseif _is_sequential_json_media(media)
        value = _decode_sequential_json(body, media)
        _validate_schema(_SPEC, schema, value, context; direction = :input)
        return (true, _decode(type, value))
    elseif startswith(media, "text/") || type === String
        isvalid(String, body) ||
            throw(_RequestFailure(400, "text request body is not valid UTF-8"))
        value = String(copy(body))
        _validate_schema(_SPEC, schema, value, context; direction = :input)
        return (true, _decode(type, value))
    end
    _validate_schema(_SPEC, schema, Base64.base64encode(body), context; direction = :input)
    return (true, type === Any ? copy(body) : _decode(type, copy(body)))
end

function _validate_parameter_descriptor(descriptor)
    styles = if descriptor.location === :path
        (:simple, :label, :matrix)
    elseif descriptor.location === :query
        (:form, :spaceDelimited, :pipeDelimited, :deepObject)
    elseif descriptor.location === :header
        (:simple,)
    elseif descriptor.location === :cookie
        (:form, :cookie)
    else
        throw(ArgumentError(
            "unsupported parameter location $(repr(descriptor.location)) in generated descriptor",
        ))
    end
    isempty(descriptor.content) || return nothing
    descriptor.shape in (:scalar, :array, :object) || throw(ArgumentError(
        "unsupported parameter shape $(repr(descriptor.shape)) in generated descriptor",
    ))
    descriptor.style in styles || throw(ArgumentError(
        "unsupported $(descriptor.location) parameter style $(repr(descriptor.style)) in generated descriptor",
    ))
    descriptor.explode isa Bool || throw(ArgumentError(
        "unsupported parameter explode value $(repr(descriptor.explode)) in generated descriptor",
    ))
    return nothing
end

function _operation_arguments(entry, path_params, query_string, headers, body, parts)
    operation = entry.operation
    query = _query_pairs(query_string)
    query_consumed = falses(length(query))
    cookies = nothing
    cookie_consumed = nothing
    values = Dict{Symbol,Any}()
    exploded_query = nothing
    exploded_cookie = nothing
    for descriptor in operation.parameters
        _validate_parameter_descriptor(descriptor)
        decoded = try
            if descriptor.location === :path
                raw = get(path_params, descriptor.name, nothing)
                raw === nothing ?
                throw(_RequestFailure(400, string("missing path parameter ", descriptor.name))) :
                _decode_path_parameter(descriptor, raw)
            elseif descriptor.location === :query
                if isempty(descriptor.content) &&
                   descriptor.style === :form &&
                   descriptor.explode === true && descriptor.shape === :object
                    exploded_query = descriptor
                    continue
                end
                _decode_query_parameter(descriptor, query, query_consumed)
            elseif descriptor.location === :header
                _decode_header_parameter(descriptor, headers)
            elseif descriptor.location === :cookie
                if cookies === nothing
                    cookies = _cookie_pairs(headers)
                    cookie_consumed = falses(length(cookies))
                end
                if isempty(descriptor.content) &&
                   descriptor.style in (:form, :cookie) &&
                   descriptor.explode === true && descriptor.shape === :object
                    exploded_cookie = descriptor
                    continue
                end
                _decode_cookie_parameter(descriptor, cookies, cookie_consumed)
            else
                throw(_RequestFailure(
                    400,
                    string("unsupported parameter location ", descriptor.location),
                ))
            end
        catch error
            error isa DecodeError ? throw(DecodeError(string(
                "invalid ",
                descriptor.location,
                " parameter ",
                descriptor.name,
                ": ",
                error.message,
            ))) : rethrow()
        end
        if decoded isa Absent
            descriptor.required && throw(_RequestFailure(
                400,
                string("missing required ", descriptor.location, " parameter ", descriptor.name),
            ))
            continue
        end
        values[descriptor.arg] = decoded
    end
    if exploded_query !== nothing
        decoded = _collect_exploded_object(
            exploded_query,
            query,
            query_consumed,
            string("decoding query parameter ", exploded_query.name);
            plus_space = true,
        )
        decoded isa Absent || (values[exploded_query.arg] = decoded)
    end
    if exploded_cookie !== nothing
        decoded = _collect_exploded_object(
            exploded_cookie,
            cookies,
            cookie_consumed,
            string("decoding cookie parameter ", exploded_cookie.name);
            plus_space = false,
        )
        decoded isa Absent || (values[exploded_cookie.arg] = decoded)
    end
    has_body, decoded_body = _decode_request_body(operation, headers, body, parts)
    args = Any[values[arg] for arg in entry.path_args]
    entry.required_body && begin
        has_body || throw(_RequestFailure(400, "missing required request body"))
        push!(args, decoded_body)
    end
    kwargs = Pair{Symbol,Any}[]
    for descriptor in operation.parameters
        descriptor.location === :path && continue
        haskey(values, descriptor.arg) || continue
        push!(kwargs, descriptor.arg => values[descriptor.arg])
    end
    !entry.required_body && has_body && push!(kwargs, :body => decoded_body)
    return args, kwargs
end

function _selector_status(selector)
    normalized = uppercase(String(selector))
    all(isdigit, normalized) && return parse(Int, normalized)
    return 200
end

function _success_response(responses)
    range = nothing
    fallback = nothing
    for response in responses
        selector = uppercase(response.selector)
        if !isempty(selector) && all(isdigit, selector) && startswith(selector, '2')
            return response
        elseif selector == "2XX"
            range === nothing && (range = response)
        elseif selector == "DEFAULT"
            fallback === nothing && (fallback = response)
        end
    end
    return something(range, fallback, Some(nothing))
end

function _server_response(operation, result)
    descriptor = _success_response(operation.responses)
    if descriptor === nothing
        # The OAS Responses Object is non-exhaustive documentation, and some
        # documents cover only error codes (flagged at planning time as
        # :missing_success_response). Answer `nothing` with an empty 200; a
        # typed value has no documented media to encode against.
        result === nothing && return (200, Pair{String,String}[], UInt8[])
        throw(ArgumentError(string(
            "operation ",
            operation.id,
            " documents no success response; return `nothing` for an empty 200 or a framework response",
        )))
    end
    status = _selector_status(descriptor.selector)
    if isempty(descriptor.media)
        result === nothing || throw(ArgumentError(string(
            "operation ",
            operation.id,
            " documents no success response content; return `nothing` or a framework response",
        )))
        return (status, Pair{String,String}[], UInt8[])
    end
    if result === nothing && all(
        entry -> !_is_json_media(_base_media_type(entry.media_type)),
        descriptor.media,
    )
        throw(ArgumentError(string(
            "operation ",
            operation.id,
            " cannot encode `nothing` using its documented non-JSON success media types",
        )))
    end
    index = something(
        findfirst(
            entry -> _is_json_media(_base_media_type(entry.media_type)),
            descriptor.media,
        ),
        1,
    )
    entry = descriptor.media[index]
    media = _base_media_type(entry.media_type)
    context = string("encoding the ", operation.id, " response body")
    if _is_json_media(media)
        lowered = _encode(result)
        _validate_schema(_SPEC, entry.schema, lowered, context; direction = :output)
        payload = Vector{UInt8}(codeunits(JSON.json(lowered)))
    elseif _is_sequential_json_media(media)
        # Sequential media is documented either with an array schema covering
        # the whole sequence (planned as a vector type) or with the schema of
        # one record (planned as the item type); validate accordingly.
        lowered = _encode(result)
        lowered isa AbstractVector || lowered isa Tuple || throw(ArgumentError(string(
            "operation ",
            operation.id,
            " documents a sequential JSON response; return an array or tuple of items",
        )))
        if entry.type <: AbstractVector && entry.type !== Vector{UInt8}
            _validate_schema(_SPEC, entry.schema, lowered, context; direction = :output)
        else
            for item in lowered
                _validate_schema(_SPEC, entry.schema, item, context; direction = :output)
            end
        end
        payload = Vector{UInt8}(codeunits(_encode_sequential_json(result, media)))
    elseif startswith(media, "text/")
        result isa AbstractString || throw(ArgumentError(string(
            "operation ",
            operation.id,
            " documents a text response; return an AbstractString or a framework response",
        )))
        _validate_schema(_SPEC, entry.schema, String(result), context; direction = :output)
        payload = Vector{UInt8}(codeunits(String(result)))
    else
        bytes = result isa AbstractVector{UInt8} ? Vector{UInt8}(result) :
                result isa AbstractString ? Vector{UInt8}(codeunits(String(result))) :
                throw(ArgumentError(string(
                    "operation ",
                    operation.id,
                    " documents a binary response; return bytes, a string, or a framework response",
                )))
        _validate_schema(
            _SPEC,
            entry.schema,
            Base64.base64encode(bytes),
            context;
            direction = :output,
        )
        payload = bytes
    end
    headers = Pair{String,String}[
        _safe_header("Content-Type", entry.media_type),
    ]
    return (status, headers, payload)
end

function _error_payload(status, message)
    payload = JSON.json((; error = (; message = String(message))))
    return (
        status,
        Pair{String,String}["Content-Type" => "application/json"],
        Vector{UInt8}(codeunits(payload)),
    )
end

# Returns a (status, headers, body) triple for request decoding failures the
# operation contract anticipates, and rethrows everything else so the hosting
# framework reports a genuine server error.
function _request_error_response(error)
    error isa _RequestFailure && return _error_payload(error.status, error.message)
    error isa DecodeError && return _error_payload(400, error.message)
    error isa SchemaValidationError &&
        return _error_payload(400, sprint(showerror, error))
    error isa UnsupportedMediaType &&
        return _error_payload(415, sprint(showerror, error))
    throw(error)
end

_response_error_payload(error) = _error_payload(500, sprint(showerror, error))
"""

function _server_stub_signature(operation::OperationPlan)
    positional = String["request"]
    path_parameters = _ordered_path_parameters(operation)
    path_names = Set{String}(parameter.name for parameter in path_parameters)
    for parameter in path_parameters
        push!(positional, string(parameter.name, "::", parameter.type))
    end
    if operation.request_body !== nothing && operation.request_body.required
        push!(positional, "body::" * operation.request_body.type)
    end
    keywords = String[]
    for parameter in operation.parameters
        parameter.name in path_names && continue
        parameter.required && push!(keywords, parameter.name * "::" * parameter.type)
    end
    for parameter in operation.parameters
        parameter.name in path_names && continue
        parameter.required ||
            push!(keywords, parameter.name * "::" * parameter.type * " = ABSENT")
    end
    if operation.request_body !== nothing && !operation.request_body.required
        push!(keywords, "body::" * operation.request_body.type * " = ABSENT")
    end
    text = operation.name * "(" * join(positional, ", ")
    isempty(keywords) || (text *= "; " * join(keywords, ", "))
    return text * ") -> " * operation.return_type
end

function _emit_server_operations(io::IO, plan::ServerPlan)
    constants = String[]
    for operation in plan.operations
        push!(constants, _emit_operation_descriptor(io, operation, plan.api))
    end
    println(io, "const _SERVER_OPS = (")
    for (operation, const_name) in zip(plan.operations, constants)
        path_parameters = _ordered_path_parameters(operation)
        path_args = join(
            (repr(Symbol(parameter.name)) for parameter in path_parameters),
            ", ",
        )
        required_body = operation.request_body !== nothing &&
                        operation.request_body.required
        println(
            io,
            "    (operation = ",
            const_name,
            ", invoke = ",
            repr(Symbol(operation.name)),
            ", method = ",
            repr(String(operation.operation.method)),
            ", path = ",
            repr(operation.operation.path),
            ", path_args = (",
            path_args,
            length(path_parameters) == 1 ? "," : "",
            "), required_body = ",
            required_body ? "true" : "false",
            ", signature = ",
            repr(_server_stub_signature(operation)),
            "),",
        )
    end
    println(io, ")\n")
end

"""
    OpenAPI.server_module_source(plan; imports, glue) -> String

Assemble a generated server module for a framework extension: the shared
generated runtime, models, operation descriptors, and the `_SERVER_OPS` route
table, wrapped between the extension's `imports` line and its router `glue`
source. Framework extensions must call this from their `OpenAPI.server_source`
methods so the generated module includes the current contract guard. Most
applications call [`OpenAPI.server`](@ref) instead.
"""
function server_module_source(
    plan::ServerPlan;
    imports::AbstractString,
    glue::AbstractString,
)
    io = IOBuffer()
    println(
        io,
        "# Generated by OpenAPI.jl v",
        PACKAGE_VERSION,
        " from ",
        repr(plan.api.title),
        " version ",
        repr(plan.api.api_version),
        ". Do not edit.",
    )
    println(io, "# Implement these handler functions in a module (or any value")
    println(io, "# supporting `getfield`) and mount them with `register!(router, impl)`:")
    for operation in plan.operations
        println(io, "#     ", _server_stub_signature(operation))
    end
    println(io, "module ", plan.module_name, "\n")
    println(io, imports)
    plan.datetime === :zoned && println(io, "using TimeZones")
    _emit_contract_guard(io)
    print(io, GENERATED_SERVER_IMPORTS, '\n')
    _emit_security(io, plan)
    _emit_schema_data(io, plan)
    print(io, GENERATED_SERVER_SPEC, '\n')
    print(io, GENERATED_RUNTIME_SERVER, '\n')
    indices = _model_indices(plan)
    wrapped_aliases = _cyclic_aliases(plan)
    abstract_targets = _forward_abstracts(plan, wrapped_aliases)
    for target in sort(collect(abstract_targets))
        println(io, "abstract type Abstract", target, " end")
    end
    isempty(abstract_targets) || println(io)
    for (index, model) in enumerate(plan.models)
        _emit_model(io, model, index, indices, abstract_targets, wrapped_aliases)
    end
    _emit_server_operations(io, plan)
    print(io, glue, '\n')
    println(io, "end # module ", plan.module_name)
    return String(take!(io))
end

"""
    OpenAPI.server_source(::Val{framework}, plan::ServerPlan) -> String

Extension seam for framework-specific server-stub emission. Loading HTTP.jl
adds the `Val{:HTTP}` method; server framework packages such as Servo.jl add
their own. [`OpenAPI.server`](@ref) dispatches here.
"""
function server_source end

function _loaded_server_frameworks()
    frameworks = String[]
    for method in methods(server_source)
        signature = method.sig
        signature isa DataType || continue
        length(signature.parameters) >= 2 || continue
        valtype = signature.parameters[2]
        valtype isa DataType && valtype <: Val && isconcretetype(valtype) || continue
        push!(frameworks, string(only(valtype.parameters)))
    end
    return sort(frameworks)
end

"""
    OpenAPI.server(source; framework=:HTTP, name="ApiServer", path=nothing, strict=true, options...) -> String

Generate a deterministic Julia server-stub module after full OpenAPI loading,
reference binding, semantic normalization, and type planning. The generated
module decodes typed request parameters and bodies, dispatches to handler
functions you implement (one per operation, listed in the generated header),
validates and encodes responses, and mounts on the chosen framework's router
through its `register!(router, impl)` function.

`framework` selects the emitter: `:HTTP` (available when HTTP.jl is loaded)
targets `HTTP.Router`; server framework packages can add their own through the
[`OpenAPI.server_source`](@ref) extension seam. Accepts the same `source`
values and keyword options as [`OpenAPI.client`](@ref).
"""
function server(
    source;
    framework::Union{Symbol,AbstractString} = :HTTP,
    name::AbstractString = "ApiServer",
    path::Union{Nothing,AbstractString} = nothing,
    strict::Bool = true,
    kwargs...,
)
    server_plan = source isa ServerPlan ? source :
                  serverplan(source; name, strict, kwargs...)
    key = Symbol(framework)
    if !hasmethod(server_source, Tuple{Val{key},ServerPlan})
        loaded = _loaded_server_frameworks()
        hint = isempty(loaded) ?
               "load a framework package first (`using HTTP` enables framework = :HTTP)" :
               "loaded frameworks: " * join(loaded, ", ")
        throw(ArgumentError(string(
            "no server generator is loaded for framework ",
            repr(key),
            "; ",
            hint,
        )))
    end
    output = server_source(Val(key), server_plan)
    if path !== nothing
        open(path, "w") do io
            write(io, output)
        end
    end
    return output
end
