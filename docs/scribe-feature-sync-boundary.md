# Scribe Feature Synchronization Boundary Check

This is the integration contract for Scribe's architecture test. The test
itself belongs in the Scribe repository so it runs with Scribe target changes.
The canonical rationale is `docs/adr/0001-application-sync-boundary.md`.

## Scan scope

Scan normal app feature sources, including recording list, recording, playback,
attachment gallery, onboarding, and app-domain reducers/models/views.

Allow composition roots to bootstrap Instant and allow normal features to
import the public `InstantSwiftData` module for schema, `@FetchAll`,
`@FetchOne`, `@Fetch`, ordinary typed mutations, auth, and sharing.

## Reject in normal features

Reject imports or symbol references that expose synchronization mechanics:

- `InstantRuntime`, `InstantStore`, or a direct local materializer;
- `queryLocal` or another cache-only query vocabulary;
- outbox flush, drain, confirm, fail, or retry APIs;
- transport connect/reconnect or transport-level subscription
  registration/resubscription APIs;
- `RealtimeTranscriptionSyncClient` or another feature-injected synchronization
  coordinator;
- manual fetch plus subscribe plus merge coordination for one composite value.

Prefer exact imports and symbols. Do not ban `InstantSwiftData` or the bare word
`sync`; both have legitimate uses. Ordinary wrapper/subscription observation is
also allowed when the feature owns its lifetime; the forbidden case is manual
transport resubscription or multi-source synchronization coordination.

## Allow in boundary targets

Allow synchronization/runtime implementation vocabulary in:

- bootstrap and app composition code;
- live client/adapter targets;
- shared Instant persistence/support targets;
- CLI and diagnostics targets;
- validation and test-support targets;
- an explicitly user-visible delivery/status operation.

## Acceptance cases

The architecture test should prove at least one allowed and one rejected
fixture for each rule family. Its failure should name the source path, symbol,
and owning boundary so a developer knows whether to move the code into a live
adapter or replace it with an ordinary Instant API.

Run the check whenever Scribe adds a feature dependency or moves query/mutation
work between targets.
