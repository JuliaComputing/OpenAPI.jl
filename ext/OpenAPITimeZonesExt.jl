# TimeZones extension: zoned date-time codecs for generated OpenAPI modules
# emitted with `datetime = :zoned` (their `using TimeZones` loads this).
module OpenAPITimeZonesExt

using TimeZones, Dates
import OpenAPI.Runtime: _decode, _encode, DecodeError

function _decode(::Type{TimeZones.ZonedDateTime}, value::AbstractString)
    matched = match(
        r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:\d{2})?$",
        value,
    )
    matched === nothing && throw(DecodeError("invalid RFC 3339 date-time $(repr(value))"))
    try
        clock = Dates.DateTime(matched.captures[1])
        fraction = matched.captures[2]
        if fraction !== nothing
            clock += Dates.Millisecond(
                parse(Int, rpad(first(fraction, min(3, length(fraction))), 3, '0')),
            )
        end
        zone = matched.captures[3]
        timezone = if zone === nothing || zone == "Z"
            TimeZones.tz"UTC"
        else
            sign = startswith(zone, '+') ? 1 : -1
            hours = parse(Int, zone[2:3])
            minutes = parse(Int, zone[5:6])
            TimeZones.FixedTimeZone(zone, sign * (3600 * hours + 60 * minutes))
        end
        return TimeZones.ZonedDateTime(clock, timezone)
    catch error
        error isa DecodeError && rethrow()
        throw(DecodeError("invalid RFC 3339 date-time: $(sprint(showerror, error))"))
    end
end
_encode(value::TimeZones.ZonedDateTime) =
    Dates.format(value, TimeZones.ISOZonedDateTimeFormat)

end # module OpenAPITimeZonesExt
