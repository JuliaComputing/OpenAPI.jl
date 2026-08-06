"""Runtime support shared by generated clients."""
module Runtime

struct Absent end
const ABSENT = Absent()

Base.show(io::IO, ::Absent) = print(io, "OpenAPI.Runtime.ABSENT")

end
