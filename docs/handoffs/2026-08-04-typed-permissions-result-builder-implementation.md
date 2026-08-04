# Handoff: Typed Instant permissions — result builder, custom bindings, TS round-trip

**Date:** 2026-08-04  
**Status:** Ready for implementation (design locked)  
**Implement in:** `/Users/laptop/Sync/instant-data-swift` (library first)  
**Then migrate:** `/Users/laptop/Sync/tools/realtime-voice-sqlite-instant` (Scribe)  
**Canonical ADR:** `docs/adr/0012-typed-swift-permissions-source-of-truth.md`  
**Related ergonomics:**  
`realtime-voice-sqlite-instant/handoffs/2026-08-04-recording-list-join-shaped-infinite-query.md`  
(no magic strings, typed paths, library does heavy lifting)

**Do not** re-derive product ACL rules. Scribe’s ownership + segment-share
semantics already live in Scribe’s `instant.perms.ts`. This work is the
**authoring surface + round-trip**, not new security policy.

---

## 0. One-line goal

Swift authors define Instant permissions next to their entity types with a
**result builder**, using **typed paths** and **named bindings they invent**
(`isOwner`, `canView`, `validCreate`, …). The library **prints**
`instant.perms.ts`, **parses** it back, and **verifies** drift. TypeScript is
an artifact; Swift is the source of truth.

---

## 1. Answers to product questions

### 1.1 Extension on the entity + result builder?

**Yes.** Preferred author shape:

```swift
@InstantEntity("recordings")
struct Recording: InstantEntityModel {
  // … fields, paths …
}

extension Recording {
  static let permissions = EntityPermissions {
    Bind("isDirectOwner") {
      Auth.isSignedIn
        && Auth.id == Data[Recording.ownerUserID]
        && Auth.id.isIn(Data[Recording.owner].id)
    }
    Bind("isLinkedGuestOwner") { /* … */ }
    Bind("isReader") { Auth.id.isIn(Data[Recording.readers].id) }
    Bind("canView") {
      Binding.isDirectOwner
        || Binding.isLinkedGuestOwner
        || Binding.isReader
        || Binding.isWriter
        || Binding.isSegmentShareReader
    }
    Bind("canWrite") {
      Binding.isDirectOwner || Binding.isLinkedGuestOwner || Binding.isWriter
    }
    Bind("remainsSameOwner") {
      NewData[Recording.ownerUserID] == Data[Recording.ownerUserID]
    }
    Bind("validCreate") {
      Data[Recording.ownerUserID].isNonempty && Data[Recording.title].isNonempty
    }

    Allow.view { Binding.canView }
    Allow.create { Binding.isDirectOwner && Binding.validCreate }
    Allow.update { Binding.canWrite && Binding.remainsSameOwner }
    Allow.delete { Binding.isDirectOwner || Binding.isLinkedGuestOwner }
  }
}
```

Keep permissions **co-located** with the model the same way `@InstantEntity`
schema lives with the type. Optional later: `@InstantPermissions` macro that
collects static members into an app-level document.

### 1.2 Can people create their own `isOwner` / `canView` / etc.?

**Yes — that is the primary API.** Bindings are **user-defined names**, not a
closed enum of Instant keywords.

Rules for custom bindings:

| Rule | Detail |
| --- | --- |
| Any legal Instant bind identifier | e.g. `isOwner`, `canView`, `validCreate`, `isTeamAdmin` |
| Expression is a typed `PermissionExpr` ADT | Not a free CEL string (except temporary `rawCEL` escape) |
| Bindings may reference other bindings | `canView` may use `Binding.isOwner` |
| No cycles | `A → B → A` fails verification |
| Undefined binding reference | Build/verify error |
| Built-in **helpers** (library) | Sugar that expands to expressions (`Auth.isSignedIn`, `Auth.id`, path ops) — not a restricted set of binding names |

**Built-in helpers** (library-provided leaves/operators) vs **user bindings**:

```text
Library helpers (always available):
  Auth.isSignedIn, Auth.id, Auth.email
  Data[path], NewData[path]
  .isIn, ==, !=, &&, ||, !
  .size / .isNonempty
  Auth.linkedGuestUsers.id   // auth.ref('$user.linkedGuestUsers.id')
  request.modifiedFields     // later slice

User bindings (app invents freely):
  Bind("isOwner") { … }
  Bind("canView") { Binding.isOwner || Binding.isReader }
  Bind("isStripeCustomer") { … }   // totally fine
```

