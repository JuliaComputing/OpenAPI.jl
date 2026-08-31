# Generated models

Generated structs are a typed view over the document's JSON Schemas. Runtime
schema validation remains authoritative. This design protects correctness when
a Julia field type cannot express every schema rule.

Implemented model behavior includes:

- objects, arrays, tuples, dictionaries, primitives, enums, and nullable types;
- required, optional, and explicit-null values;
- `allOf`, `oneOf`, `anyOf`, and discriminators;
- recursive models and recursive aliases;
- `additionalProperties`, `patternProperties`, `propertyNames`, and closed
  objects;
- JSON Schema assertions such as `const`, `not`, conditions, dependent rules,
  bounds, formats, and unevaluated constraints through runtime validation;
- `readOnly` and `writeOnly` request and response projections;
- Julia `Date`, `Time`, `DateTime`, `UUID`, and base64 byte values;
- `format: date-time` maps to `Dates.DateTime` by default, decoding RFC 3339
  offsets by normalizing to UTC; generate with `datetime = :zoned` to map to
  `TimeZones.ZonedDateTime` instead, preserving offsets end to end (the
  generated module then depends on TimeZones.jl);
- deterministic names with protection against Julia keywords, Base/Core names,
  and generated runtime names.

An unusual schema can plan to `Any` when no useful Julia type exists. It is
still validated at request and response boundaries. Custom JSON Schema dialects
and custom vocabularies can therefore retain correct validation while using a
less precise Julia type.

## Disabling boundary validation

Set `validate_requests=false` or `validate_responses=false` on a generated
`Client` only when the application accepts that loss of boundary validation.
For example, a response schema with `additionalProperties: false` rejects a new
server field. This is contract-correct but can make a client less tolerant of
an API that changes outside its published contract. With response validation
disabled, that policy also reaches nested generated models. Unknown response
properties are ignored, and an explicit null on an optional response property
decodes to `nothing` even when the document marks that property non-nullable.
Missing optional properties still decode to `ABSENT`. Values that cannot fit
the generated Julia type can still raise `DecodeError`.
