# Instant Swift Data Implementation Plan

This plan is reconciled with
`docs/instant-swift-data-goals.md`, which is the portable goal contract for the
project. When the two documents differ, the goals document wins and this plan
should be updated rather than treated as a competing source of truth.

The accepted application/runtime ownership boundary is
`docs/adr/0001-application-sync-boundary.md`.

The active, version-gated execution sequence for the V3 public syntax and real
Swift/TypeScript synchronization is `docs/v3-e2e-port-plan.md`. This document
remains the full feature inventory and progress record.

## Goal

Build a single Swift package that feels like SQLiteData/SwiftData at the app
surface, but uses InstantDB as the backing system.

The important concrete pieces are:

- A local store: an in-memory and persisted copy of the facts the client knows.
- A query observer: code that turns a query into a live Swift value and updates it
  when the local store changes.
- A mutation outbox: a durable ordered list of writes that have been applied
  optimistically but not yet confirmed by InstantDB.
- A transport: WebSocket/SSE and HTTP calls that exchange queries, transaction
  steps, auth, files, rooms, presence, topics, and stream messages with Instant.
- Schema tooling: Swift declarations that can emit the TypeScript schema,
  permissions, generated Swift entity/query/mutation helpers, and validation
  fixtures.

The target package should not require maintaining a separate core Swift SDK and
a separate sharing wrapper. It can still have internal targets, but they should
live in one repository and version together.

Resolved decisions from the later goal pass:

- The package, module, and CLI naming centers on `InstantSwiftData` and
  `instant-swift-data`.
- Swift `Date` maps to Instant's `date` semantic value by default. Epoch
  milliseconds remain an explicit compatibility strategy.
- SQLite is the first durable Swift persistence backend unless benchmarks prove
  another backend is better.
- Macro support and benchmark support are first-class package targets.
- The CLI must be agent-interactable, non-captive, and backed by the same
  durable auth/cache/outbox state as app clients.
- Swift concurrency compliance is a first-class implementation constraint. The
  detailed contract lives in `docs/swift-concurrency-guidance.md`; the core
  package must stay clean under Swift 6 strict concurrency.
- Apps own schema, observation lifetime and dynamic inputs, mutations, auth,
  and sharing. The library owns cache, optimistic observation, persistent
  outbox/reconnect, delivery, and per-operation rejection isolation.
- Static fetch declarations auto-observe local-first. Dynamic keys replace the
  wrapper-owned observation; composite fetch requests do not expose manual
  fetch/subscribe/merge work to features.
- Public `queryLocal` is rejected. Local-only behavior is selected through an
  injected local-only client that supports ordinary query and mutation APIs.
- Flush and delivery status are restricted to CLI, diagnostics, tests, and
  explicit user-visible operations.
- Entity delivery is independent from media transfer; media caching moves
  toward bounded LIFO with per-item rejection isolation.

## Upstream Inventory

Vendored on 2026-06-12. Canonical query/observation semantics were rechecked on
2026-07-25 against Instant `origin/main` `a57ca801` and SQLiteData `origin/main`
`63a2ff6`, both dated 2026-07-24.

| Source | Local path | Revision inspected | What to mine |
| --- | --- | --- | --- |
| Instant TypeScript | `upstream/instant` | `e7101761` | Canonical client behavior, schema surface, query grammar, transaction grammar, streams, storage, presence, auth, offline cache, sync table |
| SQLiteData | `upstream/sqlite-data` | `0c79d7a` | SwiftData-like API shape, `@FetchAll`/`@FetchOne`/`@Fetch`, dependency bootstrap, migration docs, observation ergonomics, example ports |
| Swift sharing Instant | `upstream/sharing-instant` | `d78601a` | Prior Swift Instant behavior: reactor, triple store, offline tests, pending flush order, schema codegen, presence/topics/storage |
| Instant iOS SDK draft | `upstream/instant-ios-sdk` | `304677c` | Core Swift client, WebSocket, local storage, auth, storage, query manager, local-first manager, macros |

At the current revisions, Instant still separates cached-first
`subscribeQuery` from strict offline-failing `queryOnce`, and SQLiteData still
backs normal `@FetchAll` CRUD with the database reader while reserving
`SyncEngine` interaction for explicit sharing operations.

`upstream/README.md` is the submodule map. The transferred plan referenced a
local-only `swift-sharing-instant-ship` checkout and a Sigil bridge path; neither
is part of this moved repository, so they are historical research leads rather
than current local inputs.

## Feature Parity Target

Instant's TypeScript client is the contract. The Swift package should support
each surface below with Swift-native types and end-to-end validation against a
real Instant app.

### Connection And Runtime

- Configure `appId`, `apiURI`, `websocketURI`, transport type, logging, date
  decoding, validation toggles, cache limits, and custom persistence store.
- Report connection status: connecting, opened, authenticated, closed, errored.
- Authenticate transport sessions and resubscribe on reconnect.
- Support WebSocket first. Keep SSE as a target if Instant's public protocol
  remains available and useful for server-like Swift environments.

Current local progress: `InstantRuntime.connectionStatus()` reports the
configured app id, HTTP/WebSocket endpoints, local-cache transport kind, opened,
authenticated, and closed local lifecycle states, current user id, pending
outbox count, and processed transaction checkpoint. The CLI proves this local
runtime shape with `instant-swift-data connection status --jsonl`,
`instant-swift-data connection close --json`, and
`instant-swift-data connection connect --json`. `InstantLiveTransportClient`
now provides injectable `.local` and `.live` session clients for the upstream
WebSocket protocol shape; `instant-swift-data validation live-session --jsonl`
builds `/runtime/session?app_id=...`, sends `init`, decodes `init-ok`, sends
`add-query`, and decodes a query/refresh response. The command uses `.local` by
default and switches to the real WebSocket when
`INSTANT_SWIFT_DATA_RUN_LIVE_SESSION=1` is set. `validation live-transaction`
extends the local protocol proof through `transact`, `transact-ok`, and the
query `refresh-ok`, while real WebSocket mutation requires the separate
`INSTANT_SWIFT_DATA_RUN_LIVE_TRANSACTION=1` opt-in and resolves Swift
`namespace/field` attr ids from the server attrs returned by `init-ok`. The
TypeScript validation runner
also consumes the Swift JSONL with `--swift-live-session-contract` so the
protocol transcript stays readable from both sides, and
`--swift-live-transaction-contract` validates the local transaction transcript
from the TypeScript side. In live observe mode the Swift command now applies the
matching external `refresh-ok` into a temporary `InstantRuntime` cache and emits
the cached Todo ids/texts as evidence, so
`--boundary-typescript-live-observe` proves both WebSocket delivery and local
runtime hydration from the TypeScript-authored admin write. Remote reconnect
replay remains future work.
`--swift-local-integrations-contract` validates the Swift-authored local room
presence/topic evidence from TypeScript, including the room handle, topic name,
presence value keys, topic payload keys, and relaunch persistence.
Cross-client Swift/TypeScript mutation delivery now has opt-in validation
coverage in both directions, but it is not yet an always-on runtime event pump.

### Schema

- Entities with scalar attributes: string, number, boolean, date, json.
- Swift-only type safety for enums, discriminated unions, typed JSON fields,
  typed IDs, local IDs, and decode validation.
- Required/optional fields.
- Indexed fields and unique fields.
- Primary keys and lookup by unique attribute.
- Links with forward/reverse labels, one/many cardinality, required forward
  links, and cascade delete behavior.
- Rooms with typed presence and typed topics.
- Special namespaces: `$users` and `$files`.
- Swift schema declarations must derive TypeScript `instant.schema.ts`.
- Swift permissions declarations should derive `instant.perms.ts`; do not leave
  permissions as a manual TypeScript-only sidecar.
- Schema tooling must support round trips:
  Swift schema -> TypeScript schema -> Swift IR, and TypeScript schema -> Swift
  generated helpers -> TypeScript schema.

### Querying

- Live subscriptions equivalent to `subscribeQuery`/React `useQuery`.
- Static `@FetchAll`, `@FetchOne`, and `@Fetch` declarations start local-first
  observation without a view task or manual load.
- Composite fetch declarations own their child reads, subscriptions, and merge;
  features only declare the composite request and any dynamic inputs.
- One-shot strict queries equivalent to `queryOnce`, exposed through
  `InstantSwiftDataClient.queryOnce(_:)` for raw snapshots/emissions and typed
  `queryOnceDecoded(_:)` for decoded values plus pagination `pageInfo`.