Optional sugar for common patterns (still expands to the same ADT):

```swift
Bind.isOwner(of: Recording.owner)           // → named "isOwner" or explicit name
Bind.isLinkedGuestOwner(of: Recording.ownerUserID)
```

These are **templates** that produce a `Bind` statement. Apps can ignore them
and write fully custom names.

### 1.3 Does Instant still use CEL?

Yes. InstantDB server evaluates CEL. We never replace the server engine. We
**author** rules in Swift ADTs and **emit** CEL into `instant.perms.ts`.

### 1.4 Do authors need TypeScript installed?

Not for authoring. They may need Instant CLI (or a wrapper) to **push** the
generated file. Prefer:

```text
swift run instant-swift-data perms print --… --to instant.perms.ts
npx instant-cli push perms
```

or a single wrapper that does both.

---

## 2. Current code inventory (start here)

| Piece | Path | State |
| --- | --- | --- |
| Stringly permissions document | `Sources/InstantSwiftDataSchema/InstantSwiftDataSchema.swift` (`InstantPermissionsDocument`, `InstantPermissionBinding`) | Exists; **replace leaves** |
| TS printer (string leave) | `TypeScriptPermissionsPrinter` same file | Exists; keep outer file shape; change body generation |
| TS parser | `TypeScriptPermissionsParser` in `TypeScriptSchemaParser.swift` | Exists; parse structure; **must parse CEL → Expr** |
| CLI | `instant-swift-data perms generate|verify` | Exists for examples |
| Example stringly perms | `InstantSchemaExamples.*Permissions` | Migrate after ADT |
| Fixtures | `validation/fixtures/instant.perms.ts`, `recording-action.server.perms.ts` | Round-trip targets |
| Design ADR | `docs/adr/0012-typed-swift-permissions-source-of-truth.md` | Locked |
| Scribe hand-written rules | `realtime-voice-sqlite-instant/instant.perms.ts` | Migration target after library green |
| Scribe offline access | `ScribeRecordingAccess` | Keep; optionally assert parity later |

**Do not** stage unrelated dirty files in `instant-data-swift` (`Package.swift`,
LinkedInfinite WIP, etc.).

---

## 3. Target architecture

```text
┌─────────────────────────────────────────────────────────────┐
│ App (Swift)                                                 │
│  extension Recording { static let permissions = … }         │
│  result builder → InstantEntityPermissions<Recording>       │
└───────────────────────────┬─────────────────────────────────┘
                            │ collect
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ InstantTypedPermissionsDocument                             │
│  namespaces: [AnyEntityPermissions]                         │
│  each: allow[Action] = Expr, bind = [name → Expr]           │
└───────────────────────────┬─────────────────────────────────┘
                            │
          ┌─────────────────┼─────────────────┐
          ▼                 ▼                 ▼
   verify (paths,     print CEL          parse CEL
   cycles, names)     → instant.perms.ts  ← instant.perms.ts
          │                 │                 │
          └──────────── round-trip equal ─────┘
                            │
                            ▼
                   instant-cli push perms
                            │
                            ▼
                      InstantDB server
```

Lowering path for printer:

1. Expand binding references in allow/link expressions **or** emit Instant
   `bind: { name: "expr" }` and leave Instant to resolve aliases (Instant
   supports `bind` — **prefer emit bind as Instant does**, do not necessarily
   inline everything).
2. Print each `Expr` to a CEL string Instant accepts.
3. Wrap in existing `const rules = { … } satisfies InstantRules` file shape.

---

## 4. Core types to implement (suggested module layout)

Prefer new files under `Sources/InstantSwiftDataSchema/`:

```text
InstantPermissionExpr.swift          // ADT + operators
InstantPermissionPath.swift          // typed Data/NewData/Auth path leaves
InstantPermissionBindings.swift      // Bind statement, Binding ref
InstantEntityPermissions.swift       // result builder + EntityPermissions
InstantTypedPermissionsDocument.swift
InstantPermissionCELPrinter.swift    // Expr → String
InstantPermissionCELParser.swift     // String → Expr (subset)
InstantPermissionVerifier.swift      // paths, cycles, reserved fields
```

