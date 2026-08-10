# Overview 01 — Schema (pointer)

**Canonical:** skill catalog — do not maintain a full fork here.

| File | Role |
| --- | --- |
| `/Users/laptop/Sync/skills/domain-as-tree/references/schemas/global.md` | `Time`, `Duration`, `Language`, `times`, … |
| `/Users/laptop/Sync/skills/domain-as-tree/references/schemas/transcription.md` | recording → transcription → segment + event |
| `/Users/laptop/Sync/skills/domain-as-tree/references/schemas/CATALOG.md` | index + schemas-vs-examples |

## Notation

`*` in trees means **zero or many** children.

## Cardinality (Q06–Q08)

```text
recording 1 ──* transcription
transcription 1 ──* segment
segment.body = speech | event     # exclusive — never both
segment 1 ──* response
response.parent = root | reply(responseId)
```

## Timeline

Homogeneous **segments** in order. **Discriminated** `body`: either **speech**
(words only) or **event** (one kind only). Never words and event on the same
row. Map segments to render. Responses on any segment.

## Status

Canonical: skill `transcription.md`. URI draft: `04-uri-tree.md` (Q09).
