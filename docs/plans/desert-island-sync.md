# Desert-island synchronization over Apple transports

Status: loopback Recipes V3 prototype plus implementation plan. The `desert`
branch now demonstrates forced non-cloud synchronization for all eight Recipes
V3 demos through an in-process coordinator host and an actual
Network.framework loopback peer. This is not evidence of physical-device,
router/LAN, direct peer-to-peer, Bluetooth, or Watch synchronization.

Tracked feature: [Instant Tools feature 046](https://issues.knophy.com/issues/046), Instant
entity `6b831f06-e880-4ee0-839f-e75707a4241d`. In the sibling Instant Tools
repository, the typed intake CLI was implemented in
`4707a45f7be4559a2f050966a78998fa8798b154`; portable Planned-status support was
implemented in `61c54fc52f6a558c476cdfbba0ced72f24375a09`. The tracker read the
record back as Library / feature / Planned / P1 with all seven criteria and an
exactly matching lossless source document.

## Intent

Instant Data Swift should be able to synchronize ordinary entity mutations and
observations when the Instant cloud is unreachable—or deliberately excluded in
testing—even when nearby devices have only a local router, a direct Apple
peer-to-peer link, Bluetooth, or an iPhone-to-Watch link.

The library's public data APIs should stay the same. Applications continue to
own schema, query and observation lifetime, mutations, authentication, sharing,
and the decision to trust a peer. The library continues to own local
materialization, optimistic observation, the durable outbox, reconnection,
delivery, and per-item rejection isolation.

## Prototype status (July 30, 2026)

The executable slice on the `desert` branch is intentionally narrower than the
complete plan below. It enables all eight Recipes V3 demos—Todos, Cursors,
Custom Cursors, Reactions, Typing Indicator, Avatar Stack, Merge Tile Game, and
Auth—under a forced Desert route. A host client talks directly to an in-process
coordinator while an actual Network.framework TCP peer crosses the loopback
listener. Both clients use the ordinary Instant query, observation, mutation,
room, topic, presence, and auth APIs appropriate to each recipe. Forced startup
waits for the required connection and presents a blocking error instead of
silently falling back to cloud.

The strict gate is:

```sh
validation/verify-recipes-v3-desert-smoke.sh
```

It runs one parameterized two-client contract for every
`InstantRecipeV3.allCases` value and then validates exactly eight JSONL evidence
records. Missing, duplicate, unexpected, skipped, unsupported, wrong-route, or
wrong-adapter results fail nonzero. The expected host is
`network-framework-host` with transport `in-process`; the expected peer is
`network-framework-peer` with transport `network-framework`.

The Merge Tile recipe exercises its canonical exact top-level string `id`
filter with `limit(1)`. Broader filters, nested queries, pagination, offsets,
and field selection remain unsupported and fail loudly. Auth exercises guest
and local magic-code sign-in on each client, including local-code autofill in
the UI. Those auth sessions are deliberately independent; they are not
replicated or trusted identities. Cloud-backed provider auth is unavailable in
forced Desert mode.

This is same-host, same-session evidence—not yet a durable or secure nearby
database. The coordinator is memory-only, the unauthenticated adapter rejects
non-loopback binding, and unsupported query shapes fail rather than returning
an authoritative but incomplete result. Bonjour/discovery, pairing and trust,
encryption, physical-device LAN or peer-to-peer testing, Bluetooth,
WatchConnectivity, coordinator persistence, wider router/LAN support, and a
repository-wide forced-mode demo inventory remain explicit follow-up phases.

"Desert mode" means a required non-cloud replication route. It must never mean
"try nearby, then quietly use the Internet."

## Decision summary

Build three independent layers:

1. **Discovery and pairing** find and authorize a peer or coordinator.
2. **Message channels** carry framed bytes over a selected Apple transport.
3. **Replication sessions** provide Instant semantics: snapshot or catch-up,
   ordered mutations, acknowledgement, rejection, observation invalidation,
   resume, and deduplication.

Start with a local-coordinator topology, not a fully symmetric mesh. A Mac,
iPhone, or iPad can host the session authority while other devices attach as
replicas. The coordinator establishes a single transaction order and makes
reconnect and conflict behavior testable. A true mesh would additionally need
causal ordering, conflict-resolution rules, tombstone retention, membership,
and compaction; that is a later protocol, not a transport swap.

The first carrier should be Network.framework over a router or direct Apple
peer-to-peer link. Add Wi-Fi Aware for supported iPhone and iPad hardware,
WatchConnectivity as the paired-Watch gateway, and Core Bluetooth as a
low-throughput fallback. Do not make MultipeerConnectivity the new foundation:
the current Apple SDK deprecates its principal session and discovery APIs in
favor of Network.framework.

## Why a WebSocket replacement is insufficient

The upstream Instant client connection can carry JSON over WebSocket or SSE,
but its reactor still speaks a server protocol: initialization establishes
server state, queries receive server-computed triples and transaction IDs,
transactions receive canonical acknowledgements, refreshes reconcile pending
optimistic mutations, and rooms and presence are server coordinated.

Therefore, changing only the socket cannot turn two clients into peers. The
selected replication backend must either:

- speak the existing Instant server protocol as a local coordinator, or
- introduce a versioned replica protocol and adapt it to the same local store,
  outbox, observation, acknowledgement, and rejection machinery.

The local-coordinator approach is the smaller first proof because it preserves
a single authority while transport selection becomes network agnostic.

Upstream references:

- [Instant `Connection.ts`](https://github.com/instantdb/instant/blob/main/client/packages/core/src/Connection.ts)
- [Instant `Reactor.js`](https://github.com/instantdb/instant/blob/main/client/packages/core/src/Reactor.js)

## Current repository seam audit

The Phase 0 route seam is now implemented:

- `Sources/InstantSwiftDataCore/InstantSyncRoute.swift` defines the typed
  `current` and `desertRequired` policies, the selected-route descriptor, and a
  transport factory that keeps route identity separate from carrier identity.
- `DependencyValues` exposes distinct cloud and Desert transport factories.
  `bootstrapInstantSwiftData` resolves only the selected factory. A required
  Desert route with no factory throws a stable `InstantError` before persistence
  bootstrap; it does not probe or fall back to cloud.
- `InstantRuntimeConfiguration`, connection status, and diagnostics carry the
  explicit selected route, adapter, and transport instead of describing every
  active backend as a cloud WebSocket.
- `InstantDesertCoordinator` supplies the memory-only authority used by the
  prototype. `InstantNetworkDesertHost` exposes it through a loopback-only
  Network.framework listener.
- The Recipes V3 composition root validates the forced-route launch
  configuration, starts either the host or peer adapter, waits for the required
  connection, shows route/adapter status, and makes all eight recipes visible.
- The shared Recipes native shell also offers a persisted Normal/Desert setting
  for the verified Mac-host/iOS-Simulator-peer topology. A change removes the
  recipe subtree, closes the old client, stops an owned host, and only then
  publishes a new composition-root bootstrap.
- The composition root scopes the selected client through the recipe subtree.
  Automatic fetch observation, room/presence/topic helpers, topic publication,
  and auth observation/actions resolve that scoped client, while outgoing
  recipe cleanup remains attached to its original runtime.
- Interactive Normal mode retains the preexisting cloud-or-local selection.
  Interactive Desert mode uses a distinct app id and persistence path so
  switching modes does not masquerade as implemented cloud reconciliation.
  Explicit `current` or `desert-required` launch configuration remains locked
  and takes precedence over the saved setting.
- `bootstrapLocalInstantSwiftData` remains process-local cache behavior. It is
  not Desert replication.

Other application composition roots still commonly reduce configuration to an
`enablesLiveSync` Boolean and install the cloud `.live` transport. The current
all-eight gate is therefore a Recipes V3 gate, not evidence that every
repository executable supports forced Desert mode.

One helper seam remains before arbitrary app subtrees can treat SwiftUI
dependency scoping as exhaustive: declaration-driven automatic `@FetchAll`,
`@FetchOne`, and `@Fetch` observation uses the scoped client, but projected
default calls such as `$rows.load()` and `$rows.subscribe()` still resolve the
task-local dependency unless the caller uses their explicit `using:` overload.
None of the eight Recipes screens calls those projected APIs. A later
repository-wide composition pass should install the scoped client into those
operations or require the explicit overload before claiming the same behavior
for every executable.

### Implemented Phase 0 behavior

1. Route selection happens in `DependencyValues.bootstrapInstantSwiftData`
   before transport resolution.
2. Cloud and Desert factories are distinct, and the focused tests install a
   cloud trap to prove the forced lane does not instantiate it.
3. A missing required Desert factory fails immediately with a typed error.
4. The runtime receives an explicit route descriptor; Desert route and
   Network.framework/in-process carrier identities remain distinct.
5. Route, adapter, and transport are exposed in connection status and
   diagnostics.
6. The Recipes host and peer use ordinary public APIs against the selected
   backend. Cloud-backed provider auth remains unavailable in that lane.
7. The Mac and iOS Simulator Recipes apps can persistently switch the entire
   catalog between Normal and Desert at the composition root. A failed peer
   keeps the setting reachable so the user can recover to Normal without a
   cloud fallback.

The prototype coordinator speaks enough of the existing Instant server
protocol to reuse `InstantRuntimeLiveSession` and the current
query/outbox/acknowledgement machinery. If a later version introduces a new
replica protocol, the backend boundary must move below that server-specific
session, because the current session expects `init-ok`, query results,
transaction acknowledgements, rooms, presence, and stream events.

The upstream TypeScript online listener is not an isolation seam. Its initial
startup proceeds to socket creation, and later online/offline notifications
control restarts. Forced desert selection therefore belongs before transport
construction rather than in a reachability callback.

### Current demo and smoke inventory

`validation/verify-recipes-v3-desert-smoke.sh` is the strict Recipes V3 gate. It
exercises all eight `InstantRecipeV3` cases through one in-process host and one
actual loopback Network.framework peer, using ordinary public APIs. Its JSONL
records contain `recipe`, `appID`, `route`, `hostAdapter`, `peerAdapter`,
`hostTransport`, `peerTransport`, `phase`, and `ok`.

The validator requires exactly one successful record for each of:

```text
todos
cursors
custom-cursors
reactions
typing-indicator
avatar-stack
merge-tile-game
auth
```

It rejects cloud, local-cache-only, wrong-route, missing, duplicate,
unexpected, empty-phase, `skip`, `unsupported`, and `not-run` evidence. This is
stronger than compilation, but it is still same-process/loopback protocol
evidence rather than installed physical-device evidence.

The broader repository still declares executables and Xcode hosts outside
Recipes V3. A future repository-wide gate should derive SwiftPM executables
from the manifest, separately enumerate Xcode hosts from their `project.yml`
files, classify tooling products explicitly, and require every remaining
target to map to one smoke contract. Missing or unsupported targets must fail
rather than skip.

The strongest existing test homes are:

- `Tests/InstantSwiftDataTests/BootstrapTests.swift` for route selection,
  missing-backend error, and a cloud-factory trap;
- `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` for a
  deterministic coordinator/session;
- `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` and
  `MutationDeliveryTests.swift` for existing outbox, reconnect,
  acknowledgement, and rejection-isolation behavior;
- `Tests/InstantSwiftDataTestingTests/LocalTodoValidationTests.swift` for
  runner syntax, JSONL semantics, exact command order, and nonzero propagation.

## Apple capability map

| Apple API | Best role | Desert value | Important limits |
| --- | --- | --- | --- |
| Network.framework Bonjour/application service | Discovery plus a reliable local message channel | Works across a normal router/LAN; `includePeerToPeer` permits supported peer-to-peer links | Local-network privacy applies on relevant platforms; discovery is not replication authority |
| Wi-Fi Aware | Secure direct discovery and high-throughput channels | No Internet or access point is required; supports simultaneous infrastructure Wi-Fi | Current Apple support is limited to specified iPhone/iPad hardware; entitlement, service declarations, user pairing, and physical-device testing are required |
| Core Bluetooth GATT | Presence, bootstrap, control, and very small deltas | Broad low-energy fallback without a router | Small MTU, fragmentation, throttling, and background limits make it a poor bulk/media path |
| Core Bluetooth L2CAP CoC | Stream-like BLE channel after discovery | Better framed throughput than encoding all data as GATT characteristics | The app must exchange the PSM and still handle lifecycle, backpressure, and platform limitations |
| WatchConnectivity | Paired Watch-to-iPhone replication gateway | Queued background transfers and immediate messages while reachable | It is not a general peer network; reachability and payload APIs have different delivery guarantees |
| Nearby Interaction | Proximity confirmation and peer-selection UI | Can prove which nearby device the user intends to pair | It does not transport application data; discovery tokens need another channel |
| DeviceDiscoveryUI | User-mediated Apple-device pairing | Natural pairing surface for Wi-Fi Aware device-to-device flows | Pairing only; the app still owns protocol and trust decisions |
| AccessorySetupKit | Privacy-preserving accessory pairing | Useful if an Instant replica is an accessory rather than another app device | Not the general Apple-device replication layer |
| MultipeerConnectivity | Legacy/prototype compatibility adapter | Historically combines nearby discovery with sessions | Current principal APIs are deprecated in favor of Network.framework; background behavior is constrained |
| ExternalAccessory / Matter / GroupActivities | Specialized accessory, smart-home, or shared-session integrations | May support a product-specific edge adapter | None is a general transport for Instant replica state |

Primary Apple references:

- [Network parameters and `includePeerToPeer`](https://developer.apple.com/documentation/network/nwparameters)
- [Network application services](https://developer.apple.com/documentation/network/nwparameters/applicationservice)
- [Wi-Fi Aware](https://developer.apple.com/documentation/wifiaware)
- [Adopting Wi-Fi Aware](https://developer.apple.com/documentation/wifiaware/adopting-wi-fi-aware)
- [Building peer-to-peer apps with Wi-Fi Aware](https://developer.apple.com/documentation/wifiaware/building-peer-to-peer-apps)
- [Core Bluetooth](https://developer.apple.com/documentation/corebluetooth)
- [Transferring data between Bluetooth Low Energy devices](https://developer.apple.com/documentation/corebluetooth/transferring-data-between-bluetooth-low-energy-devices)
- [`CBL2CAPChannel`](https://developer.apple.com/documentation/corebluetooth/cbl2capchannel)
- [WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity)
- [Transferring data with WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)
- [Nearby Interaction](https://developer.apple.com/documentation/nearbyinteraction)
- [MultipeerConnectivity](https://developer.apple.com/documentation/multipeerconnectivity)

### Local-network privacy

Bonjour registration, browsing, and resolution require local-network access on
platforms that enforce it. Apps need an accurate local-network usage string and
must declare the Bonjour service types they browse or advertise. The runtime
must surface denial as an actionable state instead of treating it as an empty
peer list. The simulator is not sufficient evidence for this permission path.

References:

- [TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- [`NSLocalNetworkUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription)
- [`NSBonjourServices`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbonjourservices)

## Proposed library boundaries

Names below describe responsibilities, not a committed public API. They should
be fitted to the repository's existing dependency and transport seams.

### Route policy

The composition root selects a route explicitly:

```swift
enum InstantSyncRoutePolicy: Sendable {
  case cloudRequired
  case desertRequired(DesertRouteOptions)
  case automatic(preferDesert: Bool)
}
```

Only `desertRequired` is in the first slice. `automatic` should wait until the
two routes have explicit transition and reconciliation semantics.

Required behavior:

- `desertRequired` ignores Internet availability for route selection.
- It does not instantiate, probe, or fall back to a cloud WebSocket/SSE client.
- Missing discovery, channel, or replication dependencies produce a typed,
  stable startup/session error that identifies the selected policy.
- Diagnostics expose the selected route, adapter, peer/coordinator identity,
  connection phase, last acknowledged sequence, and last failure without
  exposing secrets.
- The default remains the current cloud behavior until the feature is adopted
  deliberately.

### Discovery and pairing

A discovery adapter reports candidates and state; it does not open the Instant
database by itself. A pairing result should include at least:

- stable replica and application-instance identifiers;
- protocol and schema compatibility information;
- transport capabilities and maximum frame guidance;
- a user-verifiable device label;
- authenticated key material or a handle to an app-owned trust decision.

### Message channel

The channel is a reliable framed-message abstraction with explicit limits and
lifecycle. It must not expose Network.framework, Core Bluetooth, or
WatchConnectivity types to materialization or outbox code.

The contract needs:

- connect, receive, send, and cancel;
- ordered frames or an explicit ordering layer;
- maximum frame size and fragmentation/reassembly;
- backpressure rather than unbounded buffering;
- connection generation/session identity;
- cancellation that releases the underlying task/session;
- structured close and failure reasons.

An adapter may use TCP or QUIC with Network.framework, an L2CAP channel, or a
WatchConnectivity delivery primitive. Transport-specific discovery stays next
to that adapter.

### Replication session

The first protocol should be versioned and coordinator-authoritative:

1. Replica sends protocol version, app/schema identity, replica ID, and the
   last acknowledged coordinator sequence.
2. Coordinator accepts, rejects incompatibility, or sends a snapshot/catch-up.
3. Replica submits mutations with stable mutation IDs and local order.
4. Coordinator deduplicates, validates, serializes, and returns an explicit
   acknowledgement or rejection for every mutation.
5. Coordinator broadcasts committed changes with monotonically increasing
   session sequence numbers.
6. Replica persists its watermark and resumes after link loss without losing
   or double-applying an outbox item.

Each rejected mutation or stream must be isolated. One invalid mutation cannot
block unrelated queued work. Entity replication must remain independent of
media transfer; large blobs can use a separate capability and schedule.

### Coordinator selection

The first implementation should use an explicit host chosen by the application
or pairing UI. Do not begin with automatic leader election. Explicit hosting
makes loss, replacement, and cloud-bridge policy visible to the user and keeps
the protocol deterministic.

## Forced-desert verification contract

The feature is not accepted merely because a configuration value exists. Tests
must prove route isolation while the machine reports Internet availability.

### Focused selection tests

1. Arrange both a usable cloud factory and a usable fake desert backend.
2. Select `desertRequired` while the network monitor reports online.
3. Make every invocation of the cloud factory fail the test immediately.
4. Assert that bootstrap and the first query use only the desert backend.
5. Select `desertRequired` without a desert backend and assert the exact typed
   failure; no timeout and no fallback are acceptable.
6. Assert that the default policy still takes the existing cloud route.

### Deterministic replication tests

Use an in-memory coordinator and channels before physical transports:

- two replicas receive the same initial materialization;
- a mutation is immediately optimistic on its origin;
- the coordinator acknowledges it and the second replica observes it;
- an outbox survives process/store recreation and reconnect;
- duplicate frames and duplicate mutation IDs are idempotent;
- disconnect during send resumes from the last durable acknowledgement;
- rejection rolls back or marks only the relevant item;
- concurrent submissions receive one deterministic coordinator order;
- media unavailability does not delay entity delivery.

### Carrier conformance suite

Run the same contract against every adapter:

- frame fragmentation and reassembly;
- ordering and duplicate handling;
- maximum-size rejection;
- backpressure;
- cancellation and resource release;
- peer loss, reconnect, and connection-generation changes;
- permission denial and unsupported-device errors.

### Existing tests and demos

Every existing smoke test and demo target must have an explicit forced-desert
lane. The lane may inject the deterministic in-memory coordinator until a
physical adapter is appropriate, but it must exercise the real library route
selection and public data APIs.

The Recipes V3 slice now satisfies this contract for its eight catalog entries:
the parameterized test derives cases from `InstantRecipeV3.allCases`, crosses an
actual Network.framework loopback connection for the peer, and emits strict
machine-readable evidence. Extending the same fail-loud coverage to executable
products outside Recipes V3 remains future work.

The smoke runner must:

- enumerate the existing demo/example targets rather than maintain a silently
  incomplete hand list;
- pass a stable launch argument, environment value, or test configuration that
  selects `desertRequired`;
- fail if a demo ignores the selection, touches cloud transport, reports the
  route as unsupported, or silently skips its sync flow;
- print the target, selected route, adapter, and failing phase;
- return nonzero when any target is not covered or does not work.

A UI demo should show a blocking, comprehensible configuration/permission
error. A library should return a typed error rather than deliberately crash;
the smoke harness converts that error into a loud test failure.

### Evidence ladder

Report each tier separately:

1. deterministic in-memory tests — implemented for the coordinator and route
   seam;
2. protocol tests over fault-injected channels — partially implemented;
3. adapter tests on loopback or supported simulators — implemented for a
   same-process host plus an actual Network.framework loopback peer, with
   macOS/iOS Simulator launch paths documented in
   `Examples/RecipesV3/README.md`;
4. physical devices on the same router with Internet blocked;
5. physical supported iPhone/iPad devices with no router using Wi-Fi Aware or
   an appropriate peer-to-peer Network.framework path;
6. paired Apple Watch through WatchConnectivity;
7. installed-demo UI evidence and reconnection transitions.

Compilation, fixtures, and local-only clients are not live-sync evidence.

## Delivery phases

### Phase 0 — seam and fail-loud mode

- Completed for the library route seam and all eight Recipes V3 catalog
  entries: typed `desertRequired`, distinct factories, cloud trap, typed
  missing-backend failure, route diagnostics, and a strict all-eight gate.
- Still required: extend the same explicit forced lane and fail-loud inventory
  beyond Recipes V3 to the repository's other demos and executables.

### Phase 1 — local coordinator protocol

- A memory-only prototype currently speaks enough of the existing Instant
  session protocol for the eight Recipes contracts, including entity state
  changes, presence, topics, and local auth.
- Still required: a durable/versioned coordinator, catch-up and snapshot
  semantics, coordinator restart/process-restart tests, trust, encryption, and
  explicit schema/authorization rejection policy.
- Specify schema mismatch, authorization rejection, and coordinator-loss UX.

### Phase 2 — router/LAN Network.framework adapter

- A loopback-only Network.framework TCP listener/peer prototype is implemented.
- Still required: non-loopback router/LAN binding, Bonjour application-service
  discovery, and listener/browser lifecycle.
- Local-network privacy declarations and actionable denial state.
- Physical Mac/iPhone/iPad testing with WAN blocked.

### Phase 3 — direct Apple links

- Wi-Fi Aware publisher/subscriber adapter and DeviceDiscoveryUI pairing for
  supported iPhone/iPad devices.
- Evaluate `includePeerToPeer` as a compatible Network.framework path for the
  remaining supported platform combinations.
- Core Bluetooth discovery/control plus L2CAP data-channel fallback where it
  meets the conformance contract.

### Phase 4 — Watch and product-specific gateways

- Map WatchConnectivity delivery primitives to the replication session through
  the paired iPhone.
- Add product-specific accessory adapters only when their delivery semantics
  can pass the same replication tests.

### Phase 5 — cloud reconciliation and optional mesh research

- Define how locally committed coordinator sequences are submitted when cloud
  service returns and how cloud rejections remain isolated.
- Decide whether coordinator history is authoritative only for the desert
  session or can be bridged as a batch with stable mutation identities.
- Research a true peer mesh separately; do not hide it behind the carrier API.

## Feature acceptance criteria

The loopback Recipes prototype satisfies route forcing, cloud isolation,
fail-loud bootstrap, unchanged public APIs, and the eight-recipe subset of the
smoke requirement. The remaining criteria below still govern the broader
feature; the prototype is not full feature acceptance.

- A composition root can force desert mode while Internet is available.
- Forced mode never creates or falls back to a cloud connection.
- Missing/unsupported desert dependencies fail immediately with a typed error.
- Ordinary public query, observation, and mutation APIs remain unchanged.
- A deterministic two-replica test proves optimistic mutation, persisted
  outbox, delivery, acknowledgement, reconnect, and rejection isolation.
- Discovery, message channel, and replication authority are independently
  replaceable and have conformance tests.
- Existing test suites and demos have a forced-desert smoke lane that cannot
  silently skip unsupported targets.
- Router/LAN, no-router direct link, BLE fallback, and paired-Watch evidence are
  reported as distinct capabilities rather than one generic "nearby" claim.
- Entity delivery remains independent of media transfer.
- App-owned trust, authentication, permission, and schema compatibility are
  explicit in the pairing/session contract.
- Live-sync claims name the physical devices, transport, topology, Internet
  state, test time, and observed mutation path.

## Reduced structured recovery intake

This reduced semantic payload can reconstruct the product-polymorphic feature
if the tracker is unavailable. It is not a byte-for-byte dump of the normalized
record: the live record uses typed Planned/P1 values, criterion objects with
evidence requirements, and an object-valued lossless source document.

```json
{
  "product": {
    "id": "instant-data-swift",
    "name": "Instant Data Swift",
    "kind": "library"
  },
  "issueType": "feature",
  "title": "Support forced desert-island sync over pluggable Apple transports",
  "status": "Planned",
  "priority": "P1",
  "area": "transport-and-offline-sync",
  "observed": "Instant Data Swift now exposes a forced same-host loopback prototype for Recipes V3, but it does not yet expose a durable, discovered, trusted, encrypted, non-loopback route verified between nearby physical Apple devices.",
  "expected": "Applications can require a non-cloud replication backend while retaining ordinary Instant query, observation, and mutation APIs. Discovery, message transport, and replica authority are independently replaceable, and forced mode never probes or falls back to cloud.",
  "successCriteria": [
    "Forcing desert mode while Internet is available never creates a cloud connection.",
    "A missing or unsupported desert backend fails immediately with a typed diagnostic.",
    "A deterministic two-replica test covers optimistic observation, durable outbox, acknowledgement, reconnect, deduplication, and rejection isolation.",
    "Every existing smoke test and demo has a forced-desert lane and unsupported or skipped coverage fails nonzero.",
    "Router/LAN, direct Wi-Fi Aware or peer-to-peer, Bluetooth fallback, and paired-Watch capabilities are tested and reported separately.",
    "Entity synchronization remains independent of media transfer.",
    "Installed physical-device evidence is required before claiming live nearby synchronization."
  ],
  "sourceDocument": "docs/plans/desert-island-sync.md"
}
```

## Resolved prototype decisions

- `DependencyValues.bootstrapInstantSwiftData` owns route selection without
  widening the ordinary query, observation, or mutation APIs.
- The memory-only prototype coordinator speaks the existing Instant session
  protocol rather than introducing a second replica protocol.
- Hosting is explicit. There is no discovery, automatic leader election, or
  implicit cloud bridge.

## Open decisions

- Which platforms can host versus only join a coordinator in version one?
- What exact app-owned trust artifact enters the library after pairing?
- What conflict policy applies when a desert session later reconnects to an
  independently advanced cloud database?
- What history/tombstone retention window is needed for long-offline replicas?
