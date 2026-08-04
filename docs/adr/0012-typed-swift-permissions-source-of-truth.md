# 0012. Typed Swift permissions as source of truth

- Status: accepted (design locked; implementation not complete)
- Date: 2026-08-04
- Scope: Instant Swift Data schema/permissions authoring, TypeScript emission,
  Scribe and every other Instant app
- Related: ADR 0001 (app owns schema/permissions), Instant CLI push/pull,
  `INSTANT_DATA_API_DESIGN_PREFERENCES.md` `@InstantPermissions` sketch,
  Scribe handoff ergonomics in
  `realtime-voice-sqlite-instant/handoffs/2026-08-04-recording-list-join-shaped-infinite-query.md`

## Context

InstantDB’s security surface is a **permissions document of CEL-like
expressions** (`instant.perms.ts`). Today Instant Swift Data already has a
thin intermediate model:

```text
InstantPermissionsDocument
  → InstantNamespacePermissions(allow/bind as [String: String])
  → TypeScriptPermissionsPrinter
  → instant.perms.ts
```

That intermediate model still forces **magic strings**:

```swift
InstantPermissionBinding("isOwner", "auth.id in data.ref('owner.id')")
allow: [.view: "isOwner || isWriter || isReader"]
```

Scribe currently skips even that and hand-authors TypeScript. That is wrong for
Swift-first apps: authors should not maintain a parallel stringly CEL dialect
or install TypeScript to define security. Same principle as schema: **model in
Swift with the types the app already defined; library does verification and
TS emission.**

Instant still consumes TypeScript on the wire (`instant-cli push perms`). That
does not make TypeScript the product source of truth. The source of truth is
the typed Swift permissions document; TS is an artifact.

## Decision

### 1. No magic strings at the author surface

Permissions are expressed against **entity types**, **attribute paths**, and
**relation paths** the schema already defines — not bare `"recordings"`,
`"ownerUserID"`, or `"auth.id in data.ref('owner.id')"`.

Borrow the recording-list ergonomics:

| Bad (today) | Good (target) |
|---|---|
| `namespace: "recordings"` | `Rules<Recording>` / `namespace: Recording.self` |
| `"auth.id in data.ref('owner.id')"` | `Auth.id.isIn(Data.owner.id)` |
| `bind: [("canView", "isOwner \|\| isReader")]` | named `Binding` ADTs + boolean `Expr` ADT |
| hand-written `instant.perms.ts` | generated + round-trip verified |

### 2. Algebraic expression model (not string CEL)

Permission **predicates** are a closed ADT that prints to Instant CEL and
parses back:

```swift
// Sketch — names illustrative; exact symbols TBD in implementation
enum InstantPermissionExpr: Hashable, Sendable {
  case always
  case never
  case binding(InstantPermissionBindingName)   // e.g. .isDirectOwner
  case not(Self)
  case and([Self])
  case or([Self])

  // Comparisons / membership (typed leaves)
  case equal(InstantPermissionValue, InstantPermissionValue)
  case notEqual(InstantPermissionValue, InstantPermissionValue)
  case isIn(InstantPermissionValue, InstantPermissionCollection)
  case sizeAtLeast(InstantPermissionValue, Int)
  case sizeEquals(InstantPermissionValue, Int)
  // …
}

enum InstantPermissionValue: Hashable, Sendable {
  case authID
  case authEmail
  case dataField(AnyInstantAttributePath)      // typed path on Entity
  case newDataField(AnyInstantAttributePath)
  case dataRef(InstantPermissionRefPath)       // data.ref('owner.id') as path ADT
  case authRef(InstantPermissionRefPath)       // auth.ref('$user.linkedGuestUsers.id')
  case string(String)                          // only for true constants
  case number(Double)
  case null
  // …
}
```

**Named bindings** are first-class, not free-floating CEL aliases:

```swift
struct InstantPermissionBindingDefinition: Hashable, Sendable {
  var name: InstantPermissionBindingName  // typed, not raw String
  var expression: InstantPermissionExpr
}

// Built-in helpers the library provides (not magic strings apps invent ad hoc):
// - isSignedIn
// - isDirectOwner(of: Recording.owner / Recording.ownerUserID)
// - isLinkedGuestOwner(of: …)
// - isInReaders / isInWriters
// - remainsSameOwner
// - sizeNonempty(…)
// Apps compose these into canView / canWrite / validCreate.
```

Actions stay an enum (already exist as `InstantPermissionAction`):

```swift
enum InstantPermissionAction { case view, create, update, delete, … }
```

Namespace rules:

```swift
struct InstantEntityRules<Entity: InstantEntityModel> {
  var allow: [InstantPermissionAction: InstantPermissionExpr]
  var bind: [InstantPermissionBindingDefinition]
  var link: [InstantLinkPermission]   // typed relation labels
  var unlink: [InstantLinkPermission]
  var fields: [InstantFieldPermission]
}
```

App-facing sugar (direction of `@InstantPermissions` from design prefs):

