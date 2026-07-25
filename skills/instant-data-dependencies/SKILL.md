---
name: instant-data-dependencies
description: Bootstrap and inject Instant Swift Data clients and effect seams. Use when configuring bootstrapInstantSwiftData, DependencyValues, @Dependency, live, local-only, preview, test, or CLI clients, auth/transport/storage/media clients, clocks or IDs, and when removing global runtime access or feature-level synchronization coordinators.
---

# Instant Data Dependencies

Use `instant-data` and the Point-Free `pfw` and `pfw-dependencies` skills first.

## Keep one bootstrap boundary

Bootstrap app id, schema, SQLite persistence, auth/session state, transport,
outbox, and observation once at the composition root. Resolve effect clients
before constructing the runtime. Do not create parallel feature bootstrap
paths or hidden mutable singletons.

Use `@Dependency` wherever live, preview, test, CLI, or local-only behavior can
vary. Define Sendable value clients, conform keys to `TestDependencyKey`, add
`DependencyKey` live behavior where appropriate, and use computed `testValue`,
`previewValue`, and `liveValue` properties.

## Select local-only behavior by injection

Inject a local-only `InstantSwiftDataClient` at bootstrap or with dependency
overrides. Keep its public behavior isomorphic to the live client:

- ordinary fetch wrappers and subscriptions;
- ordinary one-shot queries, served from the local runtime even though a live
  client's `queryOnce` remains freshness-sensitive and fails offline;
- ordinary typed mutations and drafts;
- ordinary auth/sharing APIs when the local fixture supports them;
- deterministic local delivery/status for CLI and tests.

Do not add a public `queryLocal`, feature-specific cache client, or direct
runtime materializer. Local-only is an environment choice, not a second query
language.

`bootstrapLocalInstantSwiftData` populates the explicit
`localInstantSwiftData` dependency. Fetch wrappers read
`defaultInstantSwiftData`, so a wholly local-only feature environment must map
the local client to the default dependency at the composition boundary:

```swift
try await withDependencies {
  try await $0.bootstrapLocalInstantSwiftData(
    appID: "local-preview",
    context: .test,
    initialAttributes: Todo.instantAttributes
  )
  let localOnlyClient = $0.localInstantSwiftData
  $0.defaultInstantSwiftData = localOnlyClient
} operation: {
  // @Fetch*, subscriptions, and typed transactions use the local-only client.
}
```

Code that intentionally needs both clients may access
`@Dependency(\.localInstantSwiftData)` explicitly. Do not imply that local
bootstrap silently changes the default client.

## Inject effects, not synchronization policy

Inject capabilities such as auth exchanges, transport, storage, media transfer,
clock, UUID, and file access. Keep persistent outbox/reconnect/delivery policy
inside Instant Swift Data.

Do not inject an outbox drainer or synchronization coordinator into a normal
feature. Expose flush/status only to CLI, diagnostics, tests, or an explicit
user-visible operation.

Keep media transfer independent from entity delivery. Give media its own
Sendable dependency/client and bounded-cache policy so a rejected media item
cannot stall entity mutations or unrelated media.

## Override deterministically

Override dependencies before bootstrap in previews/tests. Use isolated
temporary or in-memory persistence, fixed clocks and IDs, finite streams, and
explicit cancellation. Do not reach into a live singleton after bootstrap to
patch behavior.

## Verify

Test live, preview, test, CLI, and local-only construction through public
clients. Prove a feature needs no conditional code when switching between live
and local-only clients.
