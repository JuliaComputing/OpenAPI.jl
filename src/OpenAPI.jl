module OpenAPI

using HTTP, JSON, URIs, Dates, TimeZones, Base64

import Base: getindex, keys, length, iterate, hasproperty
import JSON: lower

include("commontypes.jl")
include("datetime.jl")
include("val.jl")
include("json.jl")
include("client.jl")
include("server.jl")
include("tools.jl")

end # module
