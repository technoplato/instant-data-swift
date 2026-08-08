// Instant schema for exercise-gem (mirrors schema.ts for instant-cli push)
import { i } from "@instantdb/core";

const _schema = i.schema({
  entities: {
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

// This helps TypeScript display better intellisense
type _AppSchema = typeof _schema;
interface AppSchema extends _AppSchema {}
const schema: AppSchema = _schema;

export type { AppSchema };
export default schema;