- Top-level namespace queries and nested relation queries.
- Explicit linked-entity inclusion, including typed forward includes like
  `.include(Post.author, User.query.select(User.name))`. Raw core materialization
  also supports multi-linked entities and reverse links. The typed query surface
  now accepts generated reverse relation tokens. Because Swift macros cannot add
  members to the target entity from a property declared on the source entity,
  `@InstantRelation(reverse: "posts") var author: InstantID<User>` generates a
  source-hosted token used as `.include(Post.posts, Post.query.select(Post.title))`.
- Field selection, including typed `.select(Todo.text, Todo.isCompleted)`.
  Partial selections should be read as raw snapshots unless the selected fields
  satisfy the entity decoder.
- `where` operators: equality, `$ne`, `$isNull`, `$gt`, `$lt`, `$gte`, `$lte`,
  `$in`, `$like`, `$ilike`, `and`, `or`, and nested field paths like
  `relation.field`.
- Local triple materialization currently supports raw nested field filters over
  declared forward and reverse links, including `relation.id`,
  `relation.child.field`, null/not-equals matching for missing links, and
  nested include plans. Strict runtime query validation rejects undeclared
  fields, invalid include targets, and illegal nested pagination before
  materialization/cache writes. Low-level `InstantStore.materialize` remains
  validation-light for upstream fixture parity tests, matching Instant core's
  raw query-resolution behavior without weakening runtime/client validation.
- Ordering on indexed fields and `serverCreatedAt`.
- Local triple materialization uses `serverCreatedAt` ascending as the implicit
  no-order query order, matching Instant, and supports explicit
  `serverCreatedAt` ordering as
  an order-only reserved field backed by the entity id triple's `txTime`, with a
  namespace-triple fallback for low-level local rows without an id triple.
- The typed query surface exposes this reserved order as
  `.order(.serverCreatedAt, .descending)`.
- `serverCreatedAt` is not materialized into entity snapshots or decoded models,
  and schema attributes using that name are rejected at bootstrap. User data
  should use domain fields such as `createdAt`.
- Pagination on top-level namespaces: `limit`, `offset`, `first`, `after`,
  `last`, `before`, inclusive cursors, and page info.
- Infinite query subscriptions.
- Query validation rejects undeclared fields, unsupported nested paths, invalid
  include targets, unsupported operators, and illegal nested pagination before
  the network call.
- Hashing/caching of queries so cached results can be restored consistently.
- No public `queryLocal`; local-only clients use the same ordinary query and
  observation surface as live clients. Keep any cache materializer private.

### Mutations

- Transaction builder parity with TypeScript `db.tx`.
- Strict `create`, upserting `update`, strict update with no upsert, `merge`,
  `delete`, `link`, `unlink`, and `ruleParams`. Repeatable local seed commands
  should use explicit upsert helpers rather than weakening app-facing `create`.
- Batch transactions with stable operation order.
- Lookup refs by unique attribute for writes and links. Preserve lookup-shaped
  pending mutations for transport lowering; resolve local optimistic effects
  sequentially against the AEV index, no-op unresolved non-strict lookups, and
  reject strict lookup updates before cache/outbox writes when missing.
- Preserve `ruleParams` operations for transport lowering. They should validate
  lookup refs but otherwise no-op local optimistic materialization because their
  effect is server-side permission evaluation.
- Delete locally removes entity triples plus forward/reverse refs and honors
  cascade metadata. Add namespace-specific delete steps later; until then the
  Swift `.deleteEntity(String)` fallback applies cascades for every matching
  local incoming ref edge for that raw id.
- Optimistic application before server confirmation.
- Rollback or visible failure state when the server rejects a mutation.
- Durable pending mutation persistence across process restart.
- In-flight mutation de-duplication: a pending transaction id can be replayed
  idempotently only with the same prepared operations, while mismatched
  operations fail validation before another outbox row is persisted.
- Stable flush ordering after reconnect, especially link-before-create hazards.
- High-bandwidth write path for repeated field updates and linked entities.

Current local progress: pending mutations now lower into typed
`InstantTransportMutation` values with Instant-shaped `txSteps` such as
`add-triple`, `deep-merge-triple`, `retract-triple`, `delete-entity`, and
`rule-params`. Local strict-create and strict-update preconditions are preserved
and reflected as `{mode: "create"}` / `{mode: "update"}` transport options on
matching steps. Pending mutations also de-duplicate in-flight transaction IDs:
exact replays return the durable store state without appending another outbox
row, and conflicting replays fail validation. The CLI proves the bridge
non-captively with
`instant-swift-data outbox transport --json` and can include failed rows for
inspection with `instant-swift-data outbox transport --all --jsonl`.
`InstantMutationTransportClient` provides the Sendable send/ack seam that future
WebSocket transport will implement, and the current `.local` instance proves
durable confirmation/failure application with
`instant-swift-data outbox flush --jsonl`. Failed transport sends and explicit
outbox failures now make `connection status --json` report an `errored` state
with a last-error message, and retry/successful flush clears that local status
when no failed mutations remain. Real WebSocket send/ack, retry scheduling, and
server rejection rollback remain future transport work.

### Offline And Local First

- Persist schema attributes, triples, cached query results, pending mutations,
  processed tx id, auth session, and sync table state.
- Subscriptions can emit cached results while offline.
- `queryOnce` fails offline, but carries last-known cached result when available.
- Offline writes update observers immediately, stay in the outbox while the
  connection is closed, and flush in deterministic order after reconnect.
- Server confirmations clean up pending mutations without erasing newer local
  state.
- Process restart while offline restores pending local state before network
  reconnect.

Current local progress: durable `closed` connection state now makes
`InstantRuntime.queryOnce(_:)` fail with a `networkFailed` `InstantError` before
fresh local materialization, while carrying the matching `InstantCachedQuery`
when one exists. The CLI proves the non-captive shape by returning the network
exit code and cached-query summary for `instant-swift-data query todos --json`
after `instant-swift-data connection close --json`. Query observation refreshes
the persisted SQLite snapshot before registering, so finite watchers such as
`instant-swift-data examples todos watch --events 1 --jsonl` still emit cached
local results while the connection is closed. `outbox flush` now refuses to send
pending mutations while the durable state is closed, leaves them queued, and
flushes them through the same local mutation transport after
`instant-swift-data connection connect --json`. Todo example mutation commands
can also run while closed: they write optimistically, then print the restored
local SQLite snapshot through the same bounded observation path that powers
offline watches. `instant-swift-data validation local-todos --jsonl` now emits
closed-connection offline write, offline relaunch restore, and reconnect flush
evidence rows for this local path. `connection status/connect/close` argument
validation now flows through the shared `swift-parsing` target while preserving
the `inspect`/`show`, `open`, and `disconnect` aliases.
Inbound server-applied transaction handling now has a local loopback path:
`InstantRuntime.applyServerTransaction` persists the server triples, publishes
matching live observers, advances the processed transaction checkpoint, and
leaves the optimistic outbox untouched. The terminal proof is
`instant-swift-data validation server-transaction-loopback --jsonl`; real
WebSocket delivery remains future transport work.

### Realtime Sync

- Initial query load.
- Incremental triple updates.
- Query invalidation/recomputation across all active subscribers when pending
  mutations change.
- Multiple simultaneous queries with different `with` clauses.
- Reverse-link observer propagation.
- Deletions that remove forward and reverse links without ghost entities.
- Sync-table path for high-volume ordered result sets.

### Auth

- Magic code send/verify/sign-in.
- Token sign-in and session restore.
- Guest sign-in.
- OAuth / id-token sign-in surfaces where supported by Instant.
- Sign out with token invalidation option.
- Auth state subscription.
- Auth session persistence and refresh token handling.

