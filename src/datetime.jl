const DATETIME_FORMATS = [
    Dates.DateFormat("yyyy-mm-dd"),
    Dates.DateFormat("yyyy-mm-dd HH:MM:SS"),
    Dates.DateFormat("yyyy-mm-ddTHH:MM:SS"),
    Dates.DateFormat("yyyy-mm-dd HH:MM:SSzzz"),
    Dates.DateFormat("yyyy-mm-ddTHH:MM:SSzzz"),
    Dates.DateFormat("yyyy-mm-dd HH:MM:SS.sss"),
    Dates.DateFormat("yyyy-mm-ddTHH:MM:SS.sss"),
    Dates.DateFormat("yyyy-mm-dd HH:MM:SS.sssZ"),
    Dates.DateFormat("yyyy-mm-ddTHH:MM:SS.sssZ"),
    Dates.DateFormat("yyyy-mm-dd HH:MM:SS.ssszzz"),
    Dates.DateFormat("yyyy-mm-ddTHH:MM:SS.ssszzz"),
]

str2zoneddatetime(bytes::Vector{UInt8}) = str2zoneddatetime(String(bytes))
function str2zoneddatetime(str::String)
    for fmt in DATETIME_FORMATS
        try
            return ZonedDateTime(str, fmt)
        catch
            # try next format
        end
    end
    return ZonedDateTime(str2datetime(str), localzone())
end
str2zoneddatetime(datetime::DateTime) = ZonedDateTime(datetime, localzone())

str2datetime(bytes::Vector{UInt8}) = str2datetime(String(bytes))
function str2datetime(str::String)
    for fmt in DATETIME_FORMATS
        try
            return DateTime(str, fmt)
        catch
            # try next format
        end
    end
    throw(OpenAPIException("Unsupported DateTime format: $str"))
end
str2datetime(datetime::DateTime) = datetime

str2date(bytes::Vector{UInt8}) = str2date(String(bytes))
function str2date(str::String)
    for fmt in DATETIME_FORMATS
        try
            return Date(str, fmt)
        catch
            # try next format
        end
    end
    throw(OpenAPIException("Unsupported Date format: $str"))
end
str2date(date::Date) = date
