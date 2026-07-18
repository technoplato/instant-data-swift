import { i } from "@instantdb/core";

const schema = i.schema({
  entities: {
    "$users": i.entity({
      email: i.string().optional().indexed().unique(),
    }),
    v3_share_memberships: i.entity({
      acceptedAt: i.date().indexed(),
      revokedAt: i.date().optional().indexed(),
      role: i.string().indexed(),
    }),
    v3_shared_lists: i.entity({
      title: i.string().indexed(),
      value: i.number().indexed(),
    }),
    v3_shares: i.entity({
      createdAt: i.date().indexed(),
      revokedAt: i.date().optional().indexed(),
      rootID: i.string().indexed(),
      rootNamespace: i.string().indexed(),
      token: i.string().indexed().unique(),
      updatedAt: i.date().indexed(),
    }),
  },
  links: {
    v3_share_membershipsShare: {
      forward: {
        on: "v3_share_memberships",
        has: "one",
        label: "share",
        required: true,
        onDelete: "cascade",
      },
      reverse: {
        on: "v3_shares",
        has: "many",
        label: "memberships",
      },
    },
    v3_share_membershipsUser: {
      forward: {
        on: "v3_share_memberships",
        has: "one",
        label: "user",
        required: true,
      },
      reverse: {
        on: "$users",
        has: "many",
        label: "shareMemberships",
      },
    },
    v3_shared_listsOwner: {
      forward: {
        on: "v3_shared_lists",
        has: "one",
        label: "owner",
        required: true,
      },
      reverse: {
        on: "$users",
        has: "many",
        label: "ownedSharedLists",
      },
    },
    v3_shared_listsReaders: {
      forward: {
        on: "v3_shared_lists",
        has: "many",
        label: "readers",
      },
      reverse: {
        on: "$users",
        has: "many",
        label: "readableSharedLists",
      },
    },
    v3_shared_listsWriters: {
      forward: {
        on: "v3_shared_lists",
        has: "many",
        label: "writers",
      },
      reverse: {
        on: "$users",
        has: "many",
        label: "writableSharedLists",
      },
    },
    v3_sharesOwner: {
      forward: {
        on: "v3_shares",
        has: "one",
        label: "owner",
        required: true,
      },
      reverse: {
        on: "$users",
        has: "many",
        label: "ownedShares",
      },
    },
    v3_sharesRoot: {
      forward: {
        on: "v3_shares",
        has: "one",
        label: "root",
        required: true,
      },
      reverse: {
        on: "v3_shared_lists",
        has: "one",
        label: "share",
      },
    },
  },
});

export type AppSchema = typeof schema;

export default schema;
