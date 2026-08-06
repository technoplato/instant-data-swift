# TailnetDiagnostics

Extracted from Scribe (`Sources/InstantDBLogger`) so any Instant Swift app
(Recipes, library demos, Scribe) can dual-write structured diagnostics to the
Tailnet WebSocket collector:

`wss://laptop.tail91224c.ts.net/scribe-diagnostics` → `127.0.0.1:8767` →
`~/Library/Logs/Scribe/diagnostics.jsonl`

## Use

```swift
import InstantDBLogger

let logger = InstantDBLogger.webSocket(
  endpoint: URL(string: "wss://laptop.tail91224c.ts.net/scribe-diagnostics")!,
  context: InstantDBLogContext(subsystem: "com.example.recipes"),
  spoolURL: FileManager.default.temporaryDirectory
    .appendingPathComponent("recipes-diagnostics-outbox.jsonl")
)
logger.enqueue(level: .info, category: "auth", name: "sign-in.started", message: "…")
logger.bridgeInstantDiagnostics()
```

Do **not** ship admin tokens. Collector auth is Tailnet membership.