Or one file first if smaller — but keep **Expr**, **Builder**, **Print**,
**Parse**, **Verify** as separable units for tests.

### 4.1 Expression ADT (minimum viable Instant subset)

Ship the subset Instant + Scribe/Reminders already use:

```swift
public enum InstantPermissionExpr: Hashable, Sendable {
  case always                    // "true"
  case never                     // "false"
  case binding(String)           // reference to bind name (user-defined)
  case not(InstantPermissionExpr)
  case and([InstantPermissionExpr])
  case or([InstantPermissionExpr])

  case equal(InstantPermissionValue, InstantPermissionValue)
  case notEqual(InstantPermissionValue, InstantPermissionValue)
  case lessThan(InstantPermissionValue, InstantPermissionValue)
  case lessThanOrEqual(InstantPermissionValue, InstantPermissionValue)
  case greaterThan(InstantPermissionValue, InstantPermissionValue)
  case greaterThanOrEqual(InstantPermissionValue, InstantPermissionValue)

  case isIn(InstantPermissionValue, InstantPermissionValue)  // lhs in rhs
  // size(x) > 0, size(x) == n, etc.
  case sizeCompare(InstantPermissionValue, InstantPermissionComparison, Int)

  /// Temporary escape — fails verify unless allowlisted.
  case rawCEL(String, reason: String)
}

public enum InstantPermissionValue: Hashable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case authID
  case authEmail
  case dataField(field: String, namespaceHint: String?)      // until paths fully typed
  case newDataField(field: String, namespaceHint: String?)
  case dataRef(path: [String])   // data.ref('owner.id') → ["owner","id"]
  case authRef(path: [String])   // auth.ref('$user.linkedGuestUsers.id')
  case requestModifiedFields     // later
}

// Prefer typed overloads that erase into the above:
//   Data[Recording.ownerUserID] → .dataField("ownerUserID", "recordings")
//   Data[Recording.owner].id → .dataRef(["owner","id"])
```

**Operators** via overloads so the builder feels Boolean:

```swift
func && (lhs: InstantPermissionExpr, rhs: InstantPermissionExpr) -> InstantPermissionExpr
func || …
prefix func ! …

func == (lhs: InstantPermissionValue, rhs: InstantPermissionValue) -> InstantPermissionExpr
func isIn(_ collection: InstantPermissionValue) -> InstantPermissionExpr  // on Value
```

### 4.2 Result builder surface

```swift
@resultBuilder
public enum InstantPermissionRulesBuilder {
  // Build list of InstantPermissionStatement
}

public enum InstantPermissionStatement: Hashable, Sendable {
  case bind(name: String, expression: InstantPermissionExpr)
  case allow(InstantPermissionAction, InstantPermissionExpr)
  case link(relation: String, InstantPermissionExpr)    // phase 2
  case unlink(relation: String, InstantPermissionExpr)  // phase 2
}

public struct EntityPermissions<Entity: InstantEntityModel>: Sendable {
  public var statements: [InstantPermissionStatement]
  public var namespace: String { Entity.instantNamespace }

  public init(@InstantPermissionRulesBuilder _ build: () -> [InstantPermissionStatement])
}

// DSL entry points
public enum Bind {
  public static func callAsFunction(
    _ name: String,
    @InstantPermissionExprBuilder expression: () -> InstantPermissionExpr
  ) -> InstantPermissionStatement

  // Optional templates:
  // public static func isOwner(of path: …, name: String = "isOwner")
}

public enum Allow {
  public static func view(@InstantPermissionExprBuilder _ e: () -> InstantPermissionExpr) -> InstantPermissionStatement
  public static func create(…)
  public static func update(…)
  public static func delete(…)
}

// Reference a user binding inside another expression
public enum Binding {
  public static subscript(dynamicMember name: String) -> InstantPermissionExpr {
    .binding(name)
  }
  // or: Binding.named("canView")
}
```

**DynamicMember** for `Binding.canView` is nice if names are known; for free-form
names, also support `Binding.named("isStripeCustomer")`.

### 4.3 Typed path sugar (phase 1.5 — do not block MVP)

