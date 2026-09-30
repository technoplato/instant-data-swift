# Open item: "failed" mutations that the server already applied (#296, feeds N47)

Status: open. Recorded 2026-09-30 by claude-opus-5.5-fast-drain (plan 2026-09-30-fast-drain-2).

## What happened

The Recording 023-shape backlog test ran the build-72 library (`0078484f`) on an iPhone simulator against the
throwaway Instant app `bd40c50a`:

1. 2,580 pending writes accumulated offline.
2. The app reconnected with no new recording.
3. Every connection's first query result took a 26-37 s whole-component rebase, the server closed the socket during
   it, and the app reconnected (25 connections in 10 minutes).
4. Writes offered on a connection that died unanswered were re-sent on the next one. The app's permission rules
   refused 37 of those re-sends ("Permission denied: not perms-pass?", all `refusalKind=replay`).
5. 32 outbox rows ended in `status=failed`.

## What the server holds

`check-refused.mjs` read every entity those 32 rows write from `bd40c50a`, read-only. Results are in
`server-comparison.txt`:

- 47 entity writes: 15 recordings, 14 transcriptionSegments, 13 transcriptions, 3 recordingRouteChunks,
  2 recordingAttachments.
- All 47 entities exist on the server.
- 2 hold exactly the refused values.
- 45 hold newer values from later writes the server had accepted. For example, `recordings.updatedAtMs` is
  1790772223595 on the server, against 1790772215775 to 1790772222137 in the refused writes, and the segments'
  `endTimeSeconds` is larger.

So no write was lost. Each refused row was a re-send of a write that an earlier, unanswered offer had already applied,
and that later accepted writes then superseded. The app's `validUpdate` rule refused it as stale. The device still
reports 32 failed mutations, and a "Not synced" display (N47) would show them as unsynced work.

## Also observed

- `refusalKind` knows only this process's own earlier connections: the set of unanswered offers lives in memory. A
  re-send of a write an earlier process offered is labeled `first-offer`. On Michael's phone (build 72, 2026-09-30
  10:00:41 to 10:02:29), 6 refusals were all labeled `first-offer` (3 recordings, 3 transcriptionSegments). They are
  probably the same kind of stale replay from build 69's connections, but they have not been checked against the
  server.
- Build 73's receipt patches keep what the device shows correct after such a refusal: the rollback restores the
  server's value. They do not change the status the outbox reports.

## Files

- `failed-rows.jsonl`: the 32 failed outbox rows as the simulator stored them (transaction, failure, receipt).
- `failed-writes.json`: the same writes, one entry per entity with typed values and the server's hint.
- `server-comparison.txt`: per-entity comparison with `bd40c50a`, with a summary line.
- `check-refused.mjs`: the read-only comparison. It needs `INSTANT_APP_ID` and `INSTANT_APP_ADMIN_TOKEN` for
  `bd40c50a` in the environment, and it refuses any other app.

## Next steps for N47

- Tell apart "refused, but the server holds this entity at a newer value" from "refused and not applied".
  Candidates: compare with the next query result for the entity, or treat a refused replay whose entity exists on the
  server with a newer `updatedAtMs` as superseded.
- Persist the unanswered-offer set, so a replay after an app restart is labeled `replay`.
