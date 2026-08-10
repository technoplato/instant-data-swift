# Overview 01 — Schema: segments + words (historical fragment)

**Status:** SUPERSEDED by `01-schema.md` (full plain-type schema first).
Segment+words rules still hold; parent Recording fields live in `01-schema.md`.

## Entities (draft)

```text
Recording  (list / detail identity)
  id
  title?
  lifecycle: active | paused | stopped   # Q04
  createdAt / updatedAt
  segments --> [TranscriptionSegment]

TranscriptionSegment
  id
  recording --> Recording
  words: [Word] as Instant JSON string   # strict Codable
  text: String                           # DERIVED from words
  start: Time                            # DERIVED (first word.start)
  end: Time                              # DERIVED (last word.end)
  isFinal: Bool                          # open-segment finalize
  order / index?

Word  (NOT an Instant entity)
  start: Time
  end: Time
  text: String
```

## Write loop (ASCII)

```text
  rate slider ──> simulated token stream
         │
         ▼
  append/update words on open segment
         │
         ▼
  recompute text, start, end from words
         │
         ▼
  transact upsert THAT segment only
    (local materialize + durable outbox)
         │
         ▼
  peers @Fetch / observe see new words
```

## Aligns with

- ADR 0015 open-segment recipe
- Scribe `wordsJSON` + segment fields (simplified; no media/shares first)

## Open

- Persist derived `text`/`start`/`end` vs compute on read only
- Namespace / Instant attribute spelling
- Recording parent lifecycle (Q04)