Current local progress: `InstantRuntime` persists auth sessions in SQLite,
publishes auth-state changes through `observeAuthSession`, and the public
`InstantSwiftDataClient` dependency exposes the same stream alongside guest,
token, id-token, magic-code, session lookup, and sign-out operations.
`InstantIDTokenExchange` and `InstantMagicCodeExchange` are Swift Dependencies
value clients with reusable `.local` instances for durable local proof,
`InstantRefreshTokenVerifier` handles refresh-token sign-in/session restore,
`InstantOAuthExchange` follows the same shape for authorization-code flows, and
`InstantAuthTokenInvalidator` gives sign-out a dedicated token-invalidation
dependency. The OAuth and id-token exchange requests carry the current refresh
token when one is persisted so live transport can support Instant's session
upgrade/linking shape.
The CLI proves this path non-captively with commands such as
`instant-swift-data auth id-token google-ios <id-token> --json` and
`instant-swift-data auth oauth <code> --json` and
`instant-swift-data auth watch --events 1 --jsonl`; sign-out defaults to token
invalidation and can skip it locally with
`instant-swift-data auth sign-out --skip-token-invalidation --json`.
The upstream auth recipe is also exposed through
`instant-swift-data examples auth send-code <email>`,
`verify-code <email> <code>`, `status`, `watch --events 1 --jsonl`, and
`sign-out`, reusing the same `InstantMagicCodeExchange` dependency seam and
local durable auth-session store. The terminal `send-code` output represents
the transient code-entry form state that the React recipe keeps in component
state, and dashboard output derives the email from `email:<address>` local user
ids.
`InstantRuntimeConfiguration` now carries Instant-compatible `apiURI` and
`websocketURI` values, and endpoint helpers such as
`instant-swift-data auth oauth-url <client-name> <redirect-url> --json` and
`instant-swift-data auth issuer --json` prove the configured URL shape
non-captively.
Transport-backed token verification, token refresh, and server auth
invalidation remain future work, but the Swift dependency slots are in place.

### Presence, Rooms, Topics

- Join and leave rooms.
- Publish presence and subscribe to presence slices.
- Get current presence.
- Publish topics and subscribe to topic events.
- Typed room schema generation from Swift schema declarations.
- Rejoin rooms after reconnect.

Current local progress: `InstantRuntime` persists room presence and topic
messages in SQLite, scopes them by app id, resolves users through the durable
auth session or an explicit user id, exposes local snapshot subscriptions with
termination cleanup, and provides non-captive CLI commands:
presence set/list/watch/leave and topic publish/list/watch, including
`instant-swift-data rooms presence watch chat lobby --events 1 --jsonl` and
`instant-swift-data rooms topics watch chat lobby sendEmoji --events 1 --jsonl`.
The TypeScript runner validates the Swift-authored local room evidence with
`--swift-local-integrations-contract`; transport-backed subscriptions and
reconnect rejoin remain future work.

### Storage And Files

- Upload files, delete files, and query `$files`.
- Storage operation state: idle/loading/success/error plus progress where
  available.
- File permissions generation for `$files`.
- Storage references that can be embedded in app entities.
- Entity observation and mutation delivery stay independent from media byte
  transfer. A failed media item cannot block graph synchronization.
- Move media caching toward explicit item/byte bounds and LIFO preference for
  the newest eligible item, with oldest-eligible eviction and per-item retry or
  rejection isolation.

Current local progress: `InstantRuntime` can copy a local file into the CLI
cache directory, persist `InstantStoredFile` metadata in SQLite scoped by app id,
list local files, read copied contents, delete the stored content and metadata,
emit finite local upload progress states, and observe local file metadata
snapshots with termination cleanup. The CLI exposes file
upload/upload-progress/list/read/watch/delete command families, including
`instant-swift-data files upload-progress ./photo.jpg --content-type image/jpeg --jsonl`
and
`instant-swift-data files read <file-id> --json`, plus
`instant-swift-data files watch --events 1 --jsonl`, for durable terminal proof. Real
Instant `$files` sync, progress reporting, remote delete, and permissions remain
future work.

### Streams

- Support Instant's stream abstractions exposed through the TypeScript core:
  readable streams, writable streams, stream ids, resumable stream package, and
  React Native stream shims.
- Validate Swift writes observed by a TypeScript stream reader and TypeScript
  stream writes observed by Swift.
- Define backpressure and cancellation behavior explicitly before implementation.

Current local progress: `InstantRuntime` can append ordered JSON chunks to a
local stream, persist them in SQLite scoped by app id and stream id, and read
them in order. Local reads and snapshot observations accept an `afterIndex`
chunk cursor so CLI and `@StreamChunks` clients can resume after a previously
emitted local chunk index. The CLI exposes stream append/read/watch command
families, including
`instant-swift-data streams watch chat/lobby --after-index 0 --events 1 --jsonl`,
for durable terminal proof. `InstantRuntime` also persists local byte-offset
streams with generated stream ids by unique client id, UTF-8 byte offset
validation, `$streams`-style `clientID`/`done`/`size`/`abortReason` metadata,
read-by-stream-id and read-by-client-id, unbounded local content observations,
and CLI commands such as
`instant-swift-data streams append-content <stream-id> --content 'Hi ' --offset 0`
and `instant-swift-data streams read-content --client-id chat-session --byte-offset 3`.
Real Instant stream transport, reconnect behavior, transport backpressure,
transport-backed subscriptions, and Swift/TypeScript boundary proof remain
future work.

### Admin And Tooling

- Ephemeral app creation for tests.
- Schema and permission push/pull.
- Admin query and transact helpers for ground-truth verification.
- CLI commands for schema generation, migration planning, push, get,
  validation, example business commands, cache inspection, outbox inspection,
  auth, and benchmarks.
- Dev logging hooks should be optional and removable from production targets.

Current local progress: schema and permissions generation can emit structured
local evidence with `instant-swift-data schema generate --example todos --to
instant.schema.ts --json` and `instant-swift-data perms generate --example todos
--to instant.perms.ts --jsonl`. The `validation` example now uses the Swift-owned
`InstantSchemaExamples.validationDocument` and
`InstantSchemaExamples.validationPermissions` fixtures to generate and verify
`validation/fixtures/instant.schema.ts` and `validation/fixtures/instant.perms.ts`
from the CLI. Local validation can emit JSONL evidence for
todos/offline behavior with `instant-swift-data validation local-todos --jsonl`
and for auth, rooms, files, streams, and shares with
`instant-swift-data validation local-integrations --jsonl`. The local Reminders
port now emits terminal JSONL evidence with
`instant-swift-data validation reminders --jsonl`, covering search, tags, rich
fields, smart-list stats, list sharing roles, permission rejections, writer
updates, and relaunch persistence. Public adapter wrappers can be proven from
the terminal with `instant-swift-data validation platform-adapters --jsonl`,
including `@FetchAll` dynamic reload, nil-query, cached-prior-error, and
cancellation cleanup evidence, optional `@FetchOne` dynamic and nil-query
reload evidence, `@Fetch` request dynamic reload, nil request reset, and
cancellation cleanup evidence, live wrapper dynamic replacement/cancellation
evidence, topic/file/stream/share wrapper cancellation cleanup,
`@ConnectionStatus` streaming state changes, plus `@FetchAll`/`@Fetch` filtered
active-row reloads. Server-applied
transaction loopback can be proven with
`instant-swift-data validation server-transaction-loopback --jsonl`, covering
observer publication, checkpoint persistence, relaunch restore, and unchanged
optimistic outbox state. The SyncUps recording/dependency flow,
including meeting restore after relaunch, can be proven with
`instant-swift-data validation syncups-recording --jsonl`.
`validation/run-e2e.sh` now records the Swift local todo, local integration,
server transaction loopback, CloudKitDemo, live session protocol smoke,
Reminders, typed draft, platform adapter, SyncUps recording, detailed parity
report, and compact coverage summary evidence
streams, Swift schema/perms fixture generation and verification artifacts, the
Swift benchmark evidence, the TypeScript fixture check, Swift outbox payloads
consumed by TypeScript, Swift live-session protocol evidence consumed by
TypeScript, and TypeScript-authored server transaction operation tuples consumed
by Swift through the local server transaction loopback. In required remote mode
the TypeScript boundary runner now opens Instant's admin SSE subscription
endpoint, writes through admin transact, observes refresh, and confirms the row
with admin query against a credentialed app. The explicit
`--boundary-swift-live-observe` mode seeds the `todos` attrs through admin HTTP,
opens TypeScript-side admin SSE, runs Swift's live WebSocket transaction command,
and requires TypeScript to observe the Swift-authored row. The companion
`--boundary-typescript-live-observe` mode opens Swift's live WebSocket observer,
writes a unique todo through TypeScript admin HTTP, and requires Swift to
observe the external refresh and decode it from the temporary Swift runtime
cache. When those opt-in modes produce
`typescript-swift-boundary.jsonl` and `swift-typescript-boundary.jsonl` for a
non-local app id, the coverage gate can consume the artifacts through
`INSTANT_SWIFT_DATA_COVERAGE_ARTIFACTS_DIR` or
`INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR` and promote both live-transport
records from blocked to adapted; `validation/run-e2e.sh` now archives that
post-boundary gate as `swift-coverage-final.jsonl`. The Swift runtime now has
`InstantRuntime.applyLiveRefresh(_:)` to translate live `refresh-ok`
`instaql-result` join rows into local store transactions, map server attribute
ids back onto declared Swift schema identities, publish query observers, advance
the processed transaction checkpoint, and confirm a matching optimistic outbox
mutation once the server refresh has been applied, while replaying remaining
local outbox writes so newer optimistic edits stay visible. The live observe
validation path uses that API for TypeScript-to-Swift boundary evidence rather
than stopping at the raw WebSocket payload.