MVP may use string field names **produced only from**
`InstantAttributePath.name` / relation names (never hand-typed in app code):

```swift
// App writes:
Data[Recording.ownerUserID]
// expands using Recording.ownerUserID.name == "ownerUserID"
// and Entity.instantNamespace
```

Implement:

```swift
enum DataPath<Entity: InstantEntityModel> {
  static subscript<Value>(
    _ path: InstantAttributePath<Entity, Value>
  ) -> InstantPermissionValue
}

enum NewDataPath<Entity: InstantEntityModel> { … }

// Nested ref: Data[Recording.owner].id
// needs a small RefChain type
```

**Forbidden in app code:** `"ownerUserID"` string literals in Bind blocks.

### 4.4 Verification

`InstantPermissionVerifier` must fail on:

1. Binding name referenced but never defined  
2. Cyclic binding graph  
3. Empty binding name / invalid identifier for Instant  
4. `fields` rule on `id`  
5. `rawCEL` present without allowlist flag  
6. (When typed paths land) path not in entity’s `instantAttributes` / links  

Emit structured errors with namespace + binding name + message.

### 4.5 CEL printer (Expr → String)

Examples:

| Expr | CEL |
| --- | --- |
| `.always` | `true` |
| `.never` | `false` |
| `.binding("canView")` | `canView` |
| `.and([a,b])` | `(a) && (b)` (parenthesize carefully) |
| `.or([a,b])` | `(a) \|\| (b)` |
| `.equal(.authID, .dataField("ownerUserID"))` | `auth.id == data.ownerUserID` |
| `.isIn(.authID, .dataRef(["owner","id"]))` | `auth.id in data.ref('owner.id')` |
| `.isIn(.dataField("ownerUserID"), .authRef(["$user","linkedGuestUsers","id"]))` | `data.ownerUserID in auth.ref('$user.linkedGuestUsers.id')` |
| `.sizeCompare(field, .greaterThan, 0)` | `size(data.ownerUserID) > 0` |

Match Instant’s existing Scribe/Reminders style closely (spaces, `data.ref('a.b')`).

Integrate with **existing** `TypeScriptPermissionsPrinter` by converting
typed document → current `InstantPermissionsDocument` (string leaves) **or**
rewrite printer to accept typed document directly. Prefer:

```swift
TypedDocument → (lower to InstantPermissionsDocument) → existing file wrapper
```

so file header/import/`satisfies InstantRules` stay stable.

### 4.6 CEL parser (String → Expr)

Minimum: recursive-descent or precedence climb for:

```text
||  &&  !  comparisons  in  true/false  identifiers  auth.id  data.X  newData.X
data.ref('a.b')  auth.ref('…')  size(…)  parentheses
```

Round-trip requirement:

```text
print(parse(print(expr))) == normalize(print(expr))
parse(print(parse(cel)))  == normalize(parse(cel))
```

Unknown constructs → `.rawCEL` **only** in parse-for-migration mode; verify mode
fails.

Use fixtures:

- `validation/fixtures/instant.perms.ts`
- Scribe `instant.perms.ts` ownership + segment share namespaces (as golden)

### 4.7 App document aggregation

```swift
public struct InstantAppPermissions: Sendable {
  public var entities: [any InstantEntityPermissionsProtocol]
  // attrs / $default / rateLimits later
  public func typedDocument() -> InstantTypedPermissionsDocument
  public func legacyDocument() throws -> InstantPermissionsDocument  // for old printer
}
```

Apps:

```swift
enum ScribePermissions {
  static let all = InstantAppPermissions(
    entities: [
      Recording.permissions,
      Transcription.permissions,
      // …
    ]
  )
}
```

---

## 5. Implementation sequence (do in order)

### Phase A — Expr + print (no builder yet)

1. Add `InstantPermissionExpr` / `Value` + operator sugar.  
2. CEL printer unit tests (table-driven).  
3. Lower typed bind/allow maps into `InstantPermissionsDocument` strings.  
4. Print full file; compare to a hand-built expected string for a **tiny** toy
   namespace.

**Done when:** pure unit tests green; no app migration yet.

### Phase B — Result builder + custom Bind names

1. `InstantPermissionRulesBuilder`, `Bind`, `Allow`, `EntityPermissions`.  
2. Tests: user defines `Bind("isOwner")` and `Bind("canView")` referencing it.  
3. Verifier: undefined ref, cycle, reserved field.

