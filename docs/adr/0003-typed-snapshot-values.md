# ADR 0003: Typed Entity Snapshot Values

- Status: Accepted
- Date: 2026-07-27
- Scope: Cardinality-one value decoding in `InstantSwiftData`

## Context

Application models that implement `InstantEntityModel.init(snapshot:)` have
historically repeated string keys and wire-format switches even though their
entity already declares typed attribute paths:

```swift
guard case let .string(title) = snapshot.values["title"]?.first else {
  throw ...
}
```

That boilerplate can drift from the schema, produces inconsistent decode
errors, and makes a field rename touch both the attribute declaration and an
unrelated string literal. `InstantValueDecodable` already centralizes the
correct handling for strings, numbers, dates, JSON, typed IDs, wire enums, and
optionals.

## Decision

`InstantEntitySnapshot` gains a typed cardinality-one accessor:

```swift
let title = try snapshot.value(Todo.title)
let dueAt = try snapshot.value(Todo.dueAt)
```

The attribute path supplies the entity and value types. The accessor validates
that the snapshot namespace matches the path's entity namespace, then delegates
to `InstantValueDecodable` with the snapshot ID and attribute name so errors
retain precise diagnostics. Callers may provide an operation label when a
feature needs more specific error provenance.

The helper intentionally decodes the first value for a cardinality-one typed
attribute, matching `InstantAttributePath.set`. It does not invent a second
API for relationship includes or cardinality-many query results.

## Consequences

- Model decoding reuses schema-owned typed paths instead of repeating raw field
  strings and wire-format switches.
- Optional and custom wire values preserve their existing centralized missing
  and malformed-value behavior.
- A typed path from the wrong entity fails immediately with a validation error
  instead of silently reading a coincidentally named field.
- Existing direct access to `snapshot.values` remains available for advanced
  cardinality-many, include, migration, and diagnostic work.
