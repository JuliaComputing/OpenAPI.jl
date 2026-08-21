const DATETIME_FORMATS = [
    Dates.DateFormat("yyyy-mm-dd"),
    Dates.DateFormat("yyyy-mm-ddz"),
    Dates.DateFormat("yyyy-mm-dd HH:MM:SS"),
    Dates.DateFormat("yyyy-mm-ddTHH:MM:SS"),
    Dates.DateFormat("yyyy-mm-dd HH:MM:SSz"),
    Dates.DateFormat("yyyy-mm-ddTHH:MM:SSz"),
    Dates.DateFormat("yyyy-mm-dd HH:MM:SS.sss"),
    Dates.DateFormat("yyyy-mm-ddTHH:MM:SS.sss"),
    Dates.DateFormat("yyyy-mm-dd HH:MM:SS.sssz"),
    Dates.DateFormat("yyyy-mm-ddTHH:MM:SS.sssz"),
    Dates.DateFormat("yyyy-mm-dd HH:MM:SS.ss"),
    Dates.DateFormat("yyyy-mm-ddTHH:MM:SS.ss"),
    Dates.DateFormat("yyyy-mm-dd HH:MM:SS.ssz"),
    Dates.DateFormat("yyyy-mm-ddTHH:MM:SS.ssz"),
    Dates.DateFormat("yyyy-mm-dd HH:MM:SS.s"),
    Dates.DateFormat("yyyy-mm-ddTHH:MM:SS.s"),
    Dates.DateFormat("yyyy-mm-dd HH:MM:SS.sz"),
    Dates.DateFormat("yyyy-mm-ddTHH:MM:SS.sz"),
]

# The subset of `DATETIME_FORMATS` that can ever construct a `ZonedDateTime`.
# `ZonedDateTime(str, fmt)` (unlike `DateTime`/`Date`) requires the format to
# carry a `z` specifier *and* the string to supply real offset characters, so
# every format without a `z` is guaranteed to fail for every input and is
# dropped here rather than being tried and discarded on each call.
const ZONED_DATETIME_FORMATS = [
    Dates.DateFormat("yyyy-mm-ddTHH:MM:SSz"),
    Dates.DateFormat("yyyy-mm-ddTHH:MM:SS.sssz"),
    Dates.DateFormat("yyyy-mm-ddz"),
    Dates.DateFormat("yyyy-mm-dd HH:MM:SSz"),
    Dates.DateFormat("yyyy-mm-dd HH:MM:SS.sssz"),
    Dates.DateFormat("yyyy-mm-dd HH:MM:SS.ssz"),
    Dates.DateFormat("yyyy-mm-ddTHH:MM:SS.ssz"),
    Dates.DateFormat("yyyy-mm-dd HH:MM:SS.sz"),
    Dates.DateFormat("yyyy-mm-ddTHH:MM:SS.sz"),
]

const rxdatetime =
    r"([0-9]{4}-[0-9]{2}-[0-9]{2}[T\s][0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,3})?)[0-9]*([+\-Z][:\.0-9]*)?"
function reduce_to_ms_precision(datetimestr::String)
    matches = match(rxdatetime, datetimestr)
    isnothing(matches) && return datetimestr

    c1 = matches.captures[1]
    isnothing(c1) && return datetimestr

    c2 = matches.captures[2]
    return isnothing(c2) ? String(c1) : c1 * c2
end

str2zoneddatetime(bytes::Vector{UInt8}) = str2zoneddatetime(String(bytes))
function str2zoneddatetime(str::String)
    str = reduce_to_ms_precision(str)
    for fmt in ZONED_DATETIME_FORMATS
        zdt = tryparse(ZonedDateTime, str, fmt)
        zdt === nothing || return zdt
    end
    return ZonedDateTime(str2datetime(str), localzone())
end
str2zoneddatetime(datetime::DateTime) = ZonedDateTime(datetime, localzone())

str2datetime(bytes::Vector{UInt8}) = str2datetime(String(bytes))
function str2datetime(str::String)
    str = reduce_to_ms_precision(str)
    for fmt in DATETIME_FORMATS
        dt = tryparse(DateTime, str, fmt)
        dt === nothing || return dt
    end
    throw(OpenAPIException("Unsupported DateTime format: $str"))
end
str2datetime(datetime::DateTime) = datetime

str2date(bytes::Vector{UInt8}) = str2date(String(bytes))
function str2date(str::String)
    for fmt in DATETIME_FORMATS
        d = tryparse(Date, str, fmt)
        d === nothing || return d
    end
    throw(OpenAPIException("Unsupported Date format: $str"))
end
str2date(date::Date) = date
