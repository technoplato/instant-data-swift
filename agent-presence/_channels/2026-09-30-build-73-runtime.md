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
