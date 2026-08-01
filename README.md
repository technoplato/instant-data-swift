# Instant Swift Data

Instant Swift Data is a fast, modern persistence and real-time synchronization library for Swift, powered by [InstantDB](https://www.instantdb.com) and inspired by Apple's SwiftData and Point-Free's [SQLiteData](https://github.com/pointfreeco/sqlite-data).

> [!IMPORTANT]
> **Pre-release**: Instant Swift Data is currently under active development. The core runtime, persistence layer, WebSocket synchronization protocol, presence, auth, storage, and property wrappers are fully operational and tested across multi-platform targets, but public APIs may evolve before 1.0.

* [What is it?](#What-is-it)
* [Why Instant Swift Data?](#Why-Instant-Swift-Data)
* [Comparison](#Comparison)
* [Quick Start](#Quick-Start)
* [Features at a Glance](#Features-at-a-Glance)
* [Core Capabilities](#Core-Capabilities)
  * [Defining Schema & Models](#Defining-Schema--Models)
  * [Fetching & Live Observation](#Fetching--Live-Observation)
  * [Mutations & Optimistic Updates](#Mutations--Optimistic-Updates)
  * [Real-Time Presence, Rooms & Topics](#Real-Time-Presence-Rooms--Topics)
  * [Authentication & User Management](#Authentication--User-Management)
  * [Storage & Media Assets](#Storage--Media-Assets)
  * [Offline Outbox & Reconnection](#Offline-Outbox--Reconnection)
  * [CLI & Agent Workflows](#CLI--Agent-Workflows)
* [Testing & Previews](#Testing--Previews)
* [Demos & Sample Apps](#Demos--Sample-Apps)
* [Documentation & ADRs](#Documentation--ADRs)
* [Requirements](#Requirements)
* [License & Credits](#License--Credits)

---

## What is it?

**Instant Swift Data** brings the developer experience of SwiftData and Point-Free's SQLiteData to [InstantDB](https://www.instantdb.com)—an **open-source**, platform-agnostic real-time database and sync engine. 

InstantDB provides first-class support for **TypeScript** (of all shapes and sizes), **React**, **React Native**, **Vue**, and **Svelte** on the web and mobile. **Instant Swift Data** extends this ecosystem to native Apple platforms, pairing a local SQLite cache with InstantDB's real-time WebSocket protocol.

With Instant Swift Data, you define your schema using declarative Swift value types (`struct`), query and observe data in SwiftUI using reactive property wrappers (`@FetchAll`, `@FetchOne`, `@Fetch`), and execute optimistic mutations locally that instantly sync across all connected clients (iOS, macOS, watchOS, tvOS, Web, and backend services).

---

## Why Instant Swift Data?

* **Open Source & Platform Agnostic**: Powered by InstantDB's open-source sync engine, enabling seamless real-time data sharing between native Swift apps and web/mobile clients built with TypeScript, React, React Native, Vue, or Svelte.
* **SwiftData & SQLiteData Ergonomics**: Define models using familiar attributes and macros (`@InstantEntity`), and bind live queries directly to SwiftUI views with `@FetchAll` and `@FetchOne`.
* **Real-Time Graph Synchronization**: Data syncs automatically across devices via InstantDB. Changes made on one device (or web app) instantly push to all other subscribed clients.
* **Pure Value-Type Semantics**: Models are immutable Swift `struct`s, eliminating data races, reference cycle leaks, and threading issues common with `NSManagedObject` and reference-based ORMs.
* **Offline-First & Outbox Resiliency**: Perform optimistic writes immediately offline. Mutations persist in a local outbox and automatically flush upon reconnection with per-item rejection isolation.
* **Built-in Multi-User Real-Time Features**: Track user avatars, live cursors, typing indicators, and ephemeral events out-of-the-box using `@Presence`, `@Room`, and `@Topic`.
* **Integrated Auth & File Storage**: Manage sign-ins via Email Magic Code, Guest Auth, or OAuth (`@InstantAuth`), and upload/download media assets (`@InstantStorageStatus`).
* **Testable & Decoupled Architecture**: Built on Point-Free's [`swift-dependencies`](https://github.com/pointfreeco/swift-dependencies). Swap in a local-only or mock client (`InstantSwiftDataClient.localOnly()`) for instant SwiftUI previews and unit testing without network dependencies.
* **Agent & CLI Automation**: First-class command-line tools support `--json` and `--jsonl` output formats for noninteractive scripting and AI agent integration.

---

## Comparison

Instant Swift Data adapts the ergonomics of Apple's SwiftData and Point-Free's SQLiteData while providing instant real-time cloud synchronization via InstantDB:

<table>
<tr>
<th>Instant Swift Data</th>
<th>SQLiteData</th>
<th>SwiftData</th>
</tr>
<tr valign="top">
<td width="33%">

```swift
@FetchAll(Todo.query.order(.createdAt, .descending))
var todos: [Todo]

@InstantEntity
struct Todo: InstantEntityModel {
  var id: InstantID<Todo>
  var text: String
  var isCompleted: Bool
  var createdAt: Date
}
```

</td>
<td width="33%">

```swift
@FetchAll
var todos: [Todo]

@Table
struct Todo {
  let id: UUID
  var text: String
  var isCompleted: Bool
  var createdAt: Date
}
```

</td>
<td width="33%">

```swift
@Query(sort: \Todo.createdAt, order: .reverse)
var todos: [Todo]

@Model
class Todo {
  var text: String
  var isCompleted: Bool
  var createdAt: Date
  
  init(text: String, isCompleted: Bool = false) {
    self.text = text
    self.isCompleted = isCompleted
    self.createdAt = Date()
  }
}
```

</td>
</tr>
</table>

---

## Quick Start

### 1. Configure the Client

Configure the default `InstantSwiftDataClient` at app launch using Point-Free's `prepareDependencies`:

```swift
import SwiftUI
import InstantSwiftData
import Dependencies

@main
struct MyApp: App {
  init() {
    prepareDependencies {
      $0.defaultInstantSwiftData = InstantSwiftDataClient(
        appID: "YOUR_INSTANT_APP_ID"
      )
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
```

### 2. Define your Model

Declare your entities as Swift value types using the `@InstantEntity` macro:

```swift
import Foundation
import InstantSwiftData

@InstantEntity
public struct Todo: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Todo>
  public var text: String
  public var isCompleted: Bool
  public var createdAt: Date

  public init(
    id: InstantID<Todo> = InstantID(),
    text: String,
    isCompleted: Bool = false,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.text = text
    self.isCompleted = isCompleted
    self.createdAt = createdAt
  }
}
```

### 3. Observe & Mutate in SwiftUI

Use `@FetchAll` to observe queries reactively, and `@Dependency(\.defaultInstantSwiftData)` to perform mutations:

```swift
struct ContentView: View {
  @FetchAll(Todo.query.order(.createdAt, .descending)) 
  private var todos: [Todo]
  
  @Dependency(\.defaultInstantSwiftData) private var db
  @State private var newTodoText = ""

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack {
            TextField("What needs doing?", text: $newTodoText)
            Button("Add") { addTodo() }
              .disabled(newTodoText.isEmpty)
          }
        }
        
        Section {
          ForEach(todos) { todo in
            Button(action: { toggleTodo(todo) }) {
              Label(
                todo.text,
                systemImage: todo.isCompleted ? "checkmark.circle.fill" : "circle"
              )
            }
          }
        }
      }
      .navigationTitle("Todos")
    }
  }

  private func addTodo() {
    let todo = Todo(text: newTodoText)
    db.send(
      CreateTodo(id: todo.id, text: todo.text, createdAt: todo.createdAt),
      onOptimisticCommit: { _ in newTodoText = "" }
    )
  }

  private func toggleTodo(_ todo: Todo) {
    db.send(
      SetTodoCompletion(id: todo.id, isCompleted: !todo.isCompleted)
    )
  }
}
```

---

## Features at a Glance

| Feature Area | Description | Primary APIs / Annotations |
| :--- | :--- | :--- |
| **Data Modeling** | Type-safe entity definitions with namespace mapping & schema validations | `@InstantEntity`, `InstantID`, `InstantAttributePath` |
| **Live Queries** | Reactive SwiftUI observation with optimistic local cache fallback | `@FetchAll`, `@FetchOne`, `@Fetch` |
| **Mutations** | Transactional & optimistic mutations with server acknowledgment hooks | `db.send(...)`, `db.transact(...)`, `onOptimisticCommit` |
| **Real-Time Rooms & Presence** | Multi-user presence, active viewer tracking, and live cursors | `@Room`, `@Presence`, `InstantRoom`, `InstantPresence` |
| **Ephemeral Broadcasts** | Peer-to-peer real-time event streams without database persistence | `@Topic`, `InstantTopic` |
| **Authentication** | Email magic code, guest auth, OAuth sessions, and token persistence | `@InstantAuth`, `InstantAuth`, `InstantAuthState` |
| **File Storage** | Upload and manage media assets connected to entity records | `@InstantStorageStatus`, `InstantStorageClient` |
| **Offline Resilience** | SQLite-backed outbox with LIFO queue and per-item rejection isolation | `InstantSyncStatus`, `@InstantSyncStatus` |
| **CLI & Testing** | Agent-ready command line interface and isolated local test clients | `--json`, `--jsonl`, `InstantSwiftDataClient.localOnly()` |

---

## Core Capabilities

### Defining Schema & Models

Entities are defined as Swift `struct`s conforming to `InstantEntityModel`. The `@InstantEntity` macro generates static attributes, typed attribute paths, and draft mutation support:

```swift
@InstantEntity("reminders")
public struct Reminder: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Reminder>
  public var title: String
  public var isCompleted: Bool
  public var dueDate: Date?
  public var listID: InstantID<ReminderList>
}
```

Relations between entities can be declared using static `InstantReverseRelation` or `InstantAttributePath` references to build type-safe relational graph queries.

### Fetching & Live Observation

Instant Swift Data provides property wrappers for observing queries in SwiftUI:

* **`@FetchAll`**: Fetches and reactively updates an array of entities matching a query.
* **`@FetchOne`**: Fetches and reactively updates a single entity matching a query or ID.
* **`@Fetch`**: Fetches arbitrary projected data or aggregate values.

```swift
// Static query observation
@FetchAll(Todo.query.where(.isCompleted, .equals(false)))
private var pendingTodos: [Todo]

// Dynamic query loading
@FetchAll(nil) private var dynamicSearchResults: [Todo]

// Load dynamic queries programmatically
$dynamicSearchResults.load(
  Todo.query.search(.text, queryText),
  using: db
)
```

### Mutations & Optimistic Updates

Mutations are executed optimistically on the local SQLite cache and queued for server delivery over WebSocket:

```swift
db.send(
  CreateTodo(id: todoID, text: "Buy milk", createdAt: Date()),
  onOptimisticCommit: { _ in
    // Local SQLite cache updated immediately
  },
  onServerAccepted: { _ in
    // Confirmed by InstantDB backend
  },
  onFailure: { error in
    // Handle error or rollback
  }
)
```

### Real-Time Presence, Rooms & Topics

Track multi-user state in real-time within your app:

```swift
struct SharedBoardView: View {
  @Room private var room: InstantRoom<BoardRoom>
  @Presence private var activePeers: [UserPresence]
  @Topic private var cursorTopic: InstantTopic<CursorPosition>

  var body: some View {
    CanvasView()
      .instantRoom($room, InstantRoom<BoardRoom>(type: "board", id: boardID))
      .presence($activePeers, in: room, publishing: UserPresence(name: userName))
      .onReceive(cursorTopic.events) { position in
        // Update peer cursor position on screen
      }
  }
}
```

### Authentication & User Management

Instant Swift Data includes full auth workflow support, including Guest sign-in and Email Magic Code authentication:

```swift
struct AuthView: View {
  @InstantAuth private var authState: InstantAuthState
  @Dependency(\.defaultInstantSwiftData) private var db

  var body: some View {
    VStack {
      if authState.isAuthenticated {
        Text("Logged in as \(authState.user?.email ?? "Guest")")
        Button("Sign Out") { db.auth.signOut() }
      } else {
        Button("Sign in as Guest") { db.auth.signInAsGuest() }
      }
    }
  }
}
```

### Storage & Media Assets

Upload and download files attached to entity records with status monitoring:

```swift
struct MediaUploadView: View {
  @InstantStorageStatus private var storageStatus: InstantStorageStatus
  @Dependency(\.defaultInstantSwiftData) private var db

  func uploadHeaderImage(_ data: Data) {
    db.storage.upload(
      path: "headers/profile.jpg",
      data: data
    )
  }
}
```

### Offline Outbox & Reconnection

When the user goes offline, mutations are stored in a persistent local SQLite outbox. Upon reconnecting, the outbox automatically flushes to InstantDB. Individual mutations feature rejection isolation so a single failed mutation does not block or corrupt the remaining outbox stream.

Monitor sync status directly in your UI:

```swift
struct SyncBadgeView: View {
  @InstantSyncStatus private var syncStatus: InstantSyncStatus

  var body: some View {
    HStack {
      Circle()
        .fill(syncStatus.isConnected ? Color.green : Color.orange)
        .frame(width: 8, height: 8)
      Text(syncStatus.isConnected ? "Synced" : "Offline (\(syncStatus.pendingOutboxCount) pending)")
    }
  }
}
```

### CLI & Agent Workflows

The package includes CLI tools that expose identical data capabilities for terminal usage, automation scripts, and AI coding agents:

```bash
# Run noninteractive recipe commands with JSON output
swift run instant-swift-data recipes todos add "Do the dishes" --json

# Query entities with filters and pagination
swift run instant-swift-data query todos --completed false --first 10 --json

# Run live stream observation outputting NDJSON / JSONL
swift run instant-swift-data examples todos watch --jsonl
```

---

## Testing & Previews

Instant Swift Data makes testing straightforward by utilizing Point-Free's `swift-dependencies` library.

### Local In-Memory Client for Previews & Tests

Inject a local-only `InstantSwiftDataClient` that operates entirely in memory without making network calls:

```swift
#if DEBUG
struct TodoView_Previews: PreviewProvider {
  static var previews: some View {
    withDependencies {
      $0.defaultInstantSwiftData = .localOnly()
    } operation: {
      ContentView()
    }
  }
}
#endif
```

### Unit Testing

Override dependencies in Swift XCTest or Swift Testing suites:

```swift
@Test func testTodoCreation() async throws {
  let client = InstantSwiftDataClient.localOnly()
  
  try await withDependencies {
    $0.defaultInstantSwiftData = client
  } operation: {
    let todo = Todo(text: "Test item")
    client.send(CreateTodo(id: todo.id, text: todo.text, createdAt: todo.createdAt))
    
    let fetched = try client.fetch(Todo.query.where(.id, .equals(todo.id)))
    #expect(fetched.first?.text == "Test item")
  }
}
```

---

## Demos & Sample Apps

The repository includes a suite of runnable apps and multi-platform targets exercising Instant Swift Data:

* **Recipes Catalog (`swift run recipes-v3`)**: Native macOS application presenting 8 complete recipes (Todos, Cursors, Custom Cursors, Reactions, Typing Indicator, Avatar Stack, Merge Tile Game, Auth).
* **Reminders App (`swift run reminders-v3`)**: Complete multi-platform app (macOS, iOS, tvOS, watchOS) with list sharing, guest sign-in, magic code auth, tag filtering, and offline outbox sync.
* **CLI Executables**: Includes `reminders-v3-cli`, `todos-v3`, `syncups-v3`, `mobilechat-v3`, `stroopwafel-v3`, `appbuilder-v3`, and `streams-v3`.

---

## Documentation & ADRs

Detailed architecture docs and design targets are located in `docs/`:

* **[Application & Sync Boundary ADR](docs/adr/0001-application-sync-boundary.md)**: Defines canonical boundary responsibilities between application code and the Instant Swift Data library.
* **[Runtime Diagnostics](docs/diagnostics.md)**: Structured logging details and diagnostic paths.
* **[Reminders Live Parity Audit](docs/reminders-v3-live-parity-audit.md)**: Parity evaluation across macOS, iOS Simulator, tvOS Simulator, and watchOS Simulator clients.

---

## Requirements

* **Swift**: 5.9+
* **Platforms**: macOS 13.0+, iOS 16.0+, tvOS 16.0+, watchOS 9.0+
* **Xcode**: 15.0+

---

## License & Credits

Instant Swift Data is released under the MIT License.

### Credits & Acknowledgments
* **[Point-Free](https://www.pointfree.co)** for creating [SQLiteData](https://github.com/pointfreeco/sqlite-data) and [`swift-dependencies`](https://github.com/pointfreeco/swift-dependencies), whose design inspired this package.
* **[InstantDB](https://www.instantdb.com)** for providing the real-time graph database and protocol backend.
* **Apple** for the original SwiftData API concepts.
