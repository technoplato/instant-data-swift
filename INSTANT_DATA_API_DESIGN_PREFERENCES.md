# Instant Data API Design Preferences

This document records the public API preferences for Instant Swift Data as they
are discovered through the design interview. It is intentionally separate from
implementation plans: this file answers "what should the library feel like to
use?"

## Sources Checked

- Current repo docs:
  - `docs/instant-swift-data-goals.md`
  - `docs/instantdb-swift-data-plan.md`
  - `README.md`
- Referenced Codex thread:
  - `019ebd5b-8aa6-7533-b534-a8a77ee0b307`
- Local source:
  - `Sources/InstantSwiftData`
  - `Sources/InstantSwiftDataCore`
  - `Sources/InstantSwiftDataMacros`
- Local upstream references:
  - `upstream/instant`
  - `upstream/sqlite-data`
  - `upstream/sharing-instant`
- Skill guidance:
  - `instantdb`
  - `pfw-sqlite-data`
  - `pfw-structured-queries`
- Official Instant docs checked on 2026-06-30:
  - modeling data
  - reading data
  - writing data
  - auth
  - presence and topics
  - storage
  - streams

## Current Recommendation

Instant Swift Data should be InstantDB-native in its data model and semantics,
but Point-Free-like in Swift ergonomics.

That means:

- Instant's graph, links, permissions, rooms, presence, topics, streams,
  storage, realtime, optimistic writes, and offline outbox should be first-class
  concepts.
- SQLiteData's influence should show up in the Swift surface:
  property wrappers, `@Observable` compatibility, dependency bootstrap,
  generated drafts, type-safe query builders, and terse model declarations.
- The API should not expose SQL concepts such as joins, row projections, or raw
  string paths unless there is no type-safe Instant-shaped equivalent.
- The public API should prefer compile-time Swift types and generated symbols.
  Runtime validation still exists for server data, permissions, and transport
  failures, but app code should not be writing magic strings for namespaces,
  attributes, relation names, room topics, permission paths, or storage links.

Status: recommended, not yet approved by the user.

## Observed Constraints

- Package naming centers on `InstantSwiftData`.
- Swift schema is intended to be the source of truth for TypeScript schema,
  permissions, generated Swift helpers, validation fixtures, rooms, topics, and
  presence types.
- `@InstantEntity` already generates `instantNamespace`, attribute paths,
  reverse relation tokens, wire validation, and `Draft`.
- `InstantID<Entity>` already gives typed entity references.
- `InstantEntityQuery` already supports typed `where`, `select`, `include`,
  `order`, top-level pagination, and `serverCreatedAt` ordering.
- `@FetchAll`, `@FetchOne`, `@Fetch`, `@InfiniteQuery`, auth, connection,
  rooms, storage, streams, and shares have platform adapter validation.
- Local persistence is SQLite-backed and includes cached queries, outbox,
  auth/session state, connection state, schema attributes, triples, and stream
  or sharing metadata.
- Instant fields used for filtering or ordering need schema support such as
  typed/indexed attributes. The Swift API should make this discoverable.
- Rooms, presence, and topics are ephemeral. Durable realtime data should use
  transactions and queries.
- Storage should model `$files` and file links rather than storing URLs as
  ordinary string fields.

## Syntax Candidate: App Bootstrap

Recommended shape:

```swift
import Dependencies
import InstantSwiftData

@main
struct FieldOpsApp: App {
  init() {
    prepareDependencies {
      $0.defaultInstantSwiftData = try .live(
        appID: Secrets.instantAppID,
        schema: FieldOpsSchema.self,
        permissions: FieldOpsPermissions.self,
        persistence: .sqlite(.applicationSupport("FieldOps.sqlite")),
        sync: .automatic
      )
    }
  }
}
```

Why this shape:

- Mirrors SQLiteData's `prepareDependencies` bootstrap.
- Makes schema and permissions visible at initialization.
- Makes local persistence explicit but unsurprising.
- Leaves room for `.ephemeral`, `.preview`, `.test`, `.admin`, and
  `.offlineOnly` clients.

Open preference:

- Whether `.live(...)` should be the main initializer, or whether the public API
  should spell this as `InstantSwiftDataClient(...)`/`InstantDatabase(...)`.

## Syntax Candidate: Schema And Entities

Recommended shape:

```swift
@InstantEntity
struct Inspection: Codable, Sendable, Identifiable {
  let id: InstantID<Self>

  @InstantIndexed
  var scheduledAt: Date

  @InstantIndexed
  var status: Status

  var siteName: String
  var notes: String?

  @InstantRelation(reverse: "inspections")
  var assignedTechnician: InstantID<Technician>

  enum Status: String, Codable, Sendable, InstantStringEnum {
    case scheduled
    case inProgress
    case needsParts
    case complete
  }
}

@InstantEntity
struct Technician: Codable, Sendable, Identifiable {
  let id: InstantID<Self>

  @InstantUnique
  var email: String

  var displayName: String
  var region: String
}
```

What this should generate:

```swift
Inspection.instantNamespace
Inspection.scheduledAt
Inspection.status
Inspection.assignedTechnician
Inspection.inspections
Inspection.Draft

Technician.email.lookup("mira@example.com")
```

Open preferences:

- Whether indexing/uniqueness/requiredness should be declared with property
  macros, schema builder declarations, or both.
- Whether the entity macro should infer optionality entirely from Swift optional
  types.

## Syntax Candidate: Fetching And Filtering

Recommended shape:

```swift
@FetchAll(
  Inspection.query
    .where(Inspection.status == .needsParts)
    .where(Inspection.scheduledAt <= Date())
    .where(Inspection.siteName.iLike("%warehouse%"))
    .include(
      Inspection.assignedTechnician,
      Technician.query.select(Technician.displayName, Technician.region)
    )
    .order(Inspection.scheduledAt, .ascending)
    .first(50)
)
var overdueInspections: [Inspection]
```

Dynamic query in an observable model:

```swift
@Observable
final class InspectionSearchModel {
  var searchText = ""
  var selectedRegion: String?
  var includeCompleted = false

  @ObservationIgnored
  @FetchAll var inspections: [Inspection] = []

  func refresh() async throws {
    var query = Inspection.query
      .where(Inspection.siteName.iLike("%\(searchText)%"))
      .include(Inspection.assignedTechnician)
      .order(Inspection.scheduledAt, .ascending)

    if let selectedRegion {
      query = query.where(Technician.inspections.region == selectedRegion)
    }

    if !includeCompleted {
      query = query.where(Inspection.status != .complete)
    }

    try await $inspections.load(query)
  }
}
```

Notes:

- The first example is close to what exists today.
- The second example shows an aspirational nested/reverse field predicate
  spelling. The exact type-safe spelling is an open decision.
- Instant supports nested field filtering, but Swift should not expose it as
  `"technician.region"` strings.

Open preferences:

- Whether query predicates should be written with generated static paths
  (`Inspection.status == .complete`) or key-path closures
  (`.where { $0.status == .complete }`) when possible.
- Whether partial `select` results should decode into generated projection
  structs, raw snapshots, or both.

## Syntax Candidate: Mutations And Optimistic Offline Writes

Recommended shape:

```swift
@Dependency(\.defaultInstantSwiftData) var db

let inspectionID = InstantID<Inspection>()
let technician = Technician.email.lookup("mira@example.com")

try await db.transact {
  Inspection.create(
    id: inspectionID,
    Inspection.siteName.set("North Warehouse"),
    Inspection.status.set(.scheduled),
    Inspection.scheduledAt.set(.now),
    Inspection.assignedTechnician.set(technician.id)
  )

  Inspection.assignedTechnician.link(
    from: inspectionID,
    to: technician
  )
}
```

Alternative, more draft-oriented shape:

```swift
var draft = Inspection.Draft(
  siteName: "North Warehouse",
  status: .scheduled,
  scheduledAt: .now,
  assignedTechnician: technicianID
)

let inspectionID = try await db.save(draft)
```

Expected behavior:

- Writes apply to the local store immediately.
- Active fetches update before the server round trip.
- The transaction persists to a durable outbox while offline.
- Reconnect flushes transactions in order.
- Server rejection marks visible failure state and rolls back or reconciles
  according to the selected conflict policy.

Open preferences:

- Whether most app code should use explicit transaction builders, generated
  drafts, or both equally.
- Whether `create` should always be strict and `update` should preserve
  InstantDB's upsert behavior, with `updateExisting` as the strict update.

## Syntax Candidate: Auth

Recommended shape:

```swift
@AuthSession var auth

switch auth {
case .loading:
  ProgressView()

case .signedOut:
  LoginForm { email in
    try await db.auth.sendMagicCode(email)
  } verify: { email, code in
    try await db.auth.signInWithMagicCode(
      email: email,
      code: code,
      extraFields: UserProfile.Signup(
        displayName: displayName,
        createdAt: .now
      )
    )
  }

case let .signedIn(session):
  WorkspaceView(userID: session.userID)
}
```

Recommended lower-level API:

```swift
let challenge = try await db.auth.sendMagicCode("owner@clinic.example")
let result = try await db.auth.signInWithMagicCode(
  email: "owner@clinic.example",
  code: code,
  extraFields: ClinicUser.Signup(displayName: "Dr. Jain")
)

if result.created {
  try await db.transact {
    UserSettings.create(
      id: .local("settings.\(result.user.id)"),
      UserSettings.user.set(result.user.id),
      UserSettings.theme.set(.system)
    )
  }
}
```

Open preferences:

- Whether auth should hang directly off `db.auth`, methods on `db`, or both.
- Whether auth wrapper values should be enum-shaped (`.loading/.signedOut/
  .signedIn`) instead of optional session plus separate loading/error fields.

## Syntax Candidate: Sharing And Permissions

Recommended sharing shape:

```swift
let share = try await db.shares.create(
  Project.self,
  id: projectID,
  role: .writer
)

try await db.shares.accept(share.inviteToken)
try await db.shares.updateMember(share.id, userID: analystID, role: .reader)

@Shares(Project.self, id: projectID)
var projectShares: [Share<Project>]
```

Recommended permissions shape:

```swift
@InstantPermissions
struct ProjectPermissions {
  static let projects = Rules<Project> {
    Allow.view { auth, data in
      auth.userID == data.owner || auth.userID.isIn(data.members.userID)
    }

    Allow.create { auth, newData in
      auth.isSignedIn && newData.owner == auth.userID
    }

    Allow.update { auth, data, newData in
      auth.userID == data.owner
        || auth.userID.isIn(data.members.writers.userID)
    }
  }
}
```

Open preferences:

- How far the permissions DSL should go in v1:
  - typed Swift CEL builder that emits `instant.perms.ts`
  - structured Swift metadata with explicit escape hatches
  - manual TypeScript permissions with Swift validation only
- Whether sharing should be a high-level typed API above Instant permissions,
  or a thin wrapper over app-defined share entities.

## Syntax Candidate: Presence And Topics

Recommended shape:

```swift
let room = Room<DesignReviewRoom>(
  scope: "design-review",
  id: reviewID.rawValue
)

@RoomPresence(room)
var presence: Presence<DesignReviewPresence>

@RoomTopicMessages(room, DesignReviewReaction.self)
var reactions: [TopicMessage<DesignReviewReaction>]

try await $presence.publish(
  DesignReviewPresence(
    selectedFrameID: selectedFrameID,
    cursor: cursor,
    color: reviewerColor
  )
)

try await db.rooms.publish(
  DesignReviewReaction.raisedHand,
  to: room
)
```

Expected behavior:

- Presence and topics are typed.
- Presence is retained only while connected.
- Topic messages are transient and only delivered to active listeners.
- Durable comments, annotations, decisions, and votes should be normal
  transaction-backed entities.

Open preference:

- Whether room/topic/presence types should be generated from schema declarations
  or declared as independent Swift types.

## Syntax Candidate: Storage

Recommended shape:

```swift
@InstantEntity
struct DamageReport: Codable, Sendable, Identifiable {
  let id: InstantID<Self>
  var summary: String

  @InstantRelation(reverse: "damageReports")
  var inspection: InstantID<Inspection>

  @InstantRelation(reverse: "reports")
  var photo: InstantID<InstantFile>
}

let upload = try await db.storage.upload(
  fileURL,
  path: .inspectionPhoto(inspectionID, fileURL.lastPathComponent)
)

try await db.transact {
  DamageReport.create(
    id: .init(),
    DamageReport.summary.set("Cracked loading dock plate"),
    DamageReport.inspection.set(inspectionID),
    DamageReport.photo.set(upload.fileID)
  )
}
```

Open preferences:

- Whether `$files` should be surfaced as `InstantFile`, `StoredFile`, `$File`,
  or hidden behind storage-specific APIs.
- Whether file paths should be plain strings, typed path builders, or app-defined
  route types.

## Syntax Candidate: Streams

Recommended shape:

```swift
let stream = try await db.streams.create(
  ReportGenerationStream.self,
  clientID: "inspection-report-\(inspectionID.rawValue)"
)

for try await chunk in aiClient.generateInspectionSummary(inspectionID) {
  try await db.streams.append(
    chunk.text,
    to: stream,
    sequence: chunk.index
  )
}

try await db.streams.close(stream)

@StreamContent(ReportGenerationStream.self, clientID: stream.clientID)
var generatedReport: StreamContent
```

Expected behavior:

- Streams are durable where Instant streams are durable.
- UI can observe progressive content.
- Streams are separate from room topics; topics are transient realtime events.

Open preference:

- Whether streams should feel like a first-class database namespace or like a
  service under `db.streams`.

## Design Tree

Each branch gets resolved one question at a time.

1. API identity:
   - InstantDB-native with SQLiteData ergonomics.
   - SQLiteData clone with Instant as backing transport.
   - Dual surface: low-level Instant core plus high-level SQLiteData-like app API.
2. Schema declaration:
   - Entity macros only.
   - Central schema builder only.
   - Entity macros plus generated central schema.
3. Query predicate style:
   - Generated static paths.
   - Key-path closures.
   - Both, with one documented as primary.
4. Relation inclusion:
   - Generated relation tokens.
   - Key-path relation access.
   - Raw escape hatch for advanced paths.
5. Projection:
   - Full entity decode only.
   - Raw snapshots for partial selects.
   - Generated projection structs.
6. Mutation style:
   - Explicit transaction builder.
   - Draft/save first.
   - Both, with transaction builder as the primitive.
7. Offline and conflict policy:
   - Instant parity rollback.
   - Last-write-wins visible reconciliation.
   - App-configurable conflict handlers.
8. Auth:
   - `db.auth` namespace.
   - top-level `db` methods.
   - wrappers plus service namespace.
9. Permissions:
   - Typed Swift DSL.
   - TypeScript generation from structured Swift metadata.
   - Manual TypeScript with Swift validation.
10. Sharing:
   - Built-in typed share API.
   - App-modeled shares and permissions.
   - Both.
11. Rooms:
   - Schema-generated room/topic/presence types.
   - Independent Swift declarations.
12. Storage:
   - Public `$files` entity type.
   - Storage service hides `$files`.
   - Both with typed links.
13. Streams:
   - Database-like typed resource.
   - `db.streams` service.
   - Both.
14. Testing/tooling:
   - CLI as acceptance surface.
   - Swift tests only.
   - Swift plus TypeScript parity artifacts.

## Decision Log

### 2026-06-30: Initial Discovery

Status: source material inspected, no user preference decisions recorded yet.

Observed:

- The existing codebase already has much of the low-level runtime and a typed
  public API skeleton.
- The unresolved risk is not only implementation parity; it is whether the final
  app-facing syntax feels like the right Swift library.

### Question 1: API Identity

Recommended answer:

Choose "InstantDB-native with SQLiteData ergonomics" as the primary public API.

Reason:

SQLiteData is an excellent model for Swift API feel, but InstantDB is not SQL.
The API should not make graph links, realtime subscriptions, auth, files,
presence, topics, streams, optimistic writes, or offline persistence feel like
afterthoughts attached to a table-query abstraction.

Pending user answer.