Current local progress: the CLI exposes non-captive local admin helpers:
`instant-swift-data admin transact <namespace> <entity-id> --merge '{...}' [--transaction-id id]`
infers scalar/json attributes for the namespace, writes through the same
runtime/outbox/cache path as examples, supports deterministic fixed transaction
IDs for replay/de-duplication proof, and `instant-swift-data admin query
<namespace>` reads the durable local snapshots back across process launches.
It also exposes local cache detail commands, `instant-swift-data cache
attributes [namespace]` and `instant-swift-data cache triples [namespace]`, so
agents can inspect persisted schema attributes and triple facts directly. Durable
local IDs are inspectable with `instant-swift-data local-id get <name>` and
`instant-swift-data local-id list`. The `swift-parsing` CLI grammar now covers
top-level command/output normalization with combinator-driven token parsing,
typed todos, auth recipe, app-builder, chat, microblog, mobile-chat,
todo-links, reactions, typing-indicator, avatar-stack, cursors, custom-cursors,
merge-tile-game, Stroopwafel, SyncUps, Reminders, and CloudKitDemo/counters
example leaf dispatch without executable reparsing, init scaffolding,
schema/perms generate/verify, malformed no-bootstrap coverage for chat,
microblog, mobile-chat, reactions, typing-indicator, avatar-stack, cursors,
custom-cursors, merge-tile-game, Stroopwafel, SyncUps, and Reminders, auth
show/guest/token/id-token/OAuth/OAuth URL/issuer/magic-code/watch/sign-out,
admin query/transact, app show/select/ephemeral,
cache inspect/attributes/triples, connection status/connect/close, local-id get/list,
outbox inspect/transport/flush/confirm/fail/retry/drain, query todos,
sync inspect/mark-processed, room presence/topics, benchmark options,
validation local-todos/local-integrations, file upload/upload-progress/list/watch/read/delete,
stream append/read/watch, and share create/list/accept/role/revoke commands with parser-level
tests. Remote TypeScript admin query/transact/SSE smoke is available for an
existing app through `validation/run-e2e.sh` required remote mode, and
`INSTANT_SWIFT_DATA_RUN_LIVE_BOUNDARY=1` adds the Swift WebSocket write observed
by TypeScript admin SSE proof, while
`INSTANT_SWIFT_DATA_RUN_TYPESCRIPT_LIVE_BOUNDARY=1` adds the TypeScript admin
HTTP write observed by Swift WebSocket proof. Ephemeral app creation and schema
push/pull remain future work.
The e2e harness resolves the TypeScript fixture runner through
`INSTANT_SWIFT_DATA_NODE`, PATH, or the bundled Codex Node runtime, so launchd
and other sparse environments can keep emitting TypeScript fixture evidence
instead of silently skipping that side.

### Sharing

- Instant-native sharing that reproduces SQLiteData/CloudKit-style shared record
  user experience without depending on CloudKit.
- Share/root entities, memberships, roles/capabilities, share links or tokens,
  accept/revoke flows, visible sharing metadata, and generated permissions using
  `auth.ref` and `data.ref` where applicable.
- The Reminders port must prove list sharing with two users.

Current local progress: `InstantRuntime` persists local share root metadata,
owner/member rows, share tokens, accept, list, role update, revoke, and
runtime-local, user-scoped share observation flows in SQLite scoped by app id.
The public client exposes these operations and `@Shares` adapts observations
into the Swift wrapper/task/subscription surface. The CLI exposes
`instant-swift-data shares create/list/accept/role/revoke` for durable two-user
terminal proof. Local transactions now reject reader and non-member writes to
active shared roots before cache/outbox persistence, including namespace-less
delete fallbacks, and reader attempts to mint duplicate owner shares for an
already shared root are rejected. The local guard also covers
same-transaction-id replays, declared ref targets, unresolved source lookups
with shared ref targets, cascade-expanded delete targets, unresolved
primary-key lookup ref targets, and undeclared namespace-prefixed attributes.
Owners can now promote/demote accepted non-owner members between reader and
writer roles with `instant-swift-data shares role`, and writer access is
enforced through the same shared-root transaction guard
without granting share ownership or duplicate-share creation.
The CloudKitDemo counter concept now has a local Instant CLI surface:
`instant-swift-data examples counters add/list/increment/decrement/delete`
and the `examples cloudkit-demo` alias expose count mutations plus visible
share metadata, current-user role, member count, reader rejection, and writer
promotion proof. `instant-swift-data validation cloudkit-demo --jsonl` records
that same owner/invitee lifecycle as terminal evidence, including reader
rejection without outbox mutation, writer update, and relaunch persistence.
Real Instant sharing entities and generated permissions now run on an ephemeral
app, and the Swift/TypeScript boundary proves reader visibility, rejected
optimistic write reconciliation, writer mutation, outsider isolation, and
owner-only deletion. Reminders UI sharing and the Swift writer path remain
future work.

## Proposed Package Architecture

One repository, multiple targets:

- `InstantSwiftData`: public SwiftData-like API. Property wrappers, dependency
  bootstrap, query/mutation surface, errors, and docs.
- `InstantSwiftDataCore`: internal client engine. Reactor, transport, local store,
  outbox, query processor, persistence, auth, storage, presence, streams.
- `InstantSwiftDataSchema`: Swift schema declaration DSL, IR, TypeScript printer,
  Swift code generator, permissions printer.
- `InstantSwiftDataMacros`: macro implementations such as `@InstantEntity` plus
  generated `Entity.Draft` types and diagnostics for redundant namespace
  overrides.
- `InstantSwiftDataCLI`: typed command grammar and reusable command
  implementation backed by Point-Free `swift-parsing`; the executable target
  should be a thin wrapper around this target.
- `instant-swift-data`: agent-interactable CLI executable for schema generation,
  validation, auth, example commands, cache/outbox inspection, fixture app
  creation, parity scripts, and benchmarks.
- `InstantSwiftDataTesting`: ephemeral app helpers, generated draft validation
  helpers, platform adapter validation helpers, and end-to-end assertion tools.
- `InstantSwiftDataBenchmarks`: benchmark executable for Swift/TypeScript
  parity measurements.

The public API should start with concrete Swift app code:

```swift
@main
struct AppMain: App {
  init() {
    prepareDependencies {
      try $0.bootstrapInstantSwiftData(appId: "...", schema: AppSchema.self)
    }
  }
}

@InstantEntity
struct Todo: Identifiable, Codable, Sendable {
  var id: InstantID<Todo>
  var title: String
  var done: Bool
  var createdAt: Date
}

@FetchAll(Todo.query.where(Todo.done == false).order(.serverCreatedAt, .descending))
var openTodos: [Todo]

try await db.transact {
  Todo.create(title: "Ship it", done: false)
}

var draft = Todo.Draft(title: "Draft it", done: false)
let createdID = try await db.save(draft)

var editDraft = Todo.Draft(existingTodo)
editDraft.title = "Ship the edit"
try await db.save(editDraft)
```

`@InstantEntity` defaults to the documented plural namespace (`Todo` ->
`todos`). A manual override remains available, but the macro should diagnose an
override that exactly matches the default plural. `@FetchAll` should look
familiar to SQLiteData users, but the engine underneath is not SQL. A query
becomes an Instant query tree, the server returns triples, and the local store
materializes Swift values from those triples.

`@InstantEntity` should generate SQLiteData-style `Draft` types for
primary-keyed entities. Draft ids are optional, new forms can omit the id,
entities may declare immutable `let id` primary keys, `Draft(existing)` supports
edit flows, and saving a nil-id draft allocates a durable Instant id through the
client/runtime rather than treating the id as a normal writable attribute.
`InstantSwiftDataClient.transact(saving:)` mirrors SQLiteData form saves that
upsert a draft, use the returned id, and write related rows inside the same
database write. Writable optional relation drafts must save and clear refs.
Manual `instantAttributes` schemas must declare explicit static
`InstantAttributePath` values for relation draft fields; missing paths should be
diagnosed rather than silently dropping draft assignments. The `typed-drafts`
validation now also saves a macro-generated draft with a writable
`@InstantRelation` ref field and verifies the generated ref metadata and
summarized pending mutation payload shape so relation form flows have terminal
JSONL evidence.

## SQLiteData Audit Notes

