# Plan 2026-11-11-first-write-2046 (library part): a validation refusal names what was missing and the write

- planId: 2026-11-11-first-write-2046
- agentId: claude-code/first-write-2046@strangelearning (tools/agent-run, Claude Opus 5.5)
- role: mower (diagnostics of an existing path; no new behavior)
- issue: #2046 (P1); the app's part is in realtime-voice's plan of the same id
- landing: worktree ~/Sync/worktrees/first-write-2046-ids (branch agent/claude/first-write-2046) from origin/main
  (v1.9.83), red then green, release v1.9.84, landed with ~/Scribe/tools/land; Scribe pins it

## Measured (2026-11-11)

A first-offer refusal of type validation-failed ("Missing required attribute `recordings/startedAtMs`: f592cdd1 ...")
reached the device log as outbox.mutation.refused-write with refusedNamespace, refusedCheck, refusedEntityIDs,
refusedAttributes and refusedValues all empty: InstantMutationRefusal reads only a permission hint (`expected`,
`input`), and a validation hint is `{"records": [{"etype", "entity_id", "label", "attr_id", "is_required"}]}`. The write
it refused (a recordingRuntimeEvents row linking to the recording) was named only by pulling the phone's store.

## Steps (no code here)

1. red: InstantMutationRefusalTests: a validation refusal's hint records name the namespace, entity and missing
   attributes; every refusal also names the namespaces the write set and the links it made (entity, label, target),
   so a link to a row the server lacks reads from the log alone.
2. green: InstantMutationRefusal reads the records hint and summarizes the refused transaction.
3. release v1.9.84 (record and progress entry), tag on the landed main, Scribe pins it.

## Touching

- Sources/InstantSwiftDataCore/InstantMutationRefusal.swift
- Tests/InstantSwiftDataCoreTests/InstantMutationRefusalTests.swift
- PROGRESS.md, docs/releases/v1.9.84.md (release record)

## Conflict check

Last claims on the refusal files: stale-writes (2026-09-30, ended). PROGRESS.md: append-only entries. No channel.
