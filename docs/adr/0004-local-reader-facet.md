# ADR 0004: Read-only Local Client Facet

- Status: Accepted
- Date: 2026-07-27
- Scope: `InstantSwiftDataClient` composition boundaries

## Context

`queryOnce` and `query` intentionally require live freshness when the ordinary
client is closed or waiting for a server acknowledgement. That contract keeps
feature code from silently presenting stale state as fresh. Some composition
roots still need an explicit last-known-local read for startup projection,
previews, diagnostics, or recovery.

Bootstrapping a second local-only runtime against the same SQLite file provides
the right semantics, but duplicates startup hydration, schema merge, actors,
and database connections. Exposing `queryLocal` would instead leak a second
query vocabulary into ordinary features, contrary to ADR 0001.

## Decision

A bootstrapped `InstantSwiftDataClient` can derive a read-only `localReader()`
facet. The facet:

- reuses the existing runtime and in-memory store;
- serves the ordinary `query`, `queryOnce`, and `observe` APIs without a live
  server acknowledgement;
- observes only the local store and does not register a live transport query;
- exposes local ID generation and pending-mutation inspection; and
- rejects mutations and all remote-only capabilities.

The facet is created and injected at a composition or adapter boundary. Normal
features continue to depend on the ordinary client and fetch declarations.

Before:

```swift
var localDependencies = DependencyValues()
try await localDependencies.bootstrapLocalInstantSwiftData(
  appID: appID,
  persistenceURL: sharedPersistenceURL,
  initialAttributes: schema
)
let rows = try await localDependencies.localInstantSwiftData.query(query)
```

After:

```swift
let localReader = try liveClient.localReader()
let rows = try await localReader.query(query)
```

## Consequences

- Local startup reads no longer require a second runtime or SQLite bootstrap.
- Call sites retain one ordinary query vocabulary while making the freshness
  choice explicit through dependency injection.
- A client built only from test closures cannot derive the facet because it has
  no runtime; tests inject a purpose-built local reader directly.
- The facet is deliberately read-only. Writes always use the ordinary client
  so outbox, transport, authentication, and retry ownership remain centralized.
