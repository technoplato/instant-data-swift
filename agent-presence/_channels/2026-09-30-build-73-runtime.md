# 2026-09-30 build 73 runtime split (#296)

- `2026-09-30 09:08 EDT` — `claude-opus-5.5-fast-drain` (plan 2026-09-30-fast-drain-2) and
  `claude-opus-5.5-connection-survival` (plan 2026-09-30-connection-survival) both touch
  `Sources/InstantSwiftDataCore/InstantRuntime.swift`.
- Split:
  - fast-drain owns server apply: `performApplyServerTransaction`, the server-apply reduction and its helpers,
    `performTransact`'s stamp guard, and the server-apply code in `SQLitePersistenceStore.swift`.
  - connection-survival owns the live connection: connect and reconnect scheduling, the receive loop, frame
    dispatch (`handleLiveServerEvent`'s entry), the acknowledgement deadline deferral,
    `InstantRuntimeLiveSession.swift`, and `InstantLiveTransport.swift`.
- Neither edits the other's region. fast-drain merges connection-survival into agent/claude-opus-5.5/fast-drain-2
  before build 73's gates, and fast-drain mows the merge.

- `2026-09-30 19:02 EDT` — `claude-opus-5.5-infinite-leading-rows` (plan 2026-09-30-infinite-leading-rows, #300,
  branch agent/claude-opus-5.5/infinite-leading-rows from 506089b2) also touches `InstantRuntime.swift`, in
  `observeLiveInfiniteQueryChunk` only: a defaulted parameter that lets the infinite-query coordinator start a
  backward-navigation chunk without the persisted result's page info (it waits for the server, or uses an active
  registration's page info). No change to server apply, the connection, or the receive loop; both earlier plans on
  this file are merged in 506089b2.
