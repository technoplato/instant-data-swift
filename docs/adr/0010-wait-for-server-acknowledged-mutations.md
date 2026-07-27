# ADR 0010: Wait for Server-Acknowledged Mutations

- Status: Accepted
- Date: 2026-07-27
- Scope: local-first mutation durability and short-lived live clients

## Context

`transact` commits optimistically to SQLite and starts live WebSocket delivery
without blocking the caller. That is the correct application behavior, but a
short-lived tool can exit before its final mutation reaches another client.

`flushPendingMutations` is a different boundary: it sends through the injected
`InstantMutationTransportClient`. The default dependency is the local
transport, which is useful for offline and protocol tests but confirms an
outbox mutation without a live server acknowledgement. Using it as a live
delivery wait can therefore remove a mutation before the WebSocket opens.

Reconnect delivery also removes scalar writes that are older than the current
optimistic value. When several causally ordered mutations for one new entity
are pending, removing fields from the earliest full upsert can turn it into an
invalid partial server create even though a later pending mutation would have
restored the final value.

## Decision

Add `InstantSwiftDataClient.waitForAllPendingMutations(timeout:pollInterval:)`.
The method polls the durable unconfirmed outbox, reconnects a closed live
client, surfaces an errored live connection, respects cancellation and a
bounded timeout, and returns only after the server acknowledgement path has
removed every pending mutation. It never calls `flushPendingMutations`.

Before:

```swift
while !(await client.pendingMutations()).isEmpty {
  _ = try await client.flushPendingMutations()
}
```

After:

```swift
try await client.waitForAllPendingMutations(
  timeout: .seconds(10),
  pollInterval: .milliseconds(50)
)
```

Reconnect transport preserves an older scalar write while a later queued
mutation writes the same entity and attribute. Sending the pending mutations
in creation order then preserves the authored causal transition and converges
on the later value. If no queued successor remains, the existing visible-write
filter still discards a stale scalar write so retrying it cannot overwrite a
newer locally visible value.

## Consequences

- Application writes remain immediate and local-first.
- CLI tools and explicit durability boundaries can stay alive until another
  client can observe the final mutation.
- A local mutation transport can no longer masquerade as live delivery at
  these call sites.
- Offline or persistently errored clients fail at the caller's bounded timeout
  or with the live connection error instead of reporting false success.
- Pending full upserts remain valid server creates during reconnect, while an
  isolated stale retry still omits superseded cardinality-one writes.

## Verification

Focused client tests prove the wait observes pending mutations without calling
the configured flush transport, reconnects a closed client, and times out
without confirming an unacknowledged mutation. The live transport regression
proves an older pending write remains intact while its queued successor exists,
then is filtered after that successor leaves the outbox.

An ephemeral live performance matrix writes five normalized Scribe transcript
segments through both the accelerated replay writer and the tight per-segment
writer. TypeScript and Swift observers each received all five segments. The
tight writer averaged 157 ms and 192 ms respectively; accelerated replay stayed
within the two-second budget at 1,317 ms and 846 ms.