**Done when:** extension-on-entity sample compiles in a test target.

### Phase C — Parser + round-trip

1. CEL parser for the subset.  
2. Parse full `instant.perms.ts` structure (reuse `TypeScriptPermissionsParser`
   for outer object; CEL parser for each expression).  
3. Round-trip fixtures; normalize whitespace/parens policy documented.

**Done when:**  
`perms verify` can take typed Swift example **or** parse TS and re-print equal
under normalization.

### Phase D — Typed paths from InstantAttributePath

1. `Data[Entity.path]` sugar.  
2. Ref chains for `data.ref` / `auth.ref`.  
3. Reject stringly field APIs in public DSL (keep internal erase).

### Phase E — Migrate library examples

1. Convert `remindersV3Permissions` / `sharingPermissions` / `todoPermissions`
   from string leaves to typed builders.  
2. Keep CLI `perms generate --example …` working.  
3. Existing verify fixtures stay green.

### Phase F — Scribe migration (separate PR/repo)

1. Add `ScribeInstantPermissions` (or per-entity extensions) mirroring current
   `instant.perms.ts` for:
   - `recordings`
   - `recordingSegmentShares`
   - `transcriptions` / `transcriptionSegments` / `transcriptionWords`
   - `recordingAttachments`
2. Generate `instant.perms.ts`; diff against current; fix printer until equal
   under normalization.  
3. Wire drift gate: build step or `scripts/instant-drift` compares print(Swift)
   to committed file.  
4. Push only after diff is intentional empty.  
5. Optional: assert `ScribeRecordingAccess` stories still match binding names.

### Phase G — Polish (can defer)

- `link` / `unlink` permissions typed  
- `$default`, `attrs`, rate limits in builder  
- `@InstantPermissions` macro collecting statics  
- `instant-swift-data perms push` wrapper  
- Full Instant CEL feature parity  

---

## 6. Test plan (required evidence)

| Test | Asserts |
| --- | --- |
| Expr printer tables | Each leaf/operator → exact CEL |
| Custom binding composition | `canView` prints Instant bind + allow using name |
| Verifier undefined | References missing bind → error |
| Verifier cycle | A→B→A → error |
| Builder smoke | Entity extension builds document |
| Parse subset | CEL strings → Expr round-trip |
| Fixture round-trip | `validation/fixtures/instant.perms.ts` |
| Example migrate | `reminders` or `todos` generate matches fixture |
| Scribe golden (phase F) | Generated perms ≡ production intent |

Run:

```sh
cd /Users/laptop/Sync/instant-data-swift
swift test --filter InstantPermission   # or whatever suite name you choose
swift run instant-swift-data perms verify --example reminders --from … 
```

Do not block on whole-package test targets broken for unrelated reasons; add a
**focused** test target if needed.

---

## 7. Acceptance criteria (library MVP = end of Phase C/D)

- [ ] No public API requires hand-written CEL for normal ownership/share rules  
- [ ] Apps can `Bind("anyName") { … }` and reference it from `Allow` / other binds  
- [ ] Result builder co-located on entity works  
- [ ] Printer emits valid `instant.perms.ts` Instant CLI can push  
- [ ] Parser + printer round-trip for the supported CEL subset  
- [ ] Verifier catches undefined bindings and cycles  
- [ ] ADR 0012 remains accurate; update only if implementation forces a decision change  
- [ ] CHANGELOG / commit ledger updated in `instant-data-swift`  

Scribe migration is **separate acceptance** (Phase F).

---

## 8. What else needs to be done (broader checklist)

### Library (`instant-data-swift`)

1. **This handoff** — typed permissions ADT, builder, parse/print, verify.  
2. **Schema parity** — same philosophy already partly there (`@InstantEntity`,
   printers); ensure schema and perms both “Swift source → TS artifact.”  
3. **Linked/include infinite query** work (other dirty WIP) — do **not** mix
   into this PR.  
4. **Docs** — user-facing page: “Author permissions in Swift.”  
5. **CLI** — `perms print` from app target / example; optional push wrapper.

### Scribe (`realtime-voice-sqlite-instant`)

