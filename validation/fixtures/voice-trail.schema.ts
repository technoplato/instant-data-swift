import { i } from "@instantdb/core";

export const voiceTrailSchema = i.schema({
  entities: {
    "$users": i.entity({
      email: i.string().optional().indexed().unique(),
    }),
    v3_capture_attachments: i.entity({
      contents: i.string(),
      kind: i.string().indexed(),
      offsetMilliseconds: i.number().indexed(),
    }),
    v3_capture_recordings: i.entity({
      deviceID: i.string().indexed(),
      durationMilliseconds: i.number().indexed(),
      state: i.string().indexed(),
      title: i.string().indexed(),
    }),
    v3_capture_transcriptions: i.entity({
      state: i.string().indexed(),
    }),
    v3_share_memberships: i.entity({
      acceptedAt: i.date().indexed(),
      revokedAt: i.date().optional().indexed(),
      role: i.string().indexed(),
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
    v3_capture_attachmentsRecording: {
      forward: {
        on: "v3_capture_attachments",
        has: "one",
        label: "recording",
        required: true,
        onDelete: "cascade",
      },
      reverse: {
        on: "v3_capture_recordings",
        has: "many",
        label: "attachments",
      },
    },
    v3_capture_recordingsOwner: {
      forward: {
        on: "v3_capture_recordings",
        has: "one",
        label: "owner",
        required: true,
      },
      reverse: {
        on: "$users",
        has: "many",
        label: "recordings",
      },
    },
    v3_capture_recordingsReaders: {
      forward: {
        on: "v3_capture_recordings",
        has: "many",
        label: "readers",
      },
      reverse: {
        on: "$users",
        has: "many",
        label: "readableRecordings",
      },
    },
    v3_capture_recordingsWriters: {
      forward: {
        on: "v3_capture_recordings",
        has: "many",
        label: "writers",
      },
      reverse: {
        on: "$users",
        has: "many",
        label: "writableRecordings",
      },
    },
    v3_capture_transcriptionsRecording: {
      forward: {
        on: "v3_capture_transcriptions",
        has: "one",
        label: "recording",
        required: true,
        onDelete: "cascade",
      },
      reverse: {
        on: "v3_capture_recordings",
        has: "many",
        label: "transcriptions",
      },
    },
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
        on: "v3_capture_recordings",
        has: "one",
        label: "share",
      },
    },
  },
  rooms: {
    "recording.playback": {
      presence: i.entity({
        displayName: i.string(),
        focusedSegmentID: i.string().optional(),
        isPlaying: i.boolean(),
        offsetSeconds: i.number(),
        userID: i.string(),
      }),
      topics: {
        commentCommitted: i.entity({
          commentID: i.string(),
        }),
        commentDraft: i.entity({
          offsetSeconds: i.number(),
          text: i.string(),
        }),
        reaction: i.entity({
          emoji: i.string(),
          offsetSeconds: i.number(),
        }),
      },
    },
  },
});

export type AppSchema = typeof voiceTrailSchema;

export default voiceTrailSchema;