Audit source: `upstream/sqlite-data`, especially the Reminders, SyncUps,
CaseStudies, CloudKitDemo, `Fetch*`, `SyncEngine`, and CloudKit test suites.
These practices should inform the Instant Swift Data design without turning the
public API into SQL:

- **One bootstrap path.** SQLiteData's `bootstrapDatabase` and
  `prepareDependencies` pattern is good because previews, tests, app launches,
  and model code all consume the same injected database/sync dependencies. The
  Instant plan should expose `bootstrapInstantSwiftData` as the only production
  setup path, with explicit configuration for app id, auth/session store, local
  SQLite path, transport runtime, outbox, query cache, and preview/test stores.
- **Swift Dependencies for overridable effects.** App-facing clients that vary
  across live, preview, test, CLI, and local terminal contexts should be modeled
  as Point-Free `swift-dependencies` values. Define a Sendable interface in the
  appropriate module, expose reusable concrete instances in extensions such as
  `extension InstantMagicCodeExchange { public static let local = Self(...) }`,
  register `TestDependencyKey` and `DependencyKey` values with computed
  `testValue`, `previewValue`, and `liveValue`, and thread the resolved dependency into
  `bootstrapInstantSwiftData`/`InstantRuntimeConfiguration`. This applies first
  to magic-code, refresh-token, id-token, OAuth exchange, auth token
  invalidation, and mutation transport, and should later apply to live sync,
  file storage, and network clients.
  Current local progress: `InstantMagicCodeExchange`,
  `InstantRefreshTokenVerifier`, `InstantIDTokenExchange`,
  `InstantOAuthExchange`, `InstantAuthTokenInvalidator`, and
  `InstantMutationTransportClient` follow this shape, the public
  `InstantSwiftData` target exposes
  `DependencyValues.instantMagicCodeExchange` and
  `DependencyValues.instantRefreshTokenVerifier` and
  `DependencyValues.instantIDTokenExchange` and
  `DependencyValues.instantOAuthExchange` and
  `DependencyValues.instantAuthTokenInvalidator` and
  `DependencyValues.instantMutationTransport`, and
  `bootstrapInstantSwiftData` resolves those values before constructing the
  runtime configuration. The public dependency client also exposes durable auth
  operations directly, including guest, token, id-token, OAuth, magic-code
  send/verify, `signInWithMagicCodeResult(email:code:extraFields:)` with local
  `$users` persistence and Instant-compatible `created` flag semantics, session
  lookup, auth-state observation, and `signOut(invalidateToken:)`, plus outbox
  flush over the injected mutation transport. Future transport/auth clients
  should preserve the same Sendable value-client boundary and local
  static-instance convention.
- **Typed models above explicit migrations.** SQLiteData combines `@Table`,
  `Draft`, `@Selection`, typed expressions, and generated update helpers with
  named migrations that use strict SQL, foreign keys, indexes, FTS tables, and
  triggers. This is good because application queries are type checked while
  persisted schema history stays frozen and auditable. Instant Swift Data should
  keep typed access to triples, attributes, outbox rows, query cache rows, and
  sync metadata while requiring named migrations for every persisted shape. Its
  generated drafts should mirror StructuredQueries: emit only for primary-keyed
  entities, optionalize the primary key, exclude generated/managed fields, add
  `Draft(existing)`, and avoid `Identifiable` conformance by default.
- **Observable fetch wrappers as the app-facing contract.** SQLiteData's
  `@FetchAll`, `@FetchOne`, and `@Fetch` expose values plus loading, errors,
  animation, dynamic `load`, and cancellable `FetchSubscription` state. This is
  good because views and `@Observable` models can subscribe without hand-rolled
  observer lifetimes. Instant fetch wrappers should do the same over Instant
  query trees, cached materialized results, server subscriptions, and explicit
  cancellation. Instant Swift Data's `@LocalID` should follow the same wrapper
  conventions for local ID values: optional current value, loading/error state,
  dynamic `load`, projected task helpers, and SwiftUI bindings when available.
  `@AuthSession` should adapt Instant auth observation into the same
  value/loading/error/task/subscription shape instead of exposing raw auth
  callbacks to app features. `@RoomPresence` and `@RoomTopicMessages` should do
  the same for room presence and topic streams, including dynamic room/topic
  replacement for SwiftUI task lifetimes; platform-adapter validation now
  proves replacement cancels the stale live subscription before the new room
  writes wrapper state and proves topic-message task cancellation tears down the
  underlying observation. `@StoredFiles` and `@StreamChunks` should adapt storage
  metadata and stream chunk observations into the same
  loading/error/task/subscription shape, with cancellation cleanup proven from the
  terminal validation stream. `@Shares` should adapt user-scoped share snapshots
  into the same wrapper, projected binding, task, and cancellable subscription
  shape; local share observers are session- and runtime-scoped at subscription
  time, so auth-session or runtime-instance switches should resubscribe. Terminal
  validation now proves share wrapper task cancellation also tears down the
  underlying observation.
  Client adapters must transform subscribable/live Instant values into
  Swift-native wrappers, projected bindings, observable model state, and
  `AsyncSequence` streams rather than exposing raw subscription callbacks to app
  features.
- **Dynamic query work belongs in the engine.** SQLiteData's search examples
  debounce user input, cancel stale tasks, and reload the query key so filtering,
  sorting, FTS, and limits execute in SQLite. This is good because it avoids
  loading everything and doing repeated Swift collection work. Instant dynamic
  queries should replan local materialization and server subscriptions rather
  than treating post-filtered arrays as feature parity.
- **Writes have drafts, transactions, and reportable errors.** SQLiteData uses
  `Draft` values for forms, `database.write` for mutation boundaries, and
  `withErrorReporting` around user actions. This is good because edit state,
  persisted state, transaction scope, and error surfacing stay separate. Instant
  mutations should use typed drafts or builders, an explicit optimistic
  transaction boundary, durable outbox writes, rollback/failure state, and
  actionable error values. Draft saves must support both new unsaved drafts and
  drafts initialized from existing entities without weakening strict create or
  update-existing checks.
- **Examples are architecture tests.** Reminders and SyncUps keep side effects in
  `@Observable` models with `@ObservationIgnored` dependencies, preview seeds,
  injected clients, and tested model behavior. This is good because real app
  workflows exercise persistence, navigation, search, sharing, media/speech, and
  sync without burying the behavior in SwiftUI `body`. Instant example ports
  should preserve that model-first structure and include CLI access to the same
  core behavior.
- **Sync and sharing are proved with stateful tests.** SQLiteData's CloudKit
  tests use mock private/shared databases, snapshots, relaunch scenarios,
  permission rejection tests, metadata checks, root-record restrictions, and
  sync-engine lifecycle assertions. This is good because collaboration bugs live
  in durable state transitions, not in view code. Instant Swift Data should add
  both deterministic local tests and real Instant validation for memberships,
  roles, share links/tokens, accept/revoke, permissions, reconnect, and relaunch.
- **Cancellable async ownership is part of the API.** SQLiteData fetch
  subscriptions and dependency clients clean up observations and streams on task
  cancellation. This is good because live data, speech/audio, sync, and storage
  work cannot leak past the feature that started it. Instant runtime tasks need
  clear owners and cancellation handles for live queries, presence, topics,
  storage progress, streams, transport reconnect loops, and outbox drains.

## Swift Concurrency Contract

The implementation must follow `docs/swift-concurrency-guidance.md`. Concurrency
correctness is part of the acceptance contract, not cleanup work after features
exist.

Build and toolchain requirements:

- Keep Swift 6 language mode enabled.
- Keep complete strict concurrency enabled in CI.
- Enable upcoming concurrency checks as the supported toolchain allows:
  strict concurrency, region-based isolation, dynamic actor isolation,
  `nonisolated(nonsending)` by default, Sendable inference from captures, and
  isolated conformance inference.
- Do not add `@preconcurrency`, `@unchecked Sendable`, or global actor
  annotations merely to silence diagnostics. Each use needs a local explanation
  of the invariant that makes it correct.

Actor ownership rules:

- Use coarse actors for state ownership: store/triple indexes, outbox,
  persistence, transport/runtime, and delivery/observation where needed.
- Do not make every entity, query, or pending mutation an actor.
- Every mutable variable belongs to exactly one actor. Mutable state that can be
  written from two actors, or from actor-isolated and nonisolated code, is a
  design error.
- Actor methods must not suspend while invariants are partially updated. Split
  mutation, snapshot creation, persistence, and network I/O into explicit phases.
- Cross actor boundaries with immutable snapshots, never with references into
  another actor's mutable state.