1. After library MVP: **migrate** `instant.perms.ts` to Swift builders.  
2. **Drift gate** so hand-edits to TS fail the build.  
3. **Share UI** (product) — still missing; not blocked on permissions DSL but
   blocked on good local/live tests.  
4. **Offline access** — keep `ScribeRecordingAccess`; optionally generate or
   dual-test against typed bindings.  
5. **Live two-guest CEL harness** — still needed once; pure tests don’t replace
   server evaluation.  
6. **Legacy `ownerUserID` backfill** — optional attrs already; unowned rows
   invisible under new perms.  
7. **Recording list join-shaped infinite query** — separate handoff
   (`2026-08-04-recording-list-join-shaped-infinite-query.md`); do not couple.  
8. **Unrelated dirty WIP** — leave alone (launch projection, etc.).

### Product / ops

1. `instant-cli push` remains required for deploy until a full wrapper exists.  
2. Production already has ownership + segment-share **rules** pushed; regenerating
   must not silently weaken them — golden diff is mandatory.

---

## 9. Explicit non-goals (this project)

- Replacing Instant server permission evaluation  
- Full CEL language coverage on day one  
- Forcing apps to use only predefined `isOwner`/`canView` names  
- Building Scribe share UI in the same PR  
- Implementing recording-list infinite query in the same PR  
- Rewriting `ScribeRecordingAccess` into the library  

---

## 10. Suggested first PR (smallest shippable)

**Title:** Typed `InstantPermissionExpr` + CEL printer + toy builder  

**Includes:**

- Expr ADT + operators  
- Printer → strings  
- `Bind`/`Allow` result builder  
- Verifier (undefined + cycle)  
- Unit tests only  

**Excludes:** full TS file parser, Scribe migration, example mass rewrite.

**Second PR:** parser + fixture round-trip.  
**Third PR:** migrate one library example (todos or reminders).  
**Fourth PR (Scribe):** generate `instant.perms.ts` from Swift.

---

## 11. Reference snippets for the implementer

### Instant bind emission shape (must match)

```ts
recordings: {
  bind: {
    isDirectOwner: "auth.id != null && auth.id == data.ownerUserID && …",
    canView: "isDirectOwner || isLinkedGuestOwner || isReader || …",
  },
  allow: {
    view: "canView",
    create: "isDirectOwner && validCreate",
  },
},
```

### Scribe rules to preserve (phase F golden)

See Scribe `instant.perms.ts` namespaces:

- `recordings` (owner, linked guest, readers, writers, segment share reader)  
- `recordingSegmentShares`  
- `transcriptions` / `transcriptionSegments` / `transcriptionWords`  
- `recordingAttachments`  

Do not “simplify” product meaning while migrating.

### Prior art in design prefs

`INSTANT_DATA_API_DESIGN_PREFERENCES.md` already sketches:

```swift
@InstantPermissions
struct ProjectPermissions {
  static let projects = Rules<Project> {
    Allow.view { auth, data in … }
  }
}
```

Prefer **entity extension + Bind/Allow** (this handoff) over free `auth, data`
closures if closures encourage untyped access. Closures are OK only if fully
typed (`Auth`, `DataProxy<Entity>`).

---

## 12. Coordination notes

- Work on a **named branch** in `instant-data-swift`; do not leave detached HEAD.  
- Multiple agents may touch `main`; don’t clobber LinkedInfinite / CLI WIP.  
- After each verified slice: commit, `docs/audits/commit-changelog.md` entry,
  library CHANGELOG if you use one.  
- When Scribe migrates: two-commit change-log pattern in Scribe repo.  

---

## 13. Definition of “done” for the person picking this up

You are done with **library MVP** when another engineer can write:

```swift
extension Todo {
  static let permissions = EntityPermissions {
    Bind("isOwner") { Auth.id == Data[Todo.ownerID] }
    Bind("canView") { Binding.isOwner || Auth.isSignedIn }
    Allow.view { Binding.canView }
    Allow.create { Binding.isOwner }
  }
}
```

…run a library command or test helper, get a correct `instant.perms.ts`
fragment, and round-trip that fragment through parse→print without semantic
drift.

You are done with **Scribe adoption** when Scribe’s committed `instant.perms.ts`
is **generated** from Swift and the drift gate fails if someone hand-edits CEL
out of band.
