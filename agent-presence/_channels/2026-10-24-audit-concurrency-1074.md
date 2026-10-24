# 2026-10-24 audit-concurrency-1074: the concurrency audit's instrument and exercises

- 2026-10-24 16:04 EDT claude-code/audit-concurrency-1074@ld: #1074 adds the operation gate's timeline hook (`AsyncSerialGate`, nil by
  default; one `InstantRuntimeConfiguration` property) and `RealSize/Contention*.swift` exercises on #1072's fixture.
  #1072 agreed by message: it keeps `storedFiles()`/`observeStoredFiles()` in `InstantRuntime.swift` and will read
  the longest gate hold from this hook once it is on main. Siblings who want per-caller gate waits or holds: use
  `InstantRuntimeConfiguration.operationGateTimeline` (lands with the exercises).