Sendable and isolation rules:

- All values crossing actor boundaries must be `Sendable`: query plans,
  transaction steps, IDs, schema IR, errors, cache rows, outbox rows, transport
  messages, storage metadata, room/presence/topic messages, stream chunks, and
  query emissions.
- Prefer immutable structs and enums for boundary values.
- `nonisolated` is for pure, cheap helpers and protocol requirements that do not
  touch actor-owned state.
- `nonisolated(nonsending)` must be deliberate. It can keep lightweight async
  helper work caller-bound, but it must not be used when the intent is to move
  CPU-heavy work off the caller's actor.
- CPU-heavy work must use an explicit concurrent boundary, detached task, custom
  executor, or nonisolated async design that is verified not to inherit main
  actor execution.

Runtime and performance rules:

- Keep `@MainActor` out of `InstantSwiftDataCore`, `InstantSwiftDataSchema`, and
  the CLI. Main actor isolation belongs in UI adapters and examples only.
- Every long-lived task must have an owner and deterministic cancellation path.
  No fire-and-forget task may outlive the call stack without being stored and
  cancelled by its owning runtime or actor.
- Live queries, presence, topics, storage progress, and stream APIs should use
  `AsyncSequence`-shaped surfaces or equivalent observation wrappers with
  bounded buffering and explicit cancellation.
- Hot paths must batch actor crossings. Do not insert or recompute one triple at
  a time across actor boundaries.
- Synchronous SQLite or file I/O must be isolated to a persistence actor or
  custom serial executor and must not block actors responsible for query
  observation or transport responsiveness.

## Validation Suite

The validation rule is: a unit test can explain a helper, but it cannot prove
the library. Every feature must have at least one real script that moves data
through InstantDB and crosses the Swift/TypeScript boundary.

### Harness Shape

Create `validation/` with:

- `fixtures/schema.swift`: Swift source of truth for entities, links, rooms,
  topics, files, and permissions.
- `fixtures/instant.schema.ts`: generated TypeScript schema committed for diff
  review.
- `fixtures/instant.perms.ts`: generated TypeScript permissions committed for
  diff review.
- `swift-runner/`: Swift executable that can subscribe, transact, go offline,
  reconnect, upload files, publish presence/topics, and stream.
- `ts-runner/`: TypeScript executable using `@instantdb/core` and
  `@instantdb/admin`.
- `run-e2e.sh`: orchestrates a fresh ephemeral app, pushes schema/perms, runs
  both runners, collects JSONL evidence, and exits non-zero on mismatch.
- `results/`: ignored output containing per-run logs, timings, and server ids.

### End-To-End Cases

- Swift writes scalar entity; TypeScript admin observes exact fields.
- TypeScript writes scalar entity; Swift subscription observes exact fields.
- Swift creates linked graph; TypeScript nested query observes forward and
  reverse links.
- TypeScript creates multi-linked graph; Swift nested query observes all linked
  entities without duplicates.
- Swift deletes an entity; TypeScript observes removed forward and reverse links.
- TypeScript deletes an entity; Swift observers drop ghost reverse links.
- Swift writes while offline; Swift observer updates immediately; TypeScript
  sees nothing until reconnect; after reconnect TypeScript sees ordered result.
- TypeScript writes while Swift is offline; Swift emits cached result; after
  reconnect Swift observes server update.
- Restart Swift while offline with pending mutations; pending local state
  restores before reconnect and flushes once online.
- `queryOnce` succeeds online and fails offline with last-known data when cached.
- High-bandwidth scalar update stream: Swift performs repeated updates,
  TypeScript observes monotonic final state and timing budget.
- High-bandwidth linked writes: Swift writes create/link batches, TypeScript
  observes no link-before-create failures.
- TypeScript high-bandwidth writes; Swift observes without dropping final state.
- Presence: Swift joins room and publishes presence; TypeScript observes.
- Presence: TypeScript joins room and publishes presence; Swift observes.
- Topics: Swift publishes topic; TypeScript receives exactly once.
- Topics: TypeScript publishes topic; Swift receives exactly once.
- Storage: Swift uploads and links file; TypeScript queries `$files` and linked
  entity.
- Storage: TypeScript uploads or creates file record; Swift observes.
- Streams: Swift writes stream chunks; TypeScript reads in order.
- Streams: TypeScript writes stream chunks; Swift reads in order.
- Sharing: two Swift users share and accept a Reminders list; TypeScript verifies
  memberships, permissions, and visible sharing metadata.
- Sharing: local Swift readers and non-members are rejected before cache/outbox
  writes when mutating an active shared root, and readers cannot create a second
  owner share for that active root. Relationship targets, undeclared
  namespace-prefixed attributes, unresolved source lookups with shared ref
  targets, unresolved primary-key lookup ref targets, cascade-expanded delete
  targets, namespace-less deletes, and same-id pending replay are covered.
- Sharing: local owners can promote accepted members to writer, writers can
  mutate active shared roots through the normal transaction path, and demoted
  readers are rejected again before cache/outbox writes; share creation for an
  active shared root remains owner-only and non-duplicating.
- Sharing: local CloudKitDemo-style counters can be added, incremented,
  decremented, listed with visible share metadata, shared with a second user,
  rejected for reader writes, and mutated after writer promotion through
  `instant-swift-data examples counters`, the `cloudkit-demo` alias, and
  `instant-swift-data validation cloudkit-demo --jsonl`.
- Reminders: the first local Reminders port slice exposes durable
  `examples reminders add-list`, `add`, `update`, `complete`, and
  `list --refresh` commands over `remindersLists`/`reminders` namespaces; reminder
  child mutations include the list ref so shared-list reader/writer roles are
  enforced before cache/outbox writes.
- Reminders: local tags and LIKE-backed search now cover the next Reminders
  slice with `examples reminders add-tag`, `remove-tag`, `tags --jsonl`, and
  `search "text" [--tag tag] [--include-completed]`. Tags are modeled as Instant
  entities with a many-ref `reminders/tags` relation, and JSON/JSONL output
  derives visible reminder-tag rows. A runtime-backed `SearchRemindersModel`
  now ports the upstream basics/show-completed/delete-completed tests with
  highlighted titles, tag suggestions, tag-token search, tab-created near
  tokens, aged completed deletion, and loading/error state that keeps previous
  rows visible on load failure. The runnable SwiftUI app now exposes live
  substring and exact-tag search; exact SQLite FTS ranking/snippet presentation
  remains an intentional reference difference.
- Reminders: local delete workflows now cover
  `examples reminders delete <reminder-id>`,
  `delete-completed [--list-id id]`, and `delete-list <list-id>`. Reminder
  deletes carry the parent list ref for shared-root guards, completed deletes
  batch the same protected operation, and list deletes exercise cascade cleanup
  through the existing `reminders/list` link metadata.
- Reminders: rich local reminder fields now cover optional `dueDate`, optional
  `priority`, notes, and flagged state through `examples reminders add`/`update`
  flags, plus `list --scheduled`, `list --today`, `list --flagged`, and
  `list --priority high` filters. Scheduled/today/flagged/priority filters
  default to incomplete reminders, matching the upstream Reminders predicates.
  Priority is stored in Instant triples as the upstream integer rank while the
  CLI accepts and prints stable `low`/`medium`/`high` names. A runtime-backed
  `RemindersDetailModel` now ports upstream due-date, priority, and title
  ordering, show-completed toggling, move-to-manual position persistence, and
  smart-list/tag detail filters, plus loading/error state that keeps previous
  rows visible on load failure. The runnable SwiftUI app now exposes list and
  smart-list detail views, ordering, completion visibility, rich forms, and
  manual movement; exact FTS snippet presentation remains a reference difference.
- Reminders: local smart-list stats now expose `examples reminders stats --json`
  with all incomplete, completed, flagged, scheduled, and today counts. The
  flagged/scheduled/today counts exclude completed reminders, matching the
  upstream Reminders list model. FTS/highlighting and SwiftUI detail views
  remain future work.
- Reminders: `validation reminders --jsonl` now records the local Reminders port
  as acceptance evidence, including search/tag filtering, rich-field edits,
  search/detail model loading/error state, smart-list stats, local list-sharing
  reader rejection, writer updates,
  demotion rejection, and relaunch persistence. Rich edits now run through a
  Sendable `ReminderFormModel` that mirrors the SQLiteData ReminderForm flow for
  nil-id creates, existing edits, due-date toggles, selected tag de-duplication,
  and tag-link replacement. This is still local Instant proof; real Instant
  sharing entities, generated permissions, and Swift/TypeScript boundary proof
  remain future work.
