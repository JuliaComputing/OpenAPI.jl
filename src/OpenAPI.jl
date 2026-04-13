module OpenAPI

using HTTP, JSON, URIs, Dates, TimeZones, Base64
using Downloads
using p7zip_jll

import Base: getindex, keys, length, iterate, hasproperty
import JSON: lower


const _JSON_PARSE_ISROOT_SUPPORTED = try; JSON.parse("1 "; isroot=false); true; catch; false; end

if _JSON_PARSE_ISROOT_SUPPORTED
    _json_parse(io_or_str) = JSON.parse(io_or_str; isroot=false)
else
    _json_parse(io_or_str) = JSON.parse(io_or_str)
end

include("commontypes.jl")
include("datetime.jl")
include("val.jl")
include("json.jl")
include("client.jl")
include("server.jl")
include("tools.jl")

end # module