```swift
// Target author surface (illustrative)
extension Recording {
  static let permissions = EntityPermissions {
    Bind.isDirectOwner {
      Auth.isSignedIn
        && Auth.id == Data.ownerUserID
        && Auth.id.isIn(Data.owner.id)
    }
    Bind.isLinkedGuestOwner {
      Auth.isSignedIn
        && Data.ownerUserID.isIn(Auth.linkedGuestUsers.id)
        && Data.ownerUserID.isIn(Data.owner.id)
    }
    Bind.isReader { Auth.id.isIn(Data.readers.id) }
    Bind.isWriter { Auth.id.isIn(Data.writers.id) }
    Bind.isSegmentShareReader {
      Auth.id.isIn(Data.segmentShares.readers.id)
    }
    Bind.canView {
      .isDirectOwner || .isLinkedGuestOwner || .isReader
        || .isWriter || .isSegmentShareReader
    }
    Bind.canWrite {
      .isDirectOwner || .isLinkedGuestOwner || .isWriter
    }
    Bind.remainsSameOwner {
      NewData.ownerUserID == Data.ownerUserID
    }
    Bind.validCreate {
      Data.ownerUserID.size > 0 && Data.title.size > 0
    }

    Allow.view { .canView }
    Allow.create { .isDirectOwner && .validCreate }
    Allow.update { .canWrite && .remainsSameOwner && .validUpdate }
    Allow.delete { .canManage }
  }
}
```

Library verifies at compile time / generation time:

- every path exists on `Entity`
- every binding name referenced in `Allow` is defined
- no cycles in binding expansion (or expand fully before print)
- `id` field rules are rejected (Instant forbids them)
- link/unlink targets are real relation labels

### 3. Parser/printer: Swift ⇄ TypeScript (bidirectional)

| Direction | Job |
|---|---|
| **Print** | `InstantPermissionsDocument` (typed) → `instant.perms.ts` |
| **Parse** | `instant.perms.ts` → typed document (for pull/import/migration) |
| **Round-trip** | `print(parse(ts))` and `parse(print(swift))` normalize equal |

Rules:

1. **Swift is source of truth** for app repos that choose Instant Swift Data.
2. Generated `instant.perms.ts` may be committed as an **artifact** for
   `instant-cli push` and human review, never hand-edited as primary.
3. Drift gate: regenerate (or parse+diff) and fail the build if TS ≠ Swift.
4. Unparseable CEL escapes: only via an explicit
   `InstantPermissionExpr.rawCEL(String, reason:)` that **fails CI by default**
   unless allow-listed — temporary bridge, not normal authoring.

Existing `TypeScriptPermissionsPrinter` + permissions parse helpers in
`TypeScriptSchemaParser` are the seed; they must move from
`String` leaves to the ADT.

CLI (library):

```text
instant-swift-data perms print --from ScribePermissions --to instant.perms.ts
instant-swift-data perms parse --from instant.perms.ts --json
instant-swift-data perms verify --swift … --from instant.perms.ts
instant-swift-data perms push   # print then instant-cli push perms
```

### 4. What this is not

- **Not** re-implementing Instant’s server CEL engine in Swift for production
  security. Server still evaluates the printed rules.
- **Not** replacing offline product helpers like Scribe’s
  `ScribeRecordingAccess` — those remain app-owned visibility models for tests
  and UI; they should be **derived from or tested against** the same typed
  bindings where practical.
- **Not** requiring apps to install a TypeScript toolchain to *author* rules.
  They may still run `instant-cli` (or a wrapper) to push the generated file.

### 5. Migration path for Scribe

1. Implement typed ADT + printer/parser + round-trip tests in
   `instant-data-swift` (library).
2. Encode current `instant.perms.ts` recording/ownership/segment-share rules
   as typed Swift (`ScribeInstantPermissions`).
3. Generate `instant.perms.ts`; fail drift if hand edits diverge.
4. Delete stringly duplicate intent once generators are trusted.
5. Keep `ScribeRecordingAccess` pure tests; assert they agree with expanded
   binding names for the recording graph.

## Consequences

- Swift authors get autocomplete, typo-proof paths, and build-time verification.
- Instant CLI remains the deploy vehicle; TypeScript remains an interchange
  format, not the design surface.
- Library owns the heavy lifting (parse/print/verify); apps own the rules
  content (ADR 0001).
- Open Instant CEL features not yet in the ADT need an explicit extension or
  temporary raw escape with a tracking issue — never silent string holes.

## Implementation notes (first slices)

1. **Expr ADT + CEL printer** for the subset Instant actually uses in
   Reminders/Scribe (auth.id, data/newData fields, `in`, `ref`, `size`,
   `&&`/`||`/`!`, comparisons, `request.modifiedFields` later).
2. **Parser** for that subset from `instant.perms.ts` (reuse/extend
   `TypeScriptSchemaParser` permissions parsing).
3. **Typed path leaves** bound to `InstantAttributePath` / relation paths.
4. **Round-trip fixtures**: `validation/fixtures/instant.perms.ts` + Scribe’s
   ownership rules.
5. **Scribe migration** only after library round-trip is green.

## Rejected alternatives

| Alternative | Why rejected |
|---|---|
| Keep hand-written TS as source of truth | Forces Swift apps into TS; strings drift from entity models |
| Only validate TS from Swift without printing | Still dual authoring |
| Pure Swift access model as “permissions” | Does not enforce Instant server security |
| Full CEL AST parity on day one | Too large; ship Scribe/Reminders subset first |
