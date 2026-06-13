# Instant Swift Data

Instant Swift Data is a Swift package for building InstantDB-backed apps with
typed schema, local persistence, optimistic writes, live observation, and
agent-friendly command-line workflows.

This repository is early, but the first local core slice is usable: todos can be
created, listed, completed, updated, deleted, and read back across separate CLI
invocations through the same SQLite cache and outbox path used by the core
runtime.

## Local Todo CLI Demo

Use `INSTANT_SWIFT_DATA_HOME` to keep the demo cache isolated.
The ID-capture steps use `jq` to extract IDs from JSON output.

```bash
export INSTANT_SWIFT_DATA_HOME="$(mktemp -d)"

swift run instant-swift-data examples todos seed --json
swift run instant-swift-data examples todos add "do the dishes"
swift run instant-swift-data examples todos list
swift run instant-swift-data examples todos list --completed false --offset 0 --limit 10 --order desc
swift run instant-swift-data examples todos list --search dishes
swift run instant-swift-data examples todos watch --events 1 --jsonl
TODO_ID="$(swift run instant-swift-data examples todos add "ship the demo" --json | jq -r '.changedID')"
swift run instant-swift-data examples todos complete "$TODO_ID"
swift run instant-swift-data examples todos update "$TODO_ID" "ship the polished demo" --json
DELETE_TODO_ID="$(swift run instant-swift-data examples todos add "delete after smoke" --json | jq -r '.changedID')"
swift run instant-swift-data examples todos delete "$DELETE_TODO_ID" --json
swift run instant-swift-data examples todos refresh
swift run instant-swift-data examples todos reset --json
```

Agent-readable output is available with `--json` or `--jsonl`:

```bash
swift run instant-swift-data examples todos add "do the dishes" --json
TODO_ID="$(swift run instant-swift-data examples todos add "complete through JSONL" --json | jq -r '.changedID')"
swift run instant-swift-data examples todos complete "$TODO_ID" --jsonl
swift run instant-swift-data examples todos seed --jsonl
swift run instant-swift-data examples todos list --jsonl
swift run instant-swift-data examples todos watch --events 1 --jsonl
swift run instant-swift-data examples todos reset --jsonl
```

Inspect the durable cache and optimistic outbox:

```bash
swift run instant-swift-data app select local-demo --json
swift run instant-swift-data app show --json
swift run instant-swift-data cache inspect --json
swift run instant-swift-data cache inspect --json | jq '.queries[] | {queryID, namespace, resultCount}'
swift run instant-swift-data outbox inspect --jsonl
MUTATION_ID="$(swift run instant-swift-data outbox inspect --json | jq -r '.mutations[0].id')"
swift run instant-swift-data outbox confirm "$MUTATION_ID" --json
FAILED_MUTATION_ID="$(swift run instant-swift-data outbox inspect --json | jq -r '.mutations[0].id')"
swift run instant-swift-data outbox fail "$FAILED_MUTATION_ID" "server rejected" --json
swift run instant-swift-data outbox retry "$FAILED_MUTATION_ID" --json
swift run instant-swift-data outbox drain --local-confirm --limit 1 --json
swift run instant-swift-data outbox drain --local-confirm --jsonl
swift run instant-swift-data local-id get todos.viewer --json
swift run instant-swift-data sync inspect --json
swift run instant-swift-data sync mark-processed demo-tx-1 --json
```

Persist local CLI auth/session state:

```bash
swift run instant-swift-data auth guest --json
swift run instant-swift-data auth show --json
swift run instant-swift-data auth token <refresh-token> --user-id <user-id> --json
swift run instant-swift-data auth magic-code send user@example.com --json
swift run instant-swift-data auth magic-code verify user@example.com <local-verification-code> --json
swift run instant-swift-data auth sign-out --json
```

Generate the current todo example schema and permissions:

```bash
swift run instant-swift-data schema generate --example todos --to instant.schema.ts
swift run instant-swift-data perms generate --example todos --to instant.perms.ts
swift run instant-swift-data schema verify --example todos --from instant.schema.ts --json
swift run instant-swift-data perms verify --example todos --from instant.perms.ts --json
```

Run the local Swift validation evidence runner:

```bash
swift run instant-swift-data validation local-todos --jsonl
swift run instant-swift-data-validation-runner --local-todos
validation/run-e2e.sh
```

Run local core benchmarks:

```bash
swift run instant-swift-data benchmark --suite local-todos --iterations 3 --json
swift run instant-swift-data benchmark --suite local-todos --iterations 3 --jsonl
swift run instant-swift-data-benchmarks --suite local-todos --iterations 3 --json
swift run instant-swift-data-benchmarks --suite local-todos --iterations 3 --jsonl
```

The current transport is intentionally marked `not-implemented-local-cache-only`
in command output. That means the demo proves durable local cache, typed triples,
query materialization, plan-aware persisted query results, optimistic outbox
persistence, and non-captive CLI interaction, but it does not yet sync with a
real Instant app.

## Development

### Dependency Bootstrap

App, preview, test, and CLI entry points can install the default client through
Point-Free's Dependencies library:

```swift
import Dependencies
import InstantSwiftData

try await withDependencies {
  $0.instantMagicCodeExchange = .local
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

`instantMagicCodeExchange` defaults to `.local`, and app/test entry points can
override it before `bootstrapInstantSwiftData` to install live or fixture-backed
auth behavior. Local/demo clients should be reusable static instances on the
client type, for example `extension InstantMagicCodeExchange { public static let
local = Self(...) }`, while dependency keys remain computed `static var`
`liveValue`, `testValue`, and `previewValue` properties.

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

let subscription = try await $todos.subscribe()
defer { subscription.cancel() }

for try await todos in subscription {
  // Update model state from the latest local materialization.
}
```

Subscriptions are bounded newest-value streams, so slow consumers receive the
latest local materialization rather than every intermediate invalidation.

Build and test:

```bash
swift build
swift test
```

Macro snapshot tests use Point-Free's MacroTesting library and are available on
toolchains that provide XCTest:

```bash
INSTANT_SWIFT_DATA_ENABLE_MACRO_TESTING=1 swift test --filter InstantEntityMacroSnapshotTests
```

The core package is compiled in Swift 6 mode. Mutable runtime state is owned by
actors, and values crossing actor boundaries are immutable `Sendable` types.
