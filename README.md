# Instant Swift Data

Instant Swift Data is a Swift package for building InstantDB-backed apps with
typed schema, local persistence, optimistic writes, live observation, and
agent-friendly command-line workflows.

This repository is early, but the first local core slice is usable: todos can be
created, listed, completed, and read back across separate CLI invocations through
the same SQLite cache and outbox path used by the core runtime.

## Local Todo CLI Demo

Use `INSTANT_SWIFT_DATA_HOME` to keep the demo cache isolated:

```bash
export INSTANT_SWIFT_DATA_HOME="$(mktemp -d)"

swift run instant-swift-data examples todos add "do the dishes"
swift run instant-swift-data examples todos list
swift run instant-swift-data examples todos list --completed false --offset 0 --limit 10 --order desc
swift run instant-swift-data examples todos list --search dishes
swift run instant-swift-data examples todos complete <todo-id>
swift run instant-swift-data examples todos refresh
```

Agent-readable output is available with `--json` or `--jsonl`:

```bash
swift run instant-swift-data examples todos add "do the dishes" --json
swift run instant-swift-data examples todos list --jsonl
```

Inspect the durable cache and optimistic outbox:

```bash
swift run instant-swift-data app select local-demo --json
swift run instant-swift-data app show --json
swift run instant-swift-data cache inspect --json
swift run instant-swift-data outbox inspect --jsonl
swift run instant-swift-data outbox confirm <mutation-id> --json
swift run instant-swift-data outbox fail <mutation-id> "server rejected" --json
swift run instant-swift-data local-id get todos.viewer --json
```

Persist local CLI auth/session state:

```bash
swift run instant-swift-data auth guest --json
swift run instant-swift-data auth show --json
swift run instant-swift-data auth token <refresh-token> --user-id <user-id> --json
swift run instant-swift-data auth sign-out --json
```

Generate the current todo example schema and permissions:

```bash
swift run instant-swift-data schema generate --example todos --to instant.schema.ts
swift run instant-swift-data perms generate --example todos --to instant.perms.ts
swift run instant-swift-data schema verify --example todos --from instant.schema.ts --json
swift run instant-swift-data perms verify --example todos --from instant.perms.ts --json
```

The current transport is intentionally marked `not-implemented-local-cache-only`
in command output. That means the demo proves durable local cache, typed triples,
query materialization, persisted query results, optimistic outbox persistence,
and non-captive CLI interaction, but it does not yet sync with a real Instant
app.

## Development

### Dependency Bootstrap

App, preview, test, and CLI entry points can install the default client through
Point-Free's Dependencies library:

```swift
import Dependencies
import InstantSwiftData

try await withDependencies {
  try await $0.bootstrapInstantSwiftData(
    appID: "local-demo",
    persistenceURL: cacheURL,
    context: .test,
    initialAttributes: TodoExample.attributes
  )
} operation: {
  @Dependency(\.defaultInstantSwiftData) var db
  _ = try await db.query(TodoExample.query)
}
```

### Typed Queries And Writes

Entities that conform to `InstantEntityModel` can build typed local queries and
optimistic mutations over the same runtime:

```swift
try await db.transact {
  Todo.create(
    id: InstantID(rawValue: "todo-1"),
    Todo.text.set("Ship Instant Swift Data"),
    Todo.isCompleted.set(false),
    Todo.createdAt.set(Date())
  )
}

let openTodos = try await db.query(
  Todo.query
    .where(Todo.isCompleted == false)
    .order(Todo.createdAt)
)

@FetchAll(Todo.query.where(Todo.isCompleted == false))
var todos: [Todo]

try await $todos.load()
```

Build and test:

```bash
swift build
swift test
```

The core package is compiled in Swift 6 mode. Mutable runtime state is owned by
actors, and values crossing actor boundaries are immutable `Sendable` types.
