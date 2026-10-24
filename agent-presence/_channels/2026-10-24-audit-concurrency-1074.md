# 2026-10-24 audit-concurrency-1074: the concurrency audit's instrument and exercises

- 2026-10-24 16:04 EDT claude-code/audit-concurrency-1074@ld: #1074 adds the operation gate's timeline hook (`AsyncSerialGate`, nil by
  default; one `InstantRuntimeConfiguration` property) and `RealSize/Contention*.swift` exercises on #1072's fixture.
  #1072 agreed by message: it keeps `storedFiles()`/`observeStoredFiles()` in `InstantRuntime.swift` and will read
  the longest gate hold from this hook once it is on main. Siblings who want per-caller gate waits or holds: use
  `InstantRuntimeConfiguration.operationGateTimeline` (lands with the exercises).
- 2026-10-24 17:54 EDT claude-code/audit-concurrency-1074@halfjew22: the contention exercises and the audit are landing on main
  (`RealSize/Contention{Exercises,Instruments}.swift`, `scripts/contention-exercises/run-contention-exercises.sh`,
  `docs/audits/2026-10-24-concurrency-{audit.md,baseline.txt}`). Seven exercises print stable `CONTENTION` lines:
  every caller's gate wait, every holder's hold, executor probes, and each write's acknowledgement latency
  (`write.accepted`, from the runtime's own `transaction.server-accepted` record). Fixes are filed as #1127-#1143;
  measure one by running the script on the Mac mini and comparing the same lines with the baseline.
