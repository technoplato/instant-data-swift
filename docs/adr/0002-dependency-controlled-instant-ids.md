# ADR 0002: Dependency-Controlled Instant IDs

- Status: Accepted
- Date: 2026-07-27
- Scope: Typed entity identity creation in `InstantSwiftData`

## Context

New typed entities need client-generated IDs before they enter an optimistic
transaction. The existing API required every feature to construct and
canonicalize a UUID manually:

```swift
let id = InstantID<Todo>(
  rawValue: UUID().uuidString.lowercased()
)
```

That spelling bypasses Point-Free's dependency system, makes tests responsible
for threading literal IDs through feature code, and repeats the library's
lowercase UUID convention at each call site. The explicit `rawValue`
initializer remains necessary for server IDs, stable fixtures, imports, and
domain-defined identifiers.

## Decision

`InstantSwiftData` adds a zero-argument typed initializer:

```swift
let id = InstantID<Todo>()
```

It reads `DependencyValues.uuid`, converts the UUID to the canonical lowercase
string representation, and delegates to `init(rawValue:)`. Tests and previews
control generated entity identity through ordinary dependency overrides:

```swift
withDependencies {
  $0.uuid = .incrementing
} operation: {
  let first = InstantID<Todo>()
  let second = InstantID<Todo>()
}
```

The initializer lives in the higher-level `InstantSwiftData` module, which
already depends on `Dependencies`. `InstantSwiftDataCore` remains independent
of that package, and callers importing only the core module continue to use the
explicit raw-value initializer.

## Consequences

- New entity creation is concise and deterministic under test.
- Features no longer call `UUID()` directly merely to satisfy Instant identity
  plumbing.
- Existing raw, server-provided, local-name, and deterministic IDs retain their
  current APIs and semantics.
- Dependency overrides apply at the call site; the initializer does not use the
  runtime's separate transaction/outbox ID generator.
