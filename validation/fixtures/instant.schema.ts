import { i } from "@instantdb/core";

const _schema = i.schema({
  entities: {
    profiles: i.entity({
      handle: i.string().unique().indexed(),
      displayName: i.string(),
      createdAt: i.number().indexed(),
    }),
    posts: i.entity({
      content: i.string(),
      createdAt: i.number().indexed(),
    }),
  },
  links: {
    postAuthor: {
      forward: { on: "posts", has: "one", label: "author" },
      reverse: { on: "profiles", has: "many", label: "posts" },
    },
  },
  rooms: {
    validation: {
      presence: i.entity({
        name: i.string(),
        cursorX: i.number().optional(),
        cursorY: i.number().optional(),
      }),
      topics: {
        ping: i.entity({
          message: i.string(),
          sentAt: i.number(),
        }),
      },
    },
  },
});

type _AppSchema = typeof _schema;
interface AppSchema extends _AppSchema {}
const schema: AppSchema = _schema;

export type { AppSchema };
export default schema;

