# 2026-08-22 native media streams

- `2026-08-22 11:25 EDT` — `gpt-5-6-pro` expanded the 100× two-hour plan with native, typed, backpressured audio/video streams.
- The existing durable stream-fragment/outbox/reconnect transport remains authoritative; no second spool or cloud-waiting ordinary write is permitted.
- Public API target: generated entity route + value-semantic descriptor builder + typed frame writer/reader + explicit remote flush.
- New release evidence: Swift-vs-TypeScript audio/video memory, CPU, throughput, encoding overhead, resume correctness, and combined transcript/media pressure on Michael's Mac.
- Plan-only until merged. Preserve all existing live-session and queue-bound owners.