- SyncUps: the first local SyncUps port slice exposes durable
  `examples sync-ups add`, `detail`, `edit`, `add-attendee`,
  `delete-attendee`, `record`, `record-demo`, `delete-meeting`, `list`, and
  `delete` commands over `syncUps`/`attendees`/`meetings` namespaces; attendee
  and meeting children cascade with their parent sync-up, deleting the final
  attendee creates a blank replacement attendee to match the upstream form
  model, and shared-root role checks cover child writes before cache/outbox
  persistence. `SyncUpSpeechClient`, `SyncUpSoundEffectClient`, and
  `SyncUpOpenSettingsClient` are Sendable value clients with `.local`
  instances and public `DependencyValues` keys; `record-demo` fast-forwards the
  recording model through the local speech/sound path and saves the generated
  transcript from the terminal. Full SwiftUI navigation, platform live speech,
  actual audio playback, and wall-clock meeting timers remain app-facing future
  work.
- Chat: the local Instant website-style chat port exposes durable
  `examples chat seed`, `channels`, `messages [channel-id]`,
  `post <channel-id> "message" [--author name]`, and `reset` commands over linked
  `chatChannels`/`chatMessages` namespaces. A signed-out post creates a local
  guest session, while posts after `auth token --user-id` preserve logged-in
  author attribution across CLI launches.
- Microblog: the local Instant website-style microblog port exposes durable
  `examples microblog seed`, `feed`, `profiles`, `profile [user-id]`,
  `setup-profile "Display Name" <handle>`, `post "content" [--color color]`,
  `like <post-id>`, `unlike <post-id>`, `delete-post <post-id>`, and `reset`
  commands over linked `$users`, `profiles`, `posts`, and `likes` namespaces.
  Feed queries include author profiles and reverse likes, auth-gated mutations
  preserve the current user profile across launches, and deleting users/posts
  proves the upstream cascade shape.
- Mobile chat: the local Instant mobile chat port exposes durable
  `examples mobile-chat seed`, `channels`, `profiles`, `profile [user-id]`,
  `setup-profile "Display Name"`, `send <channel-id> "message"`,
  `messages [channel-id]`, `join <channel-id>`, `presence <channel-id>`,
  `leave <channel-id>`, and `reset` commands. It preserves upstream `$users`,
  `$files`, profile/channel/message links, channel-filtered ascending message
  queries with nested `author.user`, optional author links for users without a
  profile, and `chat` room presence values while isolating local non-system
  namespaces so examples do not contaminate each other. Seed/profile/reset are
  explicit terminal conveniences because the React Native upstream app does not
  ship bootstrap data or profile-creation UI; reset clears mobile chat domains
  and presence while preserving shared auth and `$users` system state.
- Stroopwafel: the local Instant website-style multiplayer port exposes durable
  `examples stroopwafel setup-profile <handle>`, `profile [user-id]`,
  `create-room [code]`, `rooms`, `room <code>`, `join <code>`,
  `ready <code>`, `unready <code>`, `kick <code> <user-id>`,
  `start <code>`, `games`, `game <game-id>`, `tap <game-id> <color>`,
  `leave <code>`, and `reset` commands. It preserves the current
  jsventures/stroopwafel source schema at
  `7f5e2379464d932c0e4681655cbf022f8d9c2614`: `$users`, rooms, games, points,
  code-based room lookup, ready/kicked user lists, host-only kick/start checks,
  per-player point rows, game completion at 13 points, and host leave as a room
  soft-delete. The current upstream source declares `rooms: {}` and uses durable
  room membership rather than typed presence/topics, so the Swift port records
  that adaptation explicitly.
- Auth recipe: the local Instant recipe port exposes durable
  `examples auth send-code <email>`, `verify-code <email> <code>`, `status`,
  `watch --events 1`, and `sign-out` commands over the existing auth runtime. It
  preserves the upstream magic-code-only recipe scope, signed-out login state,
  signed-out code-entry state, signed-in dashboard state, and sign-out flow while
  exposing `db.useUser().email` through the durable Swift auth session's standard
  user identity fields. `send-code` carries the pending code-entry state; plain
  `status` reports persisted auth/dashboard state.
- App-builder: the local Instant website-style port exposes durable
  `examples app-builder generate <prompt> [--org-id org]`, `list`,
  `show <build-id>`, `append <build-id>`, `finish <build-id>`, and `reset`
  commands. It preserves the app-builder schema shape from
  `Galaxies-dev/app-builder@e67200cc70e01d88bd9a5382cf0380f4882fb8c7`
  (`$files`, `$users.email`, `builds.instantAppId/code/reasoning/slug/error/isPreviewable/title`,
  generated `builds.file`, and required `builds.owner`), requires an email
  magic-code session like the upstream `RefreshToken`-verified generator route,
  creates local platform apps through `InstantPlatformAppClient.local`, streams
  deterministic reasoning/code through `AppBuilderCodeGeneratorClient.local`,
  uploads the generated `App.tsx` into local `$files` storage, links it from
  the build, lists only the signed-in owner's builds, and keeps detail lookup
  id-only like `/build/:buildId`.
- Reactions recipe: the local Instant recipe port exposes durable
  `examples reactions tap <fire|wave|confetti|heart>`, `list [--limit n]`, and
  `watch --events 1` commands over the existing room-topic runtime. It preserves
  the upstream `topics-example/123` room, `emoji` topic, four reaction names, and
  `{name, directionAngle, rotationAngle}` payload shape while adapting live peer
  broadcasts into local persistent topic evidence for non-captive terminal use.
- Typing indicator recipe: the local Instant recipe port exposes durable
  `examples typing-indicator join <user-id>`, `type <user-id>`,
  `stop <user-id>`, `list [--viewer-user-id id]`,
  `watch --events 1 [--viewer-user-id id]`, and `leave <user-id>` commands over
  the existing room-presence runtime. It preserves the upstream
  `typing-indicator-example/1234` room, optional `id` presence value, and
  `chat-input` activity key while deriving active typers from presence values
  where `chat-input` is `true`; supplying a viewer id gives the upstream hook's
  peer-only view.
- Avatar stack recipe: the local Instant recipe port exposes durable
  `examples avatar-stack join <user-id> [--name name]`,
  `list [--viewer-user-id id]`, `watch --events 1 [--viewer-user-id id]`, and
  `leave <user-id>` commands over the existing room-presence runtime. It
  preserves the upstream `avatars-example/avatars-example-1234` room and `name`
  presence payload, derives omitted names from the first six user-id characters,
  and splits current user from peers when a viewer id is supplied.
- Cursors recipes: the local Instant recipe ports expose durable
  `examples cursors move <user-id> --x n --y n --x-percent n --y-percent n`,
  `list [--viewer-user-id id]`, `watch --events 1 [--viewer-user-id id]`,
  `clear <user-id>`, and `leave <user-id>` commands, plus the same
  `examples custom-cursors` surface with optional `--name name`. They preserve
  the upstream `cursors-example/123` and `cursors-example/124` rooms, default
  cursor-space keys, `{x, y, xPercent, yPercent, color}` cursor payloads, and
  custom cursor `name` presence while adapting peer-only cursor rendering into
  durable terminal evidence.
- Merge tile game recipe: the local Instant recipe port exposes durable
  `examples merge-tile-game board`, `join <user-id> [--color color]`,
  `tap <user-id> <row> <column>`, `watch --events 1 [--viewer-user-id id]`,
  `reset`, and `leave <user-id>` commands. It preserves the upstream fixed board
  id, 4x4 empty state, `tile-game-example/_defaultRoomId` presence room, and
  six-color palette; taps use a single-cell deep merge while reset replaces the
  full board state. For deterministic terminal evidence, omitted colors use the
  first available palette color rather than the browser recipe's random
  available-color selection.
- CLI: `instant-swift-data examples todos add "do the dishes"` persists auth,
  local IDs, cache, and outbox state for a later CLI invocation.
- Permissions: generated permissions reject an unauthorized write in both
  Swift and TypeScript paths.
- Concurrency: concurrent Swift `transact` calls preserve deterministic outbox
  order and deterministic final store state.
- Concurrency: transport updates racing with local optimistic writes produce the
  same materialized query results across repeated runs.
- Concurrency: cancelling live query, presence, topic, stream, and storage
  subscriptions unregisters observers and releases continuations.
- Concurrency: no core API requires `@MainActor`; UI examples may adapt core
  emissions onto the main actor.

### Performance Gates

Record numbers as JSON, not prose:

