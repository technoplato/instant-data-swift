// Ephemeral Instant schema for #156 open-segment 20s network bench.
// Words are a JSON string on the open segment (not word entities).

import { i } from "@instantdb/core";

const _schema = i.schema({
  entities: {
    recordings: i.entity({
      title: i.string().indexed(),
      updatedAtMs: i.number().indexed(),
    }),
    transcriptionSegments: i.entity({
      recordingID: i.string().indexed(),
      text: i.string(),
      wordsJSON: i.string(),
      wordCount: i.number().indexed(),
      seq: i.number().indexed(),
      updatedAtMs: i.number().indexed(),
    }),
  },
  links: {
    segmentRecording: {
      forward: {
        on: "transcriptionSegments",
        has: "one",
        label: "recording",
        required: true,
        onDelete: "cascade",
      },
      reverse: {
        on: "recordings",
        has: "many",
        label: "segments",
      },
    },
  },
});

type _AppSchema = typeof _schema;
interface AppSchema extends _AppSchema {}
const schema: AppSchema = _schema;

export type { AppSchema };
export default schema;
