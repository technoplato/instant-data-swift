// Captured from the ephemeral Instant app after pushing the Swift-generated
// `recording-action` permissions on July 18, 2026.
//
// Namespace and action ordering is server-owned; semantic verification parses
// the rules before comparing them with the Swift contract.

// Docs: https://www.instantdb.com/docs/permissions

import type { InstantRules } from "@instantdb/core";

const rules = {
  v3_capture_members: {
    allow: {
      view: "true",
      create: "true",
      delete: "true",
      update: "true",
    },
  },
  v3_capture_recordings: {
    allow: {
      view: "true",
      create: "true",
      delete: "true",
      update: "true",
    },
  },
  v3_capture_attachments: {
    allow: {
      view: "true",
      create: "true",
      delete: "true",
      update: "true",
    },
  },
  v3_capture_transcriptions: {
    allow: {
      view: "true",
      create: "true",
      delete: "true",
      update: "true",
    },
  },
} satisfies InstantRules;

export default rules;
