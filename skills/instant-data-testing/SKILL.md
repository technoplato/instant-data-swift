---
name: instant-data-testing
description: Test and validate Instant Swift Data local-first, offline, optimistic, reconnect, delivery, sharing, media, and application-boundary behavior. Use when writing Swift Testing suites, porting SQLiteData or Instant tests, diagnosing cache/outbox/rejection behavior, adding architecture checks, or running local and Swift/TypeScript live acceptance gates.
---

# Instant Data Testing

Use `instant-data` and the Point-Free `pfw`, `pfw-testing`,
`pfw-custom-dump`, and `pfw-dependencies` skills first.

## Start with the failing contract

Write or tighten the smallest public-surface test before implementation. Use
Swift Testing and `expectNoDifference`/`expectDifference` for readable state
diffs. Do not link a transitive production dependency directly into its test
target.

Record upstream provenance when porting behavior: source file, test name,
Swift test, parity status, and reason for adaptation.

When the change concerns recordings, route to the current application models
and screens in `Sources/VoiceTrailV3App/` and the focused fixtures:

- `Tests/InstantSwiftDataTests/V3RecordingFixtureTests.swift`
- `Tests/InstantSwiftDataTests/V3RecordingActionFixtureTests.swift`
- `Tests/InstantSwiftDataTests/V3RecordingsListFixtureTests.swift`
- `Tests/VoiceTrailV3AppTests/`

Treat those compiling symbols as usable today and `screens/v3/` as design
targets. Recording, transcription, word, and related entities are
application-modeled `InstantEntityModel` types; do not assume a generic library
`Entity` or an unimplemented projection/fetch builder.

## Prove fetch behavior

Cover:

- static fetch auto-observation without task/load;
- explicit `@FetchAll(nil)` and `@FetchOne(nil)` starting with zero
  observations, followed by non-nil activation and nil cancellation/reset;
- cached initial emission followed by live reconciliation;
- optimistic mutation visibility before server acknowledgement;
- dynamic query/request replacement and stale cancellation;
- library-owned `@Fetch` composite combination that emits only after every
  source has emitted, without claiming an atomic cross-query snapshot;
- strict offline failure for live-client `queryOnce`, with cached context when
  supported, plus successful local-runtime reads for an explicitly injected
  local-only client;
- parity between injected local-only and live-client feature code.

Never use a public `queryLocal` to make an adapter test pass.

## Prove durable offline behavior

Test the full chronology:

1. observe the initial local value;
2. close or suspend transport;
3. mutate and observe the optimistic value immediately;
4. verify the ordered outbox persisted across relaunch;
5. reconnect and deliver in order;
6. apply server acknowledgement/refresh;
7. verify newer optimistic state was not erased;
8. verify accepted rows clear and rejected rows remain actionable.

Test each rejection independently. One bad mutation, query, stream, or media
item must not poison unrelated observation or delivery.

## Separate entity and media acceptance

Prove entity projection/delivery continues while media is offline, delayed, or
rejected. For bounded LIFO media caching, verify newest-eligible preference,
item/byte bounds, oldest-eligible eviction, relaunch retry metadata, and
per-item failure isolation.

## Enforce application architecture

Add static checks in integrating repositories that scan app and normal feature
targets for runtime/store/materializer imports, `queryLocal`, outbox
flush/drain/retry mechanics, transport/reconnect mechanics, and injected sync
coordinators. Allow bootstrap/live adapter, CLI, diagnostics, validation/test,
and explicitly user-visible sync-operation targets. Match symbols and imports;
do not ban the bare word `sync` or the public `InstantSwiftData` module. Normal
features may import it for schema, `@Fetch*`, ordinary mutations, auth, and
sharing. Ban synchronization/runtime vocabulary and manual
transport-resubscribe or fetch/subscribe/merge coordination instead. Allow an
ordinary query subscription when a non-UI feature legitimately owns its
observation lifetime.

## Layer validation

Run focused unit tests first, then the relevant package suite. For behavior that
claims synchronization, also run the repository validation script and require
real Swift/TypeScript boundary evidence when credentials are available.

Report separately:

- deterministic local test evidence;
- local protocol/mock transport evidence;
- credentialed live transport evidence;
- installed app or visible UI evidence when the claim concerns app behavior.

Do not promote a local-only or compiled fixture to a live synchronization
claim.
