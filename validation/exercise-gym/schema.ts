/**
 * Exercise-gem schema: simple counter path + complex linked graph.
 *
 * Every mutable entity carries:
 *   - clientId: Instant local client id (getLocalId) that authored the row
 *   - descriptor: stable human/machine label for the writer process
 *   - runId: one exercise run
 *   - seq: monotonic per-entity sequence for observer validity
 */
import { i } from "@instantdb/core";

export const exerciseGemSchema = i.schema({
  entities: {
    // Simple path: flat upsert throughput / RTT
    counters: i.entity({
      runId: i.string().indexed(),
      name: i.string().indexed(),
      value: i.number().indexed(),
      seq: i.number().indexed(),
      clientId: i.string().indexed(),
      descriptor: i.string().indexed(),
      payloadBytes: i.number(),
      updatedAtMs: i.number().indexed(),
    }),

    // Complex path: document → chapters → blocks → annotations
    documents: i.entity({
      runId: i.string().indexed(),
      title: i.string().indexed(),
      seq: i.number().indexed(),
      clientId: i.string().indexed(),
      descriptor: i.string().indexed(),
      summaryJSON: i.string(),
      updatedAtMs: i.number().indexed(),
    }),
    chapters: i.entity({
      runId: i.string().indexed(),
      documentId: i.string().indexed(),
      title: i.string(),
      order: i.number().indexed(),
      seq: i.number().indexed(),
      clientId: i.string().indexed(),
      descriptor: i.string().indexed(),
      bodyJSON: i.string(),
      updatedAtMs: i.number().indexed(),
    }),
    blocks: i.entity({
      runId: i.string().indexed(),
      chapterId: i.string().indexed(),
      kind: i.string().indexed(),
      text: i.string(),
      order: i.number().indexed(),
      seq: i.number().indexed(),
      clientId: i.string().indexed(),
      descriptor: i.string().indexed(),
      metaJSON: i.string(),
      updatedAtMs: i.number().indexed(),
    }),
    annotations: i.entity({
      runId: i.string().indexed(),
      blockId: i.string().indexed(),
      note: i.string(),
      score: i.number().indexed(),
      seq: i.number().indexed(),
      clientId: i.string().indexed(),
      descriptor: i.string().indexed(),
      updatedAtMs: i.number().indexed(),
    }),

    // Durable per-write event log (app-level, for correctness reconstruction)
    writeEvents: i.entity({
      runId: i.string().indexed(),
      eventId: i.string().indexed(),
      suite: i.string().indexed(),
      side: i.string().indexed(),
      op: i.string().indexed(),
      entityKind: i.string().indexed(),
      entityId: i.string().indexed(),
      seq: i.number().indexed(),
      clientId: i.string().indexed(),
      descriptor: i.string().indexed(),
      sentAtMs: i.number().indexed(),
      localAckAtMs: i.number(),
      observedAtMs: i.number(),
      rttMs: i.number(),
      payloadBytes: i.number(),
      metaJSON: i.string(),
    }),
  },
  links: {
    documentChapters: {
      forward: {
        on: "chapters",
        has: "one",
        label: "document",
        onDelete: "cascade",
      },
      reverse: {
        on: "documents",
        has: "many",
        label: "chapters",
      },
    },
    chapterBlocks: {
      forward: {
        on: "blocks",
        has: "one",
        label: "chapter",
        onDelete: "cascade",
      },
      reverse: {
        on: "chapters",
        has: "many",
        label: "blocks",
      },
    },
    blockAnnotations: {
      forward: {
        on: "annotations",
        has: "one",
        label: "block",
        onDelete: "cascade",
      },
      reverse: {
        on: "blocks",
        has: "many",
        label: "annotations",
      },
    },
  },
});

export type ExerciseGymSchema = typeof exerciseGemSchema;
