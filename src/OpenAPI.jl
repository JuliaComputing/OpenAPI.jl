module OpenAPI

using HTTP, JSON, URIs, Dates, TimeZones, Base64

import Base: getindex, keys, length, iterate
import JSON: lower

include("commontypes.jl")
include("datetime.jl")
include("val.jl")
include("json.jl")
include("client.jl")
include("server.jl")

end # module