- Subscription initial load latency.
- Swift -> TypeScript write observation latency.
- TypeScript -> Swift write observation latency.
- Offline outbox enqueue latency.
- Reconnect flush throughput and p95 time-to-visible.
- High-bandwidth update throughput for scalar and linked writes.
- Memory growth during 1k, 10k, and 50k triple workloads.
- Swift/TypeScript benchmark comparison result and quantified gap when Swift is
  slower.
- Actor-hop counts or equivalent instrumentation for triple insert,
  materialization, reconnect drain, and outbox flush hot paths.
- Cancellation latency for live query, presence/topic, storage progress, and
  stream subscriptions.

Current local progress: `instant-swift-data benchmark --suite local-todos`
emits JSON/JSONL metrics for local bootstrap, triple insert/retract, todo query
materialization, pending mutation enqueue, query-cache reads, offline SQLite
restore, high-bandwidth scalar update streams, and high-bandwidth linked write
batches, storage metadata queries, stream read/write throughput, and live-query
cancellation latency. Local presence, topic, storage, and stream subscriptions
also carry cancellation latency metrics. High-bandwidth scalar and linked
samples carry resident-memory high-water growth and budget fields, 1k/10k/50k
triple workload samples carry explicit memory budgets, and local
transact/query/cache/relaunch/outbox-flush samples carry actor-hop breakdowns.
Swift/TypeScript comparison and live transport actor-hop counts remain future
benchmark work. `validation/run-e2e.sh` records the local Swift validation
streams and a one-iteration `local-todos` benchmark artifact by default, with
`INSTANT_SWIFT_DATA_VALIDATION_BENCHMARK_ITERATIONS` available for longer local
validation runs.

Initial budgets can be loose until the implementation exists, but the suite
must emit the same metrics on day one so regressions become visible.

## Implementation Packets

1. Repository scaffold: `InstantSwiftData` package targets, macro and benchmark
   placeholders, docs, validation directories, and Swift 6 strict concurrency
   settings.
2. Schema IR and macros: import the best pieces from `InstantSchemaCodegen` and
   `InstantDBMacros`; make Swift -> TypeScript generation the primary path;
   generate `Entity.Draft` types for primary-keyed entities; add Point-Free
   MacroTesting coverage for generated code, draft expansion, and diagnostics.
3. Concurrency foundation: apply `docs/swift-concurrency-guidance.md`; define
   actor ownership for store, outbox, persistence, transport/runtime, and
   observation; define Sendable boundary types; add strict-concurrency CI.
4. Bootstrap and persistence foundation: implement `bootstrapInstantSwiftData`
   through `prepareDependencies`; provision context-aware live, preview, test,
   and CLI stores; register Swift Dependencies values for magic-code exchange
   and future auth/transport seams, using reusable local static instances such
   as `InstantMagicCodeExchange.local`; create named SQLite migrations for
   attributes, triples, query cache, sync metadata, local IDs, auth/session, and
   outbox tables.
5. Core local store: port triple store, attrs store, query materialization,
   observer invalidation, and reverse-link cleanup into `InstantSwiftDataCore`;
   persist through SQLite first; batch store mutation and query emissions across
   actor boundaries.
6. Transport and auth: merge `InstantClient`, connection messages, auth manager,
   and session persistence into the core target behind Sendable Swift
   Dependencies clients whose local/test implementations remain usable without
   real Instant credentials.
7. Agent CLI foundation: auth, selected app, SQLite cache, local IDs, query cache,
   sync metadata, and pending outbox persisted across invocations; move command
   parsing into a `swift-parsing` parser-printer grammar with parser-level tests
   while preserving global `--json`/`--jsonl` compatibility.
8. Mutation outbox: draft/builder write APIs, explicit optimistic transaction
   boundary, durable pending mutations, confirmation cleanup, rollback/error
   surfacing, ordered flush, and `save(_ draft:)` helpers that allocate ids for
   nil-id drafts through the client/runtime.
9. Query surface: `@FetchAll`, `@InfiniteQuery`, `@FetchOne`, `@Fetch`,
   `queryOnce`, pagination, infinite query, nested linked queries, dynamic
   query changes, loading/error state, animation hooks, projected bindings,
   observable-model adapters, stale pending load/subscription protection, and
   cancellable `AsyncSequence` subscription handles.
10. Realtime linked entities: multi-link resolution, field filters, different
    `with` clauses, and reverse observer propagation.
11. Offline: cached subscription emission, strict offline `queryOnce`, restart
    restore, reconnect flush.
12. Storage, auth public API, presence, topics, rooms, and streams with explicit
    async ownership and cancellation handles; the local rooms foundation should
    graduate from durable CLI state to transport-backed subscriptions without
    changing the persisted command surface.
13. Sharing model: Instant-native share entities, memberships, generated
    permissions, accept/revoke flows, visible sharing metadata,
    relaunch/reconnect proof, Reminders list sharing proof, CloudKitDemo concept
    port, and remote read-only rejection proof.
14. Example ports: Instant website examples, Instant recipes, SQLiteData
    CaseStudies, Reminders, SyncUps, and CloudKitDemo concepts; keep business
    logic in observable models with injected dependencies and preview/test seeds.
15. TypeScript test parity: port or classify Instant TypeScript core and client
    adapter tests with exact source-file/test-name provenance; adapter ports
    must exercise Swift-native wrappers, bindings, observable models, and async
    streams rather than raw subscriptions.
16. SQLiteData-style local test suite: faithfully port core and example tests for
    dynamic fetches, wrapper state, fetch subscription lifecycle, generated
    drafts, migrations, write errors, Reminders, SyncUps, CloudKitDemo-style
    sharing rules, relaunch, and cancellation alongside real Instant validation.
17. Performance pass: benchmark target, Swift/TypeScript comparison scripts,
    batch write path, query recomputation profiling, local persistence hot path,
    memory pressure, actor-hop counts, and cancellation latency.

## Non-Goals For The First Cut

- Do not preserve `@Shared(.instantSync(...))` as the primary public API.
  A compatibility adapter can come later.
- Do not maintain `instant-ios-sdk` as a separate repository dependency.
- Do not treat mock-only unit tests as acceptance proof.
- Do not manually edit generated TypeScript schema/perms except to debug the
  generator.

## Remaining Open Questions

- How much of Instant streams is stable public API versus internal support for
  React Native/resumable stream packages?
- Which Swift SQLite layer should own persistence first: GRDB,
  StructuredQueries/SQLiteData pieces, or a narrower SQLite adapter inside
  `InstantSwiftDataCore`?

## First Acceptance Contract

- WHEN a schema is declared in Swift, THE CLI SHALL generate
  `instant.schema.ts`, `instant.perms.ts`, Swift entity helpers, and a validation
  fixture app without manual edits.
- WHEN Swift writes an entity, THE TypeScript runner SHALL observe the entity
  through InstantDB and verify fields from a server read.
- WHEN TypeScript writes an entity, THE Swift runner SHALL observe the entity
  through InstantDB and verify fields from a live subscription.
- WHEN Swift writes offline, THE Swift observer SHALL update immediately, THE
  TypeScript runner SHALL not observe the write before reconnect, and THE
  TypeScript runner SHALL observe it after reconnect.
- WHEN high-bandwidth writes run, THE suite SHALL record throughput, p95
  latency, dropped-update count, final-state correctness, and memory use.
- WHEN the CLI runs `instant-swift-data examples todos add "do the dishes"`,
  THE next CLI invocation SHALL observe the same durable auth/cache/outbox world.
- WHEN CLI commands are parsed, THE grammar SHALL be expressed through
  `swift-parsing` parser-printers with tests proving top-level aliases, required
  values, unknown-command failures, and global `--json`/`--jsonl` compatibility.
- WHEN malformed CLI command leaves are rejected, THE CLI SHALL report status 64
  before bootstrapping local state or creating persistent files.
- WHEN an `@InstantEntity` has a primary key, THE macro SHALL generate a draft
  type that supports new nil-id drafts, `Draft(existing)` edit flows, writable
  assignments only, and client-side id allocation on save.
- WHEN upstream Instant or SQLiteData behavior has an equivalent Swift surface,
  THE test suite SHALL record the source file/test name and prove the behavior
  through core APIs or platform-idiomatic adapters as appropriate.
- WHEN the package builds in CI, THE core targets SHALL compile under Swift 6
  strict concurrency with no accepted concurrency-warning debt.
- WHEN concurrent Swift writes, transport updates, observer cancellation, and
  reconnect drains run, THE suite SHALL prove deterministic state, deterministic
  outbox order, bounded buffering, and cancellable task ownership.
