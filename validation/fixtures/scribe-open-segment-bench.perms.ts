// Open permissions for ephemeral #156 bench apps (never push to production).

import type { InstantRules } from "@instantdb/core";

const rules = {
  recordings: {
    allow: {
      view: "true",
      create: "true",
      update: "true",
      delete: "true",
    },
  },
  transcriptionSegments: {
    allow: {
      view: "true",
      create: "true",
      update: "true",
      delete: "true",
    },
  },
} satisfies InstantRules;

export default rules;
